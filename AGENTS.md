# AGENTS.md — ai-gb10-cluster-runtime-manager

Rules for any agent/maintainer working in this repo (DGX Spark GB10 runtime manager).

## Facts (don't "fix" these)

- **Two CLIs, both in `bin/`:**
  - `gb10` = **cluster (TP2)** — thin layer over `scripts/tp2-*`. Default target is
    the 2-node cluster; Node0 is the single side of control, Node1 is headless.
  - `gb10-single` = **single-node** runtime manager. `node0` runs compose locally,
    `node1` reaches it over `ssh -i ~/.ssh/id_gb10_cluster eye@10.0.101.102`.
- **`tp2-common.sh` auto-resolves `REPO_DIR`** from its own path — the scripts are
  portable and do NOT need the repo to live at a fixed path. Keep it that way.
- **Compose = source of truth; CLI = convenience layer.** Day-to-day ops go through
  `gb10`/`gb10-single`; compose files under `~/docker-stacks/` are the deploy contract.
- **Cluster profiles (verified 2026-08-30):** 27b = body
  `qwen3.8-27b-aeon-ultimate-uncensored-nvfp4` + drafter `qwen3.8-27b-dflash2` (dflash
  n=7, maxlen 262144, GMU 0.85, num_seqs 8, API :1234); 35b = body
  `qwen3.6-35b-a3b-heretic-nvfp4` + drafter `qwen3.6-35b-a3b-dflash` (n=11, maxlen
  131072, GMU 0.80, num_seqs 16). Both on `:1234` through Node0.
- **Unified LLM endpoint**: all LLM runtimes (TP2 + single, node0 & node1) serve the
  OpenAI API on **port 1234** sharing one `VLLM_API_KEY`. Set the same key in `tp2.env`
  and both nodes' `docker-stacks/aeon-vllm/.env`. TP2 and node0 single LLM share the
  port → they are **mutually exclusive**: `gb10 use` frees node0+node1 singles;
  `gb10-single use/start` on either node tears down TP2 first. `scripts/tp2-smoke/load/
   status` pass the bearer via `api_curl()` (or their own header) when a key is configured.
- **`scripts/tp2-*`**: `up [27b|35b]`, `down`, `status`, `smoke`, `load`. Never edit
  silently — `gb10` just forwards to them.
- **Placeholder runtimes** (`PLACEHOLDER=true` in conf): CLI skeleton only. `gb10` and
  `gb10-single` must print "not deployed yet" and never touch a missing stack.
- **Exclusive groups**: `runtimes.d/*.conf` use `MODE=exclusive` + `GROUP` for isolation
  (llm vs image vs video). `use` switches *within a group*; `start` on an exclusive runtime behaves
  like `use`. This mirrors the legacy behavior — don't rearchitect without a reason.
- **User-approved exception (2026-09-01, MiniMax H3)**: an exclusive `use` frees every OTHER
  active *exclusive* runtime on the same node **across groups** (minimaxh3 `video` vs comfyui
  `image`). Placeholders stay untouched and TP2 is handled by `ensure_tp2_down`, never the
  exclusive stop loop.
- **Secrets**: `tp2.env`, `~/docker-stacks/*/.env`, keys — never commit. `.gitignore`
  covers `tp2.env`, `state/last-runtime`, logs.
- **Node1 doesn't host the repo.** Only Node0. Node1 needs image + model dirs + sudo docker.
- **Cold start** for TP2 is ~7-15 min (weight load + FlashInfer autotune + torch.compile);
  `tp2-up`/`gb10 use` waits for `/health` 200 and reports READY.
- **Prefix caching is DELIBERATELY OFF for the TP2 27B (DFlash2) runtime.** See
  `docs/ADR_2026-09-01_prefix_caching_dflash2.md` for rationale + the pre-requisites
  (vLLM #53479/#52244/#50457/#50897/#53420/#53426) to check before a new image re-enables it.
- **ComfyUI is currently deployed on Node1** as `comfyui-aeon` / Flux 2 Dev. Do not revert it
  to the old `comfyui-personal` / `comfyui-work` split.

## Active implementation task — TP2 profile refactor before DeepSeek V4

Read **`docs/DEEPSEEK_V4_TP2_PROFILE_REFACTOR_HANDOFF_2026-09-04.md` before changing TP2 code.**
It is the authoritative task handoff for the next structural change.

The intent is to make TP2 profiles data-driven before DeepSeek-V4-Flash-0731 is deployed:

```text
cluster-profiles.d/
  27b.conf
  35b.conf
  deepseek.conf   # safe placeholder until image/model validation
```

Key rules for this task:

- Preserve existing 27B and 35B effective launch behavior first; they are the regression controls.
- Move **profile data** out of `scripts/tp2-common.sh::set_profile()` instead of adding another
  large model-specific branch.
- Make the image **profile-scoped**. The current cluster-global `IMG` assumption does not scale to
  the planned DeepSeek-derived AEON image.
- Rank0 and rank1 must consume one authoritative set of model-specific arguments. Do not keep the
  current second hard-coded copy in `scripts/tp2-up`.
- Keep networking/orchestration generic: TP2, SSH, RoCE/NCCL, auth, port 1234 and
  `--disable-custom-all-reduce` remain cluster concerns.
- Model-specific settings (KV dtype, attention/linear/MoE backend, speculative method, parser,
  graph mode, context/concurrency/GMU) belong to the cluster profile.
- `deepseek` is planned as **cluster-only** for DeepSeek-V4-Flash-0731. Do not turn the existing
  `runtimes.d/deepseek.conf` single-node placeholder into a runnable single-node stack.
- Do not build/patch the DeepSeek image in the same structural-refactor change. Planned lineage is:
  base `ghcr.io/aeon-7/aeon-vllm-ultimate:2026-08-24-v0.27.1-omni` -> derived
  `2026-09-04-v0.27.1-omni-ds4flash0731-r1`, with image work handled as a separate follow-up.
- DeepSeek r1 is a correctness/control bring-up (TP2, DSpark off, FP8 KV baseline, PIECEWISE,
  shorter context first). DSpark / longer context belong to later validation, not this refactor.
- Do not claim `deepseek` deployed until both nodes have the intended image/model and a real
  generation has passed.

## Conventions

- Keep `runtimes.d/*.conf` in sync with what's actually deployed on the nodes. A conf
  whose stack/model hasn't landed must be `PLACEHOLDER=true`, not a broken path.
- `comfyui` is the current Node1 Flux 2 Dev runtime. Old `comfyui-personal`/`comfyui-work`
  split is retired — do not resurrect it unless a future design explicitly requires it.
- Scripts are LF, `#!/usr/bin/env bash`, `set -Eeuo pipefail`. No Windows CRLF.
- `.env.example`/`tp2.env.example` are the sanitized templates; never add real keys.
- Structural refactors and model/image patch work should be separate commits/PRs so regression
  ownership is obvious.

## Handoff lineage

Operational history lives in the sibling maintenance repo handoffs
(`GB10_Docker_Stack_Deployment_Handoff_2026-08-2?3.md`, `...08-18.md`, `...08-10.md`)
and this repo's `docs/TP2_DEPLOYMENT_2026-08-30.md` (verified cluster facts).
`docs/RESTRUCTURE_2026-08-31.md` describes this repo's unification.

`docs/ADR_2026-09-01_prefix_caching_dflash2.md` records why TP2 27B prefix caching is off (and when to re-evaluate).

`docs/DEEPSEEK_V4_TP2_PROFILE_REFACTOR_HANDOFF_2026-09-04.md` is the active handoff for making the TP2 profile layer data-driven before DeepSeek-V4-Flash-0731 image/deployment work begins.
