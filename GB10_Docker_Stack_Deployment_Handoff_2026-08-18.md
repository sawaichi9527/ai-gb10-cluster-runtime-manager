# DGX Spark GB10 本地 AI 部署狀態交接（最新版）

> 更新日期：2026-08-18  
> 主機：NVIDIA DGX Spark / GB10  
> 主機名稱：`spark-25d5`  
> 使用者：`eye`  
> 區網 IP：`192.168.23.215`  
> 作業系統：Ubuntu 24.04 ARM64  
> 用途：本地 vLLM LLM 推理 + ComfyUI 生圖，以 Docker Stack 分離管理  
> 文件定位：接續 `GB10_Docker_Stack_Deployment_Handoff_2026-08-10.md`，記錄 2026-08-18 完成之 AEON vLLM `v0.26.0 → v0.27.1` 升級、**27B 與 35B 兩 runtime 的實際啟動驗證**、以及 27B→35B→27B 完整切換週期驗證。ComfyUI 相關內容沿用 2026-07-31 / 2026-08-10 文件，本文件不重複。

---

# 1. 本次工作摘要

2026-08-18 完成：

```text
1. Pull 新 image：ghcr.io/aeon-7/aeon-vllm-ultimate:2026-08-16-v0.27.1
2. 27B：.env 的 AEON_IMAGE 替換 → v0.27.1，重建容器，驗證 READY
3. 35B：docker-compose.35b.yml image 直接 pin 替換 → v0.27.1
4. 35B：首次以 v0.27.1 實際啟動驗證 READY（關閉 8/10 文件的 NOT YET REVALIDATED 項目）
5. 27B→35B→27B 完整切換週期驗證
6. 舊 image（v0.25.1 / v0.26.0）全部保留可 rollback
7. 切回 27B 作為日常預設
```

核心原則不變：

```text
gb10 Runtime Manager = 操作便利層
Docker Compose      = deployment source of truth
Host bind mounts    = persistent data
Docker image        = 可替換 runtime layer
```

---

# 2. 目前 Docker Image 狀態

主機上現有三個 AEON vLLM image：

```text
ghcr.io/aeon-7/aeon-vllm-ultimate:2026-07-16-v0.25.1   (ID f1a76ec68c64, 43GB)   保留 rollback
ghcr.io/aeon-7/aeon-vllm-ultimate:2026-07-27-v0.26.0   (ID 885d08e5831c, 43.9GB) 保留 rollback（上一版）
ghcr.io/aeon-7/aeon-vllm-ultimate:2026-08-16-v0.27.1   (ID eacd0eef2346, 50.6GB) 目前使用中
```

v0.27.1 為上游 **DSPARK release**（= `:latest`），基底 vLLM v0.27.1 from-source build for sm_121a。

升級前備份（保留在 `~/docker-stacks/aeon-vllm/`）：

```text
.env.bak-before-upgrade-20260818-220810
docker-compose.35b.yml.bak-before-upgrade-20260818-220810
```

---

# 3. 版本設定現況

## 3.1 27B（`.env` 控制）

```text
AEON_IMAGE=ghcr.io/aeon-7/aeon-vllm-ultimate:2026-08-16-v0.27.1
```

## 3.2 35B（Compose 直接 pin）

`docker-compose.35b.yml` 內：

```yaml
image: ghcr.io/aeon-7/aeon-vllm-ultimate:2026-08-16-v0.27.1
```

維持 8/10 文件的刻意設計：27B 走 `.env` 變數、35B 直接 pin，兩 profile 可各自獨立 pin 不同 runtime 版本方便 A/B 與 rollback。

## 3.3 驗證過的 resolved image

兩個 profile `docker compose config` 均通過，resolved image 皆為 `2026-08-16-v0.27.1`。

---

# 4. v0.27.1 上游重點（對本部署的影響）

來源：AEON-7/vllm-ultimate-dgx-spark README / SOURCE.md（2026-08-16）：

```text
- DSpark Markov-head speculative decoding（量化 heads）為本版 headline
- DSpark 為 MRv2-only；VLLM_USE_V2_MODEL_RUNNER=0 不再 baked
- 我們的 compose 從未 pin 過 VLLM_USE_V2_MODEL_RUNNER → 不受影響
- 未來若需要 thinking_token_budget，需 per-service re-pin =0（V2 會靜默忽略 budget）
- 依賴版本：torch 2.13.0+cu130 / Triton 3.7.1 / FlashInfer 0.6.16.post3 / NCCL 2.30.7 / transformers 5.14.1
- 官方 rollback 指向：2026-07-27-v0.26.0（本主機有保留）
```

已知良性警告（每次啟動都會出現，可忽略）：

```text
ImportError: deep_ep_cpp... undefined symbol (materialize_cow_storage)
```

原因：deep_ep 套件與 torch 2.13 ABI 不完全匹配；本機 single-node TP=1 不使用 deep_ep，vLLM 以 try-import 方式載入失敗僅記 warning，不影響功能。

---

# 5. 27B v0.27.1 啟動驗證（2026-08-18 22:08）

## 5.1 啟動結果

```text
gb10 restart 27b
→ Container recreated with 2026-08-16-v0.27.1
→ READY（耗時約 14 分 12 秒）
→ Health http 200，RestartCount=0
```

版本字串：

```text
version 0.27.1+aeon.sm121a.dspark
```

Engine 設定確認（全部與 v0.26.0 時期相同，僅換 image）：

```text
quantization=modelopt_fp4
kv_cache_dtype=fp8_e4m3
speculative: dflash, num_spec_tokens=12
max_seq_len=229376
load_format=auto
```

## 5.2 首次冷啟動時間軸

```text
Target model:   Checkpoint 26.59 GiB, Loading weights 204.06 s
Drafter:        Checkpoint  3.22 GiB, Loading weights  24.71 s
torch.compile:  59.91 s + 12.84 s（cache miss，首次）
FlashInfer:     0.6.16.post3 autotune 92 configs，約 6 分鐘
init engine:    570.27 s
全程:           約 14m12s（API start 22:08:38 → READY 22:22:50）
```

對照 v0.26.0 首次冷啟動（8/10 紀錄約 15m45s）：略快。

## 5.3 KV cache 觀察（與 v0.26.0 差異）

```text
v0.26.0:  Available KV 36.02 GiB / 622,671 tokens / 2.71x
v0.27.1:  Available KV 32.72 GiB / 565,887 tokens / 2.47x（首次啟動）
          Available KV 32.29 GiB / 558,334 tokens / 2.43x（晚間切回時）
```

v0.27.1 runtime 常駐記憶體略增，KV 容量減少約 8-10%。屬版本布局差異，非故障；長 context 高併發餘裕稍減，日常使用無感。

## 5.4 煙霧測試

```text
GET  /v1/models            → 200，served model id = aeon
POST /v1/chat/completions  → 200，正常生成
service fingerprint: vllm-0.27.1+aeon.sm121a.dspark-800c8a2d
```

（reasoning 模型在 max_tokens 極小時 content 可能為 null、文字落在 reasoning 欄位屬正常。）

## 5.5 Mounts 確認

```text
models/qwen3.6-27b-aeon-mm-mtp → /model        (ro)
models/qwen3.6-27b-dflash      → /drafter      (ro)
cache                          → /root/.cache  (rw)
```

模型與 cache 皆為 host bind，image 升級未動模型。

---

# 6. 35B-A3B v0.27.1 啟動驗證（2026-08-18 22:27）

> 8/10 文件之「35B 尚未實際啟動驗證」項目，於本次關閉。注意：35B 實際驗證時直接從 v0.25.1 時期的最後運行紀錄跳到 v0.27.1（中間 v0.26.0 僅完成 compose 驗證未運行）。

## 6.1 啟動結果

```text
gb10 use 35b
→ 27B 乾淨停止並移除
→ 35B 以 2026-08-16-v0.27.1 建立並啟動
→ READY（耗時約 8 分 41 秒）
→ Health http 200，RestartCount=0
```

版本字串：

```text
version 0.27.1+aeon.sm121a.dspark
```

Engine 設定確認（35B 專屬 tuning 全部保留）：

```text
quantization=compressed-tensors
kv_cache_dtype=auto
attention_backend=flash_attn
speculative: dflash, num_spec_tokens=11
load_format=safetensors
max_seq_len=229376
```

模型架構（由 cache modelinfos 觀察）：

```text
Target:  Qwen3_5MoeForConditionalGeneration
Drafter: DFlashQwen3ForCausalLM
```

## 6.2 首次冷啟動時間軸

```text
Target model:   Checkpoint 21.75 GiB, Loading weights 174.10 s
Drafter:        Checkpoint  0.72 GiB, Loading weights   4.68 s
torch.compile:  42.11 s + 11.77 s（cache miss，首次）
FlashInfer:     autotune 約 1 分 33 秒
init engine:    285.90 s（compilation 53.88 s）
全程:           約 8m41s（22:27:29 → READY 22:36:10）
```

35B 冷啟動明顯快於 27B，主因：checkpoint 較小（21.75 vs 26.59 GiB）、drafter 小很多（0.72 vs 3.22 GiB）、autotune 較快。

## 6.3 KV cache 觀察

```text
v0.27.1 35B:  Available KV 40.5 GiB / 761,489 tokens / 3.32x
```

35B 的 KV 餘裕顯著優於 27B（MoE 架構 + KV auto dtype）。

## 6.4 Mounts 確認（35B 專屬隔離）

```text
models/qwen3.6-35b-a3b-heretic-nvfp4 → /model                 (ro)
models/qwen3.6-35b-a3b-dflash        → /drafter               (ro)
cache/huggingface                    → /root/.cache/huggingface
cache/vllm-35b                       → /root/.cache/vllm
logs                                 → /logs
```

首次 v0.27.1 啟動後 host 端 `cache/vllm-35b` 成長至約 659 MB，新增：

```text
flashinfer_autotune_cache/0.6.16.post3/121a/.../autotune_configs.json
torch_compile_cache/.../backbone + dflash_head
modelinfos/...
```

與 27B 的 cache（掛 `/root/.cache` 整個根）維持隔離。

## 6.5 煙霧測試

```text
GET  /v1/models            → 200，served model id = aeon
POST /v1/chat/completions  → 200，正常生成
service fingerprint: vllm-0.27.1+aeon.sm121a.dspark-697850e2
```

---

# 7. 27B→35B→27B 切換週期驗證

本次完整跑過一輪 exclusive 切換：

```text
22:08  gb10 restart 27b       → 27B v0.27.1 READY（首次冷啟動 14m12s）
22:27  gb10 use 35b           → 27B 停止移除，35B v0.27.1 READY（8m41s）
22:41  gb10 use 27b           → 35B 停止移除，27B v0.27.1 READY（約 11m40s）
```

第三段切回 27B 的重點觀察 — **compile cache 命中驗證成功**：

```text
首次啟動（cache miss）:  torch.compile 59.91 s + 12.84 s
切回啟動（cache hit）:   torch.compile  1.17 s +  4.55 s
init engine: 449.78 s（compilation 僅 5.71 s）
```

FlashInfer autotune 即使有 cache 仍會重新執行量測流程（約 5-6 分鐘），屬正常行為；權重載入（約 225 s）為 NVMe 頻寬限制，與版本無關。

結論：

```text
[OK] 27B v0.27.1 啟動 / health / 推論
[OK] 35B v0.27.1 啟動 / health / 推論
[OK] exclusive 切換來回正常
[OK] torch.compile 與 autotune cache 持久化並可重用
[OK] 35B 專屬 cache 隔離正常
```

目前狀態：**27B 運行中（日常預設）**。

---

# 8. 版本效能對照總表

| 項目 | 27B v0.26.0 | 27B v0.27.1 | 35B v0.27.1 |
|---|---:|---:|---:|
| 首次冷啟動 | 約 15m45s | 約 14m12s | 約 8m41s |
| init engine | 699.60 s | 570.27 s | 285.90 s |
| Target checkpoint | 26.59 GiB | 26.59 GiB | 21.75 GiB |
| Drafter checkpoint | 3.22 GiB | 3.22 GiB | 0.72 GiB |
| KV memory | 36.02 GiB | 32.72 GiB | 40.5 GiB |
| KV tokens | 622,671 | 565,887 | 761,489 |
| 229K 滿載併發 | 2.71x | 2.47x | 3.32x |
| FlashInfer | 0.6.14 | 0.6.16.post3 | 0.6.16.post3 |
| fingerprint 尾碼 | — | -800c8a2d | -697850e2 |

---

# 9. 系統資源觀察（本次）

升級與兩次切換全程：

```text
Mem: 121 GiB 總量，peak used 約 85-92 GiB，available 最低約 36 GiB
Swap: 全程 125-142 MiB，si/so = 0（無 thrashing）
磁碟: image 三版本共約 137 GB，root 仍有 3.3T 可用
```

每次 runtime 切換（容器重建）後 swap 使用量極低，v0.26.0 時代的 3.8 GiB cold swap 已自然消化。

---

# 10. 維護通道筆記（Windows 端）

本次維護由 Windows 10 工作站遠端操作，經驗記錄：

```text
1. 原生 ssh 金鑰認證異常：
   client 簽章階段失敗（host-bound key 簽名後 server 拒絕），
   id_rsa（有 passphrase）與新建 id_gb10_maint（無 passphrase，已加入主機
   authorized_keys）都相同結果。原因未深究，暫時棄用原生 ssh 金鑰路徑。

2. 實際可用通道：
   PowerShell + Posh-SSH 模組（Install-Module Posh-SSH -Scope CurrentUser）
   以 password credential 連線，Invoke-SSHCommand 執行遠端指令。
   長時間操作（pull、restart）先丟進主機端 tmux，再輪詢 log 檔。

3. 密碼不寫入任何文件；如需再自動化，建議日後修好金鑰認證
   （可先在主機 sshd 開 sshd -ddd 或換 client 版本測試 hostbound 行為）。
```

---

# 11. Rollback SOP（v0.27.1 → v0.26.0）

若 v0.27.1 出現問題，回滾方式（沿用 8/10 SOP）：

27B（改 `.env`）：

```bash
cd ~/docker-stacks/aeon-vllm
# AEON_IMAGE 改回 ghcr.io/aeon-7/aeon-vllm-ultimate:2026-07-27-v0.26.0
docker compose -p aeon-vllm -f docker-compose.27b.yml up -d --force-recreate
```

35B（改 compose 內 image 行）：

```bash
# docker-compose.35b.yml image 改回 2026-07-27-v0.26.0
docker compose -p aeon-vllm -f docker-compose.35b.yml up -d --force-recreate
```

或直接還原本次備份：

```bash
cp .env.bak-before-upgrade-20260818-220810 .env
cp docker-compose.35b.yml.bak-before-upgrade-20260818-220810 docker-compose.35b.yml
```

確認：

```bash
docker inspect aeon-vllm --format '{{.Config.Image}}'
```

注意：v0.27.1 產生的 compile/autotune cache 與 v0.26.0 的 cache 目錄互不干擾（版本路徑分開），回滾後 v0.26.0 若 cache 已被清理需重新冷啟動一次。

---

# 12. 操作禁忌（累計版）

沿用 8/10 全部禁忌，另新增：

```text
不要刪除三個保留 image 中的任何一個（v0.25.1 / v0.26.0 / v0.27.1 並存）
不要因為 v0.27.1 KV 容量略降就調 gpu-memory-utilization（先觀察實際負載）
不要把 27B 與 35B 的 fingerprint 尾碼差異（-800c8a2d / -697850e2）當作異常
不要忽略 deep_ep ImportError warning 是良性的這個結論（除非伴隨啟動失敗）
不要在需要 thinking_token_budget 的服務上無腦升到 v0.27.1（MRv2 會靜默忽略 budget）
```

既有禁忌（摘要）：

```text
不要 runtime: nvidia / 重啟 Docker daemon
不要把模型權重寫入 container writable layer
不要把 API Key / HF Token 寫入文件或 Git
不要隨意刪 /root/.cache 對應 host cache
不要 swapoff -a
不要把 max-num-seqs=16 解讀成 16 × 229K 可同時滿載
ComfyUI 相關禁忌見 2026-07-31 文件
```

---

# 13. 部署完成狀態（2026-08-18）

```text
[OK] v0.27.1 image pull（2026-08-16-v0.27.1）
[OK] 27B .env → v0.27.1
[OK] 35B compose → v0.27.1
[OK] 27B v0.27.1 首次冷啟動 / health READY / 煙霧測試
[OK] 35B v0.27.1 首次冷啟動 / health READY / 煙霧測試（關閉 8/10 待驗證項）
[OK] 27B→35B→27B exclusive 切換週期
[OK] torch.compile / FlashInfer autotune cache 持久化與重用驗證
[OK] 35B 專屬 cache 隔離（cache/vllm-35b 659MB）
[OK] Mounts 全 host bind，模型未動
[OK] 舊 image 保留（v0.25.1 + v0.26.0）
[OK] Swap 健康（<150Mi，si/so=0）
[OK] 目前運行：27B（日常預設）
[沿用] ComfyUI Work / Personal（2026-07-31 部署，未變更）
```

---

# 14. 後續建議

```text
1. 建立 27B/35B v0.27.1 正式 benchmark（TTFT、output tok/s、
   1/3/5 concurrent、prefix cache 行為），補齊與 v0.26.0 的量化對比
2. 觀察 27B KV 減少 ~10% 是否影響實際長 context 併發場景
3. 修復 Windows 端 ssh 金鑰認證（hostbound 簽章問題），取代密碼通道
4. 35B + ComfyUI 共存壓力測試（8/10 遺留項）
5. 5 併發 + 256K context 壓力測試（8/10 遺留項）
6. ComfyUI workflow 另存命名 / 模型 manifest（7/31 遺留項）
7. 評估 v0.25.1 image 是否可除役（已隔兩個版本，建議再觀察一版）
```

---

# 15. 下一位 AI / 維護人員接手時先跑

```bash
gb10 status
gb10 doctor

docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Image}}'
docker images ghcr.io/aeon-7/aeon-vllm-ultimate

docker inspect aeon-vllm --format '{{.Config.Image}}'
curl -i http://127.0.0.1:1234/health

free -h
swapon --show
```

預期狀態：

```text
aeon-vllm 運行中，image = 2026-08-16-v0.27.1
served model = 27B（aeon-qwen36-27b）
health = 200
```

vLLM 完整指令與 troubleshooting 見 2026-08-10 文件第 18/19 節，全部仍然適用。

---

# 16. 最終結論

```text
vLLM runtime 已全面升級至 v0.27.1（DSPARK release）
27B / 35B 兩 profile 均完成實際啟動驗證
exclusive 切換機制與 cache 持久化架構運作正常
目前以 27B 為日常預設運行中
架構分層（gb10 / Compose / host models+cache / image）維持不變
```
