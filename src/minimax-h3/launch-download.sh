#!/usr/bin/env bash
# MiniMax H3 FL2VA download (idempotent; hf resumes via .incomplete). Watchdog may rerun.
# Checkpoint dir after run: ~/docker-stacks/minimax-h3/models/MiniMax-H3/FL2VA
set -uo pipefail
export PATH="$HOME/.local/bin:$PATH"
export HF_XET_HIGH_PERFORMANCE=1
export HF_HUB_DISABLE_TELEMETRY=1
TOKEN_FILE="$HOME/docker-stacks/comfyui-aeon/workspace/.cache/huggingface/token"
if [ -f "$TOKEN_FILE" ]; then
  export HF_TOKEN="$(cat "$TOKEN_FILE")"
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] using HF_TOKEN from comfyui workspace"
else
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] WARNING: no HF_TOKEN, anonymous download"
fi
log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }
log "start hf download FL2VA -> $HOME/docker-stacks/minimax-h3/models/MiniMax-H3"
hf download MiniMaxAI/MiniMax-H3 \
  --include "FL2VA/*" \
  --local-dir "$HOME/docker-stacks/minimax-h3/models/MiniMax-H3"
rc=$?
log "hf download exit=$rc"
exit $rc