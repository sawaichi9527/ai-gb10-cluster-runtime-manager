# ai-gb10-cluster-runtime-manager

DGX Spark **GB10 runtime manager** — 用一份 repo 管理 **2-node TP2 叢集**與**單節點 runtime**。
模型與啟動參數全部資料驅動（`cluster-profiles.d/*.conf`），CLI 只是便利層，**compose／kit 才是部署合約**。

```text
Node0  spark-25d5  192.168.23.215 / 10.0.101.101   rank0 · API :1234 · 單側控制面
Node1  spark-8095  192.168.23.216 / 10.0.101.102   rank1 · headless worker
```

**五個要點**

- 兩個 CLI：`bin/gb10`（叢集）、`bin/gb10-single`（單節點）。
- TP2 有 **10 條服務 lane** ＋ 1 條 A/B 專用；全部互斥，同一時間只有一條在線。
- 對外一律 `http://192.168.23.215:1234/v1`、model id **`aeon`**、共用同一把 `VLLM_API_KEY`。
- 三條 lane 用 `LAUNCH_STYLE=kit`（自帶啟動器，**刻意沒有 compose**）。
- 本文只留**每個模型最新一次**量測；完整歷史在 [`docs/BENCHMARKS.md`](docs/BENCHMARKS.md)。

## 1. 30 秒上手

| 想做的事 | 指令 |
|---|---|
| 看有哪些 lane | `gb10 list` |
| 切／啟動一條 TP2 lane | `gb10 use <lane>`（冷啟 2–14 分，等到 `/health` 200 才回報 READY） |
| 看現在誰在線／打一發 smoke | `gb10 status` · `gb10 smoke` |
| 停掉／重啟上次的 lane | `gb10 stop` · `gb10 restart [lane]`（無參數＝`state/last-cluster-profile`） |

**現役（2026-10-22 10:30 CST 實測）＝ `qwen38flash-tensorfold`**：`gb10 status` → `ready`、node0 up · node1 up、
image `tensorfold-qwen38fn:zig-db28187`、`/v1/models` = `aeon`；`state/boot-ready` = `08:31:09 READY`、`kit.*.rc=0`。
「現役」只表示**此刻在線**——它與 `qwen38flash` 是**對等 lane**（無主/備），1017 的兩條同理。

## 2. 目前狀態

### 2.1 節點、endpoint 與互斥

| runtime | endpoint | 說明 |
|---|---|---|
| TP2 叢集（rank0） | `http://192.168.23.215:1234/v1` | 本 repo，`API_PORT=1234` |
| Node0 單節點 LLM | `http://192.168.23.215:1234/v1` | `gb10-single use node0 27b\|35b` |
| Node1 單節點 LLM | `http://192.168.23.216:1234/v1` | `gb10-single use node1 27b\|35b` |
| ComfyUI（Node1） | `http://192.168.23.216:8188` | `gb10-single use node1 comfyui-jdaln` |

- 所有 LLM runtime 共用 **port 1234 + 同一把 key**（`cluster.env` 與兩節點 `standalone.env` 必須一致）。
- TP2 與單節點 LLM **互斥**：`gb10 use` 會釋放兩節點 singles；`gb10-single use/start` 會先拆 TP2。
  `use` 一個 exclusive runtime 時，會停掉**同節點所有其他 exclusive runtime（跨 group）**——
  例：node1 起 `comfyui-jdaln` 會停掉 node1 的 `27b`。
- Node0 是單側控制面：所有 `gb10`／`cluster-*` 都在 Node0 執行，經
  `ssh -i ~/.ssh/id_gb10_cluster eye@10.0.101.102`（CX7）操作 Node1。**Node1 不存放 repo**。

### 2.2 TP2 lane 總表（10 條服務 ＋ 1 條 A/B）

| lane | 引擎／image | 權重 | 契約 | 最新實測 |
|---|---|---|---|---|
| `27b` | vLLM · `aeon-vllm-ultimate:2026-09-18-v0.29.0-omni` | 27B NVFP4-mixed ＋ DFlash2 n=7 | 262144 · 8 | C1 **46.1** → C8 **172.7** · 245k prefill 611.5 · 冷啟 261 s · 詳 **§5.1** |
| `35b` | 同上 | 35B-A3B NVFP4 ＋ DFlash n=6 | 262144 · 8 | C1 **120.6** → C8 **416.4** · 245k prefill 3951.9 · 冷啟 380 s · 詳 **§5.1** |
| `deepseek` | vLLM · `eugr/spark-vllm-b12x:latest` | `deepseek-v4-flash-0731-dspark-ablit` | 262144 · 8 · KV fp8 | C1 **43.2** → C8 **119.9**（Σ 693.3）· 261K prefill 1947.1 · 12.8 min · 詳 **§5.2** |
| `deepseek-nvfp4` | 同上（digest 雙節點 pin） | `DeepSeek-V4-Flash-0731-NVFP4` ＋ DSpark k=5 | 262144 · 8 · KV fp8 | C1 **47.1** → C8 **129.9**（2.76×）· 200K prefill 1984.6 · ~21 min · 詳 **§5.4** |
| `deepseek-vision` | 同上 | `…vision-exp-ablit`（原生 vision）＋ DSpark k=6 | 262144 · 8 · KV fp8 | C1 **39.7** → C8 **96.1**（Σ 535.3）· 261K prefill 1823.7 · 詳 **§5.3** |
| `qwen38flash` | vLLM · `vllm-openai:qwen38-flash-next` | `qwen3.8-flash-next-nvfp4`（125B）＋ MTP n=3 | 262144 · 8 · KV fp8 | C1 **45.5** → C8 **196.8** · 245K prefill 2592.5 · 13 min 58 s · 詳 **§5.5** |
| `qwen38flash-tensorfold` | TensorFold · `…tensorfold:zig-db28187-f3e1300f4f62` | 同一份 checkpoint（MTP drafts） | 262144 · 8 · KV fp8 | C1 **55.5** → C8 **284.4** · 261K prefill 2989 · **1 min 53 s** · 詳 **§5.6** |
| `mimo26flash` | vLLM · `tonyd2wild/vllm-glm53-flash:sm121-v11-dflash2` | `mimo-v2.6-flash-mopd`（MXFP4 QAT）＋ DFlash2 n=7 | 262144 · 8 · KV fp8 | C1 **29.3** → C8 **63.1** · 245K prefill 724.3 · 詳 **§5.7** |
| `dsv41flash-exl3-vllm` | MiaAI vLLM kit · `…1017-exl3-2x-dgx-sparks:2.9bpw` | 1017 EXL3 2.9bpw ＋ Engram 47/48（no-spec） | 262144 · 8 · vision | C1 **23.8** → C8 **90.2** · 255K prefill 1250.1 · ~6.4 min · 詳 **§5.8** |
| `dsv41flash-tensorfold` | TensorFold · `deepseek41-tensorfold:1017`（自建） | 同一份 1017 ＋ packed Engram（drafts off） | 262144 · 8 · vision | C1 **41.9** → C8 **158.9** · 255K prefill 1029.3 · ~5.8 min · 詳 **§5.8** |

> A/B 專用（`gb10 list` 另列、**不是服務**）：`deepseek-nvfp4-tune`（單旋鈕實驗 lane，會拆掉現役）。
> `deployed` 只意味「已部署並實測過」，不代表同時在跑；數字口徑與歷史見 [`docs/BENCHMARKS.md`](docs/BENCHMARKS.md)，跨取樣模式／跨 prefix-caching 狀態**不可直接互比**。

### 2.3 對等 lane 對照（同一份權重、不同引擎；非主/備）

#### DeepSeek-V4.1-Flash 1017

同一份 `LibertAIDAI/DeepSeek-V4.1-Flash-1017-EXL3-2.9bpw`（43 shards）＋官方 1017 Engram 47/48：

| | `dsv41flash-exl3-vllm` | `dsv41flash-tensorfold` |
|---|---|---|
| 引擎 | MiaAI vLLM kit（`SPEC_METHOD=none`） | TensorFold（x00byte recipe，drafts off） |
| image | `ghcr.io/miaai-lab/…:2.9bpw`（`2f0cf3ad…`） | `deepseek41-tensorfold:1017`（自建，`nvcr.io/nvidia/pytorch:26.07-py3` 基底） |
| decode C1…C8 | 23.8 / 36.1 / 46.2 / 63.9 / 60.0 / 87.8 / 82.2 / **90.2** | **41.9 / 64.1 / 74.7 / 109.4 / 123.4 / 137.5 / 158.4 / 158.9** |
| cold prefill 128K/200K/255K | — / — / **1250.1** | 1085.6 / 1066.5 / 1029.3 |
| 併發 32K × C4 / C8 | **111 s** / —（0 error） | 147 s / 307 s（0 error） |
| `json_schema` + tool-call | 10/10 + 10/10 | 20/20 + 20/20 |
| 選它的時機 | 長 prefill（≥128K）、要 registry image | decode／高併發（C4–C8） |

> 2026-10-22 補測（`BENCH_IGNORE_EOS=1`、temp 0、**thinking off**、固定 250 tok、warm）：C3/5/6/7 為新值。
> 與 10-20 記錄相比 C1/C2 幾乎相同（−1.7 %／−2.2 %），C4/C8 偏高（TensorFold **+24 %／+32 %**）——該次
> 沒有記錄 `ignore_eos`/`max_tokens`，差異**不宣稱是效能變化**，需同協定複驗。

- **DSpark 兩邊都關**：vLLM 接受率僅 ~20 %（6-bit dense MTP 未被正確解出）；TensorFold drafter 正常
  （首 token 57.5 %、~2.1 tokens/round）但 verify 成本（1 row 22.4 ms、4 rows 46.8 ms）讓投機打平偏虧。
- 共用資料：`models/dsv41flash-1017-bundle/{checkpoint,engram-src-1017}`（symlink）、
  `…-engram-packed/{head,worker}`（各 95 GiB，兩條 lane 同格式）；`dsv41flash-tensorfold.conf` 已補
  `EXTRA_MODEL_DIRS`（與 exl3 同一個 Engram 來源），兩條 lane 的 `gb10 verify-models` gate 目標相同。

#### Qwen3.8 Flash-Next（125B NVFP4）

同一份 `qwen3.8-flash-next-nvfp4`（`nvidia/Qwen3.8-Flash-Next-NVFP4` @ `fc694b54`，25 檔 / 124 GiB，兩節點各一份）：

| | `qwen38flash` | `qwen38flash-tensorfold` |
|---|---|---|
| 引擎 | vLLM（TP2+EP，MTP n=3，zh draft 詞表、determinism ON） | TensorFold Zig engine（kit `./start.sh`，MTP drafts） |
| 啟動方式 | `LAUNCH_STYLE=compose` | `LAUNCH_STYLE=kit`（`~/docker-stacks/mia-TensorFold-qwen38flashNext`，釘 v1.1 `f8287ef40319`） |
| decode C1…C8 | 45.5 / 78.6 / 102.7 / 145.9 / 119.5 / 158.6 / 177.2 / 196.8（vLLM 09-29） | **55.5 / 90.6 / 129.0 / 150.9 / 176.7 / 212.6 / 246.9 / 284.4**（TF **10-22 全掃**） |
| 同 session A/B（僅 C1/C2/C4/C8） | 40.6 / 42.0 / 89.5 / 157.6 | 55.0 / 82.5 / 150.3 / 287.2 |
| cold prefill 32K/131K/261K | 2,770 / 2,809 / 2,559 | **3,465 / 3,240 / 2,989** |
| cold boot → `/health` | 13 min 58 s | **1 min 53 s** |
| 對外契約 | 支援 `response_format`／`logprobs`／`n>1` | **拒絕**上述三項（HTTP 400）；tools／vision／prompt reuse 正常 |

> 第一列是**各自最新一次**實測（vLLM 2026-09-29、TF 2026-10-22 補齊 C1–C8 的全掃），兩者不同 session，
> 只能看趨勢；第二列才是**同一 session、同一 payload** 的引擎對照（A/B 只跑 C1/C2/C4/C8）。
> TF 全掃與 00:00 的 A/B 相差 +0.9 / +9.8 / +0.4 / −1.0 %，落在本 lane 的 boot 漂移帶（0.80–1.32）內。

**選擇**：decode／高併發／最短冷啟 → TensorFold；需要 vLLM 專有請求欄位 → vLLM 版。

- 壓力基線（`scripts/bench-soak.py`，C=8 × 1200 s、thinking on）：**893 請求、0 error、0 probe mismatch**、
  199.9 tok/s、p50 8.3 s／p95 22.7 s；`TF_FLASHNEXT_GRAPH_LOG=1` 的 CUDA-graph 統計**只在 node1**
  （`docker logs qwen38-fn-tf`），`kit.log` 不會有。
- TensorFold 讀權重走 HF cache 橋接：`HF_CACHE=~/docker-stacks/models` ＋
  `hub/models--nvidia--…/snapshots/fc694b54…` 的**相對** symlink（絕對 symlink 在容器內會斷）。
- 124 GiB checkpoint **永不刪**（兩條 lane 共用）。

### 2.4 單節點 runtime（`runtimes.d/`）

| conf | id | group | 狀態 |
|---|---|---|---|
| `27b.conf` | 27b | llm（exclusive） | deployed（node0 本機或 node1） |
| `35b.conf` | 35b | llm（exclusive） | deployed |
| `comfyui-jdaln.conf` | comfyui-jdaln | image（exclusive） | deployed（Node1 `:8188`）· 詳 **§5.9** |

`deepseek`／`deepseek-vision`／`deepseek-nvfp4`／`qwen38flash`／`qwen38flash-tensorfold`／`mimo26flash`／
兩條 1017 都是 **cluster-only**（權重或啟動方式放不進單節點）。2026-10-14 退役：`comfyui`（aeon / Flux 2 Dev）
與 `minimaxh3`（vLLM-API `:8000`），stack 與 image 皆已自 Node1 刪除（`handoff.md`）。

## 3. 使用方式

### 3.1 `gb10` — 叢集

```bash
gb10 list                       # 10 條服務 lane + A/B-only deepseek-nvfp4-tune
gb10 use 27b                    # 預設；TP2 冷啟後等 /health
gb10 use qwen38flash-tensorfold # 同權重、TensorFold 引擎（decode 快、冷啟 ~2 分）
gb10 use dsv41flash-tensorfold  # 1017 peer lane A（decode）；peer B = dsv41flash-exl3-vllm
gb10 stop                       # cluster-down（兩節點）
gb10 restart [lane]             # 無參數 = state/last-cluster-profile
gb10 status                     # 兩節點、RDMA、KV、health
gb10 inspect <lane> / logs      # 解析後 profile 報告（sanitized dry-run）／follow 該 lane 的 log
gb10 smoke / load / doctor
```

- `restart` 只停一次（`cluster-down` → `--skip-down` 進 boot），避免第二次 teardown 與第一次互撞。
- kit lane 的 launcher **會提早以 0 結束**（`/health` 還要再等幾分鐘），所以存活判定看
  `state/kit.<lane>.rc`（exit code）＋ `/health`，**不要**看「launcher 進程還在不在」。

### 3.2 `gb10-single` — 單節點

```bash
gb10-single list [node0|node1]              # 無 node = 兩節點都列
gb10-single use   {node0|node1} <runtime>   # exclusive 切換
gb10-single start {node0|node1} <runtime>
gb10-single stop  {node0|node1} [runtime]
gb10-single restart {node0|node1} [runtime]
gb10-single status [node]                   # 無 node = 兩節點
gb10-single logs {node0|node1} <runtime>
gb10-single doctor
```

Node0 用本機 compose，Node1 走 `ssh -i ~/.ssh/id_gb10_cluster eye@10.0.101.102`。
exclusive 的 `use` 會清掉同節點其他 exclusive runtime 並先拆 TP2；「空 `state/` 屬正常」見 §7。

### 3.3 對外服務契約（客戶端必讀）

- **model id 一律 `aeon`**。`dsv41flash-tensorfold` 接受任意 id，但 `/v1/models` 仍廣告
  `deepseek-flash`（名字寫死在上游 vendored 程式，無旋鈕）——兩個都能用，統一用 `aeon`。
- **需要 key**：無 `Authorization: Bearer <key>` → **401**（`/v1/models`、`/v1/chat/completions` 皆同）。
- **thinking 預設開啟**（1017 兩條、qwen38 兩條）：`max_tokens` 太小會被 reasoning 吃光，
  回應變 `finish_reason=length` ＋ **空 `content`**。要格式化輸出請給 ≥1024 tokens，或自行送
  `chat_template_kwargs: {"thinking": false}`（實測約省 4 倍延遲）。
- **TensorFold 引擎拒絕** `response_format`／`guided_*`／`logprobs`／`n>1`（HTTP 400）；tools、vision、
  prompt reuse、`tool_choice:"required"` 正常。262144 是**硬上限**：prompt 超過即 400（不會靜默截斷）。

## 4. 架構

### 4.1 拓撲與 repo 位置

- 兩節點以 **CX7**（`10.0.101.101` ↔ `10.0.101.102`）做節點間資料移動與 NCCL/RoCE；
  `192.168.23.x` 才是服務／管理網段。
- **Repo 只在 Node0**：`~/workspace/ai-gb10-cluster-runtime-manager/`（branch `main`），
  位於 home 下、**不在** `~/docker-stacks/` 內。Node1 只需要 image ＋ 模型目錄 ＋ sudo docker。
- `~/bin/gb10`、`~/bin/gb10-single` 是指向 repo `bin/` 的 symlink。

### 4.2 三層分工（不可混合）

```text
image / kernel patches   ≠   cluster profile / model 設定   ≠   TP2 orchestration / networking
```

- **Profile 是唯一權威**：`cluster-profiles.d/*.conf` 由 `scripts/cluster-common.sh` 載入，
  rank0 建構最終 argv，rank1 以 shell-escaped array 接收（不用 eval、不重新序列化）。
- 不要在 `cluster-*` 腳本裡硬寫任何 per-model 分支；網路／SSH／RoCE／port／auth 才是 cluster 層。
- 通用 profile 欄位（未設＝行為不變）：`COMPILATION_JSON`、`CAP_ADD`、`ULIMITS`、
  `SECURITY_OPT`、`CMD_WRAPPER`、`SYNC_DIRS`、`EXTRA_MOUNTS`、`EXTRA_MODEL_DIRS`、
  `AUTOTUNE_CACHE_REL`、`SERVED_MODEL`。

### 4.3 `LAUNCH_STYLE`：compose vs kit

| | `compose`（預設） | `kit` |
|---|---|---|
| 啟動 | `cluster-up` 由 profile 資料 render `docker-compose.yml` 後部署 | profile 自帶兩節點 launcher（`KIT_DIR`／`KIT_START`／`KIT_STOP`／`KIT_*_CONTAINER`） |
| `cluster-up` 做什麼 | render、image-manifest gate、FlashInfer autotune reset、等 `/health` | 只負責執行 launcher、等 `/health`、寫 ready marker（跳過 render／gate／reset） |
| 適用 lane | 27b、35b、deepseek 三條、qwen38flash、mimo26flash | `dsv41flash-exl3-vllm`、`dsv41flash-tensorfold`、`qwen38flash-tensorfold` |

**kit lane 刻意沒有 compose**：rank 1 需要 rank 0 的 rendezvous 位址與**完全相同的 argv**，
compose 檔無法表達。`cluster-down` 會等（≤90 s）容器真的消失才放手。

### 4.4 互斥與資源

- TP2 lane **全部互斥**：每條吃滿 2× GB10 且綁 `:1234`，同一時間只有一條在線。
- **Cache 每 lane 獨立**（`~/.cache/vllm-<profile>` 或 `…-<profile>-{cluster,single}`，容器內掛 `/cache/vllm`），
  **log 統一**在 `~/docker-stacks/logs/<profile>/`（boot ＋ compose/container），不放在 stack 內。
- **TP2 每次開機前必清 FlashInfer autotune cache**：`file_key` 內含 rank，leader 存檔再 broadcast 給
  follower，follower 永遠 miss → 兩 rank tactic 數不同 → `dist.all_reduce` 死鎖（rank0 spin-wait、
  rank1 idle、`/health` 永不 ready）。`cluster-up` 會呼叫 `ensure_autotune_cache_reset`；
  `AUTOTUNE_CACHE_POLICY=off` 只能診斷用。單節點 LLM 必須用自己的 cache root（`gb10-single-boot` 會檢查）。

## 5. Lane 目錄

每條只列**關鍵參數、契約與最新一次實測**；完整 A/B、噪聲底與歷史都在
[`docs/BENCHMARKS.md`](docs/BENCHMARKS.md)。

### 5.1 `27b` / `35b` — Qwen 27B / 35B-A3B NVFP4（vLLM，DFlash）

**權重** 27B：`qwen3.8-27b-aeon-ultimate-uncensored-nvfp4-mixed` ＋ `qwen3.8-27b-dflash2`（n=7）；
35B：`qwen3.6-35b-a3b-heretic-nvfp4` ＋ `qwen3.6-35b-a3b-dflash`（n=6）
**Image** `ghcr.io/aeon-7/aeon-vllm-ultimate:2026-09-18-v0.29.0-omni` · **契約** 262144 ctx · 8 併發 · 27b GMU 0.85／35b GMU 0.80

| 2026-09-19（`bench-c` MAX_TOKENS=2048） | C1 | C2 | C3 | C4 | C8 | 245k prefill |
|---|---|---|---|---|---|---|
| 27B single → cluster | 23.8 → 46.1 | 36.6 → 76.8 | 54.4 → 87.9 | 80.3 → 105.3 | 117.2 → **172.7** | 348.7 → 611.5 |
| 35B single → cluster | 76.2 → 120.6 | 115.5 → 177.4 | 148.2 → 218.5 | 198.6 → 291.6 | 262.7 → **416.4** | 2580.1 → 3951.9 |

- **27B prefix caching 刻意 OFF**（理由與復活條件：`docs/ADR_2026-09-01_prefix_caching_dflash2.md`）；
  35B 已開啟。**此規則不適用其他模型家族。**
- 27B 冷啟可達 ~40 min → `27b.conf` 覆寫 `HEALTH_TIMEOUT=3600`（`docs/ISSUE_27B_BROKEN_2026-09-18_IMAGE_2026-09-19.md`）；
  2026-10-21 回歸實 boot：27b READY **261 s**、35b **380 s**，兩者 smoke 200。

### 5.2 `deepseek` — DeepSeek-V4-Flash-0731 mainline（fp8 DSpark）

**權重** `models/deepseek-v4-flash-0731-dspark-ablit`（166.9 GB / 48 shards；26 個 body `wo_b` 張量改寫，
**MTP/draft 與官方逐位元組相同**）· **Image** `eugr/spark-vllm-b12x:latest`（雙節點 digest pin，recipe `deepseek-v4-flash-0731.yaml`）
**契約** 262144 ctx · 8 併發 · KV fp8 · `aeon` · **旋鈕** k=7、`CUDAGRAPH_CAPTURE=64`（`seqs×(k+1)`=8×8）、batched 8192、GMU 0.85、prefix caching ON（**無 hotfix**）
**最新實測** Σ **693.3** tok/s（C1 43.2 → C8 119.9）、accept **33.4 %**、131K/200K/261K prefill 2174/2043/1947、
prefix-hit **38.5×**（逐字一致）、KV 407,775 tok、冷啟 12.8 min · **詳細** `docs/DEEPSEEK_B12X_RECIPE_AB_2026-10-09.md`

- 2026-10-09 配方繼承：對舊 Anemll E5 記錄 decode **+3.4 %**（8/8 格全正）、prefill **+16~18 %**、
  accept **+2.3 pp**；生產複驗 P0 也正（Σ 673.2、+0.4 %）。
- 舊配方封存 `_overdue_recipe/deepseek_anemll-dspark-vllm-gx10-011_20261009/`（**僅備份**）；
  舊官方模型 `models/deepseek-v4-flash-0731-official` 依裁示**兩節點暫留**，勿當殘留刪除。

### 5.3 `deepseek-vision` — DeepSeek-V4-Flash-Vision-EXP（原生多模態）

**權重** `models/deepseek-v4-flash-vision-exp-ablit`（167.8 GB / 48 shards）· **Image** 同 `deepseek`
**契約** 262144 ctx · 8 併發 · KV fp8 · `--limit-mm-per-prompt {"image":8}` · 每圖約 320–390 prompt tokens
**旋鈕** DSpark k=6（probabilistic B12X）、`CUDAGRAPH_CAPTURE=56`、batched 8192、GMU 0.85、prefix caching ON
**最新實測** Σ **535.3 / 545.9**（兩 boot，對舊配方記錄 538.1 **持平**）、131K–261K prefill **+9~14 %**、
accept 25.0~25.4 %、prefix-hit **50.9×**（三名輸出位元組一致）、KV **413,967 tok** · **詳細** `docs/DEEPSEEK_VISION_B12X_RECIPE_AB_2026-10-09.md`

- **原生 vision**：`CMD_WRAPPER`、`SYNC_DIRS`、17 個 MiaAI hotfix 全部移除（只有舊配方需要）。
- `CUDAGRAPH_CAPTURE=56` 是唯一升版旋鈕：上游 verbatim 48 在 C7/C8 掉出 capture range（Σ −6 %）。
  262144-word（＝上限）會被拒 → 實用上限 prompt ≤ 262143 tokens。
- 舊 Anemll 配方封存 `_overdue_recipe/deepseek-vision_anemll-dspark-vllm-gx10-011_20261009/`；
  舊模型 `models/deepseek-v4-flash-vision-exp` 同樣**暫留待議**。

### 5.4 `deepseek-nvfp4` — 0731 NVFP4（含 DSpark draft MXFP4 hotfix）

**權重** `nvidia/DeepSeek-V4-Flash-0731-NVFP4`（~172 GB / 48 shards，MIT，非 gated）
**Image** `eugr/spark-vllm-b12x:latest`（2026-10-06 nightly；`IMG_SHA256` ＋ `IMG_SHA256_NODE1` 雙 pin）
**契約** 262144 ctx · 8 併發 · KV fp8 · `aeon` · KV pool 344,195 tok（256K 單流 1.31×）
**旋鈕** `QUANTIZATION=none`（自動偵測）、**`--load-format safetensors`**、capture 48、GMU 0.85、`SECURITY_OPT=("seccomp=unconfined")`
**最新實測** C1 **47.1** → C8 **129.9**（**2.76×**）、accept **41–50 % 全程不崩**、200K cold prefill **1984.6**、
prefix-hit **44.8×**、garble soak 3/3 · **詳細** `docs/DEEPSEEK_NVFP4_SPECDECODE_AB_2026-10-08.md`

- Phase 3 四個 boot 的修復（皆為通用能力）：seccomp/io_uring → `SECURITY_OPT`；b12x loader strided scale →
  `safetensors`；**DSpark draft 根因**：checkpoint 的 `mtp.*` 是原生 MXFP4，卻被共享的 NVFP4 quant dict 建成
  `ModelOptNvFp4FusedMoE`（上游 vllm#49133 半修補）→ fail-closed 啟動 patch
  `patches/eugr-spark-vllm-b12x/hotfix-dspark-draft-mxfp4.py`。
- **NVFP4 KV（`nvfp4_ds_mla`）是負結果，已回退 fp8**：三重硬閘（DeepSeekV4 fp8 layout resolver／B12X 需
  GLM5Next／FlashMLA 需 SM100），未有上游變更勿重試。同名舊 lane（AEON NVFP4 實驗）已刪，**不是復活**。

### 5.5 `qwen38flash` — Qwen3.8 Flash-Next 125B NVFP4（vLLM，TP2+EP）

**權重** `models/qwen3.8-flash-next-nvfp4`（ModelOpt NVFP4，10-shard repack ＋ `model-fp8-mtp-ple.safetensors`）· **Image** `vllm/vllm-openai:qwen38-flash-next`（pin `IMG_SHA256`）
**契約** 262144 ctx · 8 併發 · KV `fp8_e4m3` · SSM state bf16 · `aeon` · KV 29.15 GiB
**旋鈕** TP2＋EP、MTP n=3、`--compilation-config {"mode":0}`（eager）、GMU **0.80**（0.835 會讓節點只剩 0.3–0.9 GiB 而硬重置）、batched 8192、prefix caching ON、**deterministic greedy 預設 ON**（`Q38_DET_OFF=1` 可單次關閉）
**最新實測**（2026-09-29，固定 400 tok）C1 45.5／C2 78.6／C4 145.9／**C8 196.8**；
32K/131K/200K/245K prefill 2784.6 / 2853.6 / 2698.9 / 2592.5；冷啟 13 min 58 s · **詳細** `docs/QWEN38FLASH_DRAFT_VOCAB_AB_2026-10-21.md`

- Runtime 支援**在容器啟動時**套進 image：`patches/qwen38flash/`（AGPL-3.0，18 檔 pin 在 `cd839d0b`；
  10 個 patcher 與上游 byte-identical），由 `CMD_WRAPPER` 就地套用，不重建 image。
- **Draft 詞表預設 `zh`**（`Q38_DRAFT_VOCAB=zh`）：中文 decode **+45~61 %**、acceptance **+30 pp**；
  `en_code_47k` 可還原上游預設；只影響 drafting，輸出位元不變。determinism knobs（`VLLM_QSA_DET_TOPK` ＋
  `VLLM_MOE_DET_FINALIZE`）解的是 target forward 非逐 bit 可重現造成的 accept/reject 翻轉（vllm#53436），
  `VLLM_BATCH_INVARIANT` 在 Blackwell+MXFP4 不可用；`PLE_OFFLOAD=true` 對 TP2 不可行（vLLM 拒絕 `nnodes=2`）。

### 5.6 `qwen38flash-tensorfold` — 同一 checkpoint，TensorFold 引擎

**權重** 同一份 `models/qwen3.8-flash-next-nvfp4`（**零下載、零複製**）· **Kit** `~/docker-stacks/mia-TensorFold-qwen38flashNext/`（上游釘 **v1.1 `f8287ef40319`**，`.env` 600）
**Image** `ghcr.io/miaai-lab/qwen3.8-flash-dual-dgx-sparks-tensorfold:zig-db28187-f3e1300f4f62`（digest `sha256:e188128d…e18c`，arm64）
**契約** 262144（YaRN off）· 8 併發 · KV fp8 · vision on · thinking on · `aeon` · `:1234`
**最新實測**（2026-10-22，固定 400、`BENCH_IGNORE_EOS=1`）C1…C8 = **55.5 / 90.6 / 129.0 / 150.9 / 176.7 / 212.6 / 246.9 / 284.4**（全掃、0 error）；
同 session A/B 四格 = 55.0 / 82.5 / 150.3 / 287.2；cold prefill 32K/131K/261K = **3465 / 3240 / 2989**、
cold boot **1 min 53 s**、soak 893 請求 0 error、長文檢索 exact 31/31 · **詳細** `docs/QWEN38FLASH_TENSORFOLD_DEPLOY_2026-10-22.md`

- **同步 A/B 全面勝 vLLM 版**：decode +35~96 %、prefill +15~25 %、開機快 7.4×，且 image 是 registry（免自建）。
  兩個必記的坑：① `docker pull` 後要**同時** tag 本地名 `tensorfold-qwen38fn:zig-db28187` 與 registry ref，
  否則 kit 前置 gate 直接 die；② 權重橋接必須用**相對** symlink（`start.sh` 把 `HF_CACHE` 掛進容器）。
  `prepare.sh` 在現役 lane 旁邊跑時要 `MEM_CHECK=0 PULL=0 HF_HUB_OFFLINE=1`（避免觸發 124 GiB 重下）。
  CUDA graph：`TF_FLASHNEXT_GRAPH_LOG=1` 時統計**只在 node1** 的 `docker logs qwen38-fn-tf`（`kit.log` 不會有）；
  實測 8300 captures / 8300 instantiated、**0 失敗**。

### 5.7 `mimo26flash` — MiMo V2.6 Flash MOPD（MXFP4 QAT ＋ DFlash2）

**權重** `models/mimo-v2.6-flash-mopd`（Xiaomi 官方 MXFP4 QAT；drafter 內嵌於 `dflash/`）· **Image** `ghcr.io/tonyd2wild/vllm-glm53-flash:sm121-v11-dflash2`（pin manifest digest）
**契約** 262144 ctx · 8 併發 · KV fp8 · `aeon` · **TP2-only**（178 GB 放不進單節點）
**旋鈕** DFlash2 n=7、GMU 0.90、prefix caching ON、MoE `marlin`、`patches/mimo26flash/`（3 支 bind-mount）
**最新實測**（2026-10-22 補測；`BENCH_IGNORE_EOS=1`、400 tok、預設取樣、**warm**）C1…C8 =
**29.3 / 36.2 / 44.0 / 55.9 / 59.6 / 61.6 / 58.5 / 63.1**（0 error）；10-03 首發記錄為 21.1 / 33.9 / — / 49.1 / — / — / — / 67.9；
32K/131K/245K prefill 1553.7 / 1015.4 / 724.3 · **詳細** `docs/MIMO26FLASH_TP2_2026-10-03.md`

- 冷啟後第一發 C1 僅 **9.1 tok/s**（JIT/compile 未熱，wall 44 s），故上表取 warm；C7 58.5 < C6 61.6 屬噪聲。

- **定案 MXFP4（2026-10-05）**：NVFP4 變體只贏 prefill（+12~28 %）與低併發，卻以 **41 % KV 容量**
  （8.81× → 5.21× @256K）、官方 QAT／`SHA256SUMS`、21 GB 磁碟為代價；decode 差距多在噪聲內。
  要回 NVFP4 只需 flip `BODY_REL` ＋ `DISPLAY_NAME`（`models/mimo-v2.6-flash-mopd-nvfp4` 因此保留）。
- DFlash cliff 探測兩變體皆過（1024-token 滑窗 NaN cliff 在本棧無法重現）；image/draft 變更後以
  `node0:/tmp/dflash-cliff.sh` 重跑。延後調優（`repetition_penalty` A/B、`long-prefill-token-threshold`、
  tool-parser truncation）見 docs §7。

### 5.8 1017 兩條 lane

參數與對照見 **§2.3**，這裡只補共通事實：

- 權重：`models/` 下 `…-1017-exl3-2.9bpw`（196 GiB）、`…-1017-engram`（189 GiB）、
  `…-engram-packed/{head,worker}`（各 95 GiB）、`dsv41flash-1017-bundle`（symlink）；image 只在 node0 pull，
  再 `docker save | ssh docker load` 走 CX7。`dsv41flash-exl3-vllm` 的 node 側 kit `.env` 需
  `SERVED_MODEL_NAME=aeon`（改前備份 `.env.bak-20261021-134817`），否則 `model=aeon` 會 404。
- 驗證 harness：`scripts/bench-1017.py`（`prefill`／`conc`／`tools`／`soak`，輸出 JSONL）。
  2026-10-21 實 boot：`dsv41flash-tensorfold` `restart` → **327 s** READY；`verify-models` 對 exl3
  **PASS**（checkpoint 52/52 ＋ Engram 3/3，兩節點）。
- **2026-10-22 全掃**（`BENCH_IGNORE_EOS=1`、temp 0、thinking off、250 tok、warm、0 error）：
  exl3 = **23.8 / 36.1 / 46.2 / 63.9 / 60.0 / 87.8 / 82.2 / 90.2**、
  tensorfold = **41.9 / 64.1 / 74.7 / 109.4 / 123.4 / 137.5 / 158.4 / 158.9**。
  同日 `gb10 use` → `/health`：exl3 **6m25s**、tensorfold **5m45s**。
  C1/C2 與 10-20 記錄吻合（−1.7 %／−2.2 %）；C4/C8 偏高（TF +24 %／+32 %）但 10-20 未記錄
  `ignore_eos`/`max_tokens`，**不宣稱效能變化**，需同協定複驗。

### 5.9 `comfyui-jdaln` — Node1 唯一 ComfyUI（`:8188`）

**Stack** `~/docker-stacks/comfyui-dgx-spark/ComfyUI-DGX-Spark-Docker-opinionated/`（clone `ef7a677b`）· **Image** 自建 `comfyui-dgx-spark-docker-opinionated-comfy:latest`（ComfyUI 0.38.0、2811 node types）
**契約** 產出在 `~/Downloads/output/`；模型用 `UNETLoader` ＋ `CLIPLoader` ＋ `VAELoader`（**刻意沒有** `models/checkpoints/`，`CheckpointLoaderSimple` 空清單是正常的）· **詳細** `docs/COMFYUI_JDALN_REMOTE_USAGE_GUIDE_2026-10-15.md`（rev 7）

- **上游 healthcheck 是假陽性**（會 match 自己的 `sh -c` 指令列）→ 可信閘門是 `gb10-single` 對 `:8188/`
  的 loopback curl，**不要看 `docker ps` 的 health**。`ComfyUI-SAM3-DGX-Spark` 被 blacklist（其 pin 的
  `comfy-env==0.2.61` 已被 PyPI 下架，貢獻 0 個節點）；11 個 `SAM3_*` 節點其實由 ComfyUI core 提供。
- **16 個 asset profile**（`.env` 的 `COMFY_ASSET_PROFILES`）、`UPDATE_DEPS=false`、allowlist 空
  （要恢復 workflow gallery 就把 pack 名寫回 `.env`，下載是冪等的）。重建前必做
  `SelfBuiltWheels/*` → `DGX-Spark-WheelsBuilder/Wheels/`，否則 onnxruntime 從原始碼編譯（數小時）。
- **輸出寬高必須是 16 的倍數**：1920×1080 實際送出 1920×**1088**（簡報要裁掉 8 列）。**Node0 有被動
  failover 鏡像**（`rsync -aHAX --no-o --no-g --delete` 走 CX7，~396 MB/s）——**尚未 boot 驗證**，
  真要切換得先 `gb10 stop` 再 `gb10-single use comfyui-jdaln node0`（會搶同一顆 GPU）。

## 6. 維運守則（Non-negotiables）

1. **同一顆 resolved image 必須兩節點 byte-identical**（TP2）；kit lane 以 `KIT_*_CONTAINER` 與
   `/health` 判定，不用 compose 驗證器。
2. **RoCE v2 環境變數**以 `cluster.env`／`cluster-common.sh` 的 pin 為準；
   `--disable-custom-all-reduce` 是跨節點 load-bearing，不可拿掉。
3. **`--kv-cache-dtype` 不是通則**：Qwen 系是 `fp8_e4m3`，DeepSeek 各 lane 有自己的 KV 政策。
4. **TP2 27B 的 prefix caching 永久 OFF**；其他模型不受此限。
5. **GB10 的 `nvidia-smi` 不可信**，一律看引擎 metrics。
6. **每次 TP2 開機前清 autotune cache**（見 §4.4）。
7. **Secrets 不進 repo**：`config/{cluster,standalone}.env`、`*.env`、`hf_token`、keys 全部 gitignored；
   `*.example` 才是模板。
8. **腳本風格**：LF、`#!/usr/bin/env bash`、`set -Eeuo pipefail`；本機 PowerShell 用 **pwsh7**（不用 5.1）。
9. **root 擁有的節點目錄不要用 `rm -rf`**（`eye` 無父目錄寫入權，會「假成功」）→
   用 `docker run --rm -v <dir>:/t … sh -c 'rm -rf /t/*'`；`;` 串接的 `DONE` 不算成功證據
   （要 `rc=$?; echo $rc > f`）。**刪 image 前先查自動化殘留**（例如 `/tmp/pull_watchdog.sh` 這類
   `while true` 迴圈），否則會跟它打架。
10. **Kit lane 沒有 compose，也不要幫它加**；rank 1 需要 rank 0 的 rendezvous 與相同 argv。
11. **標記版本＝兩邊都建 Release**：annotated tag 只產生 tag，Release 要分別 POST 到 Forgejo（`origin`）
    與 GitHub（`github`），body ＝ tag message 逐字。

## 7. 佈局

```text
bin/                  gb10（叢集）、gb10-single（單節點）
scripts/              cluster-{up,down,status,smoke,load}、cluster-common.sh、gb10-{boot-cluster,single-boot}、
                      cluster-compose-verify、check-git-sync.sh、bench-*（c/ctx/mm/ab/prefix-hit/1017/soak/draft-vocab）
cluster-profiles.d/   TP2 profile registry（唯一權威：10 條服務 + 1 條 A/B）
runtimes.d/           單節點 runtime（27b / 35b / comfyui-jdaln）
patches/              vendored runtime patch（qwen38flash、mimo26flash、eugr b12x hotfix…）
state/                執行期標記（gitignored；空目錄＝正常，見下）
docs/                 部署記錄、A/B 報告、ADR、上游查核、evidence/、_archive/（舊版文件封存）
_overdue_recipe/      退役配方自帶式封存（conf + compose + patches + recipe_README；
                      **不含** image/權重；loader 永不掃描）
```

`state/` 是**執行期便利記憶層**，不是部署契約（`.gitignore` 排除整個目錄，空目錄或不存在都正常）。
標記檔：`last-runtime`（`gb10-single`）、`last-cluster-profile`（`gb10 restart` 的預設）、`boot-ready.*`、
`boot-cluster.*.pid`、`kit.*.pid`、`kit.*.rc`；TP2 在線時單機端**不該**有 `last-runtime`。

**節點側** `~/docker-stacks/`（不在 repo 內）：每個 lane 一個以 image 來源命名的 `<stack>/`
（`aeon-vllm-omni`、`eugr-spark-vllm-b12x{,-deepseek,-vision}`、`mia-vllm-openai-qwen38flashNext`、
`mia-TensorFold-qwen38flashNext`、`tonyd2wild-vllm-mimo26flash`、`mia-vllm-dsv41flash`、
`x00byte-TensorFold-dsv41flash`（190 GB build sources）、`comfyui-dgx-spark`），
compose 檔與 `patches/` staging 都放在該目錄內。`anemll-dspark-vllm-gx10{,-miaFlaver,-miaFlaver-tune}`
與 `eugr-spark-vllm-b12x-tune` 只是 materialize 殘留（各 ≤24 檔、無容器），**不是服務**。
另有 `config/`（`cluster.env`／`standalone.env`／`hf_token`，全部 gitignored）、
`models/`（共用權重池，含 `hub/` 供 TensorFold 的相對 symlink 橋接）、`logs/<profile>/`（統一 log），
以及每 lane 獨立的 `~/.cache/vllm-<profile>[-cluster|-single]`。

## 8. 文件索引

| 主題 | 文件 |
|---|---|
| 量測總覽與歷史（所有 A/B、噪聲底、harness 協定） | [`docs/BENCHMARKS.md`](docs/BENCHMARKS.md) |
| 叢集部署／非協商項、profile 資料驅動重構驗證 | [`docs/TP2_DEPLOYMENT_2026-08-30.md`](docs/TP2_DEPLOYMENT_2026-08-30.md)、[`docs/TP2_PROFILE_REFACTOR_VALIDATION_2026-09-05.md`](docs/TP2_PROFILE_REFACTOR_VALIDATION_2026-09-05.md) |
| DeepSeek mainline／Vision 配方對決 | [`docs/DEEPSEEK_B12X_RECIPE_AB_2026-10-09.md`](docs/DEEPSEEK_B12X_RECIPE_AB_2026-10-09.md)、[`docs/DEEPSEEK_VISION_B12X_RECIPE_AB_2026-10-09.md`](docs/DEEPSEEK_VISION_B12X_RECIPE_AB_2026-10-09.md) |
| 同 image 調優（E0–E5／V0–V5）、NVFP4 spec-decode | [`docs/DEEPSEEK_TUNE_AB_2026-10-06.md`](docs/DEEPSEEK_TUNE_AB_2026-10-06.md)、[`docs/DEEPSEEK_VISION_TUNE_AB_2026-10-07.md`](docs/DEEPSEEK_VISION_TUNE_AB_2026-10-07.md)、[`docs/DEEPSEEK_NVFP4_SPECDECODE_AB_2026-10-08.md`](docs/DEEPSEEK_NVFP4_SPECDECODE_AB_2026-10-08.md) |
| qwen38flash（部署／draft 詞表／TensorFold） | [`docs/QWEN38_FLASH_NEXT_TP2_COMPOSE_2026-09-20.md`](docs/QWEN38_FLASH_NEXT_TP2_COMPOSE_2026-09-20.md)、[`docs/QWEN38FLASH_DRAFT_VOCAB_AB_2026-10-21.md`](docs/QWEN38FLASH_DRAFT_VOCAB_AB_2026-10-21.md)、[`docs/QWEN38FLASH_TENSORFOLD_DEPLOY_2026-10-22.md`](docs/QWEN38FLASH_TENSORFOLD_DEPLOY_2026-10-22.md) |
| MiMo／1017 選型 | [`docs/MIMO26FLASH_TP2_2026-10-03.md`](docs/MIMO26FLASH_TP2_2026-10-03.md)、[`docs/DSV41_FLASH_EXL3_2X_SPARK_EVAL_2026-09-29.md`](docs/DSV41_FLASH_EXL3_2X_SPARK_EVAL_2026-09-29.md) |
| ComfyUI 部署／遠端使用指南 | [`docs/COMFYUI_JDALN_DEPLOYMENT_2026-10-14.md`](docs/COMFYUI_JDALN_DEPLOYMENT_2026-10-14.md)、[`docs/COMFYUI_JDALN_REMOTE_USAGE_GUIDE_2026-10-15.md`](docs/COMFYUI_JDALN_REMOTE_USAGE_GUIDE_2026-10-15.md) |
| 上游查核（deepseek／vision／27B·35B） | [`docs/DEEPSEEK_UPSTREAM_REVERIFY_2026-09-30.md`](docs/DEEPSEEK_UPSTREAM_REVERIFY_2026-09-30.md)、[`docs/QWEN_27B_35B_UPSTREAM_REVERIFY_2026-09-30.md`](docs/QWEN_27B_35B_UPSTREAM_REVERIFY_2026-09-30.md) |
| ADR：27B prefix caching、舊版 README 備份 | [`docs/ADR_2026-09-01_prefix_caching_dflash2.md`](docs/ADR_2026-09-01_prefix_caching_dflash2.md)、[`docs/_archive/README_ARCHIVE_2026-10-22.md`](docs/_archive/README_ARCHIVE_2026-10-22.md) |
| 交接與逐 session 證據 | [`handoff.md`](handoff.md)、[`AGENTS.md`](AGENTS.md) |

## 9. 更新記錄（History）

只記**對外可觀察或對運維有意義**的變更；每個版本的完整 commit 清單見對應 tag 的 annotated message。

| 版本 | 日期 | 重點 |
|---|---|---|
| **v2.0.0** | 2026-10-22 | **README v2 佈局**：整合同模型新舊數據、單一「現役」來源、新增本 History；詳細量測歷史移入 `docs/BENCHMARKS.md`；v1.x README 封存 `docs/_archive/`。**無 runtime／CLI 行為變更。** |
| v1.9.0 | 2026-10-22 | 新 lane `qwen38flash-tensorfold`（TensorFold TP2，與 `qwen38flash` 共用 checkpoint、對等 lane）；`LAUNCH_STYLE=kit` 第三例；`scripts/bench-soak.py`；A/B decode 287.2 vs 157.6、冷啟 1m53s vs 13m58s |
| v1.8.0 | 2026-10-20 | 1017 兩條 lane（`dsv41flash-exl3-vllm`／`dsv41flash-tensorfold`）＋ 通用 `LAUNCH_STYLE=kit`／`SERVED_MODEL`／`EXTRA_MODEL_DIRS`；兩條皆 `SPEC_METHOD=none` |
| v1.7.0 | 2026-10-14 | 新 lane `comfyui-jdaln`；`comfyui`(aeon) 與 `minimaxh3` 退役、`minimax-h3-sglang` 清除；Node0 failover 鏡像（CX7）；修 `gb10-single-boot` 假 READY；輸出改 `~/Downloads/output/` |
| v1.6.0 | 2026-10-09 | 兩次**配方繼承**（`deepseek`、`deepseek-vision` → eugr b12x ＋ ablit）；退役配方改為自帶式 `_overdue_recipe/` 封存 |
| v1.5.0 | 2026-10-08 | 新 lane `deepseek-nvfp4`（Phase 1–3）；seccomp/io_uring、`safetensors` loader、DSpark draft MXFP4 hotfix；NVFP4 KV 負結果 |
| v1.4.1 | 2026-10-07 | 同 image 調優：DeepSeek E5 promote（+12.9 %／+4.5 pp／prefix 7.6×）、Vision V3 promote；新增 A/B harness 與 `-tune` 實驗 lane |
| v1.4.0 | 2026-10-05 | 新 lane `mimo26flash`（MiMo V2.6 Flash MOPD）；變體 A/B 定案 **MXFP4** |
| v1.3.4 | 2026-09-30 | 上游再查核：deepseek／vision 與 27b／35b 的 image 與權重來源皆為最新 |
| v1.3.3 | 2026-09-29 | DSV4.1-Flash EXL3 選型查核；`gb10 restart` fallback 修正；現役切回 `deepseek` |
| v1.3.2 | 2026-09-29 | docs-only：README deployed-services 表與 qwen38flash 過期事實校正 |
| v1.3.1 | 2026-09-29 | qwen38flash 對齊上游；deterministic greedy 預設；bench 協定明文化 |
| v1.3.0 | 2026-09-29 | main 上的官方穩定標記 |
| v1.2.0 | 2026-09-13 | README 新增已部署服務與最新 image benchmark 表 |
| v1.1.0 | 2026-09-10 | `gb10`／`gb10-single` 的 `use`/`start` 改為背景 boot |
| v1.0.0 | 2026-09-10 | `keystone` 併入 `main`（canonical runtime line，unrelated histories 合併） |
