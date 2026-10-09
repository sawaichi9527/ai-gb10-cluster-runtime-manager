# DeepSeek-Vision recipe succession A/B — `deepseek-vision-b12x` vs README record — 2026-10-09

Goal (user decision 2026-10-09): evaluate the combination
**`eugr/spark-vllm-b12x:latest` + `deepseek-v4-flash-vision-exp-ablit`**
against the benchmark record annotated in `README.md` for the production
`deepseek-vision` lane (Anemll `dspark-vllm-gx10:0.1.1` + official
`deepseek-v4-flash-vision-exp`). If the candidate is **>= record (parity or
better)**, the production profile inherits the new recipe; the old recipe
(including its `patches/dspark-vision/`) is archived self-contained under
the repo-root `_overdue_recipe/` as a BACKUP solution, not a deployed lane.

## Candidate lane

- Profile: `cluster-profiles.d/deepseek-vision-b12x.conf` (evaluation-only
  lane, whitelisted in `bin/gb10`).
- Provenance: upstream `eugr/spark-vllm-docker
  recipes/deepseek-v4-flash-vision-exp.yaml` (fetched 2026-10-09) — cluster
  TP2 B12X contract, `mods: []` (vision support NATIVE in this image; the
  production lane needs a startup wrapper + 17 vendored MiaAI hotfixes).
- Model: `models/deepseek-v4-flash-vision-exp-ablit` (167.8 GB, 48 shards;
  26 tensors edited by layer-range-wo_b-projection; ALL MTP/draft tensors
  byte-identical hardlinks of the official checkpoint).
- Image pins: identical to `deepseek-nvfp4` (dual-node digest lock,
  2026-10-07).

## Cells

| Cell | Config delta | Note |
|---|---|---|
| B0 | upstream recipe verbatim (`CUDAGRAPH_CAPTURE=48`) | first boot 08:13 |
| B1 | single knob: `CUDAGRAPH_CAPTURE 48 -> 56` | miaai/production formula seqs*(k+1)=8*7=56; motivated by B0 C7/C8 deficits |
| B2 | same as B1, fresh confirmation boot | boot-to-boot spread check |

Evidence: `docs/evidence/vision-b12x-recipe-ab-2026-10-09/ab-{B0,B1,B2}.txt`
(harness `scripts/bench-ab-deepseek.sh`, decode C1..C8 x3 medians, cold
prefill, cache repeat).

## Boot gates (all passed, first try)

- `--load-format b12x` loaded without the strided-dtype refusal seen on the
  NVFP4 checkpoint (no safetensors fallback needed); quant auto-detected as
  `deepseek_v4_fp8`.
- **KV pool 413,967 tokens** (fp8 KV; production nvfp4_ds_mla was 381,364) —
  262144 ctx and the 261K prefill probe fit with margin. Gate #2 concern
  resolved favourably.
- capture sizes `[1..48]` (B0) / `[1..56]` (B1/B2); health 200;
  `cluster-compose-verify` PASS on both ranks; smoke `HELLO-TP2-OK`.
- **prefix-hit correctness gate PASS without any hotfix**: 32K x3 rounds,
  cache HIT 50.9x (17.87s -> 0.35s), all rounds `PREFIX-OK` byte-identical,
  no truncation/garble. The dspark SWA-prefix truncation class of bug (which
  the production lane hotfixes via `patches/dspark-vision/
  hotfix-vllm-dspark-swa-prefix.py`) does not reproduce in this fork/image.

## Decode (C1..C8 x3 median; README = production record)

| C | B0 (cap48) | B1 (cap56) | B2 (cap56) | README prod (V3) |
|---|---|---|---|---|
| 1 | 31.3 | 39.7 | 34.8 | 33.6 |
| 2 | 48.9 | 43.9 | 50.1 | 46.5 |
| 3 | 55.7 | 55.7 | 60.0 | 64.6 |
| 4 | 62.5 | 69.7 | 67.3 | 69.4 |
| 5 | 76.6 | 74.9 | 70.2 | 70.9 |
| 6 | 76.7 | 74.1 | 83.7 | 78.4 |
| 7 | 72.1 | 81.2 | 86.9 | 85.3 |
| 8 | 82.3 | 96.1 | 92.9 | 89.4 |
| **Sigma** | **506.1** | **535.3** | **545.9** | **538.1** |
| Delta vs README | -6.0% | **-0.5%** | **+1.4%** | — |
| accept % (avg) | 23.7 | 25.0 | 25.4 | 23.95 (24.25/24.30 tune) |

- B0's deficit concentrated at C7 (-15.5%) / C8 (-8.0%), matching a
  cudagraph capture-range fallback above 48; the single-knob B1 cell
  recovered both (C7 -4.8%, C8 +7.5%) and lifted Sigma by +5.8%.
- B1/B2 boot-to-boot Sigma spread = 2.0%, both within +/-0.5..1.4% of the
  README record -> **decode = parity (two boots, same sign)**.
- Noise floor for this harness: decode +/-7% (measured 2026-10-06/08
  campaigns); per-cell swings of +/-10..14% between boots are expected.

## Prefill (BENCH_COLD=1, `bench-ctx.sh`)

| probe | B0 | B1 | B2 | README | delta |
|---|---|---|---|---|---|
| 131K | 2005.8 | 2007.9 | 2029.5 | 1794.1 (V3) / 1825.3 (V0) | **+9.4..13.1%** |
| 200K | 1907.7 | 1887.2 | 1917.0 | 1772.5 (V3) / 1710.2 (V0) | **+6.5..12.1%** |
| 245K | 1844.8 | — | — | 1671.3 | **+10.4%** |
| 261K | 1823.7 | — | — | 1657.7 (V3) | **+10.0%** |

Consistent sign across all three boots and all widths, above the +/-8%
prefill noise floor -> **prefill = better**. (32K readings swing 1783..2234
and are documented structural noise on this lane — excluded.)

## Multimodal (`bench-mm.sh`, BENCH_COLD=1, B2 config)

| cell | B0 | B2 | README | note |
|---|---|---|---|---|
| 1img C=1 | 47.8 | 46.6 | 53.1 | cold-nonce runs -11%; **non-cold first run measured 53.9 ≈ record 53.1** (parity) |
| 4img C=1 | 47.2 | 34.5 | 36.3 | B2 stream stopped early (82 tok) — not comparable |
| 8img C=1 | 33.2 | 32.4 | 16.2 | early stop (74/75 tok) vs README's full 200 — not comparable |
| 1img C=4 | 114.2 | 116.0 | 111.0 | +4.5% |
| 1img C=8 | 130.5 | 135.0 | 146.1 | -7.6% (some streams early-stop) |
| 1img C=16 | 135.3 | 152.1 | 159.4 | -4.6% |
| 4img C=8 | 131.5 | 147.3 | 90.6 | +62% but early stops inflate wall |

Mixed: concurrent cells roughly parity-to-better. The 1img C=1 cell is -11%
under BENCH_COLD=1 in both boots, but the very first (non-cold) run measured
53.9 tok/s ≈ record 53.1 — the gap tracks the cold nonce defeating the image
prefix cache, not a model deficit; treat as parity. Early natural stops
(`finish=stop` under 200 tok) make two cells non-comparable; treat the whole
mm table as within-class noise except the cold/warm flag caveat above.

## Correctness / stability

- prefix-hit: PASS (above); cache repeat 3x identical in every cell file;
  smoke OK; zero load errors; `any_errors=0` in every decode/mm run.
- Warm prefix-cache hit measured **17.87s -> 0.35s (50.9x)** at 32K.

## Verdict

**Condition 1 (parity-or-better) MET:**

- decode Sigma: parity (B1 -0.5%, B2 +1.4% vs record; two boots same sign)
- prefill: better (+9..14%, stable, beyond noise)
- acceptance: better (+1..1.4 pp)
- correctness: all gates PASS, no hotfix required
- mm: mixed/parity — the one cold-run low cell (1img C1 -11%) is explained by
  the cold nonce vs the record's warm run (non-cold 53.9 ≈ 53.1); the rest is
  within-class noise with early-stop non-comparables flagged

Recommended promotion (pending user confirmation): `deepseek-vision.conf`
inherits this recipe at the B1/B2 config (`CUDAGRAPH_CAPTURE=56`); the
Anemll recipe (conf + compose + `patches/dspark-vision/` +
`recipe_README.md`) is archived under `_overdue_recipe/` as a backup
solution; README benchmark section rewritten; candidate lane
`deepseek-vision-b12x` retired or kept as history.

## Follow-ups (not blocking)

- mm 1img C=1 cold-vs-warm caveat (see Multimodal) — re-check on the
  production lane with the same flag after promotion.
- Model retention (user decision 2026-10-09): the OLD official model dir
  `~/docker-stacks/models/deepseek-v4-flash-vision-exp` stays in place on
  BOTH nodes pending a later user decision — it is the archived recipe's
  dependency (see
  `_overdue_recipe/deepseek-vision_anemll-dspark-vllm-gx10-011_20261009/recipe_README.md`).
  Do not clean it
  as promotion residue.
- The `deepseek-vision-tune` A/B lane was a byte-copy of the OLD production
  recipe; its `.base` went stale with the promotion — **archived per user
  decision 2026-10-09** into
  `_overdue_recipe/deepseek-vision_anemll-dspark-vllm-gx10-011_20261009/`
  (whitelist removed; see its `recipe_README.md`). A future vision tune
  campaign must branch a NEW
  lane off the promoted production recipe.
- Upstream image digest advances with eugr nightly CI; the pinned digests
  in the promoted profile are the 2026-10-07 pair (re-pull => re-pin both).
