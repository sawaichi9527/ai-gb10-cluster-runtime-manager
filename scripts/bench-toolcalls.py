#!/usr/bin/env python3
"""bench-toolcalls — reproduce the MiMo tool-call storm trigger and measure it.

The MOPD checkpoint of MiMo-V2.6-Flash exists to mitigate "tool-call
repetition": on long agent trajectories the RL/base model would answer one step
with dozens to hundreds of (often identical) tool calls instead of waiting for
results. This harness reconstructs that trigger from the recipe's published
description (aggressive agent system prompt, a large file just written, ~32K
context, an explicit "do not stop" turn) and counts the tool calls the model
emits in a single assistant response.

It does not need the recipe's captured body (not shipped); it is a proxy that
must be read as "does this checkpoint still storm?", comparable to the recipe's
published RL numbers (~148/446 identical grep calls; 659-709 calls in one
response from a captured 32K body) rather than a like-for-like replay.

Env:
  VLLM_API_KEY   bearer key (from cluster.env; EMPTY => no auth)
  TC_URL         default http://127.0.0.1:1234/v1/chat/completions
  TC_MODEL       default aeon
  TC_N           runs per config (default 4)
  TC_TEMPS       comma list (default 1.0,0.6)
  TC_THINK       1 => enable_thinking true (default off)
  TC_MAXTOK      max_tokens per response (default 8192)
  TC_PADTOK      ~tokens of padded tool result to reach a long context (default 12000)
  TC_REPPEN      per-request repetition_penalty (default: omit -> server default)
"""
import collections
import json
import os
import sys
import time
import urllib.request

URL = os.environ.get("TC_URL", "http://127.0.0.1:1234/v1/chat/completions")
KEY = os.environ.get("VLLM_API_KEY", "")
MODEL = os.environ.get("TC_MODEL", "aeon")
N = int(os.environ.get("TC_N", "4"))
TEMPS = [float(x) for x in os.environ.get("TC_TEMPS", "1.0,0.6").split(",")]
THINK = os.environ.get("TC_THINK", "0") == "1"
MAXTOK = int(os.environ.get("TC_MAXTOK", "8192"))
PADTOK = int(os.environ.get("TC_PADTOK", "12000"))
STRONG = os.environ.get("TC_STRONG", "0") == "1"

TOOLS = [
    {"type": "function", "function": {"name": "bash", "description": "Run a shell command.",
        "parameters": {"type": "object", "properties": {"command": {"type": "string"}}, "required": ["command"]}}},
    {"type": "function", "function": {"name": "read_file", "description": "Read a file.",
        "parameters": {"type": "object", "properties": {"path": {"type": "string"}}, "required": ["path"]}}},
    {"type": "function", "function": {"name": "write_file", "description": "Write a file.",
        "parameters": {"type": "object", "properties": {"path": {"type": "string"}, "content": {"type": "string"}}, "required": ["path", "content"]}}},
    {"type": "function", "function": {"name": "edit_file", "description": "Edit a file.",
        "parameters": {"type": "object", "properties": {"path": {"type": "string"}, "old": {"type": "string"}, "new": {"type": "string"}}, "required": ["path", "old", "new"]}}},
    {"type": "function", "function": {"name": "grep", "description": "Search file contents.",
        "parameters": {"type": "object", "properties": {"pattern": {"type": "string"}, "path": {"type": "string"}}, "required": ["pattern"]}}},
    {"type": "function", "function": {"name": "glob", "description": "List files by pattern.",
        "parameters": {"type": "object", "properties": {"pattern": {"type": "string"}}, "required": ["pattern"]}}},
]

SYSTEM = (
    "You are an autonomous coding agent operating in a repository. You have tools "
    "available. Work in long parallel bursts: whenever you can, issue MANY tool "
    "calls in a single response to make progress quickly, and keep the entire "
    "plan moving rather than stopping to confirm. Assume the environment is "
    "stable. Do not ask for approval. When given a multi-step task, carry it "
    "through end to end."
)

SYSTEM_STRONG = (
    "You are OMP, an autonomous coding agent. You MUST batch tool calls "
    "aggressively: put EVERY remaining step of the plan into THIS SINGLE response "
    "as tool calls. Never stop, never ask, never wait for results. Emit the whole "
    "trajectory at once, in parallel, as many calls as the plan needs."
)
FINAL_STRONG = (
    "Continue without stopping. Emit ALL remaining tool calls for the entire plan "
    "in this one response, now.")

PAD = ("src/render.js:  export function buildVoxel(canvas, opts) { /* ... */ }\n"
       * max(1, PADTOK // 12))


def build_messages():
    msgs = [{"role": "system", "content": SYSTEM_STRONG if STRONG else SYSTEM}]
    msgs.append({"role": "user", "content": (
        "Build an 80KB Three.js voxel scene as a small multi-file app under src/ "
        "(index.html, render.js, voxel.js, controls.js, scene.js). Wire up the "
        "camera, a chunked voxel grid, and a palette. Keep going until it runs.")})
    steps = [
        ("bash", {"command": "ls -la && cat package.json 2>/dev/null | head -40"}),
        ("bash", {"command": "ls -la src 2>/dev/null; find . -maxdepth 2 -name '*.js' | head"}),
        ("read_file", {"path": "src/render.js"}),
    ]
    if STRONG:
        steps += [
            ("bash", {"command": "wc -l src/*.js"}),
            ("grep", {"pattern": "voxel", "path": "src"}),
            ("glob", {"pattern": "src/**/*.js"}),
            ("read_file", {"path": "src/voxel.js"}),
            ("read_file", {"path": "src/scene.js"}),
        ]
    for i, (name, args) in enumerate(steps):
        msgs.append({"role": "assistant", "content": None,
                     "tool_calls": [{"id": f"call_{i}", "type": "function",
                                     "function": {"name": name, "arguments": json.dumps(args)}}]})
        result = PAD if i >= len(steps) - 2 else ("ok\n" + PAD[:400])
        msgs.append({"role": "tool", "tool_call_id": f"call_{i}", "content": result})
    msgs.append({"role": "user", "content": (
        FINAL_STRONG if STRONG else
        "Good. Now continue and work through ALL remaining steps without stopping: "
        "finish every file, then verify. Do not pause for confirmation.")})
    return msgs


def run_once(temp):
    body = {"model": MODEL, "messages": build_messages(), "tools": TOOLS,
            "tool_choice": "auto", "max_tokens": MAXTOK, "temperature": temp,
            "stream": False, "chat_template_kwargs": {"enable_thinking": THINK}}
    rp = os.environ.get("TC_REPPEN")
    if rp:
        body["repetition_penalty"] = float(rp)
    req = urllib.request.Request(URL, json.dumps(body).encode(),
                                 {"Content-Type": "application/json"})
    if KEY and KEY != "EMPTY":
        req.add_header("Authorization", "Bearer " + KEY)
    t = time.time()
    d = json.load(urllib.request.urlopen(req, timeout=3600))
    c = d["choices"][0]
    tcs = c["message"].get("tool_calls") or []
    sigs = []
    for tc in tcs:
        f = tc.get("function", {})
        sigs.append((f.get("name"), f.get("arguments")))
    cnt = collections.Counter(sigs)
    top = cnt.most_common(1)[0][1] if cnt else 0
    return {"finish": c.get("finish_reason"),
            "tokens": d["usage"]["completion_tokens"],
            "calls": len(tcs), "uniq": len(cnt), "max_dup": top,
            "secs": round(time.time() - t, 1)}


def main():
    print(f"harness: model={MODEL} think={THINK} strong={STRONG} N={N} max_tok={MAXTOK} "
          f"pad_tok~{PADTOK} rep_pen={os.environ.get('TC_REPPEN', '<server>')}")
    for temp in TEMPS:
        print(f"### temperature={temp}")
        for i in range(N):
            try:
                r = run_once(temp)
                storm = "STORM" if r["calls"] > 20 else ("calls" if r["calls"] else "none")
                print(f"  run{i+1}: finish={r['finish']} tokens={r['tokens']} "
                      f"calls={r['calls']} uniq={r['uniq']} max_dup={r['max_dup']} "
                      f"{r['secs']}s  {storm}", flush=True)
            except Exception as e:  # noqa: BLE001
                print(f"  run{i+1}: ERROR {e}", flush=True)


if __name__ == "__main__":
    sys.exit(main())
