#!/usr/bin/env bash
# bench-multiturn.sh [TURNS=6] [MAX_TOKENS=300]
# Multi-turn stability: one growing conversation, TURNS round-trips. Each
# response must finish cleanly (stop/length) with non-empty content.
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/cluster-common.sh"

TURNS="${1:-6}"
MAX_TOKENS="${2:-300}"

python3 - "$API_PORT" "$TURNS" "$MAX_TOKENS" "${VLLM_API_KEY:-}" <<'PY'
import json, sys, time, urllib.request

port, turns, mt = int(sys.argv[1]), int(sys.argv[2]), int(sys.argv[3])
key = sys.argv[4] if len(sys.argv) > 4 and sys.argv[4] and sys.argv[4] != "EMPTY" else ""
url = f"http://localhost:{port}/v1/chat/completions"

msgs = [{"role": "user", "content": "We will keep a conversation going. Reply with one short sentence."}]
ok = 0
for t in range(turns):
    body = json.dumps({"model": "aeon", "messages": msgs, "max_tokens": mt, "temperature": 0.7}).encode()
    hdrs = {"Content-Type": "application/json"}
    if key:
        hdrs["Authorization"] = f"Bearer {key}"
    t0 = time.time()
    d = json.load(urllib.request.urlopen(
        urllib.request.Request(url, data=body, headers=hdrs), timeout=300))
    dt = time.time() - t0
    ch = d["choices"][0]
    content = (ch.get("message") or {}).get("content") or ""
    fin = ch.get("finish_reason")
    n = d["usage"]["completion_tokens"]
    good = bool(content.strip()) and fin in ("stop", "length")
    ok += good
    print(f"turn {t+1}: finish={fin} completion={n}tok wall={dt:.2f}s nonempty={bool(content.strip())} "
          f"{'OK' if good else 'BAD'}")
    msgs.append({"role": "assistant", "content": content})
    msgs.append({"role": "user", "content": "Continue."})
print(f"multiturn DONE: {ok}/{turns} clean turns")
PY
