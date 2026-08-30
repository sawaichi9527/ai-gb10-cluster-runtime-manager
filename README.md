# ai-gb10-cluster

DGX Spark **GB10 2-node cluster TP2 deployment** (main branch). Cross-node vLLM
tensor-parallel (TP=2) over a 200GbE RoCE interconnect, using the **native `mp`
backend** — **no Ray, no LiteLLM**.

## Topology

```
Node0  spark-25d5  (192.168.23.215 / 10.0.101.101 interconnect)   rank0 = API server :8000
Node1  spark-8095  (192.168.23.129 / 10.0.101.102 interconnect)   rank1 = headless worker
```

Node0 is the **single side of control**: every `tp2-*` script runs on Node0 and
orchestrates Node1 over `ssh -i ~/.ssh/id_gb10_cluster eye@10.0.101.102`.

**Where the repo lives:** checkout `ai-gb10-cluster` on **Node0 only**, at
**`~/ai-gb10-cluster/`** — under the home dir, deliberately *outside*
`~/docker-stacks/` so that directory stays purely for deployed runtime stacks
(aeon-vllm, ai-runtime-manager, comfyui-aeon). This repo *manages* the cluster, it
is not a stack itself. **Node1 does not host the repo** — Node0 reaches it purely
over ssh to launch/stop the headless worker; Node1 only needs the image + model
dirs + sudo docker.

## Profiles (verified 2026-08-30)

| profile | body | drafter | dflash n | max-model-len | GMU | num-seqs | API |
|---|---|---:|---:|---:|---:|---:|---|
| **27b** (default) | `qwen3.8-27b-aeon-ultimate-uncensored-nvfp4` | `qwen3.8-27b-dflash2` | 7 | 262144 | 0.85 | 8 | 8000 |
| **35b** | `qwen3.6-35b-a3b-heretic-nvfp4` | `qwen3.6-35b-a3b-dflash` | 11 | 131072 | 0.80 | 16 | 8000 |

## Quick start

```bash
# 1. configure (never commit real secrets)
cp tp2.env.example tp2.env && $EDITOR tp2.env   # set IMG, keys; export SUDO_PASS

# 2. bring up (27B default; or pass 35b)
scripts/tp2-up            # 27B
scripts/tp2-up 35b        # 35B-A3B

# 3. operate
scripts/tp2-status        # both nodes, RDMA, KV, health
scripts/tp2-smoke         # chat smoke (+ reasoning token note)
scripts/tp2-load          # 8-way x 3 concurrent load
scripts/tp2-down          # stop & remove both containers
```

> Cold start is ~10-15 min (weight load + FlashInfer autotune + torch.compile).
> `tp2-up` waits for `/health` 200 and reports READY.

## Key non-negotiables (see docs/TP2_DEPLOYMENT_2026-08-30.md)

- **Same image slim on BOTH nodes** — must be byte-identical for TP2 to work.
- RoCE v2 interconnect env: `NCCL_SOCKET_IFNAME`/`GLOO_SOCKET_IFNAME=enp1s0f0np0`,
  `NCCL_IB_HCA=rocep1s0f0:1`, `NCCL_IB_GID_INDEX=3`.
- `--disable-custom-all-reduce` is load-bearing for the cross-node path.
- `--kv-cache-dtype fp8_e4m3` (DFlash/DFlash2 non-causal drafter cannot use NVFP4 KV).
- MoE model: TP split is global, EP splits MoE experts across both nodes (rank0/1 **+ EP rank0/1**).
- GB10 `nvidia-smi` reports util/mem = 0%/N/A — trust engine metrics instead
  (SignDecoding acceptance, KV pool, concurrent throughput).

## Layout

```
scripts/          tp2-up|down|status|smoke|load + tp2-common.sh
docs/             TP2_DEPLOYMENT_2026-08-30.md (verified results & facts)
tp2.env.example   machine-local knobs (NEVER commit real values)
```

Single-node deployments live in the sibling repo **`829522/gb10-single`**.
