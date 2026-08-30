# ai-gb10-cluster-runtime-manager

DGX Spark **GB10 runtime manager** — 統合 **2-node TP2 叢集** 與 **單節點 runtimes** 於單一 repo。

- **`bin/gb10`** — TP2 叢集 CLI（thin layer 於 `scripts/tp2-*`）
- **`bin/gb10-single`** — 單節點 CLI（`node0` 本機 / `node1` 經 ssh）
- **`runtimes.d/*.conf`** — 兩者共用的單節點 runtime 定義
- **`scripts/tp2-*`** — 叢集部署腳本（ver detail 見 `docs/TP2_DEPLOYMENT_2026-08-30.md`）

## Topology

```
Node0  spark-25d5  (192.168.23.215 / 10.0.101.101 interconnect)  rank0 = API server :8000
Node1  spark-8095  (192.168.23.129 / 10.0.101.102 interconnect)  rank1 = headless worker
```

Node0 is single side of control: every `tp2-*`/`gb10` command runs on Node0 and
orchestrates Node1 over `ssh -i ~/.ssh/id_gb10_cluster eye@10.0.101.102`.
`gb10-single` can also drive single-node compose on `node0` (local) or `node1` (ssh).

**Where the repo lives:** checkout on **Node0 only**, at
**`~/ai-gb10-cluster-runtime-manager/`** — under home, *outside* `~/docker-stacks/`
(which stays purely for deployed runtime stacks). Node1 does **not** host the repo;
Node0 reaches it over ssh. Node1 only needs the image + model dirs + sudo docker.

## Cluster CLI — `gb10`

```bash
gb10 list                     # profile list (27b/35b + placeholders)
gb10 use 27b                  # default; TP2 up (cold ~7-15 min), waits /health
gb10 use 35b                  # switch exclusive cluster profile
gb10 stop                     # tp2-down (both nodes)
gb10 restart [27b|35b]
gb10 status                   # both nodes, RDMA, KV, health
gb10 logs                     # follow tp2-node0
gb10 smoke                    # chat smoke
gb10 load                     # concurrent load
gb10 doctor
```

## Single-node CLI — `gb10-single`

```bash
gb10-single list [node0|node1]
gb10-single use {node0|node1} <runtime>     # exclusive switch
gb10-single start {node0|node1} <runtime>   # start
gb10-single stop {node0|node1} [runtime]
gb10-single restart {node0|node1} [runtime]
gb10-single status [node]
gb10-single logs {node0|node1} <runtime>
gb10-single doctor
```

Runtimes (`runtimes.d/*`):

| conf | id | group | status |
|---|---|---|---|
| `27b.conf` | 27b | llm (exclusive) | deployed (MTP) |
| `35b.conf` | 35b | llm (exclusive) | deployed (DFlash) |
| `deepseek.conf` | deepseek | llm | **placeholder** |
| `qwen38flash.conf` | qwen38flash | llm | **placeholder** |
| `glm53flash.conf` | glm53flash | llm | **placeholder** |
| `comfyui.conf` | comfyui | image | **placeholder** (new version pending) |
| `minimaxh3.conf` | minimaxh3 | video | **placeholder** |

Placeholders print "not deployed yet"; they are CLI skeletons until models/versions land.

## Config

- `tp2.env` (gitignored) — cluster knobs: `IMG`, `MASTER_ADDR/PORT`, `NODE0/1_IP`,
  `NCCL_*`, `API_PORT`, `VLLM_API_KEY`, `SUDO_PASS`. Copy from `tp2.env.example`.
- Single-node compose files live under `~/docker-stacks/` on each host (referenced
  by `runtimes.d/*.conf` via `STACK_DIR`/`COMPOSE_FILE`).

## Non-negotiables (see docs/TP2_DEPLOYMENT_2026-08-30.md)

- Same image slim **byte-identical on BOTH nodes** for TP2.
- RoCE v2 env as pinned in `tp2.env`/`tp2-common.sh`.
- `--disable-custom-all-reduce` load-bearing cross-node.
- `--kv-cache-dtype fp8_e4m3` (DFlash/DFlash2 non-causal drafter can't use NVFP4 KV).
- GB10 `nvidia-smi` is unreliable — trust engine metrics.

## Layout

```
bin/            gb10 (cluster), gb10-single (single-node)
scripts/        tp2-up|down|status|smoke|load + tp2-common.sh
runtimes.d/     *.conf runtime definitions (shared by gb10-single)
state/          last-runtime markers (gitignored)
docs/           TP2_DEPLOYMENT_2026-08-30.md + RESTRUCTURE notes
tp2.env.example cluster config template (NEVER commit real values)
```
