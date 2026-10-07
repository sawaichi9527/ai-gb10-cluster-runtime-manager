#!/usr/bin/env bash
# =====================================================================
# bench-ab-deepseek.sh <label> [profile]
#
# A/B measurement suite for the DeepSeek V4 Flash 0731 TP2 lane
# (deepseek mainline + the deepseek-tune experiment lane).
#
# Usage — one invocation per A/B cell:
#   1. edit cluster-profiles.d/deepseek-tune.conf (ONE knob)
#   2. gb10 use deepseek-tune     # cold start ~7-15 min
#   3. gb10 wait deepseek-tune && scripts/cluster-compose-verify deepseek-tune
#   4. scripts/bench-ab-deepseek.sh <label>
# Run with the SAME label convention per cell so the files line up:
#   scripts/bench-ab-deepseek.sh E0
#
# What it measures (all byte-identical across cells)
#   decode : BENCH_IGNORE_EOS=1 (exactly 400 tok/stream), C=1..8,
#            THREE runs each — acceptance swings hard between runs, a single
#            run is noise, so report medians (bench-ab.sh precedent).
#   prefill: BENCH_COLD=1 at 32K / 131K / 200K words. BENCH_COLD is always on
#            so the cells that turn prefix caching ON do not get a free ride;
#            with caching off the nonce only adds one line, so the numbers stay
#            comparable to the 2026-09-20 baseline.
#   diag   : engine-reported cudagraph_capture_sizes / KV pool / graph-capture
#            cost, pulled from the live container — this is how a cell proves
#            its knob actually took effect (E1 is a no-op otherwise).
#   cache  : 3x repeat of one fixed prompt, completions compared byte-wise.
#            Guards the prefix-caching cell: a degenerate DSpark draft on a
#            cache hit shows up as a truncated/changed completion.
#
# Reference file for the delta table: AB_REF=<label> (default E0). The vision
# lane runs AB_REF=V0 so its cells are never compared against a mainline file.
#   scripts/bench-ab-deepseek.sh V1 deepseek-vision-tune   AB_REF=V0
#
# Output: stdout and /tmp/ab-<label>.txt. Every line is self-describing
# (`decode C=4 run=2 ...`, `prefill w=131000 ...`) so two files can be diffed
# or pasted straight into a table.
#
# NOTE: decode deltas below ~10% are noise (no warm-up round, and the target
# forward is not bit-reproducible — vllm-project/vllm#53436). Compare medians.
# =====================================================================
set -Eeuo pipefail

LABEL="${1:?usage: bench-ab-deepseek.sh <label> [profile]}"
PROFILE="${2:-deepseek-tune}"
# Baseline label the delta table compares against. The vision lane sets V0 so
# its cells never pick up a mainline reference file.
AB_REF="${AB_REF:-E0}"
cd "$(dirname "$0")/.." || exit 1
# shellcheck disable=SC1091
source scripts/cluster-common.sh

OUT="/tmp/ab-${LABEL}.txt"
: >"$OUT"

emit(){ printf '%s\n' "$*" | tee -a "$OUT"; }
# Loud abort: set -e on its own kills the script with NO output when a
# subshell fails, which is exactly how the POS6 bug below hid for a whole
# campaign. Always say what broke before exiting.
fail(){ emit "FATAL: $*"; exit 1; }

# --- readiness -------------------------------------------------------
if ! curl -fsS -m 5 "http://localhost:${API_PORT}/health" >/dev/null 2>&1; then
  emit "ABORT: API not healthy on :${API_PORT} (boot first: gb10 wait ${PROFILE})"
  exit 1
fi

# Auth: build the header as an ARRAY so it word-splits correctly.
CURL_AUTH=()
if [[ -n "${VLLM_API_KEY:-}" && "${VLLM_API_KEY}" != "EMPTY" ]]; then
  CURL_AUTH=(-H "Authorization: Bearer ${VLLM_API_KEY}")
fi

# --- engine diag (proves the knob took effect) -----------------------
emit_diag(){
  local d
  d="$(sdk docker logs cluster-node0 2>&1 || true)"
  emit "--- engine diag (${PROFILE}) ---"
  { echo "$d" | grep -oE "'cudagraph_capture_sizes': \[[^]]*\]|'max_cudagraph_capture_size': [0-9]+"
  } | sort -u | sed 's/^/  /' | tee -a "$OUT" || emit "  (capture sizes not found in engine log)"
  { echo "$d" | grep -E "Available KV cache memory|Graph capturing finished|Model loading took|Using nvfp4_ds_mla data type"
  } | sed -E 's/^[A-Za-z_0-9]+ pid=[0-9]+ //' | sort -u | sed 's/^/  /' | tee -a "$OUT" || true
  # proof-of-effect: the engine's own config dump / server_args echo. Loose
  # pattern so JSON, repr and argv forms all match; sorted -u trims the noise.
  # A cell that failed to change anything shows the E0 value here and is void.
  { echo "$d" | grep -oiE "(draft_sample_method|num_speculative_tokens|enable_prefix_caching|max_num_seqs|block_size|long_prefill_token_threshold)[^,}{]{0,60}"
  } | sort -u | sed 's/^/  cfg /' | tee -a "$OUT" || emit "  (engine config dump not found)"
  # Authoritative proof-of-effect: the argv the live container is actually
  # running. Log formats vary per image and several knobs (--block-size,
  # --long-prefill-token-threshold) never appear in the engine dump at all,
  # so a cell with no log evidence would otherwise be unverifiable.
  local argv lenv
  argv="$(sdk docker inspect cluster-node0 \
            --format '{{range .Config.Entrypoint}}{{printf "%s " .}}{{end}}{{range .Config.Cmd}}{{printf "%s " .}}{{end}}' \
            2>/dev/null || true)"
  # A sh -c style Cmd carries the whole vLLM command (and its newlines) in one
  # element; flatten so the line-oriented greps below can see every flag.
  argv="$(printf '%s' "$argv" | tr '\n' ' ')"
  lenv="$(sdk docker inspect cluster-node0 \
            --format '{{range .Config.Env}}{{printf "%s\n" .}}{{end}}' 2>/dev/null || true)"
  if [[ -n "$argv" ]]; then
    local k v
    for k in block-size long-prefill-token-threshold max-cudagraph-capture-size reasoning-parser served-model-name; do
      v="$(printf ' %s' "$argv" | grep -oE -- " --${k} [^ ]+" | head -1)"
      [[ -n "$v" ]] && { printf '  argv%s\n' "$v" | tee -a "$OUT"; } || true
    done
    printf ' %s' "$argv" | grep -oE -- '--speculative-config [^ ]+' | head -1 \
      | sed 's/^/  argv /' | tee -a "$OUT" || true
    if printf ' %s' "$argv" | grep -qE -- '--enable-prefix-caching'; then
      echo "  argv --enable-prefix-caching" | tee -a "$OUT"
    elif printf ' %s' "$argv" | grep -qE -- '--no-enable-prefix-caching'; then
      echo "  argv --no-enable-prefix-caching" | tee -a "$OUT"
    fi
  else
    emit "  (docker inspect argv unavailable - proof skipped)"
  fi
  # VLLM_USE_BREAKABLE_CUDAGRAPH is an env var, not argv — proof it from the
  # container env, never from Config.Cmd (it can never appear there).
  if [[ -n "$lenv" ]]; then
    if printf '%s\n' "$lenv" | grep -q '^VLLM_USE_BREAKABLE_CUDAGRAPH='; then
      printf '  env %s\n' "$(printf '%s\n' "$lenv" | grep '^VLLM_USE_BREAKABLE_CUDAGRAPH=' | head -1)" | tee -a "$OUT"
    else
      echo "  env VLLM_USE_BREAKABLE_CUDAGRAPH not set" | tee -a "$OUT"
    fi
    if printf '%s\n' "$lenv" | grep -q '^VLLM_PREFIX_CACHE_RETENTION_INTERVAL='; then
      printf '  env %s\n' "$(printf '%s\n' "$lenv" | grep '^VLLM_PREFIX_CACHE_RETENTION_INTERVAL=' | head -1)" | tee -a "$OUT"
    fi
  fi
  if echo "$d" | grep -q "Auto-enabling VLLM_USE_BREAKABLE_CUDAGRAPH"; then
    emit "  breakable_cudagraph=ON (=> inductor/torch.compile DISABLED)"
  else
    emit "  breakable_cudagraph=auto-enable warning ABSENT (=> inductor ON)"
  fi
  emit "  jit_spike_lines=$(echo "$d" | grep -c 'JIT compilation during inference' || true)"
}

# --- prefix-cache correctness (3x identical prompt) ------------------
emit_cachecheck(){
  local i prev="" same=0 bad=0 body
  emit "--- prefix-cache repeat check (3x identical prompt) ---"
  for i in 1 2 3; do
    body=$(curl -fsS -m 180 "${CURL_AUTH[@]}" \
      -H 'Content-Type: application/json' \
      -d '{"model":"aeon","messages":[{"role":"user","content":"Reply with exactly: HELLO-TP2-OK"}],"max_tokens":500,"temperature":0}' \
      "http://localhost:${API_PORT}/v1/chat/completions" \
      | jq -r '.choices[0].message.content // "ERR"') || body="ERR"
    if [[ -z "$body" || "$body" == "ERR" ]]; then bad=1; fi
    if [[ -n "$prev" && "$body" == "$prev" ]]; then same=$((same+1)); fi
    prev="$body"
    emit "  run${i}: len=${#body} exact=${body}"
  done
  if (( bad )); then emit "  verdict: FAIL (empty/error response)"; else
    emit "  verdict: ok (identical=${same}/2, no empty responses)"; fi
}

# --- median/mean of the 3 runs per C ---------------------------------
summarize(){
  local c vals med mean acc
  emit "--- summary (median / mean of 3 runs) ---"
  printf '%-6s %-10s %-10s %-10s\n' C med_tok/s mean_tok/s accept% | tee -a "$OUT"
  for c in 1 2 3 4 5 6 7 8; do
    vals=$(grep "^decode C=${c} run=" "$OUT" | sed -n 's/.*C_total=\([0-9.]*\).*/\1/p')
    [[ -n "$vals" ]] || { emit "  C=${c}: NO DATA"; continue; }
    med=$(echo "$vals" | sort -n | awk '{a[NR]=$1} END{printf "%.1f", a[int((NR+1)/2)]}')
    mean=$(echo "$vals" | awk '{s+=$1;n++} END{printf "%.1f", s/n}')
    acc=$(grep "^decode C=${c} run=" "$OUT" | sed -n 's/.*draft tokens = \([0-9.]*\)%.*/\1/p' | sort -n | awk '{a[NR]=$1} END{if(NR)printf "%.1f", a[int((NR+1)/2)]}')
    printf '%-6s %-10s %-10s %-10s\n' "$c" "$med" "$mean" "${acc:-n/a}" | tee -a "$OUT"
  done
}

# --- side-by-side vs the AB_REF baseline -------------------------------
# Decode deltas under ~10% are noise; print them anyway so a trend across
# cells is visible without re-opening two files.
medof(){ # <file> <C> -> median C_total of the 3 runs
  grep "^decode C=$2 run=" "$1" 2>/dev/null | sed -n 's/.*C_total=\([0-9.]*\).*/\1/p' \
    | sort -n | awk '{a[NR]=$1} END{if(NR)printf "%.1f", a[int((NR+1)/2)]}'
}
prefof(){ # <file> <w> -> prefill speed
  grep "^prefill w=$2 " "$1" 2>/dev/null | sed -n 's/.*prefill_speed = \([0-9.]*\) .*/\1/p' | head -1
}

compare_e0(){
  local ref="/tmp/ab-${AB_REF}.txt" c m0 m1 d
  [[ "$LABEL" == "$AB_REF" ]] && return 0
  if [[ ! -s "$ref" ]]; then emit "--- delta vs ${AB_REF}: SKIP (no ${ref}) ---"; return 0; fi
  emit "--- delta vs ${AB_REF} (decode, median of 3) ---"
  printf '%-6s %-9s %-9s %-9s %-9s %-9s %-9s\n' C "${AB_REF}_t/s" this_t/s d_tps% "${AB_REF}_acc" this_acc d_acc_pp | tee -a "$OUT"
  for c in 1 2 3 4 5 6 7 8; do
    m0="$(medof "$ref" "$c")"; m1="$(medof "$OUT" "$c")"
    if [[ -z "$m0" || -z "$m1" ]]; then emit "  C=$c: missing data"; continue; fi
    d="$(awk -v a="$m0" -v b="$m1" 'BEGIN{printf "%+.1f", (b-a)/a*100}')"
    local a0 a1 dap
    a0="$(grep "^decode C=${c} run=" "$ref"  | sed -n 's/.*draft tokens = \([0-9.]*\)%.*/\1/p' | sort -n | awk '{a[NR]=$1} END{if(NR)printf "%.1f", a[int((NR+1)/2)]}')"
    a1="$(grep "^decode C=${c} run=" "$OUT"  | sed -n 's/.*draft tokens = \([0-9.]*\)%.*/\1/p' | sort -n | awk '{a[NR]=$1} END{if(NR)printf "%.1f", a[int((NR+1)/2)]}')"
    dap="$(awk -v a="${a0:-0}" -v b="${a1:-0}" 'BEGIN{printf "%+.1f", b-a}')"
    printf '%-6s %-9s %-9s %-9s %-9s %-9s %-9s\n' "$c" "$m0" "$m1" "${d}%" "${a0:-n/a}" "${a1:-n/a}" "${dap}pp" | tee -a "$OUT"
  done
  emit "--- delta vs ${AB_REF} (cold prefill tok/s) ---"
  for w in 32000 131000 200000; do
    m0="$(prefof "$ref" "$w")"; m1="$(prefof "$OUT" "$w")"
    if [[ -z "$m0" || -z "$m1" ]]; then emit "  w=$w: missing data"; continue; fi
    d="$(awk -v a="$m0" -v b="$m1" 'BEGIN{printf "%+.1f", (b-a)/a*100}')"
    emit "  w=$w  ${AB_REF}=${m0}  this=${m1}  ${d}%"
  done
  emit "  (* d_tps% = relative tok/s change; d_acc_pp = acceptance percentage points."
  emit "     |d| >10% tok/s or >3pp  => real;  below that => noise.)"
}

emit "=== ${LABEL} start $(date -Is)  profile=${PROFILE} ==="
emit_diag
emit "--- decode fixed-400 (BENCH_IGNORE_EOS=1), 3 runs each, C=1..8 ---"
for c in 1 2 3 4 5 6 7 8; do
  for i in 1 2 3; do
    # Capture the child's output FIRST and test its status, instead of
    # letting `set -e` abort on a failed pipeline whose stderr had already
    # been merged into the substitution and then filtered away by grep.
    rc=0
    raw=$(BENCH_IGNORE_EOS=1 bash scripts/bench-c.sh "$c" 2>&1) || rc=$?
    if (( rc != 0 )); then
      emit "decode C=${c} run=${i}: bench-c FAILED rc=${rc}"
      emit "  raw tail: $(printf '%s\n' "$raw" | tail -15 | tr '\n' ' ' | tr -s ' ')"
      fail "bench-c.sh died for C=${c} — cell aborted; do not read a partial table"
    fi
    r=$(printf '%s\n' "$raw" | grep -E 'aggregate:|acceptance:' | tr -s ' ' | tr '\n' '|')
    emit "decode C=${c} run=${i} ${r}"
  done
done

summarize

emit "--- cold prefill (BENCH_COLD=1) ---"
for w in 32000 131000 200000; do
  rc=0
  raw=$(BENCH_COLD=1 bash scripts/bench-ctx.sh "$w" 2>&1) || rc=$?
  if (( rc != 0 )); then
    emit "prefill w=${w}: bench-ctx FAILED rc=${rc}"
    emit "  raw tail: $(printf '%s\n' "$raw" | tail -15 | tr '\n' ' ' | tr -s ' ')"
    fail "bench-ctx.sh died for w=${w} — cell aborted; do not read a partial table"
  fi
  r=$(printf '%s\n' "$raw" | grep -E 'prompt_tokens|wall_time|prefill_speed' | tr -s ' ' | tr '\n' ' ')
  emit "prefill w=${w} ${r}"
done

emit_cachecheck

compare_e0

emit "DONE ${LABEL} $(date -Is)"
