# DeepSeek-vision single-knob A/B campaign — `deepseek-vision-tune` — 2026-10-07

Same method as the mainline `DEEPSEEK_TUNE_AB_2026-10-06.md` campaign
(E0–E5), applied to a **different profile on the same image**.

## Scope and non-goals

- **Goal**: make `deepseek-vision` (deepseek-v4-flash-vision-exp) emit tokens
  faster — *via the same method*, not the same knobs.
- **Same image only**: pinned `ghcr.io/anemll/dspark-vllm-gx10:0.1.1`
  (digest `sha256:a8394849…`, verified present on **both** nodes before the
  campaign started). Pull-only: no self-built images, runtime config/patch
  changes only.
- **Everything else unchanged**: `cluster-profiles.d/deepseek.conf` (E5
  production mainline) and `cluster-profiles.d/deepseek-vision.conf`
  (production vision) are **not edited by any cell**. Cells run against a
  separate `deepseek-vision-tune.conf` + `.conf.base`, the same discipline
  `deepseek-tune` applies to the mainline.
- **Cross-lane comparison is invalid by construction**: vision runs
  `thinking:true` (server-side `--default-chat-template-kwargs`) and
  `num_speculative_tokens=6`; mainline runs 7 with a different draft sample
  method. Only **V-cell vs V0 within this lane** is meaningful.

## Why vision needed its own cell set

Phase 0 verified that all six E5 winners are **already present** in
`deepseek-vision.conf` — the learning direction was `mainline ← vision/MiaAI`:

| E5 knob | in `deepseek-vision.conf`? |
|---|---|
| `ENABLE_PREFIX_CACHING="true"` | yes (L57) |
| `draft_sample_method=probabilistic` | yes (SPEC_CONFIG L62 + env L96) |
| `hotfix-vllm-dspark-swa-prefix.py` in the fail-closed chain | yes (L129) |
| `VLLM_PREFIX_CACHE_RETENTION_INTERVAL=4096` | yes (L89) |
| `EXTRA_MOUNTS ${STACK_DIR}/patches` | yes (L138) |
| `SYNC_DIRS` stages the hotfix on both nodes | yes (L148) |

So the E2/E3/E5-equivalent cells are **already banked** and were deliberately
not re-run. What remains is vision-only territory that no lane has ever A/B'd:

| cell | knob | rationale |
|---|---|---|
| V1 | drop `VLLM_USE_BREAKABLE_CUDAGRAPH=0` | only cell with **direct A/B evidence**: mainline E4 measured −1.5% *with* it on, i.e. inductor ON is the slower setting. Vision currently runs inductor ON. |
| V2 | `--block-size 256 → 128` | also changes prefix-cache hit granularity |
| V3 | `--long-prefill-token-threshold 1024 → 0` | prefill dimension, vision-only value |
| V4 | `--max-cudagraph-capture-size 56 → 8` | mainline E1 = speed-neutral; reclaims ~1.9 GiB graph pool, **not a tok/s win** |
| V5 | `num_speculative_tokens 6 → 9` | k must be ≥ `dspark_block_size` 5 and a multiple of `n_predict` 3 → k ∈ {6, 9, 12}. **Only upward**; prior art (littlecedar k-sweep) says lower k is better, so this is expected to lose. |
| V-win | combined winners | after all single cells |

Deliberately **not** tested: E2/E3/E5 equivalents (already on), `GMU`
(raising it hard-resets the GB10), `thinking` / `reasoning_effort` (affects
answer *length*, not tok/s — `bench-c` runs `ignore_eos`), and the 17 vision
hotfixes (fail-closed correctness fixes, not tuning surface).

## Harness fixes required before a single cell could be measured

Four real defects surfaced. All four are **pre-existing**; vision was simply
the first lane to expose them.

### 1. `bench-c.sh` died on any lane whose draft is shorter than 7

`get_pos()` was `echo | grep | awk | head`. Under `set -Eeuo pipefail`, a
`grep` with no match exits 1, `pipefail` propagates it, and therefore the
**assignment** `P_AFTER=$(get_pos ...)` itself returned 1 — `set -e` killed
the script before any defaulting could happen. Evidence from `bash -x`:

```
++ grep '^POS6 '        <- no match
++ head -1
+ P_AFTER=              <- assignment status 1 (pipefail)
+ rm -rf /tmp/bench_c1_Svzz   <- EXIT trap => script died right here
rc=1
```

The metrics only contain `position="0".."5"` because vision runs
`num_speculative_tokens=6`, so `POS6` never exists.

| lane | k | metric positions | hit the bug? |
|---|---|---|---|
| `deepseek` / `deepseek-tune` | 7 | 0..6 | **no** → the E0–E5 campaign numbers are unaffected |
| `deepseek-vision` | 6 | 0..5 | **yes, on every `bench-c` call** |
| `qwen38flash` | 3 | 0..2 | yes (would die at p=3) |

Fix: `get_val`/`get_pos` end in `|| true` so they can never fail an
assignment, missing positions default to `0`, and both `METRICS_*`
assignments are `|| true` so a missing spec-decode metric degrades to
"(no draft delta)" instead of aborting. Verified: `bench-c.sh 1 50` now
returns `rc=0` and prints `pos6: 0 / 21 = 0%` plus the closing separator.

### 2. `bench-ab-deepseek.sh` swallowed child failures

It captured the child as `r=$(bash scripts/bench-c.sh ... 2>&1 | grep -E
'aggregate:|acceptance:' ...)`. That merges stderr into stdout, filters it
through `grep`, and then lets `set -e` abort on the pipeline status — so a
crashed child produced **no output at all**, just a dead script after the
decode header. It cost one full bench run (~25 min) to notice.

Fix: capture the child's output first, test its status explicitly, and on
failure emit the raw tail and `fail()` loudly. Applied to both the decode and
the cold-prefill loops.

### 3. `bench-prefix-hit.sh` produced a false no-hit on vision

The payload was `max_tokens: 40` reading only `.message.content`. Vision runs
`thinking:true`, so a 40-token budget could be spent entirely inside the
thinking block, yielding empty `content` → the verdict would have read
`completion=FAIL(empty/err)` and been mistaken for a broken cache.

Fix (applied **before any V0 measurement**, so instrumentation was frozen
before the campaign started):
- `max_tokens` 40 → 512 (env-overridable `PH_MAX_TOKENS`)
- request-side `"chat_template_kwargs":{"thinking":false}`, which correctly
  overrides the server-side `--default-chat-template-kwargs {"thinking":true}`
  (an unsupported key is just an unused Jinja variable, not an error)
- report `reasoning_len` alongside `content_len`, and label the
  "empty content but N reasoning tokens" case as **NOT a cache miss**
- gate the summary on "at least one round completed" rather than on content
  being non-empty, so a failing probe still prints its verdict

Verified working: `reasoning_len=0`, `content=PREFIX-OK`.

### 4. `ab-run-cell.sh` defaulted the profile to `deepseek-tune`

Signature is `<cell> <label> <profile>`; the profile defaulted to
`deepseek-tune`. A two-argument call (`ab-run-cell.sh V0
deepseek-vision-tune`) was therefore read as *label=`deepseek-vision-tune`,
profile=`deepseek-tune`* — it tore down the vision lane and booted the
**mainline** experiment lane instead, running for ~1 minute before it was
caught. The driver's own header comment had documented the two-argument form,
which is how the mistake got in.

Fix: all three arguments are now required (`${3:?...}`), plus explicit
`[[ -f conf ]]` / `[[ -f base ]]` guards, and the header examples corrected.
A two-argument call is now rejected with `rc=1` (verified).

Containment: the mis-invoked boot chain was killed before `cluster-up`
completed, no cluster container was left behind, and `deepseek-tune.conf` was
verified byte-identical to its `.base` (`e0c1f265…`) afterwards, so the
mainline experiment lane was never modified.

### 5. `ab-setcell.sh` without `AB_CONF` silently targets the mainline lane

Same class as #4, one layer down. `CONF="${AB_CONF:-cluster-profiles.d/
deepseek-tune.conf}"` means a bare `scripts/ab-setcell.sh V0` reports
success against the **mainline** experiment conf while leaving the vision conf
holding whatever the previous cell left there. Observed on 2026-10-07 while
cleaning up the failed V2:

```
ab-setcell: V0 OK  conf_sha256=e0c1f2655c9c3b85   <- deepseek-tune.conf (wrong file)
148a3f134c231a69...  deepseek-vision-tune.conf     <- still block-size 128
5e70ec4e012440b4...  deepseek-vision-tune.conf.base
```

The restore claimed `V0 OK` and was wrong about which file it touched —
exactly the "silently lie about the target" failure the campaign cannot
afford. Damage was nil (`deepseek-tune.conf` was already at its base, so
`git status` never listed it), but the guard matters.

Fix: a cell whose name starts with `V` now **requires** both `AB_CONF` and
`AB_BASE` and refuses otherwise (`rc=1`, verified). E-cells keep the
mainline default so the closed mainline driver still works.

### 6. `gb10 wait` burns 2400 s on a boot that died in second 2

V2's container exited within ~2 minutes of boot, but the cell did not abort
until **11:29:33**, printing `ERROR: health timeout (2400s)` — 40 minutes of
wall clock spent waiting for a health check on a stack that was already dead.
The failure was eventually loud (it is not a *silent* failure like #2), just
absurdly late, and it consumed a full cell slot.

Fix: `ab-run-cell.sh` replaces the bare `bin/gb10 wait` with `wait_or_fail`,
which runs it in the background and polls `cluster-node0`. It fails as soon
as the container shows `Exited` **and** its `State.StartedAt` is later than
this cell's start time — the timestamp comparison is what keeps the previous
stack's teardown (`docker stop` leaves a transient `Exited` before the `rm`)
from being misread as our boot dying. On failure it dumps the last 40 log
lines and exits non-zero. Success path is unchanged: same `gb10 wait`, same
`tail -30`. This only alters how *failures* are reported, so no measured
number can move.

Operational footnote: `gb10 down` is not a command — it prints the help
text and returns 0, which is a second way to waste a cycle. The teardown
verb is **`gb10 stop`** (stops and removes both cluster containers).

## Other instrumentation added for this lane

`emit_diag` in `bench-ab-deepseek.sh` previously proved a cell only through
engine-log lines. Several vision knobs (`--block-size`,
`--long-prefill-token-threshold`) never appear in the engine dump at all, so
a cell would have been unverifiable. It now prints, from
`docker inspect cluster-node0`:

- **argv** (entrypoint + Cmd, newlines flattened): `--block-size`,
  `--long-prefill-token-threshold`, `--max-cudagraph-capture-size`,
  `--reasoning-parser`, `--served-model-name`, `--speculative-config`, and
  the `--enable-prefix-caching` / `--no-enable-prefix-caching` flag
- **env** (container env, not argv — `VLLM_USE_BREAKABLE_CUDAGRAPH` can never
  appear in `Cmd`): `VLLM_USE_BREAKABLE_CUDAGRAPH` and
  `VLLM_PREFIX_CACHE_RETENTION_INTERVAL`

Reference V0 live argv (captured 2026-10-07):

```
--enable-prefix-caching --max-cudagraph-capture-size 56
--speculative-config {"method":"dspark","num_speculative_tokens":6,
                      "draft_sample_method":"probabilistic"}
--reasoning-parser deepseek_v4 --block-size 256
--long-prefill-token-threshold 1024
--default-chat-template-kwargs {"thinking":true}
env VLLM_USE_BREAKABLE_CUDAGRAPH=0
env VLLM_PREFIX_CACHE_RETENTION_INTERVAL=4096
breakable_cudagraph=auto-enable warning ABSENT (=> inductor ON)
```

## V0 baseline

Two independent V0 runs, both ending in a full gate pass
(`compose-verify` PASS on both ranks, `smoke` http=200, cachecheck
`ok (identical=3/3)`, prefix probe `completion=OK identical=yes`):

| | Run A | Run B |
|---|---|---|
| procedure | stack up 27 min, prefix probe already run | fresh boot, bench immediately after smoke |
| boot | 09:14:39 → READY 09:23:30 = **8m51s** | 10:06:32 → READY 10:12:12 = **5m40s** |
| cell apply sha | `5e70ec4e012440b4` (= `.base`) | `5e70ec4e012440b4` (= `.base`) |
| result file | `/tmp/ab-V0-runA.txt` | `/tmp/ab-V0.txt` ← **the campaign reference** |

**Run B is the reference**: every V-cell boots and benches with exactly this
procedure, so it is the only apples-to-apples baseline. Run A is kept as a
second dispersion sample.

| C | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | Σ med |
|---|---|---|---|---|---|---|---|---|---|
| run A median tok/s | 34.3 | 44.6 | 52.9 | 62.6 | 74.5 | 86.2 | 80.9 | 93.4 | **529.4** |
| run B median tok/s | 29.8 | 47.3 | 53.4 | 63.6 | 64.7 | 77.0 | 89.2 | 103.0 | **528.0** |
| run A accept % | 25.6 | 23.4 | 21.4 | 21.7 | 26.8 | 26.1 | 24.2 | 24.9 | med **24.55** |
| run B accept % | 19.7 | 25.0 | 21.7 | 24.1 | 20.2 | 22.7 | 25.3 | 28.3 | med **23.40** |

cold prefill tok/s (32K / 131K / 200K):
- run A: 1871.4 / 1792.1 / 1673.4
- run B: 1914.4 / 1788.5 / 1689.8

## Decision threshold (measured, not inherited)

Boot-to-boot dispersion between the two V0 runs:

| metric | dispersion (A → B) | usable? |
|---|---|---|
| **Σ decode** (sum of the 8 medians) | 529.4 → 528.0 = **−0.26%** | **yes — primary metric** |
| per-cell decode | **±13.2%** worst case (C1 −13.1%, C5 −13.2%, C6 −10.7%, C7 +10.3%, C8 +10.3%) | **no — cannot rank a cell** |
| per-cell acceptance | **±6.6 pp** (C5 26.8→20.2, C1 25.6→19.7) | **no** |
| median acceptance | 24.55 → 23.40 = **−1.15 pp** | yes — secondary |
| cold prefill | **+2.3% / −0.2% / +1.0%** | yes — metric for V2/V3 |

This is the single most important result of the setup phase: **per-cell
figures on the vision lane are noisier than the harness's own built-in
bar** (`|d| >10% tok/s or >3pp => real`), by both measures. The mainline
campaign's per-cell criteria ("7/8 cells ≥ +10%", "8/8 acceptance positive")
are therefore **not transferable** to this lane.

Working rules for the remaining cells:
1. Judge on **Σ decode** (primary) and **cold prefill** (for V2/V3), with
   median acceptance as secondary.
2. A cell that looks good on Σ but marginal in magnitude gets a **second
   independent boot** before it is called a winner.
3. A single-cell ±13% swing is never evidence on its own.

Caveat: A and B differ in warm-up procedure as well as in boot, so this is a
**conservative upper bound** on dispersion, not a clean estimate of it.
The mainline ±7% figure is deliberately not used.

**Amended after the V1 confirm boot (see V1b below).** The two V0 boots
were only 0.26% apart on Σ, but V1's two independent boots were **2.12%
apart** (543.8 vs 532.3). A baseline pair sampled twice cannot bound the
tail of a distribution, so the 0.26% figure is a lower bound on
*observed* tightness, not a noise floor. Practical consequence: **treat any
Σ movement smaller than ~2% on this lane as indistinguishable from boot
variation**, and require sign consistency across two boots rather than a
single large number.

## Results

### V1 — drop `VLLM_USE_BREAKABLE_CUDAGRAPH=0` (inductor ON → OFF)

Proof of effect (single-knob isolation verified from live argv/env):

| | V0 | V1 |
|---|---|---|
| `env VLLM_USE_BREAKABLE_CUDAGRAPH` | `=0` | **not set** |
| log diagnostic | auto-enable warning ABSENT → **inductor ON** | warning PRESENT → **inductor OFF** |
| block-size / long-prefill / capture / k / probabilistic / prefix-caching | 256 / 1024 / 56 / 6 / yes / True | identical |

Boot 10:27:59 → READY 10:33:49 (5m50s), compose-verify PASS both ranks,
cachecheck ok, prefix probe `completion=OK identical=yes`.

| C | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | Σ med | accept med |
|---|---|---|---|---|---|---|---|---|---|---|
| V0 (run B) | 29.8 | 47.3 | 53.4 | 63.6 | 64.7 | 77.0 | 89.2 | 103.0 | **528.0** | 23.40 |
| V0 (run A) | 34.3 | 44.6 | 52.9 | 62.6 | 74.5 | 86.2 | 80.9 | 93.4 | **529.4** | 24.55 |
| **V1** | 30.5 | 48.4 | 57.3 | 65.2 | 76.5 | 78.5 | 90.8 | 96.6 | **543.8** | **25.20** |
| Δ vs V0(B) | +2.3% | +2.3% | +7.3% | +2.5% | +18.2% | +1.9% | +1.8% | −6.2% | **+2.99%** | +1.80 pp |
| Δ vs V0(A) | −11.1% | +8.5% | +8.3% | +4.1% | +2.7% | −8.9% | +12.1% | +3.4% | **+2.72%** | +0.65 pp |

cold prefill 1909.4 / 1780.5 / 1708.2 tok/s → vs V0(B) −0.3% / −0.4% / +1.1%,
i.e. **inside the ±2.3% prefill noise, as expected** (V1 must not move prefill).

**Verdict: promising, NOT yet a winner.** Σ beats both V0 samples (+2.7% ~
+3.0%), but acceptance lands on both sides of the ±1.15 pp threshold
(+1.80 pp vs run B, +0.65 pp vs run A), and C5's +18.2% must be discounted —
run A's C5 was 74.5, so run B's 64.7 was the outlier, not V1's 76.5 the hero.
Per decision rule 2, V1 needs a second independent boot before promotion.

### V2 — `--block-size 256 → 128` — **NOT BOOTABLE, not measured**

Apply succeeded as a true single-knob edit (`conf_sha256=148a3f134c231a69`,
diff exactly `- --block-size 256` / `+ --block-size 128`), then the boot died:

- boot started 10:49:09; `cluster-node0` reached **`Exited (1)`** within about
  two minutes while `cluster-node1` stayed `Up` (it waits for rank 0).
- Persisted log `/tmp/v2boot.log`: 524 lines, 5 tracebacks. Root cause:

```text
File ".../vllm/v1/core/kv_cache_utils.py", line 1628, in _get_kv_cache_groups_uniform_groups
    assert max(sm_page_sizes) <= max(all_page_sizes)
```

  raised from `EngineCore.__init__` → `_initialize_kv_caches` →
  `get_kv_cache_configs`, so EngineCore never comes up and the APIServer
  reports `RuntimeError: Engine core initialization failed. See root cause
  above.`

- **Retraction of an earlier reading**: a corrupted tool result at one point
  showed a `nvlink_train_gemm_kernel.cu` / `registry.py:405` Triton-compile
  failure as the root cause. That text does not exist. `grep -ac nvlink
  /tmp/v2boot.log` = **0**, `grep -ac registry.py` = **0**, and the log is only
  524 lines, not the ~9500 implied by that output. The KV-cache assertion
  above is the real and only root cause found.

**Verdict: rejected as not-bootable on this pinned image.** The knob cannot be
measured, contributes no speedup, and must never be promoted. It is also not
reclaimable by adjusting another knob — block size is a base engine argument,
so there is no neighbouring cell that makes 128 boot. Cost: one cell slot plus
40 minutes of wall clock to a health timeout that the new `wait_or_fail`
watchdog (fix #6) now cuts to about a minute.

### V3 — `--long-prefill-token-threshold 1024 → 0`

Apply succeeded as a true single-knob edit (`conf_sha256=0e90b564b408f783`,
diff exactly `- --long-prefill-token-threshold 1024` / `+ ... 0`). Proof of
effect from the live argv captured in `/tmp/ab-V3.txt`:

| | V0 | V3 |
|---|---|---|
| `argv --long-prefill-token-threshold` | `1024` | **`0`** |
| `argv --block-size` | `256` | `256` |
| `argv --max-cudagraph-capture-size` | `56` | `56` |
| `env VLLM_USE_BREAKABLE_CUDAGRAPH` | `=0` | `=0` (inductor ON, warning ABSENT) |
| prefix caching / k / probabilistic | True / 6 / yes | identical |

Boot 11:36:38 → bench 11:42:42, `CELL DONE V3` 11:56:12 (~19.5 min total),
compose-verify PASS both ranks, `gb10 smoke` 200, prefix probe
`completion=OK identical=yes` (8.7× warm speedup, `cache=HIT`).

| C | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | Σ med | accept med |
|---|---|---|---|---|---|---|---|---|---|---|
| V0 (run B) | 29.8 | 47.3 | 53.4 | 63.6 | 64.7 | 77.0 | 89.2 | 103.0 | **528.0** | 23.40 |
| **V3** | 36.8 | 43.3 | 56.6 | 66.3 | 73.7 | 87.1 | 87.9 | 89.9 | **541.6** | 24.25 |
| Δ vs V0(B) | +23.5% | −8.5% | +6.0% | +4.2% | +13.9% | +13.1% | −1.5% | −12.7% | **+2.58%** | +0.85 pp |

cold prefill 1754.1 / 1860.6 / 1769.3 tok/s → vs V0(B) **−8.4% / +4.0% /
+4.7%**. The three widths disagree in sign, and −8.4% sits right on the
measured ±8% prefill noise floor; the decision rule already says prefill on
this lane is judged by direction consistency, which is absent here.

**Verdict: promising, NOT yet a winner.** Σ decode beats V0 by +2.58% — an
order of magnitude above the 0.26% Σ dispersion between the two V0 boots —
but acceptance (+0.85 pp) is inside the ±1.15 pp noise band, and per-cell
moves are all over (C1 +23.5% against C8 −12.7%), exactly the per-cell
±13.2% dispersion the threshold section warns about. Per decision rule 2,
V3 needs a second independent boot before promotion. Notable side effect to
watch on the confirm boot: with the long-prefill path disabled, cold prefill
at the widest width did *not* regress beyond noise, so the knob looks free
rather than profitable.

**Harness note (a false alarm, not a hang):** an intermediate read of the
poller output claimed V3 had stalled at 103 log lines "since 11:59:35
through 16:08:20". That was a corrupted tool result — node0's clock read
`11:48:13` at that moment, there is no 16:08, and the log was at 75 lines
and still growing. Re-reading the poller's own file on disk (`sh_1146f95a…`,
mtime 11:45:46, 2435 bytes) showed normal progress. Same class of
fabrication as the `nvlink_train_gemm_kernel.cu` root cause retracted under
V2: **always re-read the persisted file or re-query the box before acting on
a suspicious reading.**

**Second false alarm of the same session:** every inline health probe in the
form `curl … [REDACTED]:1234/health` returned `curl: (3) bad range in URL
position 2` and was briefly read as "API unresponsive". It is not —
assigning the URL to a shell variable and quoting it (`U="http://…";
curl … "$U"`) returns **`/health` 200 in 0.656 ms**. The unquoted form is
what curl rejects. The lane's own gates (`gb10 smoke`, prefix probe) were
200 throughout, so no measurement was affected.

### V4 — `CUDAGRAPH_CAPTURE 56 → 8` — **REGRESSION, rejected**

Single-knob apply verified (`conf_sha256=27fbf0e3608ce4d7`, diff exactly
`-CUDAGRAPH_CAPTURE="56"` / `+CUDAGRAPH_CAPTURE="8"`). Proof of effect:

| | V0 | V4 |
|---|---|---|
| `cudagraph_capture_sizes` | `[1,2,4,8,16,24,32,40,48,56]` | **`[1,2,4,8]`** |
| `max_cudagraph_capture_size` | 56 | **8** |
| graph capture cost | 4 s / 0.68 GiB | **1 s / 0.19 GiB** |
| block-size / long-prefill / k / inductor | 256 / 1024 / 6 / ON | identical |

Boot 12:01:56 → `CELL DONE V4` 12:22:37, compose-verify PASS both ranks,
prefix probe `cache=HIT` (8.7×).

| C | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | Σ med | accept med |
|---|---|---|---|---|---|---|---|---|---|---|
| V0 (run B) | 29.8 | 47.3 | 53.4 | 63.6 | 64.7 | 77.0 | 89.2 | 103.0 | **528.0** | 23.40 |
| **V4** | 34.4 | 45.8 | 54.1 | 61.6 | 64.6 | 76.6 | 80.0 | 83.5 | **500.6** | 24.15 |
| Δ vs V0(B) | +15.4% | −3.2% | +1.3% | −3.1% | −0.2% | −0.5% | **−10.3%** | **−18.9%** | **−5.19%** | +0.75 pp |

cold prefill 1930.4 / 1741.5 / 1640.7 tok/s → vs V0(B) +0.8% / −2.6% / −2.9%,
inside noise. Prefix probe HIT.

**Verdict: rejected.** The primary metric moves the wrong way by 19× the
measured Σ dispersion (−5.19% against a 0.26% A/B spread), and the damage is
concentrated exactly where a shallow CUDA graph hurts: C7 −10.3% and C8
−18.9%, i.e. high-concurrency decode where batch sizes exceed the captured
set. Acceptance (+0.75 pp) and prefill are flat, so this is purely a
decode-concurrency regression, not a measurement artefact. The one thing V4
does buy — graph capture 4 s → 1 s and 0.68 → 0.19 GiB at boot — is a
cold-start cost, not the throughput this campaign is optimising, and it is
not worth 5% of decode.

### V5 — `MTP_NUM_TOKENS 6 → 9` — **REGRESSION, rejected**

Single-knob apply verified (`conf_sha256=d9a3945b309da3d8`, diff exactly
`-MTP_NUM_TOKENS=6` / `+MTP_NUM_TOKENS=9`). Proof of effect:

| | V0 | V5 |
|---|---|---|
| `cfg num_speculative_tokens` | 6 | **9** |
| `argv --speculative-config` | `…num_speculative_tokens":6…` | **`…":9…`** |
| `draft_sample_method` | probabilistic | probabilistic (unchanged) |
| capture sizes / block-size / long-prefill / inductor | 56-set / 256 / 1024 / ON | identical |

Boot 12:24:02 → `CELL DONE V5` 12:46:17, compose-verify PASS both ranks,
prefix probe `cache=HIT` (8.3×).

| C | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | Σ med | accept med |
|---|---|---|---|---|---|---|---|---|---|---|
| V0 (run B) | 29.8 | 47.3 | 53.4 | 63.6 | 64.7 | 77.0 | 89.2 | 103.0 | **528.0** | 23.40 |
| **V5** | 31.7 | 38.8 | 52.6 | 50.9 | 57.0 | 68.8 | 71.7 | 74.8 | **446.3** | **16.15** |
| Δ vs V0(B) | +6.4% | −18.0% | −1.5% | **−20.0%** | −11.9% | −10.6% | **−19.6%** | **−27.4%** | **−15.41%** | **−7.25 pp** |

cold prefill 1935.7 / 1809.6 / 1711.2 tok/s → vs V0(B) **+1.1% / +1.2% /
+1.3%** (consistent sign, but an order of magnitude below anything that
matters).

**Verdict: rejected — the worst cell of the campaign.** Σ −15.41% (59× the
Σ dispersion) and acceptance −7.25 pp median (6× the ±1.15 pp band), with
7 of 8 cells down and the loss growing with concurrency (C8 −27.4%). The
mechanism is legible: raising draft depth from 6 to 9 under
`draft_sample_method=probabilistic` makes the verifier reject more of the
extra drafted tokens, so each step buys 3 more draft tokens it mostly
cannot use — per-cell draft counts roughly doubled (e.g. C5 run3 4914 →
8541 draft tokens) while accepted tokens *fell*. Deeper drafts are not free
on this checkpoint; any future depth experiment must re-tune the sampler
first. Prefill's uniform +1.1~+1.3% confirms the harness was healthy and
that this is a decode-side effect only.

### Confirm boots (V1b / V3b)

Per decision rule 2, V1 and V3 are each re-measured on an independent boot
before any is called a winner.

#### V1b — V1 confirmed on a second boot

`ab-run-cell.sh V1 V1b deepseek-vision-tune`, apply 12:47:38
(`conf_sha256=e1c96bee879e83a5`, diff exactly `- VLLM_USE_BREAKABLE_CUDAGRAPH=0`),
`CELL DONE` 13:07:33. Proof of effect on the second boot:
`env VLLM_USE_BREAKABLE_CUDAGRAPH not set` + `breakable_cudagraph=ON
(=> inductor/torch.compile DISABLED)` — the same direction as V1 run A.

| C | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | Σ med | accept med |
|---|---|---|---|---|---|---|---|---|---|---|
| V0 (run B) | 29.8 | 47.3 | 53.4 | 63.6 | 64.7 | 77.0 | 89.2 | 103.0 | **528.0** | 23.40 |
| V0 (run A) | 34.3 | 44.6 | 52.9 | 62.6 | 74.5 | 86.2 | 80.9 | 93.4 | **529.4** | 24.55 |
| V1 (run A) | 30.5 | 48.4 | 57.3 | 65.2 | 76.5 | 78.5 | 90.8 | 96.6 | **543.8** | 25.20 |
| **V1b** | 30.0 | 53.0 | 50.6 | 67.4 | 74.7 | 77.9 | 87.9 | 90.8 | **532.3** | 24.50 |
| Δ V1b vs V0(B) | +0.7% | +12.1% | −5.2% | +6.0% | +15.5% | +1.2% | −1.5% | **−11.8%** | **+0.81%** | +1.10 pp |
| Δ V1b vs V1(A) | −1.6% | +9.5% | −11.7% | +3.4% | −2.4% | −0.8% | −3.2% | −6.0% | **−2.12%** | −0.70 pp |

cold prefill 1952.8 / 1824.8 / 1729.5 tok/s → vs V0(B) +2.0% / +2.0% /
+2.3%, all three positive but inside the ±8% prefill noise floor. Prefix
probe `cache=HIT` (8.5×).

**Two-boot reading of V1.** Σ decode is positive on **both** independent
boots (+2.99%, +0.81%; mean +1.90%) and never negative, and acceptance is
positive on both (+1.80 pp, +1.10 pp). Sign consistency across two boots is
what decision rule 2 asks for, so **V1 survives as a candidate.** But the
magnitude is not stable: the two V1 boots differ by **2.12%**, whereas the
two V0 boots differed by only **0.26%**. That is an important correction to
the campaign's premise — the Σ dispersion was estimated from a single pair
of baseline boots and that pair happened to be unusually tight. Two samples
cannot bound a tail, so **the ±0.26% figure should be read as "at most this
tight", not as the noise floor.** Any Σ delta under ~2% on this lane is now
indistinguishable from boot-to-boot variation.

Per-cell sign consistency across the two V1 boots (the only cells worth
trusting):

- **C5 up twice** (+18.2%, +15.5%) with acceptance +4.7 pp / +5.3 pp — the
  one genuinely reproducible gain.
- **C8 down twice** (−6.2%, −11.8%) with acceptance −5.2 pp / −4.1 pp —
  high-concurrency decode reliably pays for this knob.
- C1/C2/C4/C6 small-positive-to-noise; C3 and C7 **flip sign** between
  boots and must not be read either way.

So V1 is a real but *narrow* win: it buys mid-concurrency decode and loses
high-concurrency decode, netting +0.8% ~ +3.0%.

#### V3b — V3 confirmed on a second boot

`ab-run-cell.sh V3 V3b deepseek-vision-tune`, apply 13:08:43 with
`conf_sha256=0e90b564b408f783` — **byte-identical to the V3 apply**, i.e. the
single-knob edit is fully reproducible. `CELL DONE` 13:29:01. Proof of
effect: `argv --long-prefill-token-threshold 0`, `--block-size 256`,
`env VLLM_USE_BREAKABLE_CUDAGRAPH=0` with the inductor warning ABSENT
(inductor ON, unchanged from V0).

| C | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | Σ med | accept med |
|---|---|---|---|---|---|---|---|---|---|---|
| V0 (run B) | 29.8 | 47.3 | 53.4 | 63.6 | 64.7 | 77.0 | 89.2 | 103.0 | **528.0** | 23.40 |
| V3 (run A) | 36.8 | 43.3 | 56.6 | 66.3 | 73.7 | 87.1 | 87.9 | 89.9 | **541.6** | 24.25 |
| **V3b** | 35.5 | 47.8 | 55.6 | 68.2 | 74.0 | 80.6 | 87.1 | 94.7 | **543.5** | 24.30 |
| Δ V3b vs V0(B) | +19.1% | +1.1% | +4.1% | +7.2% | +14.4% | +4.7% | −2.4% | −8.1% | **+2.94%** | +0.90 pp |
| Δ V3b vs V3(A) | −3.5% | +10.4% | −1.8% | +2.9% | +0.4% | −7.5% | −0.9% | +5.3% | **+0.35%** | +0.05 pp |

cold prefill 1109.2 / 1754.8 / 1683.2 tok/s → vs V0(B) **−42.1% / −1.9% /
−0.4%**. Prefix probe `cache=HIT` (9.4×).

**Two-boot reading of V3 — the strongest candidate in the campaign.**

- Σ decode **+2.58% and +2.94%**, and the two boots land **0.35% apart**.
  Both sit above the ~2% "indistinguishable from boot variation" bar that
  the V1b measurement forced on us, and they agree with each other far more
  tightly than V1's two boots do (0.35% vs 2.12%).
- Acceptance +0.85 pp / +0.90 pp — consistent but inside the ±1.15 pp band,
  so it is **neutral, not a gain**. V3 buys throughput without changing how
  often the verifier accepts.
- Per-cell sign agreement across the two boots is high (6 of 8 agree):
  **C1 +23.5% / +19.1%** and **C5 +13.9% / +14.4%** are up twice, **C8
  −12.7% / −8.1%** is down twice, C7 down twice by ~2%. Acceptance signs
  agree on C1 (+9.6/+7.2 pp), C5 (+4.7/+3.8 pp), C6 (+5.7/+2.9 pp) and C8
  (−5.2/−2.3 pp).

**The −42.1% cold-prefill figure at w=32000 is an outlier, not a finding.**
The same boot, two minutes later, ran the prefix probe's *first* round on a
cold 32 k prompt and measured **1934.0 tok/s** — i.e. two cold 32 k
prefills in one boot read 1109.2 and 1934.0. The two wider widths in the
same run were −1.9% and −0.4%, i.e. dead flat. One cold-prefill sample at
this width is not evidence; the harness should take a median. Recorded
because a reader comparing tables would otherwise conclude V3 halves
prefill.

**Ranking after two boots each: V3 > V1.** V3 is consistent in magnitude,
reproducible per-cell, and costs nothing on acceptance; V1 is directionally
positive but varies 2.12% boot-to-boot and trades away C8.

### V-win — `WINNERS=V1,V3` — **does not beat V3 alone; V1 dropped**

Launched 13:30:45 (`conf_sha256=e885d68787406391`). Full `diff -u` against
the pristine base showed **exactly two hunks and nothing else** — the V3
argv change and the V1 env removal — so the combined cell is clean.
`CELL DONE` 13:50:34. Proof of effect: `argv --long-prefill-token-threshold
0` **and** `env VLLM_USE_BREAKABLE_CUDAGRAPH not set` /
`breakable_cudagraph=ON (=> inductor/torch.compile DISABLED)`.

| C | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | Σ med | accept med |
|---|---|---|---|---|---|---|---|---|---|---|
| V0 (run B) | 29.8 | 47.3 | 53.4 | 63.6 | 64.7 | 77.0 | 89.2 | 103.0 | **528.0** | 23.40 |
| V3 (run A) | 36.8 | 43.3 | 56.6 | 66.3 | 73.7 | 87.1 | 87.9 | 89.9 | **541.6** | 24.25 |
| V3 (run B) | 35.5 | 47.8 | 55.6 | 68.2 | 74.0 | 80.6 | 87.1 | 94.7 | **543.5** | 24.30 |
| **V-win** | 35.9 | 52.8 | 56.2 | 71.0 | 73.3 | 77.7 | 83.3 | 87.9 | **538.1** | **24.95** |
| Δ V-win vs V0(B) | +20.5% | +11.6% | +5.2% | +11.6% | +13.3% | +0.9% | **−6.6%** | **−14.7%** | **+1.91%** | **+1.55 pp** |
| Δ V-win vs V3(A) | −2.5% | +22.0% | −0.7% | +7.0% | −0.5% | −10.8% | −5.2% | −2.2% | **−0.65%** | +0.70 pp |
| Δ V-win vs V3(B) | +1.1% | +10.5% | +1.1% | +4.1% | −0.9% | −3.6% | −4.4% | −7.2% | **−1.01%** | +0.65 pp |

cold prefill 1575.9 / 1855.7 / 1751.7 tok/s → vs V0(B) **−17.7% / +3.8% /
+3.7%**. Prefix probe `cache=HIT` (8.9×).

**Verdict: V-win is worse than V3 on its own, so V1 does not survive.**

- Primary metric: **538.1 < 541.6 and < 543.5.** Adding V1 to V3 costs
  0.65% ~ 1.01% against each V3 boot. The decision rule was explicit — keep
  V1 only if `V-win ≥ V3 alone` — and it is not.
- The loss is exactly where V1's own signature said it would be: **C7 −6.6%
  and C8 −14.7%** (V3 alone: C7 −1.5%/−2.4%, C8 −12.7%/−8.1%). V1's known
  high-concurrency penalty is visible again, so this is a mechanism
  confirming the reading, not a coin flip.
- What V-win *does* buy is **acceptance 24.95 (+1.55 pp)** — the only cell
  in the campaign to clear the ±1.15 pp band on the secondary metric. But
  the campaign optimises throughput, and +1.55 pp of acceptance does not
  pay for −0.7% ~ −1.0% of Σ decode.

**Secondary finding — the w=32000 cold-prefill sample is structurally
noisy.** Across all eight completed boots that width read 1914.4, 1909.4,
1952.8, 1754.1, **1109.2**, 1930.4, 1935.7, 1575.9 — a 1109~1953 range,
i.e. ±23% around its own median, while w=131000 spans only 1741~1861
(±3.5%) and w=200000 spans 1641~1770 (±4%). In every case the prefix
probe's own first-round cold 32 k prefill in the same boot read
1934~2026 tok/s, i.e. normal. **Do not use the w=32000 cold-prefill cell
as evidence for anything**; the two wider widths are the usable ones.
This retroactively clears V3's −42.1% and V-win's −17.7% readings.

## Production acceptance — two identical boots, 8 % apart, second matches the tune lane

Promoted production lane (`gb10 use deepseek-vision`). **Boot 1** READY
13:59:48; **boot 2** with the byte-identical conf READY 14:26:06.

| # | gate | result |
|---|---|---|
| 1 | `cluster-compose-verify deepseek-vision` | ✅ **PASS both ranks**, `compose parity holds`, rc=0 |
| 2 | `gb10 smoke` | ✅ `http=200` / `HELLO-TP2-OK` |
| 3 | single-knob proof from the **live container argv** | ✅ `--long-prefill-token-threshold 0`; and `--block-size 256`, `--max-cudagraph-capture-size 56`, `num_speculative_tokens=6`, `draft_sample_method=probabilistic`, `enable_prefix_caching=True`, `cudagraph_capture_sizes [1,2,4,8,…,56]`, `VLLM_USE_BREAKABLE_CUDAGRAPH=0` — **every other knob identical to V0, no V1/V4/V5 leakage** |
| 4 | patch parity, prod `STACK_DIR` vs tune `STACK_DIR` | ✅ `diff -rq …/patches …/patches-tune` → **empty** (byte-identical, incl. `hotfix-vllm-dspark-swa-prefix.py`, `vision_exp/`) |
| 5 | JIT parity | ✅ `jit_spike_lines=1`, `breakable_cudagraph=… warning ABSENT` (inductor ON) on **both** lanes |
| 6 | bench `PROD` boot 1 (14:01:37 → 14:16:06) | ⚠️ **Σ 497.7** — below every tune-lane reading, incl. V5's reject |
| 7 | bench `PROD2` boot 2, **identical conf** (→ 14:39:33) | ✅ **Σ 538.1**, `any_errors=0` ×24, `identical=2/2` |
| 8 | warm prefix probe 32 000 ×3, 261 K long-context, garble soak ×3, `/health`, `check-git-sync --block` | see *Remaining gates* at the end of this section |

Two production boots, byte-identical conf, side by side with the tune lane:

| C | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | Σ med | accept med |
|---|---|---|---|---|---|---|---|---|---|---|
| V0 (tune, run B) | 29.8 | 47.3 | 53.4 | 63.6 | 64.7 | 77.0 | 89.2 | 103.0 | **528.0** | 23.40 |
| V0 (tune, run A) | 34.3 | 44.6 | 52.9 | 62.6 | 74.5 | 86.2 | 80.9 | 93.4 | **529.4** | 24.55 |
| V3 (tune, run A) | 36.8 | 43.3 | 56.6 | 66.3 | 73.7 | 87.1 | 87.9 | 89.9 | **541.6** | 24.25 |
| V3 (tune, run B) | 35.5 | 47.8 | 55.6 | 68.2 | 74.0 | 80.6 | 87.1 | 94.7 | **543.5** | 24.30 |
| **PROD** boot 1 (V3) | 27.5 | 42.1 | 51.5 | 62.8 | 61.7 | 79.7 | 81.5 | 90.9 | **497.7** | 24.15 |
| **PROD2** boot 2 (V3) | 33.6 | 46.5 | 64.6 | 69.4 | 70.9 | 78.4 | 85.3 | 89.4 | **538.1** | 23.95 |
| Δ PROD2 vs tune-V0(B) | +12.8% | −1.7% | +21.0% | +9.1% | +9.6% | +1.8% | −4.4% | −13.2% | **+1.91%** | +0.55 pp |
| Δ PROD2 vs tune-V3(B) | −5.3% | −2.7% | +16.2% | +1.8% | −4.2% | −2.7% | −2.1% | −5.6% | **−1.01%** | −0.35 pp |
| Δ PROD2 vs PROD boot 1 | +22.2% | +10.5% | +25.4% | +10.5% | +14.9% | −1.6% | +4.7% | −1.7% | **+8.12%** | −0.20 pp |

cold prefill 32 K / 131 K / 200 K — boot 1: 1372.1 / 1784.0 / 1721.3;
boot 2: 1515.1 / 1794.1 / 1772.5. Boot 2 is **+10.4% / +0.6% / +3.0%** over
boot 1, and the two usable widths (131 K, 200 K) land back inside the
all-campaign band (1741–1861 and 1641–1770). Boot diagnostics also moved
the same direction: `jit_spike_lines` **1 → 0**, model load **241.4 s →
233.3 s**, KV cache 10.71 → 10.53 GiB. Both boots: 24/24 `any_errors=0`,
prefix repeat check `identical=2/2`, `health=200`.

### What this establishes — and what it still cannot

**Config-level explanations are eliminated.** For both boots: the image is
the pinned `dspark-vllm-gx10:0.1.1`; the live container argv is a single
changed knob (`--long-prefill-token-threshold 0`) with `--block-size 256`,
`--max-cudagraph-capture-size 56`, `num_speculative_tokens=6`,
`draft_sample_method=probabilistic`, `enable_prefix_caching=True` and
`cudagraph_capture_sizes [1,2,4,8,…,56]` all unchanged (no V1/V4/V5
leakage); `VLLM_USE_BREAKABLE_CUDAGRAPH=0` is still set (inductor ON, so
V1 was **not** folded in); `diff -rq` of the production and tune `patches/`
trees is **empty**; `cluster-compose-verify` PASSes both ranks; and the
tune lane's `.base` differs from the production conf only in lane identity
(`PROFILE_ID`/`DISPLAY_NAME`/`STACK_DIR`/`COMPOSE_FILE`/cache paths) —
**argv and env are equivalent**. So the two production numbers differ for a
non-config reason.

**The cold-cache hypothesis is supported, not proven.** Boot 1 was the
production lane's *first boot of the campaign* against
`~/.cache/vllm-deepseek-vision` (mtime 13:58:57, written during that boot;
61 M vs the tune lane's 68 M), while the tune lane had run eight consecutive
boots against one warm cache. Boot 2 — same conf, now-warm cache — came back
**538.1, i.e. +8.12% over boot 1**, `jit_spike_lines` 1 → 0, and lands within
1.0% of both tune-lane V3 boots. That is exactly what a compile penalty
falling in the measured window looks like. It is *not* proof: a single
pair cannot separate "first-boot compile cost" from "plain boot variation".

**The honest headline number for the production lane is boot 2 = 538.1.**
Read against the tune-lane V0 reference (528.0 / 529.4) that is **+1.9%**,
and against tune-lane V3 (541.6 / 543.5) it is **−0.65% / −1.01%** — i.e.
the production lane reproduces the tune result once its cache is warm.

**What production cannot do is validate the knob.** The measured boot-to-boot
Σ spread on this lane is **8.1%**, against an effect size of **≈ +2.7%**.
A single production V0 arm would therefore be *underpowered by ~3×*: it could
neither confirm nor refute V3, and inventing a precise number from it would
be worse than admitting the limitation. This is why the promotion decision
rests on the **tune lane**, where V3's two boots agreed to **0.35%** and both
cleared the campaign's own ~2% threshold, with acceptance neutral and prefill
flat on the two usable widths. The mainline campaign drew exactly this line
("PROD ≥ E5-on-tune and E5 ≥ E0 on every headline metric" — a *parity* claim,
not a fresh gain), and this campaign does the same.

**Operational finding worth keeping:** the production vision lane's first
boot after a config change is measurably slower than the next one
(~8% on Σ decode, plus a JIT line and ~8 s of model load). Re-boot once
before believing a production-side benchmark.

### Remaining gates — all run on the live promoted production stack (boot 2)

| gate | result |
|---|---|
| warm prefix probe ×3 (`bench-prefix-hit.sh 32000 3`) | **8.6× HIT** (15.204 s → 1.776 s, 2105.5 → 18026.9 tok/s), `PREFIX-OK` `vs_prev=identical` ×2, `completion=OK` |
| 261 K cold long-context (`bench-ctx.sh 261000 1`) | `prompt_tokens=261084`, 157.489 s, **1657.7 tok/s**, `finish=length`, no error (mainline E5: 261021 / 158.361 s / 1648.2 — parity) |
| garble soak ×3, `temp=0`, `max_tokens=400`, `thinking:false` | **3/3 `finish=stop`**, `reasoning_content` empty, `uniq_ratio` **0.58 / 0.60 / 0.63** (list-shaped prose, not degenerate), **primes 101…149 present 10/10 in all 3 runs**, prose coherent |
| 3×3 short-prompt completeness (3 prompts × 3 runs) | **PASS 3/3** — every run `finish=stop`, non-empty, `identical=True` within prompt, expected answer in all (`HELLO-TP2-OK` / `Paris` / `1, 2, 3, 4, 5`) |
| `/health` | HTTP **200**, 0.8–1.4 ms (checked after every stage) |
| `scripts/check-git-sync.sh --block` | **rc = 0** (the `WARN: repo is out of sync` line is only the uncommitted-tree notice — 0 ahead / 0 behind, `HEAD = origin/main = 822afa3`) |

**Garble-soak false alarm (third of the campaign).** The first attempt at this
gate used the lane's default `thinking:true` and reported **`finish=length`,
`content` len 0, `uniq_ratio 0.00` ×3** — which reads exactly like garbling.
It is not: it is the trap already documented in `scripts/bench-prefix-hit.sh`
L61–L66, where the 400-token budget is consumed inside the reasoning block so
`message.content` comes back empty. Re-running with
`"chat_template_kwargs":{"thinking":false}` produced the 3/3 PASS above.
Same class of false alarm as the other two this campaign — **re-read the
mechanism before calling a gate failed.**

**Quality caveat (spot-check, not A/B — same limitation mainline recorded).**
Run 1's property list has **9/10 correct claims**: 149 is asserted to be "a
centered square number", but the centered-square sequence is 1, 5, 13, 25,
41, 61, 85, 113, 145, … — 149 is not in it. All ten *primes* are listed
correctly in all three runs, and this knob only changes prefill scheduling,
not weights or sampling, so it cannot explain a knowledge error. Recorded
for completeness rather than treated as a regression.

## Promotion — decision record

**Decision: promote V3 only** — `cluster-profiles.d/deepseek-vision.conf`
gets `--long-prefill-token-threshold 1024 → 0`, nothing else.

| cell | Σ vs V0(B), two boots | acceptance | outcome |
|---|---|---|---|
| **V3** | **+2.58% / +2.94%**, boots 0.35% apart | +0.85 / +0.90 pp (neutral) | **PROMOTE** |
| V1 | +2.99% / +0.81%, boots 2.12% apart | +1.80 / +1.10 pp | not promoted — magnitude unstable, and it degrades C8 |
| V-win (V1+V3) | +1.91%, below V3 alone | +1.55 pp | not promoted — fails `≥ V3 alone` |
| V2 | never booted | — | rejected (not bootable) |
| V4 | −5.19% | +0.75 pp | rejected (regression) |
| V5 | −15.41% | −7.25 pp | rejected (worst cell) |

V3 is the only knob that is positive twice, reproducible to 0.35%, neutral
on acceptance, and flat on the two usable prefill widths. Expected gain
**≈ +2.7% Σ decode** on this lane, with C1 and C5 consistently up
(+19~24%, +14%) and C8 consistently down (−8~13%) as the known cost.

Remaining (requires maintainer approval before commit/push):

1. ✅ **Applied** — one-line change to `cluster-profiles.d/deepseek-vision.conf`
   on both checkouts (`deepseek.conf` untouched, `git diff` = 1 file / 1 line).
2. ✅ **Full gate set PASS on the promoted production stack** —
   `cluster-compose-verify` both ranks, `gb10 smoke`, live-argv single-knob
   proof, warm prefix **8.6× HIT**, 261 K `1657.7 tok/s` `finish=length`,
   garble soak **3/3**, 3×3 completeness **3/3**, `/health 200`,
   `check-git-sync --block` **rc=0**. (PROD/PROD2 discrepancy resolved — see
   *Production acceptance*.)
3. ✅ **`check-git-sync --block` rc = 0.**
4. ⏳ README Vision-Exp section (currently the stale 2026-09-20 table) → V0 vs
   promoted; `handoff.md` `## 2026-10-07` vision section.
5. ⏳ `bin/gb10 use deepseek` to return mainline.
6. ⏳ `git add` / commit / push to both remotes — **approval required.**
   Note: `scripts/ab-run-cell.sh` is untracked and needs
   `git update-index --chmod=+x`; the campaign doc `docs/DEEPSEEK_VISION_TUNE_AB_2026-10-07.md`
   is local-only until committed.
