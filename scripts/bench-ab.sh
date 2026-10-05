#!/usr/bin/env bash
# A/B measurement suite for the mimo26flash lane (MXFP4 vs NVFP4).
#
# Usage:  scripts/bench-ab.sh <label>
#
# Run it once per variant:
#   1. set BODY_REL in cluster-profiles.d/mimo26flash.conf
#   2. `gb10 use mimo26flash`  (cold start ~16 min)
#   3. scripts/bench-ab.sh <label>
# The script only calls the existing bench-c.sh / bench-ctx.sh harnesses, and
# does so byte-identically for both variants, so the two runs are comparable.
#
# What it measures
#   * decode : fixed-length (BENCH_IGNORE_EOS=1, exactly 400 tok/stream),
#              C=1/2/4/8, THREE runs each — acceptance swings hard between
#              runs, a single run is noise, so report median/mean of 3.
#   * prefill: BENCH_COLD=1 at 32K / 131K / 245K words (prefix caching is on,
#              hence BENCH_COLD).
#
# Output: stdout and /tmp/ab-<label>.txt. Each line is self-describing
# (`decode C=4 run=2 ...`, `prefill w=131000 ...`) so the two files can be
# diffed or pasted straight into a table.
#
# NOTE: runs are not interleaved with the other variant, and the engine has no
# warm-up round — treat decode deltas below ~10% as noise, and always compare
# medians, not single runs.
set -Eeuo pipefail

LABEL="${1:?usage: bench-ab.sh <label>}"
cd "$(dirname "$0")/.." || exit 1
OUT="/tmp/ab-${LABEL}.txt"
: >"$OUT"

emit() { printf '%s\n' "$*" | tee -a "$OUT"; }

emit "=== ${LABEL} start $(date -Is) ==="
emit "--- decode fixed-400 (BENCH_IGNORE_EOS=1), 3 runs each ---"
for c in 1 2 4 8; do
  for i in 1 2 3; do
    r=$(BENCH_IGNORE_EOS=1 bash scripts/bench-c.sh "$c" 2>&1 |
      grep -E 'aggregate:|acceptance:' | tr -s ' ' | tr '\n' '|')
    emit "decode C=${c} run=${i} ${r}"
  done
done

emit "--- cold prefill (BENCH_COLD=1) ---"
for w in 32000 131000 245000; do
  r=$(BENCH_COLD=1 bash scripts/bench-ctx.sh "$w" 2>&1 |
    grep -E 'prompt_tokens|wall_time|prefill_speed' | tr -s ' ' | tr '\n' ' ')
  emit "prefill w=${w} ${r}"
done

emit "DONE ${LABEL} $(date -Is)"
