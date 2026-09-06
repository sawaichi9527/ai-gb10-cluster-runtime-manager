# DeepSeek V4 Flash 0731 R1 — TP2 256K Context Validation (2026-09-06)

## Summary

256K context scaling experiment = **next step in the MAXLEN lineage**
(64K baseline → 128K → 256K). Branch `experiment/deepseek-v4-256k-r1`,
created from the validated 128K result (`4160ecb`).

- **Stack**: 2× DGX Spark GB10, TP2 (world_size=2, RoCE/NCCL), Node0 = API :1234.
- **Image (frozen)**: `ghcr.io/aeon-7/aeon-vllm-ultimate:2026-09-04-v0.27.1-omni-ds4flash0731-r1`.
- **Model (frozen)**: `nvidia/DeepSeek-V4-Flash-0731-NVFP4`, HF rev `f1caa71142bd0be02f728c79f75042ac1e461579`, fp8 NVFP4, KV `fp8_ds_mla`.
- **Single-variable change**: `cluster-profiles.d/deepseek.conf` `MAXLEN="131072"` → `MAXLEN="262144"` only. Commit `7b81362` (+3/-3, comment sync only).
- **Everything else frozen** from 128K: NUMSEQ=4, BATCHED=4096, GMU=0.80, KV_DTYPE=fp8_ds_mla, GRAPH_MODE=PIECEWISE, SPEC=none, no drafter, chunked prefill ON, prefix caching OFF, DSpark OFF, EP OFF, backends auto. **GMU intentionally untouched** (decision path: 240K probe must run at the stock GMU before any tuning).

## Validation sequence & results

1. `gb10 inspect deepseek` → `maxlen=262144 numseq=4 batched=4096 gmu=0.80`, kv=fp8_ds_mla, graph=PIECEWISE, spec=none, chunked=true prefix_cache=false. Only maxlen differs. PASS.
2. Cold start (`gb10 use deepseek`):
   - READY line: **14:33:50** (launch ~14:21:xx → ~12 min).
   - `tensor_parallel_size=2` in engine config; containers tp2-node0 + tp2-node1 up.
   - `fp8_ds_mla` accepted process-wide, no fallback (06:23:07).
   - Engine `max_seq_len=262144`; `/v1/models` → `max_model_len=262144`.
   - `init engine (profile, create kv cache, warmup model)` 153.92 s.
3. Smoke: HTTP 200, content `HELLO-TP2-OK`, finish_reason stop, 16 prompt / 9 completion. PASS.
4. **C1 decode (1×400, temp 0)**: rate ~20 tok/s (repeat 19.43, TTFT 0.13 s; first-in-window run 14.58 incl. warmup). Coherent. PASS.
5. **Needle ladder (needle `8349205` @35%; all actual prompt_tokens)**:

   | target | prompt_tokens | wall | found |
   |---|---|---|---|
   | 64K | 64,965 | 30.5 s | PASS |
   | 128K | 129,924 | 62.5 s | PASS |
   | 192K | 194,885 | 100.4 s | PASS |
   | **240K** | **243,604** | **131.8 s** | **PASS** |

6. **240K PASS** → C2, C4:
   - C2 (2×400): agg **32.96 tok/s** (each 16.48), no errors.
   - C4 (4×400): agg **46.44 tok/s** (each ~11.6), no errors.
7. Teardown: `gb10 stop`.

## KV pool monitoring (this experiment's control point)

The user's explicit condition: record actual KV pool size and the 240K
single-sequence share (128K pool was 417,389 tokens; 240K should still fit
but inside "allocator headroom" territory). Measured per worker (rank0):

| metric | 64K | 128K | 256K |
|---|---|---|---|
| Available KV cache memory | 12.93 GiB | 11.99 GiB | **12.51 GiB** |
| GPU KV cache size | — | 417,389 tokens | **725,237 tokens** |
| block size (DEEPSEEK_SPARSE_SWA) | 256 | 256 | 256 |
| block capacity of max seq (maxlen/256) | 256 | 512 | **1024** |

- The KV pool is **not** GMU-budget-constant and **not** maxlen-linear; the
  memory profiler's activation/graph estimate interacts with max_model_len,
  so pool tokens moved 417,389 → 725,237 (+1.74×) while available GiB stayed
  11.99 → 12.51. Pool block capacity (~2832 blocks/worker) always cleared the
  per-seq cap (1024 blocks @ 256K).
- **240K single-sequence share: 243,604 tokens ≈ 33% of the 725,237 pool**
  (measured in-flight KV usage 28.8%). Comfortable headroom — the feared
  tight-allocator regime did **not** materialize; no GMU change was needed.
- No KV OOM, no `Killed`, no allocator failure in any run.

## Decode throughput lineage (400-token completions, temp 0, agg tok/s)

| case | 64K | 128K | 256K |
|---|---|---|---|
| C1 (1×400) | 18.73 | 20.40 / 19.76 | 19.43 |
| C2 (2×400) | 39.19 | 31.69 / 34.32 | 32.96 |
| C4 (4×400) | 67.17 | 55.64 / 43.97 / 53.87 | 46.44 |

256K decode throughput holds the 128K envelope (C1 flat ~20; C2/C4 within the
concurrency-jitter band). No GPU throttle (SM 2528 MHz max). C4 jitter persists
across the lineage and is treated as the concurrency baseline for future
DSpark/optimization work.

## Errors

Functional window (weight load → smoke → bench → needles → stop) has **zero**
runtime errors. The only `Traceback` lines are benign import-time optional-module
probes (`import_utils.py:408` WARNING, standard in this container image).
No NCCL error, no DeepGEMM/CUDA assertion, no OOM on either node.

## Conclusion

All 256K PASS conditions met:

- `max_model_len = 262144` ✓
- 240K needle PASS (243,604 tokens found) ✓
- C1 coherent ✓
- C2 stable ✓ / C4 stable ✓
- no OOM (240K in-flight ≈ 33% of pool) ✓
- no NCCL error ✓
- no DeepGEMM/CUDA assert ✓

Per the decision path: main stays on the validated 64K default; 256K lives on
this branch only (not promoted). **240K PASS ⇒ next step is the ~393K probe**
(maxlen 262144→393216, same single-variable rule), before any DSpark K5 work.

## Artifacts / cleanup

- Experiment commit: `7b81362` on `experiment/deepseek-v4-256k-r1` (from 128K tip `4160ecb`).
- Scratch: `/tmp/use_ds_256k.log`, `/tmp/stop256k.log`, `/tmp/{c1,c1b,c1r2,c2,c4}_256k.log`, `/tmp/n256.log`, `/tmp/needle.py`, `/tmp/c_bench.py`. `n256.log`/bench logs contain no secrets; used API key was passed in-process argv only (needle/c_bench processes exited).
- TP2 stopped after validation (`gb10 stop`).