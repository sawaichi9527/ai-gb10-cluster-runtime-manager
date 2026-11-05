#!/usr/bin/env python3
"""DSpark draft quant dispatch fix: build the NVFP4 checkpoint's in-checkpoint
DSpark draft experts with the MXFP4 method instead of the target's NVFP4 one.

nvidia/DeepSeek-V4-Flash-0731-NVFP4 quantizes only the target trunk's routed
experts; the DSpark draft (`mtp.*`) ships natively MXFP4 (int8-packed weights,
ue8m0 group-32 scales) and the checkpoint's own quantization_config `ignore`
list exempts it.  vLLM's DeepseekV4FP8Config.get_quant_method resolves
`moe_quant_algo` lazily from get_current_vllm_config().model_config.hf_config
-- the SHARED NVFP4 dict -- so even the freshly built draft quant instance
(load_dspark_model's get_draft_quant_config) resolves "NVFP4" and constructs
the draft's routed experts as ModelOptNvFp4FusedMoE: ue8m0 group-32 scales are
loaded into e4m3 group-16 buffers (same shapes, no error), the draft MoE
computes garbage, and spec-decode acceptance collapses (~1.1 accepted
tokens/step, positions 1-4 near zero, ~16 tok/s single stream; diagnostic
tell: the draft never emits the "Mxfp4 MoE backend" line an official
fp8/MXFP4 target prints).  Upstream vllm-project/vllm#49133 diagnosed the
inheritance and was closed unmerged; this image adopted only half of it (the
fresh quant instance), and its utils.py hunk would not help a
same-checkpoint draft that shares the NVFP4 dict anyway.

The fix pre-memoizes `_resolved_moe_quant_algo = ""` on the draft's own quant
instance when the shared dict declares `mtp.*` ignored, so moe_quant_algo
resolves "" and get_quant_method returns Mxfp4MoEMethod - the exact path the
official fp8/MXFP4 checkpoint takes (community acceptance 27-60%).  The
target's own quant instance is a different object and is untouched.

Single target; source-exact region (must occur exactly once); whole-file
identity-pinned to this image's stock and patched bytes (the image itself is
digest-gated by IMG_SHA256/IMG_SHA256_NODE1); same-directory atomic replace;
already-patched targets are verified, never rewritten; anything else fails
closed (exit 1) and aborts the container start.
"""
from __future__ import annotations

import argparse
import hashlib
import importlib.metadata
import os
import stat
import sys
import tempfile
from pathlib import Path

PRODUCTION_TARGET = Path(
    "/usr/local/lib/python3.12/dist-packages/vllm/"
    "v1/worker/gpu/spec_decode/dspark/utils.py"
)
EXPECTED_VLLM_VERSION = "0.1.dev21554+geda1715e9.d20261006"
LABEL = "spec_decode/dspark/utils.py"
MARK = "# [dspark-draft-mxfp4]"

REGION_OLD = "\n".join(
    [
        "    # VllmConfig post-init restores the target's quant config because the target",
        "    # config is retained for DSpark's target-layer metadata, so we must override it.",
        "    draft_vllm_config.quant_config = get_draft_quant_config(vllm_config)",
    ]
).encode("ascii") + b"\n"

REGION_NEW = "\n".join(
    [
        "    # VllmConfig post-init restores the target's quant config because the target",
        "    # config is retained for DSpark's target-layer metadata, so we must override it.",
        "    draft_vllm_config.quant_config = get_draft_quant_config(vllm_config)",
        "    # [dspark-draft-mxfp4]",
        "    # The fresh draft quant instance still resolves `moe_quant_algo` lazily",
        "    # from the SHARED hf quantization_config, which describes the NVFP4",
        "    # target trunk. The in-checkpoint DSpark draft experts (`mtp.*`) ship",
        "    # natively MXFP4 and the checkpoint's own `ignore` list exempts them,",
        "    # so a lazily-resolved \"NVFP4\" would build them as",
        "    # ModelOptNvFp4FusedMoE and silently load ue8m0 group-32 scales into",
        "    # e4m3 group-16 buffers: garbage draft logits and a spec-decode",
        "    # acceptance collapse (~1.1 tokens/step; upstream",
        "    # vllm-project/vllm#49133, closed unmerged). Pre-memoize \"\" so the",
        "    # dispatch takes Mxfp4MoEMethod, the same path the official",
        "    # fp8/MXFP4 checkpoint takes; the target's own quant instance is a",
        "    # different object and stays untouched.",
        "    _draft_qc = draft_vllm_config.quant_config",
        "    _draft_qcfg = getattr(",
        "        draft_model_config.hf_config, \"quantization_config\", None",
        "    )",
        "    if (",
        "        _draft_qc is not None",
        "        and hasattr(_draft_qc, \"_resolved_moe_quant_algo\")",
        "        and isinstance(_draft_qcfg, dict)",
        "        and \"mtp.*\" in (_draft_qcfg.get(\"ignore\") or [])",
        "    ):",
        "        _draft_qc._resolved_moe_quant_algo = \"\"",
    ]
).encode("ascii") + b"\n"

STOCK_SHA256 = "ea48801fbc80afc518ea3a5a4d3d00e401525d9cbdd8e914ad88adfa9bde5647"
STOCK_SIZE = 5_257
PATCHED_SHA256 = "7099e1624e1eee81bc781d1a069803b67bdc8f84fa3b3ffc8734c0a49a78eed5"
PATCHED_SIZE = 6_478


class HotfixError(RuntimeError):
    pass


def _sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def _vllm_version(provider=importlib.metadata.version) -> str:
    try:
        version = provider("vllm")
    except importlib.metadata.PackageNotFoundError as error:
        raise HotfixError("vllm is not installed") from error
    if version != EXPECTED_VLLM_VERSION:
        raise HotfixError(
            f"unsupported vllm version {version!r}; "
            f"expected {EXPECTED_VLLM_VERSION!r}"
        )
    return version


def transform(stock: bytes) -> bytes:
    """Stock bytes -> patched bytes; refuses anything but exactly one site."""
    if MARK.encode("ascii") in stock:
        raise HotfixError(f"{LABEL}: target already carries the mark")
    count = stock.count(REGION_OLD)
    if count != 1:
        raise HotfixError(
            f"{LABEL}: source region count {count} != 1; expected exact stock"
        )
    patched = stock.replace(REGION_OLD, REGION_NEW, 1)
    compile(patched, LABEL, "exec")
    if patched.count(REGION_NEW) != 1:
        raise HotfixError(f"{LABEL}: transformed bytes lost the new region")
    if _sha256(stock) == STOCK_SHA256:
        pdigest = _sha256(patched)
        if pdigest != PATCHED_SHA256 or len(patched) != PATCHED_SIZE:
            raise HotfixError(
                f"{LABEL}: transform of pinned stock -> sha256={pdigest} "
                f"size={len(patched)}; expected the pinned patched identity"
            )
    return patched


def inspect(
    target: Path, *, provider=importlib.metadata.version
) -> tuple[str, bytes]:
    _vllm_version(provider)
    try:
        st = target.lstat()
    except FileNotFoundError:
        raise HotfixError(f"{LABEL}: target is missing")
    if stat.S_ISLNK(st.st_mode) or not stat.S_ISREG(st.st_mode):
        raise HotfixError(f"{LABEL}: target is not a regular file")
    data = target.read_bytes()
    digest = _sha256(data)
    if digest == PATCHED_SHA256 and len(data) == PATCHED_SIZE:
        return "patched", data
    if digest == STOCK_SHA256 and len(data) == STOCK_SIZE:
        return "stock", data
    raise HotfixError(
        f"{LABEL}: unsupported target bytes sha256={digest} "
        f"size={len(data)}; expected the pinned stock or patched identity"
    )


def _publish(target: Path, patched: bytes) -> None:
    fd, tmp_name = tempfile.mkstemp(
        prefix=".dspark-draft-mxfp4-", dir=str(target.parent)
    )
    tmp = Path(tmp_name)
    try:
        with os.fdopen(fd, "wb") as handle:
            handle.write(patched)
            handle.flush()
            os.fsync(handle.fileno())
        os.chmod(tmp, stat.S_IMODE(target.stat().st_mode))
        os.replace(tmp, target)
    except BaseException:
        tmp.unlink(missing_ok=True)
        raise


def apply(target: Path, *, provider=importlib.metadata.version) -> str:
    """Preflight the target, then write only if still stock."""
    state, data = inspect(target, provider=provider)
    if state == "patched":
        return "already-patched"
    _publish(target, transform(data))
    verify_state, _ = inspect(target, provider=provider)
    if verify_state != "patched":
        raise HotfixError(f"{LABEL}: post-apply verification failed")
    return "applied"


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--check", action="store_true", help="verify compatibility only"
    )
    parser.add_argument(
        "--status", action="store_true", help="print the target state"
    )
    parser.add_argument(
        "--target", type=Path, default=PRODUCTION_TARGET
    )
    args = parser.parse_args(argv)
    try:
        if args.check or args.status:
            state, _ = inspect(args.target)
            report = f"{state} ({args.target})"
        else:
            outcome = apply(args.target)
            report = f"{outcome} ({args.target})"
        print(f"dspark-draft-mxfp4: {report}")
        return 0
    except HotfixError as error:
        print(f"dspark-draft-mxfp4: FAIL-CLOSED: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
