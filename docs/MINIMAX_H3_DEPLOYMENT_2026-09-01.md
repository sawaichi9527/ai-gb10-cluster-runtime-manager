# MiniMax H3 (FL2VA) Deployment — Node1 Single-Node

**Date:** 2026-09-01
**Runtime:** `minimaxh3` (`runtimes.d/minimaxh3.conf`, GROUP=video, MODE=exclusive)
**Host:** Node1 (spark-8095, 192.168.23.216) — single-node vLLM-Omni FP8 (no TP2/shared storage with Node0)
**Image:** `minimax-h3-dgx-spark:sm121-fp8` (base pinned `vllm/vllm-omni:minimax-h3@sha256:e930db8e225162d01e17a49dddc43fd0e844208908d8356a028e5c4e7357696e`)
**Status:** ⏳ downloaded & provisioned — bring-up (Phase 5) awaits operator go (TP2 currently running on Node1)

---

## 1. Decisions (operator approved)

1. `bin/gb10-single` cross-group exclusive stop — starting an exclusive runtime frees every other
   active *exclusive* runtime on that node across groups (video vs image). Committed `1e36235`.
2. API binds `0.0.0.0` + `H3_ALLOW_REMOTE_API=true` + strong `H3_API_KEY` (`openssl rand -hex 32`, server-side).
3. Node0 replica copy only after Node1 deploy succeeds (dedicated connection via `~/.ssh/id_gb10_cluster`).

## 2. Stack provision (Node1) ✅

Stack dir: `/home/eye/docker-stacks/minimax-h3/`

- Recipe: `joeynyc/MiniMax-H3-DGX-Spark` (single-node `compose.yaml`, NOT `docker-compose.yml`).
- `compose.yaml` — service `minimax-h3`, container `minimax-h3-fl2va`, `network_mode: host`,
  `shm_size: 8gb`, `gpus: all`; volumes `${MINIMAX_H3_MODEL_DIR}:/models/MiniMax-H3/FL2VA:ro` +
  `${HF_CACHE_DIR}:/root/.cache/huggingface` + `./output:/output`; `VLLM_API_KEY=${H3_API_KEY:-}`.
  No container-level `healthcheck` (CLI `HEALTH_URL` probes externally).
- `.env` — written via sftp + server-side `chmod 600`, then `H3_API_KEY=__GENERATE__` replaced by
  `openssl rand -hex 32` (`sed`). `docker compose config --quiet` → `COMPOSE_CONFIG_OK`.
  Key variables: `H3_BIND_HOST=0.0.0.0`, `H3_API_PORT=8000`, `H3_ALLOW_REMOTE_API=true`,
  `H3_VIDEO_SYNC_TIMEOUT=7200`, `H3_DIFFUSION_ATTENTION_BACKEND=CUDNN_ATTN`,
  `H3_EXECUTION_MODE=compile`, `H3_CACHE_BACKEND=none`, `MINIMAX_H3_MODEL_DIR=.../FL2VA`,
  `HF_CACHE_DIR=.../.cache/huggingface`, `MINIMAX_H3_LICENSE_ACKNOWLEDGED=true`.
- `verify-h3-download.py` — sha256 spot-check helper (left in stack dir).

## 3. Model download — FL2VA (~134.2 GiB) ✅

Source: HF `MiniMaxAI/MiniMax-H3` (`FL2VA/*` subset = **81 files**, 144,051,000,000 bytes).

```bash
# idempotent; resume via .incomplete; watchdog may re-run the exact script
~/docker-stacks/minimax-h3/launch-download.sh
# equivalent: hf download MiniMaxAI/MiniMax-H3 --include "FL2VA/*" \
#   --local-dir ~/docker-stacks/minimax-h3/models/MiniMax-H3    (NOT .../FL2VA — double-nesting trap)
```

- Ran 17:03:23 → completed (~18:0x). One real stall (~17:56:47, sockets ESTAB-idle + 4× du 0-delta) —
  SIGTERM exact PID (exit 143) + relaunch of the same script (resume OK, `.incomplete` preserved).
- **Verification (PASS)**: re-run `hf download` → `rc=0`, `81/81 ✓ Downloaded`;
  largest 3 shards (10.42 GB + 5.23 GB + 5.16 GB) sha256 **match** upstream `list_repo_tree` lfs hashes;
  `find FL2VA -type f | wc -l` = 81; `du -sb FL2VA` = 144,051,182,625 (≈ API total, +182,625 slack).
- Leftover staging `.cache/huggingface` (~4.6 GB) kept; safe to delete after Phase 5 succeeds.
- ffmpeg: `~/bin/ffmpeg-master-latest-linuxarm64-gpl/bin/ffmpeg` (N-126342, BtbN linuxarm64-gpl),
  symlinked `~/.local/bin/ffmpeg`; `DL_OK`. Upstream static asset 404s on the `latest` main file — this release asset works.

## 4. CLI / config changes ✅ (committed `1e36235` + `ab2eba4`, Node0 synced to `ab2eba4`)

- `bin/gb10-single` `stop_group_except`: stops every OTHER active **exclusive** runtime on the node,
  **across groups** (skips placeholders and the target itself; TP2 handled by `ensure_tp2_down`).
- `runtimes.d/minimaxh3.conf`:

```
RUNTIME_ID="minimaxh3"
DISPLAY_NAME="MiniMax H3 (FL2VA video generation)"
ALIASES="minimax mm-h3 h3"
MODE="exclusive"
GROUP="video"
PLACEHOLDER="false"
STACK_DIR="${HOME}/docker-stacks/minimax-h3"
COMPOSE_FILE="compose.yaml"
PROJECT="minimax-h3-dgx-spark"
SERVICE="minimax-h3"
CONTAINER="minimax-h3-fl2va"
IDENTITY_MOUNT=""
HEALTH_URL="http://127.0.0.1:8000/health"
TIMEOUT="2400"        # cold start ~9 min + margin
```

## 5. Launch & verify — ⏳ pending operator go (Phase 5)

```bash
# on Node0 (dispatches docker compose to Node1); auto-tears down TP2 (做法 B) and frees other
# exclusive runtimes first (e.g. comfyui if ever live there — none today)
bash bin/gb10-single use node1 minimaxh3
```

- Preflight/`make build` is **deferred** until after tp2-down: preflight memory gate requires
  ≥105 GiB MemAvailable when the container isn't running (Node1 currently ~8 GiB free under TP2).
  `make build` = preflight + `docker compose build`; base image is pinned + only patch COPY layers → fast.
- Wait: `HEALTH_URL` `/health` on 127.0.0.1:8000 (vLLM `/health` is auth-free; `/v1/*` requires bearer).
  Smoke via recipe script; expect cold start 519–543 s, peak ~93 GB → produce 768×448 / 24fps / H.264+AAC clip.
- Verify `/health`, `/v1/...` with bearer: `Authorization: Bearer ${H3_API_KEY}` (key lives only on Node1 `.env`).
- After success: Node0 replica = rsync/scp `/home/eye/docker-stacks/minimax-h3` via `~/.ssh/id_gb10_cluster`.

## 6. Notes / follow-ups

- `GROUP=video` vs comfyui `GROUP=image`: cross-group exclusive stop = operator-approved general rule
  (comfyui.conf stays `PLACEHOLDER=true` intentionally — new version pending; Node1 currently hosts only
  `tp2-node1`, no comfyui container).
- `/health` auth & wait_ready behavior to be confirmed once, at first bring-up.
- xet stage `.cache/huggingface` (~4.6 GB) removable post-success.