# ai-gb10-cluster-runtime-manager

DGX Spark **GB10 runtime manager** — 統合 **2-node TP2 叢集** 與 **單節點 runtimes** 於單一 repo。

- **`bin/gb10`** — TP2 叢集 CLI（thin layer 於 `scripts/tp2-*`）
- **`bin/gb10-single`** — 單節點 CLI（`node0` 本機 / `node1` 經 ssh）
- **`runtimes.d/*.conf`** — 單節點 runtime 定義
- **`cluster-profiles.d/*.conf`** — TP2 叢集 profile 定義（data-driven registry）
- **`scripts/tp2-*`** — 叢集部署腳本（ver detail 見 `docs/TP2_DEPLOYMENT_2026-08-30.md`）

## Topology

```text
Node0  spark-25d5  (192.168.23.215 / 10.0.101.101 interconnect)  rank0 = API server :1234
Node1  spark-8095  (192.168.23.216 / 10.0.101.102 interconnect)  rank1 = headless worker
```

**Unified LLM endpoint convention** — all LLM runtimes serve the OpenAI-compatible
API on **port 1234, sharing one `VLLM_API_KEY`** (set the same value in `tp2.env`
and both nodes' `docker-stacks/aeon-vllm/.env`):

| runtime | endpoint | notes |
|---|---|---|
| TP2 cluster (rank0) | `http://192.168.23.215:1234/v1` | this repo, `API_PORT=1234` |
| Node0 single LLM | `http://192.168.23.215:1234/v1` | `gb10-single use node0 27b\|35b` |
| Node1 single LLM | `http://192.168.23.216:1234/v1` | `gb10-single use node1 27b\|35b` |

TP2 and the single-node LLMs are **mutually exclusive** (same port):
`gb10 use` frees both nodes' singles; a `gb10-single use/start` on either node
tears down TP2 first. Image/video runtimes (ComfyUI / MiniMaxH3) are out of scope.

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
gb10 inspect <profile>        # sanitized resolved-profile report (dry-run)
gb10 logs                     # follow tp2-node0
gb10 smoke                    # chat smoke
gb10 load                     # concurrent load
gb10 doctor
```

Current deployed TP2 profiles are 27B and 35B (data-driven from `cluster-profiles.d/`).
`deepseek` is a TP2-cluster placeholder until its model/image contract is validated;
`qwen38flash` and `glm53flash` are single-node placeholders until their runtimes land.

### TP2 profile registry (completed 2026-09-05)

The TP2 profile layer is a **data-driven cluster profile registry** (see
`docs/TP2_PROFILE_REFACTOR_VALIDATION_2026-09-05.md`):

```text
cluster-profiles.d/
  27b.conf          # deployed + live-validated (world_size=2, maxlen 262144)
  35b.conf          # deployed + live-validated (world_size=2, maxlen 262144)
  deepseek.conf     # safe placeholder (not deployed)
```

Each conf carries the **profile-scoped image** and per-model vLLM arguments, loaded once by
`scripts/tp2-common.sh`. Rank0 builds the authoritative argv; rank1 receives it as a
shell-escaped array (no eval). Networking/orchestration (TP2, SSH, RoCE/NCCL, API/auth,
resource exclusion) stays generic and cluster-owned. The existing 27B and 35B serves are the
regression controls and retained their effective launch behavior during the refactor.

Implementation handoff: **`[REDACTED:entropy:56].md`** (completed).

Separation of concerns:

```text
image / kernel patches
        !=
cluster profile / model settings
        !=
TP2 orchestration / networking
```

The DeepSeek image work is a **separate follow-up** after the structural refactor is merged and
27B/35B revalidated. Planned base/derived lineage:

```text
ghcr.io/aeon-7/aeon-vllm-ultimate:2026-08-24-v0.27.1-omni
    -> 2026-09-04-v0.27.1-omni-ds4flash0731-r1
```

`deepseek` is a **TP2 cluster profile only** (the legacy single-node
`runtimes.d/deepseek.conf` placeholder was retired 2026-09-05). `gb10 use deepseek`
fails safely as a placeholder until the image/model + a real generation are validated.

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
| `qwen38flash.conf` | qwen38flash | llm | **placeholder** |
| `glm53flash.conf` | glm53flash | llm | **placeholder** |
| `comfyui.conf` | comfyui | image | deployed (Node1, Flux 2 Dev) |
| `minimaxh3.conf` | minimaxh3 | video (exclusive) | deployed (FL2VA) |

`use` on an exclusive runtime frees every OTHER active exclusive runtime on that
node across groups (e.g. starting `minimaxh3` on node1 also stops a running
`comfyui` there) and auto-tears down an active TP2 cluster first (做法 B).
Placeholders print "not deployed yet"; they are CLI skeletons until models/versions land.

## Config

- `tp2.env` (gitignored) — cluster/site knobs: `MASTER_ADDR/PORT`, `NODE0/1_IP`,
  `NCCL_*`, `API_PORT`, `VLLM_API_KEY`, `SUDO_PASS`. Each cluster profile may override/select
  its own image; the profile-scoped `IMG` in `cluster-profiles.d/*.conf` wins over the
  cluster default when present.
- Single-node compose files live under `~/docker-stacks/` on each host (referenced
  by `runtimes.d/*.conf` via `STACK_DIR`/`COMPOSE_FILE`).

## Non-negotiables (see docs/TP2_DEPLOYMENT_2026-08-30.md)

- Same resolved image **byte-identical on BOTH nodes** for TP2.
- RoCE v2 env as pinned in `tp2.env`/`tp2-common.sh`.
- `--disable-custom-all-reduce` load-bearing cross-node.
- Existing Qwen TP2 profiles use `--kv-cache-dtype fp8_e4m3`; do not generalize that into a
  universal rule for future model families. DeepSeek gets its own profile policy.
- Prefix caching remains deliberately OFF for TP2 27B DFlash2; see
  `[REDACTED:entropy:42].md`.
- GB10 `nvidia-smi` is unreliable — trust engine metrics.

## Layout

```text
bin/            gb10 (cluster), gb10-single (single-node)
scripts/        tp2-up|down|status|smoke|load + tp2-common.sh
runtimes.d/     *.conf single-node runtime definitions
cluster-profiles.d/  data-driven TP2 profile registry (active ownership by tp2-common.sh)
state/          last-runtime markers (gitignored)
docs/           deployment notes, ADRs, restructure + active handoffs
tp2.env.example cluster/site config template (NEVER commit real values)
```