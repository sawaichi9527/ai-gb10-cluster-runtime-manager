#!/usr/bin/env python3
"""Sanity test for the patched _get_ple_embedding_quant_method.

Exercises the runtime shapes for the qwen38flash-next checkpoint:
- ModelOptMixedPrecisionConfig (quant_algo=MIXED_PRECISION) with
  quantized_layers = {PLE: FP8, experts: NVFP4} -- the actual runtime shape.
- ModelOptNvFp4Config -- the other ModelOpt shape the patch handles.
- modelopt Fp8Config baseline (must stay unchanged).

Expected: FP8 method for the PLE prefix under MixedPrecision + NvFp4Config;
None everywhere else; the returned class equals the Fp8Config-branch class.
"""

import json
import sys

from vllm.model_executor.layers.quantization.fp8 import Fp8Config
from vllm.model_executor.layers.quantization.modelopt import (
    ModelOptNvFp4Config,
    ModelOptMixedPrecisionConfig,
)
from vllm.models.qwen3_8_flash_next.nvidia.ple_layer import (
    _get_ple_embedding_quant_method,
)

PLE_PREFIX = (
    "model.language_model.layers.1.ple.ple_embedding.ngram_embedding"
)
EXPERT_PREFIX = "model.language_model.layers.1.mlp.experts"
UNKNOWN_PREFIX = "model.language_model.layers.9.input_layernorm"

QUANTIZED_LAYERS = {
    "model.language_model.layers.0.mlp.experts": {"quant_algo": "NVFP4"},
    "model.language_model.layers.1.mlp.experts": {"quant_algo": "NVFP4"},
    PLE_PREFIX: {"quant_algo": "FP8"},
    "model.language_model.layers.10.mlp.experts": {"quant_algo": "NVFP4"},
}


def make_mixed() -> ModelOptMixedPrecisionConfig:
    cfg = ModelOptMixedPrecisionConfig._from_config(
        quant_method="modelopt_mixed",
        kv_cache_quant_method=None,
        exclude_modules=[],
        original_config={"quantization": {"quantized_layers": QUANTIZED_LAYERS}},
        group_size=16,
    )
    assert cfg._resolve_quant_algo(PLE_PREFIX) == "FP8", (
        f"PLE should resolve FP8, got {cfg._resolve_quant_algo(PLE_PREFIX)}"
    )
    assert cfg._resolve_quant_algo(EXPERT_PREFIX) == "NVFP4", (
        f"experts should resolve NVFP4, got {cfg._resolve_quant_algo(EXPERT_PREFIX)}"
    )
    assert cfg._resolve_quant_algo(UNKNOWN_PREFIX) is None, (
        f"unknown should resolve None, got {cfg._resolve_quant_algo(UNKNOWN_PREFIX)}"
    )
    return cfg


def make_nvfp4() -> ModelOptNvFp4Config:
    return ModelOptNvFp4Config(
        quant_method="NVFP4",
        is_checkpoint_nvfp4_serialized=True,
        exclude_modules=[],
        group_size=16,
    )


def make_fp8(serialized: bool = True) -> Fp8Config:
    return Fp8Config(
        is_checkpoint_fp8_serialized=serialized,
        ignored_layers=[],
        activation_scheme="static",
    )


def expect_method(quant_config, prefix: str):
    return _get_ple_embedding_quant_method(quant_config, prefix)


def run():
    ref = expect_method(make_fp8(), PLE_PREFIX)
    if ref is None:
        print("FAIL: Fp8Config baseline returned None")
        return 1

    cases = [
        ("A1 Mixed PLE -> FP8 method",
         expect_method(make_mixed(), PLE_PREFIX), "not None"),
        ("A2 Mixed PLE type == Fp8Config branch",
         type(expect_method(make_mixed(), PLE_PREFIX)), type(ref)),
        ("A3 Mixed experts -> None",
         expect_method(make_mixed(), EXPERT_PREFIX), None),
        ("A4 Mixed unknown -> None",
         expect_method(make_mixed(), UNKNOWN_PREFIX), None),
        ("B1 NvFp4 PLE -> FP8 method",
         expect_method(make_nvfp4(), PLE_PREFIX), "not None"),
        ("B2 NvFp4 type == Fp8Config branch",
         type(expect_method(make_nvfp4(), PLE_PREFIX)), type(ref)),
        ("C1 Fp8Config(excluded-less) PLE -> FP8 method",
         expect_method(make_fp8(), PLE_PREFIX), "not None"),
        ("D1 Fp8Config not serialized -> None",
         expect_method(make_fp8(serialized=False), PLE_PREFIX), None),
        ("E1 None config -> None", expect_method(None, PLE_PREFIX), None),
    ]

    failed = False
    for name, got, want in cases:
        if want == "not None":
            ok = got is not None
        else:
            ok = got == want
        print(f"{'PASS' if ok else 'FAIL'}: {name} -> {got}")
        failed = failed or not ok

    if failed:
        print("SANITY CHECKS FAILED")
        return 1
    print("ALL SANITY CHECKS PASSED")
    return 0


if __name__ == "__main__":
    sys.exit(run())