#!/usr/bin/env bash
set -Eeuo pipefail

# bench-c.sh <C> [MAX_TOKENS=400]
# Mixed code+JSON short prompt (≈40 tok ctx), C concurrent streams.
# Outputs per-stream lines, aggregate C_total, acceptance %, per-position.

C="${1:?usage: bench-c.sh <C> [MAX_TOKENS]}"
MAX_TOKENS="${2:-400}"
AUTH="Bearer d47cd7b86a7d2544dc375b9e447680670d100cfb0488056a0ff57c5aa8e6680b"
URL="http://127.0.0.1:1234/v1/chat/completions"

CONTENT='You are an expert Python/TypeScript engineer. Analyze the following mixed JSON and code, then explain what it does concisely:
```json
{"data":{"status":"ok","items":[{"id":1,"name":"alpha"},{"id":2,"name":"beta"}]},"config":{"cache":true,"maxItems":50}}
```
```typescript
export async function fetchItems(baseURL: string, opts?: { retries?: number }) {
  const res = await fetch(`${baseURL}/items`);
  return res.json();
}
```'

OUTDIR=$(mktemp -d /tmp/bench_c${C}_XXXX)
trap 'rm -rf "$OUTDIR"' EXIT

# Build payload safely with jq (no shell-escape fragility)
jq -n --arg content "$CONTENT" --argjson mt "$MAX_TOKENS" \
  '{model:"aeon",messages:[{role:"user",content:$content}],max_tokens:$mt}' > "$OUTDIR/payload.json"

METRICS_BEFORE=$(curl -s http://127.0.0.1:1234/metrics | grep -E '^vllm:spec_decode_(num_draft_tokens_total|num_accepted_tokens_total|num_drafts_total|num_accepted_tokens_per_pos_total)' | grep -v '_created' | sed 's/.*position="\([0-9]*\)"} \([0-9.]*\)/POS\1 \2/')

T0=$(date +%s.%N)
for i in $(seq 1 "$C"); do
  curl -s -H "Authorization: $AUTH" -H 'Content-Type: application/json' \
    -d "@$OUTDIR/payload.json" "$URL" > "$OUTDIR/$i.json" 2>/dev/null &
done
wait
T1=$(date +%s.%N)

METRICS_AFTER=$(curl -s http://127.0.0.1:1234/metrics | grep -E '^vllm:spec_decode_(num_draft_tokens_total|num_accepted_tokens_total|num_drafts_total|num_accepted_tokens_per_pos_total)' | grep -v '_created' | sed 's/.*position="\([0-9]*\)"} \([0-9.]*\)/POS\1 \2/')

WALL=$(echo "$T1 - $T0" | bc -l)
echo "================================================================"
echo "  bench-c  C=$C  wall=$(printf '%.3f' "$WALL")s  max_tokens=$MAX_TOKENS"
echo "================================================================"

TOTAL_COMP=0
ANY_ERR=0
for i in $(seq 1 "$C"); do
  COMP=$(jq -r '.usage.completion_tokens // 0' "$OUTDIR/$i.json")
  PROMPT_T=$(jq -r '.usage.prompt_tokens // 0' "$OUTDIR/$i.json")
  FINISH=$(jq -r '.choices[0].finish_reason // "ERR"' "$OUTDIR/$i.json")
  ERR=$(jq -r '.error.message // empty' "$OUTDIR/$i.json")
  TOTAL_COMP=$((TOTAL_COMP + COMP))
  [ "$FINISH" = "ERR" ] && ANY_ERR=1
  printf "  stream%d: prompt=%stok completion=%stok finish=%s" "$i" "$PROMPT_T" "$COMP" "$FINISH"
  [ -n "$ERR" ] && printf " error=%s" "$(echo "$ERR" | head -c 80)"
  echo ""
done
C_TOTAL=$(echo "$TOTAL_COMP / $WALL" | bc -l)
echo ""
echo "  aggregate: completion=${TOTAL_COMP}tok  wall=$(printf '%.3f' "$WALL")s  C_total=$(printf '%.1f' "$C_TOTAL") tok/s  any_errors=$ANY_ERR"

# Overall acceptance: delta_accepted / delta_draft_tokens (draft_tokens = 7/batch)
get_val(){ echo "$1" | grep -E "^$2 " | awk '{print $NF}' | head -1; }
get_pos(){ echo "$1" | grep "^POS$2 " | awk '{print $NF}'; }

BATCHES_BEFORE=$(get_val "$METRICS_BEFORE" "vllm:spec_decode_num_drafts_total")
BATCHES_AFTER=$(get_val  "$METRICS_AFTER"  "vllm:spec_decode_num_drafts_total")
ACCEPTED_BEFORE=$(get_val "$METRICS_BEFORE" "vllm:spec_decode_num_accepted_tokens_total")
ACCEPTED_AFTER=$(get_val  "$METRICS_AFTER"  "vllm:spec_decode_num_accepted_tokens_total")
DRAFTED_BEFORE=$(get_val "$METRICS_BEFORE" "vllm:spec_decode_num_draft_tokens_total")
DRAFTED_AFTER=$(get_val  "$METRICS_AFTER"  "vllm:spec_decode_num_draft_tokens_total")

DELTA_BATCHES=$((BATCHES_AFTER - BATCHES_BEFORE))
DELTA_ACCEPTED=$((ACCEPTED_AFTER - ACCEPTED_BEFORE))
DELTA_DRAFTED=$((DRAFTED_AFTER - DRAFTED_BEFORE))

echo ""
if [ "$DELTA_BATCHES" -gt 0 ]; then
  ACCEPT_PCT=$(echo "scale=1; $DELTA_ACCEPTED * 100 / $DELTA_DRAFTED" | bc -l)
  MEAN_LEN=$(echo "scale=2; $DELTA_ACCEPTED / $DELTA_BATCHES" | bc -l)
  echo "  acceptance: $DELTA_ACCEPTED / $DELTA_DRAFTED draft tokens = ${ACCEPT_PCT}%  mean_accept_len=${MEAN_LEN}"
else
  echo "  acceptance: (no draft delta this run)"
fi

echo "  per-position acceptance (delta accepted_at_pos / delta_draft_batches):"
for p in 0 1 2 3 4 5 6; do
  P_AFTER=$(get_pos "$METRICS_AFTER" "$p")
  P_BEFORE=$(get_pos "$METRICS_BEFORE" "$p")
  P_DELTA=$((P_AFTER - P_BEFORE))
  if [ "$DELTA_BATCHES" -gt 0 ]; then
    P_PCT=$(echo "scale=1; $P_DELTA * 100 / $DELTA_BATCHES" | bc -l)
    printf "    pos%d: %d / %d = %s%%\n" "$p" "$P_DELTA" "$DELTA_BATCHES" "$P_PCT"
  else
    printf "    pos%d: (no delta)\n" "$p"
  fi
done
echo "================================================================"
