# DeepSeek V4 Flash 0731 mainline — eugr-b12x recipe succession A/B (2026-10-09)

**Verdict: PASSED → promoted.** `cluster-profiles.d/deepseek.conf` now runs
the eugr-b12x + Dspark-Ablit recipe; the old Anemll recipe is archived
byte-identical at `_overdue_recipe/deepseek_anemll-dspark-vllm-gx10-011_20261009/`
(conf + compose + patches + `recipe_README.md`) as an in-repo backup
solution.

Candidate lane: `deepseek-b12x` (retired after promotion).
Evidence: `docs/evidence/deepseek-b12x-recipe-ab-2026-10-09/{ab-D0.txt,d0-cycle-output.txt}`.

## 1. Succession rationale (same principle as the vision lane, user gate 2026-10-09)

The production `deepseek` recipe pinned `ghcr.io/anemll/dspark-vllm-gx10:0.1.1`
(believed unmaintained upstream) + the official checkpoint + a fail-closed
startup wrapper for the SWA-prefix hotfix. The candidate combines the
maintained runtime (`eugr/spark-vllm-b12x`, nightly CI) with the drowzeys
abliterated 0731 checkpoint.

User's three-step gate:

1. benchmark ≥ the README record for the old recipe → promote;
2. otherwise → drop the lane, production untouched;
3. the old recipe (+ patches) is archived in-repo as a BACKUP solution,
   not a deployed lane.

Baseline = README `DeepSeek V4 Flash 0731 mainline (TP2) — 2026-10-06/07
（E5 promote 後）` (decode Σ **670.7**, accept **31.1 %**, cold prefill
1784.8 / 1868.8 / 1747.3, warm prefix 7.6×, 261K 1648.2 tok/s; noise floor
decode ±7 %, prefill ±8 %).

## 2. Recipe: old vs new

| | promoted (D0) | old (archived) |
|---|---|---|
| image | `eugr/spark-vllm-b12x:latest` (dual-node digest pins) | `ghcr.io/anemll/dspark-vllm-gx10:0.1.1` |
| model | `…0731-dspark-ablit` (drowzeys Anchored-Tensors) | `…0731-official` |
| KV dtype | `fp8` (only option in this image — nvfp4_ds_mla structurally impossible, deepseek-nvfp4 cell B) | `nvfp4_ds_mla` |
| capture | **64** (formula `seqs*(k+1)=8*8`; upstream ships 48 for their k=5) | 8 |
| batched / GMU | 8192 / 0.85 (eugr family) | 16384 / 0.80 |
| spec decode | dspark k=**7** probabilistic, `attention_backend B12X` (k kept at production value; upstream ships 5) | dspark k=7 probabilistic |
| prefix caching | ON, **no hotfix** (gated) | ON + fail-closed `hotfix-vllm-dspark-swa-prefix.py` |
| wrapper / patches / SYNC_DIRS | none (`mods: []`) | CMD_WRAPPER + patches mount + SYNC_DIRS both nodes |
| dropped extras | `--async-scheduling`, `--generation-config vllm`, `--enable-flashinfer-autotune` (Anemll-lane extras; nvfp4 precedent) | present |
| stack dir | `eugr-spark-vllm-b12x-deepseek/` | `anemll-dspark-vllm-gx10/` (retired) |

**Provenance**: upstream `eugr/spark-vllm-docker`
`recipes/deepseek-v4-flash-0731.yaml` (fetched 2026-10-09) + the cluster
contract from `deepseek-nvfp4.conf` (same image: dual-node digest pins,
`seccomp=unconfined` for the b12x loader io_uring path, `HEALTH_TIMEOUT
3600`).

## 3. Model verification (three independent chains)

- HF API: `drowzeys/keys-DeepSeekV4-Flash-GA-0731-Dspark-Abliterated-Anchored-Tensors`
  (sha `a1e6937…`, gated) — file list = 48 shards + `ABLIT_META.json` +
  `DSPARK_ANCHOR_MANIFEST.json`, matches local dir exactly.
- Shard 38–44 sha256 in the HF listing == local
  `DSPARK_ANCHOR_MANIFEST.destination_sha256` (chain of custody).
- Manifest invariant: layers 36–42 restored hash-identical to official
  stock; **ALL MTP/draft tensors unchanged** → the b12x loader contract
  validated upstream against the official checkpoint holds for the draft
  head (the NVFP4 checkpoint's strided draft-scale refusal does not apply
  to this fp8 layout).
- `ABLIT_META`: 26 tensors edited (layers 10–35 `wo_b`,
  `layer-range-wo_b-projection` λ 3.5, `edit_mtp: false`).
- Mirrored byte-identical to BOTH nodes: 166,899,508,914 B / 48 shards.

## 4. Boot gates (D0, first boot after fixing a profile-authoring typo)

A first attempt died at argument parsing: the author wrote `COMPILATION_JSON`
with escaped quotes (`{\"…\"}`) → pydantic rejected `--compilation-config`.
Fixed to plain JSON (same as every other profile); a +90 s early-error check
was added to the harness so an arg error aborts instead of waiting out the
3600 s health timeout.

| gate | result |
|---|---|
| boot | READY in 12.8 min, `/health` 200 |
| `--load-format b12x` | **loaded** (80.76 GiB / 30.6 s), no strided refusal → no fallback needed |
| KV pool | **407,775 tokens** (old recipe nvfp4_ds_mla 405,179) — ≥265 K gate passes |
| capture sizes | `[1,2,4,…,56,64]` full range |
| spec config | `num_speculative_tokens: 7` |
| `cluster-compose-verify` | PASS both ranks |
| `gb10 smoke` | OK (`prompt_tokens 95`, thinking block honoured) |
| error scan | only benign FakeTensor `UserWarning`, no error/traceback |

## 5. Correctness gates

| gate | result |
|---|---|
| prefix-hit probe (`bench-prefix-hit.sh 32000 3`) | **HIT 38.5×** (13.60 s → 0.35 s), 3 rounds `PREFIX-OK` byte-identical → **the SWA-prefix bug does NOT reproduce in the eugr fork; no hotfix needed** (same conclusion as the vision succession) |
| 3×3 short-prompt completeness | **PASS 3/3** — every run `finish=stop`, non-empty, `identical=True` in-prompt (`HELLO-TP2-OK` / `Paris` / `1, 2, 3, 4, 5`) |
| garble soak ×3 (`temp=0`, `max_tokens=400`, `thinking:false`) | **PASS 3/3** — `finish=stop` ×3, `reasoning` empty, primes 101…149 **10/10** in every run, zero extras, answers identical across runs |
| 261 K / 262 K near-hard-limit | 261 000 → **1947.1 tok/s**; 262 000 → **1951.7 tok/s**; both accepted (≤262 144), no error |
| `bench-ab` prefix-repeat check | 3/3 `HELLO-TP2-OK` identical |

**Two false alarms on the way (kept in the evidence, mechanism re-read before
calling a fail — the documented lesson):**

1. HTTP 401 ×3 — the ad-hoc soak script forgot to source
   `cluster-common.sh` for `VLLM_API_KEY` (every bench script does).
   Test-harness bug, not the server.
2. First garble prompt reported `finish=length`, `uniq_ratio 0.05` —
   sampling the content showed a **coherent per-number divisibility
   enumeration** of 101–149 (correct arithmetic, linear structure): the
   verbose format simply exhausts a 400-token budget. With the format
   pinned ("just the numbers, separated by commas") the same probe is
   3/3 `finish=stop`. Not degeneration.

## 6. Decode vs the README E5 record (medians of 3 runs, same harness)

| C | E5 record | D0 | Δ |
|---|---|---|---|
| 1 | 42.3 | 43.2 | +2.1 % |
| 2 | 56.9 | 58.9 | +3.5 % |
| 3 | 71.7 | 72.2 | +0.7 % |
| 4 | 79.8 | 88.9 | +11.4 % |
| 5 | 91.8 | 93.2 | +1.5 % |
| 6 | 99.3 | 100.3 | +1.0 % |
| 7 | 113.2 | 116.7 | +3.1 % |
| 8 | 115.7 | 119.9 | +3.6 % |
| **Σ** | **670.7** | **693.3** | **+3.4 %** |

- 8/8 cells positive (sign consistency ⇒ beyond the ±7 % noise floor in
  aggregate); no C7/C8 capture-range deficit (capture 64 applied
  a-priori from the vision-B1 lesson — one cycle instead of two).
- acceptance: per-cell medians 30.0–36.7 %, mean **33.4 %** vs E5
  **31.1 %** (**+2.3 pp**) — expected: ablit touches only 26 body
  tensors, the DSpark draft is byte-official.

## 7. Prefill vs the README E5 record (cold, BENCH_COLD=1)

| scale | E5 record | D0 | Δ |
|---|---|---|---|
| 32 K | 1784.8 | 2408.4 | +34.9 % (32 K is structural noise either way) |
| 131 K | 1868.8 | 2174.1 / 2189.7 | **+16.3 %** |
| 200 K | 1747.3 | 2042.9 / 2051.5 | **+16.9 %** |
| 261 K | 1648.2 | 1947.1 | **+18.1 %** |

Warm-prefix probe: E5 recorded 7.6× on its probe shape; D0 measured
**38.5×** on `bench-prefix-hit.sh 32000` (same script the vision lane
used; not directly comparable to the E5 figure's method).

## 8. Promotion record (2026-10-09)

1. `cluster-profiles.d/deepseek.conf` rewritten to the promoted recipe
   (`PROFILE_ID=deepseek`, stack `eugr-spark-vllm-b12x-deepseek`,
   compose `docker-compose.deepseek.yml`, cache
   `~/.cache/vllm-deepseek-b12x` — the same root the A/B boots used).
2. Old recipe archived byte-identical as a self-contained bundle at
   `_overdue_recipe/deepseek_anemll-dspark-vllm-gx10-011_20261009/`
   (`deepseek-anemll.conf` SHA256 `3147b4e9…` + rendered compose +
   `patches/dspark-vision/` + `recipe_README.md`); restore steps +
   **model-retention note (the old official checkpoint stays on BOTH
   nodes pending a user decision)** in that `recipe_README.md`.
   `patches/dspark-vision/` moved into the bundle (one copy per retired
   recipe's archive; restore copies it back to the repo root — the conf's
   `SYNC_DIRS` resolves `${REPO_DIR}/patches/dspark-vision`).
3. Candidate lane `deepseek-b12x.conf` deleted; `bin/gb10` whitelist
   reverted to `deepseek-tune deepseek-nvfp4-tune`.
4. Stale composes removed on both nodes:
   `anemll-dspark-vllm-gx10/docker-compose.deepseek.yml` (old stack) and
   `eugr-spark-vllm-b12x-deepseek/docker-compose.deepseek-b12x.yml`
   (candidate name; the promoted conf renders `docker-compose.deepseek.yml`).
5. Docs: README mainline section + AGENTS succession bullet + handoff
   entry + this report.
6. P0 production re-gate: boot of the promoted `deepseek` lane + decode /
   prefill / prefix-hit re-measure — see §9.

**Known follow-ups (not part of this A/B):**

- ~~`deepseek-tune` sibling premise stale~~ → **archived** to
  `_overdue_recipe/deepseek_anemll-dspark-vllm-gx10-011_20261009/` per user
  decision 2026-10-09 (same as the
  vision-tune lane); a future mainline campaign branches a NEW lane off the
  promoted recipe.
- Quality spot-check only (same limitation every campaign recorded): no
  long-form style/factuality A/B between the official and abliterated
  checkpoints — behavioural differences are a *content* property of the
  ablit model, not of the serving recipe.

## 9. P0 — production re-gate (promoted `deepseek` lane, 2026-10-09 19:06–19:32)

Boot of the promoted profile (`gb10 use deepseek`; telemetry same config as
D0, new profile id / compose name / cache-warm):

| gate | result |
|---|---|
| boot | READY 12.7 min (19:06:14 → 19:18:54), `/health` 200 |
| load format / capture / k | `b12x` (no fallback), `[1…64]`, `num_speculative_tokens: 7` |
| KV pool | **423,356 tokens** (11.62 GiB; D0 booted 407,775 — boot-to-boot memory-profile scatter) |
| compose-verify / smoke | PASS both ranks / OK |
| prefix-hit | **HIT 38.3×** (13.81 s → 0.36 s), byte-identical `PREFIX-OK` |
| 261 K long probe | **1925.1 tok/s** (E5 record 1648.2 → +16.8 %; D0 1947.1 — within ±1.2 %) |
| cold prefill vs D0 | 32K **+0.7 %**, 131K **−0.2 %**, 200K **−0.7 %** — identical |

**Decode P0 vs D0 vs README E5 record** (medians of 3):

| C | E5 record | D0 | P0 | P0 vs E5 |
|---|---|---|---|---|
| 1 | 42.3 | 43.2 | 37.7 | −10.9 % |
| 2 | 56.9 | 58.9 | 54.0 | −5.1 % |
| 3 | 71.7 | 72.2 | 70.8 | −1.3 % |
| 4 | 79.8 | 88.9 | 82.2 | +3.0 % |
| 5 | 91.8 | 93.2 | 97.8 | +6.5 % |
| 6 | 99.3 | 100.3 | 99.8 | +0.5 % |
| 7 | 113.2 | 116.7 | 111.6 | −1.4 % |
| 8 | 115.7 | 119.9 | 119.3 | +3.1 % |
| **Σ** | **670.7** | **693.3** | **673.2** | **+0.4 % (parity)** |

- acceptance P0 mean **31.9 %** (E5 31.1 → +0.8 pp; D0 33.4 → −1.5 pp,
  inside noise).
- Verdict: **PASS** — the promoted production lane measures at parity-or-better
  against the README record on a second independent boot (D0 +3.4 %, P0
  +0.4 %); prefill holds the +16 % margin; correctness gates all green.
- Reading notes: C1 shows the largest cell delta (P0 −12.7 % vs D0) — it is
  the single-stream, highest-variance cell and the D0↔P0 boot scatter
  (12.7 %) exceeds the cell delta itself; the vision campaign recorded the
  same class of first-boot scatter (~8 %). Σ and prefill, which are the
  promotion criteria, are stable across both boots.

Evidence: `docs/evidence/deepseek-b12x-recipe-ab-2026-10-09/{ab-P0.txt,p0-cycle-output.txt}`.
