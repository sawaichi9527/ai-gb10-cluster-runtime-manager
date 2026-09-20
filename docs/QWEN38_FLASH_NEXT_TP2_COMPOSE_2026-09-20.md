# Qwen3.8 Flash-Next TP2 — compose-only lane + qwen38flash rewrite (2026-09-20)

Supersedes `docs/QWEN38_FLASH_NEXT_TP2_VALIDATION_2026-09-07.md` (which targeted
the retired `scripts/tp2-*` layout and the docker-run lane).

## Why

1. The qwen38flash profile was written against the **pre-restructure** loader
   (`QUANT`, `COMPILATION_JSON`, `LOAD_FORMAT`, `SAFETENSORS_LOAD_STRATEGY`,
   `ENABLE_FLASHINFER_AUTOTUNE`, `DISTRIBUTED_EXECUTOR_BACKEND`,
   `EXTRA_DOCKER_ENV`, `DOCKER_RUN_EXTRA`). After the restructure
   (`scripts/cluster-common.sh`), none of those fields are consumed, so the
   profile would have launched with MTP disabled, wrong quantization, and no
   PLE offload / fd limit.
2. Two launch lanes (docker-run in `cluster-up` + compose in
   `cluster-common.sh`) meant every new requirement had to be implemented twice.
   Collapsing to a single compose lane removes that duplication and gives every
   profile the `CMD_WRAPPER` in-container pre-serve hook.

## What changed (this commit)

### Loader — three generic, model-agnostic fields (`scripts/cluster-common.sh`)

| field | effect | unset behaviour |
|---|---|---|
| `COMPILATION_JSON` | raw `--compilation-config` override (verbatim) | falls back to the `GRAPH_MODE` / `PASS_CONFIG` template |
| `CAP_ADD=(...)` | appended to the compose `cap_add:` list (after `IPC_LOCK`) | unchanged |
| `ULIMITS=(NAME=VALUE ...)` | appended to the compose `ulimits:` list (after `memlock`/`stack`) | unchanged |

These are typed (not a raw YAML blob) so they stay validated and reviewable.

### Single lane

* `scripts/cluster-up` — the docker-run branch was deleted; the compose render
  (`render_tp2_compose`) is now unconditional.
* `scripts/cluster-compose-verify` — expected `cap_add` / `ulimits` sets now
  include `CAP_ADD` / `ULIMITS`; default flipped to `LAUNCH_STYLE:-compose`.
* `cluster-profiles.d/27b.conf`, `35b.conf` — now declare `LAUNCH_STYLE="compose"`
  (deepseek / deepseek-vision already did).

### Node0 cleanup (`~/docker-stacks/aeon-vllm-omni/`)

Moved to `~/.archieve/aeon-vllm-omni-cleanup-20260920/`: the three
`docker-compose.27b.yml.bak-*` backups and the orphaned
`modelopt_029_patched.py` / `qwen3_dflash2_029_patched.py` /
`triton_attn_029_patched.py` (referenced only by the superseded `bak-0918`).
Deleted the regenerable pristine extracts `flash_attn_029_orig.py` /
`triton_attn_029_orig.py`. Kept: both live composes, the live
`flash_attn_029_patched.py` (referenced by `35b.conf` and
`docker-compose.35b.yml`), `logs/` (mount target), `models/`.

## Validation

* `bash -n` on all changed scripts/profiles — pass.
* Static regression (committed blob vs working tree, git-bash): `build_vllm_args`
  (rank 0/1), `build_docker_env` (rank 0/1) and `render_tp2_compose` are
  **byte-identical** for 27b / 35b / deepseek / deepseek-vision.
* Positive probe: the new fields emit exactly
  `--compilation-config {"mode":0,"cudagraph_mode":"FULL_DECODE_ONLY"}`,
  `cap_add: [IPC_LOCK, SYS_NICE]`, `nofile: {soft: 1048576, hard: 1048576}`.

## Phase B — qwen38flash on the compose lane (implemented)

Ported from `MiaAI-Lab/Qwen3.8-Flash-Next-Dual-DGX-Sparks` @ `d2f54b7` (AGPL-3.0).

`cluster-profiles.d/qwen38flash.conf` (recipe defaults, full MTP vocabulary):

| field | value |
|---|---|
| `LAUNCH_STYLE` / `ENGINE` | `compose` / `vllm` |
| `IMAGE` | `vllm/vllm-openai:qwen38-flash-next` |
| `MAXLEN`/`NUMSEQ`/`BATCHED`/`GMU`/`NSPEC` | 262144 / 8 / **8192** / **0.835** / 3 |
| `QUANTIZATION` / `KV_DTYPE` | `modelopt` / `fp8_e4m3` |
| `DISABLE_CUSTOM_ALL_REDUCE` | `false` (recipe keeps custom all-reduce) |
| `GRAPH_MODE` / `COMPILATION_JSON` | `FULL_DECODE_ONLY` / `{"mode":0,"cudagraph_mode":"FULL_DECODE_ONLY"}` |
| `SPEC_CONFIG` | `{"method":"mtp","num_speculative_tokens":3}` — internal MTP, **full 248,320 vocab** (no reduced-vocab overlay) |
| `EXTRA_ARGS` | `--mamba-ssm-cache-dtype bfloat16 --load-format safetensors --safetensors-load-strategy lazy --distributed-executor-backend mp --mm-encoder-tp-mode data --enable-expert-parallel --all2all-backend allgather_reducescatter --hf-overrides '{"text_config":{"ple_embedding_dtype":"float8_e4m3fn"}}'` |
| `EXTRA_ENV` | `HF_HUB_OFFLINE=1 TRANSFORMERS_OFFLINE=1 TP_SOCKET_IFNAME=$NCCL_SOCKET_IFNAME NCCL_IB_DISABLE=0 NCCL_IB_AUTO_DETECT=0 NCCL_DEBUG=WARN` |
| `CAP_ADD` | `SYS_NICE` (no extra ulimits; PLE stays on GPU) |
| `SYNC_DIRS` | `patches/qwen38flash` → `$HOME/qwen38flash-patches` (both nodes) |
| `EXTRA_MOUNTS` | the staged patch dir `:ro`, the two patched configs over `/model/{config,hf_quant_config}.json:ro`, and a lane-isolated `$HOME/.cache/vllm-qwen38flash:/root/.cache/vllm` |

**Mechanism.** `CMD_WRAPPER` (single line) copies the vendored patchers and the
image's own vLLM sources into `/tmp/q38patch`, runs the four patchers, writes
the results back over the vLLM package, then `exec vllm serve`. No image
rebuild; idempotent per container start. Verified that all patchers are
`HERE`-relative and take no argv (only read `<HERE>/*.orig`), so the in-container
flow is well-defined.

**Checkpoint facts (measured on Node0, 2026-09-20).** The local checkpoint is a
10-shard repack (plus a separate `model-fp8-mtp-ple.safetensors`), not the
upstream `nvidia/...` 11-shard layout:
* PLE dtype = `float8_e4m3fn` (not declared in `config.json` → injected via `--hf-overrides`)
* MTP MoE quantization = `FP8_BLOCK_SCALES` (supported by the patched dispatch)
* MTP layer-index alias = **required** (`patch_checkpoint_config.py` patches both
  `config.json` and `hf_quant_config.json`)

**One-time prepare (Node0).** `bash patches/qwen38flash/prepare.sh` generates
`config_patched.json` + `hf_quant_config_patched.json` into the patch dir (both
gitignored). Run once before the first launch and after any checkpoint change.

**Vendored (byte-identical, sha256 in `patches/qwen38flash/NOTICE.md`):**
`patch_ple_layer.py`, `patch_modelopt_mxfp8.py`, `patch_modelopt_fp8_block_moe.py`,
`patch_qsa_fp8_kv.py`, `patch_checkpoint_config.py`, `detect_ple_dtype.py`.

`bin/gb10` registers `qwen38flash` (usage, `PROFILES_BY_NAME`, `list`, and both
`use|start` / `restart` case arms).

**Remaining (live):** `bash patches/qwen38flash/prepare.sh` on Node0, then
`gb10 use qwen38flash` → `/health` 200 → `scripts/cluster-compose-verify qwen38flash`.

## Note on live validation

Node0 mutations and validation could not be executed from this session: the
SSH MCP client cannot answer the approval prompt for destructive/privileged
commands or file uploads (read-only and non-recursive commands work). Live
bring-up and `cluster-compose-verify` must be run on Node0.
