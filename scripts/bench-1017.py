#!/usr/bin/env python3
"""bench-1017 — validation harness for the DeepSeek-V4.1-Flash-1017 lanes.

The older bench-* helpers assume the Qwen lanes (model id "aeon", prefix-cache
free environment).  The 1017 lanes serve `deepseek-flash` with a 262144-token
contract, so this harness keeps the probe configurable and records evidence as
JSONL:

  prefill  sequential cold-prefill probes at a given prompt size
  conc     N concurrent requests at a given context size
  tools    structured-output (json_schema) + tool-call storm check
  soak     mixed load (short / long / image) for N minutes, health-sampled

Env / flags (flags win):
  VLLM_API_KEY   bearer key; falls back to ~/docker-stacks/config/cluster.env
  B1017_URL      default http://127.0.0.1:1234/v1/chat/completions
  B1017_MODEL    default aeon

The cluster exposes ONE external model id, `aeon`, whatever runtime is live
(compose lanes default to it in cluster-common.sh).  Do not encode a backend id
in client configs; use --model only to prove an endpoint rejects/accepts a name.

Examples:
  scripts/bench-1017.py prefill --tokens 128000 --tokens 200000 --tokens 255000
  scripts/bench-1017.py conc --ctx 32000 --conc 4 --maxtok 256
  scripts/bench-1017.py tools --rounds 20
  scripts/bench-1017.py soak --minutes 120 --interval 60 --out /tmp/soak.jsonl

Exit code: 0 when every check passed, 1 when any check reported a failure.
"""
import argparse
import json
import os
import pathlib
import statistics
import struct
import sys
import threading
import time
import urllib.error
import urllib.request
import zlib

HOME = pathlib.Path(os.path.expanduser("~"))
DEFAULT_URL = os.environ.get("B1017_URL", "http://127.0.0.1:1234/v1/chat/completions")
DEFAULT_MODEL = os.environ.get("B1017_MODEL", "aeon")


def api_key():
    """Resolve the bearer key the way cluster-common.sh does: source
    cluster.env and let the LAST assignment win (the file is `export`-style and
    may mention VLLM_API_KEY in a comment/example first).  An explicit
    VLLM_API_KEY in the environment always wins."""
    if os.environ.get("VLLM_API_KEY"):
        return os.environ["VLLM_API_KEY"]
    key = ""
    env = HOME / "docker-stacks" / "config" / "cluster.env"
    try:
        for line in env.read_text().splitlines():
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            if line.startswith("export "):
                line = line[len("export "):].strip()
            if line.startswith("VLLM_API_KEY="):
                val = line.split("=", 1)[1].strip().strip('"').strip("'")
                if val:
                    key = val
    except OSError:
        pass
    return key


KEY = api_key()


def post(args, payload, timeout):
    """POST one chat completion. Returns (body_json, wall_seconds, error_text)."""
    body = json.dumps(payload).encode()
    req = urllib.request.Request(args.url, data=body, method="POST")
    req.add_header("Content-Type", "application/json")
    if KEY:
        req.add_header("Authorization", f"Bearer {KEY}")
    t0 = time.time()
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            raw = resp.read()
        return json.loads(raw), time.time() - t0, None
    except urllib.error.HTTPError as exc:
        detail = exc.read().decode(errors="replace")[:400]
        return None, time.time() - t0, f"HTTP {exc.code}: {detail}"
    except Exception as exc:  # noqa: BLE001 - report, never crash the campaign
        return None, time.time() - t0, f"{type(exc).__name__}: {exc}"


def filler(tokens, nonce=True):
    """~`tokens` tokens of harmless filler; a nonce defeats prefix caching."""
    head = f"cold-run nonce {time.time_ns()} {os.getpid()}\n" if nonce else ""
    return head + ("token " * tokens)


def chat(args, content, max_tokens, **extra):
    payload = {
        "model": args.model,
        "messages": [{"role": "user", "content": content}],
        "max_tokens": max_tokens,
    }
    payload.update(extra)
    return post(args, payload, args.timeout)


def emit(args, record):
    line = json.dumps(record, ensure_ascii=False)
    print(line, flush=True)
    if args.out:
        with open(args.out, "a", encoding="utf-8") as fh:
            fh.write(line + "\n")


def small_png_data_uri():
    """16x16 grey PNG, no third-party deps (for the mixed soak leg)."""
    def chunk(kind, data):
        return (struct.pack(">I", len(data)) + kind + data
                + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF))

    raw = b"".join(b"\x00" + b"\x80\x80\x80" * 16 for _ in range(16))
    png = (b"\x89PNG\r\n\x1a\n"
           + chunk(b"IHDR", struct.pack(">IIBBBBB", 16, 16, 8, 2, 0, 0, 0))
           + chunk(b"IDAT", zlib.compress(raw))
           + chunk(b"IEND", b""))
    import base64
    return "data:image/png;base64," + base64.b64encode(png).decode()


# --------------------------------------------------------------------------- #
# subcommands
# --------------------------------------------------------------------------- #
def cmd_prefill(args):
    failures = 0
    for tokens in args.tokens:
        content = filler(tokens)
        body, wall, err = chat(args, content, 1)
        if err:
            print(f"prefill tokens={tokens} ERROR {err}", flush=True)
            failures += 1
            continue
        usage = body.get("usage", {})
        prompt_t = usage.get("prompt_tokens", 0)
        reason = body["choices"][0].get("finish_reason")
        tps = prompt_t / wall if wall else 0
        print(f"prefill prompt_tokens={prompt_t} wall={wall:.2f}s "
              f"prefill_tok_s={tps:.1f} finish={reason}", flush=True)
        emit(args, {"kind": "prefill", "requested_tokens": tokens,
                    "prompt_tokens": prompt_t, "wall_s": round(wall, 3),
                    "prefill_tok_s": round(tps, 1), "finish_reason": reason,
                    "ok": reason in ("length", "stop")})
        if reason not in ("length", "stop"):
            failures += 1
    return failures


def cmd_conc(args):
    results = [None] * args.conc
    lock = threading.Lock()

    def worker(idx):
        body, wall, err = chat(args, filler(args.ctx), args.maxtok)
        with lock:
            results[idx] = (body, wall, err)

    t0 = time.time()
    threads = [threading.Thread(target=worker, args=(i,)) for i in range(args.conc)]
    for th in threads:
        th.start()
    for th in threads:
        th.join()
    total_wall = time.time() - t0

    errors = [err for _, _, err in results if err]
    walls = [wall for _, wall, _ in results if wall is not None]
    completion = 0
    prompt = 0
    for body, _, err in results:
        if err:
            continue
        usage = body.get("usage", {})
        completion += usage.get("completion_tokens", 0)
        prompt += usage.get("prompt_tokens", 0)

    p50 = statistics.median(walls) if walls else 0
    p95 = sorted(walls)[min(len(walls) - 1, int(round(0.95 * (len(walls) - 1))))] if walls else 0
    agg = completion / total_wall if total_wall else 0
    print(f"conc ctx={args.ctx} conc={args.conc} prompt_tokens={prompt} "
          f"completion={completion} wall={total_wall:.2f}s agg_tok_s={agg:.1f} "
          f"lat_p50={p50:.2f}s lat_p95={p95:.2f}s errors={len(errors)}", flush=True)
    for err in errors[:3]:
        print(f"  ERROR {err}", flush=True)
    emit(args, {"kind": "conc", "ctx": args.ctx, "conc": args.conc,
                "prompt_tokens": prompt, "completion_tokens": completion,
                "wall_s": round(total_wall, 3), "agg_tok_s": round(agg, 1),
                "lat_p50_s": round(p50, 3), "lat_p95_s": round(p95, 3),
                "errors": len(errors), "ok": not errors})
    return len(errors)


SCHEMA = {
    "name": "weather_report",
    "schema": {
        "type": "object",
        "properties": {
            "city": {"type": "string"},
            "temp_c": {"type": "number"},
            "conditions": {"type": "string",
                           "enum": ["clear", "cloudy", "rain", "snow"]},
            "alerts": {"type": "array", "items": {"type": "string"}},
        },
        "required": ["city", "temp_c", "conditions", "alerts"],
        "additionalProperties": False,
    },
}

TOOLS = [{
    "type": "function",
    "function": {
        "name": "get_weather",
        "description": "Get the current weather for a city.",
        "parameters": {
            "type": "object",
            "properties": {"city": {"type": "string"},
                           "unit": {"type": "string", "enum": ["c", "f"]}},
            "required": ["city"],
        },
    },
}]


def cmd_tools(args):
    failures = 0
    json_ok = 0
    call_ok = 0
    truncated = 0
    # Thinking is ON by default on this lane (effort 75) and can consume the
    # whole max_tokens budget before any content is emitted: with a 256-token
    # cap, 2/20 rounds ended finish_reason=length with empty content (measured
    # 2026-10-21).  Format validation is about the grammar, so turn thinking
    # off by default and keep --thinking for callers that want the long path.
    fmt_kwargs = {} if args.thinking else {"chat_template_kwargs": {"thinking": False}}
    for i in range(args.rounds):
        body, wall, err = chat(
            args,
            f"Round {i}: report the weather in Taipei as strict JSON.",
            args.maxtok,
            response_format={"type": "json_schema", "json_schema": SCHEMA},
            temperature=0,
            **fmt_kwargs,
        )
        if err:
            print(f"structured round={i} ERROR {err}", flush=True)
            failures += 1
            continue
        choice = body["choices"][0]
        content = choice["message"].get("content") or ""
        if choice.get("finish_reason") == "length":
            truncated += 1
        try:
            parsed = json.loads(content)
            ok = isinstance(parsed.get("alerts"), list) and "temp_c" in parsed
        except Exception:  # noqa: BLE001
            ok = False
        json_ok += 1 if ok else 0
        if not ok:
            print(f"structured round={i} INVALID finish={choice.get('finish_reason')} "
                  f"content={content[:160]!r}", flush=True)
            failures += 1

        body, wall, err = chat(
            args,
            "Call get_weather for Taipei in celsius. Emit exactly one tool call.",
            args.maxtok,
            tools=TOOLS,
            tool_choice="auto",
            temperature=0,
            **fmt_kwargs,
        )
        if err:
            print(f"toolcall round={i} ERROR {err}", flush=True)
            failures += 1
            continue
        calls = body["choices"][0]["message"].get("tool_calls") or []
        valid = len(calls) == 1 and isinstance(calls[0].get("function", {}).get("arguments"), str)
        if valid:
            try:
                json.loads(calls[0]["function"]["arguments"])
            except Exception:  # noqa: BLE001
                valid = False
        call_ok += 1 if valid else 0
        if not valid:
            print(f"toolcall round={i} BAD n_calls={len(calls)}", flush=True)
            failures += 1
    print(f"tools rounds={args.rounds} json_schema_valid={json_ok} "
          f"single_tool_call_valid={call_ok} truncated={truncated} "
          f"failures={failures} thinking={args.thinking}", flush=True)
    emit(args, {"kind": "tools", "rounds": args.rounds,
                "json_schema_valid": json_ok, "tool_call_valid": call_ok,
                "truncated": truncated, "thinking": args.thinking,
                "max_tokens": args.maxtok, "failures": failures,
                "ok": failures == 0})
    return failures


def cmd_soak(args):
    endpoints = {"chat": args.url.replace("/chat/completions", "/health")}
    image = small_png_data_uri()
    deadline = time.time() + args.minutes * 60
    # Thinking is ON by default on this lane and can consume a small budget
    # before any content is emitted (round 0 of the first soak attempt came
    # back empty on all three legs at 16/128/48 tokens).  A soak measures
    # stability, not reasoning, so keep it off unless asked.
    fmt_kwargs = {} if args.thinking else {"chat_template_kwargs": {"thinking": False}}
    rounds = 0
    failures = 0
    gaps = []
    while time.time() < deadline:
        t_round = time.time()
        legs = []

        body, wall, err = chat(args, "Reply with the single word: pong", 32, **fmt_kwargs)
        legs.append(("short", wall, err, body))

        body, wall, err = chat(args, filler(8000), 256, **fmt_kwargs)
        legs.append(("long8k", wall, err, body))

        img_payload = {
            "model": args.model,
            "messages": [{"role": "user", "content": [
                {"type": "text", "text": "Describe this image in 8 words."},
                {"type": "image_url", "image_url": {"url": image}},
            ]}],
            "max_tokens": 128,
        }
        img_payload.update(fmt_kwargs)
        body, wall, err = post(args, img_payload, args.timeout)
        legs.append(("image", wall, err, body))

        try:
            with urllib.request.urlopen(endpoints["chat"], timeout=10) as resp:
                health = resp.status
        except Exception as exc:  # noqa: BLE001
            health = f"ERR {type(exc).__name__}"

        for name, wall, err, body in legs:
            if err:
                failures += 1
                print(f"soak round={rounds} leg={name} ERROR {err}", flush=True)
                continue
            text = (body["choices"][0]["message"].get("content") or "").strip()
            if not text:
                failures += 1
                print(f"soak round={rounds} leg={name} EMPTY content", flush=True)

        gaps.append(round(time.time() - t_round, 2))
        rounds += 1
        print(f"soak round={rounds} elapsed={int(time.time() - (deadline - args.minutes * 60))}s "
              f"health={health} legs={len(legs)} round_wall={gaps[-1]}s "
              f"failures={failures}", flush=True)
        emit(args, {"kind": "soak_round", "round": rounds, "health": health,
                    "round_wall_s": gaps[-1],
                    "legs": {n: round(w, 3) for n, w, _, _ in legs},
                    "failures": failures})
        if health != 200:
            failures += 1
        time.sleep(max(0, args.interval - (time.time() - t_round)))

    print(f"soak rounds={rounds} minutes={args.minutes} failures={failures} "
          f"round_wall_median={statistics.median(gaps) if gaps else 0:.2f}s", flush=True)
    emit(args, {"kind": "soak_summary", "rounds": rounds, "minutes": args.minutes,
                "failures": failures, "ok": failures == 0})
    return 0 if failures == 0 else 1


def main():
    ap = argparse.ArgumentParser(description="DeepSeek-V4.1-Flash-1017 validation harness")
    ap.add_argument("--url", default=DEFAULT_URL)
    ap.add_argument("--model", default=DEFAULT_MODEL)
    ap.add_argument("--timeout", type=int, default=1800)
    ap.add_argument("--out", help="append JSONL evidence here")
    sub = ap.add_subparsers(dest="cmd", required=True)

    p = sub.add_parser("prefill", help="sequential cold-prefill probes")
    p.add_argument("--tokens", type=int, action="append", required=True)
    p.set_defaults(func=cmd_prefill)

    c = sub.add_parser("conc", help="concurrent requests at one context size")
    c.add_argument("--ctx", type=int, default=32000)
    c.add_argument("--conc", type=int, default=4)
    c.add_argument("--maxtok", type=int, default=128)
    c.set_defaults(func=cmd_conc)

    t = sub.add_parser("tools", help="structured output + tool-call checks")
    t.add_argument("--rounds", type=int, default=10)
    t.add_argument("--maxtok", type=int, default=512)
    t.add_argument("--thinking", action="store_true",
                   help="keep thinking on (default off: it can eat the whole budget)")
    t.set_defaults(func=cmd_tools)

    s = sub.add_parser("soak", help="mixed load for N minutes")
    s.add_argument("--minutes", type=int, default=120)
    s.add_argument("--interval", type=int, default=60)
    s.add_argument("--thinking", action="store_true",
                   help="keep thinking on (default off: it can eat the whole budget)")
    s.set_defaults(func=cmd_soak)

    args = ap.parse_args()
    rc = args.func(args)
    return 0 if rc == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
