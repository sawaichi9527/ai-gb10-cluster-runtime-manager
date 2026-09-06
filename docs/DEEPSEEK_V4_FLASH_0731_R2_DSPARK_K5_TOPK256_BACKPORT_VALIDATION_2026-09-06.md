# DeepSeek V4 Flash 0731 — R2 DSpark K5 topk=256 backport: Phase A validation (2026-09-06)

Live validation record for the minimal **TopK=256-only** FlashInfer SM120 DSV4 backport
(design `docs/DEEPSEEK_V4_FLASH_0731_R2_DSPARK_K5_TOPK256_BACKPORT_DESIGN_2026-09-06.md`,
review branch `image-workstream/dspark-k5-topk256-backport`).

Scope (B): single arm of the previously reported failure — the (5, 64, 256) decode /
`topk == 256` prefill dispatch entries, topk=192 deliberately absent. NO 192, NO H8/TP8,
NO dual-cache, NO #4802, NO A' shim.

## Candidate artifact (Phase A image)

- **Tag (v2)**: `ghcr.io/aeon-7/aeon-vllm-ultimate:2026-09-06-v0.27.1-omni-ds4flash0731-r1-topk256v2`
- **Image ID / digest**: sha256 `61c7f905b76b992eff609bb354334c44c74c427ec33c1d876a675ae6c917da7c`;
  Node1 image ID `c1fa6d5c52a7` (verified loaded on both nodes).
- **Sources** (from v2 build context), epoch mtimes on Node0:
  - `sparse_mla_sm120_decode_dsv4.cu` → **1788694912**
  - `sparse_mla_sm120_prefill.cu` (topk==256 dispatch arm) → **1788694912**
  - `_sparse_mla_sm120.py` (256 entries) → **1788695149**
- Backport rule: JIT must rebuild the cached op newer than the 256-entry source edits and
  contain the ≥6 `ILi…256E` templated dispatch arms (5 decode NH + ≥1 prefill), none for 192.

## §8 stale-JIT / dispatch gates

Methods: `cuobjdump` from CUDA 13 (`/usr/local/cuda/bin/cuobjdump`; `--dump-elf-symbols`
is the authoritative symbol source on this toolchain; spellings recorded as gates, not the
exact demangled names). Executed inside the target image containers so the verdict applies
to the actually-produced `.so`.

### 8.1 mtime triples — pre-boot (image-compiled `.so`)
| node | source max mtime | artifact mtime | verdict |
|---|---|---|---|
| Node0 | 1788695149 | 1788696841 | PASS (freshly JIT-built under v2) |
| Node1 | 1788695149 | 1788697460 | PASS (freshly JIT-built under v2, transferred) |

### 8.2 symbol counts on pre-boot artifacts (`cuobjdump`)
| node | `--list-elf` sm_121a cargo | `--dump-elf-symbols` `256` | `--dump-elf-symbols` `192` | verdict |
|---|---|---|---|---|
| Node0 | 5 cubins, 0 non-121a | ALL=9 (DECODE=5, >=6 ✓) | 0 | PASS |
| Node1 | 5 cubins, 0 non-121a | ALL=9 (DECODE=5, >=6 ✓) | 0 | PASS |

### 8.3 dispatch-predicate probe (in-image `tests/probe_topk256.py`)
Both nodes printed:

```
TOPK256_DISPATCH_GATE PASS [True, True, True, True, True, True]
```

The 6 cases = the failing (5,64,256) → dispatchable; (5,64,192) → False; controls
(5,64,512) & (5,64,128) → True; full 256 sweep (8,128) → True.

> §8 gates **PASS** on the v2 derived tag on **both** nodes (Node0 first, Node1 re-run).

## §8 on the boot-produced artifact (the runtime the server actually runs)

The tp2 containers JIT-built their own cached op at boot; §8.1+§8.2 were re-applied to it.

- Node0 `tp2-node0`:
  `/root/.cache/flashinfer/..0.6.16.post3/121a/cached_ops/sparse_mla_sm120/sparse_mla_sm120.so`
  mtime **1788698241** (≥ 1788695149, PASS) — `--list-elf` 5/5 sm_121a; symbols `256`=9, `192`=0.
- Node1 `tp2-node1`: same path, mtime **1788698240**, size **838120** (byte-identical size).
  `--list-elf` 5/5 sm_121a; symbols `256`=9, `192`=0.

> §8.1 + §8.2 **PASS** on the boot-produced artifacts too.

## §9 Phase A acceptance gates (deepseek TP2, profile `deepseek`, DSpark K=5 ON)

Launcher `bin/gb10 use deepseek` (`cluster-profiles.d/deepseek.conf`), READY
**2026-09-06 20:39:56**. Engine args (rank0): model `aeon`, max_model_len **65536**,
kv `fp8_ds_mla`, spec `dspark num_speculative_tokens=5`, `enable_prefix_caching=False`,
`enable_chunked_prefill=True`, `max_num_seqs=4`, `gpu_memory_utilization=0.8`,
`disable_custom_all_reduce=True`.

### 9.1 Boot
- `/health` → 200 (READY line above).
- KV block size **256** for DEEPSEEK_SPARSE_SWA.
- DSv4 decode autotune **completed** (66 configs saved/loaded both ranks, Node0 log
  `Saved 66 configs` / `Autotune cache loaded on rank 0`; Node1 `loaded on rank 1`).
- No CHECK / num_tokens abort during boot.

### 9.2 Generation
Multi-turn chat completion via `/v1/chat/completions` (`gen.py`): TURN1 stop, 33 comp
tokens; TURN2 stop, 8 comp tokens. Spec-decode counters from `/metrics`:
`draft_tokens_total=16460`, `drafts_total=3292` → **5.0 drafts/draft** (K=5); accepted
`538` → **3.27%** ≈ r2-A's 3.1%; per-pos accepted 510/28/0/0/0 → pos0-dominant
(mechanics correct; drafter quality bounded by the DFlash @ K=5).

### 9.3 Performance (single-stream aggregate tok/s)
| case | params | wall (s) | comp tok | agg tok/s | per-user tok/s |
|---|---|---|---|---|---|
| C1 | 1×256 | 22.13 | 256 | **11.57** | 11.57 |
| C1 | 1×400 | 33.44–35.52 (2 runs) | 400 | 11.96 / 11.26 | same |
| C2 | 2×400 | 41.07 | 800 | 19.48 | 9.74 |
| C4 | 4×400 | 61.72 | 1600 | 25.92 | 6.48 |

Controlling expectation (design §9.3): **native 256 > A' 512-padded probe ≈ 11.4 tok/s** —
11.57 > 11.40 ⇒ **PASS** *for the design's A'-relative gate only*. See §10 — this does NOT
clear the r1-relative performance target, so the DSpark K5 performance dimension FAILs.

⚠ Comparative note: r1 baseline C1/C2/C4 = 18.7 / 39.2 / 67.2 agg were measured with
**SPEC_METHOD=none** (no drafter, spec OFF). This run has DSpark K=5 ACTIVE by design, so
the absolute agg delta vs r1 is dominated by spec-decode overhead, not the topk=256 entry.
Aggregate still scales correctly C1→C2→C4 (11.96 → 19.48 → 25.92, +115%). Retain
spec-method parity (a no-drafter control) as a future pairing if a like-for-like agg
comparison is required.

### 9.4 Needles @ 8K / 32K / 60K (r1 parity)
| target | prompt_tokens | wall (s) | found | output |
|---|---|---|---|---|
| 8K | 8241 (r1 8234) | 4.1 | True | 8349205 |
| 32K | 32816 (r1 32803) | 20.5 | True | 8349205 |
| 60K | 61491 (r1 61483) | 39.6 | True | 8349205 |

PASS — near-exact r1 parity; the 60K case additionally exercises the long-context MLA/KV
path (64K budget) through the new kernel.

### 9.5 (OPTIONAL) decode (64,256) topk_length=133 truncation unit
Not run — optional per design §9.5; mirrors upstream's (32,256,133). Skipped this round
(GPU busy serving; no correctness dependence on the other gates).

## §10 Phase A classification (2026-09-06, owner decision)

| dimension | verdict |
|---|---|
| topk256 kernel / backport correctness | **PASS** (§8.1/8.2/8.3 green on both nodes, incl. boot-produced artifact) |
| DSpark K5 functional | **PASS** (§9.1 boot / §9.2 gen + spec counters / §9.4 needles) |
| DSpark K5 performance | **FAIL** (native topk256 C1 ≈ 11.57 tok/s essentially unchanged from A' padded-512 ≈ 11.4, materially below r1 no-spec baseline ≈ 18.7–20) |

**Consequence: AOT production image remains BLOCKED** — Phase A did not clear the
performance bar, so Phase B is NOT unlocked by this validation despite the functional
PASS. The functional unlock is retained as the correctness/backport baseline for the
next kernel or scheduling iteration; AOT build only resumes once a candidate meets the
performance gate (kernel/backport + functional + performance all PASS) and re-passes
§8.1 + §8.2 on the produced artifact.

### 9.3 note (amended)
Native topk256 C1 ≈ 11.57 tok/s ≈ A' padded-512 ≈ 11.4 tok/s — the topk=256 entry itself
does not regress vs the A' shim, but both sit materially below the r1 no-spec C1 ≈
18.7–20 tok/s. The DSpark K=5 spec-decode overhead (~3% acceptance) is the dominant
gap; the §9.3 A'-relative expectation was met but the r1-relative performance target was
NOT, which is the basis of the performance FAIL above.

## Artifacts retained

- Probe + harness scripts (Node0 `~/b1/`): `gen.py`, `c_cases.py`, `c1_256.py`,
  `needle.py` / `needle2.py`, `dbg.py`; logs `c_cases.log`, `c1_256.log`, `needle.log`,
  `needle2.log`, `tp2up-deepseek.log`.
- Extracted `.so` trees: `~/b1/so_out/` (Node0) and `/home/eye/so_out/` (Node1).
- Boot-produced artifacts inside `tp2-node0` / `tp2-node1` containers (mtime 1788698241 /
  1788698240, size 838120).