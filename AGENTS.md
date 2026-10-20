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
