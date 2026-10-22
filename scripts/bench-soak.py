#!/usr/bin/env python3
"""bench-soak.py — sustained concurrent chat load against an OpenAI-compatible endpoint.

Purpose: the kind of load that exposed engine bugs only after ~15 minutes (e.g. TensorFold
v1.1's CUDA-graph instantiate failure under many concurrent thinking requests), and the
"does it still answer correctly after 20 minutes" question that a single bench-c run cannot
answer.

Stdlib only (threads + urllib), so it runs anywhere the lane's API does — no aiohttp.

Usage:
  scripts/bench-soak.py [--url http://127.0.0.1:1234] [--model aeon]
                        [--concurrency 8] [--duration 1200] [--max-tokens 512]
                        [--thinking on|off] [--api-key-env API_KEY] [--key-file PATH]
                        [--jsonl /tmp/soak.jsonl] [--progress 60] [--timeout 900]

Per request it records one JSONL line: ts, stream, worker, http, finish_reason,
prompt_tokens, completion_tokens, content_len, reasoning_len, elapsed_s, mode, err.
Every 10th request is a "probe": the prompt asks for an exact token and the reply must
contain it (a garble/truncation check that does not depend on model quality).
A reply that stops on the token budget with empty content is counted as `truncated`
(thinking ate the budget), not as an error; an empty reply with finish_reason=stop is.

Exit: 0 all requests answered and every probe matched,
      1 at least one HTTP/transport error, empty stop, or probe mismatch,
      2 could not run (bad args, endpoint unreachable).
"""
from __future__ import annotations

import argparse
import json
import os
import random
import statistics
import sys
import threading
import time
import urllib.error
import urllib.request

PROBE_TOKEN = "HELLO-SOAK-OK"
FILLER = ("alpha bravo charlie delta echo foxtrot golf hotel india juliet kilo lima mike "
          "november oscar papa quebec romeo sierra tango uniform victor whiskey xray yankee zulu ").split()

# Prompt families: enough variety that streams do not all hit the same prefix cache, and
# enough length spread that prefill is exercised between decode bursts.
FAMILIES = (
    ("short", 0, "In one sentence, explain what a KV cache does in an inference server."),
    ("short", 0, "Name three trade-offs of speculative decoding."),
    ("medium", 3000, "Summarise the passage, then state the third fact you saw."),
    ("medium", 3000, "List every number that appears in the passage."),
    ("long", 12000, "State the last sentence of the passage verbatim."),
    ("long", 12000, "What is the most repeated word in the passage?"),
    ("short", 0, "Write a Python function that returns the n-th Fibonacci number."),
    ("short", 0, "Explain, in two sentences, why fp8 KV caches are lossy."),
)


def build_prompt(family: str, filler_tokens: int, question: str, probe: bool) -> str:
    if family == "short":
        if probe:
            return (f"Reply with exactly this token and nothing else: {PROBE_TOKEN}")
        return question
    words = " ".join(FILLER[i % len(FILLER)] for i in range(filler_tokens))
    body = (f"Passage:\n{words}\n\n"
            f"Question: {question}\n"
            f"Answer in at most 80 words.")
    if probe:
        body += f"\nThen, on a final line by itself, output exactly: {PROBE_TOKEN}"
    return body


def post_json(url: str, payload: dict, headers: dict, timeout: float) -> tuple[int, dict | str]:
    data = json.dumps(payload).encode()
    req = urllib.request.Request(url, data=data, headers=headers, method="POST")
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            return r.status, json.loads(r.read().decode())
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode("utf-8", "replace")[:400]
    except Exception as e:  # transport
        return 0, f"{type(e).__name__}: {e}"


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    p.add_argument("--url", default=os.environ.get("API_URL", "http://127.0.0.1:1234"))
    p.add_argument("--model", default=os.environ.get("MODEL", "aeon"))
    p.add_argument("--concurrency", type=int, default=8)
    p.add_argument("--duration", type=float, default=1200, help="seconds (default 20 min)")
    p.add_argument("--max-tokens", type=int, default=512)
    p.add_argument("--thinking", choices=("on", "off"), default="on")
    p.add_argument("--api-key-env", default="API_KEY")
    p.add_argument("--key-file", default=None,
                   help="file holding the bearer key (first non-comment line; overrides --api-key-env)")
    p.add_argument("--jsonl", default="/tmp/soak.jsonl")
    p.add_argument("--progress", type=float, default=60)
    p.add_argument("--timeout", type=float, default=900)
    a = p.parse_args()

    key = os.environ.get(a.api_key_env, "")
    if a.key_file:
        with open(a.key_file) as f:
            key = next((ln.strip() for ln in f if ln.strip() and not ln.lstrip().startswith("#")), "")
    base = a.url.rstrip("/")
    if not base.endswith("/v1"):
        base += "/v1"
    url = base + "/chat/completions"
    headers = {"Content-Type": "application/json"}
    if key:
        headers["Authorization"] = "Bearer " + key

    # Reachability probe: /v1/models with the same headers we will use.
    try:
        req = urllib.request.Request(base + "/models", headers=headers)
        with urllib.request.urlopen(req, timeout=30) as r:
            if r.status != 200:
                print(f"ERROR: /v1/models answered {r.status}", file=sys.stderr)
                return 2
    except Exception as e:
        print(f"ERROR: cannot reach {base}/models ({type(e).__name__}: {e})", file=sys.stderr)
        return 2

    out = open(a.jsonl, "w", buffering=1)
    lock = threading.Lock()
    stop_at = time.time() + a.duration
    stats = {"done": 0, "err": 0, "trunc": 0, "probe_fail": 0, "tokens": 0, "lat": [], "by_family": {}}
    started = time.time()
    counter = {"n": 0}

    def worker(wid: int) -> None:
        rng = random.Random(1000 + wid)
        while time.time() < stop_at:
            with lock:
                n = counter["n"]
                counter["n"] += 1
            family, filler, question = FAMILIES[n % len(FAMILIES)]
            probe = (n % 10 == 0)
            prompt = build_prompt(family, filler, question, probe)
            body = {
                "model": a.model,
                "messages": [{"role": "user", "content": prompt}],
                "max_tokens": a.max_tokens,
                "temperature": 0,
            }
            if a.thinking == "off":
                body["chat_template_kwargs"] = {"enable_thinking": False}
            t0 = time.time()
            code, resp = post_json(url, body, headers, a.timeout)
            dt = time.time() - t0
            rec = {"ts": round(time.time(), 3), "stream": wid, "worker": n, "http": code,
                   "mode": f"{family}{'+probe' if probe else ''}", "elapsed_s": round(dt, 3)}
            err = ""
            content = reason = ""
            if code != 200 or not isinstance(resp, dict):
                err = "http" if code else "transport"
                rec["err_detail"] = resp if isinstance(resp, str) else ""
            else:
                ch = (resp.get("choices") or [{}])[0]
                msg = ch.get("message") or {}
                content = msg.get("content") or ""
                reason = msg.get("reasoning_content") or ""
                fr = ch.get("finish_reason")
                usage = resp.get("usage") or {}
                rec.update({"finish_reason": fr,
                            "prompt_tokens": usage.get("prompt_tokens"),
                            "completion_tokens": usage.get("completion_tokens"),
                            "content_len": len(content), "reasoning_len": len(reason)})
                if fr == "length" and not content.strip():
                    err = "truncated"
                elif not content.strip() and not reason.strip():
                    err = "empty"
                elif probe and PROBE_TOKEN not in content:
                    err = "probe"
            rec["err"] = err
            out.write(json.dumps(rec) + "\n")
            with lock:
                stats["done"] += 1
                stats["tokens"] += int(rec.get("completion_tokens") or 0)
                stats["lat"].append(dt)
                stats["by_family"][family] = stats["by_family"].get(family, 0) + 1
                if err == "truncated":
                    stats["trunc"] += 1
                elif err == "probe":
                    stats["probe_fail"] += 1
                    stats["err"] += 1
                elif err:
                    stats["err"] += 1

    threads = [threading.Thread(target=worker, args=(i,), daemon=True) for i in range(a.concurrency)]
    for t in threads:
        t.start()
    print(f"soak: {a.concurrency} streams for {a.duration:.0f}s against {url} "
          f"(model {a.model}, max_tokens {a.max_tokens}, thinking {a.thinking})", flush=True)

    last = time.time()
    while any(t.is_alive() for t in threads):
        time.sleep(2)
        now = time.time()
        if now - last >= a.progress:
            last = now
            with lock:
                lat = sorted(stats["lat"])
                p50 = statistics.median(lat) if lat else 0
                p95 = lat[int(len(lat) * 0.95) - 1] if len(lat) > 20 else (lat[-1] if lat else 0)
                el = now - started
                print(f"[{el:6.0f}s] done={stats['done']} err={stats['err']} "
                      f"truncated={stats['trunc']} probes_failed={stats['probe_fail']} "
                      f"p50={p50:.2f}s p95={p95:.2f}s tok/s={stats['tokens'] / el:.1f}", flush=True)
    for t in threads:
        t.join()
    out.close()

    with lock:
        lat = sorted(stats["lat"])
        el = max(time.time() - started, 1e-9)
        summary = {
            "duration_s": round(el, 1), "concurrency": a.concurrency, "model": a.model,
            "max_tokens": a.max_tokens, "thinking": a.thinking,
            "requests": stats["done"], "errors": stats["err"],
            "truncated_empty_content": stats["trunc"], "probe_mismatch": stats["probe_fail"],
            "completion_tokens": stats["tokens"], "tok_per_s": round(stats["tokens"] / el, 1),
            "lat_p50_s": round(statistics.median(lat), 3) if lat else None,
            "lat_p95_s": round(lat[int(len(lat) * 0.95) - 1], 3) if len(lat) > 20 else None,
            "by_family": stats["by_family"],
        }
    print("SOAK " + json.dumps(summary, ensure_ascii=False), flush=True)
    return 0 if stats["err"] == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
