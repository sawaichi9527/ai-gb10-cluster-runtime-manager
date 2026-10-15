#!/usr/bin/env python3
"""comfy-slide — render one presentation-sized image through the comfyui-jdaln service.

Fills the gap between "the guide documents the API" and "an agent needs one command per slide":
it builds the verified payload for the chosen model/mode, queues it, polls `/history`, downloads
the artefact with `/view` and (by default) crops the model's padded `1920x1088` output down to
exactly `1920x1080` so a 16:9 deck never letterboxes.

Modes (see docs/COMFYUI_JDALN_REMOTE_USAGE_GUIDE_2026-10-15.md §5b, §10, §5c, §5d):

  qwen21 a   render 1920x1088, 25 steps, cfg 1                        50 s   text-capable default
  qwen21 b   render 2752x1536 (native 2K 16:9 bucket)               111 s   hero / supersampled
  qwen21 c   1920x1088 with cfg 2.5 + a quality negative prompt      90 s   sharpest small text
  z-image a  1280x720, 4 steps, cfg 1                                10 s   fast concept draft
  z-image b  1920x1088, 4 steps, cfg 1                               20 s   final-look draft
  edit       instruction edit of --reference (Qwen-Image 2.1 edit)   20-100 s
  layers     decompose --reference into --layers RGBA layers         ~4 min @640x640 x2
             (output size follows the REFERENCE image, not --size; one PNG per layer)

Everything is verified against the live service except `--steps/--cfg` overrides, which pass
straight through.

Examples
  # a text-carrying slide, exactly 1920x1080 on disk
  ./scripts/comfy-slide.py --model qwen21 --mode a --out slide7.png \
      --prompt 'a clean modern slide background, deep navy and white, headline "Q3 Revenue Growth"'

  # the same look, one deck: keep the style block in a file and append it to every prompt
  ./scripts/comfy-slide.py --model qwen21 --mode c --style deck-style.txt --prompt '...' --out s8.png

  # cheap drafts of the same idea on Z-Image Turbo
  ./scripts/comfy-slide.py --model z-image --mode a --prompt '...' --out draft.png

  # edit an existing slide (text/colour fixes) at slide size
  ./scripts/comfy-slide.py --model edit --reference reference/slide.png \
      --prompt 'the headline must read exactly: Q4 Outlook' --out fixed.png

Env:
  COMFY_URL      default http://192.168.23.216:8188   (node1; node0 failover = 192.168.23.215)
  COMFY_TIMEOUT  per-request seconds for /prompt and /view (default 60)
  COMFY_WAIT     max seconds to wait for a result (default 1800; H3-length jobs need more)
"""
import argparse
import json
import os
import shutil
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

URL = os.environ.get("COMFY_URL", "http://192.168.23.216:8188").rstrip("/")
TIMEOUT = int(os.environ.get("COMFY_TIMEOUT", "60"))
WAIT = int(os.environ.get("COMFY_WAIT", "1800"))

QUALITY_NEG = ("blurry, low quality, distorted text, misspelled letters, garbled typography, "
               "watermark, jpeg artifacts, cluttered layout")

# ---------------------------------------------------------------- HTTP helpers


def _get(path, timeout=None):
    req = urllib.request.Request(URL + path, headers={"Accept": "application/json"})
    with urllib.request.urlopen(req, timeout=timeout or TIMEOUT) as r:
        body = r.read()
    try:
        return json.loads(body)
    except ValueError:
        return body


def _post(path, payload):
    data = json.dumps(payload).encode()
    req = urllib.request.Request(URL + path, data=data,
                                 headers={"Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=TIMEOUT) as r:
            return json.loads(r.read())
    except urllib.error.HTTPError as e:
        # ComfyUI returns 400 with a JSON body describing validation failures
        try:
            return json.loads(e.read())
        except Exception:
            raise SystemExit("HTTP %s from %s%s" % (e.code, URL, path))


def fetch(filename, subfolder, type_="output"):
    q = "filename=%s&subfolder=%s&type=%s" % (urllib.parse.quote(filename),
                                              urllib.parse.quote(subfolder or ""), type_)
    with urllib.request.urlopen(URL + "/view?" + q, timeout=max(TIMEOUT, 300)) as r:
        return r.read()


# ---------------------------------------------------------------- payloads


def graph_qwen21(prompt, negative, w, h, steps, cfg, seed):
    return {
        "1": {"class_type": "UNETLoader", "inputs": {"unet_name": "qwen_image_2.1_int8_convrot.safetensors", "weight_dtype": "default"}},
        "2": {"class_type": "QwenImage21Cache", "inputs": {"model": ["1", 0], "device": "auto", "dtype": "default"}},
        "3": {"class_type": "CLIPLoader", "inputs": {"clip_name": "qwen3vl_8b_int8_convrot.safetensors", "type": "qwen_image"}},
        "4": {"class_type": "TextEncodeQwenImage21", "inputs": {"clip": ["3", 0], "prompt": prompt,
                                                                "negative_prompt": negative, "resolution": 1024}},
        "5": {"class_type": "VAELoader", "inputs": {"vae_name": "qwen_image_2.1_vae_bf16.safetensors"}},
        "6": {"class_type": "EmptyLatentImage", "inputs": {"width": w, "height": h, "batch_size": 1}},
        "7": {"class_type": "KSampler", "inputs": {"model": ["2", 0], "positive": ["4", 0], "negative": ["4", 1],
                                                   "latent_image": ["6", 0], "seed": seed, "steps": steps,
                                                   "cfg": cfg, "sampler_name": "euler", "scheduler": "simple", "denoise": 1}},
        "8": {"class_type": "VAEDecode", "inputs": {"samples": ["7", 0], "vae": ["5", 0]}},
        "9": {"class_type": "SaveImage", "inputs": {"images": ["8", 0], "filename_prefix": "slide"}},
    }


def graph_zimage(prompt, negative, w, h, steps, cfg, seed):
    return {
        "1": {"class_type": "UNETLoader", "inputs": {"unet_name": "z_image_turbo_bf16.safetensors", "weight_dtype": "default"}},
        "2": {"class_type": "CLIPLoader", "inputs": {"clip_name": "qwen_3_4b.safetensors", "type": "lumina2"}},
        "3": {"class_type": "VAELoader", "inputs": {"vae_name": "ae.safetensors"}},
        "4": {"class_type": "ModelSamplingAuraFlow", "inputs": {"model": ["1", 0], "shift": 3}},
        "5": {"class_type": "EmptySD3LatentImage", "inputs": {"width": w, "height": h, "batch_size": 1}},
        "6": {"class_type": "CLIPTextEncode", "inputs": {"clip": ["2", 0], "text": prompt}},
        "7": {"class_type": "CLIPTextEncode", "inputs": {"clip": ["2", 0], "text": negative}},
        "8": {"class_type": "KSampler", "inputs": {"model": ["4", 0], "positive": ["6", 0], "negative": ["7", 0],
                                                   "latent_image": ["5", 0], "seed": seed, "steps": steps,
                                                   "cfg": cfg, "sampler_name": "res_multistep", "scheduler": "simple", "denoise": 1}},
        "9": {"class_type": "VAEDecode", "inputs": {"samples": ["8", 0], "vae": ["3", 0]}},
        "10": {"class_type": "SaveImage", "inputs": {"images": ["9", 0], "filename_prefix": "slide"}},
    }


def graph_edit(prompt, negative, reference, w, h, steps, cfg, seed, ref_resolution=1440):
    return {
        "1": {"class_type": "UNETLoader", "inputs": {"unet_name": "qwen_image_2.1_int8_convrot.safetensors", "weight_dtype": "default"}},
        "2": {"class_type": "QwenImage21Cache", "inputs": {"model": ["1", 0], "device": "auto", "dtype": "default"}},
        "3": {"class_type": "CLIPLoader", "inputs": {"clip_name": "qwen3vl_8b_int8_convrot.safetensors", "type": "qwen_image"}},
        "4": {"class_type": "TextEncodeQwenImage21", "inputs": {
            "clip": ["3", 0], "prompt": prompt, "negative_prompt": negative, "resolution": ref_resolution,
            "vae": ["5", 0], "images": {"image_1": ["6", 0]}}},
        "5": {"class_type": "VAELoader", "inputs": {"vae_name": "qwen_image_2.1_vae_bf16.safetensors"}},
        "6": {"class_type": "LoadImage", "inputs": {"image": reference}},
        "8": {"class_type": "EmptyLatentImage", "inputs": {"width": w, "height": h, "batch_size": 1}},
        "9": {"class_type": "KSampler", "inputs": {"model": ["2", 0], "positive": ["4", 0], "negative": ["4", 1],
                                                   "latent_image": ["8", 0], "seed": seed, "steps": steps,
                                                   "cfg": cfg, "sampler_name": "euler", "scheduler": "simple", "denoise": 1}},
        "10": {"class_type": "VAEDecode", "inputs": {"samples": ["9", 0], "vae": ["5", 0]}},
        "11": {"class_type": "SaveImage", "inputs": {"images": ["10", 0], "filename_prefix": "edit"}},
    }


def graph_layers(reference, w, h, layers, steps=20, cfg=2.5, seed=7):
    """Qwen-Image Layered: size follows --size, layer count is the node's 3rd argument."""
    return {
        "1": {"class_type": "UNETLoader", "inputs": {"unet_name": "qwen_image_layered_bf16.safetensors", "weight_dtype": "default"}},
        "2": {"class_type": "CLIPLoader", "inputs": {"clip_name": "qwen_2.5_vl_7b_fp8_scaled.safetensors", "type": "qwen_image"}},
        "3": {"class_type": "VAELoader", "inputs": {"vae_name": "qwen_image_layered_vae.safetensors"}},
        "4": {"class_type": "CLIPTextEncode", "inputs": {"clip": ["2", 0], "text": ""}},
        "5": {"class_type": "CLIPTextEncode", "inputs": {"clip": ["2", 0], "text": ""}},
        "6": {"class_type": "LoadImage", "inputs": {"image": reference}},
        "7": {"class_type": "GetImageSize", "inputs": {"image": ["6", 0]}},
        "8": {"class_type": "VAEEncode", "inputs": {"pixels": ["6", 0], "vae": ["3", 0]}},
        "9": {"class_type": "ReferenceLatent", "inputs": {"conditioning": ["4", 0], "latent": ["8", 0]}},
        "10": {"class_type": "ReferenceLatent", "inputs": {"conditioning": ["5", 0], "latent": ["8", 0]}},
        "11": {"class_type": "ModelSamplingAuraFlow", "inputs": {"model": ["1", 0], "shift": 1}},
        "12": {"class_type": "EmptyQwenImageLayeredLatentImage", "inputs": {"width": ["7", 0], "height": ["7", 1],
                                                                           "layers": layers, "batch_size": 1}},
        "13": {"class_type": "KSampler", "inputs": {"model": ["11", 0], "positive": ["9", 0], "negative": ["10", 0],
                                                    "latent_image": ["12", 0], "seed": seed, "steps": steps, "cfg": cfg,
                                                    "sampler_name": "euler", "scheduler": "simple", "denoise": 1}},
        "14": {"class_type": "LatentCut", "inputs": {"samples": ["13", 0], "dim": "t", "index": 1, "amount": 16384}},
        "15": {"class_type": "LatentCutToBatch", "inputs": {"samples": ["14", 0], "dim": "t", "slice_size": 1}},
        "16": {"class_type": "VAEDecode", "inputs": {"samples": ["15", 0], "vae": ["3", 0]}},
        "17": {"class_type": "SaveImage", "inputs": {"images": ["16", 0], "filename_prefix": "layers"}},
    }


# ---------------------------------------------------------------- post-processing


def crop_or_scale(path, target, scale_if_larger=True):
    """Make `path` exactly `target` (WxH): crop when the render is the padded 16:9 class,
    downscale-then-crop when it is a supersampled bucket. Returns a description or None."""
    tw, th = target
    try:
        from PIL import Image
    except ImportError:
        return _external_resize(path, target) or "skipped (no PIL and no ImageMagick)"
    im = Image.open(path)
    if im.size == (tw, th):
        im.close()
        return None
    if scale_if_larger and im.width > tw * 1.2:
        # supersampled render (e.g. 2752x1536 -> 1935x1080 -> crop 1920x1080)
        new_h = th
        new_w = round(im.width * th / im.height)
        inter = im.resize((new_w, new_h), Image.LANCZOS)
        left = (new_w - tw) // 2
        out = inter.crop((left, 0, left + tw, th))
        desc = "scaled %dx%d -> %dx%d then cropped to %dx%d" % (im.width, im.height, new_w, new_h, tw, th)
    else:
        left = max(0, (im.width - tw) // 2)
        top = max(0, (im.height - th) // 2)
        out = im.crop((left, top, left + tw, top + th))
        desc = "cropped %dx%d -> %dx%d (offset %d,%d)" % (im.width, im.height, tw, th, left, top)
    if out.mode not in ("RGB", "RGBA"):
        out = out.convert("RGBA" if "A" in im.getbands() else "RGB")
    out.save(path)
    return desc


def _external_resize(path, target):
    tw, th = target
    for exe, args in (("magick", ["%s", "-resize", "%dx%d^" % (tw, th), "-gravity", "center",
                                  "-crop", "%dx%d+0+0", "+repage", "%s"]),
                      ("convert", ["%s", "-resize", "%dx%d^" % (tw, th), "-gravity", "center",
                                   "-crop", "%dx%d+0+0", "+repage", "%s"])):
        if shutil.which(exe):
            cmd = [exe] + [a % path if "%s" in a else a for a in args]
            subprocess.run(cmd, check=True)
            return "resized with %s to %dx%d" % (exe, tw, th)
    return None


# ---------------------------------------------------------------- main flow


def run(payload, prefix_out, crop, wait=WAIT):
    r = _post("/prompt", {"prompt": payload, "client_id": "comfy-slide"})
    if "error" in r or r.get("node_errors"):
        print(json.dumps(r, indent=1))
        raise SystemExit("prompt rejected")
    pid = r["prompt_id"]
    t0 = time.time()
    while time.time() - t0 < wait:
        h = _get("/history/%s" % pid)
        if h:
            st = h[pid]["status"]
            if st.get("status_str") != "success":
                print(json.dumps(st.get("messages", st), indent=1)[:4000])
                raise SystemExit("execution failed")
            files, results = [], []
            for _, o in (h[pid].get("outputs") or {}).items():
                for key in ("images", "videos", "gifs"):
                    for im in (o.get(key) or []):
                        files.append((im.get("filename"), im.get("subfolder", "")))
            if not files:
                raise SystemExit("no outputs in history")
            multi = len(files) > 1
            for i, (fn, sub) in enumerate(files, 1):
                out = prefix_out if not multi else "%s-%d%s" % (os.path.splitext(prefix_out)[0], i,
                                                                os.path.splitext(prefix_out)[1])
                with open(out, "wb") as fh:
                    fh.write(fetch(fn, sub))
                desc = crop_or_scale(out, crop) if crop else None
                results.append({"file": os.path.abspath(out), "bytes": os.path.getsize(out),
                                "post": desc, "source": fn})
            return {"status": "success", "prompt_id": pid, "wall_s": round(time.time() - t0, 1),
                    "outputs": results}
        time.sleep(5)
    raise SystemExit("timeout after %ss waiting for %s" % (wait, pid))


def main():
    p = argparse.ArgumentParser(description="render a presentation image via comfyui-jdaln")
    p.add_argument("--model", choices=["qwen21", "z-image", "edit", "layers"], default="qwen21")
    p.add_argument("--mode", choices=["a", "b", "c"], default="a",
                   help="qwen21: a=1920x1088 25st cfg1 | b=2752x1536 hero | c=cfg2.5+quality negative. "
                        "z-image: a=1280x720 draft | b=1920x1088")
    p.add_argument("--prompt", default=None)
    p.add_argument("--prompt-file", default=None)
    p.add_argument("--style", default=None, help="file whose text is appended to every prompt (deck consistency)")
    p.add_argument("--negative", default=None)
    p.add_argument("--reference", default=None, help="input image name already on the node (edit/layers)")
    p.add_argument("--layers", type=int, default=3, help="layer count for --model layers")
    p.add_argument("--size", default=None,
                   help="WxH override, e.g. 1920x1088 (ignored by --model layers: that follows the reference)")
    p.add_argument("--steps", type=int, default=None)
    p.add_argument("--cfg", type=float, default=None)
    p.add_argument("--seed", type=int, default=20261015)
    p.add_argument("--out", default="slide.png")
    p.add_argument("--crop", default="auto", help="'auto' (1920x1080 for slide sizes), 'none', or WxH")
    p.add_argument("--base-url", default=None)
    p.add_argument("--check", action="store_true", help="print /system_stats and exit")
    p.add_argument("--models", action="store_true", help="print available model filenames and exit")
    p.add_argument("--dry-run", action="store_true", help="print the payload and exit")
    a = p.parse_args()

    global URL
    if a.base_url:
        URL = a.base_url.rstrip("/")

    if a.check:
        s = _get("/system_stats")
        q = _get("/queue")
        print(json.dumps({"url": URL, "comfyui": s["system"]["comfyui_version"],
                          "os": s["system"]["os"], "device": s["devices"][0]["name"],
                          "running": len(q.get("queue_running") or []),
                          "pending": len(q.get("queue_pending") or [])}, indent=1))
        return

    if a.models:
        oi = _get("/object_info", timeout=120)
        print(json.dumps({
            "unet": oi["UNETLoader"]["input"]["required"]["unet_name"][0],
            "clip": oi["CLIPLoader"]["input"]["required"]["clip_name"][0],
            "vae": oi["VAELoader"]["input"]["required"]["vae_name"][0],
            "input_images": oi["LoadImage"]["input"]["required"]["image"][0],
        }, indent=1))
        return

    prompt = a.prompt
    if a.prompt_file:
        prompt = open(a.prompt_file, encoding="utf-8").read().strip()
    if a.style:
        prompt = (prompt or "") + "\n\n" + open(a.style, encoding="utf-8").read().strip()
    if not prompt and a.model != "layers":
        raise SystemExit("--prompt or --prompt-file is required")

    # defaults per model/mode (measured values; see the guide)
    size = {"qwen21": {"a": (1920, 1088), "b": (2752, 1536), "c": (1920, 1088)},
            "z-image": {"a": (1280, 720), "b": (1920, 1088)}}.get(a.model, {}).get(a.mode)
    steps = {"qwen21": 25, "z-image": 4}.get(a.model, 25)
    cfg = {"qwen21": 1.0, "z-image": 1.0}.get(a.model, 1.0)
    negative = ""
    if a.model == "qwen21" and a.mode == "c":
        cfg, negative = 2.5, QUALITY_NEG
    if a.size:
        w, h = (int(x) for x in a.size.lower().split("x"))
        size = (w, h)
    if size is None:
        size = (1920, 1088) if a.model != "layers" else (1920, 1088)
    if a.steps is not None:
        steps = a.steps
    if a.cfg is not None:
        cfg = a.cfg
    if a.negative is not None:
        negative = a.negative

    if a.model == "qwen21":
        payload = graph_qwen21(prompt, negative, size[0], size[1], steps, cfg, a.seed)
    elif a.model == "z-image":
        payload = graph_zimage(prompt, negative, size[0], size[1], steps, cfg, a.seed)
    elif a.model == "edit":
        if not a.reference:
            raise SystemExit("--reference is required for --model edit")
        # resolution matched to the canvas: 16:9 reference at 1440 -> exactly 1920x1088
        ref_res = 1440 if (size[0] / size[1]) > 1.6 and size[0] >= 1800 else 1024
        payload = graph_edit(prompt, negative or QUALITY_NEG, a.reference, size[0], size[1],
                             steps, cfg, a.seed, ref_res)
    else:  # layers
        if not a.reference:
            raise SystemExit("--reference is required for --model layers")
        payload = graph_layers(a.reference, size[0], size[1], a.layers, seed=a.seed)

    crop = None
    if a.crop == "auto":
        if size == (1920, 1088):
            crop = (1920, 1080)
        elif size[0] > 1920:
            crop = (1920, 1080)
    elif a.crop != "none":
        crop = tuple(int(x) for x in a.crop.lower().split("x"))

    if a.dry_run:
        print(json.dumps({"url": URL, "model": a.model, "mode": a.mode, "size": size,
                          "steps": steps, "cfg": cfg, "seed": a.seed, "crop": crop,
                          "prompt": prompt}, indent=1))
        print(json.dumps(payload, indent=1))
        return

    res = run(payload, a.out, crop)
    res["model"], res["mode"], res["size"] = a.model, a.mode, size
    print(json.dumps(res, indent=1))


if __name__ == "__main__":
    main()
