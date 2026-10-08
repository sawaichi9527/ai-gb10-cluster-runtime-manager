# DeepSeek V4 Flash 0731 NVFP4 TP2 — spec-decode A/B campaign (2026-10-08)

**Question.** Can the live `deepseek-nvfp4` lane (eugr/spark-vllm-b12x,
spec decode `num_speculative_tokens=5`) be made faster on C1 (single-stream
tok/s) by (a) raising the DSpark depth k to 6/7, (b) turning on
`rejection_sample_method: block`, (c) `enable_adaptive_verification`, or
(d) the sparse-MLA attention variant that community recipes mention?

**Method.** Same discipline as the E-/V-campaigns: a dedicated lane
`cluster-profiles.d/deepseek-nvfp4-tune.conf` (byte-copy of
`deepseek-nvfp4.conf` except `PROFILE_ID`/`DISPLAY_NAME`/`STACK_DIR`/
`COMPOSE_FILE`/lane-local cache+autotune roots), cells applied by
`scripts/ab-setcell.sh N<n>` (restores the pristine `.base` first — no cell
inherits the previous edit), driven end-to-end by
`scripts/ab-run-cell.sh N<n> N<n> deepseek-nvfp4-tune`
(compose-verify both ranks → smoke → bench). **`deepseek-nvfp4.conf` was never
touched** and remained the rollback target (restored + smoke-passed at
18:29 after the campaign).

**Harness.** `scripts/bench-ab-deepseek.sh` — decode `BENCH_IGNORE_EOS=1`
(400 tok/stream), C=1…8, 3 runs each, medians; cold prefill at 32K/131K/200K;
engine diag proof-of-effect. Evidence: `docs/evidence/nvfp4-ab-2026-10-08/ab-N*.txt`
(source `/tmp/ab-<cell>.txt` on node0).

**Noise floor:** ≈ ±7 % decode (measured in the E-campaign). Deltas smaller
than that — and above all deltas that flip sign on repeat — are not results.

**New harness fixes made during this campaign:**

- `bench-ab-deepseek.sh`: the engine-diag argv loop was missing `|| true` on
  the `v="$(… grep …)"` assignment — under `set -e`/`pipefail`, an argv knob
  the profile does not use (nvfp4 has no `--long-prefill-token-threshold`)
  killed the whole cell silently right after `argv --block-size`. Fixed.
- `ab-setcell.sh`: the first N-cell implementation rewrote the whole
  `SPEC_CONFIG` line from a template, so `N-win(N1,N5)` silently dropped N1's
  field; rewritten as field-level edits with post-assertions
  (`nv4_assert_spec`), verified with composition dry-runs.
- `ab-run-cell.sh`: `AB_REF` now auto-selects `N0` for `*nvfp4*` profiles.

---

## Cell plan

| cell | knob | rationale |
|------|------|-----------|
| N0 | baseline (≡ `deepseek-nvfp4.conf`) | reference |
| N1 | `SPEC_CONFIG` + `rejection_sample_method:"block"` | used by the Openzeka/Kimi K3/tonyd2wild recipes; keeps more of an accepted prefix on partial rejection; absent from our config |
| N2 | `num_speculative_tokens` 5 → 6 | online consensus says the in-checkpoint draft head is trained for blocks of 5; measure, don't assume |
| N3 | `num_speculative_tokens` 5 → 7 | the *vLLM official-recipe* depth — but k=5 is what eugr's canonical recipe pins for this checkpoint |
| N4 | N1 + `enable_adaptive_verification:true` | confidence-scheduled verification (vLLM blog 2026-08-14) |
| N5 | `B12X` → `B12X_MLA_SPARSE` (main + spec attention backend) | eugr canonical recipes in community write-ups cite a "sparse" variant; our profile uses plain `B12X` |
| N-win | winners combined | never reached — no winner |

Each cell = one profile edit → cold boot (~20 min) → gates → full bench
(~10 min). N1 was run twice (N1, N1b) per the "<2 % must repeat same-sign"
rule.

---

## Results

### Σ C1..C8 (median tok/s, the campaign's headline metric)

| cell | Σ | vs N0 | C1 | C1 accept | verdict |
|------|-----|-------|----|-----------|---------|
| N0 baseline | **729.5** | — | 46.8 | 48.5 % | reference |
| N1 block | 737.8 | **+1.1 %** | 44.2 (−5.6 %) | 42.8 % (−5.7pp) | noise (sign-flips on repeat) |
| N1b block (repeat) | 721.2 | **−1.1 %** | 42.5 (−9.2 %) | 41.6 % (−6.9pp) | noise; C1 negative **twice** |
| N2 k=6 | 666.2 | **−8.7 %** | 41.3 (−11.8 %) | 36.8 % (−11.7pp) | **rejected** |
| N3 k=7 | 607.2 | **−16.8 %** | 37.3 (−20.3 %) | 29.6 % (−18.9pp) | **rejected** |
| N4 adaptive | — | — | — | — | **boot fail** |
| N5 sparse backend | — | — | — | — | **invalid knob** (see below) |

### N1 — `rejection_sample_method: block` (run twice)

Acceptance at C=2…8 rose in both runs (+0.5…+4.1 pp, 7/8 and 6/8 cells
positive) — the mechanism works as advertised. But:

- Σ: **+1.1 % then −1.1 % → sign flip ⇒ noise**, both far inside ±7 %.
- **C1 — the target metric — fell in both runs (−5.6 %, −9.2 %)**, and C1
  acceptance fell both times (−5.7pp, −6.9pp). Same-sign negative on the
  metric we care about.

**Verdict: rejected.** The throughput claim is noise; the C1 effect is
consistently negative. Not promoted.

### N2 — k=6

Acceptance collapses −4…−12 pp across all eight cells (48.5 % → 36.8 % at
C1), Σ −8.7 %, C1 −11.8 %. The pre-campaign prediction from the community
field notes (the head is trained for block=5; pos-6 acceptance ≈ 0.5) is
confirmed locally: the extra draft token is mostly rejected, and the wider
verify pass costs more than the extra acceptances return.
**Rejected.**

### N3 — k=7 (vLLM official-recipe depth)

Worse still: acceptance −10…−19 pp (48.5 % → 29.6 % at C1), Σ −16.8 %,
C1 −20.3 %. Cold prefill at 32K also −56 % (extra verify work under the
cold path). **Rejected.** This settles the online-research question: for
*this* checkpoint on GB10, **k=5 is optimal**; the vLLM doc's k=7 default
does not apply to the DSpark head shipped in DeepSeek-V4-Flash-0731.

### N4 — `enable_adaptive_verification` (boot fail)

vLLM accepted the flag (config dump shows
`enable_adaptive_verification: True`), but the wider/extra graph capture
blew the memory budget:

```
Graph capturing finished in 53 secs, took 4.27 GiB   (N0: 0.92 + 0.72 GiB)
Available KV cache memory: 6.56 GiB  <  7.19 GiB required for 262144
ValueError: ... would need to be bigger ... (max_model_len 262144 vs 87296)
```

Boot never reached READY; `gb10 wait` hit its timeout and the cell was
marked FAILED. **Rejected** (same class as the V2 failure: knob is real but
does not fit this lane's memory envelope at GMU 0.85 / capture 48 / 262144).

### N5 — `B12X_MLA_SPARSE` (invalid knob — the research premise was wrong for this image)

Boot failed in <2 min with a pydantic validation error:

```
ValueError: Unknown attention backend: 'B12X_MLA_SPARSE'. Valid options are:
... B12X, FLASH_ATTN_MLA, FLASH_ATTN_MLA_SPARSE, ... (no B12X_MLA_SPARSE)
```

Follow-up inspection of the image (`eugr/spark-vllm-b12x`,
`vllm 0.1.dev21554+geda1715e9.d20261006`):

- the attention registry registers **`B12X` only** — there is no
  `B12X_MLA_SPARSE` backend in this build at all (neither for the main
  `--attention-backend` nor for `SPEC_CONFIG.attention_backend`);
- DeepSeek V4's sparse indexer is **built into the model implementation**
  (`vllm/models/deepseek_v4/attention.py` → `_sparse_indexer_and_attn`,
  unconditional) — sparse decode already runs under plain `B12X`;
- `VLLM_USE_B12X_SPARSE_INDEXER=1`, which the profile sets and which the
  earlier research read as "sparse already enabled, just pick the backend",
  **does not exist in this image's `envs.py`** — it is a no-op knob carried
  over from the Anemll-image era.

**Verdict: not a knob.** The "sparse variant" cited by community recipes
belongs to a different image line (the Anemll `dspark-vllm-gx10` family /
newer eugr builds). No re-test needed; the only tunable cousin left in this
image is `kernel_config.sparse_indexer_topk_backend` (top-k *kernel*
selection, `auto` default) — a different, untested lever, out of scope here.

---

## Conclusion

**No change to the production lane.** `deepseek-nvfp4.conf` keeps
`num_speculative_tokens=5`, no `rejection_sample_method`,
`attention_backend=B12X`, no adaptive verification. C1 stays at ~47 tok/s
(baseline Σ 729.5).

Research question answered definitively:

1. **k=6/7 do not exist as a free lunch** — locally measured, both are clear
   losses (−8.7 % / −16.8 % Σ); the community "k=5 is the trained depth"
   claim is confirmed on GB10.
2. **`rejection_sample_method: block`** — mechanism visible in acceptance
   (+1…+4 pp at C2–C8) but Σ noise and **C1 consistently negative** → no.
3. **`enable_adaptive_verification`** — flag exists but doesn't fit the
   memory envelope at 262144 → boot fail.
4. **Sparse MLA backend** — doesn't exist in this image; sparse decode
   already built into the model path.

Remaining untried levers for a future session (not attempted, no claims):
`kernel_config.sparse_indexer_topk_backend`, `CUDAGRAPH_CAPTURE` 48 → 64
(eugr canonical uses 64), `max_num_batched_tokens` 8192 → 4096 +
`max_num_seqs` 8 → 6 (eugr canonical), `--async-scheduling` (TP2 stability
risk, watchlist only).

## Runtime / hygiene

- Campaign ran 14:04–18:29 (+08:00) on node0; the exclusive TP2 port 1234
  was occupied by the tune lane throughout; production `deepseek-nvfp4`
  restored and smoke-tested (`HELLO-TP2-OK`) at 18:29.
- `deepseek-nvfp4-tune{,.base}.conf` left in the repo as the A/B lane
  (listed under "A/B evaluation only — NOT services" in `gb10 list`), conf
  restored to pristine N0 (sha `979cbefc704fd992`).
- One harness quirk hit: after N5's failed boot, `gb10-boot-cluster` lingered
  in its health-wait loop and blocked the next cell
  (`background boot for another profile already running`); killing the stale
  PID let the campaign continue. Watch for this after any boot-fail cell.
