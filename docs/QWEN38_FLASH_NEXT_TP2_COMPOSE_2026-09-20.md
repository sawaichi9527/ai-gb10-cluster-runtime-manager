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

Moved to `~/_archieve/aeon-vllm-omni-cleanup-20260920/`: the three
`docker-compose.27b.yml.bak-*` backups and the orphaned
`modelopt_029_patched.py` / `qwen3_dflash2_029_patched.py` /
`triton_attn_029_patched.py` (referenced only by the superseded `bak-0918`).
Deleted the regenerable pristine extracts `flash_attn_029_orig.py` /
`triton_attn_029_orig.py`. Kept: the live `flash_attn_029_patched.py`
(referenced by `35b.conf`), `models/`.

> `~/_archieve/` was itself deleted later the same day (user request); the
> archive contents above are gone. The composes in that dir were renamed
> `docker-compose-27b-single.yml` / `docker-compose-35b-single.yml` in the
> layout pass; the cluster lanes now materialize
> `docker-compose-<profile>-cluster.yml` there. See "Node-local layout" in
> `AGENTS.md`.

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

`cluster-profiles.d/qwen38flash.conf` (recipe defaults; MTP drafts over the
reduced 47k vocabulary, see the A/B below):

| field | value |
|---|---|
| `LAUNCH_STYLE` / `ENGINE` | `compose` / `vllm` |
| `IMAGE` / `IMG_SHA256` | `vllm/vllm-openai:qwen38-flash-next` / manifest `sha256:fc120ece…05bf8` (RepoDigests, identical on both nodes) |
| `MAXLEN`/`NUMSEQ`/`BATCHED`/`GMU`/`NSPEC` | 262144 / 8 / **8192** / **0.835** / 3 |
| `QUANTIZATION` / `KV_DTYPE` | `modelopt` / `fp8_e4m3` |
| `DISABLE_CUSTOM_ALL_REDUCE` | `false` (recipe keeps custom all-reduce) |
| `GRAPH_MODE` / `COMPILATION_JSON` | `FULL_DECODE_ONLY` / `{"mode":0,"cudagraph_mode":"FULL_DECODE_ONLY"}` |
| `SPEC_CONFIG` | `{"method":"mtp","num_speculative_tokens":3,"use_local_argmax_reduction":true}` — internal MTP on the **reduced 47,149-id** vocabulary |
| `EXTRA_ARGS` | `--mamba-ssm-cache-dtype bfloat16 --load-format safetensors --safetensors-load-strategy lazy --distributed-executor-backend mp --mm-encoder-tp-mode data --enable-expert-parallel --all2all-backend allgather_reducescatter --hf-overrides '{"text_config":{"ple_embedding_dtype":"float8_e4m3fn"}}'` |
| `EXTRA_ENV` | `HF_HUB_OFFLINE=1 TRANSFORMERS_OFFLINE=1 TP_SOCKET_IFNAME=$NCCL_SOCKET_IFNAME NCCL_IB_DISABLE=0 NCCL_IB_AUTO_DETECT=0 NCCL_DEBUG=WARN VLLM_MTP_DRAFT_VOCAB=/etc/vllm-draft-vocab.txt VLLM_CACHE_ROOT=/cache/vllm` |
| `CAP_ADD` | `SYS_NICE` (no extra ulimits; PLE stays on GPU) |
| `AUTOTUNE_CACHE_REL` | `.cache/vllm-qwen38flash/flashinfer_autotune_cache` (lane cache root; see the reset note) |
| `STACK_DIR` / `COMPOSE_FILE` | `~/docker-stacks/mia-vllm-openai-qwen38flashNext/` / `docker-compose.qwen38flash.yml` |
| `SYNC_DIRS` | `patches/qwen38flash` → `<STACK_DIR>/patches` (both nodes) |
| `EXTRA_MOUNTS` | the staged `<STACK_DIR>/patches` `:ro`, the two patched configs over `/model/{config,hf_quant_config}.json:ro`, the 47k vocab over `/etc/vllm-draft-vocab.txt:ro`, and the lane cache `~/.cache/vllm-qwen38flash:/cache/vllm` |

**Mechanism.** `CMD_WRAPPER` (single line) copies the vendored patchers and the
image's own vLLM sources into `/tmp/q38patch`, runs the five patchers, writes
the results back over the vLLM package, then `exec vllm serve`. No image
rebuild; idempotent per container start. Verified that all patchers are
`HERE`-relative and take no argv (only read `<HERE>/*.orig`), so the in-container
flow is well-defined. (The pre-flight check ran the same extract→patch sequence
host-side and reproduced upstream's `ple_layer_patched.py` byte-for-byte.)

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
`patch_qsa_fp8_kv.py`, `patch_checkpoint_config.py`, `patch_mtp_draft_vocab.py`,
`detect_ple_dtype.py`, `draft_vocab_en_code_47k.txt`.

`bin/gb10` registers `qwen38flash` (usage, `PROFILES_BY_NAME`, `list`, and both
`use|start` / `restart` case arms).

## Live status (2026-09-20)

Deployed and validated: `prepare.sh` run on Node0, `gb10 use qwen38flash` →
`/health` 200, `scripts/cluster-compose-verify qwen38flash` **PASS on both
ranks**, `gb10 smoke` → `HELLO-TP2-OK`. In-container markers:
`[qwen38flash] in-container patches applied`, `Inductor compilation was
disabled` (mode 0), attention block 1664 (bf16 SSM), PLE runtime FP8 method.
KV pool 34.01 GiB / 4,245,234 tokens (16.19x @ 262144).

### MTP draft-vocabulary A/B (same machine/session, only the vocabulary differs)

| C | full 248,320 vocab | reduced 47k | Δ |
|---|---|---|---|
| 1 | 35.7 | 40.4 | +13.2% |
| 2 | 54.8 | 58.9 | +7.5% |
| 3 | 82.3 | 88.2 | +7.2% |
| 4 | 90.9 | 101.0 | +11.1% |
| 8 | 146.5 | 156.2 | +6.6% |

Acceptance is essentially unchanged (42.8–47.4% vs 44.5–49.8%), and the reduced
drafter lifts the KV pool 33.64 → 34.01 GiB. The lane now defaults to the
reduced vocabulary (MiaAI's recommendation). Medians of 3 repeats per C;
`bench-c` stops early, so single runs vary (C=1 especially).

### Bring-up fixes (all in main)

1. Docker Compose interpolates the whole rendered file, so the `CMD_WRAPPER`'s
   `$W`/`$P` were substituted to empty and the boot died at `mkdir -p ""`.
   Emit `$$` (also fixes the same latent issue in the deepseek-vision prelude).
2. `cluster-compose-verify` did not model the `CMD_WRAPPER` entrypoint/command.
3. Its `||` field separator collided with the wrapper's `|| exit 1`.
4. The lane's autotune cache root was outside `ensure_autotune_cache_reset`
   → added the profile-declarable `AUTOTUNE_CACHE_REL`.
5. That cache dir was created by Docker as root, so `eye` could not rename it
   out of the way → the reset now pre-creates the parent (`mkdir -p`) and both
   nodes were chowned once.

## Note on the earlier tooling constraint

The SSH MCP client used for part of this session cannot answer approval prompts
for destructive/privileged commands or file uploads. This turned out not to
matter: `eye` is in the `docker` group, so non-sudo docker and the live
bring-up were executed directly on Node0. Uploads remain unavailable from that
client; files were transferred via git.
