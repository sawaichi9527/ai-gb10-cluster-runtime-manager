# 35B AEON Benchmark Report (Single TP1 vs Cluster TP2)

**Date:** 2026-09-10
**Model:** `qwen3.6-35b-a3b-heretic-nvfp4` (body) + `qwen3.6-35b-a3b-dflash` (drafter, AEON 8L full-attention)
**Image:** `ghcr.io/aeon-7/aeon-vllm-ultimate:2026-08-24-v0.27.1-omni`

---

## Configuration Change (this run vs. previous 35b attempts)

Implements the decided changes so 35b matches the AEON DFlash requirements:

| Item | Before | After | Rationale |
|------|--------|-------|-----------|
| Cluster drafter | z-lab 1222B config | **AEON `qwen3.6-35b-a3b-dflash`** (sha256 `6db5c712...`) | AEON officiable 8L full-attn target layers `[1,10,19,28,37]`; z-lab obsolete |
| Single/cluster KV cache dtype | (unset / fp8) | **`bfloat16`** (single `auto`→bf16; cluster `KV_DTYPE="bfloat16"`) | DFlash non-causal → FA2 only → no FP8 KV |
| Attention backend | (default) | **`flash_attn`** (single & cluster, incl. speculative `attention_backend`) | HF Req #5: DFlash spec decode requires flash_attn |
| MoE backend pin | (auto) | **`VLLM_TEST_FORCE_FP8_MARLIN=1`** | HF Req #6: NVFP4 MoE → MARLIN (defensive) |
| Prefix caching | (cluster only) | OFF (cluster) / ON (single, untouched) | Multi-host DFlash media |
| max-model-len (single) | 229,376 | **262,144** | Test uses ~245k ctx; must fit |
| Image | single node1 hardcoded `2026-08-16-v0.27.1` | **`2026-08-24-v0.27.1-omni`** everywhere | Unify between single & cluster |

> Note: cluster 35b first launch failed with `--kv-cache-dtype: invalid choice: 'bf16'`; fixed to `bfloat16` in `cluster-profiles.d/35b.conf` (vLLM accepts `bfloat16`, not `bf16`).

---

## Test Configuration (effective)

| Parameter | Single (TP1) | Cluster (TP2) |
|-----------|-------------|--------------|
| Tensor Parallel | 1 | 2 (rank0 + rank1) |
| Speculative | DFlash n=11 | DFlash n=11 |
| Attention backend | FLASH_ATTN | FLASH_ATTN |
| KV cache dtype | auto (→bfloat16) | bfloat16 |
| Quantization | compressed-tensors | compressed-tensors |
| MoE backend | MARLIN | MARLIN |
| max-model-len | 262,144 | 262,144 |
| max-num-seqs | 16 | 8 |
| gpu-memory-utilization | 0.60 | 0.80 |
| Prefix caching | ON | OFF |
| max-num-batched-tokens | 32,768 | 16,384 |
| Generation max_tokens | 2,048 | 2,048 |

---

## Concurrency Benchmark (bench-c, MAX_TOKENS=2048)

| C | Single C_total (tok/s) | Single Accept% | Single Mean Len | Cluster C_total (tok/s) | Cluster Accept% | Cluster Mean Len | Speedup |
|---|------------------------|----------------|-----------------|------------------------|-----------------|------------------|---------|
| 1 | 26.6 | 24.1% | 2.65 | 30.0 | 24.2% | 2.67 | 1.13x |
| 2 | 108.9 | 24.1% | 2.66 | 167.3 | 27.9% | 3.07 | 1.54x |
| 3 | 142.6 | 22.6% | 2.48 | 206.5 | 24.1% | 2.65 | 1.45x |
| 4 | 154.5 | 20.9% | 2.30 | 227.1 | 24.2% | 2.66 | 1.47x |
| 8 | 229.2 | 21.8% | 2.40 | 341.9 | 25.0% | 2.75 | 1.49x |

**Observations:**
- Cluster TP2 delivers 1.1x–1.5x throughput, roughly flat acceptance (single 20.9–24.1%, cluster 24.1–27.9%).
- DFlash n=11 acceptance is uniformly lower than 27b's DFlash2 n=7 (24–28% vs 27b cluster 28–38%). Mean accepted length ~2.4–3.1.
- C8 peak: single 229.2 → cluster 341.9 tok/s (1.49x).
- Any errors: 0 throughout.

---

## Long-Context Prefill (bench-ctx, 245,010 tokens, max_tokens=1)

| | Single (TP1) | Cluster (TP2) |
|---|-------------|--------------|
| prompt_tokens | 245,010 | 245,010 |
| wall_time | 97.3s | 61.5s |
| prefill_speed | 2518.7 tok/s | 3986.4 tok/s |
| finish_reason | length | length |

**Observations:**
- 35B is dramatically faster at long-context prefill than 27b (which did 331.6/616.5 tok/s single/cluster) — 7.6x/6.5x faster, likely because 35B is MoE (A3B) with sparse compute.
- Cluster TP2 1.58x faster than single.

---

## Benchmark Notes

- Cluster cold start ~7 min (model load 133s + torch.compile 47s + FlashInfer autotune 88 configs) — similar to 27b.
- Single cold start ~7 min.
- Engine log verification: `Using FlashAttention version 2`, `Using 'MARLIN' NvFp4 MoE backend`, `kv_cache_dtype=bfloat16`, `attention_backend: flash_attn`, world_size=2.