# Recipe archive — `deepseek-nvfp4` (+ `-tune`) on `eugr/spark-vllm-b12x:nightly-20261006`

**Archived 2026-11-05** (user decision: the image is replaced, no rollback to this
version is planned; only the settings/patches are kept, the image itself is
deleted from both nodes to reclaim disk).

## Identity

| item | value |
|---|---|
| profiles | `deepseek-nvfp4` (service) ＋ `deepseek-nvfp4-tune` (A/B lane, `.conf` + `.conf.base`) |
| model | `nvidia/DeepSeek-V4-Flash-0731-NVFP4` (~172 GB / 48 shards, MIT, non-gated — **still live**) |
| image | `eugr/spark-vllm-b12x:nightly-20261006` |
| node0 digest | `sha256:036c307678dad66adbbb5a627ec8d3a0d8f9bbf8be4a679e6e441a0b2e1ab2c3` |
| node1 digest | `sha256:dc0e9faa61d4d4133e07ec81536107b99ab741c49f198b5d4fafbc8f2466b2eb` |
| image size | 11.2 GB compressed (29 layers) |
| vLLM | `0.1.dev21554+geda1715e9.d20261006` (commit `eda1715e9`, fork `dev/karmic-kraken`) |
| FlashInfer | `f8d3729e9c85d20afdf4a1e672771cdb157e0e33` |
| B12X kernels | standalone wheel `lukealonso/b12x@master` (pre-2026-10-07 migration) |
| contract | TP2 · 262144 ctx · 8 seqs · KV fp8 · `--load-format safetensors` · `SECURITY_OPT=("seccomp=unconfined")` (b12x loader needs io_uring) |

## The one runtime patch (archived here, pre-re-pin)

`patches/eugr-spark-vllm-b12x/hotfix-dspark-draft-mxfp4.py` — the **2026-10-06
version**, pinned to vllm `0.1.dev21554+geda1715e9` (stock `ea48801f…`/5257 B →
patched `7099e162…`/6478 B). It pre-memoizes `_resolved_moe_quant_algo = ""` on
the DSpark draft's own quant instance so the in-checkpoint MXFP4 draft experts
take `Mxfp4MoEMethod` instead of the target's NVFP4 path (upstream
vllm-project/vllm#49133 was closed unmerged).

**The live tree now carries a different pin** of the same file for
`nightly-20261102` (`0.1.dev21830+g8244d1c44`, stock `a92f4243…`/5756 B →
patched `56dcb6ca…`/6977 B). Do **not** mix the two: the script is
single-image pinned and fails closed on a version/hash mismatch.

## Why it was retired

Superseded on **2026-11-05** by `nightly-20261102` (same four-lane bump).
Evidence: `handoff.md` §2026-11-05, `docs/BENCHMARKS.md` §12.

## Benchmark record at archival time (this image, `nightly-20261006`)

`bench-c` `BENCH_IGNORE_EOS=1`, 400 tok/stream, x3 medians:

| C | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | Σ |
|---|---|---|---|---|---|---|---|---|---|
| tok/s | 47.1 | 69.0 | 71.3 | 90.7 | 87.1 | 110.1 | 123.4 | 129.9 | **728.7** |
| accept % | 47.6 | 50.0 | 41.4 | 43.0 | 44.8 | 43.9 | 48.8 | 45.2 | — |

- temp-0 acceptance gate (pos0 ≥ 0.3): pos0 0.629 / avg 27.0 % (2026-10-08 records).
- prefix-hit **44.8×**; 200K cold prefill 1984.6 tok/s; KV pool 344,195 tok;
  cold start ~21 min.
- On `nightly-20261102`: Σ **732.2** (+0.5 %), acceptance 46.6 %, pos0 83.0 %,
  prefix-hit 48.4×, self-boot prints `dspark-draft-mxfp4: applied` and
  `Using 'B12X_MXFP4_MXFP8' Mxfp4 MoE backend`.

## Contents

- `deepseek-nvfp4.conf` / `deepseek-nvfp4-tune.conf` / `deepseek-nvfp4-tune.conf.base`
  — byte-identical archived profiles (SHA256 in `_overdue_recipe/README.md`)
- `docker-compose.deepseek-nvfp4.yml`, `docker-compose.deepseek-nvfp4-tune.yml`
  — deploy-contract composes re-rendered from these confs on 2026-11-05
  (`--api-key` → `<REDACTED:from-cluster.env>`)
- `patches/eugr-spark-vllm-b12x/hotfix-dspark-draft-mxfp4.py` — the 2026-10-06 pin

## Restore (if ever needed)

```sh
cp _overdue_recipe/deepseek-nvfp4_eugr-spark-vllm-b12x-nightly-20261006_20261105/deepseek-nvfp4.conf \
   cluster-profiles.d/deepseek-nvfp4.conf
mkdir -p patches/eugr-spark-vllm-b12x
cp _overdue_recipe/deepseek-nvfp4_eugr-spark-vllm-b12x-nightly-20261006_20261105/patches/eugr-spark-vllm-b12x/*.py \
   patches/eugr-spark-vllm-b12x/
docker pull eugr/spark-vllm-b12x:nightly-20261006           # node0
docker save eugr/spark-vllm-b12x:nightly-20261006 | \
  ssh -i ~/.ssh/id_gb10_cluster eye@10.0.101.102 docker load  # -> node1
# re-pin both digests, then:
~/bin/gb10 use deepseek-nvfp4
```

Because the hotfix is single-image pinned, restoring this recipe **requires**
restoring this archived hotfix as well — otherwise the container fails closed at
start (which is the intended safety behaviour).
