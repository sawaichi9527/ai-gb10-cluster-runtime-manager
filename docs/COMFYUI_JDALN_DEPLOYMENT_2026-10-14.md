# ComfyUI (jdaln / DGX-Spark opinionated) Deployment — Node1

**Date:** 2026-10-14
**Runtime:** `comfyui-jdaln` (`runtimes.d/comfyui-jdaln.conf`, GROUP=image, MODE=exclusive)
**Host:** Node1 (192.168.23.216)
**Upstream:** `https://github.com/jdaln/ComfyUI-DGX-Spark-Docker-opinionated`
**Result:** ✅ `http://192.168.23.216:8188` → 200 · ComfyUI **0.38.0** · **2812** node types registered

> This is a **second, independent** ComfyUI runtime on Node1, sitting alongside the
> existing `comfyui` (comfyui-aeon / Flux 2 Dev). Both are `GROUP=image` +
> `MODE=exclusive`, so `gb10-single use` switches between them and frees the other.
> Port 8188 cannot collide because only one exclusive runtime runs at a time.

---

## 1. Why a new runtime instead of replacing `comfyui`

The existing `comfyui` runtime is the aeon-spark lane serving Flux 2 Dev — it is a
working, validated production lane (`docs/ComfyUI_DEPLOYMENT_2026-08-31.md`). The
jdaln fork is a *different* stack (own Dockerfile, own prebuilt aarch64 wheels, 33
custom node packs, multi-workflow template gallery). Replacing would have destroyed
the rollback path for no benefit.

**Decision:** add `comfyui-jdaln` as a new exclusive runtime; keep `comfyui` untouched
as the rollback.

---

## 2. Stack layout (no deploy artifacts at `~/` root)

| Purpose | Path |
|---|---|
| Repo clone + compose | `~/docker-stacks/comfyui-dgx-spark/ComfyUI-DGX-Spark-Docker-opinionated/` |
| Model / user / IO data | `~/docker-stacks/comfyui-dgx-spark/ComfyData/{models,user,input,output}` |
| Boot + compose logs | `~/docker-stacks/logs/comfyui-jdaln/` |
| Runtime conf (in repo) | `runtimes.d/comfyui-jdaln.conf` |

The stack is nested one level under `comfyui-dgx-spark/` because the upstream repo
must live at a directory whose lowercased name equals `PROJECT`; keeping it under a
non-conflicting parent avoids name clash with any future stack.

---

## 3. Clone / build record

- **Clone SHA:** `ef7a677bd1f31242271cde9d21203ca887bcacc6`
- **Submodule:** `ComfyUI @ a5a00900`
- **Build:** rc=0 in **144 s** → image `comfyui-dgx-spark-docker-opinionated-comfy:latest`
  (the upstream compose has `build: .` and **no `image:`** key, so Compose derives the
  tag as `<project>-<service>`; `PROJECT` is pinned to the directory-derived default
  so a manual `docker compose build` produces the same tag).
- **git-lfs:** installed permanently at `~/.local/bin/git-lfs`. **Required** — the
  upstream `DGX-Spark-WheelsBuilder/Wheels/` holds prebuilt aarch64 wheels (flash-attn,
  onnxruntime-gpu, SageAttention) in Git LFS. Without lfs those are pointer files and
  the build silently recompiles from source (hours).

### 3.1 Upstream gap fixed: empty `Wheels/`

The cloned tree had `DGX-Spark-WheelsBuilder/Wheels/` containing only `.gitkeep` —
the LFS content was not present in our checkout. Fixed by copying
`SelfBuiltWheels/*` → `DGX-Spark-WheelsBuilder/Wheels/`.

**Reapply after any upstream `git pull` + rebuild**, or the build regresses to
compiling onnxruntime from source.

---

## 4. Entrypoint stages (all before the HTTP listener)

```
venv create → torch cu130 → /opt wheels → ComfyUI requirements
  → 33 custom node packs (clone + pip install)
  → bootstrap_asset_profiles        ← the long stage
  → python /workspace/ComfyUI/main.py --listen 0.0.0.0 --port 8188 ...
```

There is **no `set -e` and no `trap`**, so a failed step does *not* abort the
entrypoint — a failed `git clone` is merely skipped and the loop continues (except
that a clone hanging on a credential prompt blocks forever, see §5).

---

## 5. Incident: 17.5 h hang on a 404 custom node repo

**Symptom:** pid1 alive 17.5 h, `bootstrap_asset_profiles` never reached, `:8188`
never listening, container disk reads flat.

**Root cause:** `custom_nodes.txt` line 29/33 points at
`https://github.com/Saganaki22/ComfyUI-VDN-H3.git`, which returns **404**. `git clone`
fell back to a credential prompt on the container's open stdin
(`wchan=anon_pipe_read`, `read_bytes=0`).

**Fix (order matters):**

```bash
rm -rf <partial-dir>                              # 1. remove the partial clone FIRST
pkill -9 -f 'ComfyUI-VDN-H3[.]git'                # 2. then kill the hung git
# 3. comment the dead line in custom_nodes/custom_nodes.txt
```

The order matters: killing first lets the loop's *next* iteration re-issue the clone
and re-hang.

The line is now commented out in `custom_nodes/custom_nodes.txt:56`. That edit is
safe only *after* the entrypoint's read loop has completed — editing mid-loop shifts
the fd offset, which is why it was deferred until after first boot.

---

## 6. Bug fixed and shipped: false READY on health timeout

`scripts/gb10-single-boot` could write the `boot-ready.<node>.<runtime>` marker
**even when the health probe never succeeded**, so `gb10-single wait` reported READY
while `:8188` was dead. This bit us directly during §5 (stale marker
`state/boot-ready.node1.comfyui-jdaln` claiming READY at `2026-10-12 21:52:30`).

**Fix:** commit **`537c64e`** — "fix(gb10-single-boot): never mark READY on a health
timeout" (+14/−2). A `_ready` flag is set only on a real probe success; a zero flag
after the loop now `exit 1` instead of falling through, and the in-loop timeout
branch merely `break`s.

- `bash -n` passed; both simulation scenarios (probe succeeds / probe never succeeds)
  tested.
- Pushed to origin + github, pulled on node0, `check-git-sync` = SYNC_OK.
- The stale false marker was deleted on node0.

---

## 7. Asset download: the scope explosion, and how it was cut

### 7.1 What was expected vs what happened

First deployment chose asset profile **`z-image-turbo-core`** (3 files, 19.27 GiB).

The actual expansion came from `.env` carrying an **uncommented**
`COMFY_CUSTOM_NODE_EXAMPLE_WORKFLOWS_ALLOWLIST`. The bootstrap helper does:

```python
profiles = [p for p in COMFY_ASSET_PROFILES.split(",") ...]      # z-image-turbo-core
for module in effective_modules:                                  # 6 allowlisted packs
    profiles.extend(module_profile_map.get(module, []))           # → +2 profiles
```

so the effective set became `['z-image-turbo-core', 'leapfusion-hunyuanvideo-i2v',
'minimax-h3-easy']` — **93 GiB** instead of 19.27 GiB.

Then stage ② hit: the helper walks each allowlisted pack's `example_workflows/*.json`,
parses `widgets_values`, and downloads **every model reference it can resolve to a URL**.
118 workflow JSONs → **204 model references**. Of those, 54 resolved by direct HF URL;
9 were already on disk, leaving **45 files / 174 GiB ≈ 8.8 h** — a floor, not a ceiling,
because the WanVideoWrapper pack resolves through the helper's *repo-candidate* path
(97 refs, not fully quantified) rather than direct URLs.

Disk measured at that moment: **111 GiB already written**, 1.5 T free.

### 7.2 Three traps found before editing

1. **The default is not in `.env`.** `.env`'s allowlist line is a *comment*; the real
   default sits in `docker-compose.yml:49` as `${VAR:-ComfyUI-WanVideoWrapper,...}`.
   Commenting `.env` would have been a no-op.
2. **`${VAR:-}` treats empty as unset**, so setting the var to empty in `.env` would
   still fall back to the 6-pack default. The compose line had to become `${VAR-}`.
3. **`UPDATE_DEPS=true`** makes the entrypoint `git pull` every pack on restart — 32
   packs over the ~150 KB/s GitHub link we measured, each one a fresh chance to hang
   on a since-deleted remote.

### 7.3 The trim (user decision: "砍 ALLOWLIST，先讓服務上線")

| File | Change |
|---|---|
| `custom_nodes/custom_nodes.txt:56` | commented the dead 404 VDN-H3 URL |
| `docker-compose.yml:49` | `${VAR:-<6 packs>}` → `${VAR-}` (default removed) |
| `.env` | `UPDATE_DEPS=false`, `COMFY_CUSTOM_NODE_EXAMPLE_WORKFLOWS_ALLOWLIST=` (empty) |

With an empty explicit allowlist and `COMFY_CUSTOM_NODE_MODULES_ALLOWLIST=true`, the
helper's emit function hits `raise SystemExit(0)` before it ever consults
`selection_metadata` → `effective_modules` is empty → **no workflow JSON is scanned**.
`profiles` still holds `z-image-turbo-core`, but those 3 files are already on disk and
`download_if_missing` skips them.

### 7.4 Result

```
2026-10-14 00:13:46  background boot started (PID 1676144)
2026-10-14 00:14:32  READY
```

**46 seconds** from `use` to READY, versus the 9–15 h the untrimmed path would have
taken. 111 GiB of already-fetched models were preserved (nothing deleted).

To re-enable a workflow gallery later: put the pack names back on the `.env` line and
flip `UPDATE_DEPS` back to `true`. Downloads are idempotent (`download_if_missing`
skips existing files), so nothing already fetched is repeated.

---

## 8. Verification (2026-10-14 00:21)

| Check | Result |
|---|---|
| container | `status=running health=healthy restarts=0` |
| `GET http://127.0.0.1:8188/` | **200** |
| `GET http://192.168.23.216:8188/` | **200** |
| `/system_stats` | ComfyUI **0.38.0**, frontend 1.53.10, templates 0.11.76 |
| `/object_info` | **2812** node types registered |
| `gb10-single status node1` | `comfyui-jdaln  exclusive image  running  READY` |
| `state/boot-ready.node1.comfyui-jdaln` | written 00:14:32 by the **fixed** boot script |
| disk `ComfyData` | 106 G, 1.5 T free |
| GPU | GB10; `nvidia-smi` reports `[N/A]` memory (driver quirk on this platform) |

`z-image-turbo-core` (the profile chosen for this deployment) — all three present:

```
OK  diffusion_models/z_image_turbo_bf16.safetensors   12GiB
OK  text_encoders/qwen_3_4b.safetensors               7.5GiB
OK  vae/ae.safetensors                                320MiB
```

### 8.0 Render smoke test — PASSED

A real z-image turbo text-to-image job was queued through `POST /prompt` (the exact
graph from `ComfyUI-Simple-Prompt-Batcher/examples/z-image_simple_prompt_batcher.json`,
converted to API format):

| Param | Value |
|---|---|
| loader | `UNETLoader` `z_image_turbo_bf16.safetensors` + `CLIPLoader` `qwen_3_4b` (`type=lumina2`) + `VAELoader` `ae.safetensors` |
| sampling | `ModelSamplingAuraFlow` shift 3 → `EmptySD3LatentImage` 1024×576 → `KSampler` **4 steps, cfg 1, res_multistep / simple**, denoise 1 |
| prompt | `a room with neon light, a teddybear` |

```
POST /prompt  → {"prompt_id":"3c6f7ee4-228e-43a7-b5aa-4f871cc2297d","node_errors":{}}
history       → status: success  completed: True   (no execution_error)
output        → ComfyData/output/z-image_00001_.png  (709,670 bytes, valid PNG)
```

~30 s end-to-end (3 poll intervals). This exercises model load + text encode + sampling +
VAE decode + disk write, i.e. the whole pipeline, not just the HTTP listener.


### 8.1 Known caveat: `ComfyUI-SAM3-DGX-Spark` fails to import

The pack's `requirements.txt` pins `comfy-env==0.2.61` / `comfy-3d-viewers==0.2.41`.
**`0.2.61` no longer exists on PyPI** — the oldest published `comfy-env` is `0.3.0`
(latest `0.4.46`). The prestartup script therefore cannot install it, and
`__init__.py` (`from comfy_env import register_nodes`) raises → the whole pack is
skipped. Log line: `ComfyUI-SAM3-DGX-Spark/prestartup_script.py / No module named 'comfy_env'`.

**Impact: none on the SAM3 nodes themselves.** All 11 `SAM3_*` node types in
`/object_info` carry full specs and are registered by ComfyUI **core**, not by the
pack:

```json
"python_module": "comfy_extras.nodes_sam3d_body"
```

`ComfyUI-BFSNodes/bfs_shot_loop.py` also imports `comfy_extras.nodes_sam3.SAM3_Detect`
directly. So the third-party pack contributes **zero** nodes and nothing is missing;
it is dead weight, not a functional gap. Left as-is (upstream pin, not our regression).

---

## 9. Operational notes

- **Exclusive pair:** ~~`comfyui` (aeon/Flux2)~~ + `comfyui-jdaln` were both `GROUP=image`,
  so `use` stopped the other and port 8188 could not collide. **Since 2026-10-14 only
  `comfyui-jdaln` exists** — `comfyui` was retired (§11) — so the pair no longer applies;
  `MODE=exclusive` + `GROUP=image` are kept so future image lanes stay isolated from
  `27b`/`35b` (`llm`).
- **Upstream healthcheck is a false positive** — `curl ... || pgrep -af 'curl .* models/...'`
  matches the healthcheck's *own* `sh -c` command line, so `pgrep` finds itself and the
  container always reports `healthy`. **The authoritative gate is gb10-single's loopback
  curl to `:8188/`.** Do not trust `docker ps` health for this stack.
- **After an upstream `git pull`:** re-copy `SelfBuiltWheels/*` →
  `DGX-Spark-WheelsBuilder/Wheels/` before rebuilding (§3.1).
- **Boot log lives on node0**, not node1:
  `~/docker-stacks/logs/comfyui-jdaln/boot-single-node1.log` (node0 runs the boot script
  over ssh; only the container runs on node1).
- `gb10 down` is illegal (rc=2); use `gb10 stop`.

---

## 10. Repo history for this deployment

| Commit | Content |
|---|---|
| `72716a8` | `runtimes.d/comfyui-jdaln.conf` + `bin/gb10-single` + `README.md` |
| `537c64e` | `fix(gb10-single-boot): never mark READY on a health timeout` (+14/−2) |

Pushed to both remotes, pulled on node0, `check-git-sync --block` = SYNC_OK.

---

## 11. Retirement of `comfyui` (comfyui-aeon / Flux 2 Dev) — 2026-10-14

Operator decision: **"不要複製 flux2, 直接退役移除 Comfy-aeon 相關檔案"**. Executed the
same day, after `comfyui-jdaln` had been deployed and render-verified.

### 11.1 Order of operations (the HF token had to move FIRST)

1. **HF token relocated before anything was deleted.** It lived at
   `~/docker-stacks/comfyui-aeon/workspace/.cache/huggingface/token` — i.e. *inside the
   tree about to be destroyed*, and it was still the live credential for
   `src/minimax-h3/launch-download.sh`. Moved to
   `~/docker-stacks/config/hf_token` (mode `600`, 37 B, sha256 prefix
   `7f871a56841c699c`); `launch-download.sh`'s `TOKEN_FILE` was repointed to
   `${HF_TOKEN_FILE:-$HOME/docker-stacks/config/hf_token}` on both the repo copy and the
   deployed copy on node1.
2. Image `ghcr.io/aeon-7/comfyui-aeon-spark:slim` removed (26.7 GB).
3. Stack `~/docker-stacks/comfyui-aeon/` removed (~71 GB).
4. Residual `grep -rn comfyui-aeon ~/docker-stacks` → clean.

### 11.2 Deleting it took THREE attempts — and produced two false-success signals

Worth recording because both are reusable traps:

- **`rm -rf` silently leaves root-owned subtrees.** The container had created
  `workspace/` contents as `root:root`, so `eye` had no write permission on the parent
  directories and could not unlink them: `rm: 拒絕不符權限的操作`. 1949 files survived the
  first pass. Fix: delete *inside* a container (`docker run --rm -v <dir>:/t …`), where you
  are root in the namespace — no `sudo` password needed (the operator is in `docker`).
- **A `DONE` marker written with `;` is worthless.** `bash -c "rm -rf …; echo DONE > file"`
  writes `DONE` regardless of `rm`'s exit status, so it reported success over a tree that
  was never deleted. The retry captured the real codes instead (`echo "$rc" > file`, two
  separate files) and returned `[0 0]`.
- **SSH timeouts do not mean failure.** Several `Invoke-SSHCommand` calls returned
  `has timed out` while the remote had already completed — and conversely, a timeout can
  also kill the remote mid-`rm`. Always *verify state* (`dir gone?`, `image in
  docker images?`, `token sha256`) before re-sending an idempotency-sensitive script.

### 11.3 Irreversibly deleted flux2 weights (not mirrored anywhere)

| file | size |
|---|---|
| `flux2_dev_fp8mixed.safetensors` | 34 GiB |
| `mistral_3_small_flux2_bf16.safetensors` | 34 GiB |
| `Flux2TurboComfyv2.safetensors` | 2.6 GiB |
| `flux2-vae.safetensors` | 321 MiB |
| `full_encoder_small_decoder.safetensors` | 238 MiB |
| 4 × KJNodes intrinsic LoRAs | 4 × 6.2 MiB |

`comfyui-jdaln` carries **zero** flux2 weights, so nothing was migrated — re-obtaining
these means re-downloading from HF.

### 11.4 Repo changes

`git rm runtimes.d/comfyui.conf`; `README.md` (runtime table, cross-group example,
"two independent lanes" section → single lane, `Layout` stack list); `AGENTS.md`
(ComfyUI bullet rewritten); `bin/gb10-single` header + `usage` runtime list + the
`stop_group_except` comment.

---

## 12. Retirement of `minimaxh3` — 2026-10-14

Operator decision, in answer to *"comfyui-dgx-spark 範本裡也有 MiniMax H3 圖生影片，是不是與
`minimax-h3/`、`minimax-h3-sglang/` 重複？"*.

### 12.1 Why it is not a duplicate, and why it was retired anyway

The three MiniMax things on Node1 were **three different layers**, so the honest answer to
"重複嗎" was *capability overlaps, interface does not*:

| | `minimaxh3` (lane) | `minimax-h3-sglang` | `comfyui-jdaln` |
|---|---|---|---|
| engine | vLLM (`vllm/vllm-omni:minimax-h3`) | SGLang `v0.5.18-cu130` | ComfyUI 0.38.0 native + packs |
| interface | OpenAI-compatible API `:8000` | (never promoted) | node graph + UI `:8188` |
| weights | original HF shards ≈ 64 GB | NVFP4 `pruned_nvfp4` 12.5 GB | `pruned_int8_convrot` 20.9 GB |
| state | live lane until 2026-10-14 | **already dead** — `archive_sglang_experiment_2026-09-04/` holds `FAILURE_ANALYSIS.md`, `compose.*.failed.yaml`, `launch.*.failed.sh`; last touched 2026-09-04, never referenced by any conf | live |

Three different quantizations → not interchangeable; two different interfaces → scripted
callers and interactive users were served separately. Despite that, the operator chose to
**retire the lane**: interactive i2v is the actual use case, and jdaln covers it.

### 12.2 Verification gate (operator chose "先跑一次 i2v 驗證")

Nothing had ever exercised jdaln's MiniMax path — only `z-image` had been render-tested.
So the retirement was blocked on a real render:

- Graph built from the **native blueprint's own wiring**
  (`ComfyUI/blueprints/Image to Video (MiniMax H3).json`, expanded out of its litegraph
  subgraph), *not* hand-invented — which is why the result contains **no**
  `MiniMaxH3SigmaShift`, **no** `MiniMaxH3AddGuide` and **no** `EmptyMiniMaxH3LatentAV`:
  `MiniMaxH3ImageToVideo` produces both `positive` and `LATENT`, and `first_frame` does the
  anchoring. Defaults are no-LoRA + 20 steps (the blueprint's `PrimitiveBoolean` is `false`).
- Submitted as API-format 15-node graph → `node_errors: {}`.
- `prompt_id d91692b7-5ca7-4e3e-a2b9-8cb5d2c717d5` → `status=success`,
  `completed=True`, **204.52 s**.
- Output `ComfyData/output/video/MiniMax_H3_verify_00001_.mp4`, 935,097 B, magic
  `\0\0\0 ftyp isom` (valid MP4).
- Server log confirmed all four pieces loaded: `MiniMaxH3TEModel_` 14956 MB,
  `MiniMaxH3VideoVAE` 4965 MB, `MiniMaxH3` 19995 MB (`model_type FLOW_AV`),
  `MiniMaxH3AudioVAE` 312 MB; native ops incl. `nvfp4, convrot_w4a4, int8_tensorwise`.

**Known gap:** `minimax_h3_ref2va` was never downloaded (cut by the §7 asset trim), so
`MiniMaxH3ReferenceToVideo` and the *Reference to Video* template still do not run.
`ImageToVideo` / `TextToVideo` are fine. Of jdaln's 51 MiniMax node types, 39 are local and
12 are cloud API nodes (`ComfyCloudMiniMaxH3*`, `MinimaxHailuo*`) that call remote services.

### 12.3 What was deleted

| target | size | note |
|---|---|---|
| `~/docker-stacks/minimax-h3/` | **135 G** | 64 G weights + 73 G HF cache + 1.6 G `.git`; `MINIMAX_H3_MODEL_DIR` pointed *inside* it → no external dependents |
| `~/Downloads/minimax-h3-output/` | 19 M | operator: "一起刪"; `storage/*` was root-owned → container fallback |
| image `minimax-h3-dgx-spark:sm121-fp8` | **32 GB** | `Untagged` + `Deleted`, rc 0 |
| `runtimes.d/minimaxh3.conf` | — | `git rm` |
| `src/minimax-h3/` | — | `git rm -r` (45 files, incl. the in-flight `launch-download.sh` token edit — moot once retired) |

**Not deleted:** `~/docker-stacks/models/` (shared 453 G pool) — verified to contain **no**
minimax copy, so nothing outside the lane depended on these weights.

**Deleted later the same day (follow-up operator instruction, 2026-10-14):**
`minimax-h3-sglang` — originally out of scope for the lane retirement, then cleared on
request. Dir `~/docker-stacks/minimax-h3-sglang/` **56 GB** (entirely
`models/quantized`) + images `429ac2d-cu134-ffmpeg` (45.8 GB) and `429ac2d-nvfp4`
(59.2 GB), each `Untagged` + `Deleted` rc=0; node1 image count 11 → 9, no
`sglang` path remains under `~/docker-stacks/`. Safe because three of its weights
(`qwen3vl_32b_minimax_h3_nvfp4_awq` 15 GiB, `minimax_h3_video_vae_fp16` 4.9 GiB,
`minimax_h3_audio_vae_fp32` 578 MiB) are duplicated inside `comfyui-jdaln`'s
`ComfyData/models/`, while the other three (`.sglang` / `.upstream` / `.corrupt`,
12 GiB each) were SGLang-only conversions of a checkpoint jdaln does not use.
`.cache` was root-owned → container `rm`, `rc=[0 0]`.
Its `FAILURE_ANALYSIS.md` (the 2026-09-04 stop-loss record: sanitization verified,
but `audio_vae`'s custom Diffusers class blocks a weights-only override →
`ComponentCheckpointUnsupportedError`, unfixable within the allowed rules) was
preserved verbatim in `handoff.md` **before** deletion.

Disk: `used 2.1T → 1.9T`, `avail 1.5T → 1.7T`, `59% → 53%` (both retirements combined).

### 12.4 What was lost

The OpenAI-compatible **API endpoint on `:8000`** (with `H3_API_KEY`, `network_mode: host`,
batch/scripted access) no longer exists. Any automated caller must move to the ComfyUI
`/prompt` API on `:8188`. Weights are re-downloadable via the recipe in
`docs/MINIMAX_H3_DEPLOYMENT_2026-09-01.md` but that is a multi-hour fetch at the measured
~5–7 MB/s.
