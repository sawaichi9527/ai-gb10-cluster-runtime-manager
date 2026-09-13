# 35B AEON Benchmark Report (Single TP1 vs Cluster TP2) — v0.29.0

**Date:** 2026-09-13
**Model:** `qwen3.6-35b-a3b-heretic-nvfp4` (body) + `qwen3.6-35b-a3b-dflash` (drafter, AEON 8L full-attention)
**Image:** `ghcr.io/aeon-7/aeon-vllm-ultimate:2026-09-11-v0.29.0-omni`
**Comparison baseline:** 2026-09-10 `docs/BENCHMARK_35B_AEON_BF16_FLASHATTN_2026-09-10.md` (image `2026-08-24-v0.27.1-omni`, DFlash n=6)

---

## Config fix applied before this run (35b only; 27b untouched)

The 35b profile/compose carried a v0.27-era MoE knob that v0.29 no longer recognizes:

| Item | Before | After | Reason |
|------|--------|-------|--------|
| `VLLM_TEST_FORCE_FP8_MARLIN` | `=1` (cluster `EXTRA_ENV` + single compose) | **removed** | v0.29 logs `Unknown vLLM environment variable detected: VLLM_TEST_FORCE_FP8_MARLIN` → ignored. It was added 2026-09-10 for the old n=11 lane. |
| `VLLM_USE_V2_MODEL_RUNNER` | implicit (image `mrv2-default-routing` only) | **`=1` explicit** in cluster profile | Pin V2 like 27b (image default is V2 today, but not contractually). |

- Both single `docker-compose.35b.yml` (Node0 + Node1) and cluster `cluster-profiles.d/35b.conf` now match the 27b counterparts item-for-item.
- Re-boot verification: **0×** `Unknown vLLM environment variable`, `Using V2 Model Runner`, `attention_backend: flash_attn`.

> Note (honesty): the earlier boot that stalled ~26 min at FlashInfer autotune was **not** conclusively caused by this env (v0.29 already ignored it). The clean re-boot completed autotune normally — treat the stall as a one-off autotune wedge, not an env effect; the cleanup is still correct.

---

## Test Configuration (effective, v0.29)

| Parameter | Single (TP1) | Cluster (TP2) |
|-----------|-------------|--------------|
| Tensor Parallel | 1 | 2 (rank0 + rank1) |
| Speculative | DFlash n=6 | DFlash n=6 |
| Spec attention backend | `flash_attn` | `flash_attn` |
| Attention backend | `FLASH_ATTN` | `FLASH_ATTN` |
| KV cache dtype | `bfloat16` | `bfloat16` |
| Quantization | compressed-tensors | compressed-tensors |
| max-model-len | 262,144 | 262,144 |
| max-num-seqs | 8 | 8 |
| max-num-batched-tokens | 16,384 | 16,384 |
| gpu-memory-utilization | 0.80 | 0.80 |
| Prefix caching | ON | ON |
| VLLM_USE_V2_MODEL_RUNNER | **1** | **1** |
| PASS_CONFIG | — (TP1, no cross-rank all-reduce) | `{"fuse_allreduce_rms":false}` |
| FlashInfer allreduce/sampler | — | `VLLM_ALLREDUCE_USE_FLASHINFER=0`, `VLLM_USE_FLASHINFER_SAMPLER=0` |
| Generation max_tokens | 2,048 | 2,048 |

> v0.29 35b needs one patched-file bind: `flash_attn_029_patched.py` → `vllm/v1/attention/backends/flash_attn.py` (accept `use_mm_prefix`). 27b separately needs 3 binds (ModelOpt / DFlash2 / TRITON_ATTN).

---

## Concurrency Benchmark (bench-c, MAX_TOKENS=2048)

| C | Single C_total (tok/s) | Single Accept% | Single Mean Len | Cluster C_total (tok/s) | Cluster Accept% | Cluster Mean Len | Speedup |
|---|------------------------|----------------|-----------------|-------------------------|-----------------|------------------|---------|
| 1 | 76.4 | 35.7% | 2.14 | 113.9 | 40.3% | 2.41 | 1.49x |
| 2 | 121.6 | 36.0% | 2.16 | 199.0 | 44.3% | 2.65 | 1.64x |
| 3 | 134.7 | 32.5% | 1.95 | 249.0 | 40.9% | 2.45 | 1.85x |
| 4 | 171.8 | 36.6% | 2.20 | 273.2 | 42.8% | 2.57 | 1.59x |
| 8 | 269.5 | 36.9% | 2.21 | 402.6 | 38.1% | 2.29 | 1.49x |

**Observations:**
- Cluster TP2 delivers 1.49x–1.85x throughput.
- DFlash n=6 acceptance 32.5–36.9% single / 38.1–44.3% cluster (cluster consistently higher).
- Any errors: 0 throughout.
- C1 is latency-bound and first-generation-after-cold-start — high run-to-run variance; judge throughput on C≥2.

---

## Long-Context Prefill (bench-ctx, 245,010 tokens, max_tokens=1)

| | Single (TP1) | Cluster (TP2) |
|---|-------------|--------------|
| prompt_tokens | 245,010 | 245,010 |
| wall_time | 94.195s | 62.174s |
| prefill_speed | 2601.0 tok/s | 3940.7 tok/s |
| finish_reason | length | length |

> Measured **cold** (container restarted before the run) — 35b single runs `--enable-prefix-caching`, so a repeated identical payload is served at ~8876 tok/s (cache hit), which is not a prefill number. Cluster TP2 prefill 1.52x faster than single.

---

## Regression vs 2026-09-10 (v0.27.1-omni → v0.29.0-omni; both n=6)

| Metric | Single 09-10 | Single 09-13 | Δ | Cluster 09-10 | Cluster 09-13 | Δ |
|---|---|---|---|---|---|---|
| C1 | 29.5 | 76.4 | **+159%** | 26.1 | 113.9 | **+336%** |
| C2 | 100.1 | 121.6 | +21% | 151.5 | 199.0 | +31% |
| C3 | 155.7 | 134.7 | −13% | 197.5 | 249.0 | +26% |
| C4 | 170.9 | 171.8 | +1% | 239.8 | 273.2 | +14% |
| C8 | 267.5 | 269.5 | +1% | 310.6 | 402.6 | +30% |
| Prefill 245k | 2504.1 | 2601.0 | +4% | 3964.2 | 3940.7 | −1% |

**Run-to-run variance:** a second single 35b run on v0.29 (differing only in the removed obsolete env) gave C1 68.4 / C3 152.5 / C4 186.3 / C8 262.9 — i.e. C1–C4 carry a **±10–15% noise band**, while 245k prefill was stable (2599.2 vs 2601.0). Treat ±5–10% (per handoff §26.4) as a floor; C1/C3 span wider.

---

## Patch Requirements (this run)

| Patch | File (bind) | Reason |
|-------|-------------|--------|
| flash_attn use_mm_prefix | `flash_attn_029_patched.py` → `vllm/v1/attention/backends/flash_attn.py` | 0.29 DFlash flash_attn regression — the impl must accept `use_mm_prefix` kwarg |

> Mounted by both single (`docker-compose.35b.yml`) and cluster (`cluster-profiles.d/35b.conf` EXTRA_MOUNTS) from `~/docker-stacks/aeon-vllm-omni/`. 27b is unaffected (TRITON_ATTN + its own 3 binds).

---

## Artifacts

- Single raw: `/tmp/bench35b_single.out` (pre-fix), `/tmp/bench35b_single_v2.out` (aligned re-run), `/tmp/ctx245_single35b.out` (200k), `/tmp/ctx245_single35b_v2.out` (245k warm-cache), `/tmp/ctx245_single35b_cold.out` (245k cold)
- Cluster raw: `/tmp/bench35b_cluster.out` (cold 245k ctx + C1–C8 in one capture)
