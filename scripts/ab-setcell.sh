#!/usr/bin/env bash
# =====================================================================
# ab-setcell.sh <cell>
#
# Reset cluster-profiles.d/deepseek-tune.conf to the pristine E0 baseline
# (deepseek-tune.conf.base), then apply EXACTLY the knob set for <cell>.
# Starting every cell from the same base is what makes the cells isolatable:
# a cell never inherits the previous cell's edit.
#
#   base | E0     baseline — byte-identical argv to deepseek.conf
#   E1            CUDAGRAPH_CAPTURE 8 -> 128
#   E2            draft_sample_method greedy -> probabilistic (k=7 kept)
#   E3            prefix caching ON + dspark-swa-prefix hotfix + retention
#   E4            VLLM_USE_BREAKABLE_CUDAGRAPH=0 (put inductor/compile back)
#   E5            winners combined: WINNERS="E1,E3" (aliases: capture, prob,
#                 prefix, breakable)
#
# After applying it prints the resulting knob block and a unified diff vs the
# baseline so the cell's edit is auditable in the log. `bash -n` gates syntax.
#
# DeepSeek-vision lane (2026-10-07, V-cells) — same machine, same image
# ghcr.io/anemll/dspark-vllm-gx10:0.1.1, but a different profile. The E1..E4
# anchors above are mainline anchors and DO NOT match deepseek-vision.conf
# (it already runs capture=56, probabilistic, prefix caching on, breakable=0),
# so vision gets its own key set:
#   V0           vision baseline — byte-identical argv to deepseek-vision.conf
#   V1           drop VLLM_USE_BREAKABLE_CUDAGRAPH=0   (mainline E4 = -1.5 %)
#   V2           --block-size 256 -> $V2_BLOCK         (default 128)
#   V3           --long-prefill-token-threshold -> $V3_THR (default 0, off)
#   V4           CUDAGRAPH_CAPTURE 56 -> $V4_CAP       (default 8)
#   V5           num_speculative_tokens 6 -> $V5_K     (default 9; also keeps
#                MTP_NUM_TOKENS in step — one logical knob, the draft depth)
#   V-win        winners combined: WINNERS="V1,V2"
#
# Point it at a different lane with AB_CONF / AB_BASE (both must be given
# together or both defaulted):
#   AB_CONF=cluster-profiles.d/deepseek-vision-tune.conf \
#   AB_BASE=cluster-profiles.d/deepseek-vision-tune.conf.base \
#   scripts/ab-setcell.sh V1
#
# Usage:
#   scripts/ab-setcell.sh E1
#   WINNERS="E1,E3" scripts/ab-setcell.sh E5
#   scripts/ab-setcell.sh base          # restore baseline before a re-run
# =====================================================================
set -Eeuo pipefail

CELL="${1:?usage: ab-setcell.sh base|E0|E1|E2|E3|E4|E5|V0|V1|V2|V3|V4|V5}"
cd "$(dirname "$0")/.." || exit 1

# Default to the mainline experiment lane; a vision run overrides both.
CONF="${AB_CONF:-cluster-profiles.d/deepseek-tune.conf}"
BASE="${AB_BASE:-cluster-profiles.d/deepseek-tune.conf.base}"

die(){ echo "ab-setcell: FAIL: $*" >&2; exit 1; }
[ -f "$BASE" ] || die "missing ${BASE} (pristine baseline copy)"

# A V-cell without an explicit target is ALWAYS a mistake: the default above is
# the mainline lane, so a bare `ab-setcell.sh V0` reports success against
# deepseek-tune.conf while leaving the vision conf holding the previous cell's
# edit. That is exactly what happened on 2026-10-07 — a bare V0 restore after
# the failed V2 printed `V0 OK conf_sha256=e0c1f265` (the mainline sha) while
# deepseek-vision-tune.conf silently stayed at block-size 128
# (sha 148a3f13). Refuse rather than lie about which file was touched.
case "$CELL" in
  V*)
    if [ -z "${AB_CONF:-}" ] || [ -z "${AB_BASE:-}" ]; then
      die "V-cell '${CELL}' needs an explicit target (the default is the mainline deepseek-tune lane):
  AB_CONF=cluster-profiles.d/<lane>.conf AB_BASE=cluster-profiles.d/<lane>.conf.base scripts/ab-setcell.sh ${CELL}"
    fi
    ;;
esac

cp -f "$BASE" "$CONF"

req(){ grep -qFx -- "$1" "$CONF" || die "anchor missing: [$1]"; }

# exact full-line replacement
repl(){
  req "$1"
  local n; n="$(grep -nFx -- "$1" "$CONF" | head -1 | cut -d: -f1)"
  sed -i "${n}s|.*|${2}|" "$CONF"
  grep -qFx -- "$2" "$CONF" || die "replace failed: [$2]"
}

# insert one line after an exact anchor line
ins_after(){
  req "$1"
  awk -v a="$1" -v t="$2" '{print} $0==a{print t}' "$CONF" >"$CONF.tmp"
  mv "$CONF.tmp" "$CONF"
  grep -qFx -- "$2" "$CONF" || die "insert failed: [$2]"
}

# insert one line before an exact anchor line
ins_before(){
  req "$1"
  awk -v a="$1" -v t="$2" '$0==a{print t} {print}' "$CONF" >"$CONF.tmp"
  mv "$CONF.tmp" "$CONF"
  grep -qFx -- "$2" "$CONF" || die "insert failed: [$2]"
}

# delete every line exactly equal to the anchor (vision V1 uses this to drop
# a line that is already present in the baseline)
delline(){
  req "$1"
  grep -vFx -- "$1" "$CONF" >"$CONF.tmp"
  mv "$CONF.tmp" "$CONF"
  if grep -qFx -- "$1" "$CONF"; then die "delete failed: [$1]"; fi
}

# ---- knob functions -------------------------------------------------
k_capture(){                      # E1
  repl 'CUDAGRAPH_CAPTURE="8"' 'CUDAGRAPH_CAPTURE="128"'
}

k_prob(){                         # E2
  local n
  n="$(grep -n '^SPEC_CONFIG=' "$CONF" | head -1 | cut -d: -f1)"
  [ -n "$n" ] || die "SPEC_CONFIG missing"
  sed -i "${n}s|draft_sample_method\":\"greedy|draft_sample_method\":\"probabilistic|" "$CONF"
  grep -qF 'draft_sample_method":"probabilistic"' "$CONF" || die "probabilistic replace failed"
  grep -qF '"num_speculative_tokens":7' "$CONF" || die "k=7 was not preserved"
}

k_prefix(){                       # E3
  repl 'ENABLE_PREFIX_CACHING="false"' 'ENABLE_PREFIX_CACHING="true"'
  ins_after '  VLLM_MEMORY_PROFILER_ESTIMATE_CUDAGRAPHS=0' \
            '  VLLM_PREFIX_CACHE_RETENTION_INTERVAL=4096'
  ins_before 'EXTRA_ARGS=(' \
    "CMD_WRAPPER='python3 /opt/dspark-patches/hotfix-vllm-dspark-swa-prefix.py || exit 1'"
  ins_after '  -v "${HOME}/.cache/vllm-deepseek:/cache/vllm"' \
            '  -v "${STACK_DIR}/patches:/opt/dspark-patches:ro"'
  printf '%s\n' '' \
    '# E3: stage the SWA-prefix hotfix dir on BOTH nodes (cluster-up hook).' \
    'SYNC_DIRS=(' \
    '  "${REPO_DIR}/patches/dspark-vision:${STACK_DIR}/patches"' \
    ')' >>"$CONF"
}

k_breakable(){                    # E4
  ins_after '  VLLM_MEMORY_PROFILER_ESTIMATE_CUDAGRAPHS=0' \
            '  VLLM_USE_BREAKABLE_CUDAGRAPH=0'
}

# ---- vision (V) knob functions ---------------------------------------
# Each V-cell starts from the pristine vision baseline, so every function
# asserts the baseline line it expects to find rather than silently no-op.

v_breakable(){                    # V1
  delline '  VLLM_USE_BREAKABLE_CUDAGRAPH=0'
}

v_blocksize(){                    # V2
  local b="${V2_BLOCK:-128}"
  repl '  --block-size 256' "  --block-size ${b}"
}

v_prefillthresh(){                # V3
  local t="${V3_THR:-0}"
  repl '  --long-prefill-token-threshold 1024' "  --long-prefill-token-threshold ${t}"
}

v_capture(){                      # V4
  local c="${V4_CAP:-8}"
  # The baseline line carries a trailing comment, so match the assignment by
  # prefix rather than the whole line, and rewrite it with the baseline value
  # noted in-line so the cell's diff stays self-explanatory.
  local n
  n="$(grep -n '^CUDAGRAPH_CAPTURE=' "$CONF" | head -1 | cut -d: -f1)"
  [ -n "$n" ] || die "CUDAGRAPH_CAPTURE missing"
  sed -i "${n}s|.*|CUDAGRAPH_CAPTURE=\"${c}\"                     # V4 cell (V0 baseline: miaai formula seqs*(k+1)=8*7=56)|" "$CONF"
  grep -q "^CUDAGRAPH_CAPTURE=\"${c}\"" "$CONF" || die "capture replace failed"
}

v_k(){                            # V5: draft depth
  local k="${V5_K:-9}"            # ONE logical knob: the spec-config JSON and
  # the env that mirrors it move together (baseline comment: k must be
  # >= dspark_block_size 5 and a multiple of n_predict 3).
  (( k % 3 == 0 && k >= 5 )) \
    || die "V5: k=${k} illegal - must be >=5 and a multiple of n_predict=3"
  repl "SPEC_CONFIG='{\"method\":\"dspark\",\"num_speculative_tokens\":6,\"draft_sample_method\":\"probabilistic\"}'" \
       "SPEC_CONFIG='{\"method\":\"dspark\",\"num_speculative_tokens\":${k},\"draft_sample_method\":\"probabilistic\"}'"
  repl '  MTP_NUM_TOKENS=6' "  MTP_NUM_TOKENS=${k}"
}

apply_key(){
  case "$1" in
    E1|capture|CUDAGRAPH_CAPTURE) k_capture ;;
    E2|prob|probabilistic)        k_prob ;;
    E3|prefix)                    k_prefix ;;
    E4|breakable|compile)         k_breakable ;;
    V1|vbreakable)                v_breakable ;;
    V2|vblock)                    v_blocksize ;;
    V3|vthr)                      v_prefillthresh ;;
    V4|vcap)                      v_capture ;;
    V5|vk)                        v_k ;;
    *) die "unknown cell/key: $1" ;;
  esac
}

# ---- dispatch -------------------------------------------------------
case "$CELL" in
  base|E0|E0-baseline|V0)  : ;;                 # baseline only
  E1|E2|E3|E4)             apply_key "$CELL" ;;
  E5)
      W="${WINNERS:-}"
      [ -n "$W" ] || die "E5 requires WINNERS=<comma list>, e.g. WINNERS=E1,E3"
      for k in ${W//,/ }; do apply_key "$k"; done
      ;;
  V1|V2|V3|V4|V5)          apply_key "$CELL" ;;
  V-win)
      W="${WINNERS:-}"
      [ -n "$W" ] || die "V-win requires WINNERS=<comma list>, e.g. WINNERS=V1,V3"
      for k in ${W//,/ }; do apply_key "$k"; done
      ;;
  *) die "unknown cell: ${CELL}" ;;
esac

# ---- validate + report ---------------------------------------------
bash -n "$CONF" || die "profile syntax error after edit"

echo "--- ab-setcell ${CELL}: applied knobs (target ${CONF}) ---"
grep -nE '^(CUDAGRAPH_CAPTURE|ENABLE_PREFIX_CACHING|SPEC_CONFIG|CMD_WRAPPER|SYNC_DIRS)|VLLM_USE_BREAKABLE_CUDAGRAPH|VLLM_PREFIX_CACHE_RETENTION_INTERVAL|dspark-patches|--block-size|--long-prefill-token-threshold|MTP_NUM_TOKENS' \
  "$CONF" | sed 's/^/  /'

echo "--- diff vs baseline (${BASE}) ---"
diff -u "$BASE" "$CONF" | sed 's/^/  /' || true

echo "ab-setcell: ${CELL} OK  conf_sha256=$(sha256sum "$CONF" | cut -c1-16)"
