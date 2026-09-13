# 27B MIXED v3 Benchmark Report (Single TP1 vs Cluster TP2) — v0.29.0

**Date:** 2026-09-13
**Model:** `qwen3.8-27b-aeon-ultimate-uncensored-nvfp4-mixed`
**Image:** `ghcr.io/aeon-7/aeon-vllm-ultimate:2026-09-11-v0.29.0-omni`
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
| VLLM_USE_V2_MODEL_RUNNER | **1 (required)** | **1 (required)** |
| max-model-len | 262,144 | 262,144 |
| max-num-seqs | 8 | 8 |
| max-num-batched-tokens | 16,384 | 16,384 |
| **gpu-memory-utilization** | **0.80** | **0.85** |
| **KV cache dtype** | **`fp8`** | **`fp8_e4m3`** |
| Generation max_tokens | 2,048 | 2,048 |

> v0.29.0 requires `VLLM_USE_V2_MODEL_RUNNER=1` — V1 runner rejects dflash2 in 0.29; V2 whitelists it. This is a change vs the 2026-09-10 run (V2=0).
> Cluster additionally needs 3 patched-file binds (modelopt fold, qwen3_dflash2 layer_type, triton_attn use_mm_prefix); single needs the same 3. See repo AGENTS.md / patch notes.

---

## Concurrency Benchmark (bench-c, MAX_TOKENS=2048)

| C | Single C_total (tok/s) | Single Accept% | Single Mean Len | Cluster C_total (tok/s) | Cluster Accept% | Cluster Mean Len | Speedup |
|---|------------------------|----------------|-----------------|------------------------|-----------------|------------------|---------|
| 1 | 23.3 | 32.2% | 2.26 | 41.0 | 31.7% | 2.22 | 1.76x |
| 2 | 38.3 | 27.0% | 1.89 | 69.0 | 31.5% | 2.21 | 1.80x |
| 3 | 55.0 | 33.7% | 2.36 | 96.2 | 33.5% | 2.34 | 1.75x |
| 4 | 73.9 | 41.8% | 2.93 | 93.8 | 32.7% | 2.29 | 1.27x |
| 8 | 106.7 | 29.9% | 2.09 | 180.8 | 34.2% | 2.39 | 1.69x |

**Per-position acceptance (cluster C1):** pos0 75.3%, pos1 49.3%, pos2 32.0%, pos3 22.2%, pos4 19.7%, pos5 13.5%, pos6 9.8%

**Observations:**
- Cluster TP2 delivers 1.27x–1.80x throughput speedup across all concurrency levels (vs 1.39x–1.68x in v2 run).
- DFlash2 n=7 acceptance: cluster 31.5–34.2%, single 27.0–41.8%. Both functional.
- C8 peak: single 106.7 tok/s → cluster 180.8 tok/s (1.69x).

---

## Long-Context Prefill (bench-ctx, 245,052 tokens, max_tokens=1)

| | Single (TP1) | Cluster (TP2) |
|---|-------------|--------------|
| prompt_tokens | 245,052 | 245,052 |
| wall_time | 705.7s (11.8 min) | 423.5s (7.1 min) |
| prefill_speed | 347.2 tok/s | 578.6 tok/s |
| finish_reason | length | length |

**Observations:**
- Cluster TP2 prefill 1.67x faster (578.6 vs 347.2 tok/s).
- Both handle 245k context correctly (model native max_position_embeddings=262,144).

---

## Regression vs 2026-09-10 (image reasoning-eos → v0.29.0-omni)

| Metric | Single 09-10 | Single 09-13 | Δ | Cluster 09-10 | Cluster 09-13 | Δ |
|---|---|---|---|---|---|---|
| C1 | 19.1 | 23.3 | **+22%** | 31.5 | 41.0 | **+30%** |
| C2 | 43.4 | 38.3 | **−12%** | 68.9 | 69.0 | +0.1% |
| C3 | 54.0 | 55.0 | +2% | 75.2 | 96.2 | **+28%** |
| C4 | 57.8 | 73.9 | **+28%** | 82.5 | 93.8 | +14% |
| C8 | 89.5 | 106.7 | **+19%** | 150.6 | 180.8 | **+20%** |
| Prefill 245k | 331.6 | 347.2 | +5% | 616.5 | 578.6 | −6% |

(deltas are single-run; ±5–10 tok/s noise band applies, per prior handoff §26.4)

---

## Cold Start Times

| | Single | Cluster |
|---|--------|---------|
| Total cold start | ~530s | ~310s (v2 run baseline; v0.29 single autotune fp4_gemm ~150s) |

---

## v0.29.0 Patch Requirements (this run)

| Patch | File (bind) | Reason |
|-------|-------------|--------|
| modelopt fold | `modelopt_029_patched.py` → `vllm/model_executor/layers/quantization/modelopt.py` | image-internal 2-hunk fold regression |
| qwen3_dflash2 layer_type | `qwen3_dflash2_029_patched.py` → `vllm/model_executor/models/qwen3_dflash2.py` | DFlash2N3Qwen3 decoder layer missing `layer_type` kwarg (base passes it) |
| triton_attn use_mm_prefix | `triton_attn_029_patched.py` → `vllm/v1/attention/backends/triton_attn.py` | TritonAttentionImpl must accept `use_mm_prefix` (DFlash sets default False) |

> Both single (docker-compose.27b.yml) and cluster (cluster-profiles.d/27b.conf EXTRA_MOUNTS) mount the same 3 patched files. 35b uses a separate flash_attn patch — see the companion report `docs/BENCHMARK_35B_V029_SINGLE_CLUSTER_2026-09-13.md` (same v0.29.0-omni image, same day).