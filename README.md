# ai-gb10-cluster-runtime-manager

DGX Spark **GB10 runtime manager** — 統合 **2-node TP2 叢集** 與 **單節點 runtimes** 於單一 repo。

- **`bin/gb10`** — TP2 叢集 CLI（thin layer 於 `scripts/cluster-*`）
- **`bin/gb10-single`** — 單節點 CLI（`node0` 本機 / `node1` 經 ssh）
- **`runtimes.d/*.conf`** — 單節點 runtime 定義
- **`cluster-profiles.d/*.conf`** — TP2 叢集 profile 定義（data-driven registry）
- **`scripts/cluster-*`** — 叢集部署腳本（ver detail 見 `docs/TP2_DEPLOYMENT_2026-08-30.md`）


## Deployed services & benchmark results (latest image)

> 2026-09-13 實測。27B/35B 原使用 `ghcr.io/aeon-7/aeon-vllm-ultimate:2026-09-11-v0.29.0-omni`；DeepSeek 為歷史主力線 `ghcr.io/anemll/dspark-vllm-gx10:0.1.1` 之既有結果。
> **2026-09-19 更新**：35B 與 27B 皆已升 `2026-09-18-v0.29.0-omni` 並重新實測（單節點啟用 `VLLM_USE_V2_MODEL_RUNNER=1`）。27B 先前在 09-18 首次冷啟動觸及 `cluster-up` 硬編碼 2400s health timeout 而誤判失敗（非 image 缺陷）；已改為 profile 可覆寫（27B `HEALTH_TIMEOUT=3600`），實測 READY 並完成 cluster/single benchmark。

### 已部署服務

| service | 模型 / 方法 | image | endpoint | 狀態 |
|---|---|---|---|---|
| 27B single (TP1) | `qwen3.8-27b-aeon-ultimate-uncensored-nvfp4-mixed` + DFlash2 n=7 | `2026-09-18-v0.29.0-omni` | `:1234/v1` | deployed（09-19 實測） |
| 27B cluster (TP2) | 同上 | `2026-09-18-v0.29.0-omni` | `http://192.168.23.215:1234/v1` | deployed（09-19 實測） |
| 35B single (TP1) | `qwen3.6-35b-a3b-heretic-nvfp4` + DFlash n=6 | `2026-09-18-v0.29.0-omni` | `:1234/v1` | deployed（09-19 實測） |
| 35B cluster (TP2) | 同上 | `2026-09-18-v0.29.0-omni` | `http://192.168.23.215:1234/v1` | deployed（09-19 實測） |
| DeepSeek V4 Flash cluster (TP2) | `deepseek-v4-flash-0731-official` + DSpark n=7 | `anemll/dspark-vllm-gx10:0.1.1` | `http://192.168.23.215:1234/v1` | deployed (mainline) |

### 27B v0.29.0-omni (bench-c C1-C8, MAX_TOKENS=2048; 245k cold prefill)

> **2026-09-19 實測（09-18 image；single node0 與 TP2 cluster 皆本次重測）。** 先前的「啟動失敗」為 `cluster-up` 硬編碼 2400s health timeout 短於 27B 首次冷啟動（~40min）所致，非 image 缺陷；已改為 profile 可覆寫（27B `HEALTH_TIMEOUT=3600`，詳見 `docs/ISSUE_27B_BROKEN_2026-09-18_IMAGE_2026-09-19.md`）。與 09-11 基準相比：single 幾近持平（245k 348.7 vs 347.2）；cluster 於 C1/C2/C4 與長 prefill 略升、C3/C8 略降（run-to-run 變異，各 stream completion 長度不同）。

| C | Single tok/s | Cluster tok/s | Speedup |
|---|---|---|---|
| 1 | 23.8 | 46.1 | 1.94x |
| 2 | 36.6 | 76.8 | 2.10x |
| 3 | 54.4 | 87.9 | 1.62x |
| 4 | 80.3 | 105.3 | 1.31x |
| 8 | 117.2 | 172.7 | 1.47x |
| 245k prefill (tok/s) | 348.7 | 611.5 | 1.75x |

### 35B v0.29.0-omni (bench-c C1-C8, MAX_TOKENS=2048; 245k cold prefill)

> **2026-09-19 實測（09-18 image；single node0 與 TP2 cluster 皆本次重測）。** `scripts/bench-c.sh` / `bench-ctx.sh` 實測。與 09-11 基準大致持平（single 245k 2580.1 vs 2601.0）。註：先前記錄的 245k prefill `180398.5` tok/s 為量測瑕疵（245k 僅 ~1.4s，不可能）；本次 cluster 62.0s / 3951.9、single 95.0s / 2580.1 為可信值。

| C | Single tok/s | Cluster tok/s | Speedup |
|---|---|---|---|
| 1 | 76.2 | 120.6 | 1.58x |
| 2 | 115.5 | 177.4 | 1.54x |
| 3 | 148.2 | 218.5 | 1.47x |
| 4 | 198.6 | 291.6 | 1.47x |
| 8 | 262.7 | 416.4 | 1.59x |
| 245k prefill (tok/s) | 2580.1 | 3951.9 | 1.53x |

> 245k prefill 用 `bench-ctx.sh 245000 1`（max_tokens=1 純 prefill）。
> **踩雷（已自動化）**：兩節點 FlashInfer autotune cache 若不一致，TP2 會在 `Autotuning` 階段集體死鎖（rank0 高 GPU spin-wait、rank1 閒置，`/health` 永不 ready）。`scripts/cluster-up` 現於啟動前呼叫 `ensure_autotune_cache_symmetry`（`cluster-common.sh`）：兩節點指紋不一致就自動清掉並重 tune；可用 `AUTOTUNE_CACHE_POLICY=verify|always-clear|off`（預設 `verify`）調整。單節點 runtime 另用獨立 cache root（`~/.cache/vllm*`），不污染 TP2 路徑（`gb10-single-boot` 會檢查）。

### DeepSeek V4 Flash fp8 mainline (bench-c C1-C8; 200K probe) - 歷史結果

| C | Cluster tok/s | Acceptance |
|---|---|---|
| 1 | 35.3 | 23.8% |
| 2 | 45.9 | 25.1% |
| 4 | 56.6 | 31.0% |
| 8 | 85.9 | 26.8% |
| 200K prefill (tok/s) | 1600.3 | - |

> 完整報告：maintenance repo `docs/BENCHMARK_27B_MIXED_V3_V029_SINGLE_CLUSTER_2026-09-13.md`、`docs/BENCHMARK_35B_V029_SINGLE_CLUSTER_2026-09-13.md`；DeepSeek 見 handoff §23.3。

## Topology

```text
Node0  spark-25d5  (192.168.23.215 / 10.0.101.101 interconnect)  rank0 = API server :1234
Node1  spark-8095  (192.168.23.216 / 10.0.101.102 interconnect)  rank1 = headless worker
```

**Unified LLM endpoint convention** — all LLM runtimes serve the OpenAI-compatible
API on **port 1234, sharing one `VLLM_API_KEY`** (set the same value in `cluster.env`
and both nodes' `docker-stacks/config/standalone.env`):

| runtime | endpoint | notes |
|---|---|---|
| TP2 cluster (rank0) | `http://192.168.23.215:1234/v1` | this repo, `API_PORT=1234` |
| Node0 single LLM | `http://192.168.23.215:1234/v1` | `gb10-single use node0 27b\|35b` |
| Node1 single LLM | `http://192.168.23.216:1234/v1` | `gb10-single use node1 27b\|35b` |

TP2 and the single-node LLMs are **mutually exclusive** (same port):
`gb10 use` frees both nodes' singles; a `gb10-single use/start` on either node
tears down TP2 first. Image/video runtimes (ComfyUI / MiniMaxH3) are out of scope.

Node0 is single side of control: every `cluster-*`/`gb10` command runs on Node0 and
orchestrates Node1 over `ssh -i ~/.ssh/id_gb10_cluster eye@10.0.101.102`.
`gb10-single` can also drive single-node compose on `node0` (local) or `node1` (ssh).

**Where the repo lives:** checkout on **Node0 only**, at
**`~/workspace/ai-gb10-cluster-runtime-manager/`** — under home, *outside* `~/docker-stacks/`
(which stays purely for deployed runtime stacks). Node1 does **not** host the repo;
Node0 reaches it over ssh. Node1 only needs the image + model dirs + sudo docker.

## Cluster CLI — `gb10`

```bash
gb10 list                     # profile list (27b/35b + placeholders)
gb10 use 27b                  # default; TP2 up (cold ~7-15 min), waits /health
gb10 use 35b                  # switch exclusive cluster profile
gb10 stop                     # cluster-down (both nodes)
gb10 restart [27b|35b]
gb10 status                   # both nodes, RDMA, KV, health
gb10 inspect <profile>        # sanitized resolved-profile report (dry-run)
gb10 logs                     # follow cluster-node0
gb10 smoke                    # chat smoke
gb10 load                     # concurrent load
gb10 doctor
```

Current deployed TP2 profiles are 27B, 35B and DeepSeek (data-driven from
`cluster-profiles.d/`). `qwen38flash` and `glm53flash` are single-node placeholders
until their runtimes land.

### TP2 profile registry (completed 2026-09-05)

The TP2 profile layer is a **data-driven cluster profile registry** (see
`docs/TP2_PROFILE_REFACTOR_VALIDATION_2026-09-05.md`):

```text
cluster-profiles.d/
  27b.conf          # deployed + live-validated (world_size=2, maxlen 262144)
  35b.conf          # deployed + live-validated (world_size=2, maxlen 131072)
  deepseek.conf     # deployed + live-validated (fp8 DSpark mainline, 256k ctx)
```

Each conf carries the **profile-scoped image** and per-model vLLM arguments, loaded once by
`scripts/cluster-common.sh`. Rank0 builds the authoritative argv; rank1 receives it as a
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

DeepSeek V4 Flash 0731 is deployed as a **TP2 cluster profile** (the legacy single-node
`runtimes.d/deepseek.conf` placeholder was retired 2026-09-05). The mainline uses the
official fp8 checkpoint (`deepseek-v4-flash-0731-official`, weights under
`~/docker-stacks/models`) with the public Anemll runtime
`ghcr.io/anemll/dspark-vllm-gx10:0.1.1`, SHA256SUMS-gated and validated with a real
generation. It serves the unified :1234 API at 256K context (same-model DSpark draft,
8 concurrent streams). The retired NVFP4 AEON lane is archived to
`~/_archieve/cluster-profiles.d/deepseek-nvfp4.conf`.

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

- `cluster.env` (gitignored) — cluster/site knobs: `MASTER_ADDR/PORT`, `NODE0/1_IP`,
  `NCCL_*`, `API_PORT`, `VLLM_API_KEY`, `SUDO_PASS`. Each cluster profile may override/select
  its own image; the profile-scoped `IMG` in `cluster-profiles.d/*.conf` wins over the
  cluster default when present.
- Single-node compose files live under `~/docker-stacks/` on each host (referenced
  by `runtimes.d/*.conf` via `STACK_DIR`/`COMPOSE_FILE`).

## Non-negotiables (see docs/TP2_DEPLOYMENT_2026-08-30.md)

- Same resolved image **byte-identical on BOTH nodes** for TP2.
- RoCE v2 env as pinned in `cluster.env`/`cluster-common.sh`.
- `--disable-custom-all-reduce` load-bearing cross-node.
- Existing Qwen TP2 profiles use `--kv-cache-dtype fp8_e4m3`; do not generalize that into a
  universal rule for future model families. DeepSeek gets its own profile policy.
- Prefix caching remains deliberately OFF for TP2 27B DFlash2; see
  `[REDACTED:entropy:42].md`.
- GB10 `nvidia-smi` is unreliable — trust engine metrics.

## Layout

```text
bin/            gb10 (cluster), gb10-single (single-node)
scripts/        cluster-up|down|status|smoke|load + cluster-common.sh
runtimes.d/     *.conf single-node runtime definitions
cluster-profiles.d/  data-driven TP2 profile registry (active ownership by cluster-common.sh)
state/          last-runtime marker files (gitignored, empty = normal)
docs/           deployment notes, ADRs, restructure + active handoffs
cluster.env.example cluster/site config template (NEVER commit real values)
```

### state/ — 執行期「最後狀態」標記（非架構內容，空目錄屬正常）

`state/` 是 **執行期快取／便利記憶層**，不是部署契約；`docker-stacks/` 的 compose 與
`cluster-profiles.d/*.conf` 才是 source of truth。這個目錄刻意 **不納入版本控制**
（`.gitignore`），因此**內容為空、甚至目錄不存在，都是正常狀態**——代表「目前沒有可
記憶的上次選擇」，CLI 會落回預設值（如 TP2 預設 `27b`）。

目前已定義的標記檔：

- **`state/last-runtime`** — 由 `bin/gb10-single` 寫入／讀取（`STATE=${REPO_DIR}/state`）。
  - **寫入**：`use`／`start` 成功啟動一個單機 runtime 後，寫入 `node/runtime_ID`
    （例如 `node1/minimaxh3`），記住「這個 node 上次選了哪個 runtime」。
  - **讀取**：後續 `use`／`start` 在某台 node 上未指定 runtime 時，以此作為上次選擇的
    回退依據（`awk -F/ '{print $2}'` 拆出 runtime ID）；若無此檔，則視為「該 node
    沒有 active 或 previous runtime」並提示。
  - 注意：TP2 主動使用時，單機端**不該**有 `last-runtime`（單機與 TP2 互斥，見上方
    Unified LLM endpoint 說明）。

- **`state/last-cluster-profile`** — 由 `bin/gb10` 讀取
  （`P="${2:-$(cat "${REPO_DIR}/state/last-cluster-profile" ... || echo 27b)}"`），
  在未指定 TP2 profile 時，回退到「上次選用的 cluster profile」，否則預設 `27b`。

**所以如果你檢查時發現 `state/` 是空目錄：那不是沒用的架構，而是正常的初始／乾淨
狀態**，只是還沒觸發過任何寫入動作（或某台 node 從未成功 `use`／`start` 過）。只要
`gb10 use 27b`、`gb10-single use node1 minimaxh3` 這類動作真正跑過一次，對應的標記檔
就會出現；之後記得它是執行期產物即可。
