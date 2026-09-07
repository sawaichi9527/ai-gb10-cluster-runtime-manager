#!/usr/bin/env bash
# =====================================================================
# tp2-common.sh — shared env load + data-driven cluster-profile loader
# for ai-gb10-cluster. Sourced by every scripts/tp2-* entrypoint.
# NOT meant to be run alone.
#
# Architecture:
#   cluster-profiles.d/<id>.conf  = authoritative per-profile data
#     (image, model rels, context/concurrency/GMU, model-specific vLLM
#      args). TP2 orchestration layer stays model-agnostic; it only
#      consumes the resolved profile.
# =====================================================================
set -Eeuo pipefail

# ---- resolve this script dir (repo root/scripts) independent of CWD ----
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
PROFILE_DIR="${REPO_DIR}/cluster-profiles.d"

# ---- load tp2.env if present (gitignored) else defaults from example ----
ENV_FILE="${REPO_DIR}/tp2.env"
if [[ -f "${ENV_FILE}" ]]; then
  # shellcheck disable=SC1090
  source "${ENV_FILE}"
else
  # shellcheck disable=SC1090
  source "${REPO_DIR}/tp2.env.example"
fi

: "${MASTER_ADDR:?tp2.env missing MASTER_ADDR}"
: "${MASTER_PORT:?tp2.env missing MASTER_PORT}"
: "${API_PORT:=1234}"
# Cluster-global default image (fallback; a cluster profile may override).
: "${IMG:=ghcr.io/aeon-7/aeon-vllm-ultimate:2026-08-24-v0.27.1-omni}"

# ---- SUDO_PASS: prefer env, else prompt on first docker use (lazy) ----
# Lazy so read-only/registry commands (gb10 list|inspect|help, profiles)
# never hang on a password prompt. Only sdk()/sudo_pass() trigger it.
_sudo_pass(){
  if [[ -n "${SUDO_PASS:-}" || "${_SUDO_DONE:-}" == "1" ]]; then
    echo "$SUDO_PASS"; return
  fi
  if [[ -t 0 ]]; then
    read -rsp "sudo password for docker on both nodes: " SUDO_PASS
    echo >&2 ""
  else
    echo "ERROR: SUDO_PASS is required (export it or add to tp2.env)" >&2
    exit 1
  fi
  _SUDO_DONE=1
  echo "$SUDO_PASS"
}
sudo_pass(){ _sudo_pass; }

# ---- docker helper (sudo on local Node0) ----
sdk(){ echo "$(sudo_pass)" | sudo -S "$@" 2>/dev/null; }

# ---- auth for the vLLM API (_API_KEY != EMPTY means auth required) ----
# api_curl <url> [curl args...] — run curl with the optional Bearer header.
api_curl(){
  local url="$1"; shift
  if [[ -n "${VLLM_API_KEY:-}" && "${VLLM_API_KEY}" != "EMPTY" ]]; then
    curl -fsS -H "Authorization: Bearer ${VLLM_API_KEY}" "$@" "${url}"
  else
    curl -fsS "$@" "${url}"
  fi
}

MODELS_BASE="${NODE0_MODELS_BASE:-$HOME/docker-stacks/aeon-vllm/models}"

# =====================================================================
# Cluster profile registry (data-driven) — replaces the old hard-coded
# set_profile() case table.
# =====================================================================

# list_cluster_profiles -> sorted list of PROFILE_IDs from cluster-profiles.d
list_cluster_profiles(){
  local f id
  ( shopt -s nullglob
    for f in "${PROFILE_DIR}"/*.conf; do
      id="$(basename "$f" .conf)"
      [[ -n "$id" ]] && echo "$id"
    done
  ) | sort -u
}

# valid_cluster_profile <id>
valid_cluster_profile(){
  local id
  for id in $(list_cluster_profiles); do
    [[ "$id" == "$1" ]] && return 0
  done
  return 1
}

# load_profile <id> — source the conf, resolve BODY/DRAF and per-profile
# image into PROFILE_* state. Fails safely on unknown/placeholder.
# Resolved outputs:
#   PROFILE   PROFILE_ID
#   BODY DRAF (absolute model dirs)
#   IMG       (resolved per-profile image)
#   MAXLEN NUMSEQ BATCHED GMU NSPEC
#   KV_DTYPE ATTN_BACKEND ... (model-specific settings)
load_profile(){
  local id="$1"
  local conf="${PROFILE_DIR}/${id}.conf"
  if [[ ! -f "$conf" ]]; then
    echo "ERROR: unknown cluster profile '$id' (known: $(list_cluster_profiles | tr '\n' ' '))" >&2
    exit 2
  fi
  # reset state so a partial conf can't leak a previous profile
  unset PROFILE_ID DISPLAY_NAME PLACEHOLDER IMAGE BODY_REL DRAF_REL \
        MAXLEN NUMSEQ BATCHED GMU NSPEC \
        KV_DTYPE ATTN_BACKEND LINEAR_BACKEND MOE_BACKEND \
        SPEC_METHOD SPEC_ATTN_BACKEND NSPEC GRAPH_MODE \
        REASONING_PARSER TOOL_CALL_PARSER ENABLE_AUTO_TOOL_CHOICE \
        ENABLE_CHUNKED_PREFILL ENABLE_PREFIX_CACHING \
        QUANTIZATION SPEC_CONFIG CUDAGRAPH_CAPTURE \
        EXTRA_ARGS EXTRA_ENV EXTRA_MOUNTS \
        DISABLE_CUSTOM_ALL_REDUCE SHM_SIZE 2>/dev/null || true
  # shellcheck disable=SC1090
  source "$conf"
  PROFILE="${PROFILE_ID:?cluster profile missing PROFILE_ID}"
  if [[ "${PLACEHOLDER:-false}" == "true" ]]; then
    PROFILE_PLACEHOLDER="true"
  else
    PROFILE_PLACEHOLDER="false"
  fi
  # Per-profile image override; fall back to cluster-global tp2.env IMG.
  if [[ -n "${IMAGE:-}" ]]; then
    IMG="$IMAGE"
  fi
  # Resolve model dirs from MODELS_BASE + relative rels.
  if [[ "${PROFILE_PLACEHOLDER}" == "true" ]]; then
    BODY="${BODY_REL:-}"
    DRAF="${DRAF_REL:-}"
    return 0
  fi
  : "${BODY_REL:?cluster profile $PROFILE missing BODY_REL}"
  : "${IMG:?cluster profile $PROFILE has no image; set IMAGE or tp2.env IMG}"
  BODY="${MODELS_BASE}/${BODY_REL}"
  # Drafter is optional (empty DRAF_REL => no /drafter mount, no spec decode).
  DRAF=""
  if [[ -n "${DRAF_REL:-}" ]]; then
    DRAF="${MODELS_BASE}/${DRAF_REL}"
  fi
  export PROFILE PROFILE_PLACEHOLDER
}

# =====================================================================
# build_vllm_args <rank> -> sets VLLM_ARGS (bash array)
#   rank=0 : API server (port + reasoning/tool parsers + api-key)
#   rank=1 : headless worker (no parser / no api-key)
# Both ranks consume the SAME resolved profile data; only rank-specific
# fields differ. Model-specific settings are profile-owned, never
# re-hard-coded here.
# =====================================================================
build_vllm_args(){
  local rank="$1"

  VLLM_ARGS=(--served-model-name aeon)
  # rank0 serves the API (binds 0.0.0.0:<port>); rank1 is a headless worker.
  # --host/--port are rank0-only, matching the verified pre-refactor argv.
  [[ "$rank" == "0" ]] && VLLM_ARGS+=(--host 0.0.0.0 --port "${API_PORT}")
  [[ "$rank" == "1" ]] && VLLM_ARGS+=(--headless)
  VLLM_ARGS+=(
    --tensor-parallel-size 2
    --nnodes 2
    --node-rank "${rank}"
    --master-addr "${MASTER_ADDR}"
    --master-port "${MASTER_PORT}"
    --kv-cache-dtype "${KV_DTYPE:-fp8_e4m3}"
    --max-model-len "${MAXLEN}"
    --max-num-seqs "${NUMSEQ}"
    --max-num-batched-tokens "${BATCHED}"
    --gpu-memory-utilization "${GMU}"
  )
  # Quantization flag is profile-overridable (data stays in the conf).
  #   unset          -> historical default: --quantization compressed-tensors
  #   QUANTIZATION=X -> --quantization X
  #   QUANTIZATION=none -> omit the flag entirely (checkpoints whose HF
  #   config already carries their own quant method).
  if [[ -n "${QUANTIZATION:-}" && "${QUANTIZATION}" != "none" ]]; then
    VLLM_ARGS+=(--quantization "${QUANTIZATION}")
  elif [[ -z "${QUANTIZATION:-}" ]]; then
    VLLM_ARGS+=(--quantization compressed-tensors)
  fi
  # Custom all-reduce disable is the historical behavior; a profile may opt
  # out (DISABLE_CUSTOM_ALL_REDUCE=false) to follow a recipe contract.
  [[ "${DISABLE_CUSTOM_ALL_REDUCE:-true}" == "true" ]] \
    && VLLM_ARGS+=(--disable-custom-all-reduce)
  # Profile-owned backend overrides (empty/unset => vLLM auto default).
  [[ -n "${ATTN_BACKEND:-}" ]] && VLLM_ARGS+=(--attention-backend "${ATTN_BACKEND}")
  [[ -n "${LINEAR_BACKEND:-}" ]] && VLLM_ARGS+=(--linear-backend "${LINEAR_BACKEND}")
  [[ -n "${MOE_BACKEND:-}" ]] && VLLM_ARGS+=(--moe-backend "${MOE_BACKEND}")
  [[ "${ENABLE_CHUNKED_PREFILL:-true}" == "true" ]] && VLLM_ARGS+=(--enable-chunked-prefill)
  [[ "${ENABLE_PREFIX_CACHING:-false}" == "true" ]] && VLLM_ARGS+=(--enable-prefix-caching) \
    || VLLM_ARGS+=(--no-enable-prefix-caching)
  VLLM_ARGS+=(--compilation-config "{\"cudagraph_mode\":\"${GRAPH_MODE:-FULL_AND_PIECEWISE}\"}")
  [[ -n "${CUDAGRAPH_CAPTURE:-}" ]] \
    && VLLM_ARGS+=(--max-cudagraph-capture-size "${CUDAGRAPH_CAPTURE}")
  # Speculative decode: a profile-owned raw SPEC_CONFIG JSON wins over the
  # template (e.g. same-model DSpark drafts that need no /drafter mount);
  # the template path stays the default for /drafter-style profiles.
  if [[ -n "${SPEC_CONFIG:-}" ]]; then
    VLLM_ARGS+=(--speculative-config "${SPEC_CONFIG}")
  elif [[ -n "${SPEC_METHOD:-}" && "${SPEC_METHOD}" != "none" && -n "${DRAF:-}" ]]; then
    VLLM_ARGS+=(--speculative-config "{\"method\":\"${SPEC_METHOD}\",\"model\":\"/drafter\",\"num_speculative_tokens\":${NSPEC:-1},\"attention_backend\":\"${SPEC_ATTN_BACKEND:-TRITON_ATTN}\"}")
  fi
  # API-serving rank only: parsers + optional tool choice.
  if [[ "$rank" == "0" ]]; then
    [[ -n "${REASONING_PARSER:-}" ]] && VLLM_ARGS+=(--reasoning-parser "${REASONING_PARSER}")
    [[ -n "${TOOL_CALL_PARSER:-}" ]] && VLLM_ARGS+=(--tool-call-parser "${TOOL_CALL_PARSER}")
    [[ "${ENABLE_AUTO_TOOL_CHOICE:-false}" == "true" ]] && VLLM_ARGS+=(--enable-auto-tool-choice)
  fi
  VLLM_ARGS+=(--trust-remote-code)
  # Verbatim profile-owned extras (bash array EXTRA_ARGS in the conf).
  [[ -n "${EXTRA_ARGS+x}" ]] && VLLM_ARGS+=("${EXTRA_ARGS[@]}")
  if [[ "$rank" == "0" && "${VLLM_API_KEY:-EMPTY}" != "EMPTY" && -n "${VLLM_API_KEY:-}" ]]; then
    VLLM_ARGS+=(--api-key "${VLLM_API_KEY}")
  fi
  export VLLM_ARGS
}

# =====================================================================
# build_docker_env <rank> -> sets DOCKER_ENV_EXTRA (array), DOCKER_MOUNTS
# =====================================================================
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
  # Profile-owned env/mount extras (arrays EXTRA_ENV / EXTRA_MOUNTS in the
  # conf). EXTRA_ENV entries are KEY=VAL and get an explicit "-e" flag each
  # (built-ins above already carry "-e"); EXTRA_MOUNTS entries are full
  # "-v src:dst[:opts]" tokens. Unset => no extras (unchanged behavior).
  if [[ -n "${EXTRA_ENV+x}" ]]; then
    local _kv
    for _kv in "${EXTRA_ENV[@]}"; do DOCKER_ENV_EXTRA+=(-e "$_kv"); done
  fi
  DOCKER_MOUNTS=(-v "${BODY}:/model:ro")
  [[ -n "${DRAF:-}" ]] && DOCKER_MOUNTS+=(-v "${DRAF}:/drafter:ro")
  [[ -n "${EXTRA_MOUNTS+x}" ]] && DOCKER_MOUNTS+=("${EXTRA_MOUNTS[@]}")
  export DOCKER_ENV_EXTRA DOCKER_MOUNTS
}

# =====================================================================
# inspect_profile <id> — dry-run resolver: prints SANITIZED resolved
# profile values. NEVER prints API keys or sudo passwords.
# =====================================================================
inspect_profile(){
  local id="$1"
  load_profile "$id"
  echo "profile:  ${PROFILE}$([[ "${PROFILE_PLACEHOLDER}" == "true" ]] && echo " (placeholder)")"
  echo "display:  ${DISPLAY_NAME:-<unset>}"
  echo "image:    ${IMG:-<unresolved>}"
  if [[ "${PROFILE_PLACEHOLDER}" == "true" ]]; then
    echo "status:   not deployed (placeholder)"
    echo "model:    <none>"
    echo "drafter:  <none>"
    echo "note:     fails safe; no image/model resolution, no container start"
    return 0
  fi
  echo "body:     ${BODY}"
  echo "drafter:  ${DRAF:-<none>}"
  echo "args:     maxlen=${MAXLEN:-?} numseq=${NUMSEQ:-?} batched=${BATCHED:-?} gmu=${GMU:-?}"
  echo "kv:       ${KV_DTYPE:-fp8_e4m3}  attn: ${ATTN_BACKEND:-auto}  linear: ${LINEAR_BACKEND:-auto}  moe: ${MOE_BACKEND:-auto}"
  echo "quant:    ${QUANTIZATION:-<default: compressed-tensors>}$( [[ "${QUANTIZATION:-}" == "none" ]] && echo " (flag omitted)" || true )"
  echo "capture:  ${CUDAGRAPH_CAPTURE:-<engine default>}"
  echo "extras:   args=$([[ -n "${EXTRA_ARGS+x}" ]] && echo "${#EXTRA_ARGS[@]}" || echo 0) env=$([[ -n "${EXTRA_ENV+x}" ]] && echo "${#EXTRA_ENV[@]}" || echo 0) mounts=$([[ -n "${EXTRA_MOUNTS+x}" ]] && echo "${#EXTRA_MOUNTS[@]}" || echo 0)"
  echo "spec:     ${SPEC_METHOD:-none}$([[ -n "${DRAF:-}" && -n "${SPEC_METHOD:-}" && "${SPEC_METHOD}" != "none" ]] && echo " n=${NSPEC:-?} (model=/drafter)")$([[ -n "${SPEC_CONFIG:-}" ]] && echo " (SPEC_CONFIG override)")"
  echo "graph:    ${GRAPH_MODE:-FULL_AND_PIECEWISE}"
  echo "parsers:  reasoning=${REASONING_PARSER:-none} tool=${TOOL_CALL_PARSER:-none} autotool=${ENABLE_AUTO_TOOL_CHOICE:-false}"
  echo "prefill:  chunked=${ENABLE_CHUNKED_PREFILL:-true} prefix_cache=${ENABLE_PREFIX_CACHING:-false}"
  echo "auth:     $([[ -n "${VLLM_API_KEY:-}" && "${VLLM_API_KEY}" != "EMPTY" ]] && echo "Bearer set (rank0)" || echo "disabled")"
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
  if [[ -n "${DRAF:-}" ]]; then
    [[ -d "$DRAF" ]] || die "missing drafter: $DRAF"
  fi
  if ! n1 true; then
    echo "ERROR: cannot reach Node1 via ssh (${NODE1_SSH_USER}@${NODE1_IP} key ${NODE1_SSH_KEY})" >&2
    exit 1
  fi
  echo "INFO: ssh to Node1 OK"
}

die(){ echo "ERROR: $*" >&2; exit 1; }
