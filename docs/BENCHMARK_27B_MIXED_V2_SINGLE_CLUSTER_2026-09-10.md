# 27B MIXED v2 Benchmark Report (Single TP1 vs Cluster TP2)

**Date:** 2026-09-10
**Model:** `qwen3.8-27b-aeon-ultimate-uncensored-nvfp4-mixed`
**Image:** `ghcr.io/aeon-7/aeon-vllm-ultimate:2026-09-07-reasoning-eos`
**Drafter:** `qwen3.8-27b-dflash2` (DFlash2)

---

## Test Configuration

| Parameter | Single (TP1) | Cluster (TP2) |
|-----------|-------------|--------------|
| Tensor Parallel | 1 | 2 (rank0 + rank1) |
| Speculative | DFlash2 n=7 | DFlash2 n=7 |
| Attention Backend | TRITON_ATTN | TRITON_ATTN |
| Prefix Caching | OFF | OFF |
| Quantization flag | unset (hf_quant_config) | unset (hf_quant_config) |
| VLLM_USE_V2_MODEL_RUNNER | 0 | 0 |
| max-model-len | 262,144 | 262,144 |
| max-num-seqs | 8 | 8 |
| max-num-batched-tokens | 32,768 | 32,768 |
| **gpu-memory-utilization** | **0.70** | **0.85** |
| **KV cache dtype** | **`fp8`** | **`fp8_e4m3`** |
| Generation max_tokens | 2,048 | 2,048 |

> Note: cluster `GMU="0.85"` (cluster-profiles.d/27b.conf), single `VLLM_GPU_MEMORY_UTILIZATION=0.70` (standalone.env). KV cache dtype differs: single compose sets `--kv-cache-dtype fp8`, cluster profile sets `KV_DTYPE="fp8_e4m3"`.

---

## Concurrency Benchmark (bench-c, MAX_TOKENS=2048)

| C | Single C_total (tok/s) | Single Accept% | Single Mean Len | Cluster C_total (tok/s) | Cluster Accept% | Cluster Mean Len | Speedup |
|---|------------------------|----------------|-----------------|------------------------|-----------------|------------------|---------|
| 1 | 19.1 | 23.9% | 1.67 | 31.5 | 33.0% | 2.31 | 1.65x |
| 2 | 43.4 | 36.3% | 2.54 | 68.9 | 38.1% | 2.67 | 1.59x |
| 3 | 54.0 | 32.2% | 2.25 | 75.2 | 28.8% | 2.02 | 1.39x |
| 4 | 57.8 | 25.5% | 1.78 | 82.5 | 28.9% | 2.02 | 1.43x |
| 8 | 89.5 | 27.6% | 1.93 | 150.6 | 28.4% | 1.99 | 1.68x |

**Per-position acceptance (cluster C1):** pos0 74.6%, pos1 53.7%, pos2 35.8%, pos3 25.3%, pos4 20.8%, pos5 11.9%, pos6 8.9%

**Observations:**
- Cluster TP2 delivers 1.4x–1.7x throughput speedup across all concurrency levels.
- DFlash2 n=7 acceptance: cluster 28.4–38.1%, single 23.9–36.3%. Both functional; cluster slightly higher.
- C8 peak: single 89.5 tok/s → cluster 150.6 tok/s (1.68x).

---

## Long-Context Prefill (bench-ctx, 245,052 tokens, max_tokens=1)

| | Single (TP1) | Cluster (TP2) |
|---|-------------|--------------|
| prompt_tokens | 245,052 | 245,052 |
| wall_time | 738.8s (12.3 min) | 397.4s (6.6 min) |
| prefill_speed | 331.6 tok/s | 616.5 tok/s |
| finish_reason | length | length |

**Observations:**
- Cluster TP2 prefill 1.86x faster (616.5 vs 331.6 tok/s).
- Both handle 245k context correctly (model native max_position_embeddings=262,144).

---

## Cold Start Times

| | Single | Cluster |
|---|--------|---------|
| Total cold start | ~530s (8.8 min) | ~310s (5.2 min) |
| Notes | Model load 145s + torch.compile 85s + autotune 161s | torch.compile 81s + autotune 43s |

Cluster faster due to TP2 split load + warm autotune cache.

---

## ModelOpt MIXED Hard Rules Compliance

| Rule | Status |
|------|--------|
| #1 No `--quantization` flag | PASS (count=0 both) |
| #2 Reasoning-eos image | PASS |
| #3 TRITON_ATTN | PASS |
| #4 No prefix caching | PASS |
| #5 DFlash2 n=7 external spec | PASS |
| #6 Never MTP+DFlash mix | PASS |
| #7 VLLM_USE_V2_MODEL_RUNNER=0 | PASS |

---

## Known Config Difference

* **GMU**: single 0.70 / cluster 0.85 (intended, kept as-is)
* **KV cache dtype**: single `fp8` / cluster `fp8_e4m3` (intentional per-profile difference; not normalized in this run)