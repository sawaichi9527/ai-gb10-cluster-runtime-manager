#!/usr/bin/env python3
"""Build-time patch for vllm#54765 (ModelOpt PLE embedding selector).

Enables the FP8 PLE embedding path for checkpoints served under a ModelOpt
quant config where the PLE ngram_embedding is FP8-quantized. This happens in
two shapes at runtime:

- ``ModelOptNvFp4Config`` (pure NVFP4 checkpoint, quant_algo=NVFP4): PLE is
  ``{"quant_algo": "FP8"}`` inside the same quant config. The patch mirrors
  the FP8 branch behavior for non-excluded, serialized configs.
- ``ModelOptMixedPrecisionConfig`` (quant_algo=MIXED_PRECISION, the case for
  this qwen38flash-next checkpoint): per-layer algos live in
  ``quantized_layers`` and the runtime wraps NVFP4/FP8/MXFP8 sub-configs.
  ``_resolve_quant_algo(prefix)`` returns the upper-cased per-layer algo, so
  the FP8 method is returned only for layers declared ``FP8``.

Without this, ``_get_ple_embedding_quant_method`` returns None for any
non-Fp8Config quant config, so the PLE is built as an unquantized
VocabParallelEmbedding (.weight only) and AutoWeightsLoader fails with
`There is no module or parameter named 'ngram_embedding.weight_scale'`.

The patch is AST-driven so it does not hard-code the FP8 embedding method
class name: it resolves the class referenced by the function's final
`return <Cls>()` and mirrors that exact return for the ModelOpt branches.
"""

import ast
import pathlib
import sys

PLE = pathlib.Path(
    "/usr/local/lib/python3.12/dist-packages/"
    "vllm/models/qwen3_8_flash_next/nvidia/ple_layer.py"
)
src = PLE.read_text(encoding="utf-8")
tree = ast.parse(src)


def _resolve_fp8_method_cls() -> str:
    for node in ast.walk(tree):
        if (
            isinstance(node, ast.FunctionDef)
            and node.name == "_get_ple_embedding_quant_method"
        ):
            for child in ast.walk(node):
                if isinstance(child, ast.Return) and isinstance(
                    child.value, ast.Call
                ):
                    func = child.value.func
                    if isinstance(func, ast.Name) and func.id != "None":
                        return func.id
    raise SystemExit("failed to resolve FP8 PLE embedding method class name")


method_cls = _resolve_fp8_method_cls()

anchor = "from vllm.model_executor.layers.quantization.fp8 import Fp8Config"
modelopt_import = (
    "from vllm.model_executor.layers.quantization.modelopt import "
    "(ModelOptNvFp4Config, ModelOptMixedPrecisionConfig)"
)
if "ModelOptMixedPrecisionConfig" not in src:
    if src.count(anchor) != 1:
        raise SystemExit(f"anchor not unique: {anchor!r}")
    src = src.replace(anchor, anchor + "\n" + modelopt_import, 1)

guard = "    if not isinstance(quant_config, Fp8Config):"
branch = (
    f"    if isinstance(quant_config, ModelOptMixedPrecisionConfig):\n"
    f"        if quant_config._resolve_quant_algo(prefix) != \"FP8\":\n"
    f"            return None\n"
    f"        if quant_config.is_layer_excluded(prefix):\n"
    f"            return None\n"
    f"        return {method_cls}()\n"
    f"\n"
    f"    if isinstance(quant_config, ModelOptNvFp4Config):\n"
    f"        if not quant_config.is_checkpoint_nvfp4_serialized:\n"
    f"            return None\n"
    f"        if quant_config.is_layer_excluded(prefix):\n"
    f"            return None\n"
    f"        return {method_cls}()\n"
    f"\n"
    f"{guard}"
)
if "isinstance(quant_config, ModelOptMixedPrecisionConfig)" in src:
    raise SystemExit("already patched")
if src.count(guard) != 1:
    raise SystemExit(f"Fp8Config guard not unique: {guard!r}")
src = src.replace(guard, branch, 1)

PLE.write_text(src, encoding="utf-8")
compile(src, str(PLE), "exec")
print(
    f"patched {PLE}: ModelOptMixedPrecisionConfig/ModelOptNvFp4Config -> "
    f"{method_cls}"
)