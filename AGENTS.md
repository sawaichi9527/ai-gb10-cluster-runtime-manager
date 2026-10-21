# AGENTS.md — ai-gb10-cluster-runtime-manager

Rules for any agent/maintainer working in this repo (DGX Spark GB10 runtime manager).

## Facts (don't "fix" these)

- **Two CLIs, both in `bin/`:**
  - `gb10` = **cluster (TP2)** — thin layer over `scripts/cluster-*`. Default target is
    the 2-node cluster; Node0 is the single side of control, Node1 is headless.
  - `gb10-single` = **single-node** runtime manager. `node0` runs compose locally,
    `node1` reaches it over `ssh -i ~/.ssh/id_gb10_cluster eye@10.0.101.102`.
- **Canonical repo path (fixed 2026-09-09; branch corrected 2026-09-29):** the only live
  checkout is `~/workspace/ai-gb10-cluster-runtime-manager` (branch **`main`** — verified
  on node0 2026-09-29: `git rev-parse --abbrev-ref HEAD` = `main`, upstream `origin/main`,
  clean tree. The older `keystone` branch was merged into `main` at `496c9b1` and is **not**
  the checked-out branch; origin =
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
- **Node-local layout (2026-09-20; vision updated 2026-10-09).** Every runtime's
  node-side artifacts live under `~/docker-stacks/<stack>/`, the stack named after
  the image source: `aeon-vllm-omni` (27b/35b), `anemll-dspark-vllm-gx10` (deepseek),
  `eugr-spark-vllm-b12x` (deepseek-nvfp4), `eugr-spark-vllm-b12x-vision`
  (deepseek-vision, since 2026-10-09; the retired `anemll-dspark-vllm-gx10-miaFlaver`
  is history), `mia-vllm-openai-qwen38flashNext` (qwen38flash). A stack dir holds
  the materialized compose, `patches/` (SYNC_DIRS staging), etc. **Nothing deploys at
  the `~/` root.** Lanes that run BOTH cluster and single (27b/35b) suffix the compose
  `-cluster`/`-single`; cluster-only lanes use `docker-compose.<profile>.yml`.
- **deepseek-vision recipe succession (2026-10-09).** `deepseek-vision.conf` now runs
  `eugr/spark-vllm-b12x:latest` + `models/deepseek-v4-flash-vision-exp-ablit`
  (upstream vision recipe, native vision — NO `CMD_WRAPPER`/`SYNC_DIRS`/patches;
  promoted knob `CUDAGRAPH_CAPTURE=56`; evidence
  `docs/DEEPSEEK_VISION_B12X_RECIPE_AB_2026-10-09.md`). The old Anemll recipe is a
  **backup solution only**: self-contained archive at
  `_overdue_recipe/deepseek-vision_anemll-dspark-vllm-gx10-011_20261009/`
  (byte-identical conf + rendered compose + `patches/dspark-vision/` +
  `recipe_README.md`; migrated from `cluster-profiles.d/_backup/` 2026-10-09 — the
  repo-root dir is never scanned by the loader); restore steps in that
  `recipe_README.md`. **The old official model `models/deepseek-v4-flash-vision-exp`
  stays on BOTH nodes pending a user decision — do not delete it as promotion
  residue.**
- **deepseek mainline recipe succession (2026-10-09).** `deepseek.conf` now runs
  `eugr/spark-vllm-b12x:latest` + `models/deepseek-v4-flash-0731-dspark-ablit`
  (drowzeys `keys-…-Dspark-Abliterated-Anchored-Tensors`; 26 body `wo_b` tensors
  edited, **MTP/draft byte-official** → b12x loader contract holds). Promoted from
  the `deepseek-b12x` candidate lane after the full-recipe A/B beat the README E5
  record: decode Σ **693.3 vs 670.7 (+3.4 %, 8/8 cells positive)**, prefill
  +16..18 % (261K 1947 vs 1648), acceptance 33.4 vs 31.1 % (+2.3 pp), prefix-hit
  **38.5× PASS with NO hotfix** (the SWA-prefix bug does NOT reproduce in the
  eugr fork), soak 3×3 + garble 3/3 + 262K near-limit all PASS; evidence
  `docs/DEEPSEEK_B12X_RECIPE_AB_2026-10-09.md` +
  `docs/evidence/deepseek-b12x-recipe-ab-2026-10-09/`. Deviations from the
  upstream 0731 recipe: `CUDAGRAPH_CAPTURE=64` (formula `seqs*(k+1)` with the
  kept **k=7**) and k=7 itself (upstream ships 5; README baseline is k=7).
  The old Anemll recipe is a **backup solution only**: self-contained archive at
  `_overdue_recipe/deepseek_anemll-dspark-vllm-gx10-011_20261009/` — byte-identical
  `deepseek-anemll.conf` (SHA256 `3147b4e9…`) + rendered compose + its SWA-prefix
  hotfix dependency `patches/dspark-vision/` + `recipe_README.md` (migrated from
  `cluster-profiles.d/_backup/` 2026-10-09); restore steps in that `recipe_README.md`.
  **The old official model
  `models/deepseek-v4-flash-0731-official` stays on BOTH nodes pending a user
  decision — do not delete it as promotion residue.**
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
- **Single launch lane = compose (since 2026-09-20) — plus one opt-in `kit` style.**
  `scripts/cluster-up` renders `docker-compose.yml` per launch from the same profile data
  (`build_vllm_args`/`build_docker_env`); the old docker-run branch was removed. The
  default `LAUNCH_STYLE` is `compose`. A profile may instead declare
  `LAUNCH_STYLE="kit"` (added 2026-10-20 for `dsv41flash-exl3-vllm`), meaning it names
  its own two-node launcher via `KIT_DIR`/`KIT_START`/`KIT_STOP` (and
  `KIT_HEAD_CONTAINER`/`KIT_WORKER_CONTAINER` for status); `cluster-up` then runs that
  launcher, waits for `/health` and writes the ready marker, skipping the compose render,
  the image-manifest gate and the FlashInfer autotune reset. `cluster-down` runs the
  lane's `KIT_STOP` for the last selected kit profile. `SERVED_MODEL` names the id used
  by `gb10 smoke`/`gb10 load`. All kit fields are reset by `load_profile`, so they can
  never leak into a compose lane. Four generic, model-agnostic profile
  fields exist for things the shared builders do not cover: `COMPILATION_JSON` (raw
  `--compilation-config` override), `CAP_ADD=(...)` and `ULIMITS=(NAME=VALUE ...)`
  (compose `cap_add` / `ulimits` extras), and `SECURITY_OPT=(...)` (compose
  `security_opt` entries — e.g. `deepseek-nvfp4` needs `seccomp=unconfined` because
  the Docker default seccomp profile blocks io_uring, which the b12x loader requires;
  upstream eugr hides this behind `--privileged`). All four are no-ops when unset —
  keep it that way so 27b/35b/deepseek stay byte-identical.
  `cluster-compose-verify` treats `SecurityOpt` as a subset match and tolerates
  exactly one Compose-added token: **Compose v5 (v5.0.2) injects
  `security_opt: ["label=disable"]` for any service with `ipc: host`**, which is every
  TP2 lane, and these hosts run apparmor+seccomp only (no SELinux) so it is a no-op.
  Do not "fix" that by declaring `SECURITY_OPT=("label=disable")` in profiles — that
  would change every render; keep the tolerance in the verifier.
- **The two 1017 lanes are PEERS, not primary/backup (user decision 2026-10-21).**
  `dsv41flash-exl3-vllm` (MiaAI vLLM kit) and `dsv41flash-tensorfold` (TensorFold TP2) are
  both first-class lanes: identical registration in `bin/gb10` (usage ×2,
  `PROFILES_BY_NAME`, `list`, `use|start`, `restart`), the same 1017 weights + Engram, and
  the same external id `aeon`. Pick per workload — decode / high concurrency → TensorFold,
  long prefill (≥128K) or a registry image instead of the self-built one → the vLLM kit.
  "現役" in the docs only ever means "the lane that is live right now". They are mutually
  exclusive exactly like every other TP2 lane (each consumes both GB10s and binds `:1234`;
  `gb10-boot-cluster` always runs `cluster-down` + frees the singles first), so do NOT add a
  "fallback" placeholder, a `--force` guard, or any primary/secondary profile field. Both are
  `LAUNCH_STYLE="kit"`, so `cluster-compose-verify` skips them and their boot gate is
  `state/kit.<profile>.rc` (exit code) + `/health` — never "is the launcher process alive".
- **`qwen38flash` (vLLM) and `qwen38flash-tensorfold` (TensorFold) are PEER lanes (2026-10-22).**
  Same checkpoint (`~/docker-stacks/models/qwen3.8-flash-next-nvfp4`, `nvidia/…-NVFP4` @ `fc694b54`,
  25 files / 124 GiB on BOTH nodes — **never delete it as "residue"**, both lanes read it), different
  engines, identical `gb10` registration, mutually exclusive like every TP2 lane. Pick per workload:
  decode / high concurrency / short cold boot → `qwen38flash-tensorfold`; vLLM-only request fields
  (`response_format`/`guided_*`, `logprobs`, `n>1`) → `qwen38flash`. The TF engine **refuses** those
  three with HTTP 400; tools, vision, prompt reuse and `tool_choice:"required"` work.
  - `LAUNCH_STYLE="kit"`: kit dir `~/docker-stacks/mia-TensorFold-qwen38flashNext/` = an upstream
    clone of `MiaAI-Lab/Qwen3.8-Flash-Dual-DGX-Sparks-TensorFold` **pinned at `f8287ef40319` (v1.1)**
    plus `.env` (mode 600, the only settings source). `KIT_START=./start.sh`, `KIT_STOP=./stop.sh`,
    containers `qwen38-fn-tf` on both ranks. **There is no compose file and there must not be one** —
    rank 1 needs rank 0's rendezvous address and the identical argv on the other node.
  - Image `ghcr.io/miaai-lab/qwen3.8-flash-dual-dgx-sparks-tensorfold:zig-db28187-f3e1300f4f62`
    (digest `sha256:e188128d…e18c`, arm64). The checkout pin is load-bearing: prepare.sh compares its
    own `image_hash()` with the image label `tf.patches`; upstream `main` (`6730319e`, "Unreleased")
    hashes differently and would silently trigger a local Zig build.
  - **Three things that will bite** (all measured 2026-10-22):
    (a) `cluster-up`'s kit preflight only checks that the conf's `IMAGE` string exists — after a
    `docker pull`, also `docker tag <ref> tensorfold-qwen38fn:zig-db28187` **and** tag the local name
    with the registry ref, or the boot dies `kit image not present on node0`;
    (b) the checkpoint must be reachable *inside* the container, where `start.sh` mounts `HF_CACHE` at
    `/root/.cache/huggingface` — the bridge is `HF_CACHE=~/docker-stacks/models` plus a **relative**
    symlink `models/hub/models--nvidia--Qwen3.8-Flash-Next-NVFP4/snapshots/fc694b54… -> ../../../qwen3.8-flash-next-nvfp4`
    on both nodes (an absolute symlink dangles in the container);
    (c) `scripts/prepare.sh` needs `MEM_CHECK=0 PULL=0 HF_HUB_OFFLINE=1` when run beside a live TP2
    lane (memory floor is 10 GiB, node1 must not pull over WAN, and the 124 GiB download must not start).
  - Measured same-session A/B (fixed 400 tok, `BENCH_IGNORE_EOS=1`): TF **55.0/82.5/150.3/287.2** tok/s
    at C1/C2/C4/C8 vs vLLM 40.6/42.0/89.5/157.6; cold prefill 3,465/3,240/2,989 vs 2,770/2,809/2,559;
    boot → `/health` **1m53s** vs 13m58s. Details + caveats:
    `docs/QWEN38FLASH_TENSORFOLD_DEPLOY_2026-10-22.md`.
- **`gb10 restart` stops a lane ONCE, and a dead kit launcher now fails fast (2026-10-21, `74ca594`).**
  `restart` runs `cluster-down` synchronously and then passes `--skip-down` to
  `gb10-boot-cluster` (`use`/`start` keep the full teardown) — the second stop used to
  race the first one's container teardown and could relaunch into a name still in use.
  For kit lanes `cluster-down` now waits (≤90 s) until `KIT_*_CONTAINER` really disappears,
  `cluster-up` records the launcher exit code in `state/kit.<profile>.rc` and exits 1 with
  the log tail when it is non-zero, and `restart` exits 1 (instead of printing "launched")
  when the background job dies immediately. Do not "simplify" these away: the kit launcher
  legitimately exits **0** several minutes before `/health`, so liveness must be judged by
  the exit code, never by "is the process still running".
- **Thinking is ON by default on the 1017 lanes (effort 75) — keep it that way (user decision 2026-10-21).**
  The downside is budget, not correctness: a small `max_tokens` is consumed entirely by
  reasoning and the response comes back with `finish_reason=length` and **empty `content`**
  (measured 2/20 at 256 tokens on dsv41flash-tensorfold). Do not disable thinking on the
  service side; clients that need formatted output must allow ≥1024 tokens (or send
  `chat_template_kwargs: {"thinking": false}` themselves). `scripts/bench-1017.py` does the
  latter by default (`--thinking` restores the long path) because a validation run measures
  the format contract, not reasoning.
- **`aeon` is THE external model id (aligned 2026-10-21).** Clients never need to know which
  runtime is live: compose lanes default to `SERVED_MODEL=aeon`, and both 1017 confs now
  declare `SERVED_MODEL="aeon"`. The vLLM kit lane needed a node-side change too —
  `~/docker-stacks/mia-vllm-dsv41flash/.env` `SERVED_MODEL_NAME=aeon` (was the backend name,
  which made `model=aeon` a 404; the pre-change copy is `.env.bak-20261021-134817`).
  `dsv41flash-tensorfold` accepts any id and still *advertises* `deepseek-flash` on
  `/v1/models` because the name is baked into the vendored upstream server (no knob; do not
  patch third-party code for it) — both ids answer, prefer `aeon`.
  Key parsing note: `cluster.env` holds `export VLLM_API_KEY=...` and mentions the same name
  in a comment first, so any parser must skip `#` lines and let the **last** assignment win.
- **`qwen38flash` draft vocab: default is `zh` (measured 2026-10-21), not the upstream 47k.**
  `Q38_DRAFT_VOCAB=en_code_47k|es|zh|ja|de|pt|fr|ru` selects the MTP drafter head for one
  launch. The default is `zh` because the measured Chinese decode gain is large and the
  English control did not move beyond this lane's own boot-to-boot drift
  (`docs/QWEN38FLASH_DRAFT_VOCAB_AB_2026-10-21.md`: zh **+45…61 %** decode, acceptance
  **+30 pp** in all four concurrency cells; the lane's A/A drift upper bound was 0.80–1.32).
  `Q38_DRAFT_VOCAB=en_code_47k` restores the upstream default — use it for English-heavy
  traffic. An unknown value aborts in `load_profile` (fail-closed). It changes **drafting
  only**: `compute_logits` keeps the full 248,320 vocabulary and any draft outside the
  subset is rejected at verification, so replies are bit-identical. The vendored pin is
  upstream `cd839d0b` (2026-09-29, `main` HEAD at the time of writing); all ten patchers are
  byte-identical to it and the seven 65k language vocabularies are the only functional
  addition since `2c86a1d0`. Re-verify with `scripts/bench-draft-vocab.py` (English control,
  `ignore_eos`, `--reps 6` so C=1 also sees every prompt), never with a single arm's tok/s.
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
  active *exclusive* runtime on the same node **across groups** (originally minimaxh3 `video`
  vs comfyui `image`; both retired 2026-10-14, so the live instance is `comfyui-jdaln` `image`
  vs `27b`/`35b` `llm`). Placeholders stay untouched and TP2 is handled by
  `ensure_tp2_down`, never the exclusive stop loop.
- **Secrets**: `~/docker-stacks/config/{cluster,standalone}.env`, `~/docker-stacks/*/.env`,
  keys — never commit. `.gitignore` covers `config/cluster.env`, `state/last-runtime`, logs.
- **DeepSeek is cluster-only.** The legacy single-node `runtimes.d/deepseek.conf`
  placeholder was **retired 2026-09-05**, and `gb10-single list` no longer shows
  `deepseek`. On the TP2 cluster, `cluster-profiles.d/deepseek.conf` is **mainline
  (PLACEHOLDER=false since 2026-09-07)**; since the **2026-10-09 recipe
  succession** it runs `eugr/spark-vllm-b12x:latest` + the dspark-ablit 0731
  checkpoint (see the succession bullet) — previously official fp8 checkpoint +
  public Anemll runtime `ghcr.io/anemll/dspark-vllm-gx10:0.1.1`. Weights at the
  shared pool `~/docker-stacks/models` — `gb10 use deepseek` is a real launch,
  not a placeholder.
- **Node1 doesn't host the repo.** Only Node0. Node1 needs image + model dirs + sudo docker.
- **Cold start** for TP2 is ~7-15 min (weight load + FlashInfer autotune + torch.compile);
  `cluster-up`/`gb10 use` waits for `/health` 200 and reports READY.
- **Prefix caching is DELIBERATELY OFF for the TP2 27B (DFlash2) runtime.** See
  `[REDACTED:entropy:42].md` for rationale + the pre-requisites
  (vLLM #53479/#52244/#50457/#50897/#53420/#53426) to check before a new image re-enables it.
  **This 27B rule does NOT apply to `deepseek`** — see the next bullet.
- **DeepSeek mainline ran E5 on the Anemll image since 2026-10-06 — superseded by
  the 2026-10-09 recipe succession above; this paragraph now documents the BACKUP
  recipe in `_overdue_recipe/deepseek_anemll-dspark-vllm-gx10-011_20261009/deepseek-anemll.conf`** (history +
  evidence `docs/DEEPSEEK_TUNE_AB_2026-10-06.md`). The archived conf has
  `draft_sample_method=probabilistic` (was greedy) **and prefix caching ON**, and
  in THAT recipe prefix caching is **not safe without its hotfix**: `CMD_WRAPPER` runs
  `patches/dspark-vision/hotfix-vllm-dspark-swa-prefix.py` at container start (fail-closed),
  the read-only dir is mounted from `${STACK_DIR}/patches`, and `SYNC_DIRS` stages it on
  **both** nodes (node1 has no repo). Without the hotfix a prefix-cache hit leaves the
  DSpark draft's 128-token sliding window unpopulated and the verifier accepts a
  **truncated** answer. (The promoted eugr-b12x recipe needs no such hotfix — its
  prefix-hit gate passed 38.5× with byte-identical completions.) Measured on the
  Anemll recipe vs its pre-promotion config: decode C1..C8 median sum
  594.2 → **670.7** tok/s (**+12.9 %**, 7/8 cells ≥+10 %), acceptance 26.9 → **31.1 %**
  (**+4.5 pp, 8/8 positive**), warm-prefix prefill **7.6×** (the tune-lane E5 run measured
  655.5 / +10.3 % / 32.1 % / 8.5× — same ballpark), cold prefill/boot/memory unchanged.
  **Production acceptance gate passed 2026-10-07 00:18**: compose-verify on both ranks,
  `gb10 smoke`, 3×3 completeness, 261K long-context (261021 tok @ 1648 tok/s), garble soak
  3/3, `/health` 200.
  Two sibling knobs were measured and **rejected**: `CUDAGRAPH_CAPTURE` 8→128 (E1, +2.1 %
  = noise but +16 s boot + 1.9 GiB graph pool) and `VLLM_USE_BREAKABLE_CUDAGRAPH=0` (E4, −1.5 %).
  Repeatable harness: `scripts/ab-setcell.sh` (single-knob cell apply) +
  `scripts/bench-ab-deepseek.sh` (C1..C8 ×3 medians, cold prefill, engine diag,
  auto Δ-vs-E0) + `scripts/bench-prefix-hit.sh` (warm prefix HIT/no-hit probe with a
  temperature=0 completeness verdict) on `cluster-profiles.d/deepseek-tune.conf`
  (**archived** to `_overdue_recipe/deepseek_anemll-dspark-vllm-gx10-011_20261009/`
  per user decision 2026-10-09 —
  after the succession it is a byte-copy of the OLD Anemll recipe, no longer a
  "production sibling"; a future mainline campaign must branch a NEW lane off
  the promoted recipe + a fresh `.base`).
  Measured noise floor from that campaign: **decode ≈ ±7 %, prefill ≈ ±8 %** — smaller
  deltas are not results.
- **ComfyUI on Node1 = `comfyui-jdaln` only (since 2026-10-14).** It runs
  `jdaln/ComfyUI-DGX-Spark-Docker-opinionated` (self-built image, ComfyUI 0.38.0,
  2811 node types — was 2812 until `ComfyUI-SAM3-DGX-Spark` was blacklisted on
  2026-10-15; see the asset-profile bullet below) under
  `~/docker-stacks/comfyui-dgx-spark/`, UI at `:8188`.
  The legacy `comfyui` lane (`comfyui-aeon` / Flux 2 Dev) was **retired 2026-10-14** —
  stack (~71 GB) + image (26.7 GB) deleted from Node1, `runtimes.d/comfyui.conf` removed.
  Do not resurrect it, and do not bring back the older `comfyui-personal` / `comfyui-work`
  split. Its HF token now lives at `~/docker-stacks/config/hf_token` (mode 600).
  **Remote clients must load models with `UNETLoader` + `CLIPLoader` + `VAELoader` —
  `models/checkpoints/` is intentionally absent** (`CheckpointLoaderSimple` therefore
  returns an empty list; that is not a missing install). **Output width and height must be
  multiples of 16** — anything else is silently padded and not cropped back (1920×1080 delivers
  1920×1088, which letterboxes in a 16:9 slide deck; render 1088 and crop 8 rows). Verified API
  payloads for z-image, MiniMax H3 (i2v/t2v) and Qwen-Image 2.1 (t2i/edit/background-removal,
  plus the measured resolution/quality modes), and the `/prompt` → `/history` → `/view`
  contract, are in `docs/COMFYUI_JDALN_REMOTE_USAGE_GUIDE_2026-10-15.md` (**rev 7**: §0 agent
  TL;DR + decision table, §2/§4/§5/§5b/§5c/§5d payloads, §5.1–§5.3 the MiniMax H3 ladder,
  §9 node0 failover, **§10 presentation-deck workflow**, **§11 model portfolio + how to add a
  family**, **§12 the slide prompt template + the `scripts/comfy-slide.py` helper**).
- **`comfyui-jdaln` asset profiles (expanded 2026-10-15, now **16**).** Node1's
  `ComfyUI-DGX-Spark-Docker-opinionated/.env` (gitignored upstream) sets
  `COMFY_ASSET_PROFILES=` to sixteen profiles — up from the single `z-image-turbo-core`
  the lane launched with: `z-image-turbo-core`, `z-image-turbo-union-control`,
  `frame-interpolation-film`, `lucida-background-removal`, `lotus-depth-support`,
  `ltx-2.5-latent-upscale`, `whisper-subtitles`, `seedvr2-video-upscale`,
  `qwen3-tts-voice-design` (first expansion, ~20 GB), **`qwen-image-2.1-t2i`,
  `qwen-image-2.1-edit`, `qwen-image-2.1-remove-background`** (second, ~33 GB),
  **`flux2-klein-4b-edit`, `qwen-image-layered-core`** (third, ~33 GB as fp8mixed), then
  **`minimax-h3-easy`, `minimax-h3-ref2v`** (fourth, the H3 extensions; `ComfyData/models`
  106 GB → 124 → 173 → 186 → ~222 GB). **Z-Image Base
  (`z_image_bf16.safetensors`, 12.31 GB) is installed as a MANUAL file** — no pack profile
  exists for it (see the guide §10.3), so it is not part of the pack's asset bookkeeping and
  simply travels with the mirror rsync. **Qwen-Image Layered ships as bf16 (40.86 GB) in the
  manifest but is installed as `fp8mixed` (20.53 GB)** with a
  `qwen_image_layered_bf16 → fp8mixed` symlink so the boot bootstrap skips the 40 GB file.
  **The H3 3D latent upscaler's manifest URL is WRONG** (404 → a 15-byte error page); the file
  was fetched from its real path in `LBH-123-AI/Minimax_h3_latent_Upscaler`
  (`minimax_h3_latent_upscaler_3d_conv_v1/…_fp16.safetensors`, 690,592,672 B) and installed under
  the manifest's expected name so the bootstrap skips it.
  The compose reads `.env` twice — for variable substitution AND via `env_file: - .env`
  (line 64) — so every rule below depends on that one file:
  - **`HF_TOKEN` sits on `.env` line 5**, copied from `~/docker-stacks/config/hf_token`
    and reaching the container through the upstream `env_file` key. **The compose file was
    NOT edited**, so this lane still carries only its two pre-existing local divergences
    (the `${COMFY_OUTPUT_DIR:-…}` default and the allowlist default). Never add an
    `HF_TOKEN:` entry under `environment:` — it would create a third divergence for
    something `env_file` already does.
  - **`.env` line 11 `COMFY_NODE_BLACKLIST=ComfyUI-SAM3-DGX-Spark` is deliberately ON.**
    That pack cannot import (`No module named 'comfy_env'`) against the image's baked
    `torch 2.10.0+cu130`; blacklisting silences a per-boot `[ERROR]` and costs exactly
    one node type (2812 → 2811). Do not remove it to "restore" the count — the import
    failure is upstream, not ours.
  - **`Lightricks/LTX-2.5` is `gated: auto`**: `ltx-2.5-latent-upscale`'s two files
    (1.47 GB video VAE + 1.00 GB spatial upscaler) need a one-time "Agree and access
    repository" click in a browser **as the token's account**. A valid-but-un-accepted
    account gets **HTTP 403, not 401** — so a 403 here is NOT a bad token, it means the
    licence was never accepted. `Lightricks/LTX-2` (the LTX 2.0 / 2.3 lanes) is
    `gated: false` and needs nothing.
  - **Adding profiles never re-downloads weights already on disk**:
    `scripts/bootstrap_comfy_assets.sh` `download_if_missing()` returns early on an
    existing file (`if [ -f "$dest" ]; then return 0; fi`). Per-dest `.asset-profile-complete`
    markers apply only to `hf_snapshot`-type assets. The lane's `TIMEOUT="14400"`
    (`runtimes.d/comfyui-jdaln.conf`) is sized for exactly this — a multi-GB WAN pull
    during boot — and the compose healthcheck passes on a running `.part` download so
    the container is not declared unhealthy mid-pull.
  - **Dry-run before adding a profile**:
    `python3 scripts/smoke/plan_downloads.py <profiles…>` — host-side, read-only, skips
    what is present, asks Hugging Face for real sizes, and **exits non-zero on any
    401/403**. Run it on the HOST, not in the container (`/workspace/scripts` is baked
    into the image and is not bind-mounted). Note its "to download" totals are inflated
    on the host: the existence check uses the manifest's raw `/workspace/ComfyUI/models/…`
    paths, which only resolve inside the container — that is a false positive, not a
    real re-download.
- **`comfyui-jdaln` has a failover mirror on Node0 (built 2026-10-14, brought level four
  times 2026-10-15 over CX7).** Node0 holds a copy of the whole lane at
  `~/docker-stacks/comfyui-dgx-spark/` (236 GB, 114,412 files / 16,320 dirs / 9 symlinks,
  byte-identical to node1) plus the image
  `comfyui-dgx-spark-docker-opinionated-comfy:latest`.
  - **It is a MANUAL rsync, not a scheduled job — verify before trusting it.** It fell behind
    four times on 2026-10-15 (asset-profile expansion; Qwen-Image 2.1; Z-Image Base / FLUX.2 Klein
    / Qwen-Image Layered; then the H3 extensions — the last one: **rc=0, 21.68 GB, 447 MB/s**).
    A cleanup on 2026-10-16 removed the pack's stale Git-LFS staging (537 MB) and the intermediate
    `.env.bak-*` files, leaving **114,404 files / 16,320 dirs / 9 symlinks** on both nodes
    (`.env` md5 `f3525434…`). Verify the file/dir/link counts, the `.env` md5 and one >2 GB
    weight's sha256 on **both** nodes before trusting a failover — never assume it is current just
    because it exists.
  - **Node0↔Node1 data movement goes over CX7, always** (`10.0.101.101`↔`10.0.101.102`,
    key `~/.ssh/id_gb10_cluster`, rsync 3.2.7 on both) — not through the Windows host,
    not over the `192.168.23.x` LAN. Both nodes lack passwordless sudo, so every rsync
    runs as `eye`.
  - Stack pulled with `rsync -aHAX --no-o --no-g --delete` — 335 s, ~396 MB/s
    (disk-bound; the NIC has far more headroom). **`--no-o --no-g` is deliberate**: the
    source has exactly one non-`eye` entry (`ComfyUI-DGX-Spark-Docker-opinionated/ComfyUI/user`,
    uid 0), and dropping ownership keeps the mirror free of root-owned files rather than
    reproducing the trap that has bitten this repo twice.
  - Image moved **Node1 → Node0** via `ssh eye@10.0.101.102 'docker save <img>' | docker load`
    (128 s). Get the direction right: Node1 owns the image, so Node1 saves — putting
    `docker save` on Node0 fails with `reference does not exist`.
  - **Verified**: file/dir/symlink counts match exactly on both ends, and a >2 GB
    weight's sha256 (`hunyuan_video_720_fp8_e4m3fn.safetensors` =
    `07ae20b5c60574414c4102bebaec79f3024f5e8db78ae27819b22d0e61d62426`) is identical
    on both. The image differs in *bytes shown* but not in content: Node0 uses the
    classic `overlay2` graph driver (31 layers unpacked, `.Size` 10.28 GB) while Node1
    uses the containerd image store (31 layers compressed, `.Size` 6.87 GB) — the
    diff-ID chains are byte-identical, the `Created`/`Entrypoint`/arch match, and a
    `--entrypoint /bin/sh` smoke test runs (Python 3.12.3, `/workspace` intact). **Do
    not "fix" the image-ID or size mismatch; it is a storage-representation artifact.**
  - **Not boot-tested on Node0** — Node0 was serving the 27b TP2 cluster, and starting
    ComfyUI there contends for the same GB10 GPU. Failover is therefore a manual
    `gb10-single use comfyui-jdaln node0` (`runtimes.d/comfyui-jdaln.conf` has no `NODE`
    field; `gb10-single` takes the node as an argument), not an automatic switch, and it
    requires TP2 down first. Re-mirror with the same rsync line, excluding nothing.
    After the 2026-10-15 re-sync Node0 is at `1.8T used / 1.8T avail / 50%`
    (`46%` before the mirror, `49%` after the initial pull).
  - **Outputs go to `~/Downloads/output/`, not `ComfyData/output/` (since 2026-10-14).**
    The output bind mount lives in the *upstream git-tracked* compose
    (`ComfyUI-DGX-Spark-Docker-opinionated/docker-compose.yml`), and
    `scripts/gb10-single-boot` invokes compose with an explicit `-f "$COMPOSE_FILE"`, so a
    `docker-compose.override.yml` would **not** be auto-loaded — the edit had to go into
    the compose itself, as a defaults-preserving parameter:
    `- ${COMFY_OUTPUT_DIR:-../ComfyData/output}:/workspace/ComfyUI/output`. The actual value
    lives in the gitignored `.env` (`COMFY_OUTPUT_DIR=/home/eye/Downloads/output`) and
    travels with the mirror rsync. Both nodes carry it, and compose+`.env` sha256 match.
    - **The compose file is upstream-tracked and now diverges by 2 lines.** A future
      `git pull` from `jdaln/ComfyUI-DGX-Spark-Docker-opinionated` may conflict here; the
      other local line (a `COMFY_CUSTOM_NODE_EXAMPLE_WORKFLOWS_ALLOWLIST` default) predates
      this change and is redundant with `.env`. Resolve conflicts by keeping
      `${COMFY_OUTPUT_DIR:-../ComfyData/output}`.
    - **`~/Downloads/output/` is OUTSIDE the mirrored tree** (`~/docker-stacks/comfyui-dgx-spark/`),
      so rendered outputs are **not** carried to Node0 by the mirror. That is intentional —
      outputs are regenerable. Both nodes have the dir created and empty.
    - **`ComfyData/output/` is kept, now empty** (it remains the upstream default if
      `COMFY_OUTPUT_DIR` is ever unset), and still holds two empty custom-node dirs
      (`qwen3-tts_voices/`, `exp_data/`) that ComfyUI recreates at startup.
    - The two deployment-test artefacts were deleted from **both** nodes
      (`MiniMax_H3_verify_00001_.mp4` 935,097 B and `z-image_00001_.png` 709,670 B, plus the
      empty `video/` subdir); the mp4 was fetched to the operator's Windows
      `Downloads\` first, sha256-verified identical. Verify any change by
      `docker inspect comfyui` showing `/home/eye/Downloads/output -> /workspace/ComfyUI/output`
      and a writable probe inside the container; after the recreate, `:8188` was READY in
      ~10 s with `health=healthy`.
- **`minimaxh3` retired 2026-10-14.** The vLLM-API MiniMax H3 lane (`:8000`,
  OpenAI-compatible, stack `~/docker-stacks/minimax-h3/` 135 GB + image
  `minimax-h3-dgx-spark:sm121-fp8` 32 GB + `~/Downloads/minimax-h3-output`) was deleted
  **only after** jdaln's native ComfyUI MiniMax H3 nodes were render-verified end-to-end
  (i2v `prompt_id d91692b7`, `status=success`, 204.5 s → `MiniMax_H3_verify_00001_.mp4`;
  record in `docs/COMFYUI_JDALN_DEPLOYMENT_2026-10-14.md`). `runtimes.d/minimaxh3.conf`
  and `src/minimax-h3/` are gone. The sibling `~/docker-stacks/minimax-h3-sglang/`
  was **also removed 2026-10-14** on a follow-up operator instruction: dir 56 GB
  (all of it `models/quantized`) + 2 images ≈ 105 GB, both `Untagged`+`Deleted`
  rc=0, image count 11→9. It was a never-promoted 2026-09-04 SGLang experiment
  with no repo conf, never a lane; three of its weights duplicated what
  `comfyui-jdaln` already had, the rest were SGLang-only conversions (one already
  `.corrupt`). Its `FAILURE_ANALYSIS.md` — the stop-loss record (`audio_vae`
  custom Diffusers class → `ComponentCheckpointUnsupportedError`, not fixable
  within the allowed rules) — was preserved verbatim in `handoff.md` before
  deletion. Nothing under `~/docker-stacks/` matches `sglang` anymore.
  - **Node0's leftovers were also cleared 2026-10-14** (follow-up operator instruction):
    Node0 had been holding its own copies of BOTH retired runtimes — `minimax-h3` 135 GB
    (217 files, newest mtime 2026-09-01 23:17; this was the "failover mirror rsync in
    progress" from the 2026-09-01 deployment) and `comfyui-aeon` 54 GB (3,919 files,
    5,054 non-`eye` entries, newest mtime 2026-07-31 — older than Node1's copy was) —
    plus the image `ghcr.io/aeon-7/comfyui-aeon-spark:slim` 16.8 GB. Both dirs went
    through one in-container `rm` (`rc=0`; `comfyui-aeon` was the root-owned one) and
    the image through `Untagged`+`Deleted` (`rc=0`): **~204 GB reclaimed on Node0**,
    disk `1.8T used / 1.8T avail / 51%` → `1.6T / 2.0T / 46%`. Checked before deleting:
    no repo conf referenced either path, no `state/` marker existed, and no container in
    any state used them.
    `minimax-h3-sglang` never existed on Node0. Node0's `~/docker-stacks/` now has no
    trace of any retired runtime.
  - **One stray container is NOT ours and was left alone**: Node0 has `c0918` in
    `Created` state since 2026-09-18 (`ghcr.io/aeon-7/aeon-vllm-ultimate:2026-09-18-v0.29.0-omni`,
    `cmd=null`, no mounts) — a leftover `docker create` for the AEON runtime, unrelated
    to these retirements.

## TP2 profile refactor (completed 2026-09-05)

The TP2 profile layer is **data-driven** (see `docs/TP2_PROFILE_REFACTOR_VALIDATION_2026-09-05.md`):

```text
cluster-profiles.d/
  27b.conf           # deployed + live-validated (world_size=2, maxlen 262144)
  35b.conf           # deployed + live-validated (world_size=2, maxlen 262144)
  deepseek.conf      # mainline (onboarded 2026-09-07; recipe succession 2026-10-09:
                     # eugr b12x + dspark-ablit; old Anemll recipe in _overdue_recipe/)
  deepseek-vision.conf  # Vision-EXP-ablit on eugr b12x (2026-10-09 recipe succession;
                        # native vision, no hotfixes; old Anemll recipe in _overdue_recipe/)
  qwen38flash.conf   # Qwen3.8 Flash-Next 125B NVFP4 TP2+EP (2026-09-20); official
                     # vllm/vllm-openai:qwen38-flash-next + vendored MiaAI patchers
  deepseek-nvfp4.conf   # DeepSeek-V4-Flash-0731-NVFP4 on eugr/spark-vllm-b12x (built
                        # 2026-10-07, booted 2026-10-08); same name as a retired
                        # unrelated AEON experiment — not a revival
  mimo26flash.conf      # MiMo V2.6 Flash MOPD (MXFP4) TP2 + in-checkpoint DFlash
  deepseek-nvfp4-tune.conf  # single-knob A/B lane for deepseek-nvfp4 (NOT a service;
                            # also has a .conf.base sibling)
  dsv41flash-exl3-vllm.conf # DeepSeek-V4.1-Flash-1017 EXL3 2.9bpw via the MiaAI-Lab
                            # kit (LAUNCH_STYLE=kit; SPEC_METHOD=none; 256K/8)
  dsv41flash-tensorfold.conf # the same 1017 checkpoint on TensorFold TP2 (self-built
                             # image; LAUNCH_STYLE=kit; drafts off; 256K/8)
                            # ^ the two 1017 lanes above are PEER lanes: neither is a
                            #   backup of the other (see the Fact above)
  qwen38flash-tensorfold.conf # Qwen3.8 Flash-Next 125B NVFP4 on MiaAI's TensorFold TP2
                             # recipe (LAUNCH_STYLE=kit; registry image
                             # zig-db28187-f3e1300f4f62; 256K native, no YaRN; 8 at once;
                             # fp8 KV; vision on) — PEER lane of qwen38flash (see the Fact)
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
  **(superseded 2026-10-09 → `eugr/spark-vllm-b12x:latest` + `deepseek-v4-flash-0731-dspark-ablit`;
  the Anemll recipe is archived in `_overdue_recipe/` as a backup only.)**

## Conventions

- Keep `runtimes.d/*.conf` in sync with what's actually deployed on the nodes. A conf
  whose stack/model hasn't landed must be `PLACEHOLDER=true`, not a broken path.
- Keep `cluster-profiles.d/*.conf` in sync with what's actually deployable as a TP2 profile;
  a profile whose image/model hasn't landed must be `PLACEHOLDER=true`.
- **Retired recipes live in repo-root `_overdue_recipe/<profile>_<image+tag>_<yyyymmdd>/`**
  (user decision 2026-10-09; replaced `cluster-profiles.d/_backup/`). Each dir is a
  self-contained bundle: the byte-identical archived conf (+ tune `.base`), the compose
  rendered from it (API key placeholder `<REDACTED:from-cluster.env>`), a copy of
  `patches/dspark-vision/`, and a `recipe_README.md` carrying the recipe's historical
  benchmark record + restore steps. **Docker images and model weights are NOT uploaded
  there** — pins/paths are recorded instead. The loader only scans
  `cluster-profiles.d/*.conf`, so this repo-root dir is never live; restoring a recipe
  means copying its conf (and `patches/dspark-vision/`) back to their repo paths first.
- `comfyui-jdaln` is the current (and only) Node1 ComfyUI runtime since 2026-10-14.
  Both older ComfyUI identities are retired: `comfyui`/aeon/Flux 2 Dev was dismantled
  2026-10-14 (see its bullet above), and the `comfyui-personal`/`comfyui-work` split is
  retired — do not resurrect either unless a future design explicitly requires it.
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
- **Marking a version creates a Release on BOTH remotes (since 2026-10-14).** A pushed
  annotated tag creates only a **tag** — never a Release. A Release is a per-platform
  object that must be POSTed to each host separately, so marking a version on only one
  side silently leaves the other's releases page stale. That went unnoticed for six
  versions: `v1.3.1`…`v1.7.0` were tagged on both hosts, but only GitHub ever received
  the release objects, so Forgejo's page still read `v1.2.0`. For every new version
  create the release on **both** `origin` (Forgejo `http://192.168.23.167:3000`) and
  `github`, with `name` = tag name, `body` = the annotated tag message verbatim,
  `draft=false`, `prerelease=false`, `target_commitish=main`. Get credentials from the
  local store with `git credential fill` (LF-only request file + `cmd /c`) — never write
  them to any file in this repo and never echo them. The 2026-10-14 repair took both
  hosts to 13/13 byte-identical releases (`v1.0.0`…`v1.7.0`); details in `handoff.md`.

## Handoff lineage

Operational history lives in the sibling maintenance repo handoffs
(`[REDACTED:entropy:46]?3.md`, `...08-18.md`, `...08-10.md`)
and this repo's `docs/TP2_DEPLOYMENT_2026-08-30.md` (verified cluster facts).
`docs/RESTRUCTURE_2026-08-31.md` describes this repo's unification.

`[REDACTED:entropy:42].md` records why TP2 27B prefix caching is off (and when to re-evaluate).

`[REDACTED:entropy:56].md` is the (now-completed) handoff that made the TP2 profile layer
data-driven; `docs/TP2_PROFILE_REFACTOR_VALIDATION_2026-09-05.md` records the static + live
validation that closed it.
