# DeepSeek V4 Flash 0731 R1 — TP2 393K Context Validation (2026-09-06)

## Summary

393K context scaling experiment — **final rung of the MAXLEN ladder**
(64K → 128K → 256K → **393K**). Branch `experiment/deepseek-v4-393k-r1`,
created from the validated 256K result (`d6829d8`). The stated goal: prove the
"long-context correctness ladder" is complete enough that the next step is a
deliberate move to r2 / DSpark K5 rather than stacking more raw maxlen.

- **Stack**: 2× DGX Spark GB10, TP2 (world_size=2, RoCE/NCCL), Node0 = API :1234.
- **Image (frozen)**: `ghcr.io/aeon-7/aeon-vllm-ultimate:2026-09-04-v0.27.1-omni-ds4flash0731-r1`.
- **Model (frozen)**: `nvidia/DeepSeek-V4-Flash-0731-NVFP4`, HF rev `f1caa71142bd0be02f728c79f75042ac1e461579`, fp8 NVFP4, KV `fp8_ds_mla`.
- **Single-variable change**: `cluster-profiles.d/deepseek.conf` `MAXLEN="262144"` → `MAXLEN="393216"` only. Commit `ade20e3` (+3/-3, comment sync only).
- **Everything else frozen**: NUMSEQ=4, BATCHED=4096, GMU=0.80, KV_DTYPE=fp8_ds_mla, GRAPH_MODE=PIECEWISE, SPEC=none, no drafter, chunked prefill ON, prefix caching OFF, DSpark OFF, EP OFF, backends auto. GMU untouched (stock 0.80, per decision path).

## Validation sequence & results

1. `gb10 inspect deepseek` → `maxlen=393216 numseq=4 batched=4096 gmu=0.80`, kv=fp8_ds_mla, graph=PIECEWISE, spec=none, chunked=true prefix_cache=false. Only maxlen differs. PASS.
2. Cold start (`gb10 use deepseek`):
   - READY (health 200) observed ~15:24 (launch ~15:14 → ~10-11 min).
   - `tensor_parallel_size=2`; containers tp2-node0 + tp2-node1 up.
   - `fp8_ds_mla` accepted, no fallback.
   - `/v1/models` → `max_model_len=393216`.
   - engine init ~07:22:31 (153.9 s class).
3. Smoke: HTTP 200, `HELLO-TP2-OK`, finish_reason stop, 16 prompt / 9 completion. PASS.
4. **C1 (1×400, temp 0)**: repeat 19.52 tok/s (TTFT 0.13 s; first-in-window 14.96 incl. warmup). Coherent. PASS.
5. **Needle ladder (needle `8349205` @35%; all actual prompt_tokens)**:

   | target | prompt_tokens | wall | found |
   |---|---|---|---|
   | 128K | 129,924 | 64.0 s | PASS |
   | 256K | 259,844 | 142.7 s | PASS |
   | 320K | 324,764 | 199.2 s | PASS |
   | **376K** | **373,483** | **232.5 s** | **PASS** |

   The requested near-limit probe condition (actual prompt tokens ≤ ~385K with
   optional extra probe) is met by the 376K run itself: actual prompt_tokens
   **373,483** already sit inside the ≤~385K band under maxlen 393216, so no
   further optional probe was needed.
6. **376K PASS** → C2, C4:
   - C2 (2×400): agg **32.11 tok/s** (each ~16.1), no errors.
   - C4 (4×400): agg **52.38 tok/s** (each ~13.1), no errors.
7. Teardown: `gb10 stop`.

## KV pool monitoring

| metric | 64K | 128K | 256K | 393K |
|---|---|---|---|---|
| Available KV memory / worker | 12.93 GiB | 11.99 GiB | 12.51 GiB | **11.58 GiB** |
| GPU KV cache size (tokens) | — | 417,389 | 725,237 | **974,033** |
| block size (SWA) | 256 | 256 | 256 | 256 |
| per-seq blocks @ maxlen | 256 | 512 | 1024 | **1536** |

- Pool tokens grew 725,237 → **974,033** at 393K; available GiB nominally
  11.58 GiB/worker (memory-profiler interaction with max_model_len, not a
  capacity regression — block pool always cleared the per-seq cap).
- **Near-limit occupancy**: the 376K probe at **373,483 tokens** ≈ **38% of the
  974,033 pool** (measured in-flight KV 28.6% prefill). Comfortable headroom — no
  allocator pressure, no GMU change needed, at the stock 0.80.
- No KV OOM, no `Killed`, no allocator failure on either node.

## Decode throughput lineage (400-token completions, temp 0, agg tok/s)

| case | 64K | 128K | 256K | 393K |
|---|---|---|---|---|
| C1 (1×400) | 18.73 | 20.40 / 19.76 | 19.43 | **19.52** |
| C2 (2×400) | 39.19 | 31.69 / 34.32 | 32.96 | **32.11** |
| C4 (4×400) | 67.17 | 55.64 / 43.97 / 53.87 | 46.44 | **52.38** |

C1 holds flat ~19-20 tok/s across the entire MAXLEN ladder; C2 stable ~32;
C4 showed run-to-run jitter across the lineage (this day 52.38, comfortably in
band). No GPU throttle (SM 2528 MHz max). This is the DSpark/concurrency
baseline for the r2/K5 decision.

## Errors

Functional window (weight load → smoke → bench → needles → stop) has **zero**
runtime errors. node1: 0 matches for any CUDA/NCCL/OOM/Killed/Traceback. node0:
3 lines are the standard benign import-time optional-module probes
(`import_utils.py:408` WARNING, identical in every container run of this
image). No NCCL error, no DeepGEMM/CUDA assertion, no OOM on either node.

## Conclusion

All 393K PASS conditions met:

- `max_model_len = 393216` ✓
- 376K needle PASS (373,483 actual tokens found) ✓
- C1 coherent ✓ / C2 stable ✓ / C4 stable ✓
- near-limit occupancy ≈ 38% of pool — no OOM, no allocator issue ✓
- no NCCL error ✓ / no DeepGEMM/CUDA assert ✓

Per the decision path this closes the r1 long-context correctness ladder:
main stays on the validated 64K default; 393K is branch-scoped (not promoted).
**Next step (per user): the correctness ladder is sufficient → move to r2 /
DSpark K5**, instead of further maxlen-only stacking.

## Artifacts / cleanup

- Experiment commit: `ade20e3` on `experiment/deepseek-v4-393k-r1` (from 256K tip `d6829d8`), pending the validation-doc commit.
- Scratch: `/tmp/use_ds_393k.log`, `/tmp/stop393k.log`, `/tmp/{c1,c1r,c2,c4}_393k.log`, `/tmp/n393.log`, `/tmp/needle.py`, `/tmp/c_bench.py`. Bench/needle logs contain no secrets; API key passed in process argv only (processes exited).
- TP2 stopped after validation (`gb10 stop`).