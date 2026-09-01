# GB10 多節點 vLLM — 連線與硬體驗證報告

> 日期：2026-08-30
> 驗證人：Windows 工作站經 Posh-SSH `eye/20040401` 直連兩台
> 目的：確認新購 DGX Spark 可連、更新設定一致、QSFP 互連成立，為後續多節點 vLLM (tensor-parallel) 奠定第一關

## 主機識別

| 角色 | IP (現行) | hostname | OS |
|---|---|---|---|
| 既有 GB10 | 192.168.23.215 | spark-25d5 | Ubuntu 24.04.4 LTS |
| 新購 Spark | 192.168.23.129 (明日→固定 .216) | spark-8095 | Ubuntu 24.04.4 LTS |

兩台帳密相同：`eye / 20040401`。SSH 均成功（Phase 0 通過）。

## Phase 1 — 更新設定一致性（重點）

| 檢查項 | .215 (既有) | .129 (新) | 一致? |
|---|---|---|---|
| GPU | NVIDIA GB10 | NVIDIA GB10 | ✅ |
| 驅動 `nvidia-smi` | 580.173.02 | 580.173.02 | ✅ **一致** |
| Kernel | 6.17.0-1031-nvidia | 6.17.0-1031-nvidia | ✅ |
| OS | Ubuntu 24.04.4 LTS | Ubuntu 24.04.4 LTS | ✅ |
| Docker | 29.2.1 | 29.2.1 | ✅ |
| nvidia-container-toolkit | 1.20.0 | 1.20.0 | ✅ |
| RDMA/BP 韌體 (fw_ver) | 28.45.4028 | 28.45.4028 | ✅ |
| SuperNIC 型號 | 0x15b3 / 0x1021 (BlueField/ConnectX-7) | 同 | ✅ |
| unattended-upgrades 自動更新 | 未啟用 | 未啟用 | ✅ |
| 已拉取容器映像 | omni ＋ v0.27.1 ＋ comfyui ＋ cuda13 | 無 | 差異(正常，新機未部署) |

**結論**：所有關鍵軟韌體元件一致。驅動、kernel、docker、toolkit、RDMA 韌體完全相同，自動更新策略皆為關閉 → **無更新不同步的叢集隱患**。GPU 驅動非 dpkg 套件（DGX 內建），故 dpkg 查無 nvidia 行屬正常。

## Phase 2 — QSFP 互連 / RDMA

### 高速互連埠（BlueField SuperNIC）
兩台各有 4 個 RDMA HCA，其中 `roceP2p1s0f0`（netdev `enP2p1s0f0np0`）為對外 QSFP 叢集互連埠，**兩端皆 ACTIVE**：

| 埠 (netdev / HCA) | .215 | .129 | 說明 |
|---|---|---|---|
| enP2p1s0f0np0 / roceP2p1s0f0 | **carrier=1, PORT_ACTIVE** | **carrier=1, PORT_ACTIVE** | **互連成立（200G）** |
| enp1s0f0np0 / rocep1s0f0 | carrier=1, ACTIVE | carrier=1, ACTIVE | 200G，第二組 f0 |
| enp1s0f1np1 / rocep1s0f1 | DOWN | DOWN | 未接線 |
| enP2p1s0f1np1 / roceP2p1s0f1 | DOWN | DOWN | 未接線 |

- 兩台 `enP2p1s0f0np0` 皆 carrier=1、speed **200000 (200Gb/s)**、operstate up、mlx5_ib RDMA 驅動在載。
- **實體 + RDMA 層互連成立**：相同 fw 28.45.4028、兩端 PORT_ACTIVE、200G link。

### IP 現況
- 管理埠 `enP7s7`：.215 = 192.168.23.215/24，.129 = 192.168.23.129/24（明日改 .216）。
- **互連介面（enP2p1s0f0np0 等）目前無 IP 指派**（僅 link-local）→ 預期狀態，叢集部署時需配對接 IP（如 10.0.x.x）才能跑跨機 NCCL / 多節點 vLLM。

## 成案判定

**✅ 通過**。兩台可 SSH 連、元件版本一致、QSFP 互連在實體與 RDMA 層皆 ACTIVE（200G）。多節點 vLLM 所需之互連基礎已具備。

## 下一階段注意事項（尚待完成，本次未做）

1. **配互連 IP**：在兩台 `enP2p1s0f0np0` 配對接 IPv4（例 10.0.0.215 / 10.0.0.129），用 IPoIB/RoCE 互通。
2. **NCCL smoke test**：跨兩台跑 `nccl-tests` 或 `torch.distributed` allreduce 驗證 over QSFP 頻寬 → 才正式成案 gate（本次因無 IP 未執行）。
3. **HDK/PyTorch/NCCL 容器映像對齊**：多節點 vLLM 需兩節點用**相同 AEON 映像**（omni 2026-08-24-v0.27.1-omni）。新 Spark 尚未拉取。
4. **明日改 IP 至 .216 後**需 re-verify 管理連結與互連（保持 command/IP 不變）。
5. **多節點 vLLM 做法**：vLLM 採 `--tensor-parallel-size 2` + 跨機 MPI/NCCL 啟動，兩節點掛相同 vLLM 映像與共享模型路徑（或各持模型複本）。

## 操作忌（新增）
- 互連介面目前無 IP 是正常，不要手動亂配後就以為互連壞。
- 別在未跑 NCCL smoke 前就認定多節點 vLLM 一定可行——RDMA ACTIVE 與跨機 NCCL 頻寬是兩件事。
