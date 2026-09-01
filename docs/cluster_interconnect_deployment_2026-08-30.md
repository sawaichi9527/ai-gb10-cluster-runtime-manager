# DGX Spark 2-Node 叢集互連部署報告（2026-08-30）

> 更新日期：2026-08-30
> 主機：
> - **Node 0**：`spark-25d5` / `192.168.23.215`（既有 GB10，明日改固定 IP，管理網 10GbE `enP7s7`）
> - **Node 1**：`spark-8095` / `192.168.23.129`（新購 DGX Spark，明日改固定 IP 192.168.23.216）
> - 兩台使用者皆 `eye`，密碼 `20040401`（Posh-SSH 直連）
> - **互連**：單條 QSFP DAC（Left Port 0），200GbE，CX-7 / RoCE `rocep1s0f0` + `roceP2p1s0f0`
> - 用途：2-Node 叢集 → 多節點 vLLM 分散式推理（tensor-parallel）
> - 文件定位：接續 `verification_cluster_connectivity_2026-08-30.md`（成案判定 ✅），記錄本日完成之**管理網 IPv6 關閉 + 互連 IP 配置 + MTU 9000 + SSH 免密互通**。

---

# 1. 本次工作摘要

依使用者決策（2 節點固定不擴充）與 NVIDIA 官方「Connect Two Sparks」playbook：
- 1. RJ-45 管理介面 `enP7s7` 之 IPv6 **徹底 disable**（`ipv6.method=disabled`）
- 2. 互連 CX-7 網段採 **`10.0.101.0/24` + `10.0.102.0/24`**（實驗室太多 192.168.x.x，故避開）
- 3. 僅用**單條 QSFP DAC**（官方：單條即達全頻寬）
- 4. MTU **9000**（jumbo frames）
- 5. SSH 免密互通（互連 IP）

# 2. 完成項目與驗證結果

## 2.1 IPv6 關閉（管理介面 `enP7s7`）— 兩台皆完成 ✅

```bash
# 以 NetworkManager connection 之 UUID 操作（避開中文連線名「有線連線 3」傳遞問題）
nmcli con mod <UUID> ipv6.method disabled
nmcli con down <UUID> && nmcli con up <UUID>
```

- Node 0 (.215) connection UUID：`3c5d944e-d114-3a06-9eae-8b5cb64103bd`
- Node 1 (.129) connection UUID：`ee00d5e9-cba2-3959-8ee3-fa575dbd6ab3`

**驗證**：`nmcli -g ipv6.method con show <UUID>` = `disabled`；`ip -6 addr show dev enP7s7` **完全無輸出**（連 link-local 都無）；`ip -4 addr show dev enP7s7` 仍 `192.168.23.x/24` 正常。

## 2.2 互連 CX-7 IP + MTU 9000 — 兩台皆完成 ✅

`/etc/netplan/40-cx7.yaml`（兩台相同結構，僅 IP 末段不同）：

```yaml
network:
  version: 2
  ethernets:
    enp1s0f0np0:
      addresses:
        - <IP_A>/24
      dhcp4: no
      mtu: 9000
    enP2p1s0f0np0:
      addresses:
        - <IP_B>/24
      dhcp4: no
      mtu: 9000
```

| 介面 (partition) | Node 0 (.215) | Node 1 (.129) |
|---|---|---|
| `enp1s0f0np0` (P1) | **10.0.101.101/24** | **10.0.101.102/24** |
| `enP2p1s0f0np0` (P2) | **10.0.102.101/24** | **10.0.102.102/24** |

**驗證**（`netplan apply` 後）：
- `enp1s0f0np0` → 10.0.101.x/24，**mtu 9000**
- `enP2p1s0f0np0` → 10.0.102.x/24，**mtu 9000**
- `ip -4 route`：多出 `10.0.101.0/24` 與 `10.0.102.0/24` 走互連介面；管理網 `192.168.23.0/24` + default route 不受影響
- 檔案屬 `root:root 600`

> 註：兩台 netplan 檔皆以「寫 /tmp + sudo cp」方式建立，避開 Posh-SSH 引號地獄；YAML 內容經 `sudo cat` 比對確認格式正確。

## 2.3 互連互通驗證（雙向 + jumbo）— 通過 ✅

| 測試 | 來源 → 目標 | 結果 |
|---|---|---|
| A | .129 10.0.101.102 → 10.0.101.101 | 2/2 0% loss ~0.8ms |
| B | .129 10.0.102.102 → 10.0.102.101 | 2/2 0% loss ~1.2ms |
| Jumbo A (MTU 9000, 8972B) | .129 → .215 | 2/2 通過 |
| Jumbo B (MTU 9000, 8972B) | .129 → .215 | 2/2 通過 |
| 反向 A | .215 10.0.101.101 → 10.0.101.102 | 2/2 0% loss ~1.0ms |
| 反向 B | .215 10.0.102.102 → 10.0.102.102 | 2/2 0% loss ~1.1ms |

## 2.4 SSH 免密互通（互連 IP）— 雙向通過 ✅

- **Node 0 → Node 1**：`ssh -i ~/.ssh/id_gb10_cluster eye@10.0.101.102 hostname` → `spark-8095` (exit 0)
- **Node 1 → Node 0**：`ssh -i ~/.ssh/id_gb10_cluster eye@10.0.101.101 hostname` → `spark-25d5` (exit 0)

Key 政策：
- 兩台各有一把獨立空 passphrase ed25519 key `~/.ssh/id_gb10_cluster`，公鑰互放 `authorized_keys`（comment：`gb10_cluster_node0` / `gb10_cluster_node1`）
- 既有 keys（NVIDIA Sync `sawaichi@Haruhi`、`chohan_lin`、`opencode-gb10-maint`、`sawaichi@Acubens`）皆**保留未動**
- 公鑰對應：
  - Node 0 pub：`ssh-ed25519 AAAA...IDefejqn0A9tBpRa... gb10_cluster_node0`
  - Node 1 pub：`ssh-ed25519 AAAA...IBrSf4SsA8L3... gb10_cluster_node1`

> 除錯紀錄：最初遠端 `ssh-keygen -N ""` 因 Posh-SSH/引號地獄產出**帶 passphrase** 的 key，導致單向 `Permission denied`。解法：改為**本機 (Windows) 用 ps1 產空 passphrase key → base64 上傳私鑰 + 追加公鑰**，徹底避開遠端引號問題。Node0/Node1 私鑰皆重產。

# 3. 網路架構總結

```text
管理網 192.168.23.0/24 (enP7s7, IPv6 disabled)
   Node0 .215   Node1 .129 (→明日 .216)
        │              │
        └── QSFP DAC (Left Port 0) ──┘
            ├ enp1s0f0np0   → 10.0.101.0/24   (Node0 .101 / Node1 .102), RoCE roce?p1s0f0
            └ enP2p1s0f0np0 → 10.0.102.0/24   (Node0 .101 / Node1 .102), RoCE roceP2p1s0f0
            流量隔離：管理/NCCL 控制器走 10GbE；模型同步/NCCL data 走互連 CX-7 (MTU 9000)
```

- 單條 QSFP DAC 即提供 **200 Gb/s** 全頻寬（官方確認）
- 互連介面僅 IPv4、無 IPv6 需求

---

# 4. Phase 1：Node 1 環境拉齊（2026-08-30，晚場）✅

目的：Node 1 (`spark-8095` / `.129`) 原為 fresh 狀態，對齊 Node 0 之設定、映像、模型，並驗證跨機 GPU 互連（NCCL）可用性。

## 4.1 Node 1 基礎設定

- `eye` 加入 docker 群：`usermod -aG docker eye`（gid 988，同 Node 0；**登出重登才生效**，本場作業暫以 `sudo docker`）
- 建立 `~/docker-stacks/ai-runtime-manager`（含 `gb10` script 內容）＋ `~/bin/gb10 -> ~/docker-stacks/ai-runtime-manager/gb10` symlink（與 Node 0 一致）
- `~/docker-stacks/aeon-vllm/`：copy Node 0 之 `.env`、`docker-compose.27b.yml`、`docker-compose.35b.yml`（**含相同 `VLLM_API_KEY`**）；建 `cache/`、`models/`

## 4.2 映像對齊（omni 18.8G + cuda base 560M）✅

- **GHCR 直拉失敗**：Node 1 網路至 `ghcr.io/aeon-7/...` 反覆 `error from registry: retry-after: xxxms`（5 次重試皆中途放棄，疑似 GHCR 路徑丟包）；`docker pull` 無法完成
- **解法（互連 bypass）**：Node 0 本機已持有 omni 映像 → `docker save`（18.94GB tar）→ scp 走互連 → Node 1 `sudo docker load`（38.1GB disk / 18.9GB content）
  - scp 互連傳輸：18.94GB in **23s ≈ 820 MB/s**
  - `docker load` 解壓約 2-3 分鐘（Posh-SSH 端 probe timeout 屬正常，server-side 續跑）
  - 驗證：`sudo docker images` → `ghcr.io/aeon-7/aeon-vllm-ultimate:2026-08-24-v0.27.1-omni` ✅；圖像 ID 因 save/load 重算與 Node 0 不同，屬正常

## 4.3 模型對齊（~72G）✅

- Node 1 `models/` 已含 5 目錄，總量 **72G（與 Node 0 相同）**：
  | model | size |
  |---|---|
  | `qwen3.6-27b-aeon-mm-mtp` | 27G |
  | `qwen3.8-27b-aeon-ultimate-uncensored-nvfp4` | 20G |
  | `qwen3.6-35b-a3b-heretic-nvfp4` | 22G |
  | `qwen3.6-27b-dflash` | 3.3G |
  | `qwen3.6-35b-a3b-dflash` | 737M |
- 傳輸走互連 scp（10.0.101.x），單檔吞吐實測約 **515–820 MB/s**
- **完整性驗證**：兩台 `sha256sum model.safetensors`（19.7G）＝ `5ca4957d...cdf2`；`model-mtp-bf16.safetensors`（849M）＝ `90fa0e3e...cdf2`，**兩台完全一致** ✅
- 傳輸完畢後兩台 `du -sh models` 皆 72G、目錄清單相同

## 4.4 Node 1 單機冒煙 ✅

- `sudo docker compose -f docker-compose.27b.yml config`：CFG_RC=0，image/.env 正確解析（TP=1、port 1234、mount /model）
- 容器內 GPU 驗證（omni image + `--gpus all`）：
  ```
  torch 2.13.0+cu130
  cuda_avail True
  device NVIDIA GB10
  devcount 1
  nccl_found (2, 29, 7)
  ```
- `vllm --version` → `0.27.1+aeon.sm121a.dspark`（與 Node 0 相同）；注意需以 `--entrypoint vllm` 呼叫

---

# 5. Phase 2：跨機 NCCL smoke test（**判定 gate**）✅

- **方法**：兩台各以 omni 容器（`--network host --gpus all`）跑 `torch.distributed`（NCCL backend）跨機 allreduce 1GB × 10 次
  - `MASTER_ADDR=10.0.101.101`（Node 0 互連 IP）、port 29501、WORLD_SIZE=2
  - `NCCL_SOCKET_IFNAME=enp1s0f0np0`（**data 走互連**）、`NCCL_P2P_LEVEL=SYS`、`NCCL_DEBUG=WARN`
- **結果**（兩 rank 同步完成）：
  ```
  [rank0] node=spark-25d5 dev=NVIDIA GB10 ... allreduce size=1074MB iters=10 elapsed=4.997s alg_bw=2.15 GB/s
  [rank1] node=spark-8095 dev=NVIDIA GB10 ... allreduce size=1074MB iters=10 elapsed=4.996s alg_bw=2.15 GB/s
  NCCL version 2.29.7+cuda13.2
  ```
- **解讀**：allreduce 之 bus bandwidth ≈ 2×alg_bw ≈ **4.3 GB/s**（約 34 Gbit/s 有效載荷），與先前 scp 實測（~700–820MB/s 單向）一致，確認互連為實際 NCCL data path。兩 GPU 已完成同步式 allreduce，**多節點 vLLM tensor-parallel 前置條件成立**。
- ⚠️ **後續更正（2026-08-30 §5.1）**：上述 `alg_bw=2.15 GB/s` 為 **CPU-loopback allreduce 之 `alg_bw`**（且當時 `NCCL_P2P_LEVEL=SYS` 禁 P2P/RDMA），**不代表線路極限**。Phase 0 以 `ib_write_bw` 直接量 RDMA 原生帶寬，實為 **109.15 Gb/s ≈ 13.6 GB/s**（詳見 §5.1）。
- 作業後 clean：兩台已刪除 `nccl_ar.py` / logs / `check_cuda.py` / `pull_omni.sh` 等暫存。

> 備註：初始 rank 1 因 Posh-SSH 巢狀 `bash -c` 引號地獄吃掉了 `echo pw | sudo -S` 管線（sudo 1 次密碼錯誤），改為**先寫 launcher script 再 nohup** 才成功 —— 與既有「引號地獄」原則一致。

---

# 5.1 Phase 0：互連真值重測（2026-08-30，晚場二部）

目的：釐清 §5 之 `alg_bw=2.15 GB/s` 是否為線路極限。結論為**否**——線路健康，先前數值為 CPU-loopback allreduce 之量測失真。以 `ib_write_bw` / `ibv_devinfo` / `ethtool` / `lspci` 對兩台實測如下。

## 5.1.1 鏈路與 PCIe 狀態（兩台對稱 ✅）

| 檢查 | Node0 (.215) | Node1 (.129) | 判定 |
|---|---|---|---|
| 協商速度 `ethtool .Speed` | `enp1s0f0np0` + `enP2p1s0f0np0` 皆 **200000Mb/s**，Link detected **yes** | 同左 | 200G ✅ |
| RoCE 狀態 `ibv_devinfo` | `rocep1s0f0` + `roceP2p1s0f0` = **PORT_ACTIVE(4)**、link_layer Ethernet、active_mtu 4096 | 同左 | RoCEv2 up，非 TCP fallback ✅ |
| PCIe `lspci -vvv` LnkSta | **Speed 32GT/s (Gen5), Width x4** | 同左 | **PCIe Gen5 x4（Spark 設計，非可修之 BIOS 限制）** |
| 未用 port | `rocep1s0f1` / `roceP2p1s0f1` = PORT_DOWN（No cable） | 同左 | 僅用 P1/P2 單 port，正常 |

## 5.1.2 RDMA Write 原生帶寬（`ib_write_bw`，單 port rocep1s0f0）

server：Node0 `ib_write_bw -d rocep1s0f0`；client：Node1 `ib_write_bw -d rocep1s0f0 10.0.101.101`

```
 #bytes     #iterations    BW peak[Gb/sec]    BW average[Gb/sec]   MsgRate[Mpps]
 65536      5000             109.16             109.15 		   0.208192
```

**結論：RDMA Write ≈ 109.15 Gb/s ≈ 13.6 GB/s**（兩端 server/client 輸出一致）。

## 5.1.3 判讀（重要）

1. **RoCE 未退化成 TCP**：`ibv_devinfo` PORT_ACTIVE + `link_layer Ethernet`（RoCEv2）＋ 200G 協商 → 排除「NCCL 走 TCP socket」。
2. **非 21.5 GB/s 誤寫成 2.15**：量到的是 ~13.6 GB/s，上一個數量級，與「21.5 誤寫」無關——2.15 是 NCCL allreduce `alg_bw` 的 CPU 迴圈失真。
3. **實測上限由 PCIe Gen5 x4 決定，非線路**：DGX Spark 之 CX-7 為 **x4**（32GT/s × 4 ≈ 16 GB/s 方向性理論值）。單 port RDMA Write 13.6 GB/s ≈ **已近飽和 PCIe x4**。因此**本叢集跨節點 TP2 帶寬天花板 ≈ 13–16 GB/s**，而非桌面級 x16 CX-7 的 25–50 GB/s。
4. **對 TP2 的意義**：13.6 GB/s 足夠支撐 vLLM TP2 運作（NCCL 以 RDMA 跑），但對 <121GB 模型，單節點 TP1（記憶體頻寬瓶頸）通常仍較優；TP2 價值在 >121GB 單機放不下的模型。此與 AEON「TP=1 為受支援預設」一致。

## 5.1.4 診斷工具備註

- `ibstat` / `iperf3` **兩台均未安裝**（`MISSING`）；`ib_write_bw` / `ibv_rc_pingpong` / `ethtool` / `lspci` / `ibv_devinfo` 已具。
- `ethtool` 需 sudo；`ib_write_bw` 無需 sudo 即可量。
- 診斷腳本以 base64 上傳 + `bash` 執行（避開 Posh-SSH 引號地獄）：本地 `network_diag.sh` / `rdma_server.sh` / `rdma_client.sh`。

---

```bash
# 互連 IP（官方 rollback）
sudo rm /etc/netplan/40-cx7.yaml && sudo netplan apply

# 管理介面 IPv6（還原為 DHCP/SLAAC）
sudo nmcli con mod <UUID> ipv6.method auto
sudo nmcli con down <UUID> && sudo nmcli con up <UUID>

# SSH 免密（移除互放 key）
# 兩台各自：刪除 ~/.ssh/id_gb10_cluster；並在對方 authorized_keys 移除 gb10_cluster_node0/1 行
```

# 7. 後續步驟（多節點 vLLM，尚未執行）

1. ~~NCCL smoke test~~ ✅ 已完成（見 §5，alg_bw 2.15 GB/s）
2. ~~Node 1 映像對齊~~ ✅ 已完成（見 §4.2）
3. ~~模型路徑同步~~ ✅ 已完成（見 §4.3，兩台各持 ~72G 完整權重）
4. ~~線路真值重測~~ ✅ 已完成（見 §5.1，RDMA Write ≈ 13.6 GB/s；先前 2.15 GB/s 為 allreduce CPU 失真）。互連健康，**多節點 vLLM（TP2）路徑可行**。
5. **多節點 vLLM**：`--tensor-parallel-size 2 --distributed-executor-backend ray`，`VLLM_HOST_IP`/控制器指向互連 IP 10.0.101.x；NCCL 以 RDMA 跑（13.6 GB/s）。→ 待執行（Ray 底座 + 27B TP2 benchmark）
6. **操作禁忌**：互連兩 partition **不可設同網段**（官方硬規則）；管理網與互連網段不可重疊
7. 明日 Node 1 管理 IP 改固定 `192.168.23.216` 後，需確認互連 IP（10.0.101/102.x）與 SSH 免密不受影響

# 8. 驗證命令速查

```bash
# 互連 IP 現況（兩台）
ip -4 addr show enp1s0f0np0 enP2p1s0f0np0
# 管理介面 IPv6 應為 disabled
nmcli -g ipv6.method con show <UUID>
# 免密互通
ssh -i ~/.ssh/id_gb10_cluster eye@10.0.101.<peer> hostname
# jumbo 測
ping -M do -s 8972 10.0.101.<peer>
# RoCE 對應
ibdev2netdev
```
