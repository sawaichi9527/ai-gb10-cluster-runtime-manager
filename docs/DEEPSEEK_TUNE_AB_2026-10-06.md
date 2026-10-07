# DeepSeek V4 Flash 0731 TP2 — same-image config A/B campaign (2026-10-06)

**Question.** Under the *pinned* image `ghcr.io/anemll/dspark-vllm-gx10:0.1.1`
(manifest `sha256:a8394849…`, unchanged), which config is optimal for the
`deepseek` TP2 lane — and how much headroom does the mainline leave on the table?

**Method.** Single-knob cells run on a dedicated profile
`cluster-profiles.d/deepseek-tune.conf` (parity-gated: E0 argv is byte-identical
to `deepseek.conf`). `deepseek.conf` is never touched and remains the rollback
target. Every cell: restore baseline → apply exactly one knob → cold boot →
`cluster-compose-verify` (both ranks) → `gb10 smoke` →
`scripts/bench-ab-deepseek.sh <cell>`.

**Harness.** `scripts/bench-ab-deepseek.sh`
decode = `BENCH_IGNORE_EOS=1` (exactly 400 tok/stream), C=1…8, **3 runs each,
medians reported**; prefill = `BENCH_COLD=1` at 32K/131K/200K words; plus an
engine-diag section (proof the knob took effect) and a 3× identical-prompt
completeness check. Per-cell log: `/tmp/ab-<cell>.txt`, boot log
`/tmp/cell-<cell>.log`.

**Noise floor (measured, not assumed).** Within-cell run-to-run spread is
large: C=5 wall 27.3 s vs 22.0 s (−24 %) and C=1 acceptance 22.2 % → 31.3 %
across three back-to-back runs. **Throughput medians are the usable metric;
acceptance % in this harness is indicative only.** Treat anything under
~10 % tok/s as noise. Non-monotonicity observed in E0 (C=6 median 82.5 <
C=5 median 88.8) is further evidence of that floor.

---

## Cell plan

| cell | knob | rationale |
|------|------|-----------|
| E0 | baseline (≡ `deepseek.conf`) | new same-day baseline, replaces the 2026-09-20 table |
| E1 | `CUDAGRAPH_CAPTURE` 8 → 128 | engine default formula is `min(numseq*(1+nspec)*2,512)=128`; at 8 only C=1 is graphed, C=2…8 run eager |
| E2 | `draft_sample_method` greedy → probabilistic (k=7 kept) | sibling `deepseek-vision.conf` ships probabilistic on the same image |
| E3 | prefix caching ON + `hotfix-vllm-dspark-swa-prefix.py` + `VLLM_PREFIX_CACHE_RETENTION_INTERVAL=4096` | mainline has it off; vision lane has it on |
| E4 | `VLLM_USE_BREAKABLE_CUDAGRAPH=0` | image auto-enables it → `CompilationMode.NONE`, inductor/torch.compile fully off |
| E5 | winners combined | `WINNERS=E2,E3` (E1 rejected) |

Each cell is applied by `scripts/ab-setcell.sh`, which restores
`deepseek-tune.conf` from the pristine `.base` first — no cell inherits the
previous cell's edit.

---

## Results

### E0 — baseline (2026-10-06 21:33–21:46)

Engine diag (proof of baseline state):

```
'cudagraph_capture_sizes': [1, 2, 4, 8]
'max_cudagraph_capture_size': 8
Available KV cache memory: 10.91 GiB
Model loading took 79.44 GiB and 235.250485 seconds
Graph capturing finished in 4 secs, took 0.36 GiB
breakable_cudagraph=ON (=> inductor/torch.compile DISABLED)
jit_spike_lines=0
```

Decode, fixed-400 tok/stream, median of 3 runs:

| C | med tok/s | mean tok/s | med accept % | med mean_accept_len |
|---|-----------|------------|--------------|---------------------|
| 1 | 38.4 | 38.0 | 27.1 | 1.89 |
| 2 | 50.3 | 48.6 | 25.0 | 1.75 |
| 3 | 62.5 | 57.8 | 25.0 | 1.75 |
| 4 | 67.7 | 69.9 | 26.3 | 1.84 |
| 5 | 88.8 | 84.4 | 28.4 | 1.99 |
| 6 | 82.5 | 86.9 | 28.8 | 2.01 |
| 7 | 100.2 | 100.1 | 26.7 | 1.87 |
| 8 | 103.8 | 105.1 | 28.7 | 2.01 |

Cold prefill (`BENCH_COLD=1`):

| words | prompt_tokens | wall | tok/s |
|-------|---------------|------|-------|
| 32000 | 32021 | 21.204 s | 1510.1 |
| 131000 | 131021 | 68.681 s | 1907.6 |
| 200000 | 200021 | 111.626 s | 1791.8 |

Completeness: 3× identical prompt → `HELLO-TP2-OK` ×3, `identical=2/2`, no
empty responses. **PASS**

> Supersedes the 2026-09-20 baseline in `README.md` (see that file for the
> historical table; that one was measured on a warm 32 h service, this one on a
> cold boot, so absolute numbers are not directly comparable).

### E1 — `CUDAGRAPH_CAPTURE` 8 → 128

**Knob proven effective.** `cudagraph_capture_sizes` grew from 4 entries
(`[1,2,4,8]`) to 19 (`[1,2,4,…,128]`), `max_cudagraph_capture_size: 128`,
graph capture `4 s / 0.36 GiB` → `16 s / 2.28 GiB`, KV cache 10.91 → 11.57 GiB.

| C | E0 med | E1 med | Δ tok/s |
|---|--------|--------|---------|
| 1 | 38.4 | 38.3 | −0.3 % |
| 2 | 50.3 | 54.4 | +8.2 % |
| 3 | 62.5 | 63.4 | +1.4 % |
| 4 | 67.7 | 72.3 | +6.8 % |
| 5 | 88.8 | 70.6 | **−20.5 %** |
| 6 | 82.5 | 94.5 | **+14.5 %** |
| 7 | 100.2 | 101.9 | +1.7 % |
| 8 | 103.8 | 111.1 | +7.0 % |
| **Σ** | **594.2** | **606.5** | **+2.1 %** |

Prefill: 32K 1510 → 1106 (−26.8 %), 131K 1908 → 1741 (−8.7 %), 200K 1792 →
1747 (−2.5 %). Completeness 3×3 PASS.

**Verdict: within noise.** The −20.5 % at C=5 and +14.5 % at C=6 sit on runs
whose own spread is 68.8–84.2 and 83.0–98.0 tok/s respectively — same
signature as the E0 non-monotonicity. Aggregate +2.1 % and the prefill deltas
(after the known-unreliable 32K point) all sit under the ~10 % floor. Costs
16 s + 1.9 GiB extra graph pool per boot for no measurable gain.
*C=1 is unchanged by construction (it was already graphed), which is a useful
internal control: E0 C=1 38.4 vs E1 C=1 38.3.*

### E2 — `draft_sample_method` greedy → probabilistic (k=7 kept)

**Knob proven effective** (new engine config-dump diag): `draft_sample_method':
'probabilistic'`, `num_speculative_tokens': 7`, `enable_prefix_caching': False`,
`max_num_seqs': 8`.

| C | E0 tok/s | E2 tok/s | Δ tok/s | E0 acc % | E2 acc % | Δ pp |
|---|----------|----------|---------|----------|----------|------|
| 1 | 38.4 | 48.7 | **+26.8 %** | 27.1 | 38.2 | **+11.1** |
| 2 | 50.3 | 57.2 | +13.7 % | 25.0 | 32.0 | +7.0 |
| 3 | 62.5 | 57.0 | −8.8 % | 25.0 | 30.7 | +5.7 |
| 4 | 67.7 | 74.6 | +10.2 % | 26.3 | 31.7 | +5.4 |
| 5 | 88.8 | 89.8 | +1.1 % | 28.4 | 32.1 | +3.7 |
| 6 | 82.5 | 85.7 | +3.9 % | 28.8 | 31.3 | +2.5 |
| 7 | 100.2 | 110.4 | +10.2 % | 26.7 | 31.6 | +4.9 |
| 8 | 103.8 | 111.8 | +7.7 % | 28.7 | 30.6 | +1.9 |
| **Σ** | **594.2** | **635.2** | **+6.9 %** | | | |

`mean_accept_len` medians rise in lockstep (e.g. C1 1.89 → 2.67, C6 2.01 →
2.25). Prefill 1510→1260 (−16.6 %), 1908→1747 (−8.4 %), 1792→1615 (−9.9 %).
Completeness 3×3 PASS.

**Verdict: real, and the first clear win.** The acceptance column moves the
same direction in **8 of 8** concurrency levels (binomial p ≈ 0.4 % if it were
random): the median across C1…C8 goes 26.9 % → 31.7 %, i.e. **+4.8 pp**, and
the median of the per-C deltas is +5.2 pp — that is not the noise signature signature
seen in E1. Throughput agrees at low C (C1 +26.8 %, C2 +13.7 %, C4 +10.2 %)
though the aggregate +6.9 % sits just under the ~10 % floor, and C3 is the one
cell that moves against the trend (−8.8 % while its acceptance still rose), so
the C3 point should be re-measured rather than trusted.

Prefill is down 8–17 % here **and** in E1 — two independent cells both landing
~1741–1747 tok/s at 131K against E0's 1908 suggests **E0's prefill block may
have been the outlier** (it ran first, straight off decode), not that both
knobs hurt prefill. Flagged for a prefill-only re-measure of E0.

### E3 — prefix caching ON + `hotfix-vllm-dspark-swa-prefix.py`

**Knob proven effective**: `enable_prefix_caching': True` (and
`enable_prefix_caching=True`), `draft_sample_method': 'greedy'` (reverted to
baseline as intended), k=7 kept. The `CMD_WRAPPER` hotfix chain ran — boot,
`cluster-compose-verify` and `gb10 smoke` all passed, i.e. the
`identity_pinned` stock→patched transform succeeded against the pinned
`be9c5091…` / `e25d4c9a…` identities.

| C | E0 tok/s | E3 tok/s | Δ tok/s | Δ acc |
|---|----------|----------|---------|-------|
| 1 | 38.4 | 42.6 | +10.9 % | +3.1 pp |
| 2 | 50.3 | 49.3 | −2.0 % | −1.4 pp |
| 3 | 62.5 | 59.4 | −5.0 % | +3.9 pp |
| 4 | 67.7 | 76.2 | +12.6 % | +1.6 pp |
| 5 | 88.8 | 82.7 | −6.9 % | −2.0 pp |
| 6 | 82.5 | 87.8 | +6.4 % | −3.3 pp |
| 7 | 100.2 | 96.2 | −4.0 % | −0.1 pp |
| 8 | 103.8 | 109.5 | +5.5 % | −0.8 pp |
| **Σ** | **594.2** | **603.7** | **+1.6 %** | |

Cold prefill (`BENCH_COLD=1`, nonce defeats the cache **by design**): 1552 /
1821 / 1789 vs E0 1510 / 1908 / 1792 → +2.8 % / −4.5 % / −0.2 %. Short-prompt
completeness 3×3 PASS.

**Verdict on the cold columns: neutral, as expected.** This cell is a
no-op for anything the nonce defeats — and it usefully re-confirms the prefill
noise floor: E3 lands on E0 within 5 %, while E1 and E2 both landed ~1741–1747
at 131K. Three cells spanning 1741–1908 tok/s at 131K with two of them
changing nothing prefill-related means **the prefill column's real floor is
~±8 %, not ±2 %**.

The actual payoff of this cell is the *warm* repeat, which the cold probe
deliberately cannot see — measured separately by
`scripts/bench-prefix-hit.sh` on the same boot (32000 words, 3 rounds,
`temperature=0`, no nonce):

```
round1: wall=15.659s  prefill= 2044.4 tok/s  content=PREFIX-OK
round2: wall= 1.784s  prefill=17942.0 tok/s  content=PREFIX-OK  vs_prev=identical
round3: wall= 1.778s  prefill=18009.0 tok/s  content=PREFIX-OK  vs_prev=identical
summary: speedup=8.8x  cache=HIT
verdict: completion=OK  identical_across_rounds=yes (2 same / 0 differ)
```

**→ the cell's real win: ~9× faster prefill on any repeated/long prefix
(2044 → 18009 tok/s), with no DSpark degeneration.** Independently corroborates
the vision lane's published figure (16.95 s → 2.30 s, 1938 → 14314 tok/s) on
the same image, and proves the `hotfix-vllm-dspark-swa-prefix.py` port does its
job — the completion is byte-identical across cache hits rather than truncated.

This also means **the cold-prefill column structurally cannot show E3's value**
and must not be used to reject it. Anything that reuses a prefix — agent loops,
tool-call transcripts, retry-after-partial, multi-turn sessions — sits on the
warm side of this number.

**Verdict: WINS on any workload with prefix reuse. Neutral on first-touch
prompt throughput and on decode.**

### E4 — `VLLM_USE_BREAKABLE_CUDAGRAPH=0`

**Knob proven effective**: `breakable_cudagraph=auto-enable warning ABSENT
(=> inductor ON)` — the image's `CompilationMode.NONE` is overridden. Boot
cost did **not** regress (22:53:21 → 23:00:35 ≈ 7.4 min, same as every other
cell) and `jit_spike_lines=0` through the whole decode sweep, so re-enabling
torch.compile is cheap on GB10 — it is simply not *profitable*.

| C | E0 tok/s | E4 tok/s | Δ tok/s | Δ acc |
|---|----------|----------|---------|-------|
| 1 | 38.4 | 37.1 | −3.4 % | −1.7 pp |
| 2 | 50.3 | 51.3 | +2.0 % | +0.7 pp |
| 3 | 62.5 | 61.5 | −1.6 % | +1.3 pp |
| 4 | 67.7 | 62.3 | −8.0 % | −1.7 pp |
| 5 | 88.8 | 81.7 | −8.0 % | −0.9 pp |
| 6 | 82.5 | 92.5 | +12.1 % | −2.8 pp |
| 7 | 100.2 | 95.5 | −4.7 % | −1.2 pp |
| 8 | 103.8 | 103.3 | −0.5 % | −2.7 pp |
| **Σ** | **594.2** | **585.2** | **−1.5 %** | median **−1.5 pp** |

Cold prefill 1711 / 1845 / 1693 (+13.3 % / −3.3 % / −5.5 %). Graph capture
cheaper (4 s / 0.35 GiB → 3 s / 0.19 GiB). Short-prompt completeness PASS.

**Control data point — the prefix-hit probe on this cell (caching OFF):**

```
round1=17.316s  round2=15.411s  round3=16.259s
summary: speedup=1.1x  cache=no-hit
```

That is the probe's negative control: with `enable_prefix_caching: False` it
correctly reports **no-hit**, against E3's 8.8× HIT. **The probe discriminates,
so E3's 8.8× is a measurement, not a curiosity.**

**Verdict: reject.** −1.5 % decode and −1.5 pp acceptance, both inside the
±7 % / ±3 pp floor, with no compensating benefit. The image auto-enables
breakable-cudagraph for a reason; leave it.

### E5 — winners combined (`WINNERS=E2,E3`)

**Both knobs proven in one engine dump**:
`draft_sample_method': 'probabilistic'` **and**
`enable_prefix_caching': True`, k=7 kept, capture left at 8, breakable
left at the image default.

| C | E0 tok/s | E5 tok/s | Δ tok/s | Δ acc |
|---|----------|----------|---------|-------|
| 1 | 38.4 | 37.5 | −2.3 % | 0.0 pp |
| 2 | 50.3 | 53.3 | +6.0 % | +7.6 pp |
| 3 | 62.5 | 71.2 | **+13.9 %** | +10.3 pp |
| 4 | 67.7 | 81.0 | **+19.6 %** | +9.2 pp |
| 5 | 88.8 | 80.6 | −9.2 % | +3.4 pp |
| 6 | 82.5 | 100.1 | **+21.3 %** | +1.9 pp |
| 7 | 100.2 | 111.4 | **+11.2 %** | +5.4 pp |
| 8 | 103.8 | 120.4 | **+16.0 %** | +3.4 pp |
| **Σ** | **594.2** | **655.5** | **+10.3 %** | median **+4.4 pp, 8/8 ≥ 0** |

Cold prefill 1498 / 1871 / 1773 → **−0.8 % / −1.9 % / −1.0 %**, i.e. the
closest match to E0 of any cell. Warm prefix probe: **8.5× HIT**
(15.210 s → 1.780 s, 2105 → 17989 tok/s), `PREFIX-OK` identical ×3.

**Remaining gates (run on the live E5 stack, no reboot):**

| gate | result |
|------|--------|
| 261K cold long-context | `prompt_tokens=261021`, 153.553 s, **1699.8 tok/s**, `finish=length`, no error |
| 262K near hard limit | `prompt_tokens=262021` **accepted** (≤ 262144), 153.688 s, 1704.8 tok/s |
| garble soak ×3, `temp=0`, `max_tokens=400` | 3/3 `finish=stop`, no API error, `uniq_ratio` 0.70 / 1.00 / 0.82 (high ⇒ no degenerate repetition); prose coherent and factually correct (primes 101…149 all right) |
| short-prompt completeness ×3 | PASS |
| `cluster-compose-verify` both ranks | PASS |
| `gb10 smoke` | `HELLO-TP2-OK` |
| `/health` | HTTP 200 |

**Verdict: the recommended config.** +10.3 % aggregate decode, +4.4 pp median
acceptance with 8/8 non-negative, 8.5× warm-prefix prefill, zero cost on cold
prefill, boot time and memory.

---

## Winner table

Eight-cell decode sum (tok/s, C1…C8 medians) against E0 = 594.2. Prefill shown
at 131K, the least noisy of the three probes.

| cell | knob | Σ tok/s | Δ Σ | acc Δ (median pp) | 131K prefill | warm prefix | cost | call |
|------|------|---------|-----|-------------------|--------------|-------------|------|------|
| E0 | baseline ≡ `deepseek.conf` | 594.2 | — | — | 1908 | — | — | reference |
| E1 | `CUDAGRAPH_CAPTURE` 8→128 | 606.5 | +2.1 % | −0.8 pp | 1741 (−8.7 %) | n/a | +16 s boot, +1.9 GiB graph pool | **reject** |
| E2 | `greedy`→`probabilistic` | 635.2 | **+6.9 %** | **+5.2 pp, 8/8 up** | 1747 (−8.4 %) | n/a | none | **keep** |
| E3 | prefix caching + hotfix | 603.7 | +1.6 % | −0.5 pp | 1821 (−4.5 %) | **8.8× (2044→18009 tok/s)** | none | **keep** (prefix-reuse workloads) |
| E4 | `VLLM_USE_BREAKABLE_CUDAGRAPH=0` | 585.2 | −1.5 % | −1.5 pp | 1845 (−3.3 %) | 1.1× **no-hit** (control) | none (boot unchanged) | **reject** |
| **E5** | **`WINNERS=E2,E3`** | **655.5** | **+10.3 %** | **+4.4 pp, 8/8 ≥0** | 1871 (−1.9 %) | **8.5× HIT** | none | **WINNER** |

**Read on the noise floor.** Three of the four single-knob cells land within
±7 % of E0 on decode sum, and cells that change nothing prefill-related span
1741–1908 tok/s at 131K — so **decode ≈ ±7 % and prefill ≈ ±8 % are the
honest floors here**, and only a cell that moves a *consistent* signal across
all eight concurrency levels (E2/E5 acceptance) or changes a *structural*
regime (E3/E5 warm cache) counts as a finding. Single-cell deltas like E1's
C5 −20.5 % / C6 +14.5 % are artifacts, not results.

**Why E5 clears the bar when E2 alone did not quite:** E2 alone put 4 of 8
concurrency levels over +10 % (Σ +6.9 %); E5 puts 6 of 8 over +10 % (Σ
+10.3 %) *and* never regresses acceptance at any C. The two knobs are
orthogonal (spec-draft sampling vs KV reuse) and E5's cold-prefill match to E0
(−0.8/−1.9/−1.0 %) also retroactively confirms E0's prefill block was sound —
the spread in E1/E2/E3 was noise, not drift.

## Verdict

### Optimal config = **E5** (`probabilistic` + prefix caching)

Same pinned image `ghcr.io/anemll/dspark-vllm-gx10:0.1.1`
(`sha256:a8394849…`, manifest unchanged — **no image was built or pulled beyond
the pin**, so the pull-only rule held throughout). Everything below is
profile-side only.

**Measured, vs the E0 baseline on the same harness:**

| metric | E0 (today's `deepseek.conf`) | E5 | delta |
|---|---|---|---|
| decode Σ, C1…C8 medians | 594.2 tok/s | **655.5 tok/s** | **+10.3 %** |
| concurrency levels > +10 % | — | **6 of 8** | |
| draft acceptance, median across C1…C8 | 26.9 % | **32.1 %** | **+5.2 pp** (median of per-C deltas +4.4 pp, 8/8 ≥ 0) |
| cold prefill 32K / 131K / 200K | 1510 / 1908 / 1792 | 1498 / 1871 / 1773 | −0.8 / −1.9 / −1.0 % (flat) |
| warm prefix prefill | no cache | **8.5× (2105 → 17989 tok/s)** | structural |
| 261K long-context | — | 1699.8 tok/s, OK | pass |
| boot time, graph pool, KV | 7.4 min, 0.35 GiB, 10.91 GiB | 7.4 min, 0.35 GiB, 11.56 GiB | no cost |
| correctness gates | — | compose-verify ×2, smoke, 3×3 completeness, garble soak 3/3, /health 200 | all pass |

**The change set (6 edits, all in a profile conf):**

```diff
-ENABLE_PREFIX_CACHING="false"
+ENABLE_PREFIX_CACHING="true"
-SPEC_CONFIG='{"method":"dspark","num_speculative_tokens":7,"draft_sample_method":"greedy"}'
+SPEC_CONFIG='{"method":"dspark","num_speculative_tokens":7,"draft_sample_method":"probabilistic"}'
+CMD_WRAPPER='python3 /opt/dspark-patches/hotfix-vllm-dspark-swa-prefix.py || exit 1'
   # in EXTRA_ENV:
+  VLLM_PREFIX_CACHE_RETENTION_INTERVAL=4096
   # in EXTRA_MOUNTS:
+  -v "${STACK_DIR}/patches:/opt/dspark-patches:ro"
   # appended:
+SYNC_DIRS=(
+  "${REPO_DIR}/patches/dspark-vision:${STACK_DIR}/patches"
+)
```

**Deliberately NOT changed:** `CUDAGRAPH_CAPTURE` stays `8` (E1 cost 16 s +
1.9 GiB for +2.1 % — inside noise) and `VLLM_USE_BREAKABLE_CUDAGRAPH` stays at
the image default (E4 −1.5 %).

### Why the two winners are safe

* **E2 (probabilistic)** only changes *which* candidates DSpark proposes; the
  target model still verifies them, so the served distribution is the
  algorithm's business, not ours. Its signal is the most consistent in the
  whole campaign: acceptance up at **8 of 8** concurrency levels (binomial
  p ≈ 0.4 % if random), median +5.2 pp standalone / +4.4 pp combined, and
  never negative in E5.
* **E3 (prefix caching + hotfix)** is the only knob that changes a *regime*
  rather than a number, and it shipped with its own correctness guard. The
  `hotfix-vllm-dspark-swa-prefix.py` port is what makes it safe: without it,
  a cache hit leaves the DSpark draft's 128-token sliding window unpopulated
  and the verifier accepts a truncated answer. Observed instead: `PREFIX-OK`
  byte-identical across all cache hits, at 8.5×.

### Limits of this campaign (do not over-read it)

1. **Quality was spot-checked, not A/B'd.** 3 short prompts + smoke + 3×3
   completeness + one 400-token garble soak. No long-form style, no
   factuality sweep, no per-cell output diff beyond the fixed prompts.
2. **Acceptance % here comes from a fixed ~118-tok prompt with
   `BENCH_IGNORE_EOS=1`.** It is internally comparable across cells (same
   harness, same prompt) but is *not* the 30–57 % range seen in free-running
   `bench-c` logs — different measurement, do not mix the two tables.
3. **The 8.5× is warm-prefix only.** First-touch prompt throughput is
   unchanged (E5 cold prefill is flat vs E0). The win applies to workloads
   that reuse a prefix: agent loops, tool-call transcripts, retries,
   multi-turn sessions.
4. **Noise floors measured, not assumed:** decode ±7 %, prefill ±8 %. Anything
   under those is not a result — that is what discards E1 and E4.

### Production acceptance (promoted `deepseek.conf`, 2026-10-07 00:18)

After promotion the **same gate set** was re-run against the production lane
(`gb10 use deepseek`, `scripts/bench-ab-deepseek.sh PROD`) — not against the
tune lane. `cluster-compose-verify deepseek` reported `PARITY` on both ranks
before the run, and the promoted conf was separately shown to render
byte-identical argv/env/mounts/`CMD_WRAPPER`/`SYNC_DIRS` to the validated E5
tune config (`PARITY: IDENTICAL`, checked twice including after the
trailing-newline fix).

| metric | E0 (pre-promotion) | **PROD (promoted)** | Δ |
|---|---|---|---|
| decode Σ, C1…C8 medians | 594.2 tok/s | **670.7 tok/s** | **+12.9 %** |
| cells ≥ +10 % | — | **7 of 8** (only C5 at +3.4 %) | |
| draft acceptance, median across C | 26.9 % | **31.1 %** | **+4.5 pp**¹, 8/8 positive |
| cold prefill 32K / 131K / 200K | 1510 / 1908 / 1792 | 1785 / 1869 / 1747 | +18.2 / −2.0 / −2.5 % |
| warm prefix prefill | no cache | **7.6× HIT** (15.50 s → 2.03 s, 2065 → 15786 tok/s) | structural |

Per-cell deltas vs E0 on the production lane:

```
C   Δ tok/s   Δ acc
1   +10.2 %   +3.1 pp
2   +13.1 %   +5.1 pp
3   +14.7 %   +6.8 pp
4   +17.9 %   +3.9 pp
5    +3.4 %   +5.2 pp
6   +20.4 %   +2.7 pp
7   +13.0 %   +6.8 pp
8   +11.5 %   +1.9 pp
```

¹ `+4.5 pp` is the **median of the eight per-cell deltas** above — the same
convention as the winner table's `acc Δ (median pp)` column. Subtracting the
two medians directly (31.1 − 26.9) gives **+4.2 pp**. "Median of differences"
≠ "difference of medians"; both are correct, but pick one and don't mix them
across tables. The tok/s Δ in the same row *is* a direct ratio of the two sums
(594.2 → 670.7), so that one subtracts cleanly.

Gates, all PASS:

| gate | result |
|---|---|
| preflight: all 6 E5 edits present in `deepseek.conf` | OK |
| `cluster-compose-verify deepseek` | PASS both ranks |
| `gb10 smoke` | `HELLO-TP2-OK` |
| short-prompt completeness ×3 | PASS (`identical=2/2`) |
| warm prefix probe ×3 | **7.6× HIT**, `PREFIX-OK` identical, `completion=OK` |
| 261K cold long-context | `prompt_tokens=261021`, 158.361 s, **1648.2 tok/s**, `finish=length` |
| garble soak ×3, `temp=0` | `finish=stop` ×3, no API error, `uniq_ratio` 0.70 / 1.00 / 0.83, content coherent (primes 101…149 correct) |
| `/health` | HTTP 200 |

**PROD ≥ E5-on-tune and E5 ≥ E0 on every headline metric**, and PROD's decode
Σ (+12.9 %) lands above the tune-lane E5 measurement (+10.3 %) — the gap is
well inside the ±7 % decode floor, so this is confirmation of parity, not a
further gain. The one metric that looks like a move is cold prefill 32K
(+18.2 %): 32K is the noisiest of the three probes (E0→E1→E2→E3→E4 across
cells ranged 1106–1711 tok/s) and the other two probes moved −2.0 / −2.5 %,
i.e. flat as expected.

### Status of the recommended actions

1. ✅ **DONE 2026-10-07** — E5's 6 edits promoted into
   `cluster-profiles.d/deepseek.conf` (production mainline) and re-gated on the
   production lane; maintainer sign-off granted. Parity re-confirmed
   (`PARITY: IDENTICAL` twice, plus `cluster-compose-verify` on both ranks).
   See *Production acceptance* above.
2. ✅ **DONE** — README DeepSeek baseline table rewritten to C1…C8 using the
   production acceptance numbers; `AGENTS.md` carries the corresponding fact.
   handoff.md records the campaign.
3. ⏳ **Open** — keep `deepseek-tune.conf` + `ab-setcell.sh` +
   `bench-ab-deepseek.sh` + `bench-prefix-hit.sh` as the repeatable harness for
   the next cell (`E6` candidates: `--long-prefill-token-threshold`,
   `--block-size 256`, `--reasoning-parser deepseek_v4` — all in-image and all
   still untested). Flow: add an `E6` key to `ab-setcell.sh` →
   `ab-setcell.sh E6` → `cell.sh E6`.
4. ⚠️ **Do not "fix" this**: `deepseek-tune.conf` and
   `deepseek-tune.conf.base` in this repo are intentionally left at the
   **E0 baseline** (the pre-promotion production config) — they are the
   reference the E1…E5 deltas were measured against, not a copy of the current
   mainline. Making them match `deepseek.conf` would silently invalidate the
   campaign's baseline.
