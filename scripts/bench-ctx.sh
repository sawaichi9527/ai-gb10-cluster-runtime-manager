#!/usr/bin/env bash
set -Eeuo pipefail

# bench-ctx.sh [NUM_WORDS=200000] [MAX_TOKENS=1]
# Long-context prefill probe: builds a ~NUM_WORDS-token prompt,
# sends with max_tokens=$MAX_TOKENS, reports wall time & prefill speed.
# max_tokens=1 isolates prefill (decode ≈ negligible overhead).

NUM_WORDS="${1:-200000}"
MAX_TOKENS="${2:-1}"
AUTH="Bearer d47cd7b86a7d2544dc375b9e447680670d100cfb0488056a0ff57c5aa8e6680b"
URL="http://127.0.0.1:1234/v1/chat/completions"
PAYLOAD="/tmp/payload_ctx${NUM_WORDS}.json"
RESULT="/tmp/result_ctx${NUM_WORDS}.json"

echo "================================================================"
echo "  bench-ctx  words=$NUM_WORDS  max_tokens=$MAX_TOKENS"
echo "================================================================"

# Build prompt: NUM_WORDS repeated "token" words ≈ NUM_WORDS tokens
awk -v n="$NUM_WORDS" 'BEGIN{while(i++<n) printf "token "}' > /tmp/ctx_body.txt
BODY_SIZE=$(wc -c < /tmp/ctx_body.txt)
echo "  payload body: ${BODY_SIZE} chars (~$((BODY_SIZE / 4)) tokens estimated)"

# Build JSON via jq (avoids ARG_MAX limits)
jq -n --rawfile text /tmp/ctx_body.txt \
  '{"model":"aeon","messages":[{"role":"user","content":$text}],"max_tokens":'"$MAX_TOKENS"'}' \
  > "$PAYLOAD"
PAYLOAD_SIZE=$(wc -c < "$PAYLOAD")
echo "  payload JSON: ${PAYLOAD_SIZE} bytes"

# Prefill probe (timed)
echo "  sending request..."
T0=$(date +%s.%N)
curl -s -H "Authorization: $AUTH" -H 'Content-Type: application/json' \
  -d "@$PAYLOAD" "$URL" > "$RESULT" 2>/dev/null
T1=$(date +%s.%N)

WALL=$(echo "$T1 - $T0" | bc -l)
PROMPT_T=$(jq -r '.usage.prompt_tokens // 0' "$RESULT")
COMP_T=$(jq -r '.usage.completion_tokens // 0' "$RESULT")
FINISH=$(jq -r '.choices[0].finish_reason // "ERR"' "$RESULT")
CONTENT=$(jq -r '.choices[0].message.content[:200] // "N/A"' "$RESULT")
ERR=$(jq -r '.error.message // empty' "$RESULT")

if [ -n "$ERR" ]; then
  echo "  ERROR: $ERR"
  exit 1
fi

PREFILL_TPS=$(echo "scale=1; $PROMPT_T / $WALL" | bc -l)
echo ""
echo "  result:"
echo "    prompt_tokens  = $PROMPT_T"
echo "    completion_tokens = $COMP_T"
echo "    finish_reason  = $FINISH"
echo "    wall_time      = $(printf '%.3f' "$WALL")s"
echo "    prefill_speed  = $(printf '%.1f' "$PREFILL_TPS") tok/s (prompt_tokens / wall)"
echo "    content_preview = $(echo "$CONTENT" | head -c 120)"
echo "================================================================"
