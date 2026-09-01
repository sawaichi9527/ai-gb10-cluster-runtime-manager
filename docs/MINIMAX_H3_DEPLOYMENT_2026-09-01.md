# MiniMax H3 (FL2VA) Deployment — Node1 Single-Node

**Date:** 2026-09-01
**Runtime:** `minimaxh3` (`runtimes.d/minimaxh3.conf`, GROUP=video, MODE=exclusive)
**Host:** Node1 (spark-8095, 192.168.23.216) — single-node vLLM-Omni FP8 (no TP2/shared storage with Node0)
**Image:** `minimax-h3-dgx-spark:sm121-fp8` (base pinned `vllm/vllm-omni:minimax-h3@sha256:e930db8e225162d01e17a49dddc43fd0e844208908d8356a028e5c4e7357696e`)
**Status:** ✅ **DEPLOYED & VERIFIED (2026-09-01)**
- Node1: `minimax-h3-fl2va` running, `/health` = `200` (cold start ≈ 11.9 min), smoke `t2va` PASS (H.264 768×448@24fps + AAC).
- Node0: failover mirror rsync in progress (`~/.ssh/id_gb10_cluster`, interconnect `10.0.101.x`).
- TP2 torn down first (operator-approved Phase 5).

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

## 4. CLI / config changes ✅ (committed `1e36235` + `ab2eba4`; docs `f950a24`; Node0 synced to `f950a24`)

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

## 5. Launch & verify — ✅ DONE (2026-09-01)

```bash
# on Node0 (dispatches docker compose to Node1); tears down TP2 (approved) and frees exclusive runtimes
bash bin/gb10-single use node1 minimaxh3      # reference; see execution notes below
```

**Execution notes (MCP-driven):**

- TP2 removed first: `docker rm -f tp2-node1` (Node1) + `docker rm -f tp2-node0` (Node0) —
  eye has docker.sock group access on both nodes, so the `sudo`+`SUDO_PASS` path was never needed
  (Node0 `tp2.env` has no `SUDO_PASS`, non-interactive `sudo` would fail).
  MemAvailable on Node1 → 117 GiB, preflight memory gate (≥105 GiB) satisfied.
- `make build`: preflight passed; image `minimax-h3-dgx-spark:sm121-fp8` = **32 GB** built
  (base layers ~10 GB streamed; BuildKit `docker compose build`).
- Launched via `docker compose -p minimax-h3-dgx-spark -f …/compose.yaml up -d` (equivalent to the CLI
  path; `gb10-single status node1 minimaxh3` reflects **running / READY** via container inspect).
  MCP note: interactive sessions do not self-exec the open-session `command` — dispatch through
  `run-command(session=…)`; long builds/waits need `nohup … </dev/null &` inside a session because a
  60 s tool-timeout kills the process tree.
- Cold start: container up ≈14:57 → app startup complete 15:09:20 UTC (`/health` 200) ≈ **11.9 min**;
  weights (13 shards) took 157.9 s; `serving_time_to_first_output` 130.7 s on first request.
- Smoke: `POST /v1/videos/sync` (768×448, 20 steps, 24fps, 2.0 s, seed 42) → HTTP 200, elapsed 132.2 s.
- Verify (`verify-output.sh …/output/smoke-t2va.mp4`) — **full_decode=passed**:
  - Video: H.264 Constrained Baseline, 768×448, yuv420p, 24/1 fps, 56 frames, 2.333 s, ~2.0 Mbps
  - Audio: AAC-LC, 32 kHz, stereo, 2.357 s, ~125 kbps (audio_flow_shift 3.0 — model-generated audio)
  - size 628,877 B · sha256 `52e7e54703b24341685c8f5e3076844541a4422589019ba9bc4b2451b1bb9dce`
- Cosmetic: vLLM-Omni 0.1.dev2381 vs vLLM 0.26.0 mismatch RuntimeWarning at startup (base-image noise,
  non-fatal). `status node1` shows STATE `null` for other non-running runtimes (display quirk only).
- `/health` is auth-free (confirmed), `/v1/*` requires `Authorization: Bearer ${H3_API_KEY}` (Node1 `.env`).

**Node0 replica (in progress):**

```bash
rsync -aAX --partial --exclude 'models/MiniMax-H3/.cache' \
  -e 'ssh -i /home/eye/.ssh/id_gb10_cluster' \
  eye@10.0.101.102:/home/eye/docker-stacks/minimax-h3/ \
  /home/eye/docker-stacks/minimax-h3/
```

## 6. Notes / follow-ups

- `GROUP=video` vs comfyui `GROUP=image`: cross-group exclusive stop = operator-approved general rule
  (comfyui.conf stays `PLACEHOLDER=true` intentionally — new version pending; Node1 currently hosts only
  `minimaxh3` after TP2 teardown).
- `/health` auth & wait_ready behavior confirmed: `/health` auth-free; READY gate works via container inspect.
- xet stage `.cache/huggingface` (~4.3 GB) moved to `/tmp/minimax-h3-xet-cache.trash` (post-success cleanup).
- ffprobe PATH fix: `~/.local/bin` not in tooling PATH → `smoke-t2va.sh` + `verify-output.sh` now prepend
  it when present (no-root alternative to `/usr/local/bin` symlink, which would need server sudo).