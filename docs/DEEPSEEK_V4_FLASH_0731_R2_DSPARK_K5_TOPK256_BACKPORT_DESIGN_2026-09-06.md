# DeepSeek V4 Flash 0731 r2 — SM120 DSV4 topk=256 FlashInfer backport (production design, B scope)

- **Status:** DRAFT for review. **Scope/design only — NO image build yet.**
- **Branch lineage:** created from Forgejo `main` @ `571cd65`; does NOT inherit the r2 experiment branch
  (`experiment/deepseek-v4-dspark-k5-r2`) or its A' workaround commit (`88e5b3e`, `/tmp/a1` 512-padding hook in
  `scripts/tp2-up`). That hook stays out of production.
- **Guard:** the "no image build" guard is lifted **only** after this doc + the hunk diff it specifies are
  reviewed clean (see §10). Then **Phase A (JIT-validation image build)** may proceed. The **Phase B (AOT
  production image)** must not be built until the phase-A candidate passes the full r2 functional and
  performance gates (§9).

## 1. Context and root cause (self-contained)

- r1 baseline is frozen and documented (`docs/DEEPSEEK_V4_FLASH_0731_R1_TP2_BASELINE_2026-09-06.md`):
  TP2 64K context, FP8-KV baseline (`fp8_ds_mla`), PIECEWISE graph, DSpark OFF, no drafter; cold start ~11 min,
  smoke C1 ≈ 18.7 tok/s single-stream aggregate, needles found @ 8K/32K/60K.
- r2 brings DSpark speculative decoding (K=5 draft tokens) on top of r1, same model
  `deepseek-v4-flash-0731-nvfp4` (sliding_window=128, heads=64, kv_heads=1, d_qk=512, d_v=512), same image
  tag `ghcr.io/aeon-7/aeon-vllm-ultimate:2026-09-04-v0.27.1-omni-ds4flash0731-r1`.
- Failure reproduced: boot aborts with `sparse_mla_sm120.cu` TVM-FFI ICHECK "Unsupported sparse-MLA prefill
  configuration ... `num_tokens > 64, got 5`" on the decode (prompt > context) path after autotune. Root cause:
  the DSpark pipeline pads the decode workspace to 64-entry index tiles, so the **decode topk width becomes 256**
  (128 sliding-window + 5 draft tokens padded up to the 256-wide buffer; active entries = 133). The AEON
  0.6.16.post3 SM120 DSV4 launch table only instantiates topk ∈ {128, 512, 1024}; a `(64, 256)` decode request
  is not dispatchable → falls through to the decode/paged/prefill orchestrator, which rejects it via the CHECK
  above.
- Empirical proof (r2-A probe, §7b of the local evidence doc
  `docs/DEEPSEEK_V4_FLASH_0731_R2_DSPARK_K5_FUNCTIONAL_FAIL_2026-09-06.md`): the kernel is **length-tolerant**
  — the same runtime boots and generates correctly when the decode topk is padded to 512. The only missing
  piece is a native topk=256 specialization. The 512-padding was diagnostic only and must NOT be carried into
  production.

## 2. Upstream authoritative reference

- **Commit:** `24d7dfb2639083c5a4d418881099421fc800b7bb` — FlashInfer PR **#4380**
  "feat(sm120): consolidate DSV4 sparse MLA top-k 192/256 support" (consolidated replacement for #4309 + #4372).
- It fixes exactly the decode→prefill abort class we reproduced. Its 192/256 groundwork matches our runtime:
  133 active entries = 128 window + 5 drafts, laid out in 64-entry index tiles → the 256 bucket ("other
  integrations") is our bucket.
- We take the **256 arms only** from #4380. 192, H8/TP8, dual-cache, benchmark-only and the later #4802
  top-k refactor changes stay out (§12).

## 3. Target image facts (verified in-container on both nodes, image above)

- flashinfer ships as **three separate packages** (all `0.6.16.post3`):
  - `flashinfer-python` — python package, contains the JIT machinery AND a bundled C++ source tree under
    `flashinfer/data/` (this is the only source available in-image; no git tree, no `direct_url.json`).
  - `flashinfer_cubin` — prebuilt CUDA cubins for explicit GEMM/GQA ops (unrelated to the sm120 sparse-MLA
    binding, which is compiled from source).
  - `flashinfer_jit_cache` — AOT-precompiled artifacts, including
    `flashinfer_jit_cache/jit_cache/sparse_mla_sm120/sparse_mla_sm120.so` (997 KB).
- Full path note: packages live under `/usr/local/lib/python3.12/site-packages/` in the image.
- The sm120 binding is a **monolithic JIT extension**: `import flashinfer.mla` calls
  `flashinfer/jit/mla.py:gen_sparse_mla_sm120_module().build_and_load()`, compiling FIVE files in one ninja
  unit from `FLASHINFER_CSRC_DIR=.../flashinfer/data/csrc/`:
  `sparse_mla_sm120.cu`, `sparse_mla_sm120_decode_dsv3_2.cu`, `sparse_mla_sm120_decode_dsv4.cu`,
  `sparse_mla_sm120_prefill.cu`, `sparse_mla_sm120_jit_binding.cu`.
- AOT short-circuit: `flashinfer/jit/core.py:try_load()` trusts a prebuilt artifact whose spec fingerprint
  matches; with the baked `.../sparse_mla_sm120.so` present it **never rebuilds from source**. Therefore a
  source patch MUST either remove that AOT artifact or re-AOT-compile it, or the patched sources are dead bytes.
- Toolchain is present in-image for JIT: `nvcc` (CUDA 13.0.88), `g++`, `cmake`, `ninja 1.13`. Compilation
  happens on the device at import time (first boot) using the live device architecture.

## 4. Backport map (files / hunks / anchors)

### 4.1 Required

| # | File in image (`site-packages/flashinfer/…`) | Anchor | 256-only edit (verbatim line to add) |
|---|---|---|---|
| 1 | `data/csrc/sparse_mla_sm120_decode_dsv4.cu` — dsv4 decode dispatch table at L148-171 (`#define DSV4_DISPATCH(NH,TOPK)` + per-head entries) | after each `  DSV4_DISPATCH(N, 1024)` line, N∈{8,16,32,64,128} | `  DSV4_DISPATCH(N, 256)` — 5 lines total, one per head |
| 2 | `data/csrc/sparse_mla_sm120_prefill.cu` — `dispatch_dsv4_single` topk if-chain at L294-301 (`else if (topk == 128) DISPATCH_BY_NH_CM(BF16, 128);`, then 512/1024/2048 → FP8; **256 missing**) | after the `topk == 128` branch, before `topk == 512` | `  else if (topk == 256) DISPATCH_BY_NH_CM(BF16, 256);` — 1 line |
| 3 | `mla/_sparse_mla_sm120.py` — `_DECODE_DSV4_DISPATCH` frozenset at L79-97 | inside the frozenset | add `(8, 256), (16, 256), (32, 256), (64, 256), (128, 256)` — 5 entries |

- These are exactly the decode+prefill dispatch-table arms of #4380, minus the 192 variants. The 256 prefill
  arm uses the BF16 (index-dtype) instantiation with heads=64 — the existing `DISPATCH_MG_CM(BF16, 64, 256, MG_N_HG_DEFAULT)`
  `else` fallback already covers our head count; no `case 8` (H8) is involved.

### 4.2 Optional / cosmetic

| # | File | Note |
|---|---|---|
| 4 | `data/csrc/sparse_mla_sm120_jit_binding.cu` | comment-only in #4380 — skip |
| 5 | `mla/_sparse_mla_sm120.py` gate | #4380 adds a python-side fail-fast `ValueError` for unsupported decode sizes — recommend mirroring it as hardening (independent of the 256 arms) |

### 4.3 Excluded (explicitly NOT taken)

- All 192 top-k arms (decode table, prefill `else if`, python set) — 192 is a different integration bucket and
  is fully separable from 256.
- H8/TP8 (`case 8` + `VALID_HPB`/`REPLICATE_H`) in `prefill.cu` and `sparse_mla_sm120/prefill_kernel.cuh`.
- Dual-cache prefill changes; scheduling/efficiency refactors; #4802 top-k refactor.
- `bench_sparse_mla_sm120.py`, tests, and other upstream test changes (we keep our own verification in §9).

## 5. Why no kernel-header change is needed (clean-split verdict)

- Both kernels already honour the **runtime** per-token active topk length:
  - `data/include/flashinfer/attention/sparse_mla_sm120/decode_dsv4_kernel.cuh` L126-164:
    `topk_len = topk_length_ptr ? __ldg(topk_length_ptr) : TOPK` with per-tile masking.
  - `sparse_mla_sm120/prefill_kernel.cuh` L73-L1180: `topk_length` buffers + invalid-index masking on all
    dot-product and exp paths.
- `TOPK` is a C++ compile-time template parameter; the 256 instantiation is a **pure dispatch-table addition**.
  vLLM already passes `decode_swa_lens = 133` over the 256-wide buffer, so truncation works with zero header edits.
- **Clean-split verdict: 256-only is a clean, additive split.** Every required edit adds a parallel literal
  in an existing table/chain/set. The only upstream coupling is H8's own self-contained block (`case 8` +
  `VALID_HPB`), which is irrelevant for heads=64. 192 is independently excludable. No hunk in §4.1 conflicts with
  the out-of-scope #4380 content.

## 6. Rebuild procedure

### 6.1 Option A — JIT validation build (Phase A target)

For a derived image that must keep the toolchain + bundled source:
1. Overlay the three patched files of §4.1 onto `site-packages/flashinfer/` (same relative paths).
2. **Delete `flashinfer_jit_cache/jit_cache/sparse_mla_sm120/`** from the derived image so the AOT
   short-circuit (`is_aot`) is inactive. Also clear the per-arch runtime cache directory in the base layer if
   one is baked (`~/.cache/flashinfer/…/cached_ops/sparse_mla_sm120/`), so a stale `.so` cannot be reused.
3. First vLLM boot recompiles the monolithic `sparse_mla_sm120.so` via ninja from the patched sources
   (mtimes are the ninja input key), writing to
   `~/.cache/flashinfer/<version>/<arch>/cached_ops/sparse_mla_sm120/sparse_mla_sm120.so`.
   Cold-start cost: a few extra minutes on top of the ~11 min r1 bring-up.
4. This is exactly the artifact the Phase-A candidate runs with; a well-known-good candidate can be promoted to
   Option B afterwards.

### 6.2 Option B — AOT production build (Phase B target; NOT before §10 passes)

1. Re-run the AEON AOT-compile step **inside the derived image** with the same toolchain/flags as the JIT path
   so a fresh `sparse_mla_sm120.so` is baked as `flashinfer_jit_cache/jit_cache/sparse_mla_sm120/sparse_mla_sm120.so`.
   Requires the AEON flashinfer fork source at tag `0.6.16.post3` (the image ships only the compiled artifact +
   prebuilt bundles + bundled `data/` source, not the git tree).
2. Keep Phase-A sources overlaid (the AOT artifact must be newer than the patched sources it was made from; §8.1
   gate re-applies).

## 7. Compile architecture / ABI

- nvcc (CUDA 13.0.88), g++, cmake, ninja, all in-image; standard flags `-std=c++17 -O3 -DNDEBUG -use_fast_math -Xfatbin=-compress-all`
  plus feature enables (FP16/BF16/E4M3/E5M2, and E8M0/E2M1 where the pool permits).
- **gencode is derived from the live device** (flashinfer `normalize_cuda_arch`), producing per-arch cubins:
  SM 12.x with minor 0 → `compute_120f`/`code=sm_120f`; other minors → `...a` (SM120's `f`/`.a` split is
  flashinfer's arch-normalization convention for the strict-`fp32_atomics` vs relaxed fallback). GB10
  (DGX Spark) is **SM121** → `-gencode=arch=compute_121a,code=sm_121a`. The per-arch split keeps SM120 cubins
  from running on SM121 (illegal-instruction class), which matters because the cluster is a mixed-use fleet.
- Loader is `apache-tvm-ffi` (`tvm_ffi.load_module`) → the artifact must be produced in the AEON env/rootfs
  (same tvm-ffi + CUDA), never cross-compiled on the host. This confines the build to the image/AEON-rootfs.

## 8. Runtime verification gate — target-specific (**stale-JIT-cache**)

Purpose: prove that the running artifact is the one compiled **from the patched sources for THIS target**
(specific image tag, SM121 devices, heads=64/FP8-KV/profile), and that a stale 256-less artifact is neither
baked-in nor resurrected by the cache/JIT loader. All checks run **inside the target image** on node0 (and
node1 where noted). Image hookup:

```sh
IMG=ghcr.io/aeon-7/aeon-vllm-ultimate:2026-09-04-v0.27.1-omni-ds4flash0731-r1   # derived Phase-A tag at execution
docker run --rm --entrypoint "" "$IMG" /bin/sh -c '<check>'
```

### 8.1 mtime check — the artifact-to-use is newer than the patched sources

```sh
stat -c '%Y %n' \
  /usr/local/lib/python3.12/site-packages/flashinfer/data/csrc/sparse_mla_sm120_decode_dsv4.cu \
  /usr/local/lib/python3.12/site-packages/flashinfer/data/csrc/sparse_mla_sm120_prefill.cu \
  /usr/local/lib/python3.12/site-packages/flashinfer/mla/_sparse_mla_sm120.py \
  /usr/local/lib/python3.12/site-packages/flashinfer_jit_cache/jit_cache/sparse_mla_sm120/sparse_mla_sm120.so \
  "$HOME/.cache/flashinfer"/*/*/cached_ops/sparse_mla_sm120/sparse_mla_sm120.so
```

PASS (pre-boot): the baked AOT `.so` is **absent or older** than every patched source, AND no runtime-cache
`.so` newer than the patched sources exists (no runtime-cache entry pre-boot is normal — treat as absent). PASS
(post-first-boot): the runtime-cache `.so` mtime is **>= each patched source** mtime (ninja re-picked the
input). Fail → stale 256-less artifact would be loaded; do not peel the image for validation.

### 8.2 symbol check — the rebuilt artifact contains the 256 instantiations, only sm_121a arches, no 192

```sh
SO="$HOME/.cache/flashinfer"/*/*/cached_ops/sparse_mla_sm120/sparse_mla_sm120.so
cuobjdump --list-elf "$SO"          # expect ONLY sm_121a (compute_121a) fatbins
cuobjdump --dump-elf "$SO" | grep -c -E 'ILi256E'   # >= 6 : 5 decode (NH=8,16,32,64,128) + >=1 prefill (256)
cuobjdump --dump-elf "$SO" | grep -c -E 'ILi192E'   # == 0 : 192 deliberately absent
```

(The `Li256E`/`Li192E` spellings are the templated device-symbol arms of the dispatch kernel; record the exact
demangled names at execution time as gate evidence — the contract is the counts above, not the exact spelling.)
Optional prefill cross-check when the python module exposes the prefill dispatch: `_decode_dsv4_dispatchable`'s
prefill counterpart for `(64,256,512,64)` in the BF16 set.

### 8.3 dispatch-predicate check — image-side python probe, target parameters

The probe is committed as an in-repo unit test during Phase A and copied into the container
(`probe_topk256.py`); run inside the target image:

```sh
python3 /tmp/probe_topk256.py
```

Probe body:

```python
from flashinfer.mla._sparse_mla_sm120 import _decode_dsv4_dispatchable
cases = [
    (5, 64, 256, 512, 64, True),   # the failing r2 case — MUST now be dispatchable
    (5, 64, 192, 512, 64, False),  # 192 deliberately absent
    (5, 64, 512, 512, 64, True),   # unchanged control
    (5, 64, 128, 512, 64, True),   # unchanged control
    (5,  8, 256, 512, 64, True),   # full 256 head sweep
    (5,128, 256, 512, 64, True),
]
res = [(_decode_dsv4_dispatchable(*c[:5]) == c[5]) for c in cases]
assert all(res), res
print("TOPK256_DISPATCH_GATE PASS", res)
```

PASS ⇒ exactly the 5 added entries gate to True, controls unchanged, 192 gates to False. Importing the module
**is** the load-time `try_load`/JIT traversal — a failed/absent instantiation surfaces here before any boot.

**Gate = 8.1 AND 8.2 AND 8.3, evaluated in the target image for the exact derived tag on node0, verified
once more in a node1 run.** Record evidence (mtime triples, symbol counts, probe output) in the r2 validation
record before Phasing A→B per §10.

## 9. Phase A acceptance (full r2 functional + performance gates)

Run after the stale-JIT gate passes and with the `A'` hook reverted on the validation worktree
(`scripts/tp2-up`, `/tmp/a1` removed on both nodes):

1. Boot: `/health` 200; no CHECK abort; `sparse_mla_sm120` autotune completes; DSpark spec-decode active.
2. Generation: a real multi-turn completion OK; spec counters probe → avg ≈ 5.0 draft tokens/draft, acceptance
   rate ≈ r2-A measured (~3.1%).
3. Performance: 256-tok C1 vs **r1 baseline ≈ 18.7 tok/s** single-stream aggregate. Expectation: native 256 >
   A' 512-padded probe (≈ 11.4 tok/s). Also C2/C4 (agg) regression vs r1 (≈ 39 / 67 tok/s).
4. Needles @ 8K/32K/60K (r1 parity).
5. (Optional) truncation unit on the image: decode `(64,256)` with `topk_length=133` matches a truncated
   reference — mirrors upstream's `(32,256,133)` test.

## 10. Definition of done for the guard lift and onward

1. This design doc + §4 hunk diff reviewed clean on the review branch.
2. Stale-JIT gate (§8) green on the Phase-A candidate, both nodes.
3. §9 passes. Then and only then the production (AOT) image build (Option B, §6.2) is unlocked;
   it must re-pass §8.1+§8.2 on the produced artifact before it is pinned as the r2 image.

## 11. Exclusions and constraints (do not do)

- No A' 512-padding carry-over into production code paths.
- No wholesale flashinfer upgrade; stay on 0.6.16.post3.
- No #4802 top-k refactor; no 192; no H8/TP8; no dual-cache; no benchmark changes.
- No host cross-compilation of the binding (`tvm_ffi`/CUDA ABI).
- Image builds stay gated as described; nothing here authorizes a build by itself.

## 12. References

- Local evidence doc (r2 fail + A' probe narrative): `docs/DEEPSEEK_V4_FLASH_0731_R2_DSPARK_K5_FUNCTIONAL_FAIL_2026-09-06.md`
  (section 7c superseded by this document).
- r1 frozen baseline: `docs/DEEPSEEK_V4_FLASH_0731_R1_TP2_BASELINE_2026-09-06.md`.
- Upstream FlashInfer PR #4380 / commit 24d7dfb; image-side package probes (three-package split, JIT/AOT
  mechanism, gencode rule) were recorded in the evidence doc §7 and are folded into this document (§3, §7).