# AGENTS.md — ai-gb10-cluster-runtime-manager

Rules for any agent/maintainer working in this repo (DGX Spark GB10 runtime manager).

## Facts (don't "fix" these)

- **Two CLIs, both in `bin/`:**
  - `gb10` = **cluster (TP2)** — thin layer over `scripts/cluster-*`. Default target is
    the 2-node cluster; Node0 is the single side of control, Node1 is headless.
  - `gb10-single` = **single-node** runtime manager. `node0` runs compose locally,
    `node1` reaches it over `ssh -i ~/.ssh/id_gb10_cluster eye@10.0.101.102`.
- **Canonical repo path (fixed 2026-09-09):** the only live checkout is
  `~/workspace/ai-gb10-cluster-runtime-manager` (branch `keystone`, origin =
  `http://192.168.23.167:3000/829522/ai-gb10-cluster-runtime-manager`). `~/bin/gb10`
  and `~/bin/gb10-single` are symlinks into its `bin/`. The pre-restructure checkout
  `~/ai-gb10-cluster-runtime-manager` was archived to `~/_archieve/` (2026-09-09): its
  `tp2-*` scripts still look for `tp2-node*` containers and would report a false
  `down` against the live `cluster-node*` stacks (plus a stray debug `:` line, fixed
  in `e9d9602`). Do not resurrect it or re-point the symlinks.

- **`cluster-common.sh` auto-resolves `REPO_DIR`** from its own path — the scripts are
  portable and do NOT need the repo to live at a fixed path. Keep it that way.
- **Compose = source of truth; CLI = convenience layer.** Day-to-day ops go through
  `gb10`/`gb10-single`; compose files under `~/docker-stacks/` are the deploy contract.
- **Unified AEON stack dir (2026-09-13; filenames updated 2026-09-20)**: since 27b and 35b both run the v0.29.0-omni image, their composes/models/patches live under one dir `~/docker-stacks/aeon-vllm-omni/` (`docker-compose-27b-{cluster,single}.yml` + `docker-compose-35b-{cluster,single}.yml` + `models/` + `flash_attn_029_patched.py`). `aeon-vllm-reasoning-eos/` is retired.
- **Node-local layout (2026-09-20).** Every runtime's node-side artifacts live under
  `~/docker-stacks/<stack>/`, the stack named after the image source: `aeon-vllm-omni`
  (27b/35b), `anemll-dspark-vllm-gx10` (deepseek), `anemll-dspark-vllm-gx10-miaFlaver`
  (deepseek-vision), `mia-vllm-openai-qwen38flashNext` (qwen38flash). A stack dir holds
  the materialized compose, `patches/` (SYNC_DIRS staging), etc. **Nothing deploys at
  the `~/` root.** Lanes that run BOTH cluster and single (27b/35b) suffix the compose
  `-cluster`/`-single`; cluster-only lanes use `docker-compose.<profile>.yml`.
- **Caches are per-lane and never shared**: `~/.cache/vllm-<profile>` (cluster-only) or
  `~/.cache/vllm-<profile>-{cluster,single}`. The cluster `AUTOTUNE_CACHE_REL` in each
  conf points the per-boot FlashInfer reset at the lane's own root. **Logs are unified**
  under `~/docker-stacks/logs/<profile>/` (boot + compose/container), not per-stack.
- **Cluster profiles are data-driven** (verified 2026-09-05) from `cluster-profiles.d/`
  and loaded by `scripts/cluster-common.sh` (`load_profile`/`build_vllm_args`/`build_docker_env`).
  27b = body `qwen3.8-27b-aeon-ultimate-uncensored-nvfp4` + drafter `qwen3.8-27b-dflash2`
  (dflash n=7, maxlen 262144, GMU 0.85, num_seqs 8, API :1234); 35b = body
  `qwen3.6-35b-a3b-heretic-nvfp4` + drafter `qwen3.6-35b-a3b-dflash` (n=6, maxlen
  262144, GMU 0.80, num_seqs 8). Both on `:1234` through Node0. Do NOT re-hard-code
  profile data in `cluster-*` scripts — the registry is the only authoritative set.
- **Single launch lane = compose (since 2026-09-20).** `scripts/cluster-up` renders
  `docker-compose.yml` per launch from the same profile data
  (`build_vllm_args`/`build_docker_env`); the old docker-run branch was removed. Every
  profile declares `LAUNCH_STYLE="compose"`. Three generic, model-agnostic profile
  fields exist for things the shared builders do not cover: `COMPILATION_JSON` (raw
  `--compilation-config` override), `CAP_ADD=(...)` and `ULIMITS=(NAME=VALUE ...)`
  (compose `cap_add` / `ulimits` extras). All three are no-ops when unset — keep it
  that way so 27b/35b/deepseek stay byte-identical.
- **SGLang launcher removed (2026-09-20).** `build_sglang_args` and every `ENGINE=sglang`
  branch were deleted from `cluster-common.sh`, `cluster-up` and `cluster-compose-verify` —
  the SGLang route was abandoned (it was only ever an early DeepSeek-Vision experiment) and
  no profile ever set `ENGINE=sglang`. `ENGINE` remains as a defaulted field (`vllm`) but is
  effectively fixed. Verified byte-identical renders for all five lanes after the removal.
- **Unified LLM endpoint**: all LLM runtimes (TP2 + single, node0 & node1) serve the
  OpenAI API on **port 1234** sharing one `VLLM_API_KEY`. Set the same key in
  `~/docker-stacks/config/cluster.env` and both nodes' `~/docker-stacks/config/standalone.env`.
  TP2 and node0 single LLM share the
  port → they are **mutually exclusive**: `gb10 use` frees node0+node1 singles;
  `gb10-single use/start` on either node tears down TP2 first. `scripts/cluster-smoke/load/
   status` pass the [REDACTED:bearer-auth:10] `api_curl()` (or their own header) when a key is configured.
- **`scripts/cluster-*`**: `up [27b|35b]`, `down`, `status`, `smoke`, `load`. Never edit
  silently — `gb10` just forwards to them.
- **Lazy sudo**: `scripts/cluster-common.sh` exposes `sudo_pass()` (private `_sudo_pass`).
  It reuses an exported `SUDO_PASS` (from `~/docker-stacks/config/cluster.env`) with no
  prompt; if unset it only prompts interactively and otherwise errors rather than hanging.
  `sdk()`, `cluster-down`, `cluster-status` and the `cluster-up` heredoc all go through
  `sudo_pass()` so they never block on a non-tty password read. Credentials never echo to
  stdout/logs.
- **Placeholder runtimes** (`PLACEHOLDER=true` in conf): CLI skeleton only. `gb10` and
  `gb10-single` must print "not deployed yet" and never touch a missing stack.
- **Exclusive groups**: `runtimes.d/*.conf` use `MODE=exclusive` + `GROUP` for isolation
  (llm vs image vs video). `use` switches *within a group*; `start` on an exclusive runtime behaves
  like `use`. This mirrors the legacy behavior — don't rearchitect without a reason.
- **User-approved exception (2026-09-01, MiniMax H3)**: an exclusive `use` frees every OTHER
  active *exclusive* runtime on the same node **across groups** (minimaxh3 `video` vs comfyui
  `image`). Placeholders stay untouched and TP2 is handled by `ensure_tp2_down`, never the
  exclusive stop loop.
- **Secrets**: `~/docker-stacks/config/{cluster,standalone}.env`, `~/docker-stacks/*/.env`,
  keys — never commit. `.gitignore` covers `config/cluster.env`, `state/last-runtime`, logs.
- **DeepSeek is cluster-only.** The legacy single-node `runtimes.d/deepseek.conf`
  placeholder was **retired 2026-09-05**, and `gb10-single list` no longer shows
  `deepseek`. On the TP2 cluster, `cluster-profiles.d/deepseek.conf` is **mainline
  (PLACEHOLDER=false since 2026-09-07)**: official deepseek-ai fp8 checkpoint +
  public Anemll runtime `ghcr.io/anemll/dspark-vllm-gx10:0.1.1`, weights at the shared
  pool `~/docker-stacks/models` — `gb10 use deepseek` is a real launch, not a placeholder.
- **Node1 doesn't host the repo.** Only Node0. Node1 needs image + model dirs + sudo docker.
- **Cold start** for TP2 is ~7-15 min (weight load + FlashInfer autotune + torch.compile);
  `cluster-up`/`gb10 use` waits for `/health` 200 and reports READY.
- **Prefix caching is DELIBERATELY OFF for the TP2 27B (DFlash2) runtime.** See
  `[REDACTED:entropy:42].md` for rationale + the pre-requisites
  (vLLM #53479/#52244/#50457/#50897/#53420/#53426) to check before a new image re-enables it.
- **ComfyUI is currently deployed on Node1** as `comfyui-aeon` / Flux 2 Dev. Do not revert it
  to the old `comfyui-personal` / `comfyui-work` split.

## TP2 profile refactor (completed 2026-09-05)

The TP2 profile layer is **data-driven** (see `docs/TP2_PROFILE_REFACTOR_VALIDATION_2026-09-05.md`):

```text
cluster-profiles.d/
  27b.conf           # deployed + live-validated (world_size=2, maxlen 262144)
  35b.conf           # deployed + live-validated (world_size=2, maxlen 262144)
  deepseek.conf      # mainline (onboarded 2026-09-07; dspark-vllm-gx10:0.1.1, pool weights)
  deepseek-vision.conf  # Vision-Exp (2026-09-20); SAME image as deepseek + CMD_WRAPPER hotfixes
  qwen38flash.conf   # Qwen3.8 Flash-Next 125B NVFP4 TP2+EP (2026-09-20); official
                     # vllm/vllm-openai:qwen38-flash-next + vendored MiaAI patchers
```

Key rules:

- Preserve existing 27B and 35B effective launch behavior first; they are the regression controls.
- Profile data lives in `cluster-profiles.d/*.conf` only — no hard-coded per-model branch in
  `cluster-common.sh`, and no second copy in `cluster-up`. Rank0 constructs the authoritative argv;
  rank1 receives it as a shell-escaped array (no eval, no serialize+re-eval).
- The image is **profile-scoped** (`IMG` in each conf), so a future DeepSeek-derived AEON image
  can be selected per-profile rather than assuming a single cluster-global `IMG`.
- Networking/orchestration stays generic: TP2, SSH, RoCE/NCCL, auth, port 1234 and
  `--disable-custom-all-reduce` remain cluster concerns.
- Model-specific settings (KV dtype, attention/linear/MoE backend, speculative method, parser,
  graph mode, context/concurrency/GMU) belong to the cluster profile conf.
- **qwen38flash** (2026-09-20) is the first lane whose runtime support is *patched into the image
  at container start*: `patches/qwen38flash/` vendors the MiaAI-Lab patchers (AGPL-3.0, see
  `NOTICE.md`) and `CMD_WRAPPER` applies them in place — no image rebuild. It mounts the 47k
  reduced MTP vocabulary at `/etc/vllm-draft-vocab.txt`, pins `IMG_SHA256`, and declares its own
  `AUTOTUNE_CACHE_REL` (lane-isolated vLLM cache root, since the image enables FlashInfer
  autotune by default). Keep `prepare.sh`/`NOTICE.md` and the image tag in sync.
- The TP2 structural refactor (2026-09-05) originally scoped DeepSeek as a correctness/control
  bring-up; that NVFP4 AEON lane has since been **archived**
  (`~/_archieve/cluster-profiles.d/deepseek-nvfp4.conf`) in favor of the **mainline** DeepSeek
  lane (since 2026-09-07): official deepseek-ai fp8 checkpoint + public Anemll runtime
  `ghcr.io/anemll/dspark-vllm-gx10:0.1.1` (manifest revision 9e165c…, SHA256SUMS-gated;
  gate-passed 40K reference, retuned to the 256KB + DSpark + 8-stream production contract).

## Conventions

- Keep `runtimes.d/*.conf` in sync with what's actually deployed on the nodes. A conf
  whose stack/model hasn't landed must be `PLACEHOLDER=true`, not a broken path.
- Keep `cluster-profiles.d/*.conf` in sync with what's actually deployable as a TP2 profile;
  a profile whose image/model hasn't landed must be `PLACEHOLDER=true`.
- `comfyui` is the current Node1 Flux 2 Dev runtime. Old `comfyui-personal`/`comfyui-work`
  split is retired — do not resurrect it unless a future design explicitly requires it.
- Scripts are LF, `#!/usr/bin/env bash`, `set -Eeuo pipefail`. No Windows CRLF.
- **TP2 FlashInfer autotune cache must be reset before every boot.** It is rank-keyed
  (the persisted `file_key` embeds `tp_rank`/`ep_rank`/`cluster_rank`) and vLLM only
  persists it on world rank 0, then broadcasts that leader-authored file to every rank.
  A follower can never hit those keys, so the ranks profile different tactic counts and
  the per-tactic `dist.all_reduce` deadlocks (rank0 spin-wait, rank1 idle, `/health` never
  ready). `scripts/cluster-up` calls `ensure_autotune_cache_reset` (in `cluster-common.sh`)
  to clear both nodes before launch (`AUTOTUNE_CACHE_POLICY=clear|off`, default `clear`).
  Keeping single-node LLM runtimes on their OWN cache root (`~/.cache/vllm`, `~/.cache/vllm-<id>`,
  never TP2's `vllm-cache`); `gb10-single-boot` warns if a compose violates this.
- `.env.example`/`cluster.env.example` are the sanitized templates; never add real keys.
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
