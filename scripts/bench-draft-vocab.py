#!/usr/bin/env python3
"""bench-draft-vocab — A/B the MTP draft vocabulary on the qwen38flash lane.

The lane's only difference between arms is `Q38_DRAFT_VOCAB` (en_code_47k by
default, or one of the upstream 65k language files). Drafting changes speed only
— a draft outside the subset is rejected at verification — so a fair comparison
needs (a) fixed-length decode, (b) an English control measured in the same boot,
because upstream measured the English control itself to span 49.4-64.0 tok/s
across ten boots of one config (+-12%).

This harness therefore interleaves two prompt sets (the target language and an
English control of similar shape), pins every stream to exactly --max-tokens
(ignore_eos), and records the spec-decode counters from /metrics around each
cell so a speed change can be attributed to the drafter rather than the target.

Examples
  scripts/bench-draft-vocab.py run --label 47k   --lang zh --reps 3 --out /tmp/q38-47k.jsonl
  scripts/bench-draft-vocab.py run --label zh65k --lang zh --reps 6 --out /tmp/q38-zh65k.jsonl
  scripts/bench-draft-vocab.py compare /tmp/q38-47k.jsonl /tmp/q38-zh65k.jsonl

`--reps` also rotates the prompt start, so use --reps 6 to cover all six prompts
of each set at every concurrency (with the default 3, C=1 covers three prompts).

Env / flags (flags win):
  VLLM_API_KEY   bearer key; falls back to ~/docker-stacks/config/cluster.env
  BDV_URL        default http://127.0.0.1:1234/v1/chat/completions
  BDV_METRICS    default http://127.0.0.1:1234/metrics
  BDV_MODEL      default aeon

Exit code: 0 when every request succeeded, 1 when any cell reported an error.
"""
import argparse
import json
import os
import pathlib
import re
import statistics
import sys
import threading
import time
import urllib.error
import urllib.request

HOME = pathlib.Path(os.path.expanduser("~"))
DEFAULT_URL = os.environ.get("BDV_URL", "http://127.0.0.1:1234/v1/chat/completions")
DEFAULT_METRICS = os.environ.get("BDV_METRICS", "http://127.0.0.1:1234/metrics")
DEFAULT_MODEL = os.environ.get("BDV_MODEL", "aeon")


def api_key():
    """Same resolution as cluster-common.sh / bench-1017.py: the environment
    wins, else the LAST VLLM_API_KEY assignment in cluster.env (skip comments)."""
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

# Prompt sets. Both are the same shape (code+JSON analysis, prose, JSON output,
# short reasoning) so the draft acceptance is comparable across languages.
PROMPTS = {
    "en": [
        "Explain concisely what this Python function does, then list two edge cases:\n"
        "```python\ndef merge(a: dict, b: dict) -> dict:\n    out = dict(a)\n"
        "    for k, v in b.items():\n        out[k] = out.get(k, 0) + v\n    return out\n```",
        "Summarize the trade-offs between fixed-length and variable-length batching "
        "for an LLM inference server, in four bullet points.",
        "Write a JSON object describing a monitoring alert with fields: service, severity, "
        "threshold, window_seconds, runbook. Output JSON only.",
        "A cache has 3 shards and a request misses two of them. Explain step by step how "
        "the request is served and what the hit ratio means for latency.",
        "Explain why speculative decoding speeds up memory-bandwidth-bound decode more "
        "than it speeds up compute-bound prefill.",
        "Given an API that returns {\"items\": [...], \"next\": \"cursor\"}, describe the "
        "pagination algorithm and one failure mode.",
    ],
    "zh": [
        "請用繁體中文簡潔說明下列 Python 函式的功能，並列出兩個邊界情況：\n"
        "```python\ndef merge(a: dict, b: dict) -> dict:\n    out = dict(a)\n"
        "    for k, v in b.items():\n        out[k] = out.get(k, 0) + v\n    return out\n```",
        "請用繁體中文說明 LLM 推論伺服器中「固定長度批次」與「可變長度批次」的取捨，"
        "以四個要點呈現。",
        "請輸出一個 JSON 物件描述監控告警，欄位包含 service、severity、threshold、"
        "window_seconds、runbook。只輸出 JSON。",
        "一個快取有三個分片，某個請求命中其中兩個分片。請用繁體中文逐步說明該請求如何"
        "被服務，以及命中率對延遲的意義。",
        "請用繁體中文解釋：為什麼推測解碼（speculative decoding）對「記憶體頻寬受限」的"
        "解碼階段加速，會比對「運算受限」的預填充階段更明顯。",
        "有一個 API 回傳 {\"items\": [...], \"next\": \"cursor\"}，請用繁體中文說明分頁"
        "演算法，並指出一個可能的失敗情況。",
    ],
}


def post(payload, timeout):
    body = json.dumps(payload).encode()
    req = urllib.request.Request(URL, data=body, method="POST")
    req.add_header("Content-Type", "application/json")
    if KEY:
        req.add_header("Authorization", f"Bearer {KEY}")
    t0 = time.time()
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            raw = resp.read()
        return json.loads(raw), time.time() - t0, None
    except urllib.error.HTTPError as exc:
        return None, time.time() - t0, f"HTTP {exc.code}: {exc.read().decode(errors='replace')[:200]}"
    except Exception as exc:  # noqa: BLE001 - report, do not crash a long run
        return None, time.time() - t0, f"{type(exc).__name__}: {exc}"


METRIC_RE = re.compile(r"^(vllm:spec_decode_[a-z_]+?)(\{[^}]*\})?\s+([0-9.eE+-]+)$")


def metrics_snapshot():
    """Return {series_with_labels: value} for the spec-decode counters, or {}."""
    req = urllib.request.Request(METRICS)
    if KEY:
        req.add_header("Authorization", f"Bearer {KEY}")
    try:
        with urllib.request.urlopen(req, timeout=15) as resp:
            text = resp.read().decode(errors="replace")
    except Exception:  # noqa: BLE001 - metrics are optional for the run
        return {}
    out = {}
    for line in text.splitlines():
        m = METRIC_RE.match(line.strip())
        if not m:
            continue
        name, labels, value = m.group(1), m.group(2) or "", m.group(3)
        try:
            out[name + labels] = float(value)
        except ValueError:
            continue
    return out


def metric_delta(before, after):
    touched = {k: after[k] - before.get(k, 0.0) for k in after if after.get(k, 0.0) != before.get(k, 0.0)}
    drafts = sum(v for k, v in touched.items() if k.startswith("vllm:spec_decode_num_drafts_total"))
    draft_tokens = sum(v for k, v in touched.items() if k.startswith("vllm:spec_decode_num_draft_tokens_total"))
    accepted = sum(v for k, v in touched.items() if k.startswith("vllm:spec_decode_num_accepted_tokens_total"))
    per_pos = {}
    for k, v in touched.items():
        if k.startswith("vllm:spec_decode_num_accepted_tokens_per_pos_total"):
            m = re.search(r'position="(\d+)"', k)
            if m:
                per_pos[m.group(1)] = v
    return {
        "drafts": drafts,
        "draft_tokens": draft_tokens,
        "accepted": accepted,
        "accept_pct": (100.0 * accepted / draft_tokens) if draft_tokens else None,
        "al": (1.0 + accepted / drafts) if drafts else None,
        "per_pos": per_pos,
    }


def one_stream(prompt, args):
    payload = {
        "model": args.model,
        "messages": [{"role": "user", "content": prompt}],
        "max_tokens": args.max_tokens,
        "ignore_eos": True,
        "temperature": args.temperature,
        "seed": args.seed,
        "chat_template_kwargs": {"enable_thinking": bool(args.thinking)},
    }
    body, wall, err = post(payload, args.timeout)
    if err:
        return {"ok": False, "wall": wall, "tokens": 0, "error": err}
    usage = (body or {}).get("usage") or {}
    tokens = int(usage.get("completion_tokens") or 0)
    return {"ok": True, "wall": wall, "tokens": tokens, "error": None}


def run_cell(prompts, conc, args):
    results = [None] * conc
    start = threading.Barrier(conc + 1)

    def worker(i):
        start.wait()
        results[i] = one_stream(prompts[i % len(prompts)], args)

    threads = [threading.Thread(target=worker, args=(i,)) for i in range(conc)]
    for t in threads:
        t.start()
    before = metrics_snapshot()
    t0 = time.time()
    start.wait()
    for t in threads:
        t.join()
    wall = time.time() - t0
    after = metrics_snapshot()
    tokens = sum(r["tokens"] for r in results if r and r["ok"])
    errors = [r["error"] for r in results if r and not r["ok"]]
    return {
        "wall_s": round(wall, 3),
        "tokens": tokens,
        "agg_tok_s": round(tokens / wall, 2) if wall > 0 else None,
        "per_stream_tok_s": round(tokens / conc / wall, 2) if wall > 0 and conc else None,
        "errors": errors,
        **metric_delta(before, after),
    }


def cmd_run(args):
    lang = args.lang
    if lang not in PROMPTS:
        sys.exit(f"unknown --lang {lang!r}; known: {', '.join(PROMPTS)}")
    control = [x for x in PROMPTS if x != lang][0]
    concs = [int(x) for x in args.concurrency.split(",") if x.strip()]
    rows, failures = [], 0
    out = open(args.out, "a", encoding="utf-8") if args.out else sys.stdout
    try:
        for rep in range(1, args.reps + 1):
            for c in concs:
                for name, prompts in ((lang, PROMPTS[lang]), (control, PROMPTS[control])):
                    # Rotate the prompt start every rep: with C=1 the cell would
                    # otherwise always hit prompts[0], so a 3-rep median at C1
                    # would be one prompt's number, not the set's.
                    off = (rep - 1) % len(prompts)
                    rotated = prompts[off:] + prompts[:off]
                    cell = run_cell(rotated, c, args)
                    failures += len(cell["errors"])
                    row = {
                        "ts": time.strftime("%Y-%m-%dT%H:%M:%S"),
                        "label": args.label,
                        "lang": name,
                        "target_lang": lang,
                        "conc": c,
                        "rep": rep,
                        "prompt_start": off,
                        "max_tokens": args.max_tokens,
                        "thinking": bool(args.thinking),
                        **cell,
                    }
                    rows.append(row)
                    acc = f"  accept={cell['accept_pct']:.1f}%" if cell["accept_pct"] is not None else ""
                    print(f"[{args.label}] {name:2s} C{c} rep{rep}: {cell['agg_tok_s']} tok/s agg{acc}", flush=True)
                    if args.out:
                        out.write(json.dumps(row) + "\n")
                        out.flush()
    finally:
        if args.out:
            out.close()
    if args.out:
        summarize(rows, args.label, lang)
    return 1 if failures else 0


def med(rows, lang, conc, field):
    vals = [r[field] for r in rows if r["lang"] == lang and r["conc"] == conc and r.get(field) is not None]
    return statistics.median(vals) if vals else None


def summarize(rows, label, target):
    control = [x for x in PROMPTS if x != target][0]
    print(f"\n== {label}: medians over reps ==")
    print(f"{'C':>3} {target:>8} {control:>8} {'ratio':>7} {'accept%':>8}")
    for conc in sorted({r["conc"] for r in rows}):
        a = med(rows, target, conc, "agg_tok_s")
        b = med(rows, control, conc, "agg_tok_s")
        acc = med(rows, target, conc, "accept_pct")
        ratio = (a / b) if (a and b) else None
        print(
            f"{conc:>3} {a if a is not None else '-':>8} {b if b is not None else '-':>8} "
            f"{(f'{ratio:.3f}' if ratio else '-'):>7} {(f'{acc:.1f}' if acc is not None else '-'):>8}"
        )


def load(path):
    rows = []
    with open(path, encoding="utf-8") as fh:
        for line in fh:
            line = line.strip()
            if line:
                rows.append(json.loads(line))
    return rows


def cmd_compare(args):
    """Control-normalized comparison of two arms.

    Both arms measured the same target/control sets, so the control cancels the
    boot-to-boot drift; the ratio of the two normalized ratios is the effect.
    """
    a_rows, b_rows = load(args.file_a), load(args.file_b)
    target = a_rows[0]["target_lang"]
    control = [x for x in PROMPTS if x != target][0]

    def norm(rows, conc):
        t = med(rows, target, conc, "agg_tok_s")
        c = med(rows, control, conc, "agg_tok_s")
        return (t / c) if (t and c) else None

    print(f"target={target}  control={control}   A={args.file_a}  B={args.file_b}")
    print(f"{'C':>3} {'A tok/s':>9} {'B tok/s':>9} {'A norm':>7} {'B norm':>7} {'B/A':>7}")
    effects = []
    for conc in sorted({r["conc"] for r in a_rows} & {r["conc"] for r in b_rows}):
        at, bt = med(a_rows, target, conc, "agg_tok_s"), med(b_rows, target, conc, "agg_tok_s")
        an, bn = norm(a_rows, conc), norm(b_rows, conc)
        eff = (bn / an) if (an and bn) else None
        if eff:
            effects.append(eff)
        print(
            f"{conc:>3} {at if at is not None else '-':>9} {bt if bt is not None else '-':>9} "
            f"{(f'{an:.3f}' if an else '-'):>7} {(f'{bn:.3f}' if bn else '-'):>7} "
            f"{(f'{eff:.3f}' if eff else '-'):>7}"
        )
    if effects:
        print(f"\nmean normalized effect: {statistics.mean(effects):.3f}  "
              f"(min {min(effects):.3f}, max {max(effects):.3f}, cells {len(effects)})")
    return 0


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)

    r = sub.add_parser("run", help="measure one arm (one boot)")
    r.add_argument("--label", required=True, help="arm label, e.g. 47k or zh65k")
    r.add_argument("--lang", default="zh", help="target language set (en|zh)")
    r.add_argument("--reps", type=int, default=3)
    r.add_argument("--concurrency", default="1,2,4,8")
    r.add_argument("--max-tokens", type=int, default=400)
    r.add_argument("--temperature", type=float, default=0.0)
    r.add_argument("--seed", type=int, default=0)
    r.add_argument("--thinking", action="store_true", help="leave thinking on (default off)")
    r.add_argument("--timeout", type=float, default=900)
    r.add_argument("--model", default=DEFAULT_MODEL)
    r.add_argument("--out", help="JSONL evidence file (append)")
    r.set_defaults(func=cmd_run)

    c = sub.add_parser("compare", help="control-normalized B/A table from two JSONL files")
    c.add_argument("file_a")
    c.add_argument("file_b")
    c.set_defaults(func=cmd_compare)

    args = ap.parse_args()
    global URL, METRICS
    URL, METRICS = DEFAULT_URL, DEFAULT_METRICS
    sys.exit(args.func(args))


if __name__ == "__main__":
    main()
