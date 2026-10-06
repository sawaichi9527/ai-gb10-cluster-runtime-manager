#!/usr/bin/env bash
# =====================================================================
# bench-prefix-hit.sh [WORDS=32000] [ROUNDS=3]
#
# Warm prefix-cache probe — the measurement `bench-ab-deepseek.sh` deliberately
# disables. bench-ctx.sh runs with BENCH_COLD=1 (a per-run nonce) so that
# prefix caching can NEVER give a cell a free ride, which keeps the prefill
# column comparable across cells. The consequence is that the whole point of
# the prefix-caching cell is invisible: with the nonce defeated, E3's prefill
# looks identical to E0's.
#
# This probe does the opposite: ONE fixed long prompt, sent ROUNDS times with
# no nonce, so round 2..N is a genuine prefix-cache hit.
#
#   * speed   : round-1 wall vs round-N wall (cold vs cache hit)
#   * correct : temperature=0, fixed answer instruction — every round must
#               return the same non-empty completion. A degenerate DSpark
#               draft on a cache hit truncates or garbles the answer, which is
#               exactly what patches/dspark-vision/hotfix-vllm-dspark-swa-prefix.py
#               exists to prevent. PASS here is what licenses prefix caching.
#
# Output: stdout + appended to /tmp/ab-<LABEL>.txt when LABEL is set, so the
# cell's own file carries it.
#
# Usage:
#   scripts/bench-prefix-hit.sh            # 32000 words, 3 rounds
#   LABEL=E3 scripts/bench-prefix-hit.sh 131000 3
# =====================================================================
set -Eeuo pipefail

WORDS="${1:-32000}"
ROUNDS="${2:-3}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/cluster-common.sh"

URL="http://127.0.0.1:${API_PORT}/v1/chat/completions"
OUT="${LABEL:+/tmp/ab-${LABEL}.txt}"

AUTH_ARGS=()
if [[ -n "${VLLM_API_KEY:-}" && "${VLLM_API_KEY}" != "EMPTY" ]]; then
  AUTH_ARGS=(-H "Authorization: Bearer ${VLLM_API_KEY}")
fi

emit(){ printf '%s\n' "$*"; [[ -n "${OUT:-}" && -f "${OUT:-/nonexistent}" ]] && printf '%s\n' "$*" >>"$OUT"; return 0; }

curl_j(){ # <payload-file> <result-file>
  curl -s -m 600 "${AUTH_ARGS[@]}" -H 'Content-Type: application/json' \
    -d "@$1" "$URL" >"$2" 2>/dev/null
}

# ---- one fixed long prompt: WORDS "token" words + a pinned answer --------
BODY="/tmp/prefix_hit_body_${WORDS}.txt"
if [[ ! -f "$BODY" ]]; then
  awk -v n="$WORDS" 'BEGIN{ while(i++<n) printf "token "; printf "\n\nReply with exactly: PREFIX-OK" }' \
    > "$BODY"
fi
PAYLOAD="/tmp/prefix_hit_payload_${WORDS}.json"
jq -n --rawfile text "$BODY" \
  '{"model":"aeon","messages":[{"role":"user","content":$text}],"max_tokens":40,"temperature":0}' \
  > "$PAYLOAD"

emit "--- prefix-cache HIT probe (words=${WORDS}, rounds=${ROUNDS}, temp=0, no nonce) ---"

prev=""; first_wall=""; n=0; ident=0; diffs=0; bad=0
for r in $(seq 1 "$ROUNDS"); do
  RES="/tmp/prefix_hit_res_${WORDS}_${r}.json"
  t0=$(date +%s.%N)
  if ! curl_j "$PAYLOAD" "$RES"; then emit "  round${r}: transport ERROR"; continue; fi
  t1=$(date +%s.%N)

  wall=$(echo "$t1 - $t0" | bc -l)
  err=$(jq -r '.error.message // empty' "$RES" 2>/dev/null || true)
  if [[ -n "$err" ]]; then emit "  round${r}: API ERROR: ${err}"; continue; fi

  pt=$(jq -r '.usage.prompt_tokens // 0' "$RES")
  ct=$(jq -r '.usage.completion_tokens // 0' "$RES")
  fin=$(jq -r '.choices[0].finish_reason // "ERR"' "$RES")
  content=$(jq -r '.choices[0].message.content // "ERR"' "$RES")
  speed=$(awk -v p="$pt" -v w="$wall" 'BEGIN{printf "%.1f", p/w}')

  n=$((n+1))
  [[ -z "$first_wall" ]] && first_wall="$wall"

  same="n/a"
  if [[ -n "$prev" ]]; then
    if [[ "$content" == "$prev" ]]; then same="identical"; ident=$((ident+1));
    else same="DIFFERS"; diffs=$((diffs+1)); fi
  fi
  prev="$content"
  [[ -z "$content" || "$content" == "ERR" ]] && bad=$((bad+1))

  emit "  round${r}: wall=${wall}s prefill=${speed} tok/s pt=${pt} ct=${ct} finish=${fin} content_len=${#content} vs_prev=${same}"
  emit "           content=${content}"
done

# ---- summary + verdict ------------------------------------------------
# $wall still holds the last round's wall time from the loop above.
if [[ -n "${first_wall:-}" && -n "${wall:-}" && -n "${prev:-}" ]]; then
  awk -v a="$first_wall" -v b="$wall" -v len="${#prev}" \
      -v id="$ident" -v df="$diffs" -v bd="$bad" 'BEGIN{
     speedup = (b > 0) ? a/b : 0
     hit     = (speedup > 1.5) ? "HIT" : "no-hit"
     ok      = (bd == 0 && len > 0) ? "OK" : "FAIL(empty/err)"
     same    = (df == 0) ? "yes" : "NO"
     printf "  summary: round1=%ss last=%ss  speedup=%.1fx  cache=%s\n", a, b, speedup, hit
     printf "  verdict: completion=%s  identical_across_rounds=%s (%d same / %d differ)  len=%d\n", ok, same, id, df, len
  }'
fi

emit "=== end prefix-cache HIT probe ==="
exit 0
