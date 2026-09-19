#!/usr/bin/env bash
# =====================================================================
# bench-mm.sh — multimodal (image) probe for the vision lane.
#
# bench-mm.sh [NUM_IMAGES=1] [C=1] [MAX_TOKENS=200]
#
# Sends C concurrent /v1/chat/completions requests, each carrying
# NUM_IMAGES copies of a test image + a short text prompt. Reports wall,
# aggregate completion tok/s and the per-request prompt-token cost (the
# image token overhead). Test image defaults to the served model's own
# inference/examples/images/carrots.jpeg; override with MM_IMAGE=<path>.
# =====================================================================
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/cluster-common.sh"

NIMG="${1:-1}"
C="${2:-1}"
MAX_TOKENS="${3:-200}"

IMG_FILE="${MM_IMAGE:-${BODY}/inference/examples/images/carrots.jpeg}"
[[ -f "$IMG_FILE" ]] || { echo "ERROR: test image not found: $IMG_FILE (set MM_IMAGE=)" >&2; exit 1; }

URL="http://127.0.0.1:${API_PORT}/v1/chat/completions"
OUTDIR="$(mktemp -d /tmp/bench_mm_XXXX)"
trap 'rm -rf "$OUTDIR"' EXIT

base64 -w0 "$IMG_FILE" > "$OUTDIR/img.b64"
PROMPT="Describe the image(s) in one short sentence."

jq -n --rawfile b "$OUTDIR/img.b64" --argjson n "$NIMG" --arg p "$PROMPT" --argjson mt "$MAX_TOKENS" \
  '{model:"aeon",messages:[{role:"user",content:([range(0;$n)|{type:"image_url",image_url:{url:("data:image/jpeg;base64,"+$b)}}]+[{type:"text",text:$p}])}],max_tokens:$mt,temperature:0}' \
  > "$OUTDIR/payload.json"

echo "================================================================"
echo "  bench-mm  images=${NIMG}  C=${C}  max_tokens=${MAX_TOKENS}"
echo "  image:   ${IMG_FILE} ($(wc -c < "$IMG_FILE") bytes)"
echo "  payload: $(wc -c < "$OUTDIR/payload.json") bytes"
echo "================================================================"

T0=$(date +%s.%N)
for i in $(seq 1 "$C"); do
  api_curl "$URL" -m 600 -H 'Content-Type: application/json' \
    -d "@$OUTDIR/payload.json" > "$OUTDIR/$i.json" 2>/dev/null &
done
wait
T1=$(date +%s.%N)
WALL=$(echo "$T1 - $T0" | bc -l)

TOTAL_COMP=0; ANY_ERR=0
for i in $(seq 1 "$C"); do
  COMP=$(jq -r '.usage.completion_tokens // 0' "$OUTDIR/$i.json")
  PT=$(jq -r '.usage.prompt_tokens // 0' "$OUTDIR/$i.json")
  FIN=$(jq -r '.choices[0].finish_reason // "ERR"' "$OUTDIR/$i.json")
  ERR=$(jq -r '.error.message // empty' "$OUTDIR/$i.json")
  TOTAL_COMP=$((TOTAL_COMP + COMP))
  [ "$FIN" = "ERR" ] && ANY_ERR=1
  printf "  stream%d: prompt=%stok completion=%stok finish=%s" "$i" "$PT" "$COMP" "$FIN"
  [ -n "$ERR" ] && printf " error=%s" "$(echo "$ERR" | head -c 80)"
  echo ""
done
C_TOTAL=$(echo "$TOTAL_COMP / $WALL" | bc -l)
echo ""
echo "  aggregate: completion=${TOTAL_COMP}tok  wall=$(printf '%.3f' "$WALL")s  C_total=$(printf '%.1f' "$C_TOTAL") tok/s  any_errors=$ANY_ERR"
echo "  images/request=${NIMG}  (prompt_tokens above include the image token cost)"
echo "================================================================"
