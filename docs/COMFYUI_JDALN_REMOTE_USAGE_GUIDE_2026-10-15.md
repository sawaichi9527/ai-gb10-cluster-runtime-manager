# Remote usage guide — `comfyui-jdaln` (ComfyUI on node1, mirrored on node0)

**Audience:** any external client — an AI agent (hermes-agent, opencode/dsh, presenton) or a
human — that generates images or videos by calling this ComfyUI over the network.
**If you are an AI agent: read §0 first**, then the recipe section for your job.

> **Repo-tracked copy.** This is the source of truth for the deployment's *remote* API contract.
> Evidence in it was produced in-session on 2026-10-15 against the live `comfyui-jdaln` runtime
> on Node1; the artefacts were downloaded to the operator machine and sha256-verified against the
> node.
> Companion document: `docs/COMFYUI_JDALN_DEPLOYMENT_2026-10-14.md` (deployment, asset profiles,
> retirements).
> **Maintenance rule: if the ComfyUI image or the asset profiles change, re-verify
> §2/§4/§5/§5b against `/object_info` before trusting the file names below.**

**Version of this document:** 2026-10-15 (**rev 4**). Rev 2 added §5b Qwen-Image 2.1 and the
"output dimensions must be multiples of 16" rule; rev 3 added §0 (agent TL;DR) and §9 (node0
failover); rev 4 adds §10 (presentation-deck workflow: two independent model workflows, the
optional hybrid, the 1080p crop contract, batching and QA). Everything marked ✅ was executed
against the live service on that date, with file sizes/hashes and wall times recorded below.

---

## 0. TL;DR — for an AI client (read this first)

**Base URL: `http://192.168.23.216:8188` (node1).** Failover: `http://192.168.23.215:8188`
(node0) — see §9. No auth. HTTP only.

### The minimal loop (any job)

```bash
BASE=http://192.168.23.216:8188

# 1) queue  (payload.json = {"prompt": {...}, "client_id": "my-agent"})
PID=$(curl -s -X POST -H 'Content-Type: application/json' --data @payload.json \
        "$BASE/prompt" | python3 -c 'import sys,json;print(json.load(sys.stdin)["prompt_id"])')

# 2) poll — use a LONG timeout (image ≈ 20–60 s, MiniMax H3 ≈ 13 min)
while :; do
  H=$(curl -s "$BASE/history/$PID"); [ "$H" != "{}" ] && break; sleep 5
done

# 3) verify + fetch the artefact named in history.outputs[*].images[*].filename
curl -s -o out.png "$BASE/view?type=output&filename=<filename>"
```

`node_errors: {}` on the POST only means **the graph was accepted**. Real failures arrive later
inside `history[<id>].status.messages` as `execution_error`, and success is
`status.status_str == "success"`.

### Choose the model by the job

| The job | Use | Wall time | Recipe |
|---|---|---|---|
| Image that must contain **legible text** (slides, labels, dense layouts) | **Qwen-Image 2.1** t2i | 50 s @1920×1088 | §5b.3 |
| Sharpest possible text / hero cover image | Qwen-Image 2.1, mode B or C | 90–111 s | §5b.2 |
| Fast image drafts; composition locked by a canny/depth/pose sketch | **Z-Image Turbo** (+ union ControlNet) | ~16–20 s | §4 |
| Edit an existing image (rewrite text, recolour, swap object, ≤10 refs) | **Qwen-Image 2.1** edit | 20–50 s | §5b.4 |
| Subject cutout with **real alpha** on a transparent background | **Qwen-Image 2.1** remove-background | 20 s | §5b.4 |
| Video **with audio** (~5 s, 24 fps), from text or from a first frame | **MiniMax H3** (20 steps) | **≈13 min** | §5 |
| Same video, faster draft | MiniMax H3 + turbo LoRA (8 or 4 steps) | less | §5 |
| Frame interpolation / video upscale / subtitles / speech | FILM / SeedVR2 / Whisper / Qwen3-TTS | seconds | §2 inventory |

**Building a slide deck?** Go straight to **§10** — it splits this into two independent
workflows (Qwen-Image 2.1 for graphic/text slides, Z-Image Turbo for pure imagery), plus the
1080p 16:9 crop contract, batching rules and a QA checklist.

### Four rules that break naive clients

1. **Never `CheckpointLoaderSimple`** — `models/checkpoints/` does not exist here, and its combo
   list is legitimately empty (§2).
2. **Output width and height must be multiples of 16** — ask for 1920×1080 and you receive
   1920×1088, which letterboxes in a 16:9 deck. Render 1088 and crop 8 rows (§5b.1).
3. **Set generous client timeouts** — a MiniMax H3 clip needs ~13 min even when warm; a cold
   first run stages ~40 GB of weights.
4. **Fetch files with `/view`** — the model directories are not exposed over HTTP, and outputs
   are written on the *node*, not to your machine.

---

## 1. Service endpoint

| Item | Value |
|---|---|
| Base URL | `http://192.168.23.216:8188` (Node1, LAN) |
| Server | ComfyUI **0.38.0**, frontend 1.53.10, templates 0.11.76, Linux, GPU *NVIDIA GB10* |
| Auth | **none** on `:8188` (do not send an API key) |
| Health check | `GET http://192.168.23.216:8188/system_stats` → JSON with `system.comfyui_version` |
| Registered node types | 2811 (`ComfyUI-SAM3-DGX-Spark` is deliberately blacklisted; not a missing install) |
| GPU concurrency | **one GPU, serialized.** Image jobs ~15 s; MiniMax H3 video jobs **~13 min**. ComfyUI queues jobs; long client timeouts are mandatory |

---

## 2. GOLDEN RULE — never use `CheckpointLoaderSimple` here

`models/checkpoints/` **does not exist** in this deployment, so
`CheckpointLoaderSimple.ckpt_name` is an **empty list**. That is by design, not a broken install.

> If a tool reports *"CheckpointLoaderSimple is empty — install the main model into
> models/checkpoints/"*, the tool is using a **checkpoint-shaped template**, which is wrong for
> every model served here. Z-Image Turbo and MiniMax H3 are published as **separate
> UNET / text-encoder / VAE files**, not as all-in-one checkpoints.

**Do not** copy any `diffusion_models/*.safetensors` into `models/checkpoints/` — a
`CheckpointLoaderSimple` load would fail (those files contain no CLIP/VAE weights). Use the
graphs in §4 / §5 instead.

### How to discover what is actually available (always do this first)

```bash
curl -s http://192.168.23.216:8188/object_info/UNETLoader   # -> models/diffusion_models/*
curl -s http://192.168.23.216:8188/object_info/CLIPLoader   # -> models/text_encoders/*
curl -s http://192.168.23.216:8188/object_info/VAELoader    # -> models/vae/*
```

The filename strings inside those combo lists are the **only** valid values for the
corresponding inputs. Verified on 2026-10-15:

- `UNETLoader.unet_name`: `hyvideo/hunyuan_video_720_fp8_e4m3fn.safetensors`, `lotus-depth-d-v1-1.safetensors`, `minimax_h3_fl2va_int8_convrot.safetensors` (symlink to the pruned file), `minimax_h3_fl2va_pruned_int8_convrot.safetensors`, **`qwen_image_2.1_int8_convrot.safetensors`**, `seedvr2_3b_int8_convrot.safetensors`, `z_image_turbo_bf16.safetensors`
- `CLIPLoader.clip_name`: `clip_l.safetensors`, `llava_llama3_fp16.safetensors`, **`qwen3.5_9b_qwen_image_2.1_pe_i2i.int8_convrot.safetensors`**, **`qwen3.5_9b_qwen_image_2.1_pe_t2i.int8_convrot.safetensors`**, `qwen3vl_32b_minimax_h3_nvfp4_awq.safetensors`, **`qwen3vl_8b_int8_convrot.safetensors`** (symlink to the `w4a8` file), **`qwen3vl_8b_w4a8.safetensors`**, `qwen_3_4b.safetensors`, `umt5-xxl-enc-bf16.safetensors`
- `VAELoader.vae_name`: `Wan2_1_VAE_bf16.safetensors`, `ae.safetensors`, `hyvid/hunyuan_video_vae_bf16.safetensors`, `ltx-2.5-video-vae-bf16.safetensors`, `minimax_h3_audio_vae_fp32.safetensors`, `minimax_h3_video_vae_fp16.safetensors`, **`qwen_image_2.1_vae_bf16.safetensors`**, `seedvr2_ema_vae_fp16.safetensors`, `vae-ft-mse-840000-ema-pruned.safetensors`, `pixel_space`
- `CheckpointLoaderSimple.ckpt_name` (**for contrast**): `[]` — still empty; see §2.

### Second golden rule — output dimensions must be multiples of 16

**Width and height must both be multiples of 16.** Anything else is silently padded by the model
and the padding is **not** cropped back, so the delivered image is larger than requested:
ask for **1920×1080** and you get **1920×1088** (1080 = 67.5×16). Since 1920×1088 = 1.7647 and
16:9 = 1.7778, a presentation tool will letterbox it (~7 px black bars each side at 1920 wide).
For 1080p slide work: render **1920×1088** and crop 8 rows, or render the native 2K 16:9 bucket
**2752×1536** and downscale. Full evidence and timings in §5b.1.

---

## 3. API contract (ComfyUI native)

| Call | Purpose |
|---|---|
| `POST /prompt` | Queue a job. Body `{"prompt": {<node_id>: {"class_type": …, "inputs": {…}}}, "client_id": "<any>"}`. Returns `{"prompt_id", "number", "node_errors"}` |
| `GET /history/<prompt_id>` | `{}` while queued/running; when finished → `{<id>: {"status": {"status_str": "success"\|"error", "completed": bool, "messages": […]}, "outputs": {…}}}` |
| `GET /queue` | `queue_running` / `queue_pending` |
| `GET /view?filename=<f>&subfolder=<s>&type=output` | **Download a produced file** (works over the LAN; raw bytes) |
| `POST /upload/image` | multipart field `image=` → upload a first frame; returns `{"name": …, "subfolder": …, "type": "input"}` (then use `name` in `LoadImage.image`) |
| `POST /interrupt` | Cancel the running job |
| `GET /object_info[/<NodeType>]` | Node specs + combo file lists |

**Reading the result correctly**

- `"node_errors": {}` in the `POST /prompt` reply only means **the graph was accepted**. Real
  failures arrive later, inside `history[<id>].status.messages` as `execution_error`.
- Always poll `GET /history/<prompt_id>` until it is non-empty, then check
  `status.status_str == "success"`. Timings: z-image ≈ 15 s, MiniMax H3 ≈ **13 min**.
- Produced files appear under `status/outputs[<node_id>]` (`images` / `videos` keys carry
  `filename`, `subfolder`, `type`). Fetch with `/view`.

---

## 4. Image generation — Z-Image Turbo ✅

**Files used (three separate loaders — no checkpoint):**

| Role | Node | File |
|---|---|---|
| UNET / main model | `UNETLoader` | `diffusion_models/z_image_turbo_bf16.safetensors` |
| Text encoder | `CLIPLoader` with `type="lumina2"` | `text_encoders/qwen_3_4b.safetensors` |
| VAE | `VAELoader` | `vae/ae.safetensors` |

Pipeline: `UNETLoader → ModelSamplingAuraFlow(shift 3) → KSamplerSelect(res_multistep)` +
`EmptySD3LatentImage` → `SamplerCustomAdvanced`-style sampling is **not** required; the
template uses a plain `KSampler` with **4 steps, cfg 1, res_multistep / simple**, then
`VAEDecode → SaveImage`.

**Verified payload** (POST to `/prompt`; produced `z-image_check_00001_.png`, 709,638 bytes,
`sha256 70150063…b8e5`, ~16 s):

```json
{"prompt": {
 "1": {"class_type":"UNETLoader","inputs":{"unet_name":"z_image_turbo_bf16.safetensors","weight_dtype":"default"}},
 "2": {"class_type":"CLIPLoader","inputs":{"clip_name":"qwen_3_4b.safetensors","type":"lumina2"}},
 "3": {"class_type":"VAELoader","inputs":{"vae_name":"ae.safetensors"}},
 "4": {"class_type":"ModelSamplingAuraFlow","inputs":{"model":["1",0],"shift":3}},
 "5": {"class_type":"EmptySD3LatentImage","inputs":{"width":1024,"height":576,"batch_size":1}},
 "6": {"class_type":"CLIPTextEncode","inputs":{"clip":["2",0],"text":"a room with neon light, a teddybear"}},
 "7": {"class_type":"CLIPTextEncode","inputs":{"clip":["2",0],"text":""}},
 "8": {"class_type":"KSampler","inputs":{"model":["4",0],"positive":["6",0],"negative":["7",0],"latent_image":["5",0],"seed":42,"steps":4,"cfg":1,"sampler_name":"res_multistep","scheduler":"simple","denoise":1}},
 "9": {"class_type":"VAEDecode","inputs":{"samples":["8",0],"vae":["3",0]}},
 "10":{"class_type":"SaveImage","inputs":{"images":["9",0],"filename_prefix":"z-image"}}
}}
```

Notes: keep `steps=4` and `cfg=1` (turbo distill). Reference UI graph (on the server):
`custom_nodes/ComfyUI-Simple-Prompt-Batcher/examples/z-image_simple_prompt_batcher.json`.

---

## 5. Video generation — MiniMax H3 ✅ (image→video and text→video)

**Files used:**

| Role | Node | File |
|---|---|---|
| UNET / main model | `UNETLoader` | `diffusion_models/minimax_h3_fl2va_pruned_int8_convrot.safetensors` |
| Text encoder | `CLIPLoader` with `type="minimax"` | `text_encoders/qwen3vl_32b_minimax_h3_nvfp4_awq.safetensors` |
| Video VAE | `VAELoader` | `vae/minimax_h3_video_vae_fp16.safetensors` |
| Audio VAE | `VAELoader` | `vae/minimax_h3_audio_vae_fp32.safetensors` |
| *(optional)* LoRA | `LoraLoaderModelOnly` | `loras/minimax_h3_fl2v_turbo_8step_v1.0_comfyui_bf16.safetensors` (then `steps=8`); also `…_v1.2_…`, `…_4step_…` |

**Graph (native blueprint wiring — this is the verified shape):**

```
UNETLoader(1) ─┬─> BasicScheduler(model)                     [scheduler=simple, steps=20, denoise=1]
               └─> BasicGuider(model)
CLIPLoader(2) ──> MiniMaxH3ImageToVideo(clip)
VAELoader(vid,3) ─> MiniMaxH3ImageToVideo(vae)   ─┬─> BasicGuider(conditioning)   "positive"
                                                  └─> SamplerCustomAdvanced(latent_image)  slot 1 = LATENT
LoadImage(4)    ──> MiniMaxH3ImageToVideo(first_frame)      [omit for text→video]
KSamplerSelect(sampler=res_multistep) ──> SamplerCustomAdvanced(sampler)
RandomNoise(noise_seed)               ──> SamplerCustomAdvanced(noise)
BasicScheduler ──> SamplerCustomAdvanced(sigmas)
SamplerCustomAdvanced ─┬─> VAEDecode(vae=3)      ─┐
                       └─> VAEDecodeAudio(vae=4) ─┴─> CreateVideo(fps=24) ──> SaveVideo(format="mp4")
```

- **Do not** add `MiniMaxH3SigmaShift`, `MiniMaxH3AddGuide` or `EmptyMiniMaxH3LatentAV` — the
  native blueprint does not use them: `MiniMaxH3ImageToVideo` itself outputs `CONDITIONING`
  *and* `LATENT`, and anchoring is done through the optional `first_frame` input.
- `length` must land on the **17k+5 grid**; `124` ≈ 5.2 s at 24 fps (trained range ~124–362).
- **Text→video = the same graph with `first_frame` omitted** ✅ (verified).

**Verified payload, image→video** (input `figurine_knight.jpg`; it is already on the server — to
use your own image, upload it first with `POST /upload/image` (see §6) and put the returned
`name` into `LoadImage.image`):

```json
{"prompt": {
 "1": {"class_type":"UNETLoader","inputs":{"unet_name":"minimax_h3_fl2va_pruned_int8_convrot.safetensors","weight_dtype":"default"}},
 "2": {"class_type":"CLIPLoader","inputs":{"clip_name":"qwen3vl_32b_minimax_h3_nvfp4_awq.safetensors","type":"minimax"}},
 "3": {"class_type":"VAELoader","inputs":{"vae_name":"minimax_h3_video_vae_fp16.safetensors"}},
 "4": {"class_type":"VAELoader","inputs":{"vae_name":"minimax_h3_audio_vae_fp32.safetensors"}},
 "5": {"class_type":"LoadImage","inputs":{"image":"figurine_knight.jpg"}},
 "6": {"class_type":"MiniMaxH3ImageToVideo","inputs":{"clip":["2",0],"vae":["3",0],"prompt":"The knight slowly raises his sword as sparks drift upward, cinematic camera push-in","width":1344,"height":768,"length":124,"first_frame":["5",0]}},
 "7": {"class_type":"KSamplerSelect","inputs":{"sampler_name":"res_multistep"}},
 "8": {"class_type":"BasicScheduler","inputs":{"model":["1",0],"scheduler":"simple","steps":20,"denoise":1}},
 "9": {"class_type":"RandomNoise","inputs":{"noise_seed":42}},
 "10":{"class_type":"BasicGuider","inputs":{"model":["1",0],"conditioning":["6",0]}},
 "11":{"class_type":"SamplerCustomAdvanced","inputs":{"noise":["9",0],"guider":["10",0],"sampler":["7",0],"sigmas":["8",0],"latent_image":["6",1]}},
 "12":{"class_type":"VAEDecode","inputs":{"samples":["11",0],"vae":["3",0]}},
 "13":{"class_type":"VAEDecodeAudio","inputs":{"samples":["11",0],"vae":["4",0]}},
 "14":{"class_type":"CreateVideo","inputs":{"images":["12",0],"audio":["13",0],"fps":24}},
 "15":{"class_type":"SaveVideo","inputs":{"video":["14",0],"filename_prefix":"MiniMax_H3_i2v","format":"mp4"}}
}}
```

**Text→video:** delete node `5` and the `"first_frame":["5",0]` entry from node `6`.
Everything else is identical. ✅ verified.

**Measured results (2026-10-15, live service):**

| Job | Result | Wall time | File |
|---|---|---|---|
| image→video | `status: success, completed: true` | **834 s** | `MiniMax_H3_i2v_guide_00001_.mp4`, 2,248,032 B, `sha256 5025954c…7a12` |
| text→video | `status: success, completed: true` | **755 s** | `MiniMax_H3_t2v_guide_00001_.mp4`, 4,627,422 B, `sha256 af32cc38…5d4a` |

Both files are real MP4s (magic `ftyp isom`); both carry a **24 fps, 124-frame (~5 s) video plus
a generated audio track**. Budget **~13 minutes per clip** even when the models are already warm —
do not use short HTTP/timeout settings.

**Known limitations**

- **Reference to Video is NOT available** (`MiniMaxH3ReferenceToVideo`): its weights
  (`minimax_h3_ref2va…`) were never downloaded. `Image to Video` / `Text to Video` (above) work.
- 12 of the 51 `MiniMax*` node types are **cloud API** nodes (`ComfyCloudMiniMaxH3*`,
  `MinimaxHailuo*`) that call paid remote services — ignore them for local generation.
- A simpler alternative pack exists (`MiniMaxH3EasyLoader → MiniMaxH3Easy →
  MiniMaxH3EasySampler → MiniMaxH3EasySegmentDecode`); it is **not** what was verified here.
  Prefer the graph in this section.

---

## 5b. Qwen-Image 2.1 — slide graphics with real text, editing and cutouts ✅

**Recommended whenever the image must carry legible text** (headlines, labels, charts-style
graphics). One set of weights serves generation *and* editing. Three profiles are enabled
(~33 GB total, mostly shared):

| Job | Profile | Official template id | Measured |
|---|---|---|---|
| Text to image up to 2K, dense text, native alpha | `qwen-image-2.1-t2i` | `image_qwen_image_2_1_t2i` | 50 s @1920×1088 |
| Instruction edit, up to 10 reference images | `qwen-image-2.1-edit` | `image_qwen_image_2_1_image_edit` | 20–50 s |
| Instruction background removal → **real alpha** | `qwen-image-2.1-remove-background` | `image_qwen_image_2_1_background_removal` | 20 s |

Loaders: `UNETLoader qwen_image_2.1_int8_convrot.safetensors` →
`QwenImage21Cache` (device `auto`, dtype `default`) → `KSampler`; `CLIPLoader`
`qwen3vl_8b_int8_convrot.safetensors` with `type="qwen_image"` → `TextEncodeQwenImage21`;
`VAELoader qwen_image_2.1_vae_bf16.safetensors`; `KSampler` **25 steps, cfg 1, euler / simple**.
The BFL-style prompt-rewriter (`qwen3.5_9b_..._pe_t2i` via `TextGenerate`) is **optional** — the
verified payloads below skip it.

### 5b.1 Resolution — multiples of 16, and the 1080p crop

Measured on node1 (25 steps, cfg 1, euler/simple, same seed and prompt):

| requested | delivered | wall time |
|---|---|---|
| 1280×720 (both /16) | 1280×720 | 20 s |
| 1920×1080 (1080 not /16) | **1920×1088** | 60 s (cold load) |
| 1920×1088 | 1920×1088 | **50 s** |
| 2752×1536 (native 2K 16:9 bucket) | 2752×1536 | **111 s** |
| 1920×1088 + cfg 2.5 + quality negative prompt | 1920×1088 | 90 s |

- Native buckets published for this model: **2048×2048 (1:1), 2400×1792 (4:3), 2528×1696 (3:2),
  2752×1536 (16:9)** — note that even the "native 16:9" is 1.7917, not exactly 16:9.
- `resolution` on `TextEncodeQwenImage21` is **only** the resize target for reference images
  (multiples of 32; `0` = keep each reference's own size). It does not size a text-to-image job.
- **For exactly 1920×1080 (no letterboxing in a slide deck):** render **1920×1088**, then crop
  8 rows (4 top / 4 bottom) in post. Verified: the resulting 1920×1080 fills a 16:9 display.

### 5b.2 Three quality modes for slide art

| Mode | Recipe | Wall | Use for |
|---|---|---|---|
| **A (default)** | render 1920×1088 → crop 8 rows → 1920×1080 | **50 s** | every slide |
| **B (hero)** | render 2752×1536 (native) → downscale to 1935×1080 → crop to 1920×1080 | **111 s** | cover/hero image; supersampled text |
| **C (sharpest text)** | A or B **+ `cfg` 2.5 + a quality-oriented `negative_prompt`** | 90 s | small print, dense labels |

Mode C follows the published guidance ("CFG below 1 is not usable; a small CFG with a
quality-focused negative prompt is what people reach for when text in the image needs to be
sharper"). Example negative prompt: `blurry, low quality, distorted text, misspelled letters,
garbled typography, watermark, jpeg artifacts, cluttered layout`.

### 5b.3 Verified text-to-image payload (mode A: 1920×1088)

```json
{"prompt":{
 "1":{"class_type":"UNETLoader","inputs":{"unet_name":"qwen_image_2.1_int8_convrot.safetensors","weight_dtype":"default"}},
 "2":{"class_type":"QwenImage21Cache","inputs":{"model":["1",0],"device":"auto","dtype":"default"}},
 "3":{"class_type":"CLIPLoader","inputs":{"clip_name":"qwen3vl_8b_int8_convrot.safetensors","type":"qwen_image"}},
 "4":{"class_type":"TextEncodeQwenImage21","inputs":{"clip":["3",0],"prompt":"<YOUR PROMPT>","negative_prompt":"","resolution":1024}},
 "5":{"class_type":"VAELoader","inputs":{"vae_name":"qwen_image_2.1_vae_bf16.safetensors"}},
 "6":{"class_type":"EmptyLatentImage","inputs":{"width":1920,"height":1088,"batch_size":1}},
 "7":{"class_type":"KSampler","inputs":{"model":["2",0],"positive":["4",0],"negative":["4",1],"latent_image":["6",0],"seed":20261015,"steps":25,"cfg":1,"sampler_name":"euler","scheduler":"simple","denoise":1}},
 "8":{"class_type":"VAEDecode","inputs":{"samples":["7",0],"vae":["5",0]}},
 "9":{"class_type":"SaveImage","inputs":{"images":["8",0],"filename_prefix":"slide"}}
}}
```

### 5b.4 Editing / background removal — two traps

Reference images go into the node's **autogrow** input. In the **API format that is a nested
object**, never flat keys:

```json
"4":{"class_type":"TextEncodeQwenImage21","inputs":{
  "clip":["3",0],
  "prompt":"<EDIT INSTRUCTION>",
  "negative_prompt":"",
  "resolution":1440,
  "vae":["5",0],
  "images":{"image_1":["6",0],"image_2":["7",0]}
}}
```

1. **Names are `image_1` … `image_16` inside `images`.** Passing `"image_1": [...]` as a
   top-level input fails with
   `TextEncodeQwenImage21.execute() got an unexpected keyword argument 'image_1'`.
2. **`vae` is required for edits** (the reference latents are spliced into the sequence).
3. ⚠️ **The node's `latent` output is always SQUARE** (`resolution × resolution`) despite its
   tooltip saying "on the first reference image's size". For a 16:9 edit you must ignore that
   output and feed your own `EmptyLatentImage`; keep `resolution` at a value whose reference
   resize matches your canvas (16:9 reference + `resolution=1440` resizes it to exactly
   1920×1088).

Verified: costume replacement (2 refs, 1024×1024, 20 s), 16:9 slide re-edit
(`EmptyLatentImage 1920×1088` + `resolution=1440`, **1920×1088, 50 s**), background removal on
the bundled sample `angry_broccoli.png` (**RGBA `alpha_minmax = (0, 255)` — genuinely
transparent**, 20 s). Ordinary text-to-image output is also RGBA but effectively opaque
(measured `(244,255)`), so do not treat an alpha channel as proof of a cutout.



## 6. Outputs, inputs and file transfer

| Direction | Location |
|---|---|
| **Outputs** (what you fetch) | Node1 `~/Downloads/output/` — mounted as the container's `/workspace/ComfyUI/output`. Fetch with `GET /view?...&type=output` |
| **Inputs** (first frames etc.) | Node1 `…/ComfyData/input/` → container `/workspace/ComfyUI/input`. Upload via `POST /upload/image` |
| Already-present inputs | `angry_broccoli.png` (background-removal sample), `portrait_model_denim.png` + `clothing_light_blue_denim_shirt.png` (Qwen-Image 2.1 edit samples), `figurine_knight.jpg` (MiniMax H3 i2v sample), `Mona-Lisa-oil-wood-panel-Leonardo-da.webp`, `image_lotus_depth_v1_1_input_image.png`, `infinitetalk_speaker1_mask.png`, `infinitetalk_speaker2_mask.png` |

`filename_prefix` in `SaveImage` / `SaveVideo` controls the file name (ComfyUI appends
`_00001_`). Outputs are **not** mirrored elsewhere; always download from `/view`.

---

## 7. Worked end-to-end example (bash)

```bash
BASE=http://192.168.23.216:8188

# 1) queue
PID=$(curl -s -X POST -H 'Content-Type: application/json' \
        --data @z-image.json "$BASE/prompt" | python3 -c 'import sys,json;print(json.load(sys.stdin)["prompt_id"])')

# 2) poll until history is non-empty (use generous timeouts: H3 needs ~13 min)
while :; do
  H=$(curl -s "$BASE/history/$PID")
  [ "$H" != "{}" ] && break
  sleep 10
done
echo "$H" | python3 -c 'import sys,json;d=json.load(sys.stdin);[print(v["status"]) for v in d.values()]'

# 3) fetch the artefact
curl -s -o out.png "$BASE/view?type=output&filename=z-image_00001_.png"
```

---

## 8. Troubleshooting quick table

| Symptom | Cause | Action |
|---|---|---|
| `CheckpointLoaderSimple.ckpt_name == []` | correct behaviour here | use `UNETLoader` + `CLIPLoader` + `VAELoader` (§4/§5) |
| Agent asks to "install the model into models/checkpoints/" | wrong template shape | reject; the model is already installed in `diffusion_models/` |
| `node_errors: {}` but nothing ever finishes | job queued behind another (single GPU) | check `GET /queue`; raise the timeout to >15 min for H3 |
| Job "hangs" far longer than expected | MiniMax H3 first run after boot stages ~40 GB of weights | budget ~13 min; poll instead of restarting |
| `status_str: "error"` | read `status.messages[].execution_error` | usually a wrong combo value (file name) |
| Need a node type that seems missing | 2811 types registered; SAM3 pack blacklisted on purpose | check `GET /object_info/<NodeType>` before assuming |
| `find .` style inspection of models | — | use `/object_info` instead; the filesystem is not exposed over HTTP |

---

## 9. Node0 — the same service on the other machine (failover)

Node1 is the **primary**. Node0 keeps a **byte-identical passive mirror** of the whole lane
(weights, `.env`, the same container image), refreshed **manually** by rsync over the CX7 network.
It is **not** started automatically and there is **no automatic switch**.

| | node1 (primary) | node0 (failover) |
|---|---|---|
| API / UI | `http://192.168.23.216:8188` | `http://192.168.23.215:8188` |
| Host | `spark-8095` | `spark-25d5` |
| Lane state | running | mirror present, **service stopped** |
| Contains | everything below | the same weights and `.env` (173 GB, verified byte-identical 2026-10-15) |

### Bringing it up (on node0)

```bash
gb10 stop                                   # TP2 (27B/35B cluster) owns the same GB10 GPU
gb10-single use comfyui-jdaln node0         # node0 runs the same compose locally
```

- The node is an **argument**, not a config field (`runtimes.d/comfyui-jdaln.conf` has no `NODE`),
  and it must be **typed explicitly** — hence "no automatic switch".
- **TP2 must be down first**: the 27B/35B cluster and ComfyUI contend for the same GPU.
- Same endpoint and same API contract as §1–§5b: once it is up, every payload in this document
  works unchanged against `http://192.168.23.215:8188`.

### Before trusting the mirror (do this, it has silently fallen behind twice)

Compare on **both** machines: file/dir/symlink counts, the `.env` md5, and one >2 GB weight's
sha256. Reference values as of 2026-10-15: `114,396 / 16,317 / 7` entries,
`.env` md5 `53328eebbb8a9c8b445cbe5a2c51a4ab`, stack 173 GB,
`qwen_image_2.1_int8_convrot.safetensors` sha256 `cb74113cb03faecd79611b01fd7fd642f0aa60d6f0b95086abee214d75eaa57d`.
The mirror is updated with a single rsync over CX7 (see `AGENTS.md`, "failover mirror") — never
through the Windows host or the 192.168.23.x LAN.

### For an agent that does not know which node it is on

Probe both URLs with `GET /system_stats`; whichever answers `200` with
`system.comfyui_version = 0.38.0` is the node to use. Ask the operator before failing over —
it is a manual, GPU-exclusive operation.

---

## 10. Presentation-deck workflow (16:9, 1080p)

Everything in this section is about producing **slide art**. It is split into **two independent
workflows** — one per model — because that is what the two families are good at.
**Workflow A (Qwen-Image 2.1 t2i + edit) is a complete pipeline on its own**; Workflow B
(Z-Image Turbo) is a separate, equally complete pipeline for pure imagery. The hybrid in §10.4 is
**optional** and explicitly not a community standard.

### 10.1 Which model for which slide

| The slide needs | Model | Reasoning (see sources below) | Measured here |
|---|---|---|---|
| Headlines, labels, numbers, dense or long text **inside the image** | **Qwen-Image 2.1** | the open-source text-rendering champion (EN+CN); built for posters/labels/UI/graphics | 20–111 s |
| Photoreal or concept imagery, no in-image text (text goes in the deck tool) | **Z-Image Turbo** | photorealism, portraits, product shots, 4-step speed; "realism better, diversity narrower" | 10–20 s |
| 1–5 words of in-image text on a photo-like image | Z-Image Turbo (acceptable) or Qwen 2.1 (safer) | reviewer consensus: Z-Image "will do the basics but do not expect longer text to work" | — |
| Cutout with real alpha | **Qwen-Image 2.1** remove-background | Z-Image outputs **RGB (no alpha)** | 20 s |

**What the community says** (checked 2026-10-15):

- "Qwen-Image is the answer when text accuracy is critical: posters, banners, UI mockups, product
  labels, and social graphics with overlaid copy… Z-Image Turbo is the faster alternative when
  throughput matters more than maximum text precision." (model round-up)
- "Nothing local renders text better" than Qwen-Image for readable text / posters / logos.
- Z-Image Turbo is described as a 6B **speed-first** distilled model: ~2–3 s on data-centre GPUs,
  8-step distillation, strong photorealism, bilingual short text, occasionally weak anatomy; one
  careful reviewer: *"Text rendering is not as strong as Qwen Image or Flux.2. It will do the
  basics but do not expect longer text to work."*
- **Beware of comparison pages**: at least one marketing comparison asserts "Z-Image Turbo lacks
  text rendering support entirely", which is **false** — we rendered legible in-image headlines
  with it locally (§10.3). Treat vendor/marketing comparisons as low-trust; prefer your own A/B.
- Mixed pipelines (draft on one model, finish on the other) are only mentioned anecdotally; the
  mainstream advice is **"use the right model for the job"**.

**Local A/B you can look at**: `E_草稿_zimage_1920x1080.png` (Z-Image Turbo, same prompt) vs
`F_定稿_qwen21_1920x1080.png` (Qwen-Image 2.1, refined). Compare the headline/subheading
legibility before deciding per slide type.

### 10.2 Workflow A — graphic / text slides: **Qwen-Image 2.1 is a complete workflow by itself**

`qwen-image-2.1-t2i` **generates**, `qwen-image-2.1-edit` **corrects and re-composes**, and
`qwen-image-2.1-remove-background` **cuts out** — all three run on the **same weights** (one
checkpoint, one text encoder, one VAE). Nothing else has to be installed, and no second model has
to be loaded: a whole deck can be produced, fixed and post-processed inside this one family.
(That is also why 2.1 was chosen: text accuracy where you need it, plus editing, without a
cross-model detour.)

| Stage | What to do | Cost | Typical |
|---|---|---|---|
| **A1 draft** | same payload as §5b.3 with `EmptyLatentImage 1280×720`, 2–4 seeds → pick the composition. *(All Qwen-Image 2.1 — the cheap knob is resolution, not another model.)* | 20 s per image | 3 drafts = 1 min |
| **A2 final** | §5b.2 modes: **A** 1920×1088 = 50 s · **B** hero 2752×1536 = 111 s · **C** cfg 2.5 + quality negative prompt = 90–100 s | 50–111 s | one final per slide |
| **A3 fix** | text wrong, or an element misplaced? **Do not re-roll — edit it**: `images{"image_1": <final>}`, e.g. "the headline must read exactly: …" / "move the accent line to the bottom", keeping `resolution` matched to the canvas (§5b.4) | 20–100 s | only when needed |
| **A4 post** | crop 1920×1088 → **1920×1080** (§10.5); place body copy in the deck tool | instant | always |

Everything in A1–A3 is the same two profiles, so there is no model-switch cost anywhere in this
workflow.

*Optional accelerator (not required)*: the sibling checkpoint
`qwen-image-2512-t2i-lightning-4step` (4 assets, **+31.8 GB**) is a 4-step Qwen-class model for
draft-grade output, and `qwen-image-t2i-lightning-8step` is its 8-step sibling. They are separate
downloads and a *different* checkpoint — 1280×720 on 2.1 at 20 s is normally cheap enough.

### 10.3 Workflow B — pure imagery / photoreal slides (Z-Image Turbo only)

Payload = §4. Measured: **1280×720 = 10 s**, **1920×1088 = 20 s** (4 steps, cfg 1,
`res_multistep`/`simple`, `ModelSamplingAuraFlow` shift 3).

- **Keep in-image text to a hero word or two.** For anything longer, generate the *text-free*
  background here and set the type in the deck tool.
- **Lock the composition** when the slide layout is fixed: use the enabled
  `z-image-turbo-union-control` profile with a canny/depth/pose sketch of your layout outline
  (blueprints `Canny to Image (Z-Image-Turbo)`, `Depth to Image (Z-Image-Turbo)`,
  `Pose to Image (Z-Image-Turbo)`, `ControlNet (Z-Image-Turbo)`).
- **No alpha**: Z-Image returns RGB. If you need a transparent subject, run Workflow A's
  remove-background step instead.
- Drafting is so cheap here (10 s) that "3 seeds and pick" is the normal way to work.

### 10.4 Optional hybrid — Z-Image draft refined by Qwen-Image 2.1 (verified, not standard)

Verified end-to-end: Z-Image Turbo draft at 1920×1088 (**20 s**) → Qwen-Image 2.1 **edit** with
`images{"image_1": <draft>}`, `resolution 1440`, `EmptyLatentImage 1920×1088`, cfg 2.5
(**100 s**) → the layout is preserved while the typography is redrawn cleanly.

Use it **only** when you must keep an exact composition that Z-Image produced. Otherwise
Workflow A is cheaper and simpler, and the community does not treat cross-model refinement as a
normal practice — it costs an extra model load and does not make Qwen's typography better than
Qwen's own output.

### 10.5 The 1080p 16:9 contract (the details people get wrong)

1. **Render 1920×1088** — both dimensions are multiples of 16, so nothing is padded (§5b.1).
2. **Crop exactly 8 rows** (4 top / 4 bottom) → **1920×1080**. Do not resize; a resize blurs type.
3. Never request 1920×1080 directly: the model pads to 1088 and a 16:9 deck letterboxes 1.7647.

```bash
# ImageMagick
magick in_1920x1088.png -crop 1920x1080+0+4 +repage out_1920x1080.png

# Python (Pillow)
python3 -c "from PIL import Image; im=Image.open('in_1920x1088.png'); im.crop((0,4,1920,1084)).save('out_1920x1080.png')"

# Windows PowerShell (.NET)
Add-Type -AssemblyName System.Drawing
$s=[System.Drawing.Image]::FromFile('in_1920x1088.png'); $b=New-Object System.Drawing.Bitmap 1920,1080
$g=[System.Drawing.Graphics]::FromImage($b)
$g.DrawImage($s,(New-Object System.Drawing.Rectangle 0,0,1920,1080),(New-Object System.Drawing.Rectangle 0,4,1920,1080),[System.Drawing.GraphicsUnit]::Pixel)
$b.Save('out_1920x1080.png',[System.Drawing.Imaging.ImageFormat]::Png)
```

- **Hero mode B** instead renders 2752×1536 → scale to **1935×1080** → crop 8 px per side → 1920×1080.
- **Safe area**: keep in-image text at least ~5 % from every edge (≈96 px at 1920 wide) so the
  deck tool never clips it; reserve the area your body copy will occupy as *calm empty space* in
  the prompt (say it explicitly: "the right two thirds is calm empty space").
- If the image will sit behind text, ask for high contrast and a flat area behind the text zone.

### 10.6 Batch and scheduling rules

- **One GPU, serialized.** Jobs queue; check `GET /queue`. Do not fire parallel requests hoping
  for speed — they run one after another.
- **Group jobs by model.** Switching between Z-Image (~20 GB of weights) and Qwen-Image 2.1
  (~23 GB incl. text encoder) evicts and reloads weights. Batched drafts then batched finals are
  materially faster than alternating.
- Budgets measured here: 10-slide deck ≈ 10 drafts @10 s + 10 finals @50 s ≈ **10 min** of GPU
  time (plus fixes), using Workflow A at 1280×720 drafts / 1920×1088 finals.

Reusable helper (queue → poll → crop → save), drop-in for an agent:

```python
import json, time, urllib.request
BASE = "http://192.168.23.216:8188"

def run(payload, out_path, timeout=1200, crop1080=True):
    req = urllib.request.Request(BASE + "/prompt", data=json.dumps({"prompt": payload}).encode(),
                                 headers={"Content-Type": "application/json"})
    pid = json.load(urllib.request.urlopen(req))["prompt_id"]
    deadline = time.time() + timeout
    while time.time() < deadline:
        h = json.load(urllib.request.urlopen(f"{BASE}/history/{pid}"))
        if h:
            status = h[pid]["status"]
            assert status["status_str"] == "success", status.get("messages")
            name = h[pid]["outputs"][list(h[pid]["outputs"])[0]]["images"][0]["filename"]
            blob = urllib.request.urlopen(f"{BASE}/view?type=output&filename={name}").read()
            open(out_path, "wb").write(blob)
            if crop1080:
                from PIL import Image
                im = Image.open(out_path)                      # 1920x1088 -> 1920x1080
                if im.size == (1920, 1088):
                    im.crop((0, 4, 1920, 1084)).save(out_path)
            return out_path
        time.sleep(5)
    raise TimeoutError(pid)
```

### 10.7 Consistency and reproducibility across a deck

- Record, per slide: the **full prompt**, the **seed**, the payload's model mode (A/B/C) and the
  crop step. Any of those missing makes the slide unreproducible.
- Append a **fixed style block** to every prompt in one deck (palette, style, "flat vector, high
  contrast, calm empty space on the right"), and keep the **negative prompt** identical. That is
  what makes a deck look like one deck.
- Keep the same **seed family** (e.g. one base seed + slide index) so re-rolls stay close.
- Prefer fixing a near-miss with **edit** (§10.2 A3) over re-rolling the whole slide.

### 10.8 Post-flight QA checklist

| Check | How |
|---|---|
| Exact text | read the words; any error → fix with an edit, never accept a near-miss |
| Size is exactly 1920×1080 | file properties / `PIL.Image.size` |
| Nothing important in the outer 5 % | visual — the deck tool may crop/scale |
| Text area still usable | is the promised empty space actually empty? |
| Consistency | same palette/style/typography as the rest of the deck |
| Alpha only where wanted | a cutout should show `alpha_minmax (0,255)`; t2i output is effectively opaque |
| Provenance | prompt + seed + mode recorded |
