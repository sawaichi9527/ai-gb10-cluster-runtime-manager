#!/usr/bin/env bash
# =====================================================================
# prepare.sh — generate the derived checkpoint-config artifacts for the
# qwen38flash cluster lane.
#
# Run ONCE on Node0 (where the checkpoint lives) before the first launch,
# and again whenever the checkpoint changes:
#
#     bash patches/qwen38flash/prepare.sh [MODEL_DIR]
#
# Produces (gitignored, staged to both nodes by the profile's SYNC_DIRS):
#     config_patched.json
#     hf_quant_config_patched.json
#
# These add the absolute MTP layer-index alias (mtp.layers.<n>) to
# quantization_config.quantized_layers. Without it vLLM builds the MTP MoE
# unquantized and its FP8 weight_scale_inv tensors fail to load. If the
# checkpoint already declares the absolute indices, the originals are copied
# verbatim so the read-only bind mounts in the profile always resolve.
# =====================================================================
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODEL_DIR="${1:-${HOME}/docker-stacks/models/qwen3.8-flash-next-nvfp4}"

[[ -d "${MODEL_DIR}" ]] || { echo "ERROR: model dir not found: ${MODEL_DIR}" >&2; exit 1; }
[[ -f "${MODEL_DIR}/config.json" ]] || { echo "ERROR: no config.json in ${MODEL_DIR}" >&2; exit 1; }

echo "== qwen38flash prepare =="
echo "model: ${MODEL_DIR}"

# 1. MTP layer-index alias (writes config_patched.json + hf_quant_config_patched.json
#    into SCRIPT_DIR when the checkpoint needs it).
PATCHED="$(python3 "${SCRIPT_DIR}/patch_checkpoint_config.py" "${MODEL_DIR}" "${SCRIPT_DIR}")"
if [[ -n "${PATCHED}" ]]; then
  echo "patched: ${PATCHED}"
else
  echo "checkpoint already declares absolute MTP layer indices — copying verbatim"
fi

# 2. Always leave both files present so the bind mounts resolve.
if [[ ! -f "${SCRIPT_DIR}/config_patched.json" ]]; then
  cp "${MODEL_DIR}/config.json" "${SCRIPT_DIR}/config_patched.json"
fi
if [[ ! -f "${SCRIPT_DIR}/hf_quant_config_patched.json" ]]; then
  if [[ -f "${MODEL_DIR}/hf_quant_config.json" ]]; then
    cp "${MODEL_DIR}/hf_quant_config.json" "${SCRIPT_DIR}/hf_quant_config_patched.json"
  fi
fi

# 3. Report the PLE dtype that the profile injects via --hf-overrides.
PLE_DTYPE="$(python3 "${SCRIPT_DIR}/detect_ple_dtype.py" "${MODEL_DIR}")"
echo "PLE dtype: ${PLE_DTYPE:-<none>}"
if [[ "${PLE_DTYPE}" != "float8_e4m3fn" ]]; then
  echo "WARN: profile pins --hf-overrides ple_embedding_dtype=float8_e4m3fn;" >&2
  echo "      checkpoint reports '${PLE_DTYPE:-<none>}'. Re-check cluster-profiles.d/qwen38flash.conf." >&2
fi

echo "== artifacts =="
ls -la "${SCRIPT_DIR}/config_patched.json" "${SCRIPT_DIR}/hf_quant_config_patched.json" 2>/dev/null || true
