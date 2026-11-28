#!/usr/bin/env bash
set -Eeuo pipefail
# =====================================================================
# bench-sweep.sh <profile-id> <label> [C ...]
#
# Full decode sweep for the 27b/35b family: C1..C8 x REPS (median per cell)
# + a cold 245K pure-prefill probe. Protocol matches the 2026-10-22 baseline
# so an image bump can be diffed cell by cell:
#   BENCH_IGNORE_EOS=1, 400-token outputs, default sampling, warm server.
#
# Env: REPS=3 (per cell)  MAXT=400  CTX_WORDS=245000  CSKIP=""
# Writes <LOG_BASE>/<profile>/bench-sweep-<label>-<ts>.txt and prints a table.
#
# This is a *measurement* tool: it never boots, stops or changes a profile.
# =====================================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/cluster-common.sh"

P="${1:?usage: bench-sweep.sh <profile> <label> [C ...]}"
LABEL="${2:?usage: bench-sweep.sh <profile> <label> [C ...]}"
shift 2
CS=("$@")
[[ ${#CS[@]} -eq 0 ]] && CS=(1 2 3 4 5 6 7 8)
REPS="${REPS:-3}"
MAXT="${MAXT:-400}"
CTX_WORDS="${CTX_WORDS:-245000}"
PREFILL_RUNS="${PREFILL_RUNS:-2}"

LOG_DIR="${LOG_BASE}/${P}"
mkdir -p "${LOG_DIR}"
OUT="${LOG_DIR}/bench-sweep-${LABEL}-$(date +%Y%m%d-%H%M%S).txt"

median() { sort -n | awk '{a[NR]=$1} END{ if(NR%2) printf "%.1f", a[(NR+1)/2]; else printf "%.1f", (a[NR/2]+a[NR/2+1])/2 }'; }

{
  echo "=================================================================="
  echo "  bench-sweep  profile=${P}  label=${LABEL}  $(date '+%F %T')"
  echo "  protocol: BENCH_IGNORE_EOS=1 max_tokens=${MAXT} reps=${REPS} C=${CS[*]}"
  echo "  host: $(hostname)"
  echo "=================================================================="
} | tee "${OUT}"

declare -A MED
for C in "${CS[@]}"; do
  vals=(); errs=0; acc=""
  for r in $(seq 1 "${REPS}"); do
    raw=$(BENCH_IGNORE_EOS=1 "${SCRIPT_DIR}/bench-c.sh" "${C}" "${MAXT}" 2>&1 || true)
    v=$(echo "${raw}" | grep -o 'C_total=[0-9.]*' | head -1 | cut -d= -f2)
    e=$(echo "${raw}" | grep -o 'any_errors=[0-9]*' | head -1 | cut -d= -f2)
    [[ -z "${v}" ]] && { echo "  C=${C} rep=${r}: NO RESULT" | tee -a "${OUT}"; errs=$((errs+1)); continue; }
    [[ "${e:-0}" != "0" ]] && errs=$((errs+1))
    [[ -z "${acc}" ]] && acc=$(echo "${raw}" | grep -o 'acceptance: .*' | head -1)
    vals+=("${v}")
  done
  if (( ${#vals[@]} == 0 )); then
    echo "  C=${C}: FAILED (all reps)" | tee -a "${OUT}"
    continue
  fi
  med=$(printf '%s\n' "${vals[@]}" | median)
  MED[$C]="$med"
  line=$(printf '  C=%-2s median=%-7s reps=[%s] any_errors=%s  %s' \
    "${C}" "${med}" "$(IFS=' '; echo "${vals[*]}")" "${errs}" "${acc}")
  echo "${line}" | tee -a "${OUT}"
done

if [[ ${#MED[@]} -gt 0 ]]; then
  sum=0; row=""
  for C in "${CS[@]}"; do
    v="${MED[$C]:-0}"; row+=$(printf '%8s' "${v}")
    sum=$(echo "${sum} + ${v}" | bc -l)
  done
  {
    echo ""
    echo "  C:        $(printf '%8s' "${CS[@]}")"
    echo "  decode:   ${row}"
    echo "  Sigma:    $(printf '%.1f' "${sum}")"
  } | tee -a "${OUT}"
fi

echo "" | tee -a "${OUT}"
echo "  cold prefill probe: ${CTX_WORDS} words, max_tokens=1, BENCH_COLD=1" | tee -a "${OUT}"
for r in $(seq 1 "${PREFILL_RUNS}"); do
  raw=$(BENCH_COLD=1 "${SCRIPT_DIR}/bench-ctx.sh" "${CTX_WORDS}" 1 2>&1 || true)
  pts=$(echo "${raw}" | grep -o 'prompt_tokens *= *[0-9]*' | head -1 | tr -dc '0-9')
  pps=$(echo "${raw}" | grep -o 'prefill_speed *= *[0-9.]*' | head -1 | grep -o '[0-9.]*$')
  echo "  prefill run${r}: prompt_tokens=${pts:-?}  ${pps:-?} tok/s" | tee -a "${OUT}"
done

echo "" | tee -a "${OUT}"
echo "  saved: ${OUT}" | tee -a "${OUT}"
