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
- **Cluster profiles are data-driven** (verified 2026-09-05) from `cluster-profiles.d/`
  and loaded by `scripts/tp2-common.sh` (`load_profile`/`build_vllm_args`/`build_docker_env`).
  27b = body `qwen3.8-27b-aeon-ultimate-uncensored-nvfp4` + drafter `qwen3.8-27b-dflash2`
  (dflash n=7, maxlen 262144, GMU 0.85, num_seqs 8, API :1234); 35b = body
  `qwen3.6-35b-a3b-heretic-nvfp4` + drafter `qwen3.6-35b-a3b-dflash` (n=11, maxlen
  131072, GMU 0.80, num_seqs 16). Both on `:1234` through Node0. Do NOT re-hard-code
  profile data in `tp2-*` scripts — the registry is the only authoritative set.
- **Unified LLM endpoint**: all LLM runtimes (TP2 + single, node0 & node1) serve the
  OpenAI API on **port 1234** sharing one `VLLM_API_KEY`. Set the same key in `tp2.env`
  and both nodes' `docker-stacks/aeon-vllm/.env`. TP2 and node0 single LLM share the
  port → they are **mutually exclusive**: `gb10 use` frees node0+node1 singles;
  `gb10-single use/start` on either node tears down TP2 first. `scripts/tp2-smoke/load/
   status` pass the [REDACTED:bearer-auth:10] `api_curl()` (or their own header) when a key is configured.
- **`scripts/tp2-*`**: `up [27b|35b]`, `down`, `status`, `smoke`, `load`. Never edit
  silently — `gb10` just forwards to them.
- **Lazy sudo**: `scripts/tp2-common.sh` exposes `sudo_pass()` (private `_sudo_pass`).
  It reuses an exported `SUDO_PASS` (from `tp2.env`) with no prompt; if unset it only
  prompts interactively and otherwise errors rather than hanging. `sdk()`, `tp2-down`,
  `tp2-status` and the `tp2-up` heredoc all go through `sudo_pass()` so they never block
  on a non-tty password read. Credentials never echo to stdout/logs.
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
- **DeepSeek is cluster-only.** `cluster-profiles.d/deepseek.conf` is the **mainline** =
  official deepseek-ai fp8 checkpoint + public Anemll runtime (`ghcr.io/anemll/dspark-vllm-gx10:0.1.1`,
  Weschera lineage), 256KB context + DSpark spec7 + NUMSEQ 8, served model id `aeon` on `:1234`
  (verified live 2026-09-07: `/health` 200, `max_model_len=262144`, 200K prefill 1600 tok/s).
  The retired NVFP4 AEON lane is **archive-only** in `cluster-profiles.d/deepseek-nvfp4.conf`
  (`PLACEHOLDER=true`, safe-fails): its model weights + dedicated AEON images were **physically
  REMOVED from both nodes 2026-09-07** — only the recipe + validation record stay in the repo;
  re-bring-up needs a re-download + rebuilt AEON image. The legacy single-node
  `runtimes.d/deepseek.conf` placeholder was **retired 2026-09-05**; `gb10-single list` no longer
  shows `deepseek`.
- **DeepSeek concurrency benchmark**: `scripts/bench-c.sh <C> [max_tokens]` runs the fixed
  mixed code+JSON prompt at concurrency C (1/2/4/8) with curl+awk only (jq/bc present on Node0;
  `python3 -c`/`pkill -f`/heredoc are unreliable in the run-command client — avoid).
  `scripts/bench-ctx.sh [words] [max_tokens=1]` is the long-context prefill probe (200K measured
  1600 tok/s). Reference C results: C1 35 · C2 46 · C4 57 · C8 86 tok/s (acceptance 24-31%,
  mean accept len 1.7-2.2) — full table in `docs/DEEPSEEK_V4_FP8_MAINLINE_2026-09-07.md`.
- **Node1 doesn't host the repo.** Only Node0. Node1 needs image + model dirs + sudo docker.
- **Cold start** for TP2 is ~7-15 min (weight load + FlashInfer autotune + torch.compile);
  `tp2-up`/`gb10 use` waits for `/health` 200 and reports READY.
- **Prefix caching is DELIBERATELY OFF for the TP2 27B (DFlash2) runtime.** See
  `[REDACTED:entropy:42].md` for rationale + the pre-requisites
  (vLLM #53479/#52244/#50457/#50897/#53420/#53426) to check before a new image re-enables it.
- **ComfyUI is currently deployed on Node1** as `comfyui-aeon` / Flux 2 Dev. Do not revert it
  to the old `comfyui-personal` / `comfyui-work` split.

## TP2 profile refactor (completed 2026-09-05)

The TP2 profile layer is **data-driven** (see `docs/TP2_PROFILE_REFACTOR_VALIDATION_2026-09-05.md`):

```text
cluster-profiles.d/
  27b.conf          # deployed + live-validated (world_size=2, maxlen 262144)
  35b.conf          # deployed + live-validated (world_size=2, maxlen 131072)
  deepseek.conf     # MAINLINE since 2026-09-07: fp8 official + Anemll (256K + DSpark7 + 8-way)
  deepseek-nvfp4.conf  # retired NVFP4 AEON lane (archive-only record; weights+images removed)
```

Key rules:

- Preserve existing 27B and 35B effective launch behavior first; they are the regression controls.
- Profile data lives in `cluster-profiles.d/*.conf` only — no hard-coded per-model branch in
  `tp2-common.sh`, and no second copy in `tp2-up`. Rank0 constructs the authoritative argv;
  rank1 receives it as a shell-escaped array (no eval, no serialize+re-eval).
- The image is **profile-scoped** (`IMG` in each conf), so each model can carry its own
  image (DeepSeek mainline already switched to the public Anemll `dspark-vllm-gx10` image;
  the AEON-derived NVFP4 lane is archived, not deactivated structurally).
- Networking/orchestration stays generic: TP2, SSH, RoCE/NCCL, auth, port 1234 and
  `--disable-custom-all-reduce` remain cluster concerns.
- Model-specific settings (KV dtype, attention/linear/MoE backend, speculative method, parser,
  graph mode, context/concurrency/GMU) belong to the cluster profile conf.
- DeepSeek timeline (completed): r1 64K correctness (DSpark off) → r2 DSpark K5 on the AEON
  NVFP4 image (measured ~3% draft acceptance) → **2026-09-07 mainline switch** to the official fp8 checkpoint + Anemll runtime (verified
  256K prefill 1600 tok/s, C-class acceptance 24-31%). NVFP4 weights + dedicated AEON images
  were **removed from both nodes** the same day (archive-only record); re-bring-up needs a
  re-download + rebuilt image — never claim NVFP4 available until both nodes have the intended
  image/model and a real generation passes.

## Conventions

- Keep `runtimes.d/*.conf` in sync with what's actually deployed on the nodes. A conf
  whose stack/model hasn't landed must be `PLACEHOLDER=true`, not a broken path.
- Keep `cluster-profiles.d/*.conf` in sync with what's actually deployable as a TP2 profile;
  a profile whose image/model hasn't landed must be `PLACEHOLDER=true`.
- `comfyui` is the current Node1 Flux 2 Dev runtime. Old `comfyui-personal`/`comfyui-work`
  split is retired — do not resurrect it unless a future design explicitly requires it.
- Scripts are LF, `#!/usr/bin/env bash`, `set -Eeuo pipefail`. No Windows CRLF.
- `.env.example`/`tp2.env.example` are the sanitized templates; never add real keys.
- Structural refactors and model/image patch work should be separate commits/PRs so regression
  ownership is obvious.

## Handoff lineage

Operational history lives in the sibling maintenance repo handoffs
(`[REDACTED:entropy:46]?3.md`, `...08-18.md`, `...08-10.md`)
and this repo's `docs/TP2_DEPLOYMENT_2026-08-30.md` (verified cluster facts).
`docs/RESTRUCTURE_2026-08-31.md` describes this repo's unification.

`[REDACTED:entropy:42].md` records why TP2 27B prefix caching is off (and when to re-evaluate).

`[REDACTED:entropy:56].md` is the (now-completed) handoff that made the TP2 profile layer
data-driven; `docs/TP2_PROFILE_REFACTOR_VALIDATION_2026-09-05.md` records the static + live
validation that closed it.