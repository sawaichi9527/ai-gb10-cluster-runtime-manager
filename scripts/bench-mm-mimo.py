#!/usr/bin/env python3
"""bench-mm-mimo — image / audio / video smoke test for the mimo26flash lane.

Correctness-oriented (not a throughput bench):
  * image  — draws a known image locally (red square, blue circle, green
             triangle, "MIMO 42") and asks the model to list shapes + read text.
  * audio  — sends a speech WAV in both request shapes vLLM accepts
             (`input_audio` and `audio_url`) and asks for the password.
  * video  — sends an MP4 (red box sliding right on white) and asks what moves
             and which direction.

Modeled on the recipe's tests/mimo_vision.py and tests/mimo_media.py, adapted to
the unified endpoint (model id `aeon`, bearer auth).

Env:
  VLLM_API_KEY   bearer key (from cluster.env; EMPTY => no auth)
  MM_URL         default http://127.0.0.1:1234/v1/chat/completions
  MM_MODEL       default aeon
  MM_WAV         speech WAV path (default ~/docker-stacks/logs/mimo26flash/assets/speech.wav)
  MM_MP4         motion MP4 path (default ~/docker-stacks/logs/mimo26flash/assets/motion.mp4)
"""
import base64
import io
import json
import os
import sys
import time
import urllib.error
import urllib.request

URL = os.environ.get("MM_URL", "http://127.0.0.1:1234/v1/chat/completions")
KEY = os.environ.get("VLLM_API_KEY", "")
MODEL = os.environ.get("MM_MODEL", "aeon")
ASSETS = os.path.expanduser("~/docker-stacks/logs/mimo26flash/assets")
WAV = os.environ.get("MM_WAV", os.path.join(ASSETS, "speech.wav"))
MP4 = os.environ.get("MM_MP4", os.path.join(ASSETS, "motion.mp4"))


def ask(parts, label, max_tokens=300, temp=0.0):
    body = {"model": MODEL, "max_tokens": max_tokens, "temperature": temp,
            "chat_template_kwargs": {"enable_thinking": False},
            "messages": [{"role": "user", "content": parts}]}
    req = urllib.request.Request(URL, json.dumps(body).encode(),
                                 {"Content-Type": "application/json"})
    if KEY and KEY != "EMPTY":
        req.add_header("Authorization", "Bearer " + KEY)
    t = time.time()
    try:
        r = json.load(urllib.request.urlopen(req, timeout=900))
        c = r["choices"][0]["message"]["content"]
        pt = r["usage"]["prompt_tokens"]
        print(f"{label:20s} {time.time()-t:6.1f}s prompt_tokens={pt:6d}: {c[:400]!r}", flush=True)
        return c
    except urllib.error.HTTPError as e:
        print(f"{label:20s} HTTP {e.code}: {e.read().decode()[:300]}", flush=True)
        return None


def draw_image():
    from PIL import Image, ImageDraw
    img = Image.new("RGB", (512, 384), "white")
    d = ImageDraw.Draw(img)
    d.rectangle([40, 40, 220, 200], fill="red")
    d.ellipse([280, 60, 470, 250], fill="blue")
    d.polygon([(120, 360), (220, 230), (320, 360)], fill="green")
    d.text((300, 320), "MIMO 42", fill="black")
    b = io.BytesIO()
    img.save(b, "PNG")
    return "data:image/png;base64," + base64.b64encode(b.getvalue()).decode()


def b64(path):
    with open(path, "rb") as f:
        return base64.b64encode(f.read()).decode()


def main():
    print(f"harness: model={MODEL} url={URL}")
    ask([{"type": "image_url", "image_url": {"url": draw_image()}},
         {"type": "text", "text": "List every shape in this image with its color, and read any text."}],
        "image")
    if os.path.isfile(WAV):
        data = b64(WAV)
        ask([{"type": "input_audio", "input_audio": {"data": data, "format": "wav"}},
             {"type": "text", "text": "Transcribe this audio exactly, then tell me the secret password."}],
            "audio(input_audio)")
        ask([{"type": "audio_url", "audio_url": {"url": "data:audio/wav;base64," + data}},
             {"type": "text", "text": "What is the secret password in this audio?"}],
            "audio(audio_url)")
    else:
        print(f"skip audio: {WAV} not found")
    if os.path.isfile(MP4):
        ask([{"type": "video_url", "video_url": {"url": "data:video/mp4;base64," + b64(MP4)}},
             {"type": "text", "text": "Describe this video: what object is shown, what color is it, and which direction does it move?"}],
            "video")
    else:
        print(f"skip video: {MP4} not found")


if __name__ == "__main__":
    sys.exit(main())
