# Qwen38Flash TP2 Profile — Bring-up Implementation & Validation (2026-09-07)

> **SUPERSEDED 2026-09-20.** This document describes the pre-restructure
> `scripts/tp2-common.sh` / `scripts/tp2-up` / `bin/gb10` layout and the
> docker-run launch lane. The loader has since been restructured to
> `scripts/cluster-common.sh`, the docker-run lane was removed (compose is now
> the only lane), and the qwen38flash profile is being rewritten against the
> MiaAI-Lab recipe. The loader field names below (`QUANT`, `COMPILATION_JSON`,
> `LOAD_FORMAT`, `SAFETENSORS_LOAD_STRATEGY`, `ENABLE_FLASHINFER_AUTOTUNE`,
> `DISTRIBUTED_EXECUTOR_BACKEND`, `EXTRA_DOCKER_ENV`, `DOCKER_RUN_EXTRA`) no
> longer exist — see `docs/QWEN38_FLASH_NEXT_TP2_COMPOSE_2026-09-20.md`.

Scope: adding the **qwen38flash** TP2 cluster profile (`cluster-profiles.d/qwen38flash.conf`)
for Qwen3.8 Flash-Next 125B NVFP4 on the 2-node cluster, using the official
`vllm/vllm-openai:qwen38-flash-next` image. This records the registry/loader/heredoc
changes, the static regression showing 27B/35B/deepseek byte-identical launch behavior,
and the pre-flight gates still outstanding before the first live deployment.

## Objective

Bring up Qwen3.8 Flash-Next 125B NVFP4 (NVIDIA ModelOpt checkpoint, internal MTP n=3,
no drafter) as a TP2 profile using the **official** vLLM image — without disturbing the
27B/35B regression controls or the DeepSeek placeholder contract. Keep profile data in
`cluster-profiles.d/qwen38flash.conf` only (no hard-coded per-model branches).

## Profile contract (`qwen38flash.conf`)

| field | value | notes |
|---|---|---|
| `IMAGE` | `vllm/vllm-openai:qwen38-flash-next` | profile-scoped; overrides cluster-global IMG |
| `BODY_REL` | `qwen3.8-flash-next-nvfp4` | under `$MODELS_BASE` |
| `DRAF_REL` | *(empty)* | MTP is internal — no drafter mount |
| `MAXLEN` / `NUMSEQ` / `BATCHED` / `GMU` | 262144 / 8 / 16384 / 0.80 | |
| `QUANT` | `modelopt` | vs cluster default `compressed-tensors` |
| `KV_DTYPE` | `fp8_e4m3` | |
| `SPEC_METHOD` | `mtp` | emits `--speculative-config {"method":"mtp","num_speculative_tokens":3,"attention_backend":"FLASH_ATTN"}` with **no** `model` field |
| `NSPEC` | 3 | |
| `GRAPH_MODE` / `COMPILATION_JSON` | `FULL_DECODE_ONLY` / `{"mode":0,...}` | avoids Inductor duplicating the PLE table |
| `LOAD_FORMAT` / `SAFETENSORS_LOAD_STRATEGY` | `safetensors` / `lazy` | 125B lazy load |
| `ENABLE_FLASHINFER_AUTOTUNE` | `false` | NVIDIA recipe |
| `DISTRIBUTED_EXECUTOR_BACKEND` | `mp` | |
| `EXTRA_DOCKER_ENV` | `VLLM_PLE_CPU_OFFLOAD=1` | 51B n-gram table CPU-offloaded |
| `DOCKER_RUN_EXTRA` | `--ulimit nofile=1048576 --cap-add SYS_NICE` | ~128 mmap'd shards |
| parsers / prefill / prefix caching | qwen3 / qwen3_coder / autotool / chunked on / prefix caching off | |

## What changed

| file | change |
|---|---|
| `scripts/tp2-common.sh` | loader `unset` list + `QUANT COMPILATION_JSON LOAD_FORMAT SAFETENSORS_LOAD_STRATEGY ENABLE_FLASHINFER_AUTOTUNE DISTRIBUTED_EXECUTOR_BACKEND EXTRA_DOCKER_ENV DOCKER_RUN_EXTRA`; `build_vllm_args` uses `${QUANT:-compressed-tensors}`, emits optional `--distributed-executor-backend`, `COMPILATION_JSON` or legacy graph fallback, MTP-vs-drafter spec-config (drops the old *AND a drafter* gate so internal methods work), `--load-format`/`--safetensors-load-strategy`/`--no-enable-flashinfer-autotune`; `build_docker_env` appends `EXTRA_DOCKER_ENV` to **both** ranks; `inspect_profile` reports the new fields |
| `scripts/tp2-up` | rank0 docker run splices `DOCKER_RUN_ARGS` (word-split from `DOCKER_RUN_EXTRA`, no-op when empty); rank1 heredoc emits `EXTRA_DOCKER_ENV` (`-e "…"`) + `DOCKER_RUN_EXTRA` before the body mount — trailing-space printf so existing profiles stay byte-identical |
| `bin/gb10` | `qwen38flash` registered (usage, `PROFILES_BY_NAME`, `list`, `use`/`start`, `restart`); stale `glm53flash` placeholder rows removed |
| `cluster-profiles.d/qwen38flash.conf` | new profile (above) |
| `README.md` / `AGENTS.md` | registry + conventions doc the new profile; note the **distinct** single-node `runtimes.d/qwen38flash.conf` (gpt-oss-38b Flash placeholder) is a different model |

### Heredoc mechanics note

The tp2-up rank1 script is an **unquoted** heredoc: `\` + newline is a line continuation,
so the docker-run becomes one remote line. `$(…)` command substitution strips trailing
newlines and its output is not re-scanned, so the first attempt (printf with a trailing
`\\\n`) leaked a stray literal `\` into the generated line. The shipped form uses
**trailing-space printf only** (no backslash):

```bash
$(for _e in ${EXTRA_DOCKER_ENV:-}; do printf '    -e "%s" ' "${_e}"; done)$(if [[ -n "${DOCKER_RUN_EXTRA:-}" ]]; then printf '    %s ' "${DOCKER_RUN_EXTRA}"; fi)$(if [[ -n "${DRAF:-}" ]]; then printf '%s ' '-v "${R_DRAF}:/drafter:ro"'; fi)-v "\${R_BODY}:/model:ro" \
```

Extras splice as whitespace-separated args on the single line; for 27B/35B/deepseek
(`EXTRA_DOCKER_ENV` / `DOCKER_RUN_EXTRA` empty) the emitted remote script is byte-identical
to before.

## Static regression (Node0, feature branch, no nodes touched)

| check | result |
|---|---|
| `bash -n` — `bin/gb10`, `bin/gb10-single`, `scripts/tp2-common.sh`, `tp2-up`, `tp2-down`, `tp2-status`, `tp2-smoke`, `tp2-load`, `cluster-profiles.d/qwen38flash.conf` | pass |
| rank0 `build_vllm_args 0` + `build_docker_env 0` vs `git show HEAD` baseline | **byte-identical** for 27b, 35b, deepseek (r0 and r1) |
| rank1 remote heredoc render vs `git show HEAD` baseline (real `tp2-up` lines 47–70, `node_up` stubbed) | **byte-identical** for 27b, 35b, `deepseek` (real id) |
| qwen38flash rank0 argv | `--quantization modelopt`, `--kv-cache-dtype fp8_e4m3`, MTP spec-config (no drafter), `--compilation-config {"mode":0,"cudagraph_mode":"FULL_DECODE_ONLY"}`, `--load-format safetensors --safetensors-load-strategy lazy`, `--no-enable-flashinfer-autotune`, `--distributed-executor-backend mp`, chunked prefill, no prefix caching, `-e VLLM_PLE_CPU_OFFLOAD=1`, `--ulimit nofile=1048576 --cap-add SYS_NICE` |
| qwen38flash rank1 heredoc render | same extras spliced after memlock line; body/text mount `${R_BODY}:/model:ro`; **no** `/drafter` mount |
| `gb10 list` | 27b / 35b / deepseek / qwen38flash; `glm53flash` gone |
| `gb10 inspect qwen38flash` | resolves image/model; shows `(MTP3)` spec, no placeholder tag |
| `gb10 inspect deepseek` | placeholder safe-fail preserved |

## Pre-flight gates (before live `gb10 use qwen38flash`)

1. **Image on both nodes**: `docker pull vllm/vllm-openai:qwen38-flash-next` on Node0 +
   Node1; confirm an aarch64 (GB10) manifest exists for the tag and the image is
   un-cross-arch. This is an official image, not the planned AEON-derived lineage — the
   DeepSeek image plan in `AGENTS.md` is untouched.
2. **Model download**: `qwen3.8-flash-next-nvfp4` (125B) must exist under
   `~/docker-stacks/aeon-vllm/models/` on **both** nodes. Size/gated-token access to be
   confirmed before starting (this is a gated model); cold start weight load will be long.
3. **Unauthenticated `inspect`** shows `auth: disabled` only if `VLLM_API_KEY=EMPTY`; with
   the unified key set in `tp2.env`, `gb10-smoke`/`load` pass the shared bearer header
   (existing `api_curl` behavior).
4. **Live bring-up**: `gb10 use qwen38flash` → wait `/health` 200 (cold start is long for
   125B) → `gb10 status` (world_size=2, RDMA) → `gb10 smoke` + `gb10 load` (acceptance:
   generation completes; MTP acceptance > 0 in engine metrics).

## Handoff state

Code + static regression complete on `feature/tp2-qwen38-flashnext`.

> **Update 2026-09-20:** the lane was re-implemented on the restructured loader /
> compose lane and is **merged and live** (`gb10 use qwen38flash`). See
> `docs/QWEN38_FLASH_NEXT_TP2_COMPOSE_2026-09-20.md`. The `feature/tp2-qwen38-flashnext`
> branch below is historical and was not merged.
```