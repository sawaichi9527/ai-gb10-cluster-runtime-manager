# Recipe archive — `deepseek-vision` on `eugr/spark-vllm-b12x:nightly-20261006`

**Archived 2026-11-05** (user decision: the image is replaced, no rollback to this
version is planned; only the settings are kept, the image itself is deleted from
both nodes to reclaim disk).

## Identity

| item | value |
|---|---|
| profile | `deepseek-vision` (DeepSeek-V4-Flash-Vision-EXP ablit, native multimodal, TP2, `:1234`) |
| image | `eugr/spark-vllm-b12x:nightly-20261006` |
| node0 digest | `sha256:036c307678dad66adbbb5a627ec8d3a0d8f9bbf8be4a679e6e441a0b2e1ab2c3` |
| node1 digest | `sha256:dc0e9faa61d4d4133e07ec81536107b99ab741c49f198b5d4fafbc8f2466b2eb` |
| image size | 11.2 GB compressed (29 layers) |
| vLLM | `0.1.dev21554+geda1715e9.d20261006` (commit `eda1715e9`, fork `dev/karmic-kraken`) |
| FlashInfer | `f8d3729e9c85d20afdf4a1e672771cdb157e0e33` |
| B12X kernels | standalone wheel `lukealonso/b12x@master` (pre-2026-10-07 migration) |
| weights | `~/docker-stacks/models/deepseek-v4-flash-vision-exp-ablit` (167.8 GB / 48 shards, shared pool — **still live**) |
| runtime patches | none (native vision; the old Anemll-era MiaAI hotfixes are NOT part of this recipe) |

## Why it was retired

Superseded on **2026-11-05** by `eugr/spark-vllm-b12x:nightly-20261102`
(vllm `0.1.dev21830+g8244d1c44`, B12X inside FlashInfer `9873d7a3…`) as part of
the four-lane b12x image bump. Evidence: `handoff.md` §2026-11-05,
`docs/BENCHMARKS.md` §12.

## Benchmark record at archival time (this image, `nightly-20261006`)

`bench-c` `BENCH_IGNORE_EOS=1`, 400 tok/stream, x3 medians (promotion boot B1):

| C | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | Σ |
|---|---|---|---|---|---|---|---|---|---|
| tok/s | 39.7 | 43.9 | 55.7 | 69.7 | 74.9 | 74.1 | 81.2 | 96.1 | **535.3** |

- acceptance 25.0 %; prefix-hit **50.9×** (byte-identical);
  131K–261K prefill +9~14 % vs the old Anemll route; KV pool 413,967 tok;
  `CUDAGRAPH_CAPTURE=56` (upstream shipped 48 — C7/C8 fell out of the capture range).
- On `nightly-20261102`: Σ **541.9** (+1.2 %), C1 −16.4 % / C7 +12.6 % (single-cell
  scatter, lane historically moves 10–17 % per cell between boots),
  prefix-hit 44.1×, images 1img C=1 47.3 / C=8 151.0 tok/s.

## Contents

- `deepseek-vision.conf` — byte-identical archived profile (SHA256 in
  `_overdue_recipe/README.md`)
- `docker-compose.deepseek-vision.yml` — deploy-contract compose re-rendered from
  this conf on 2026-11-05 (`--api-key` → `<REDACTED:from-cluster.env>`)

## Restore (if ever needed)

```sh
cp _overdue_recipe/deepseek-vision_eugr-spark-vllm-b12x-nightly-20261006_20261105/deepseek-vision.conf \
   cluster-profiles.d/deepseek-vision.conf
docker pull eugr/spark-vllm-b12x:nightly-20261006          # node0
docker save eugr/spark-vllm-b12x:nightly-20261006 | \
  ssh -i ~/.ssh/id_gb10_cluster eye@10.0.101.102 docker load # -> node1
# re-pin both digests after measuring, then:
~/bin/gb10 use deepseek-vision
```

Caveats: Docker Hub may prune the tag (the digests above are the identity
record); the weights pool is shared with the live lane and untouched.
