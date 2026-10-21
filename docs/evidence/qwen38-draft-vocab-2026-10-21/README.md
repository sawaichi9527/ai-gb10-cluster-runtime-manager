# Evidence — qwen38flash draft vocabulary A/B (2026-10-21)

Raw `bench-draft-vocab.py` JSONL from the two arms. One row per cell
(`label`, `lang`, `conc`, `rep`, `prompt_start`, `wall_s`, `tokens`,
`agg_tok_s`, `per_stream_tok_s`, spec-decode counters and their deltas,
`errors`).

| file | arm | harness | rows |
|---|---|---|---|
| `q38-47k.jsonl` | 47k (upstream default) | first version (3 reps, no prompt rotation) | 24 |
| `q38-47k-b.jsonl` | 47k | fixed (6 reps, prompt start rotates per rep) | 48 |
| `q38-zh65k.jsonl` | zh 65k | first version | 24 |
| `q38-zh65k-b.jsonl` | zh 65k | fixed | 48 |

**Use the `-b` pair for the decision.** The first pair is kept because it is the
evidence for the harness lesson: with C=1 always hitting `prompts[0]`, the English
control read 74.8 % acceptance (60.1 tok/s) on that one prompt and 4–58 % on the
others, which produced a false "English regressed 35 %" signal. See
`docs/QWEN38FLASH_DRAFT_VOCAB_AB_2026-10-21.md` §"What went wrong first".

Collected 2026-10-21 on node0 (`spark-25d5`), lane `qwen38flash`, from the live
cluster; copied byte-for-byte from `/tmp/q38-*.jsonl` (sha256 verified on both
ends):

```
325ee597c7e392cafbcc48cc48ee7082ff7260ee640e64b483de9a5e4ec7b736  q38-47k-b.jsonl
327b047f65bb39d1399c25de521ea2b05e8d1c8c271c5951e0cf84ce264caab7  q38-47k.jsonl
a75cac24b6badbc182d3bdba679dc78f848f804cc38de4e40256aaad0ea1e6ba  q38-zh65k-b.jsonl
05355957985e2a2ab5abbefe16ef63af927d4f4edd93cdcc89958357d9c09d03  q38-zh65k.jsonl
```
