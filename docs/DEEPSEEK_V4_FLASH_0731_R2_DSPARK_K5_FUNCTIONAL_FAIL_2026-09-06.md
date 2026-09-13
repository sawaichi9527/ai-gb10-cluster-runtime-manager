# DeepSeek V4 Flash 0731 r2 — DSpark K=5 Functional Fail Root-Cause (2026-09-06)

Author: maintainer run 2026-09-06. Scope: patch-draft review only — no image build, no CI, no
dependency bump. Goal: (1) keep this analysis as evidence in-repo; (2) decide surgical vs
limited-backport by comparing against current upstream dedicated DSV4 FlashInfer sparse path;
(3) answer the semantics question: is `num_tokens <= 64` the *correct* dispatch condition or just
a legacy boundary of the general launcher.

## 1. Failure (FUNCTIONAL FAIL, not deploy-time error)

- Boot: TP2 profile `deepseek` on image `ghcr.io/aeon-7/aeon-vllm-ultimate:2026-09-04-v0.27.1-omni-ds4flash0731-r1`,
  model `DeepSeek-V4-Flash-0731-NVFP4`, explicit `--speculative-config '{"method":"dspark","num_speculative_tokens":5}'`.
- 2026-09-06 08:36:14 warmup autotune step, then 08:36:37 graph capture fails:
  `RuntimeError: Check failed: num_tokens > 64 (5 vs. 64) : Decode (num_tokens <= 64) must go
  through sparse_mla_sm120_decode_dsv3_2 or sparse_mla_sm120_decode_dsv4; got num_tokens=5`
- Evidence on Node0: `/tmp/r2-boot-full.log`, `/tmp/r2-error.txt`, `/tmp/argv-r1.txt`, `/tmp/argv-r2.txt`.

## 2. Full call chain (from boot log; all files inside the r1 image)

```
flashinfer_sparse_mla_warmup.py ... "Autotuning FlashInfer SM120 sparse MLA DSv4 decode"
vllm/models/deepseek_v4/attention.py (init/forward)             [model-level, arch DeepSeekV4ForCausalLM]
vllm/models/deepseek_v4/nvidia/flashinfer_sparse.py:688  DeepseekV4FlashInferSM120Attention.forward_mqa
  :634  _forward_sparse_impl
  :769  _forward_decode
        → flashinfer_trtllm_batch_decode_sparse_mla_dsv4(query=q, swa_kv_cache=..., sparse_indices=...,
                                           swa_topk_lens=..., kv_layout="NHD", ...)
vllm/utils/flashinfer.py                 export of the dsv4 symbol
flashinfer/mla/_core.py:1265→1133        _trtllm_batch_decode_sparse_mla_dsv4_sm120
  :453                                   _trtllm_batch_decode_sparse_mla_sm120 (common runner)
flashinfer/mla/_sparse_mla_sm120.py:708  run
  :492                                   _sparse_mla_sm120_paged_attention (custom-op dispatch)
  :380                                   impl.paged_attention
/workspace/csrc/sparse_mla_sm120.cu:261  tvm.error.InternalError CHECK(num_tokens > 64) FAILS
```

Key: **the runtime already calls the *dedicated* upstream DSV4 entry**
(`flashinfer_trtllm_batch_decode_sparse_mla_dsv4` from `models/deepseek_v4/nvidia/flashinfer_sparse.py`).
It does NOT go through the generic `FlashInferMLASparseSM120Impl`/v32 launcher. So this is not a
"wrong entry point" problem — the vLLM-side Python layer is upstream-consistent.

## 3. Semantics of `<= 64` (the question)

**`_DECODE_MAX_TOKENS = 64` is a kernel-side constant.** In the image's
`flashinfer/mla/_sparse_mla_sm120.py` (~line 74):

```
# Kernel-side constants. Mirrored from
# include/flashinfer/attention/sparse_mla_sm120/{arch,model}/*.cuh
_DECODE_MAX_TOKENS = 64
# docstring: Decode/prefill cutoff: num_tokens > _DECODE_MAX_TOKENS routes to the
# prefill orchestrator; otherwise to the standalone decode kernels.
```

The C++ side (`/workspace/csrc/sparse_mla_sm120.cu:261`) hard-checks the same boundary on the
*general* paged op: `num_tokens > 64` is the pinned precondition of the general paged/attention
entry. `num_tokens <= 64` decode must use `sparse_mla_sm120_decode_dsv3_2` or `_dsv4`.

**Verdict: `<= 64` is the correct, design-level dispatch condition** (decode/prefill cutoff baked
into the C++ and mirrored in Python), **not** merely a "legacy failure boundary" of a leftover
launcher. `num_tokens > 64` → prefill orchestrator; `<= 64` → standalone decode kernels.

## 4. Why the correct semantic still failed (the real gap)

The Python runner auto-dispatches to the standalone decode lanes only when **all** of:

| Gate | DSV4 decode lane | DSV3.2 decode lane |
|---|---|---|
| `num_tokens <= 64` | yes | yes |
| `d_qk` | 512 | 576 |
| KV page block size | `== 64` (`_DECODE_DSV4_PAGE_BLOCK_SIZE`) | `== 64` |
| `(num_heads, topk)` | heads {8,16,32,64,128} × topk {128,512,1024} | same heads × topk {128,512,1024,2048} |

r2 runtime facts (CORRECTED after the option-D probe):

- The "Setting kv cache block size to 256 for DEEPSEEK_SPARSE_SWA backend" log line refers to the
  **main MLA KV cache**. The **DSV4 SWA cache itself uses block_size = 64**, hardcoded in the Sparse
  SWA backend (`vllm/v1/attention/backends/mla/sparse_swa.py:80-82`, "determines the SWA block size
  of 64 tokens per block. TODO(yifan): make SWA block size automatically determined and
  configurable."). So `_packed_kv_page_block_size(SWA cache [num_pages, 1, 64, 584])` = 64 =
  flashinfer's expected pbs. Gate 3 is actually satisfied — there is NO missing packing/translation
  layer at the page level.
- Decode sub-batch during DSpark warmup = 5 tokens (≤ 64). ✓ gate 1.
- DSV4 ⇒ d_qk = 512 ✓ gate 2; `kv_pbs = 64` ✓ gate 3.
- The failing gate is **gate 4: `(num_heads, topk)`**. r2 DSpark K=5 forces sparse-index width
  `topk = cdiv(window_size + num_spec, 128) * 128 = cdiv(128 + 5, 128) * 128 = **256**`
  (`sparse_swa.py:487-488` `noncausal_index_width`), and **256 ∉ dsv4 set {128,512,1024}** and
  ∉ dsv3_2 candidates for d_qk=512 (dsv3_2 needs 576). Both decode lanes refuse → fall through to
  the general C++ paged op whose precondition is `num_tokens > 64` → CHECK fires.

So the crash is **purely a kernel-specialization gap**: the SM120 DSV4 standalone decode kernels are
instantiated only for topk ∈ {128,512,1024}, and DSpark K=5 on this model (window 128) requires a
sparse-index width of 256. The "few-line vLLM dispatch patch" framing is wrong: adding a `<= 64`
branch that calls the dsv4 entry changes nothing, because that entry is already the one being called
and funnels into the same runner with the same topk set gate.

The gate is not a local customization: upstream `flashinfer-ai/flashinfer` HEAD
(`flashinfer/mla/_sparse_mla_sm120.py`, matches this image's file) also has
`_DECODE_DSV4_PAGE_BLOCK_SIZE = 64` with the comment that the instantiated decode kernels are
pbs=64 only.

## 5. Experimental isolation: r1 (ok) vs r2 (fail)

`diff /tmp/argv-r1.txt /tmp/argv-r2.txt` on Node0:

```
33a34,35
> --speculative-config
> {"method":"dspark","num_speculative_tokens":5}
```

- r1 (READY 2026-09-06 08:43:36, C1 ≈ 18.73 tok/s, 256k/393k needle runs pass) had **no** explicit
  `--speculative-config`.
- r2 added the explicit dspark K=5 form and failed at cold-start autotune.
- Everything else (image, model, max_model_len, TP size, profile args) is byte-identical.

Single-variable experiment. The K-sensitive part of the sparse path is the SWA index/topk width:
`noncausal_index_width = cdiv(window_size + num_speculative_tokens, 128) * 128`
(`sparse_swa.py:487-488`; model `sliding_window = 128` from config.json):

- r1 (no spec ⇒ `num_speculative_tokens = 0`): `cdiv(128 + 0, 128) * 128` = **128** → in dsv4 set ✓
- r2 (K=5): `cdiv(128 + 5, 128) * 128` = **256** → NOT in dsv4 set ✗

**Closed.** No r1 boot log was needed: the width formula + the dispatch set fully explain the r1-ok /
r2-fail pair.

## 5b. Decisive probe (option D, no code / no image change)

Run inside the same r1 image (docker, pure Python — no GPU):

```
== probe: DSV4 SM120 decode dispatch (r2 geometry) ==
model: heads=64 d_qk=512 window=128 ; r2 K5 topk_width=256 ; r1 K0 topk_width=128
r1 K0  heads=64 topk=128 pbs=64 dsv4_dispatchable => True
r2 K5  heads=64 topk=256 pbs=64 dsv4_dispatchable => False
r2 K5  heads=64 topk=256 pbs=64 dsv3_2_dispatchable (d_qk=512, needs 576) => False
```

Plus dispatch sets printed by the probe:

- dsv4  set: heads {8,16,32,64,128} × topk {128, 512, 1024}  (no 256)
- dsv3_2 set: heads {8,16,32,64,128} × topk {128, 512, 1024, 2048} (requires d_qk = 576; DSV4 is 512)

The three probe questions:

1. vLLM logical block size → main MLA 256; **DSV4 SWA cache 64** (sparse_swa.py:82).
2. FlashInfer effective pbs → **64** (`_packed_kv_page_block_size(shape[2])` on the SWA cache);
   packed-span handling is consistent — no missing packing/translation layer.
3. DSpark K=5 actual topk width → **256**, outside both instantiations.

Launcher: DSV4 decode lane not dispatchable → general `sparse_mla_sm120_paged_attention` C++ entry →
CHECK(`num_tokens > 64`, got 5) at warmup. `num_decode_tokens = 5` (DSpark K=5), sat through the
`_forward_decode` at `flashinfer_sparse.py:769`.

Decision tree result (user-defined): **packing correct, PBS64 correct, kernel missing the topk=256
specialization → option B (limited FlashInfer kernel backport).** Note the logical64 branch is moot:
the SWA logical block size is already 64; the block size is not part of the failure.

## 6. Upstream comparison (the asked deliverable)

- vLLM upstream `vllm/models/deepseek_v4/nvidia/flashinfer_sparse.py`
  (`DeepseekV4FlashInferSM120Attention._forward_decode` → `flashinfer_trtllm_batch_decode_sparse_mla_dsv4`,
  `decode_cu = query_start_loc[: num_decodes + 1]`, kv_layout "NHD", 128 MiB workspace) — this image
  ships the same file; it is what actually failed above. No local deviation.
- Upstream `DeepseekV4FlashInferMLASparseBackend.get_supported_kernel_block_sizes() -> [256]`
  concerns the main MLA cache (SM100/general sparse); the DSV4/SM120 SWA cache is 64 and already
  matches flashinfer's pbs-64 decode instantiations — see §5b, no reconciliation needed.
- Upstream flashinfer `_sparse_mla_sm120.py` = same `_DECODE_MAX_TOKENS=64`, same pbs-64 decode set,
  same topk instantiations {128,512,1024} for dsv4. **Therefore the same K=5-on-window-128 width
  (256) would also not dispatch on current upstream flashinfer.** Implication: unless upstream vLLM
  changes the width formula or upstream flashinfer widens the set, DSpark K=5 on a window-128 DSV4
  is unsupported upstream too — nobody has validated this combination.
- Conclusion: no local customization to revert; both layers match upstream. The failure is the
  **upstream kernel-specialization gap for topk=256** (SM120 DSV4 decode), surfaced by DSpark K=5.

## 7. Fix options (decision requested — NOT applied)

| Option | Change | Build | Risk |
|---|---|---|---|
| A'. Align DSV4 sparse-index width into the instantiated topk set (256 → up to 512, len-aware) | vLLM-side (`sparse_swa.py` width alignment per dispatch set) | no image rebuild (python-only) | changes index buffer geometry/lens for the DSV4 path only; kernel must honour per-token lens < width (unverified yet) |
| B. Flashinfer-side backport: instantiate dsv4 decode kernels for topk=256 too (or widen set) | flashinfer kernel/build (TP1/generated ta) | image rebuild (against the "no image build" guardrail) | real fix; out of current scope |
| C. Route `<=64` decode through the prefill orchestrator (drop the C++ guard) | C++ patch | image rebuild | defeats the dedicated decode kernels (perf regression); last resort |

Option D (probe) is **done** (§5b) and settled the tree: packing correct, PBS64 correct, kernel
missing the topk=256 specialization → **B is the final fix direction**. Before committing to a
rebuild, the cheapest validation is **A'** (a ~1-line width-alignment in `sparse_swa.py`, no rebuild):
if the dsv4 kernel honours `swa_topk_lens` < buffer width, DSpark K=5 boots on the existing image.
If A' fails (kernel not len-tolerant), fall back to B.

## 7b. A1 experiment — DONE 2026-09-06 (A' executed; boots, kernel IS len-tolerant)

**Decision:** A' = one-boot diagnostic probe, NOT promoted as the final r2 fix (user directive).
Proof-target: with index width snapped 256→512 so the existing dsv4 topk=512 decode kernel
dispatches, r2 DSpark K=5 on the *current* image either (i) boots + passes a real generation
⇒ only the native topk=256 specialization is missing (→ proceed to B), or (ii) aborts
⇒ kernel is not len-tolerant. Booted ⇒ **(i)**.

**Probe (pre-boot, dispatch predicate, pure python, image flashinfer):**
`dsv4_dispatchable(num_tokens=5, heads=64, d_qk=512, pbs=64, topk)`:
topk=128 **True** (r1), topk=256 **False** (r2), topk=512 **True**, topk=1024 **True**.

**Change (probe-only, reverted before B):** single guard appended in
`vllm/.../backends/mla/sparse_swa.py` after the width ternary
(`..., 128) * 128 if self.is_dspark else 0`):
`if self.noncausal_index_width == 256: self.noncausal_index_width = 512`.
`decode_swa_lens` (per-token lens) untouched; fill kernel writes `-1` sentinel in the padded
columns. Injected via guarded bind-mount (`A1_SWA_PATCH=1`,
`tp2-up` commit `88e5b3e` on `experiment/deepseek-v4-dspark-k5-r2`), no image rebuild.

**Result (frozen r2-A config, live cluster):**

| Check | Result |
|---|---|
| Boot gate (CHECK `num_tokens > 64`) | **PASS** — SM120 DSV4 decode autotune cache loaded; no abort; dedicated dsv4 kernel path ran |
| `/health` | **200 READY** |
| K=5 draft active | argv `--speculative-config {"method":"dspark",...:5}`; live ports `spec_decode_num_draft_tokens_total=1855` over 371 drafts = **avg 5.0 draft tokens/draft** (K=5 shape machine-correct) |
| Generation | **OK** — 48-tok + 256-tok completions, plausible text, no crash |
| Acceptance | 58 / 1855 ≈ **3.1 %** (≈0.6 token/draft accepted) — drafter quality poor at K=5, mechanics fine |
| C1 decode | 256 tok / 22.4 s ≈ **11.4 tok/s** (r1 baseline ≈18.7 tok/s single-stream) |

**Conclusion:**
- The existing DSV4 SM120 kernel **honours `swa_topk_lens` < buffer width** ⇒ the only remaining
  image defect is the **missing native topk=256 decode specialization** for SM120 DSV4.
- **Proceed to B** (limited FlashInfer kernel backport: instantiate dsv4 decode for topk=256 or
  widen the dispatch set) as the production fix.
- **Do NOT promote the 512-padding workaround as the final r2 implementation.**
- Artifacts: patched `sparse_swa.py` sha256 `783ff2ea4556cdb9550b581d34132df26cd66fd383926ae37a29b7e35a6862b9`
  (Node0+Node1 `/tmp/a1/sparse_swa.py`, py_compile clean); probe `probe_a.py`; boot log
  `/tmp/a1-boot.log`; gen `/tmp/a1-gen.json`, `/tmp/a1-timed.json`; commit `88e5b3e`.
- Revert-before-B checklist: drop the `A1_SWA_PATCH` hook in `scripts/tp2-up`, delete
  `/tmp/a1/*` on both nodes.

## 7c. B design — SM120 DSV4 topk=256 backport (status: EXTRACTED)

Design moved to the independent production backport design document (branch
`image-workstream/dspark-k5-topk256-backport`, from Forgejo main `571cd65`):
`docs/DEEPSEEK_V4_FLASH_0731_R2_DSPARK_K5_TOPK256_BACKPORT_DESIGN_2026-09-06.md`.
It carries the 256-only backport map (files/hunks/anchors), clean-split verdict, Option A/JIT + Option B/AOT
rebuild procedures, expected compile architecture/ABI, the target-specific stale-JIT-cache verification gate
(mtime + symbol + dispatch predicate), and the Phase-A acceptance gates. The "no image build" guard lifts per
that doc §10 (doc/diff reviewed clean → Phase A JIT-validation build), and the AOT production image must not be
built until the JIT candidate passes the full r2 functional/performance gates.

## 8. Frozen r2-A baseline (unchanged)

- Attribute set: MAXLEN=65536, TP2, EP off, `fp8_ds_mla`, GMU=0.80, num_seq=4, batched=4096,
  PIECEWISE, prefix cache off, same image, same model, embedded spec form
  `--speculative-config '{"method":"dspark","num_speculative_tokens":5}'`.

## 9. Handoff lineage

- This repo: `docs/TP2_DEPLOYMENT_2026-08-30.md`, `docs/RESTRUCTURE_2026-08-31.md`,
  `docs/TP2_PROFILE_REFACTOR_VALIDATION_2026-09-05.md`,
  `docs/DEEPSEEK_V4_FLASH_0731_R1_TP2_BASELINE_2026-09-06.md`.
- Sibling maintenance handoffs `...09-03.md` / `...09-04.md` (repo or sibling repo) carry the
  per-run operational context for this r1/r2 DeepSeek V4 Flash bring-up.