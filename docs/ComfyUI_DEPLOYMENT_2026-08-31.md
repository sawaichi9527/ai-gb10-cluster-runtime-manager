# ComfyUI (Flux 2 Dev) Deployment — Node1 Dedicated

**Date:** 2026-08-31
**Runtime:** `comfyui` (`runtimes.d/comfyui.conf`, GROUP=image, MODE=exclusive)
**Host:** Node1 (spark-8095, 192.168.23.216) — dedicated, no shared storage with Node0
**Image:** `ghcr.io/aeon-7/aeon-spark:slim` (digest pinned `7fda74d7af1d`, matches Node0)
**Result:** ✅ Verified — Flux 2 Dev t2i image produced (`flux2_n1_verify_00001_.png`, 1,332,159 bytes)

---

## 1. Prerequisites

- **Memory**: Both TP2 runtimes (35B-A3B master + rank1) must be stopped first — Node1 has ~16 GB free while TP2 runs; Flux 2 Dev needs ~71 GB.
  - Stop via `bash scripts/tp2-down` on **Node0** (`~/ai-gb10-cluster-runtime-manager`). This tears down both `tp2-node0` and `tp2-node1`.
  - Pre-approved swap: "tp2-down → ComfyUI".
- **HF token**: Node1 needs a HuggingFace token (gated access). Copied from Node0 via scp with `~/.ssh/id_gb10_cluster`:
  - lands at `workspace/.cache/huggingface/token`.
- **Image**: `comfyui-aeon:slim` pulled to Node1 (digest matches Node0's pin).

## 2. Stack provision (Node1)

Stack dir: `/home/eye/docker-stacks/comfyui-aeon/`

- `docker-compose.yml` — `comfyui-aeon:slim` pinned digest, hostname `comfyui-work`, container `comfyui-spark`, port 8188.
  - Flags: `--use-sage-attention --disable-pinned-memory --reserve-vram 2.0 --enable-cors-header --enable-manager --enable-assets`
  - `SKIP_MODEL_DOWNLOAD=1` (models placed manually), `shm_size: 32gb`, healthcheck on `/system_stats` (start_period 600s).
- `.env` — `COMFYUI_PORT=8188`.
- `workspace/` — model subdirs (`diffusion_models/`, `text_encoders/`, `vae/`, `loras/`) + HF cache.

## 3. Flux 2 Dev model download (~71 GB)

AEON image ships `/usr/local/bin/download_models.py` (Flux 2 Dev-first, all-or-nothing incl. LTX 2.3). For **Flux 2 Dev only**, a selective downloader was used:

| File | Destination | Size |
|---|---|---|
| `flux2_dev_fp8mixed.safetensors` (Comfy-Org/flux2-dev) | `models/diffusion_models/` | 35.46 GB |
| `mistral_3_small_flux2_bf16.safetensors` (text encoder, best quality) | `models/text_encoders/` | 35.58 GB |
| `flux2-vae.safetensors` | `models/vae/` | 336 MB |
| `full_encoder_small_decoder.safetensors` (FLUX.2-small-decoder) | `models/vae/` | 250 MB |
| `Flux2TurboComfyv2.safetensors` (turbo LoRA) | `models/loras/` | 2.76 GB |

Download command (backgrounded, `--rm` container auto-removes on exit):
```bash
docker run --rm --name n1-flux2-dl \
  -v <workspace>:/workspace/ComfyUI \
  -v <stack>/dl_flux2.py:/dl_flux2.py:ro \
  -e HF_HOME=/workspace/ComfyUI/.cache/huggingface \
  -e HF_HUB_ENABLE_HF_TRANSFER=1 \
  --entrypoint python ghcr.io/aeon-7/aeon-spark:slim /dl_flux2.py
```

### ⚠️ Gotcha: nested `split_files/` placement

`hf_hub_download(local_dir=...)` writes into `<sub>/split_files/<sub>/file.safetensors` — ComfyUI scans model dirs **directly** (no recursion), so files must be **flattened**:
```bash
# run as root (files are root-owned from the container)
echo "$SUDO_PASS" | sudo -S mv \
  models/diffusion_models/split_files/diffusion_models/flux2_dev_fp8mixed.safetensors \
  models/diffusion_models/flux2_dev_fp8mixed.safetensors
```
After flatten, remove empty `split_files` trees. Verify: `curl http://127.0.0.1:8188/models/<sub>` returns the filenames.

## 4. Launch & verify

```bash
# on Node0 (dispatches docker compose to Node1)
bash bin/gb10-single use node1 comfyui
```

- Container starts, healthcheck `healthy` after ~start_period.
- `curl http://127.0.0.1:8188/system_stats` → READY.
- Models detected in all 4 subdirs (see §3 table).

### t2i verification workflow

Flux 2 Dev is a **diffusion model** — use `UNETLoader` (NOT `CheckpointLoaderSimple`), plus `CLIPLoader`, `VAELoader`, `FluxGuidance`, `Flux2Scheduler`, `SamplerCustomAdvanced`. Required inputs: `UNETLoader.weight_dtype="default"`, `CLIPLoader.type="flux2"`.

```python
WORKFLOW = {
  "12": {"class_type":"UNETLoader","inputs":{"unet_name":"flux2_dev_fp8mixed.safetensors","weight_dtype":"default"}},
  "38": {"class_type":"CLIPLoader","inputs":{"clip_name":"mistral_3_small_flux2_bf16.safetensors","type":"flux2","options":"default"}},
  "10": {"class_type":"VAELoader","inputs":{"vae_name":"full_encoder_small_decoder.safetensors"}},
  "6":  {"class_type":"CLIPTextEncode","inputs":{"text":"A serene mountain lake at sunrise, photorealistic, high detail","clip":["38",0]}},
  "26": {"class_type":"FluxGuidance","inputs":{"conditioning":["6",0],"guidance":4}},
  "22": {"class_type":"BasicGuider","inputs":{"model":["12",0],"conditioning":["26",0]}},
  "16": {"class_type":"KSamplerSelect","inputs":{"sampler_name":"euler"}},
  "48": {"class_type":"Flux2Scheduler","inputs":{"steps":20,"width":1024,"height":1024}},
  "25": {"class_type":"RandomNoise","inputs":{"noise_seed":1027111520328378,"control_after_generate":"randomize"}},
  "13": {"class_type":"SamplerCustomAdvanced","inputs":{"noise":["25",0],"guider":["22",0],"sampler":["16",0],"sigmas":["48",0],"latent_image":["47",0]}},
  "47": {"class_type":"EmptyFlux2LatentImage","inputs":{"width":1024,"height":1024,"batch_size":1}},
  "8":  {"class_type":"VAEDecode","inputs":{"samples":["13",0],"vae":["10",0]}},
  "9":  {"class_type":"SaveImage","inputs":{"filename_prefix":"flux2_n1_verify","images":["8",0]}}
}
```

Result: `20/20 [00:54]`, `Prompt executed in 303.39 seconds` → `output/flux2_n1_verify_00001_.png`.

## 5. conf summary (`runtimes.d/comfyui.conf`)

```
RUNTIME_ID="comfyui"
DISPLAY_NAME="AEON ComfyUI (Node1 dedicated · Flux 2.0 Dev)"
ALIASES="comfy"
MODE="exclusive"
GROUP="image"
STACK_DIR="${HOME}/docker-stacks/comfyui-aeon"
COMPOSE_FILE="docker-compose.yml"
PROJECT="comfyui-aeon"
SERVICE="comfyui"
CONTAINER="comfyui-spark"
IDENTITY_MOUNT="/workspace/ComfyUI"
HEALTH_URL="http://127.0.0.1:8188/system_stats"
TIMEOUT="900"
```

## 6. Notes / follow-ups

- `GROUP=image` means `gb10-single use node1 comfyui` does **not** stop other group=image single-node runtimes, but **auto-tears down TP2** first (做法 B: `ensure_tp2_down` runs `scripts/tp2-down` if `tp2-node0` is active). Reverse direction: `gb10 use 27b|35b` auto-frees node1 (`gb10-single free node1`) before TP2 up.
- Stage 3 (TP2-xDiT CLI pipeline, Qwen-Image 20B) pending: bf16-only xdit-poc may conflict with Node0's fp8/nvfp4 models (sm_121 NaN note still open).
