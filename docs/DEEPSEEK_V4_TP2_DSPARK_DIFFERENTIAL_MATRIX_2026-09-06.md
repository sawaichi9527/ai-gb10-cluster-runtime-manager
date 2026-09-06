# DeepSeek-V4-Flash-0731 TP2 + DSpark — Differential Deployment Study (2026-09-06)

- **Primary objective:** production deployment of DeepSeek-V4-Flash-0731 TP2 with DSpark,
  **sustained C1 > 40 tok/s** on this exact 2× DGX Spark pair. The current AEON K5 result
  (~3.27% acceptance / ~11.6 tok/s) is NOT an acceptable endpoint.
- **Method:** differential study against known-good public TP2 recipes → stage one qualified
  public reference lane on the existing pair with the **exact official
  `deepseek-ai/DeepSeek-V4-Flash-0731`** checkpoint (AEON profile untouched) → pass the gate →
  port differences back into AEON one at a time.
- **Success gate:** acceptance ≥ healthy community range AND sustained C1 > 40 tok/s on a real
  mixed/code workload.

## 1. Our AEON lane (live baseline, for the matrix)

Source: live serve args (verified in-container), `cluster-profiles.d/deepseek.conf` (branch
state), loader audit `DEEPSEEK_V4_DSPARK_LOADER_AUDIT_2026-09-06.md`.

- Checkpoint: `nvidia/DeepSeek-V4-Flash-0731-NVFP4` rev `f1caa71142bd0be02f728c79f75042ac1e461579`
  — **NVFP4 weights** (`quantization_config`: fp4 experts, ue8m0 scales, shared experts ignored)
- vLLM: `0.27.1+aeon.sm121a.dspark` (AEON fork, base v0.27.1)
- Spec: `{"method":"dspark","num_speculative_tokens":5}` — `draft_sample_method` defaults to
  **greedy** (verified in our speculative.py:284); measured acceptance **3.27%** (538/16460)
- EP: off (TP=2 only) · MoE: `auto` · KV: `fp8_ds_mla` block 256
- Graph: `PIECEWISE`, capture `[1,2,4,8,16,24,32,40,48]` (max 48)
- `max_num_seqs 4`, `max_num_batched_tokens 4096`, prefix caching **off**, chunked prefill on, GMU 0.80
- Patches: native topk256 sparse-MLA backport only (loader audit exonerated the draft loader)
- Measured: no-spec r1 C1 **18.7** tok/s; dspark K5 C1 **~11.6** tok/s

## 2. Recipe lineage map

```text
jasl/vllm (SM12x DS4 enablement, PR #41834) ──► hazyumps/deepseek-v4-flash-gb10 (TP2+EP, official 0731)
rafaelcaricio/vllm + local-inference-lab ──► MiaAI-Lab/DeepSeek-v4-Flash-DSpark-2x-DGX-Spark (Vision-Exp)
                                             ├─► Anemll/dspark-vllm-gx10 image (0.1.1, vLLM 0.25.2.dev)
                                             ├─► Weschera/DeepSeek-V4-Flash-0731-DSpark-2x-DGX-Spark (official 0731, pinned)
                                             └─► tonyd2wild 0731-NVFP4 repo (Patches 1/2/2b/3/4, vLLM 0.21.1rc1 overlay)
Keys/drowzeys ──► concurrency + nvfp4_ds_mla wiring (inside Mia/tonyd stacks)
```

## 3. The exact matrix

| Dim | AEON (live) | Weschera 40K speed | Weschera 1M | hazyumps GA | MiaAI-Lab (Vision-Exp) | tonyd2wild 0731-NVFP4 | GroveMinting/eugr |
|---|---|---|---|---|---|---|---|
| checkpoint repo + revision | `nvidia/…-0731-NVFP4` @ `f1caa711…` | **official `deepseek-ai/…-0731` @ `9e165c30…`** + SHA256SUMS manifest gate | same | official 0731 GA (48 shards, ~156–167 GB) | `deepseek-ai/…-Vision-Exp` (+ablit variant) | 0731 official (+ `fraserprice/…-DSpark` preview historically) | official 0731 |
| weight quantization | **NVFP4 weights** (fp4 experts, `deepseek_v4_fp8` compressed-tensors) | official **fp8** (e4m3/ue8m0/block 128) | same | official fp8 | official fp8 | official fp8 weights; NVFP4 only as **KV** path (Stage-C) | official fp8 |
| vLLM / image | AEON fork `0.27.1+aeon.sm121a.dspark` | Anemll `ghcr.io/anemll/dspark-vllm-gx10:0.1.1` (ID `3430d661…`), vLLM `0.25.2.dev0+g752a3a504.d20260714` | same | jasl fork image `hazyumps/deepseek-v4-flash-gb10:sm121-cu130-20260727d`, vLLM `0.1.dev19369+gd64074e6f` (PR #41834) | Anemll 0.1.1 (same image) | `vllm-dspark-runtime:mia-raf-pr1…p2b`, vLLM **0.21.1rc1** (rafaelcaricio lineage) | eugr `vllm-node`, ~`0.26.1rc1` lineage |
| DSpark K + draft sampling | K5, greedy (default) — **3.27% measured** | **K7, greedy — 84.57% measured** | K5, probabilistic | K5, greedy (~0.80 per 4× report) | K6, probabilistic | K5, greedy (patch-4 → 60.2%) | K5 (conservative) |
| EP | off | off (TP=2 only) | off | **on** (TP=2+EP) | off | off | off |
| MoE backend | `auto` (runtime-resolved) | `flashinfer_b12x` (+`VLLM_USE_B12X_MOE=1`) | same | jasl fork native fused DeepGEMM top-k | `flashinfer_b12x` | overlay default (b12x family) | eugr native |
| KV dtype | `fp8_ds_mla` block 256 | `nvfp4_ds_mla` block 256 | same | **fp8** | `nvfp4_ds_mla` block 256 | `nvfp4_ds_mla` (Stage-C, 584-byte envelope) | fp8 |
| graph mode / capture | `PIECEWISE`, capture 1..48 | `--max-cudagraph-capture-size` = seqs×8 = **8** | seqs×6 = 36 | `FULL_AND_PIECEWISE` | FULL-family (Anemll), capture 42→32 | default | default |
| max_num_seqs | 4 | **1** | 6 | 4 | 6 | 12 | 1 |
| max_num_batched_tokens | 4096 | 8192 | 8192 | (see TUNING) | 8192 | 8192 | — |
| prefix caching | **off** | off (speed profile) | on | on (docs) | on (retention interval 4096) | on | — |
| scheduler / Markov / draft patches | native topk256 backport only | none (Anemll-native stack) | none | none (indexer fix native in fork) | Keys mask + hotfixes (#22 nvfp4 long-ctx, #27 long-prefill, #43 sched diag, stops-suppress, spin-wait #79) | Keys concurrency P1/2/2b, P3 cold-start garble, **P4 shared-expert** | topk 256→128 mapping mod; native generic stacked mappings |
| async-scheduling / extras | — | `--async-scheduling`, `--tokenizer-mode deepseek_v4`, `--enable-flashinfer-autotune`, `--generation-config vllm`, tool/reasoning parsers, `VLLM_SPARSE_INDEXER_MAX_LOGITS_MB=256`, `PYTORCH_CUDA_ALLOC_CONF=expandable_segments:True`, NCCL/IB env set | same | NCCL 2.30.4 LD_PRELOAD + RDMA env | compose env set | `/opt/env` venv, shm 64g | eugr launcher env |
| **published result** | C1 11.6 tok/s, 3.27% | **83.8 tok/s median, 84.57% acceptance, 3.09× vs spec-off (1024-prompt/512-out fixture, same output SHA)** | 1M capacity pass (1.79× conc @1M) | 47–60 easy / ~40 mixed, prefill 1.6–1.8k | mixed avg 48.7 (0731 table) | 55.4 mean / 60.2% (K5, NVFP4 KV) | (conservative; no headline) |

## 4. Community healthy ranges (0731 TP2 DSpark)

- Acceptance: **60–92% structured (code/JSON/math), ~40% creative; per-position ≈
  0.83/0.73/0.57/0.47/0.40 (K5)**; K7 greedy measured 84.57% on Weschera's fixture.
- C1 decode: **40–55 tok/s mixed**, 53–67 code (K5); K7 greedy 83.8 on the 40K fixture;
  spec-off floor ≈ 27–31 tok/s.
- Prefill: 1.6–1.8k tok/s (official fp8 weights).

## 5. Differential hypotheses (why AEON sits at 3.27% vs 60–85%)

Ranked by plausibility given the matrix:

1. **Checkpoint variant — NVFP4 *weights* vs official fp8.** No community recipe runs NVFP4
   *weights*; NVFP4 appears only as the **KV** dtype (KV is a context lever, not a speed lever —
   tonyd measured KV dtype throughput-neutral). The drafter's 3×256 routed experts in fp4
   plausibly destroy draft quality → collapsed acceptance. AEON's spec-off floor (18.7) is also
   below the community spec-off floor (27–31), consistent with quant/efficiency differences.
2. **AEON fork's DSpark runtime** (v0.27.1+aeon.sm121a) vs Anemll 0.25.2 / jasl fork — different
   indexer/topk/graph plumbing per fork.
3. Graph mode `PIECEWISE` + capture 48 vs FULL-family/derived capture sizes — speed lever.
4. MoE backend `auto` vs `flashinfer_b12x` / native fused DeepGEMM top-k.
5. Scheduling: seqs 4/batched 4096/prefix-off vs 1/8192/off (speed lane) — throughput shaping.
6. `draft_sample_method` — **excluded**: AEON default is already greedy.

## 6. Reference lane staging (Weschera contract; AEON profile untouched)

Chosen recipe: **Weschera/DeepSeek-V4-Flash-0731-DSpark-2x-DGX-Spark** (MiaAI-Lab/Anemll lineage)
— the only public recipe with (a) the exact official checkpoint pinned to revision
`9e165c30e2704aec5d9d593cce3eebd58bbef1cb` + SHA256SUMS manifest gate, (b) a pinned public image
(`ghcr.io/anemll/dspark-vllm-gx10:0.1.1`, ID `3430d661…`), (c) two qualified modes, and (d)
measured gate-shaped numbers (83.8 tok/s / 84.57%).

Contract to stage:

- **Gate profile (speed):** MODE=dspark7 → `{"method":"dspark","num_speculative_tokens":7,
  "draft_sample_method":"greedy"}`, maxlen 40000, seqs 1, batched 8192, capture 8, prefix off,
  KV `nvfp4_ds_mla`, `--moe-backend flashinfer_b12x`, `--async-scheduling`,
  `--enable-chunked-prefill`, `--tokenizer-mode deepseek_v4`, `--generation-config vllm`,
  `--enable-flashinfer-autotune`, `--distributed-executor-backend mp`, worker-first.
- **Serving profile:** MODE=dspark5 → K5 probabilistic, maxlen 1048576, seqs 6, capture 36,
  prefix on.
- Anemll env set: `VLLM_USE_B12X_MOE=1`, `VLLM_USE_FLASHINFER_SAMPLER=1`,
  `VLLM_SPARSE_INDEXER_MAX_LOGITS_MB=256`, `VLLM_MEMORY_PROFILER_ESTIMATE_CUDAGRAPHS=0`,
  `TORCH_CUDA_ARCH_LIST/FLASHINFER_CUDA_LIST=12.1a`, `CUTE_DSL_ARCH=sm_121a`,
  `DG_JIT_USE_NVRTC=0`, `PYTORCH_CUDA_ALLOC_CONF=expandable_segments:True`,
  `FLASHINFER_WORKSPACE_BASE` mount, plus the RoCE/NCCL set (`NCCL_NET=IB`, IB HCA/GID/timeout
  22/retry 7, `NCCL_CROSS_NIC=1`, `NCCL_CUMEM_ENABLE=0`, `NCCL_NVLS_ENABLE=0`).
- Gates: `sha256sum -c SHA256SUMS` in the checkpoint dir (manifest hash
  `9ab9b79d95289707e7ec23227bf49a142c0174b6334a1fbe5fedd464f7913871`) + image ID
  `sha256:3430d6614a8e2925f34d059af6caf05aff42387326db4d05639a60f10f2654d8`.

Staging status (live):

- [x] Weschera contract extracted (env files + launch_rank.sh fetched byte-wise)
- [x] node0: Anemll image pull started (`/home/eye/b1/pull-anemll.log`)
- [x] node0: official checkpoint download started @ pinned revision →
      `/home/eye/docker-stacks/aeon-vllm/models/deepseek-v4-flash-0731-official` (74 files,
      container `ds4dl`, log `/tmp/dl.log` inside container)
- [ ] manifest verify + image-ID gate after download/pull
- [ ] node1: rsync checkpoint + image pull
- [ ] `tp2-common.sh` minimal generic extension: `SPEC_CONFIG` (raw JSON override), `EXTRA_ENV`,
      `EXTRA_ARGS`, `CUDAGRAPH_CAPTURE` — additive only; existing profiles unchanged
- [ ] `cluster-profiles.d/deepseek-ref.conf` (new; `deepseek.conf` untouched)
- [ ] first live switch (stops the AEON lane — exclusive :1234) → needs explicit go
- [ ] gate measurement: mixed/code C1 sustained + acceptance ≥ community range

## 7. Port-back plan (after the reference lane passes)

One variable at a time into AEON, in this order (highest expected effect first):
1. Official fp8 checkpoint weights (re-quantize later only if needed) — isolates hypothesis 1.
2. Graph mode + capture-size derivation.
3. MoE backend pinning (`flashinfer_b12x` or equivalent) + indexer env.
4. Scheduling knobs (seqs/batched/prefix per workload class).
5. Only then consider upstreaming the AEON DSpark runtime delta vs the winning fork.
