#!/usr/bin/env bash
# =====================================================================
# mm-make-assets.sh — regenerate the multimodal smoke assets used by
# scripts/bench-mm-mimo.py, on the local node.
#
#   speech.wav  16 kHz mono: "The secret password is purple elephant."
#               (espeak-ng on the host; resampled by the image's ffmpeg)
#   motion.mp4  16 frames, 8 fps: a red square sliding right on white
#               (frames drawn with PIL; assembled by the image's ffmpeg)
#
# Needs: espeak-ng on the host, python3+PIL, and the lane image (for ffmpeg —
# the host has none). Output dir: $MM_ASSETS or
# ~/docker-stacks/logs/<profile>/assets.
# =====================================================================
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/cluster-common.sh"

load_profile "${MM_PROFILE:-mimo26flash}"
A="${MM_ASSETS:-$HOME/docker-stacks/logs/${PROFILE}/assets}"
mkdir -p "$A/frames"

echo "== speech (espeak-ng) =="
espeak-ng -w "$A/speech_raw.wav" "The secret password is purple elephant."

echo "== video frames (PIL) =="
python3 - "$A/frames" <<'PY'
import sys
from PIL import Image, ImageDraw
out = sys.argv[1]
for i in range(16):
    im = Image.new("RGB", (320, 240), "white")
    dr = ImageDraw.Draw(im)
    x = 20 + i * 17  # slide right across the frame
    dr.rectangle([x, 90, x + 60, 150], fill="red")
    im.save(f"{out}/f{i:02d}.png")
print("frames:", 16)
PY

echo "== resample + assemble (image ffmpeg: $IMG) =="
sdk docker run --rm --entrypoint bash -v "$A:/out" "$IMG" -c '
ffmpeg -y -loglevel error -i /out/speech_raw.wav -ar 16000 -ac 1 /out/speech.wav
ffmpeg -y -loglevel error -framerate 8 -i /out/frames/f%02d.png -c:v libx264 -pix_fmt yuv420p /out/motion.mp4
echo "ffmpeg rc=$?"'

ls -l "$A/speech.wav" "$A/motion.mp4"
echo "assets ready in $A"
