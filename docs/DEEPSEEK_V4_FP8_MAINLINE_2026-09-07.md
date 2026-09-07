# DeepSeek V4 Flash 0731 — fp8 DSpark Mainline (256K / 8-way)

**Status**: LIVE / mainline since 2026-09-07 · **Server**: TP2 Node0 `:1234`, model id `aeon`
**Profiles**: `cluster-profiles.d/deepseek.conf` (mainline) · `deepseek-nvfp4.conf` (archived placeholder)

---

## 1. Decision (2026-09-07)

- The fp8 reference lane (official `deepseek-ai` fp8 checkpoint + public Anemll runtime) is
  **promoted to the production mainline**, and the profile id is **`deepseek`** (the
  temporary `deepseek-ref` id was retired; its 40K speed-contract and gate numbers live in
  git history + this file for regression control).
- The **NVFP4 AEON lane is archived** (`deepseek-nvfp4.conf`, `PLACEHOLDER=true`, safe-fails
  as "not deployed yet"). Its mis-predicted draft acceptance and performance do not justify
  keeping it as mainline; the weights are **kept on disk on both nodes** — do NOT delete —
  so a future mature AEON image (real topk-256-quality DSpark) can re-enable it.
- Mainline contract: **256KB context + DSpark speculative decode + 8 concurrent streams**,
  all serving the unified `:1234` OpenAI API with the shared `VLLM_API_KEY`.

## 2. Launch contract (effective argv)

| Key | Value |
|---|---|
| profile id | `deepseek` |
| image | `ghcr.io/anemll/dspark-vllm-gx10:0.1.1` |
| model | `deepseek-v4-flash-0731-official` (revision `9e165c30...`) |
| max_model_len | **262144** |
| max_num_seqs | **8** |
| max_num_batched_tokens | 16384 |
| gpu_memory_utilization | 0.80 |
| quantization | `none` (fp8 in checkpoint) |
| kv_cache_dtype | `nvfp4_ds_mla` (sparse MLA KV format; NOT the weights) |
| moe_backend | `flashinfer_b12x` (B12xExperts) |
| graph mode | `FULL_AND_PIECEWISE`, `max_cudagraph_capture_size=8` |
| speculative | DSpark, **7 speculative tokens**, greedy (`dspark7`) |
| prefix caching | off (deliberate) |
| chunked prefill | on |
| served_model_name | `aeon` |

## 3. Capability verification (live 2026-09-07)

- `/health` = 200 after cold start (~7 min; weights 79.44 GiB + graphs 0.34 GiB ≈ 79.8 GiB / 96 GB).
- KV cache available = **11.44 GiB ≈ 371,451 tokens** → 256K context real, with slack for 8-way burst.
- `/v1/models` → `max_model_len: 262144`, served id `aeon`.
- Smoke (11 tok prompt) → `MAINLINE_OK`, `finish_reason=stop`.

## 4. Concurrency benchmark (C1 · C2 · C4 · C8)

Fixed mixed code+JSON prompt (118 prompt tokens), `max_tokens=400`, `curl -w` burst, wall = full batch.

| C | wall (s) | completion tok | C_total (tok/s) | acceptance % | mean accept len | per-position (pos0→6 %) |
|---|---|---|---|---|---|---|
| 1 | 6.58 | 232 | **35.3** | 23.8 | 1.66 | 63 · 46 · 22 · 15 · 10 · 7 · 3 |
| 2 | 8.43 | 387 | **45.9** | 25.1 | 1.75 | 69 · 44 · 28 · 16 · 9 · 6 · 4 |
| 4 | 21.11 | 1196 | **56.6** | 31.0 | 2.17 | 73 · 53 · 35 · 25 · 16 · 9 · 6 |
| 8 | 25.69 | 2208 | **85.9** | 26.8 | 1.87 | 70 · 46 · 29 · 20 · 13 · 6 · 4 |

- All streams `finish_reason=stop`, zero errors. Per-position acceptance matches the
  decaying shape (pos0 ~63-73% → pos6 ~3-6%), typical for same-model DSpark on a "hard" reasoning task.
- Reminder: the 40K gate lane measured ~75.8 tok/s burst / ~77% acceptance on a long warm
  profile; the 256K mainline trades a fraction of that for the 256K capability. Both are valid
  windows on the SAME weights; keep the 40K numbers historical, not a concurrency target.

## 5. Long-context probe (200K, capability proof)

`scripts/bench-ctx.sh 200000 1` — 200,005 prompt tokens, 1 completion token:

- wall = **124.97 s** → **prefill ≈ 1600 tok/s** at 200K context
- `finish_reason=length`, no OOM, no hang → **256KB context genuinely usable**.

## 6. Runbook

```bash
gb10 use deepseek          # switch to mainline (cold start ~7-15 min, waits for /health)
gb10 use deepseek-nvfp4    # safe-fail: "not deployed yet" (archived placeholder)
bash scripts/bench-c.sh 8 400   # C-class throughput + acceptance
bash scripts/bench-ctx.sh 200000 1  # long-context prefill probe
gb10 status / smoke / load
```

## 7. Archive record — NVFP4 AEON lane (captured verbatim from Node0)

Retired 2026-09-07. The complete launch contract was consumed by
`cluster-profiles.d/deepseek-nvfp4.conf` (`PLACEHOLDER=true`). Key values:

```
IMAGE  = ghcr.io/aeon-7/aeon-vllm-ultimate:2026-09-06-v0.27.1-omni-ds4flash0731-r1-topk256v2
BODY   = deepseek-v4-flash-0731-nvfp4
MAXLEN/SEQ/BATCHED/GMU = 65536 / 4 / 4096 / 0.80
KV_DTYPE = fp8_ds_mla   GRAPH_MODE = PIECEWISE
SPEC = dspark K5 (embedded draft)   prefix caching = off
```

Files (both nodes) retained: `~/docker-stacks/aeon-vllm/models/deepseek-v4-flash-0731-nvfp4/`.
Re-enable only after both nodes have a mature image + a passing real generation.

## 8. CLI changes (commit `57fd65b`)

- `bin/gb10`: `PROFILES_BY_NAME = 27b:35b:deepseek:deepseek-nvfp4:qwen38flash:glm53flash`
- `deepseek` = fp8 DSpark mainline (256K); `deepseek-nvfp4` = archived placeholder.
- `deepseek-ref` id removed (conf deleted; docs + git hold its gate numbers).

## Ongoing notes

- Bench harness (`scripts/bench-c.sh`, `scripts/bench-ctx.sh`) is bash+jq+bc only,
  deliberate: `python3 -c`, `pkill -f '<script>'` and heredocs are unreliable in the
  run-command client on Node0.
- Follow-up ideas (not committed): per-C latency p50/p95, temperature-swept acceptance,
  and a 256K-context generation correctness pass (not just prefill).