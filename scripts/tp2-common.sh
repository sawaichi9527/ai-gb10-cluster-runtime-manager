#!/usr/bin/env bash
# =====================================================================
# tp2-common.sh — shared env load + profile table for gb10-cluster
# Sourced by every scripts/tp2-* entrypoint. NOT meant to be run alone.
# =====================================================================
set -Eeuo pipefail

# ---- resolve this script dir (repo root/scripts) independent of CWD ----
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

# ---- load tp2.env if present (gitignored) else defaults from example ----
ENV_FILE="${REPO_DIR}/tp2.env"
if [[ -f "${ENV_FILE}" ]]; then
  # shellcheck disable=SC1090
  source "${ENV_FILE}"
else
  # shellcheck disable=SC1090
  source "${REPO_DIR}/tp2.env.example"
fi

: "${IMG:?tp2.env missing IMG}"
: "${MASTER_ADDR:?tp2.env missing MASTER_ADDR}"
: "${MASTER_PORT:?tp2.env missing MASTER_PORT}"
: "${API_PORT:=8000}"

# ---- SUDO_PASS: prefer env, else prompt (never stored in repo) ----
_sudo_pass(){
  if [[ -n "${SUDO_PASS:-}" ]]; then echo "$SUDO_PASS"; return; fi
  if [[ -t 0 ]]; then
    read -rsp "sudo password for docker on both nodes: " SUDO_PASS
    echo >&2 ""
  else
    echo "ERROR: SUDO_PASS is required (export it or add to tp2.env)" >&2
    exit 1
  fi
  echo "$SUDO_PASS"
}
SUDO_PASS="$(_sudo_pass)"

# ---- docker helper (sudo on local Node0) ----
sdk(){ echo "$SUDO_PASS" | sudo -S "$@" 2>/dev/null; }

# =====================================================================
# Profile -> runtime parameters (verified 2026-08-30)
#  profile    body model                          drafter
#  ---------  ----------------------------------  ---------------------
#  default 27b  qwen3.8-27b-aeon-ultimate-...nvfp4  qwen3.8-27b-dflash2 (dflash n=7)
#  35b        qwen3.6-35b-a3b-heretic-nvfp4         qwen3.6-35b-a3b-dflash (dflash n=11)
# =====================================================================
MODELS_BASE="${NODE0_MODELS_BASE:-$HOME/docker-stacks/aeon-vllm/models}"

# set_profile <27b|35b>  -> sets PROFILE, BODY, DRAF, MAXLEN, NUMSEQ,
#                           BATCHED, GMU, NSPEC
set_profile(){
  case "${1:-27b}" in
    27b|a|A)
      PROFILE="27b"
      BODY="${MODELS_BASE}/qwen3.8-27b-aeon-ultimate-uncensored-nvfp4"
      DRAF="${MODELS_BASE}/qwen3.8-27b-dflash2"
      MAXLEN=262144; NUMSEQ=8; BATCHED=16384; GMU=0.85; NSPEC=7
      ;;
    35b|b|B)
      PROFILE="35b"
      BODY="${MODELS_BASE}/qwen3.6-35b-a3b-heretic-nvfp4"
      DRAF="${MODELS_BASE}/qwen3.6-35b-a3b-dflash"
      MAXLEN=131072; NUMSEQ=16; BATCHED=16384; GMU=0.80; NSPEC=11
      ;;
    *)
      echo "ERROR: unknown profile '$1' (use 27b [default] or 35b)" >&2
      exit 2
      ;;
  esac
}

# Common vLLM args shared by rank0 and rank1 for a profile.
# USAGE: build_vllm_args rank  (rank=0|1) -> echoes array via $VLLM_ARGS
build_vllm_args(){
  local rank="$1"
  local ib_ifname ib_hca ib_gid host_ip
  if [[ "$rank" == "0" ]]; then
    host_ip="${NODE0_IP}"; ib_ifname="${NODE0_SOCKET_IFNAME:-$NCCL_SOCKET_IFNAME}"
    ib_hca="${NODE0_IB_HCA:-$NCCL_IB_HCA}"; ib_gid="${NODE0_IB_GID_INDEX:-$NCCL_IB_GID_INDEX}"
  else
    host_ip="${NODE1_IP}"; ib_ifname="${NODE1_SOCKET_IFNAME:-$NCCL_SOCKET_IFNAME}"
    ib_hca="${NODE1_IB_HCA:-$NCCL_IB_HCA}"; ib_gid="${NODE1_IB_GID_INDEX:-$NCCL_IB_GID_INDEX}"
  fi

  VLLM_ARGS=(
    --served-model-name aeon
    --host 0.0.0.0
  )
  [[ "$rank" == "0" ]] && VLLM_ARGS+=(--port "${API_PORT}")
  [[ "$rank" == "1" ]] && VLLM_ARGS+=(--headless)
  VLLM_ARGS+=(
    --tensor-parallel-size 2
    --nnodes 2
    --node-rank "${rank}"
    --master-addr "${MASTER_ADDR}"
    --master-port "${MASTER_PORT}"
    --quantization compressed-tensors
    --kv-cache-dtype fp8_e4m3
    --attention-backend TRITON_ATTN
    --max-model-len "${MAXLEN}"
    --max-num-seqs "${NUMSEQ}"
    --max-num-batched-tokens "${BATCHED}"
    --gpu-memory-utilization "${GMU}"
    --disable-custom-all-reduce
    --enable-chunked-prefill
    --no-enable-prefix-caching
    --compilation-config '{"cudagraph_mode":"FULL_AND_PIECEWISE"}'
    --speculative-config "{\"method\":\"dflash\",\"model\":\"/drafter\",\"num_speculative_tokens\":${NSPEC},\"attention_backend\":\"TRITON_ATTN\"}"
    --reasoning-parser qwen3
    --tool-call-parser qwen3_coder
    --enable-auto-tool-choice
    --trust-remote-code
  )
  if [[ "${VLLM_API_KEY:-EMPTY}" != "EMPTY" && -n "${VLLM_API_KEY:-}" ]]; then
    VLLM_ARGS+=(--api-key "${VLLM_API_KEY}")
  fi
  export VLLM_ARGS
}

# Common docker run fragments for a profile at given rank.
# USAGE: build_docker_env rank  -> sets DOCKER_ENV_EXTRA (array), DOCKER_MOUNTS
build_docker_env(){
  local rank="$1"
  local host_ip ib_hca ib_gid
  if [[ "$rank" == "0" ]]; then
    host_ip="${NODE0_IP}"; ib_hca="${NODE0_IB_HCA:-$NCCL_IB_HCA}"; ib_gid="${NODE0_IB_GID_INDEX:-$NCCL_IB_GID_INDEX}"
  else
    host_ip="${NODE1_IP}"; ib_hca="${NODE1_IB_HCA:-$NCCL_IB_HCA}"; ib_gid="${NODE1_IB_GID_INDEX:-$NCCL_IB_GID_INDEX}"
  fi
  DOCKER_ENV_EXTRA=(
    -e "VLLM_HOST_IP=${host_ip}"
    -e "NCCL_SOCKET_IFNAME=${NCCL_SOCKET_IFNAME}"
    -e "GLOO_SOCKET_IFNAME=${NCCL_SOCKET_IFNAME}"
    -e "NCCL_IB_HCA=${ib_hca}"
    -e "NCCL_IB_GID_INDEX=${ib_gid}"
    -e "PYTORCH_CUDA_ALLOC_CONF=expandable_segments:True"
  )
  DOCKER_MOUNTS=(
    -v "${BODY}:/model:ro"
    -v "${DRAF}:/drafter:ro"
  )
  export DOCKER_ENV_EXTRA DOCKER_MOUNTS
}

# ---- remote execution on Node1 (headless worker) over interconnect ssh ----
n1(){  # runs a script's body on Node1 via ssh; args: [bash -c '...']
  local sshcmd=(
    ssh -o BatchMode=yes -o StrictHostKeyChecking=no \
       -i "${NODE1_SSH_KEY}" "${NODE1_SSH_USER}@${NODE1_IP}"
  )
  "${sshcmd[@]}" "$@"
}

# Common validation: profiles exist on both nodes, ssh reachable
node_up(){
  echo "INFO: NODE0=$(hostname) NODE1=${NODE1_SSH_USER}@${NODE1_IP}"
  [[ -d "$BODY" ]] || die "missing body model: $BODY"
  [[ -d "$DRAF" ]] || die "missing drafter: $DRAF"
  if ! n1 true; then
    echo "ERROR: cannot reach Node1 via ssh (${NODE1_SSH_USER}@${NODE1_IP} key ${NODE1_SSH_KEY})" >&2
    exit 1
  fi
  echo "INFO: ssh to Node1 OK"
}

die(){ echo "ERROR: $*" >&2; exit 1; }
