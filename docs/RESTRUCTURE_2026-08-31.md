# RESTRUCTURE_2026-08-31

## 目的

把原本分家的兩套 GB10 管理邏輯統一進**單一 repo**：

- `ai-gb10-cluster`（2-node TP2 叢集，`scripts/tp2-*`）
- `gb10-single`（單節點 `gb10` CLI + `runtimes.d`）

統一後 repo 命名為 **`ai-gb10-cluster-runtime-manager`**，由兩個獨立 CLI 構成：
`bin/gb10`（叢集）與 `bin/gb10-single`（單節點）。

## 搬遷

| 舊位置 | 新位置 |
|---|---|
| `ai-gb10-cluster/scripts/tp2-*` | `scripts/`（不變，路徑可攜） |
| `ai-gb10-cluster/tp2.env(.example)` | `tp2.env(.example)`（不變） |
| `ai-gb10-cluster/docs/TP2_DEPLOYMENT_2026-08-30.md` | `docs/`（不變） |
| `ai-gb10-cluster` CLI（無） | **新** `bin/gb10`（thin layer 於 scripts/tp2-*） |
| `gb10-single/bin/gb10` | **改寫** 為 `bin/gb10-single`（加 node0/node1） |
| `gb10-single/runtimes.d/*.conf` | `runtimes.d/*.conf`（改名 + 加 placeholder） |

## CLI 語法

- **`gb10`**（叢集，Node0）：`use/start/stop/restart/status/logs/smoke/load/list/doctor`，
  綁 TP2 profile `27b|35b`（+ placeholder `deepseek/qwen38flash/glm53flash`）。
- **`gb10-single`**（單節點，node0 本機 / node1 ssh）：
  `use|start|stop|restart|status|logs|doctor`，首參數為 `node0|node1`，
  第二參數為 `runtimes.d/` 內 runtime（`27b|35b|comfyui|deepseek|qwen38flash|glm53flash|minimaxh3`）。

## Placeholder 政策

尚未部署的模型/版本一律在 conf 標 `PLACEHOLDER=true`，CLI 遇到時印
「not deployed yet」並退出，**不得**觸碰不存在的 stack。目前 placeholder：
`deepseek`、`qwen38flash`、`glm53flash`。

## 主機部署

Repo 僅存在 **Node0** `~/ai-gb10-cluster-runtime-manager/`。`~/bin/gb10` 與
`~/bin/gb10-single` 為 symlink 指向 repo 的 `bin/`。單節點 compose/stack 仍放
`~/docker-stacks/`（`.gitignore` 排除 secrets/models）。

## 待辦 / 風險

- Node1 已部署 `comfyui-aeon` stack（`gb10-single use node1 comfyui`，Flux 2 Dev，見 `docs/ComfyUI_DEPLOYMENT_2026-08-31.md`）。
- 新模型（deepseek/glm5）落地後需把 placeholder conf 補上 STACK/COMPOSE 並取消 `PLACEHOLDER`.
- `gb10-single node1` 依賴 `~/.ssh/id_gb10_cluster`（沿用 TP2 key）。
