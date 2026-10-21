# qwen38flash — MTP draft vocabulary A/B (2026-10-21)

**Decision: the lane's default draft head becomes `zh` (65,536-row Chinese file);
`Q38_DRAFT_VOCAB=en_code_47k` restores the upstream default.**

Measured on the live TP2 cluster (`qwen38flash`, node0 `spark-25d5` / node1
`spark-8095`), upgrade-only change: the only difference between arms is which
vocabulary the MTP drafter slices its `lm_head` to. Weights, image, patches,
sampling and serving flags are identical; drafting never changes outputs (a
draft outside the subset is rejected at verification), so this is a pure speed
knob.

## Why it was worth measuring

The upstream 47k file is English+code. Upstream's own coverage table puts Chinese
at **34.7 %** held-out coverage (Russian 31.5 %, Japanese 30.0 %), and their TP=2
measurement reports zh **+19…+39 %** once the language file is used. This
deployment's traffic is Chinese-heavy, so the expected win is larger than for an
English-only site.

## Method

`scripts/bench-draft-vocab.py` (added in this change).

- Each arm runs **both** a Chinese set and an English control in the **same boot**,
  interleaved per concurrency, so boot-to-boot drift affects both.
- Every stream is fixed-length (`ignore_eos`, `max_tokens=400`), `temperature=0`,
  `seed=0`, `chat_template_kwargs.enable_thinking=false`.
- Acceptance is a **delta of the vLLM `spec_decode_*` counters** sampled around
  each cell (`/metrics`), not a cumulative average.
- `--reps 6` rotates the prompt start, so every concurrency level (including
  C=1) sees all six prompts of a set. This mattered: with the first version
  (3 reps, no rotation) C=1 always measured prompt 0 and produced a **false
  "English regressed 35 %"** signal — see "What went wrong first" below.
- `compare` normalises the target language against the English control of the
  same arm (`target/control`), then reports B/A.

## Results

Both arms: reps 6, medians over reps, zh target / en control.

| C | 47k zh tok/s | zh 65k tok/s | Δ zh | 47k accept | zh 65k accept |
|---|---|---|---|---|---|
| 1 | 27.66 | **44.50** | **+60.9 %** | 15.9 % | **49.3 %** |
| 2 | 47.16 | **74.55** | **+58.1 %** | 17.8 % | **53.1 %** |
| 4 | 75.05 | **112.53** | **+49.9 %** | 22.7 % | **52.4 %** |
| 8 | 114.43 | **165.81** | **+44.9 %** | 20.6 % | **50.4 %** |

| C | 47k en tok/s | zh 65k en tok/s | Δ en |
|---|---|---|---|
| 1 | 42.29 | 43.81 | +3.6 % |
| 2 | 78.63 | 73.49 | −6.5 % |
| 4 | 91.28 | 108.71 | +19.1 % |
| 8 | 151.60 | 133.30 | −12.1 % |

Control-normalised effect (`B norm / A norm`), from
`bench-draft-vocab.py compare /tmp/q38-47k-b.jsonl /tmp/q38-zh65k-b.jsonl`:

| C | A norm | B norm | B/A |
|---|---|---|---|
| 1 | 0.654 | 1.016 | **1.553** |
| 2 | 0.600 | 1.014 | **1.691** |
| 4 | 0.822 | 1.035 | **1.259** |
| 8 | 0.755 | 1.244 | **1.648** |

mean **1.538** (min 1.259, max 1.691).

**Acceptance is the load-bearing evidence**: +30 pp in all four cells, on
six-prompt medians. Throughput alone would not be enough — this lane's
boot-to-boot drift is large (below).

## Caveats (read before quoting the numbers)

1. **Boot-to-boot drift is bigger than upstream's ±12 % claim.** Same 47k config,
   two boots, normalised: 1.149 / 0.797 / 1.320 / 1.025 (mean 1.073). That
   estimate is itself contaminated (the first 47k arm used the pre-fix harness),
   so treat it as an **upper bound** on drift, not a clean A/A figure. The zh
   effect exceeds it in 3 of 4 cells; C4 (1.259) is inside it. The +30 pp
   acceptance move is not subject to that drift.
2. **English is not improved, just not measurably hurt.** It moves within the
   drift band above; an English-heavy deployment should stay on
   `Q38_DRAFT_VOCAB=en_code_47k`.
3. **One boot per arm.** This is a 2-boot A/B plus an A/A drift bound, not a
   10-boot campaign. The direction matches upstream; the magnitude (+45…+61 %
   vs their +19…+39 %) is larger, plausibly because the acceptance headroom was
   bigger here at 47k (17–23 % vs their ~34.7 % coverage).
4. **Prompt sets are synthetic** (six prompts: code explanation, prose,
   JSON-only output, step-by-step reasoning, mechanism explanation, pagination
   algorithm). They exercise drafting, not task quality; quality is unchanged by
   construction.
5. **The draft head gets bigger**: 65,536 ids, `60279 on this rank of 2`, draft
   `lm_head` shard 0.59 → 0.29 GiB per draft step (from 0.22 GiB at 47k). That
   is the cost side of the trade and is why a language file is not free.

## What went wrong first (harness lesson)

The first pass (3 reps, no prompt rotation) reported English C1 falling from
60.1 to 39.4 tok/s and acceptance 74.8 % → 38.7 %, i.e. a 35 % regression. It
was an artifact:

- C=1 always sent `prompts[0]`. The English prompt 0 happens to be highly
  predictable (74.8 % acceptance), while other English prompts in the same boot
  measured 4–58 %. With six rotated prompts the C1 control median is 42–44 tok/s
  in **both** arms.
- Lesson: a single-prompt C=1 cell is not a control. `bench-draft-vocab.py` now
  rotates the prompt start per rep and records `prompt_start` in every JSONL row.

## Reproduction

On node0, in a maintenance window (the lane is exclusive; each arm costs a
13-minute boot here):

```bash
cd ~/workspace/ai-gb10-cluster-runtime-manager && git pull   # >= a333b99
# arm A (upstream default)
Q38_DRAFT_VOCAB=en_code_47k gb10 use qwen38flash && gb10 wait qwen38flash
scripts/bench-draft-vocab.py run --label 47k-b --lang zh --reps 6 --out /tmp/q38-47k-b.jsonl
# arm B (new default)
gb10 use qwen38flash && gb10 wait qwen38flash
scripts/bench-draft-vocab.py run --label zh65k-b --lang zh --reps 6 --out /tmp/q38-zh65k-b.jsonl
scripts/bench-draft-vocab.py compare /tmp/q38-47k-b.jsonl /tmp/q38-zh65k-b.jsonl
```

Confirm the mount and the drafter line before trusting an arm:

```bash
docker inspect -f '{{range .Mounts}}{{.Source}} {{end}}' cluster-node0 | tr ' ' '\n' | grep draft_vocab
docker logs cluster-node0 2>&1 | grep -iE 'of 248320' | tail -2
# 47k  -> "47149 of 248320 tokens (19.0%), 45734 on this rank of 2; ... 0.59 -> 0.22 GiB"
# zh   -> "65536 of 248320 tokens (26.4%), 60279 on this rank of 2; ... 0.59 -> 0.29 GiB"
```
