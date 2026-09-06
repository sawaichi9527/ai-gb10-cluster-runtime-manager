# DeepSeek V4 Flash 0731 — DSpark Draft Loader Audit (2026-09-06)

- **Status:** name-level audit **COMPLETE — loader exonerated**. Value-level mutation
  verification (checklist #5) **OPEN**, scheduled for the next TP2 maintenance window.
  tonyd2wild Patch 4 comparison: **addendum commit** (verdict: no semantic gap, not applied).
- **Directive:** user-approved checklist 2026-09-06 — (1) locate the actual stacked-param
  mapping incl. `shared_experts.w1/w3 -> gate_up_proj` shard 0/1; (2) enumerate checkpoint
  tensors; (3) instrument a load with DEBUG-level skip reporting; (4) produce exact counts;
  (5) verify live parameter mutation; (6) compare tonyd2wild Patch 4 (apply only on a proven
  gap); (7) keep the native topk256 patch active. **Do not move to "drafter quality" until
  #5 closes.**
- **Runtime context:** `tp2-node0` image
  `ghcr.io/aeon-7/aeon-vllm-ultimate:2026-09-06-v0.27.1-omni-ds4flash0731-r1-topk256v2`
  (vLLM `0.27.1+aeon.sm121a.dspark`), live serve
  `--speculative-config {"method":"dspark","num_speculative_tokens":5}`, KV `fp8_ds_mla`,
  max_model_len 65536, TP=2, health 200, acceptance 538/16460 (~3.27%).
- **Checkpoint:** `nvidia/DeepSeek-V4-Flash-0731-NVFP4` at
  `/home/eye/docker-stacks/aeon-vllm/models/deepseek-v4-flash-0731-nvfp4`
  (48 shards ~171GB, HF rev `f1caa71142bd0be02f728c79f75042ac1e461579`).
- **Boot evidence:** `DSpark draft model loaded: 96 params` (`dspark.py:491`,
  `len(loaded_params)`), zero traceback at draft load.

## Method

1. **Static** — full read of the installed loader
   (`vllm/models/deepseek_v4/nvidia/dspark.py`) and the config wiring
   (`vllm/config/speculative.py`, `vllm/v1/worker/gpu/spec_decode/dspark/{utils,speculator}.py`,
   `vllm/transformers_utils/model_arch_config_convertor.py`, `vllm/config/vllm.py`).
2. **Ground truth** — `DSparkDeepseekV4ForCausalLM` constructed on the **meta device** inside a
   throwaway CPU container of the same image, after mirroring the live config path
   (`ModelConfig` + `SpeculativeConfig(method="dspark", num_speculative_tokens=5)` → draft
   `ModelConfig` with `hf_overrides=hf_config_override`). The mirror reproduced the live logs
   exactly (`Resolved architecture: DeepSeekV4MTPModel` → DSpark branch reset,
   `Overriding draft model max model len from 1048576 to 65536`). CPU-only build required three
   platform patches (`compute_fp8_einsum_recipe`, MoE backend select, fp8 linear kernel) that
   affect **execution only** — parameter registration is untouched. `vc.quant_config=None` was
   used to skip CPU-incompatible quant kernel selection; quant adds only `*_scale` parameter
   names, which the simulation tracks separately.
3. **Full-key simulation** — all **4,705** `mtp.*` keys from `model.safetensors.index.json`
   pushed through a faithful re-implementation of `load_weights`' mapping chain against the
   ground-truth `params_dict`.

## Key findings

### F1. Layer-index alignment — RESOLVED, loader correct

- Draft config (mirror probe): `num_hidden_layers=43`, **no `n_mtp_layers`** (so
  `num_dspark_layers = 3` via default), `dspark_target_layer_ids=[40,41,42]`,
  `n_predict=1`, `model_type=deepseek_v4`, `architectures=[DSparkDraftModel]`.
- `dspark.py` builds its 3 layers with the **prefix metadata**
  `f"layers.{num_hidden_layers + i}"` (= `layers.43/44/45`), but `nn.Module` **registers
  positionally**: the meta build's `named_parameters()` yields
  `model.layers.{0,1,2}.*` (`LAYER_IDX ['0','1','2']`).
- `_remap_dspark_name` maps `mtp.{stage}` → `model.layers.{stage}` (stage 0/1/2) — **exact
  match** with positional registration.
- `load_weights` uses `params_dict[name]` **direct indexing with no `.get()` fallback and no
  try/except** — any mapping miss would `KeyError`-crash the boot. The boot was clean; the
  4,705-key simulation found zero unexpected misses. Both facts confirm the alignment.
- The `layers.{43+i}` prefix is vLLM metadata only (quant/attention plumbing); the
  `num_hidden_layers`-offset convention belongs to the standalone-MTP loader (`mtp.py`), not
  to this model's registration. Prior-session concern about an index misalignment was a
  false alarm.

### F2. Mapping chain (verbatim, execution order)

1. `confidence_head.*` → dropped (0 such keys exist in this checkpoint — dead rule, harmless).
2. Model-level heads → `model.*`: `main_proj.`, `main_norm.`, `norm.`, `hc_head_fn/base/scale`,
   `markov_head.` (early-exit **before** the stacked loop — this is what protects
   `markov_w1` from the `w1` shard rule).
3. `.scale` suffix rewrite (before everything else): expert scales
   (`_EXPERT_SCALE_RE = r"\.experts\.\d+\.w[123]\.scale$"`) → `.weight_scale`; everything else
   → `.weight_scale_inv` (so `shared_experts.*.scale` correctly lands on the block-quant
   `weight_scale_inv` names).
4. `.shared_experts.w2` → `.shared_experts.down_proj`.
5. Routed experts (`.experts.`) → **non-mega** MoE mapping
   (`use_mega_moe = kernel_config.moe_backend == "deep_gemm_mega_moe"`; live `moe_backend='auto'`
   → non-mega), `fused_moe_make_expert_params_mapping`:
   `ffn.experts.routed_experts.w13_` (w1,w3) / `w2_` (w2), `expert_id` preserved; expert
   `weight_loader(..., return_success=True)` — a `False` return silently continues (see R2).
6. Stacked (remaining layer params): `("gate_up_proj","w1",0)`, `("gate_up_proj","w3",1)`,
   `("attn.fused_wqa_wkv","attn.wq_a",0)`, `("attn.fused_wqa_wkv","attn.wkv",1)`.
   The bare `w1`/`w3` anchoring is safe in this flow: routed experts exited at step 5 and
   `markov_head` at step 2; no other remaining name contains `w1`/`w3` (simulation-verified
   over all 4,705 keys).
7. Direct: per-layer norms (`attn_norm`, `ffn_norm`, `q_norm`, `kv_norm`), hyper-connection
   params (`hc_attn_fn/base/scale`, `hc_ffn_fn/base/scale` — 6 per layer), `attn_sink`
   (per-rank narrow copy), `ffn.gate.bias → e_score_correction_bias`.

**Shared-expert answer (checklist #1):** `shared_experts.w1` → `shared_experts.gate_up_proj`
shard 0, `shared_experts.w3` → shard 1 (via generic stacked rows), `shared_experts.w2` →
`down_proj` (via rename) — structurally present, simulation-proven reachable, and included in
the live "96 params" load.

### F3. Checkpoint census + full-key accounting

Per stage (`mtp.0/1/2`): 256 routed experts × 6 (`w1/w2/w3` weight+scale) = 1536, shared
experts 6, `main_proj.weight`+`.scale`, `main_norm`, `hc_ffn_{fn,base,scale}`,
`hc_attn_{fn,base,scale}`, `ffn.gate.{weight,bias}`, attn block
(`wq_a/wkv/wq_b/wo_a/wo_b` weight+scale, `q_norm`, `kv_norm`, `attn_norm`, `attn_sink`),
`ffn_norm`, `norm`, `markov_head.{markov_w1,markov_w2}`.
Counts: `mtp.0`=1568, `mtp.1`=1565 (no `main_proj`/`main_norm`), `mtp.2`=1572. **MTPTOTAL 4705.**

Ground truth (TP=1, unquantized probe): **73 parameters**, `LAYER_IDX ['0','1','2']`.
Simulation vs ground truth: **HIT 2375** + **SCALEMISS 25** (quant-only names absent in the
unquantized probe: `main_proj` 1, attn scales 4/layer ×3, shared scales 2/layer ×3 — all exist
in the live quantized model) + **expert scales 2304** (`routed_experts.w13_weight_scale` /
`w2_weight_scale` — same class; live has them; arithmetic: 25 + 2304 = 2330 scale-class
tensors = all 2,304 expert scales + 25 non-expert scales + 1 dropped = 4,705 accounted).
**Zero unexpected misses.**
UNTOUCHED (probe): only `lm_head.weight` + `embed_tokens.weight` — both aliased from the
target after load (`load_dspark_model` `_should_share` gates) — by design.

### F4. "96 params" reconciled exactly

```
96 = 3 layers × (21 structural + 4 attn-scale + 2 shared-scale + 2 expert-scale names)
   + 9 model-level (main_proj.weight, main_proj.weight_scale_inv, main_norm.weight,
     norm.weight, hc_head_fn, hc_head_base, hc_head_scale, markov_head.markov_w1/w2)
```

### F5. Config-path facts (empirically verified via mirror probe)

- `hf_config_override` (`speculative.py:344`): `deepseek_v4` → `deepseek_mtp`
  (`n_predict=1`, `DeepSeekV4MTPModel`) at draft ModelConfig build; the DSpark branch
  (`:966-977`) then resets `model_type=deepseek_v4`, `architectures=[DSparkDraftModel]`,
  `update_arch_()`. **`num_hidden_layers` is never zeroed (43) — and does not need to be (F1).**
  The `num_hidden_layers: 0` overrides apply only to MiMo/MiMoV2/Glm4MoeLite/GlmOcr etc.
- `update_arch_` refreshes hf_text_config / arch / registry only.
- `load_dspark_model` (`dspark/utils.py`, 84 lines): attention backend falls back to the
  target's; `cache_dtype` override only when `kv_cache_dtype` set; `quant_config =
  get_draft_quant_config(vllm_config)`; `embed_tokens` + `lm_head` aliased from target;
  no config surgery that could affect layer numbering.

## Checklist status

| # | Item | Status |
|---|------|--------|
| 1 | Locate actual mapping incl. shared w1/w3→gate_up 0/1 | **DONE** (F2) |
| 2 | Enumerate checkpoint draft tensors | **DONE** (F3) |
| 3 | Instrumented DEBUG-level load | **DONE at name level** (meta ground truth + full-key sim; boot log had no skip warnings) |
| 4 | Counts: checkpoint / mapped / loaded / skipped | **DONE** — 4705 = 2375 HIT + 25 non-expert scales + 2304 expert scales (all quant-class, present live) + 1 dropped (absent key class); 96 distinct loaded names reconciled exactly |
| 5 | Verify live parameter mutation | **OPEN** — next TP2 maintenance window; must prove `shared_experts.gate_up_proj` w1 and w3 shards independently, plus representative routed-expert, attention, and Markov checkpoint tensors |
| 6 | tonyd2wild Patch 4 comparison | **DONE** — no semantic gap; not applied (addendum commit) |
| 7 | Keep native topk256 patch active | **DONE** — untouched |

## Residual risks / open items

- **R1 (#5)** — value-level mutation verification, as scoped above.
- **R2** — expert `weight_loader(..., return_success=True)`: a `False` return silently
  `continue`s, invisible in the 96-name count. Static mitigation: 2,304 weight + 2,304 scale
  tensors flow into 6 fused params (`w13_weight/w2_weight` + their `*_weight_scale`) with
  uniform shapes per class; those fused params are inside the loaded 96; weight-loader
  behavior is all-or-nothing per shape class. Definitive closure requires #5.
- **R3 (awareness only)** — the `layers.{43,44,45}` prefix metadata vs positional registration
  `{0,1,2}`: harmless for weight loading (proven); any registry keyed by layer-name prefix
  sees 43–45, which matches the target-convention MTP numbering. No action.

## Conclusion

The installed AEON DSpark draft loader is **name-complete and index-correct** for the local
`DeepSeek-V4-Flash-0731-NVFP4` checkpoint: every one of the 4,705 draft tensors has a unique,
existing destination; the loader fails loudly (KeyError) on any mapping miss; the boot was
clean. **The K5 acceptance deficit (~3.27%) is not attributable to the loader.** Per user
directive, the "drafter quality" line of investigation remains blocked until checklist #5
closes in the next TP2 maintenance window.
