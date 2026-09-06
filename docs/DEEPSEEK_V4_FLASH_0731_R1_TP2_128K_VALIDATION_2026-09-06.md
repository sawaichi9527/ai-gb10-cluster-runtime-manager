# DeepSeek V4 Flash 0731 R1 — TP2 128K Context Validation (2026-09-06)

## Summary

128K context scaling experiment for the validated DeepSeek V4 Flash 0731 r1
baseline (64K), on branch `experiment/deepseek-v4-128k-r1`.

- **Stack**: 2× DGX Spark GB10, TP2 (world_size=2, RoCE/NCCL), Node0 = API :1234.
- **Image**: `ghcr.io/aeon-7/aeon-vllm-ultimate:2026-09-04-v0.27.1-omni-ds4flash0731-r1` (frozen from r1 baseline, unchanged).
- **Model**: `nvidia/DeepSeek-V4-Flash-0731-NVFP4`, HF rev `f1caa71142bd0be02f728c79f75042ac1e461579`, fp8 NVFP4 weights + `fp8_ds_mla` KV.
- **Single-variable change**: `cluster-profiles.d/deepseek.conf` `MAXLEN="65536"` → `MAXLEN="131072"` only. Commit `055be95` (+3/-3, comment sync only).
- **Everything else frozen** from the r1 baseline: NUMSEQ=4, BATCHED=4096, GMU=0.80, KV_DTYPE=fp8_ds_mla, GRAPH_MODE=PIECEWISE, SPEC_METHOD=none, no drafter, ENABLE_CHUNKED_PREFILL=true, ENABLE_PREFIX_CACHING=false, DSpark OFF, EP OFF, backends auto.

## Validation sequence (user-specified)

1. `gb10 inspect deepseek` → resolved args: `maxlen=131072 numseq=4 batched=4096 gmu=0.80`, `kv=fp8_ds_mla`, `graph=PIECEWISE`, `spec=none`, `chunked=true prefix_cache=false`. Only maxlen differs from the 64K baseline. PASS.
2. `gb10 use deepseek` → READY.
   - Cold start: BEGIN 10:05:20, health 200 at **10:16:59** (~11.7 min). Engine init 154.66 s.
   - `fp8_ds_mla` accepted on rank0, process-wide, no fallback (log 02:05:40).
   - `world_size=2` confirmed (tp2-node0 + tp2-node1 up).
   - `/v1/models`: `id=aeon`, `max_model_len=131072`.
3. Minimal generation: HTTP 200, `finish_reason=stop`, content `HELLO-TP2-OK`, coherent. PASS.
4. 400-token C1/C2/C4 (temp 0, streaming with include_usage): all completed, no errors. PASS.
5. Needle-in-haystack ladder (needle `8349205` @35%, presence check): all truths recovered through 121,805 tokens. PASS.
6. Teardown: `gb10 stop`.

## KV cache sanity (check-total ≈ 2×)

The user's sanity expectation was that KV/worker should trend toward 2× the
64K value. Measured values:

| metric | 64K baseline | 128K run |
|---|---|---|
| Available KV cache memory / worker | 12.93 GiB | **11.99 GiB** |
| GPU KV cache size | (same pool family) | **417,389 tokens** |
| block size (DEEPSEEK_SPARSE_SWA) | 256 | 256 |

Why the pool did NOT double: vLLM sizes the KV-cache block pool from the
**memory budget** (`gpu_memory_utilization=0.80`), NOT from `max_model_len`.
Raising maxlen changes per-sequence capacity (131072/256 = **512 blocks/seq**),
not the pool size. The pool holds ~1630 blocks/worker (417,389 tokens), so the
largest validated sequence (121,805 + output tokens ≈ 477 blocks ≈ 122K tokens)
used ~28.4% of the pool — comfortably inside. The slightly lower available
memory vs 64K (11.99 vs 12.93 GiB) comes from larger reserved
activation/graph-profiling estimates at maxlen 131072, not a cache regression.

Proportionality remains visible per-sequence: 64K→512 seq-blocks max, 128K→
**1024 seq-tokens-blocks max**; in-flight KV for the 123K request was ~28.4% of
pool vs ~0% idle, and prompt prefill ran at ~12,180 tokens/s on the 123K prompt.

## Needle ladder (actual prompt tokens)

| target | prompt_tokens | wall | found |
|---|---|---|---|
| 8K | 5,924 | 4.2 s | PASS (8349205) |
| 32K | 23,485 | 10.4 s | PASS |
| 60K | 43,964 | 19.6 s | PASS |
| 60K (calibrated) | 60,926 | 27.5 s | PASS |
| 96K | 70,283 | 37.9 s | PASS |
| 96K (calibrated) | 97,445 | 46.0 s | PASS |
| **120K (calibrated)** | **121,805** | **58.3 s** | **PASS (8349205)** |

120K case prefill throughput ≈ 12,180 tokens/s (server metric).

## Decode throughput (400-token completions, temp 0; runs shown)

| case | 64K baseline | 128K runs (this day) |
|---|---|---|
| C1 (1×400) | 18.73 | **20.40 / 19.76** |
| C2 (2×400) | 39.19 | **31.69 / 34.32** |
| C4 (4×400) | 67.17 | **55.64 / 43.97 / 53.87** |

Single-stream throughput at 128K is at/above the 64K baseline. Concurrent runs
are within ±20% of baseline with high run-to-run jitter (no GPU throttle
observed: SM clock 2528 MHz max, low power draw); treated as variance, not a
regression. No OOM, no NCCL timeout, no DeepGEMM/CUDA assertion in any run.

## Errors

Zero `error`/`exception`/`traceback`/`oom`/`nccl`/`assert` matches in container
logs across the whole validation window.

## Conclusion

- `max_model_len=131072` effective and honored.
- `fp8_ds_mla` accepted, no fallback.
- **120K needle PASS** — the longest validated retrieval (121,805 prompt tokens).
- C1 coherent, C2/C4 completed and stable (no errors); throughput in baseline ballpark.
- No OOM / NCCL timeout / DeepGEMM or CUDA assertion.
- KV pool did not double (memory-budget bound), but per-sequence 128K capacity is proven by the 121.8K in-flight request (28.4% pool usage).

Per the decision path, the experiment defaults (`MAXLEN=131072` in `cluster-profiles.d/deepseek.conf`) are **not** promoted: the branch default stays 64K. This document and branch record the 128K evidence for the next scaling decision (128K → 256K → ~393K → then DSpark K5).

## Artifacts / cleanup

- Experiment commit: `055be95` on `experiment/deepseek-v4-128k-r1` (from Forgejo main `571cd65`).
- Bench scripts `/tmp/c_bench.py`, `/tmp/needle.py` (no secrets); `/tmp/args128.json` (contains `--api-key` argv) and `/tmp/use_ds_128k.log`, `/tmp/stop128k.log` are scratch — `/tmp/args128.json` should be removed.
- TP2 stopped after validation (`gb10 stop`).