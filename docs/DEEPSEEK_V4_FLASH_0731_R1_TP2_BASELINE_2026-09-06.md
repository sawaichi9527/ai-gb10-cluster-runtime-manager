# DeepSeek V4 Flash 0731 — TP2 64K Baseline (2026-09-06)

Live bring-up record. DeepSeek-V4-Flash-0731-NVFP4, frozen AEON r1 image, 2-node TP2 on
DGX Spark GB10 (SM121). Cold start **READY 2026-09-06 08:43:36** (~11 min).

> Serves as the A/B baseline for the next rounds: **64K → 128K → 256K** and **DSpark**
> bring-up. Keep the harness (ds_bench.py) and this record byte-comparable.

## Deployment

- **Launcher**: `bin/gb10 use deepseek` (cluster profile `cluster-profiles.d/deepseek.conf`,
  data-driven via `scripts/tp2-common.sh` loader).
- **Rank1 transport**: rank1 payload is built as a local file
  (`/tmp/tp2-rank1-stdin.sh`, sha256-verified) and piped with `n1 bash -s < file` —
  file-safe, never heredoc-over-ssh.
- **Nodes**: Node0 `spark-25d5` (10.0.101.101, control side) + Node1
  `eye@10.0.101.102` (headless). Unified API on **:1234** with shared
  `VLLM_API_KEY` (auth for all endpoints incl. `/health`).

## Image

- **Tag**: `ghcr.io/aeon-7/aeon-vllm-ultimate:2026-09-04-v0.27.1-omni-ds4flash0731-r1`
- **Pull / content digest**: `ghcr.io/aeon-7/aeon-vllm-ultimate@sha256:37758f115f9fefacb0b7f5b4af015f459f214470c97fb771874446024a9eb27f`
- **Created**: `2026-09-05T12:46:57.873325444+08:00` (identical both nodes)
- **Docker image IDs**: Node0 `sha256:96571d4be9a3c4db28b0e7957a6cc12dc8c5b50afb01709cce9468abff3abc41`,
  Node1 `sha256:37758f…eb27f`
- **Verified equivalent**: identical **27 layers**, identical **full config**
  (Env/Cmd/Entrypoint/Labels/Arch), identical Created. The `.Id` delta is
  history-metadata only, not content.
- Key labels: `com.aeon.profile=ds4flash0731-r1`,
  `com.aeon.deepgemm.commit=8b1392b978f5a03c828dd1711090d7fb50958b8a`,
  `ai.aeon.vllm_base=vLLM 0.27.1 (from-source, sm_121a 3-way merge + 8 cherry-picks)`,
  `ai.aeon.hardware=NVIDIA DGX Spark GB10 SM121`,
  `ai.aeon.slim=rebased onto nvidia/cuda:13.0.2-base-ubuntu22.04 (arm64); 50.6GB->18.3GB`,
  `ai.aeon.features=… flashinfer-0.6.16.post3, torch-2.13.0, triton-3.7.1, nccl-2.30.7,
  fp8-kv, tp2-crossnode-cudagraphs, dspark(…)` (DSpark feature present but OFF this round).

## Model

- **HF repo**: `nvidia/DeepSeek-V4-Flash-0731-NVFP4`
- **HF revision**: `f1caa71142bd0be02f728c79f75042ac1e461579` (from
  `~/.cache/huggingface/hub/models--nvidia--DeepSeek-V4-Flash-0731-NVFP4/refs/main`)
- **Local path (both nodes)**: `~/docker-stacks/aeon-vllm/models/deepseek-v4-flash-0731-nvfp4`
  (170 GB, 48 safetensors shards + `model.safetensors.index.json`, config/tokenizer)
- **config.json**: `model_type=deepseek_v4`, `max_position_embeddings=1048576`
  (native 1M; this round limits to **65536**), weight quant via
  `compressed-tensors` / `deepseek_v4_fp8` (UE8M0 scale format forwarded into DeepGEMM).

## Runtime (in-container, Node0 `pip show`)

| component | version |
|---|---|
| vLLM | `0.27.1+aeon.sm121a.dspark` |
| torch | `2.13.0+cu130` |
| flashinfer-python | `0.6.16.post3` (cubin `0.6.16.post3`, jit-cache `0.6.16.post3+cu130`) |
| triton | `3.7.1` |
| deep_gemm | `2.6.1+8b1392b` (commit `8b1392b978f5a03c828dd1711090d7fb50958b8a`) |
| nvidia-nccl-cu13 (vLLM pynccl) | `2.29.7` (image label `nccl-2.30.7` for system NCCL) |
| nccl4py / torchcodec | `0.4.1` / `0.16.0` |

Verified from runtime logs: `quantization=deepseek_v4_fp8`, DeepGEMM **UE8M0 + E8M0 + PDL**
enabled, `DeepGemmFp8BlockScaledMMKernel` selected, NvFp4 MoE backend **FLASHINFER_CUTLASS**,
vLLM all-reduce via **PYNCCL**, FlashInfer for top-p/top-k sampling.

## TP2 config (effective)

- **world_size = 2** (2×GB10), NCCL init `tcp://10.0.101.101:29501`, backend=nccl,
  `--disable-custom-all-reduce`.
- **KV cache dtype**: `fp8_ds_mla` (accepted on both ranks, process-wide, no fallback).
- **KV cache memory**: `Available KV cache memory: 12.93 GiB` per worker.
- **Context**: `max_model_len=65536`; `--enable-chunked-prefill`; **prefix caching OFF**.
- **Concurrency**: `max_num_seqs=4`, `max_num_batched_tokens=4096`, `gpu-memory-utilization=0.80`.
- **Graph mode**: **PIECEWISE** cudagraph (`compile_ranges_endpoints=[4096]`, capture sizes
  `[1,2,4,8]`); `VLLM_USE_BREAKABLE_CUDAGRAPH=1` → vLLM torch.compile pipeline disabled.
- **EP OFF**: `enable_return_routed_experts=False`.
- **DSpark OFF** (feature present in image; speculative_config=None this round).
- **No drafter, no speculative decode**; tokenizer `deepseek_v4`; dtype bf16.

## Startup

- Cold start **~11 min** (inside the 7–15 min window): `READY 2026-09-06 08:43:36`,
  line `TP2 profile=deepseek READY on :1234` (health wait auto-gate).
- `gb10 status` post-start: `tp2-node0/tp2-node1 Up`, `health: READY`,
  `/v1/models` = `aeon`, `max_model_len=65536`. KV scales to `12.93 GiB` @ 64K.

## Results (all PASS)

### Minimal generation
HTTP 200, `finish_reason=stop`, content `HELLO-TP2-OK` (usage p16/c9). No reasoning preamble.

### Decode (400-token completions, temp 0)

| case | wall | comp_tok | aggregate tok/s | per-user |
|---|---|---|---|---|
| C1 (1×400) | 21.36 s | 400 | **18.73** | ≈ 18.7 |
| C2 (2×400) | 20.41 s | 800 | **39.19** | ≈ 19.6 |
| C4 (4×400) | 23.82 s | 1600 | **67.17** | ≈ 16.8 |

Scaling is clean: aggregate throughput keeps climbing through C4 while per-user rate only
drops ~10% (16.8 vs 18.7) — the right shape for multi-user agentic coding / long context.

### Needle-in-haystack (needle `8349205`, inserted @35% of haystack, presence check)

| target | prompt_tokens | wall | result |
|---|---|---|---|
| 8K | 8234 | 5.6 s | **found** |
| 32K | 32803 | 14.5 s | **found** |
| 60K | 61483 | 28.0 s | **found** |

The 60K case proves the 64K MLA/KV path actually works end-to-end (61.5K prompt tokens in
28.0 s with correct retrieval), not just boot.

## Config reference (effective profile)

`cluster-profiles.d/deepseek.conf`: `IMAGE=2026-09-04-v0.27.1-omni-ds4flash0731-r1`,
`BODY_REL=deepseek-v4-flash-0731-nvfp4`, `DRAF_REL=""` (no drafter),
`MAXLEN=65536`, `NUMSEQ=4`, `BATCHED=4096`, `GMU=0.80`,
`KV_DTYPE=fp8_ds_mla`, `GRAPH_MODE=PIECEWISE`, `SPEC_METHOD=none`,
`ENABLE_CHUNKED_PREFILL=true`, `ENABLE_PREFIX_CACHING=false`.

## Launcher bug fixed this session (generic TP2, not DeepSeek-specific)

`scripts/tp2-up` built the rank1 `docker run` through an UNQUOTED heredoc with
backslash-continuation across physical lines. The drafter mount was wrapped in
`$(if [[ -n "${DRAF:-}" ]]; then printf …; fi)`. For any **no-drafter** profile the
command substitution emits an EMPTY line, which **interrupts the backslash chain** →
`docker run … -v …` with no image → `docker: 'docker run' requires at least 1 argument`.

**Rule (applies to every future no-drafter model):**
> the optional drafter mount must contribute **argv tokens only**; it must **never own
> shell line-continuation syntax**.

Fix: the conditional now emits the mount as whitespace-separated `-v "…"` tokens on the
same physical line as the body mount (`$(if … fi)-v … \`), and the line itself owns the
trailing continuation. Verified dry-run: deepseek (no drafter) and 27B (drafter) both
produce a single, complete `docker run … --entrypoint vllm … serve /model` line.
Live coverage: deepseek (no-drafter branch) ✓ PASS; **27B (with-drafter branch) ✓ PASS**
2026-09-06 — READY 09:33:15; health 200; `/v1/models` `aeon`/`max_model_len=262144`;
smoke 200 `finish_reason=stop` (content produced); launch args confirmed
`speculative_config {method: dflash, num_speculative_tokens: 7, attention_backend:
TRITON_ATTN}` (API-server args + engine `SpeculativeConfig(num_spec_tokens=7)`),
`DFlash2DraftModel` resolved, dflash2 CUDA graphs FULL captured 8/8, 27B profile
effective: maxlen 262144, KV fp8_e4m3, FULL_AND_PIECEWISE, numseq 8, batched 16384.