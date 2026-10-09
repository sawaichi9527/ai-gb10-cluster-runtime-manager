# Vendored DGX Spark DeepSeek-V4-Flash-Vision-Exp startup hotfixes

These files are copied verbatim from:

- Upstream: https://github.com/MiaAI-Lab/DeepSeek-v4-Flash-DSpark-2x-DGX-Spark
- Commit:   `97e8733238f81f5fdc44b241f8996a7858825744`
- License:  MIT (see the upstream repository `LICENSE`)

They are mounted read-only into the `deepseek-vision` container at
`/opt/dspark-patches` and applied at container start by the profile's
`CMD_WRAPPER` (see `cluster-profiles.d/deepseek-vision.conf`), BEFORE
`vllm serve` runs. `vision_exp/` is the native ViT/Aligner + image processor
payload required by `hotfix-dsv4-vision-exp.py`.

Do not edit these files locally; re-vendor from upstream when the recipe
updates. The base image is the unmodified Anemll runtime
`ghcr.io/anemll/dspark-vllm-gx10:0.1.1` (same image as the mainline deepseek
profile); all vision support lives in these patches, not in the image.
