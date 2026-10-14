# src/ — vendored reference sources

Sources pinned beside this repo. `runtimes.d/*.conf` reference deployment
targets; `src/` holds upstream source checked in for provenance/pinning.

**Currently empty of vendored sources.**

The only entry ever placed here was `minimax-h3/` (the MiniMax H3 FL2VA
reference implementation backing `runtimes.d/minimaxh3.conf`). The `minimaxh3`
runtime was **retired 2026-10-14** and the directory was removed with it —
Node1's stack `~/docker-stacks/minimax-h3/` (135 GB) and image
`minimax-h3-dgx-spark:sm121-fp8` (32 GB) are gone too. MiniMax H3
image-to-video is now served by `comfyui-jdaln`'s native ComfyUI nodes
(`comfy_extras.nodes_minimax_h3` + `ComfyUI-MiniMaxH3-Easy`), which were
render-verified before the lane was dismantled.

Keep this directory for future vendored sources: when a runtime needs a pinned
upstream tree for provenance, add `<name>/` here **and** a matching
`runtimes.d/<name>.conf`.
