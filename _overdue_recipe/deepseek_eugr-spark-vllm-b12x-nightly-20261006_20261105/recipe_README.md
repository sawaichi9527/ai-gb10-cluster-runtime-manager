# Recipe archive — `deepseek` on `eugr/spark-vllm-b12x:nightly-20261006`

**Archived 2026-11-05** (user decision: the image is replaced, no rollback to this
version is planned; only the settings are kept, the image itself is deleted from
both nodes to reclaim disk).

## Identity

| item | value |
|---|---|
| profile | `deepseek` (DeepSeek-V4-Flash-0731 dspark-ablit, TP2, `:1234`) |
| image | `eugr/spark-vllm-b12x:nightly-20261006` |
| node0 digest | `sha256:036c307678dad66adbbb5a627ec8d3a0d8f9bbf8be4a679e6e441a0b2e1ab2c3` |
| node1 digest | `sha256:dc0e9faa61d4d4133e07ec81536107b99ab741c49f198b5d4fafbc8f2466b2eb` |
| image size | 11.2 GB compressed (29 layers) |
| vLLM | `0.1.dev21554+geda1715e9.d20261006` (commit `eda1715e9`, fork `local-inference-lab/vllm`, ref `dev/karmic-kraken`) |
| FlashInfer | `f8d3729e9c85d20afdf4a1e672771cdb157e0e33` |
| B12X kernels | **standalone wheel** `lukealonso/b12x@master` (`b12x_from_pypi: 0`) — i.e. *before* eugr's 2026-10-07 "B12X is now part of FlashInfer" migration |
| weights | `~/docker-stacks/models/deepseek-v4-flash-0731-dspark-ablit` (166.9 GB / 48 shards, shared pool — **still live**, not archived) |
| runtime patches | none (this recipe deliberately has no `CMD_WRAPPER` / `SYNC_DIRS`) |

## Why it was retired

Superseded on **2026-11-05** by `eugr/spark-vllm-b12x:nightly-20261102`
(vllm `0.1.dev21830+g8244d1c44`, B12X inside FlashInfer `9873d7a3…`) as part of
the four-lane b12x image bump. Full replacement evidence:
`handoff.md` §2026-11-05 and `docs/BENCHMARKS.md` §12.

## Benchmark record at archival time (this image, `nightly-20261006`)

`bench-c` `BENCH_IGNORE_EOS=1`, 400 tok/stream, **x3 medians**, thinking default on:

| C | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | Σ |
|---|---|---|---|---|---|---|---|---|---|
| tok/s | 43.2 | 58.9 | 72.2 | 88.9 | 93.2 | 100.3 | 116.7 | 119.9 | **693.3** |

- acceptance 33.4 %; prefix-hit **38.5×** (byte-identical); garble soak 3/3;
  261K prefill 1947.1 tok/s; cold start ~12.8 min; KV pool 407,775 tok
  (the KV number is from the 2026-10-09 promotion run).
- On `nightly-20261102` the same recipes measured Σ **687.6** (−0.8 %),
  cold start 17m46s (see `docs/BENCHMARKS.md` §12.1).

## Contents

- `deepseek.conf` — byte-identical archived profile (pre-bump; SHA256 in
  `_overdue_recipe/README.md`)
- `docker-compose.deepseek.yml` — deploy-contract compose re-rendered from this
  conf on 2026-11-05 (`--api-key` replaced with `<REDACTED:from-cluster.env>`)

## Restore (if ever needed)

```sh
cp _overdue_recipe/deepseek_eugr-spark-vllm-b12x-nightly-20261006_20261105/deepseek.conf \
   cluster-profiles.d/deepseek.conf
# node0: re-pull the dated tag (Docker Hub retains it), verify the digest
docker pull eugr/spark-vllm-b12x:nightly-20261006
docker image inspect eugr/spark-vllm-b12x:nightly-20261006 | grep -A2 RepoDigests
# node1: transfer over CX7 (direction: node0 -> node1)
docker save eugr/spark-vllm-b12x:nightly-20261006 | \
  ssh -i ~/.ssh/id_gb10_cluster eye@10.0.101.102 docker load
# then re-pin IMG_SHA256 / IMG_SHA256_NODE1 to the freshly measured digests
~/bin/gb10 use deepseek
```

**Caveats**

1. Docker Hub may eventually prune `nightly-20261006`; the digest pins above are
   the only guarantee of identity if it still exists.
2. Do **not** restore the `deepseek-nvfp4` hotfix from this archive into a live
   `nightly-20261102` tree: that hotfix is single-image pinned to
   `0.1.dev21554`, and the live one was re-pinned to `0.1.dev21830`.
3. The weights directory listed above is shared with the live lane and was not
   touched by this archival.
