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
# Usage:
#   scripts/ab-setcell.sh E1
#   WINNERS="E1,E3" scripts/ab-setcell.sh E5
#   scripts/ab-setcell.sh base          # restore baseline before a re-run
# =====================================================================
set -Eeuo pipefail

CELL="${1:?usage: ab-setcell.sh base|E0|E1|E2|E3|E4|E5}"
cd "$(dirname "$0")/.." || exit 1

CONF="cluster-profiles.d/deepseek-tune.conf"
BASE="cluster-profiles.d/deepseek-tune.conf.base"

die(){ echo "ab-setcell: FAIL: $*" >&2; exit 1; }
[ -f "$BASE" ] || die "missing ${BASE} (pristine baseline copy)"

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

apply_key(){
  case "$1" in
    E1|capture|CUDAGRAPH_CAPTURE) k_capture ;;
    E2|prob|probabilistic)        k_prob ;;
    E3|prefix)                    k_prefix ;;
    E4|breakable|compile)         k_breakable ;;
    *) die "unknown cell/key: $1" ;;
  esac
}

# ---- dispatch -------------------------------------------------------
case "$CELL" in
  base|E0|E0-baseline) : ;;                    # baseline only
  E1|E2|E3|E4)         apply_key "$CELL" ;;
  E5)
      W="${WINNERS:-}"
      [ -n "$W" ] || die "E5 requires WINNERS=<comma list>, e.g. WINNERS=E1,E3"
      for k in ${W//,/ }; do apply_key "$k"; done
      ;;
  *) die "unknown cell: ${CELL}" ;;
esac

# ---- validate + report ---------------------------------------------
bash -n "$CONF" || die "profile syntax error after edit"

echo "--- ab-setcell ${CELL}: applied knobs ---"
grep -nE '^(CUDAGRAPH_CAPTURE|ENABLE_PREFIX_CACHING|SPEC_CONFIG|CMD_WRAPPER|SYNC_DIRS)|VLLM_USE_BREAKABLE_CUDAGRAPH|VLLM_PREFIX_CACHE_RETENTION_INTERVAL|dspark-patches' \
  "$CONF" | sed 's/^/  /'

echo "--- diff vs baseline (${BASE}) ---"
diff -u "$BASE" "$CONF" | sed 's/^/  /' || true

echo "ab-setcell: ${CELL} OK  conf_sha256=$(sha256sum "$CONF" | cut -c1-16)"
