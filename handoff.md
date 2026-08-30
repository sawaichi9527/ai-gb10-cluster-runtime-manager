# DGX Spark GB10 本地 AI 部署狀態交接（最新版）

> 更新日期：2026-08-29  
> 主機：NVIDIA DGX Spark / GB10  
> 主機名稱：`spark-25d5`  
> 使用者：`eye`  
> 區網 IP：`192.168.23.215`  
> 作業系統：Ubuntu 24.04 ARM64  
> 用途：本地 vLLM LLM 推理 + ComfyUI 生圖，以 Docker Stack 分離管理  
> 文件定位：接續 `GB10_Docker_Stack_Deployment_Handoff_2026-08-18.md`，記錄 2026-08-23 完成之 **27B 模型遷移 + Looping 修復 + 基準測試**，以及 2026-08-29 完成之 **vLLM 映像切換至 `omni`（v0.27.1-omni）+ v0.25.1/v0.26.0 除役 + omni vs v0.27.1 性能對比 + DFlash2 導入調查定案（留在 MTP）**。ComfyUI 與 35B 相關沿用 08-18 文件。

> **2026-08-30 追加 — 2-Node 叢集互連已建立**（本機為 Node 0，新增 Node 1 `spark-8095`）。詳見 `docs/cluster_interconnect_deployment_2026-08-30.md` 與 `docs/verification_cluster_connectivity_2026-08-30.md`。叢集入口摘要見下方 **# 13**。

---

# 1. 本次工作摘要

2026-08-23 完成（由 Windows 工作站經 Posh-SSH 直連操作）：

```text
1. 下載 sakamakismile/Qwen3.8-27B-AEON-ULTIMATE-UNCENSORED-NVFP4 (20.5 GB, 14 files, 29m21s, Xet)
   → ./models/qwen3.8-27b-aeon-ultimate-uncensored-nvfp4 (model.safetensors 19G + model-mtp-bf16 811M)
2. 備份 docker-compose.27b.yml → .bak-qwen36-20260823-1345，替換為 Qwen3.8 專用 compose
3. chat_template.jinja 預設 reasoning_effort xhigh → medium (避免 uncensored 模型長思考 looping)
4. speculative: qwen3_5_mtp (deprecated) → mtp
5. 27B 首次以 Qwen3.8 NVFP4 啟動驗證 READY (13m32s, init 577s)，二次重啟 (cache hit) 11m06s / 479s
6. 煙霧測試 + 單併發 benchmark (16-17 tok/s, prefill 2078 tok/s, 4併發 58.8 tok/s aggregate)
7. 舊 qwen3.6 模型目錄保留可 rollback，未刪 image
8. 目前運行：27B Qwen3.8 (日常預設)
```

核心原則不變：`gb10 = 操作層 / Compose = source of truth / Host bind = persistent / Image = 可替換`

---

# 1A. 2026-08-29 映像轉換：切換至 omni + 舊映像除役

2026-08-29 完成（由 Windows 工作站經 Posh-SSH `eye/20040401` 直連）：

```text
1. 除役 v0.25.1 與 v0.26.0：docker rmi 成功 (磁盘 root 274G → 237G)
2. Pull omni：ghcr.io/aeon-7/aeon-vllm-ultimate:2026-08-24-v0.27.1-omni (18.8GB, 73d790a870bd)
3. 27B 堆疊切換：.env AEON_IMAGE → :2026-08-24-v0.27.1-omni（備份 .env.bak-v0271-20260829-001127 供 rollback）
   compose 解析確認 image 為 omni（docker compose -f docker-compose.27b.yml config | jq '.services.vllm.image'）
4. 重啟 aeon-vllm（--force-recreate）：health 200，冷啟動 783s (13m03s)，
   version 0.27.1+aeon.sm121a.dspark，Available KV 42.19 GiB
5. 冒煙測試通過：GET /v1/models → aeon 229376；POST 2+2 → 200 reasoning/内容正常
6. Benchmark (raw /completions, 2026-08-29 15:xx)：
   decode 512/1024/2048 → 18.27/18.16/17.27 tok/s
   TTFB (stream) ~0.17s
   conc1/2/4 agg → 18.9/34.8/66.2 tok/s
7. 決策：接受 omni（不 rollback A/B），27B 日常切至 omni；v0.27.1 image 保留為 rollback
```

**性能結論（omni vs v0.27.1 08-23 記錄 §5.4，方向性比較，方法略異）**：單流 decode +6~10%（17.3-18.3 vs 16.3-17.8），concurrency aggregate +6~13%（conc4 66.2 vs 58.8），TTFB 極低 ~0.17s。冷啟動同 ~13min，KV 容量一致（42.19 GiB）。

**注意**：08-23 的 v0.27.1 數據以 chat 方式測量，本日 omni 以 raw `/completions` 測量，為方向性比較非嚴格 A/B（嚴格 A/B 需 rollback 重測，未執行，使用者接受）。

---



# 2. 參數變更總表（重點標記）

| 項目 | 變更前 (qwen3.6-27b 08-18) | 變更後 (qwen3.8-27b 08-23) | 原因 |
|---|---|---|---|
| **模型** | `qwen3.6-27b-aeon-mm-mtp` 26.59 GiB + `qwen3.6-27b-dflash` 3.22 GiB | `qwen3.8-27b-aeon-ultimate-uncensored-nvfp4` 19G + `model-mtp-bf16` 811M (總 20.5 GiB) | sakamakismile NVFP4 W4A4 (group16) 量化，源自 `AEON-7/Qwen3.8-27B-AEON-ULTIMATE-UNCENSORED-BF16`，MTP head 內建 bf16，無需外掛 drafter |
| **quantization** | `modelopt` (modelopt_fp4) | **移除 `--quantization` 參數** (`compressed-tensors` 自動偵測) | NVFP4 `nvfp4-pack-quantized` 由 `config.json:quantization_config` 自動識別，顯式指定會衝突；`ignore` 含 `visual` + `mtp.*` + `lm_head` |
| **kv_cache_dtype** | `fp8_e4m3` | `fp8` | sakamakismile 官方 serve 建議；Qwen3.8 NVFP4 與 `fp8` KV 搭配，實測 `Available KV 42.16 GiB` 容量翻倍 |
| **attention_backend** | `TRITON_ATTN` | `TRITON_ATTN` 保留 (實際 MTP 時自動選 `FLASHINFER` for decode) | 保持單變量，TRITON 仍兼容，FlashInfer 僅 autotune 階段使用 |
| **speculative** | `{"method":"dflash","model":"/drafter","num_speculative_tokens":12,"attention_backend":"TRITON_ATTN"}` | `{"method":"mtp","model":"/model","num_speculative_tokens":3}` | Qwen3.8 MTP head 內建於 `/model`，無需 `/drafter`；`n=3` 為官方 serve 基準，`n=6` 亦在 9-case gate 通過 (gotchas)，保留 `3` 保守 |
| **volumes** | `qwen3.6-27b-aeon-mm-mtp:/model:ro` + `qwen3.6-27b-dflash:/drafter:ro` + `cache:/root/.cache` | `qwen3.8-27b-...:/model:ro` + `cache:/root/.cache` | 移除 drafter mount，MTP 無需外掛 |
| **chat_template** | `reasoning_effort|default('xhigh')` (預設最高) | `reasoning_effort|default('medium')` (僅首個替換) | **Looping Trap 修復**：uncensored 去除拒絕後，`xhigh` 在長/邊緣問題上思考可 >18k 並重複循環；`medium` 實測 9-case (法英長文, temp 0/0.7, MTP n=6) 全部 1-3k 正常收斂 |
| **max_model_len** | `229376` | `229376` 保留 (tokenizer 支援 `262144`) | 保持單變量，避免 KV 壓力突增 |
| **KV 容量** | `32.72 GiB / 565,887 toks / 2.47x` | **`42.16 GiB / 1,171,404 toks / 5.11x`** | NVFP4 更省權重顯存，KV 餘裕翻倍 |

---

# 3. 模型來源與下載

* 上游：`sakamakismile/Qwen3.8-27B-AEON-ULTIMATE-UNCENSORED-NVFP4` (NVFP4 W4A4 group16, `compressed-tensors` 0.17.1, 基於 `AEON-7/Qwen3.8-27B-AEON-ULTIMATE-UNCENSORED-BF16`)
* 下載：`hf download ... --local-dir ./models/qwen3.8-27b-aeon-ultimate-uncensored-nvfp4` (需 `huggingface_hub[hf_transfer]` + `HF_XET_HIGH_PERFORMANCE=1`, GB10 上 `pip install --break-system-packages`), `14/14 files` `29m21s`, `Xet CAS` 模式 (`enP7s7 RX ~40 GB`)
* 驗證：`config.json:quantization_config.format nvfp4-pack-quantized`, `ignore` 含 `mtp.*`, `model.safetensors.index.json total_size 20559282592`
* 舊模型保留：`qwen3.6-27b-aeon-mm-mtp` + `dflash` 未刪

---

# 4. docker-compose.27b.yml (新)

```yaml
volumes:
  - ./models/qwen3.8-27b-aeon-ultimate-uncensored-nvfp4:/model:ro
  - ./cache:/root/.cache
command: serve /model
  --host 0.0.0.0 --port ${VLLM_PORT} --api-key ${VLLM_API_KEY}
  --served-model-name aeon --tensor-parallel-size 1 --dtype auto
  --kv-cache-dtype fp8  # was fp8_e4m3
  --attention-backend TRITON_ATTN
  --max-model-len ${VLLM_MAX_MODEL_LEN} --max-num-seqs ${VLLM_MAX_NUM_SEQS}
  --max-num-batched-tokens ${VLLM_MAX_BATCHED_TOKENS} --gpu-memory-utilization ${VLLM_GPU_MEMORY_UTILIZATION}
  --enable-chunked-prefill --enable-prefix-caching
  --generation-config vllm --reasoning-parser qwen3 --tool-call-parser qwen3_coder --enable-auto-tool-choice
  --mm-encoder-tp-mode data
  --speculative-config '{"method":"mtp","model":"/model","num_speculative_tokens":3}'  # was dflash
  --trust-remote-code
```

`docker compose config` 通過。image 由 `.env:AEON_IMAGE` 指定（**2026-08-29 起為 `ghcr.io/aeon-7/aeon-vllm-ultimate:2026-08-24-v0.27.1-omni`**，原 `2026-08-16-v0.27.1` 為主要 rollback；`.env.bak-v0271-20260829-001127` 存有 v0.27.1 設定）。

---

# 5. 啟動驗證

## 5.1 首次冷啟動 (2026-08-23 13:46:40 → 14:00:12 READY, 13m32s)

```text
Checkpoint 19.15 GiB Loading 149.61s
Drafter(MTP) 19.15 GiB Loading 44.58s
Model loading 19.31 GiB / 195.89s
torch.compile 69.53s + 10.04s (cache miss)
FlashInfer autotune 138 configs ~6m46s (6 iterations, 0.6.16.post3)
init engine 577.32s (compilation 79.57s)
Available KV 42.28 GiB / 1,174,289 toks / 5.12x
```

## 5.2 二次重啟 (cache hit, 14:05:48 → 14:16:54, 11m06s)

```text
Loading 118.47s + 34.05s
torch.compile 17.27s (vs 69.53s)
init engine 479.28s (compilation 25.15s)
Available KV 42.16 GiB / 1,171,404 / 5.11x
```

符合 08-18 觀察：`torch.compile` 快取命中大幅縮短，`FlashInfer` 仍重跑。

## 5.3 煙霧測試

```text
GET /v1/models → 200 aeon 229376
POST /v1/chat/completions (2+2) → 200 reasoning 61 toks / completion 256 (17.5 tok/s)
POST long French 5 eras (medium, max 600) → 200 reasoning ~800 chars / content 600 / length
POST long French (無顯式 medium, 預設 medium) → 200 正常 (已修補 xhigh→medium)
fingerprint: vllm-0.27.1+aeon.sm121a.dspark-b2529726
```

## 5.4 Benchmark (單機 TP=1, 08-23 14:29)

```text
Decode short 54 toks prompt:
  256 tok 14.3s 17.8 tok/s
  512 tok 31.1s 16.5 tok/s
 1024 tok 62.8s 16.3 tok/s

Prefill 8410 toks: 4.65s (含10 decode) ~2078 tok/s

併發 aggregate (各256):
  conc1 17.0 tok/s
  conc2 32.9 tok/s (16.5 /流)
  conc4 58.8 tok/s (14.7 /流)
```

對照 sakamakismile TP=4 69 tok/s 單流，TP=1 此值合理；`nvidia-smi GB10 49C 11W`

### 5.4b Benchmark — omni (2026-08-29, raw `/completions`)

```text
Decode (長文 essay prompt, raw /completions):
  512 tok 28.0s  18.27 tok/s
 1024 tok 56.4s  18.16 tok/s
 2048 tok 118.6s 17.27 tok/s
TTFB (stream): 0.195 / 0.154 / 0.174s

Prefill (~3900 toks): ~1384 tok/s

併發 aggregate (各512, raw /completions):
  conc1 18.9 tok/s
  conc2 34.8 tok/s (17.39 /流)
  conc4 66.2 tok/s (16.55 /流)
```

對照 §5.4 v0.27.1：omni 單流 decode +6~10%，conc agg +6~13%，TTFB 極低。方法略異（v0.27.1 用 chat / omni 用 raw completions），為方向性比較。

## 5.5 Mounts / Cache

```text
qwen3.8-27b-aeon-ultimate-uncensored-nvfp4 → /model (ro)
cache → /root/.cache (rw)
cache/vllm-35b 仍隔離，35B 未受影響
```

---

# 6. 系統資源

```text
Mem 121 GiB, 啟動期間 used 82Gi, available 39Gi, Swap 153Mi si/so=0
磁碟 root 3.7T 已用 274G 可用 3.3T, image 三版本 137G, models 共 ~58G (qwen3.6 27G+3.3G, 35B 22G+0.7G, qwen3.8 20G)
```

---

# 7. 維護通道

沿用 08-18：`Posh-SSH` password (`eye/20040401`)，`id_gb10_maint` 仍 host-bound 簽章失敗。

---

# 8. Rollback SOP (Qwen3.8 → Qwen3.6)

```bash
cd ~/docker-stacks/aeon-vllm
cp docker-compose.27b.yml.bak-qwen36-20260823-1345 docker-compose.27b.yml
# 若曾改 chat_template，需還原：cp models/qwen3.8/.../chat_template.jinja.bak-xhigh chat_template.jinja
docker compose -p aeon-vllm -f docker-compose.27b.yml up -d --force-recreate
docker inspect aeon-vllm --format '{{.Config.Image}}'
curl -i http://127.0.0.1:1234/health
```

舊模型目錄 `qwen3.6-27b-aeon-mm-mtp` 與 `dflash` 仍保留，無需重下載。

## 8b. Rollback SOP — omni → v0.27.1 (2026-08-29)

```bash
cd ~/docker-stacks/aeon-vllm
# 還原 .env (AEON_IMAGE 回 v0.27.1)，保留之備份供回退：
#   cp .env.bak-v0271-20260829-001127 .env
# 或手動 sed：AEON_IMAGE → ghcr.io/aeon-7/aeon-vllm-ultimate:2026-08-16-v0.27.1
docker compose -p aeon-vllm -f docker-compose.27b.yml up -d --force-recreate
docker inspect aeon-vllm --format '{{.Config.Image}}'
curl -i http://127.0.0.1:1234/health   # 冷啟動 ~13min 後 200
```

兩映像（omni 73d790a870bd / v0.27.1 eacd0eef2346）皆保留於本機。

---

# 9. 操作禁忌 (新增)

```text
不要刪除 qwen3.8 內 15 個 mtp.* 的 bf16 (quantization_config.ignore)
不要以 xhigh (預設) 在 uncensored 上跑長文/邊緣問題 (必用 medium, 1-3k)
不要因 KV 從 32→42 GiB 就貿然提高 gpu-memory-utilization (先觀察併發)
不要把 qwen3_5_mtp 當作永久寫法 (已改 mtp)
不要刪除 27B 容器與 model 目錄；不要刪除 v0.27.1 image (目前主要 rollback 目標)
  → 已於 2026-08-29 除役 v0.25.1 / v0.26.0 (舊三版本規則已更新，現只留 v0.27.1 + omni)
```

---

# 10. 部署完成狀態 (2026-08-23，含 08-29 omni 追加)

```text
[OK] 27B Qwen3.8 NVFP4 下載 20.5G 14/14
[OK] docker-compose.27b.yml 遷移 (modelopt→compressed-tensors, fp8_e4m3→fp8, dflash→mtp, 移除 drafter)
[OK] chat_template 預設 medium (looping 修復)
[OK] 27B Qwen3.8 首次冷啟動 13m32s / 二次 11m06s / health 200 / 推論 200
[OK] 單併發 17 tok/s, 4併發 58.8 tok/s aggregate
[OK] KV 42.16 GiB / 1.17M toks / 5.11x
[OK] Mounts host bind, 舊模型保留
[OK] 35B 未動 (沿用 08-18)
[OK] Swap <200Mi

--- 2026-08-29 omni ---
[OK] 除役 v0.25.1 / v0.26.0 (docker rmi, root 274G→237G)
[OK] Pull omni 2026-08-24-v0.27.1-omni (18.8GB)
[OK] .env AEON_IMAGE → omni (備份 .env.bak-v0271-20260829-001127)
[OK] 重啟 27B → health 200 / 冷啟動 783s / version 0.27.1+aeon.sm121a.dspark / KV 42.19 GiB
[OK] 冒煙 2+2 → 200 / /v1/models aeon 229376
[OK] omni bench: decode 18.27/18.16/17.27, TTFB ~0.17s, conc agg 18.9/34.8/66.2
      (對比 v0.27.1: 單流+6~10%, conc agg +6~13%)
[OK] 目前運行：27B Qwen3.8 @ omni (日常預設)；v0.27.1 image 保留為 rollback
```

---

# 11. 後續建議

```text
1. 正式 benchmark 補齊 (TTFT, 1/2/4/8 conc, prefix cache)
2. ~~評估 mtp n=3 → 6 的增益~~ / 新增：DFlash2 導入調查已定案「留在 MTP」（見 §11b）；日後若要再挑戰，先依 §11b 觸發流程在 omni 上做最小冒煙測試
3. 修復 Windows ssh 金鑰 host-bound 問題
4. 35B + Qwen3.8 共存壓力測試
5. 評估 qwen3.6 舊模型/ v0.25.1 image 除役時機
```

---

# 11b. 2026-08-29 DFlash2 導入調查 — 定案：留在 vLLM MTP（維持現狀）

> 研究目標：是否將 spec-decode 從 MTP 升級至 **DFlash2**（`z-lab/Qwen3.8-27B-DFlash2`），搭配 sakamakismile AEON NVFP4 target，以取得 2.5x 倍單流增益。經完整搜尋與架構比對後定案：**不導入，留在 MTP**。

## 結論摘要

```text
1. 目標配對（AEON-7 官方優化 + DFlash2）的斷點：
   - AEON-7 官方尚未發布 Qwen3.8-27B NVFP4（僅 BF16 Early-Access）。
   - 可用 NVFP4 是 sakamakismile 社區版；其官方 model card 指定的 spec-decode = qwen3_5_mtp n=3（即現況），非 DFlash。
   - z-lab DFlash2 drafter 是針對 stock Qwen/Qwen3.8-27B 的 argmax 訓練，非 AEON uncensored。

2. 「vLLM v0.27.1-omni (AEON) + sakamakismile AEON NVFP4 + z-lab DFlash2」無任何公開實證：
   - 所有 GB10 上 vLLM+DFlash2+NVFP4 的可用數字（liuzl 45.17 tok/s C1、techprototyper 生產 45.6 tok/s、
     vllm #53435 GB10 69.6 tok/s C1）皆為 stock/nightly vLLM，非 AEON omni 映像；且 target 皆
     RadixArk/Inferact/unsloth/FP8，非 sakamakismile AEON。

3. omni 映像 DFlash2 loader 狀態為已知風險：
   - DFlash2 的 decoder_layer_cls indirection 已回歸兩次（#52816 加入 → #52560 移除 → #53435 修復）。
   - omni 以 v0.27.1 為基底 + cherry-pick #52816，其 qwen3_dflash.py 是否處於已回歸
     （layers.0.attention_conv 載入失敗）狀態未定，需在 Spark 上實測才能判定。

4. 走 SGLang 則需全新 stack（新容器 + 與現有 27b/35b vLLM 並存/取代 + rollback），成本高、AEON 版
   acceptance 仍需實測。

5. 對照數字（供日後參考）：
   - SGLang 已驗證路徑（target 皆非 AEON）：Weschera 42.04 tok/s、salient-data 27.55 (prose)/74.17 (code-edit)、
     Kearuga ~65 tok/s C1。
   - 現況 MTP n=3 @ omni：decode 17.3-18.3 tok/s 單流。零新增風險。
```

## 日後若再挑戰 DFlash2（依序驗證）

```text
[觸發] 先對現有 omni 映像做最小冒煙測試：
  --speculative-config '{"method":"dflash","model":"/path/to/z-lab/Qwen3.8-27B-DFlash2","num_speculative_tokens":7}'
  + --trust-remote-code + VLLM_ALLOW_LONG_MAX_MODEL_LEN=1 + kv-cache fp8/auto

  - 若出現 "There is no module or parameter named 'layers.0.attention_conv'"
    → omni 處於已回歸狀態，需補 #53435 / #53662 修補（不可直接上），或改走 SGLang。
  - 若 accept = 0% / 變慢
    → MRv2 / target-head 對齊問題（AEON 多模態 qwen3_5 目標的相容性未驗證，makers 只對 stock 驗證）。
  - 若 accept>0 且提速，才考慮正式切至 DFlash2。

[AEON target 的正面訊號] sakamakismile AEON NVFP4 把 lm_head 保留在 BF16（未 packed），
  較 RadixArk 的 packed head 更符合 DFlash2 candidate selector 對『未量化 head』的需求（見 #52883）。

[引擎取捨] omni 測不過 → 才評估 SGLang 路徑
  （lmsysorg/sglang:qwen38-27b-dflash2，需 #35496 quantized-lm_head 支援）。
```

**本定案不變更現有部署**：27B Qwen3.8 @ omni + MTP n=3 維持日常預設。無新容器、無源碼改動、無 rollback。

---

# 12. 下一位接手先跑

```bash
gb10 status 2>/dev/null || ~/bin/gb10 status
docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Image}}'
docker inspect aeon-vllm --format '{{.Config.Image}}'
docker inspect aeon-vllm --format '{{range .Mounts}}{{println .Source " -> " .Destination}}{{end}}'
curl -i http://127.0.0.1:1234/health
curl -s http://127.0.0.1:1234/v1/models -H "Authorization: Bearer $VLLM_API_KEY" | python3 -m json.tool | head -n 20
free -h; swapon --show
```

預期：`aeon-vllm Up`, `qwen3.8-27b-... → /model`, `health 200`, `served aeon Qwen3.8`.

---

# 13. 2026-08-30 叢集互連（2-Node，本機為 Node 0）— 入口摘要

> 完整報告見 `docs/cluster_interconnect_deployment_2026-08-30.md`；本次完成 B1/B2/C/A 四階段 + Phase 1（Node1 拉齊）+ Phase 2（NCCL 冒煙），成案判定見 `docs/verification_cluster_connectivity_2026-08-30.md`。

```text
節點角色（明日固定 IP）：
  Node 0 (本機)  spark-25d5  192.168.23.215   (維持)
  Node 1         spark-8095  192.168.23.129 → 明日改 192.168.23.216
  兩台使用者 eye / 20040401

互連（單條 QSFP DAC, Left Port 0, 200GbE, MTU 9000）：
  enp1s0f0np0   → 10.0.101.0/24   Node0 .101 | Node1 .102
  enP2p1s0f0np0 → 10.0.102.0/24   Node0 .101 | Node1 .102
  管理網 192.168.23.0/24 之 IPv6 已在兩台 disabled（enP7s7）

已完成（Phase A/B/C + Phase 1 + Phase 2）：
  [OK] 管理介面 IPv6 徹底 disabled（兩台）
  [OK] netplan 40-cx7.yaml 互連 IP + MTU 9000（兩台）→ netplan apply
  [OK] 互連互通：10.0.101/102 四方向 ping + jumbo 8972 全通過
  [OK] SSH 免密雙向（互連 IP 10.0.101.x）：
        Node0→Node1  spark-8095 / Node1→Node0  spark-25d5
        各自空 passphrase ed25519 (~/.ssh/id_gb10_cluster)，既有 keys 全保留
  [OK] Node1 eye 加入 docker 群（重登入生效）；docker-stacks + ~/bin/gb10 symlink 對齊
  [OK] Node1 映像對齊：cuda 13.0.1 base + omni 2026-08-24-v0.27.1-omni
        （GHCR 直拉因 registry retry 抖動失敗 → 改 Node0 docker save → scp 互連
        ~820MB/s → sudo docker load；on Node1 image ID 04f01d0df91d，與 Node0 不同屬正常）
  [OK] Node1 models/ 對齊：5 目錄共 72G（與 Node0 相同）；key 檔 sha256 兩台一致
  [OK] Node1 單機冒煙：torch 2.13.0+cu130 / GB10 GPU 可見 / vllm 0.27.1+aeon.sm121a.dspark
  [OK] NCCL smoke test（跨機 gate）：兩 rank 同步 allreduce 1GB×10
        alg_bw=2.15 GB/s（bus ≈ 4.3 GB/s），NCCL 2.29.7+cuda13.2，data 走互連
        （NCCL_SOCKET_IFNAME=enp1s0f0np0, MASTER_ADDR=10.0.101.101, TCP init）
         → 多節點 vLLM tensor-parallel 前置條件成立

尚未做（後續里程碑）：
  [ ] 多節點 vLLM --tensor-parallel-size 2（VLLM_HOST_IP/控制器走互連 IP）
  [ ] 明日 Node1 管理 IP 改固定 192.168.23.216 後，複驗互連/SSH 免密不受影響
  [ ] Node1 正式 gb10 操作（重登入後 eye 免 sudo docker）
```

**今日關鍵坑**：`ssh-keygen -N ""` 經 Posh-SSH/引號通道會產出**帶 passphrase** 的 key 導致免密失敗；正確做法是**本機 (Windows) ps1 產空 passphrase key → base64 上傳私鑰 + 追加公鑰**（本文件 §2.4 有完整除錯紀錄）。另：Posh-SSH 巢狀 `bash -c "...| sudo -S ... "` 會被引號地獄吃掉管線（sudo 1 次密碼錯誤）；長命令/多步任務一律先寫 `.sh` **再 nohup** 執行。

---

# 14. 2026-08-30 跨機 TP2（2-Node vLLM tensor-parallel）— 實測結果

> 本次在 §13 叢集互連之上，完成 **跨機 TP=2 引擎實測**：單一 27B 模型 split 兩台 GB10。**成案成功**。且**推翻 §11b 舊定案**（DFlash2「留在 MTP」）——DFlash2 drafter 已在 omni 上實測 **accept 51.4%**。
>
> **重要修正（Ray）**：先前主管/文件稱「TP2 需 Ray + LiteLLM」為**錯誤認知**。AEON omni 官方 dual-Spark TP=2 配方**不用 Ray**，用原生 **`mp` backend + `--nnodes 2 --node-rank {0,1}`**；`--distributed-executor-backend` 保持預設（非 ray）。本次全程**無 Ray、無 RAY_ADDRESS、無 `ray start`**；通訊全走 NCCL（`cuda_communicator: Using ['PYNCCL'] for group tp`）。**LiteLLM 亦未上**（每組合≤1 LLM，直連 :8000）。

```text
節點角色（沿用 §13）：
  Node 0 spark-25d5 10.0.101.101（API server, rank 0, --port 8000）
  Node 1 spark-8095 10.0.101.102（headless worker, rank 1, --headless）
  RoCE：rocep1s0f0 ↔ enp1s0f0np0，GID[3]=::ffff:10.0.101.x (RoCE v2)，PORT_ACTIVE，MTU 4096, 200GbE

TP2 引擎命令核心（27B + DFlash2，Node0 = API / Node1 = 同引擎參數但 --headless --node-rank 1、
   無 frontend 旗標）：
  -e VLLM_HOST_IP=10.0.101.10x -e NCCL_SOCKET_IFNAME=enp1s0f0np0 -e GLOO_SOCKET_IFNAME=enp1s0f0np0
  -e NCCL_IB_HCA=rocep1s0f0:1 -e NCCL_IB_GID_INDEX=3 -e PYTORCH_CUDA_ALLOC_CONF=expandable_segments:True
  --device /dev/infiniband --cap-add IPC_LOCK --ulimit memlock=-1:-1
  serve /model --tensor-parallel-size 2 --nnodes 2 --node-rank {0|1}
    --master-addr 10.0.101.101 --master-port 29501
    --quantization compressed-tensors --kv-cache-dtype fp8_e4m3 --attention-backend TRITON_ATTN
    --max-model-len 262144 --max-num-seqs 8 --max-num-batched-tokens 16384 --gpu-memory-utilization 0.85
    --disable-custom-all-reduce --enable-chunked-prefill --no-enable-prefix-caching
    --compilation-config '{"cudagraph_mode":"FULL_AND_PIECEWISE"}'
    --speculative-config '{"method":"dflash","model":"/drafter","num_speculative_tokens":7,"attention_backend":"TRITON_ATTN"}'
    --trust-remote-code
  mounts 兩台相同：qwen3.8-27b-aeon-ultimate-uncensored-nvfp4:/model:ro , qwen3.8-27b-dflash2:/drafter:ro
  image：ghcr.io/aeon-7/aeon-vllm-ultimate:2026-08-24-v0.27.1-omni（兩台同 slim e62ac10d）

DFlash2 drafter（z-lab/Qwen3.8-27B-DFlash2，incoai mirror）已同步兩台 /models/qwen3.8-27b-dflash2：
  - Node0 下載：git clone + git lfs pull（model.safetensors 3,848,817,896 B real, BF16, DFlash2DraftModel）
  - Node0→Node1 互連 rsync（exclude .git，~3.6G，real file 非 symlink）
  - config：block_size 8, target_layer_ids [5,19,33,47,61], is_causal:false, max_window_layers 5
    → 應配 --kv-cache-dtype fp8_e4m3（DFlash non-causal 不支援 NVFP4 KV）＋ n=7（block 8）

實測結果（2026-08-30 14:2x）：
  [OK] world_size=2 rank=0/1, TP rank 0(N0)/1(N1)，跨 RoCE NCCL (nccl 2.29.7)
  [OK] DFlash2DraftModel resolved（兩機）＋ Avg Draft acceptance rate 48.2%→51.4%（逐位置 up to 0.875）
        → DFlash2 有效，非空轉（§11b 舊疑慮已實測解除）
  [OK] Available KV cache 85.68/85.52 GiB（兩機彙總，單機 ~42GiB → 跨機近倍增）
  [OK] max_model_len 262144（DFlash2 上限 262144 內；>262K 需 remove drafter）
  [OK] :8000/health OK → /v1/models aeon 262144
  [OK] 功能冒煙 <HELLO-TP2-OK>
  [OK] 8 併發 × 3 rounds 全過：~227/275/286 comp-tok/s（對比官方單機 c=8 ~126-144）
  [OK] --disable-custom-all-reduce 帶入（custom all-reduce 是單機 NVLink 路徑，跨機必關）
  GB10 unified-memory：nvidia-smi util/mem 回報 [N/A]/0% 屬正常，非無負載（引擎吞吐為真值）

既有資產指路：
  - 27B DFlash2 drafter：/home/eye/docker-stacks/aeon-vllm/models/qwen3.8-27b-dflash2（兩台）
  - 27B TP2 啟動：/tmp/launch_tp2_node0.sh（N0 API）＋ /tmp/launch_tp2_node1.sh（N1 worker）→ docker run -d
  - 冒煙：smoke_tp2b.sh / 並發：load_tp2.sh（8-way ×3）
  - check：check_tp2c.sh（health/models/RDMA）、check_nccl.sh（NCCL env/backend）

⚠️ 目前狀態：兩台 TP2 冒煙容器（tp2-node0 / tp2-node1）**仍在跑**（非日常單機）。推進 35B-A3B TP2 前
  先 `docker rm -f tp2-node0 tp2-node1`；回到日常單機 27B 需重啟 aeon-vllm stack。

### 35B-A3B + DFlash TP2 冒煙 — 亦全過（2026-08-30 14:5x）
> 與 27B 同配方，換 body/drafter。鏡像未動（同 slim e62ac10d）。

  body  qwen3.6-35b-a3b-heretic-nvfp4 (Qwen3_5MoeForConditionalGeneration, compressed-tensors/nvfp4-pack-quantized)
  drafter qwen3.6-35b-a3b-dflash (DFlashDraftModel v1, block_size 16, targets [1,6,11,16,22,27,32,37], 6 layers)
  spec  num_speculative_tokens 11 (≤ block 16，沿用 08-18 單機定案)
  GMU   0.80 pure（35B MoE body 23GB 較大，未加側車）
  max-model-len 131072（35B 未強制 262K cap；DFlash v1 非 DFlash2，無 262K 互斥）

  [OK] world_size=2 rank=0/1, TP rank 0/1, **EP rank 0/1**（MoE experts 跨機分工）
  [OK] Qwen3_5MoeForConditionalGeneration + DFlashDraftModel resolved（V2 Model Runner）
  [OK] Available KV cache 79.73 GiB（跨機彙總，單機 ~40GiB）
  [OK] max_model_len 131072, :8000/health OK
  [OK] chat 冒煙 content '\n\nHELLO-TP2-OK' finish stop
        ※小中招：chat max_tokens 64 時 content=None（Qwen3 MoE thinking 吃掉 64 tokens）——加大 max_tokens
          即出答案，非模型故障；純 /v1/completions 亦正常出文
  [OK] DFlash v1 acceptance 非 0：Avg Draft acceptance 26.6%→81.8%，per-position up to 1.000（MoE 有效）
  [OK] 8 併發 ×3 rounds：~402/556/533 comp-tok/s（35B-A3B active-3B，比 27B-DFlash2 更快，符合預期）

  → 35B 主力組合跨機 TP2 成立，Phase B1 全部完成（27B + DFlash2 與 35B + DFlash 雙配方皆驗證）。

尚未做（Phase B2+ 後續）：
  [ ] dual-GMU 切換 script（pure / sidecar）→ Phase B2 併 ComfyUI 側車
  [ ] Phase C：組合 6 全停 → TP1 分站（N0 27B + N1 ComfyUI，無 Ray/LiteLLM）
  [ ] 明日 Node1 管理 IP 改 192.168.23.216 後複驗互連/TP2 不受影響
```

---

# 15. 2026-08-30 repo 建立 + TP2 scriptization + 實地驗證

> 依主管指令：① TP2 雙配方（27b default / 35b）script 化並 git 化；② 於 forgejo 建立兩公開 repo；③ 在 Node0 實地完整驗證。**全部完成並通過。**

## 15.1 forgejo 兩公開（open）repo

| repo | 網址 | 用途 |
|------|------|------|
| `829522/ai-gb10-cluster` | http://192.168.23.167:3000/829522/ai-gb10-cluster | **TP2 叢集管理**：deploy / healthcheck / 揪錯 / smoke / scenario 切換 |
| `829522/gb10-single` | http://192.168.23.167:3000/829522/gb10-single | **單 spark 部署**：照搬主機現況（gb10 CLI + compose + runtimes） |

- 皆 **open/public**、default branch `main`、可匿名 clone（Node0 實測 `git clone` 免認證成功）。
- push 用 forgejo MCP token（`opencode.jsonc`），HTTPS push 後立即還原 remote URL 為乾淨公開網址——token 不存 `.git/config`。

## 15.2 ai-gb10-cluster 內容（Node0 單側編排，無 Ray/LiteLLM）

- Node0 有 repo + scripts（`~/ai-gb10-cluster/`）；**Node1 不需 repo**，只經 ssh 起 headless worker。
- `scripts/`：`tp2-common.sh`（env 載入 + 雙 profile 參數表 + `sdk` docker 助手 + `n1` ssh 助手）、`tp2-up [27b|35b]`、`tp2-down`、`tp2-status`、`tp2-smoke`、`tp2-load`。
- `tp2.env`（**gitignored**，由 `tp2.env.example` 複製填值）含 IMG / NODE*_IP / MASTER_ADDR/PORT / NCCL RoCE v2 / API_PORT / VLLM_API_KEY / SUDO_PASS。
- profile 參數（與 §14 實測一致）：27b → body `qwen3.8-27b-...nvfp4` + drafter `qwen3.8-27b-dflash2`、dflash n=7、maxlen 262144、GMU 0.85、num_seqs 8；35b → `qwen3.6-35b-a3b-heretic-nvfp4` + `qwen3.6-35b-a3b-dflash`、n=11、maxlen 131072、GMU 0.80、num_seqs 16。

## 15.3 Node0 實地完整驗證（全部通過）

在 Node0 `~/ai-gb10-cluster/` 依序執行流水線：

```
tp2-down → tp2-up <profile> → tp2-status → tp2-smoke
```

- **27b（default）**：
  - `tp2-down` 清掉 §14 既有容器；`tp2-up 27b` 冷啟動 ~7.5 min → `README on :8000`。
  - `tp2-status`：兩節點容器 Up、health READY、`/v1/models` aeon `max_model_len:262144`、`world_size=2 rank=0`、`Available KV cache 85.54 GiB`（對 §14 之 85.68/85.52）。
  - `tp2-smoke`：`finish_reason stop`、content `\n\nHELLO-TP2-OK`、http=200。
- **35b（scenario 切換）**：`tp2-down`（清 27b）→ `tp2-up 35b` 冷啟動 ~7.2 min → READY。
  - `tp2-status`：`max_model_len:131072`、GMU 0.8、n=11、num_seqs 16、KV `79.72 GiB`（對 §14 之 79.73）。
  - `tp2-smoke`：content `\n\nHELLO-TP2-OK`、http=200。

→ **雙配方 scenario switching 完全 script 化且實地驗證可行。**

## 15.4 驗證中發現並修正的 bug

- `tp2-status` 原 grep `/tmp/tp2-node0.log`，但該檔對 detached `docker run -d` 只含 container hash（vLLM logs 在 `docker logs tp2-node0`）。改為 `sdk docker logs tp2-node0`。commit `dbb4709`，push 後 Node0 `git pull` 複驗顯示 KV/world_size 資訊正常。RDMA/NET 段仍空（log 未含那些固定字串），屬可接受。

## 15.5 目前狀態與 repo 位置

- 本機（Windows）repo 工作副本：`C:\Users\Sawaichi\AppData\Local\Temp\opencode\gb10-repos\{ai-gb10-cluster, gb10-single}`（remote 皆乾淨無 token）。
- Node0：`~/ai-gb10-cluster/`（git clone，`git pull` 即可更新）、`tp2.env` 已建（gitignored）。
- **驗證後 TP2 回到 35B**：`tp2-node0`（N0 API）/ `tp2-node1`（N1 headless）Up，含 dflash n=11 + KV 79.72 GiB。
- 回到日常單機 27B：`tp2-down` 停 TP2，再啟 `~/bin/gb10` 單機 stack（見 §12）。
```

---

# 16. 2026-08-31 repo 統一重構：ai-gb10-cluster-runtime-manager + gb10/gb10-single CLI 分流

> 依主管指令：將舊單節點 `~/docker-stacks/ai-runtime-manager` 與 TP2 `~/ai-gb10-cluster` **兩套管理**整併為單一統一 repo **`~/ai-gb10-cluster-runtime-manager`**，並分離 `gb10`（cluster）與 `gb10-single`（單機）兩支 CLI。**全部完成並實地驗證。**

## 16.1 目錄與 repo

- forgejo repo 由 `829522/ai-gb10-cluster` **改名**（id 10 保留）→ `829522/ai-gb10-cluster-runtime-manager`
  - `http://192.168.23.167:3000/829522/ai-gb10-cluster-runtime-manager`（open/public、匿名 clone、history 保留、default branch `main`）
  - 舊單機 repo `829522/gb10-single` 仍存在，但已由本統一 repo 之 `bin/gb10-single` 取代（新統一 repo 為唯一 source of truth）
- 統一 repo 結構（git 追蹤）：

```text
ai-gb10-cluster-runtime-manager/
├── bin/
│   ├── gb10            → TP2 cluster CLI（wrapper over scripts/tp2-*）
│   └── gb10-single     → 單機 CLI（node0 本地 / node1 SSH；runtimes.d/*.conf）
├── runtimes.d/
│   ├── 27b.conf  35b.conf              （deployed，exclusive/llm）
│   ├── comfyui.conf  minimaxh3.conf    （placeholder；comfyui GROUP=image、minimaxh3 GROUP=video）
│   └── deepseek.conf qwen38flash.conf glm53flash.conf  （placeholder，llm）
├── scripts/  tp2-common.sh tp2-up/down/status/smoke/load
├── docs/     TP2_DEPLOYMENT_2026-08-30.md  RESTRUCTURE_2026-08-31.md
├── README.md  AGENTS.md  .gitignore  tp2.env.example
```

- git commit：`b4ebcd3`（統一 + CLI + placeholders）、`4eacd8a`（symlink BASH_SOURCE bugfix）。

## 16.2 CLI 分流（設計原則）

| | `gb10` | `gb10-single` |
|---|---|---|
| 範圍 | TP2 2-node cluster（exclusive） | 單節點獨立 / add-on runtime |
| 預設執行 | Node0 編排兩節點 | node0 本地 / node1 經 `~/.ssh/id_gb10_cluster` SSH |
| 用法 | `use/start/stop/restart {27b\|35b\|...}`、`status/logs/smoke/load/doctor/list` | `use/start/stop/restart {node0\|node1} <runtime>`、`list/status/logs/doctor` |
| runtime 定義 | 內建 profile（27b default / 35b） | `runtimes.d/*.conf` |

- `gb10 use <profile>` 為 exclusive（cluster 只有一份 LLM）。
- `gb10-single list node0` 列出 7 runtimes；placeholder 顯示 `placeholder` 狀態。
- 新增模型（deepseek/qwen38flash/glm53flash、minimaxh3=video、comfyui 新版）落定後：補 conf STACK/COMPOSE 並取消 `PLACEHOLDER=true`。
- Node1 仍 headless（無 repo）；`gb10-single node1` 僅對 placeholder 生效（exit 0），comfyui 為 CLI-only skip sync。

## 16.3 Node0 部署 + Node1 清理（實地完成）

- **Node0**：舊 `~/docker-stacks/ai-runtime-manager` 與 `~/ai-gb10-cluster` 已刪除；新 repo clone 至 `~/ai-gb10-cluster-runtime-manager/`；`tp2.env`（gitignored secret）自舊 clone 還原；`~/bin/gb10`、`~/bin/gb10-single` → repo `bin/` 之 symlink。
- **Node1 (spark-8095, 192.168.23.129)**：`~/docker-stacks/ai-runtime-manager` 已清除，`~/bin/gb10` 舊 symlink 已移除（Node1 維持 headless 無 repo）。

## 16.4 驗證（Node0 實地全過）

```text
gb10 list                       → 5 profile（27b default / 35b / deepseek / qwen38flash / glm53flash placeholder）
gb10 use deepseek               → ERROR placeholder exit 1（正確）
gb10-single list node0          → 7 runtimes：27b/35b inactive；comfyui(image)/deepseek/
                                  glm53flash/qwen38flash(llm)/minimaxh3(video) placeholder
gb10-single use node0 deepseek  → placeholder exit 0（正確）
gb10-single use node1 comfyui   → placeholder exit 0（正確）
gb10 status                     → TP2 完整：tp2-node0/1 Up、RDMA/KV 讀取、health READY、/v1/models aeon 131072
```

- **驗證後 TP2 仍在線**：35B-A3B（master_addr 10.0.101.101、max_seq_len 131072、n=11、KV 79.72 GiB）— 重構未中斷運行中之 cluster。

## 16.5 發現並修正的 bug

- **symlink BASH_SOURCE**：CLI 自 `~/bin/gb10`（symlink）執行時，`dirname ${BASH_SOURCE[0]}` 取到 `/home/eye/bin`（symlink 路徑未解析）→ REPO_DIR 誤判 `/home/eye` 導致找不到 scripts/runtimes.d。修法：以 `readlink -f -- "${BASH_SOURCE[0]}"` 解析 real path 後再取 dirname。commit `4eacd8a`，Node0 `git pull` 複驗全過。

## 16.6 註記與後續

- 後續新模型落地：改 placeholder conf、重寫 `bin/gb10-single` 之 runtime 列舉即可；TP2 新 profile 需補 `scripts/tp2-common.sh` 參數表 + `runtimes.d/<name>.conf`。
- 本機（Windows）統一 repo 的工作副本：`C:\Users\Sawaichi\AppData\Local\Temp\opencode\merge-target`（remote 乾淨無 token）。
- **Node1 管理 IP 改 192.168.23.216**：依主管指示**待 8 小時後（9AM）**再處理——改 IP 後需複驗互連/SSH 免密/TP2 不受影響。目前為暫緩項目。

# 17. 2026-08-31 ComfyUI（Flux 2 Dev）部署 — Node1 專屬（Stage 1 完成並驗證）

> 依專案階段：Stage 1 = 單節點 ComfyUI on Node1（dedicated），用 AEON `comfyui-aeon:slim` + Flux 2 Dev，驗證門 = 產出 Flux 2 圖片。已全部完成並實地驗證。Node1 與 Node0 **無共享儲存**（兩份獨立 copies）。

## 17.1 重點結果

- ✅ Node1 `comfyui-aeon:slim` 映像已拉取（digest `7fda74d7af1d`，與 Node0 一致）
- ✅ Flux 2 Dev 全模型下載 ~71 GB 並拍平到 ComfyUI 結構（見 17.3）
- ✅ TP2-down（兩節點停機）釋放 Node1 記憶體 → `gb10-single use node1 comfyui` 啟動 → **healthy**
- ✅ Flux 2 Dev t2i 出圖驗證通過：`output/flux2_n1_verify_00001_.png`（1,332,159 bytes），`20/20 [00:54]`、`Prompt executed in 303.39s`

## 17.2 CLI 分流與 exclusive 切換

- `runtimes.d/comfyui.conf`：`MODE=exclusive`、`GROUP=image`、`STACK_DIR=${HOME}/docker-stacks/comfyui-aeon`、`CONTAINER=comfyui-spark`、HEALTH_URL `http://127.0.0.1:8188/system_stats`、TIMEOUT 900。
- `DISPLAY_NAME="AEON ComfyUI (Node1 dedicated · Flux 2.0 Dev)"`（已從 placeholder 改為正式，commit `f218651` via Forgejo API）。
- ⚠️ `GROUP=image`：`gb10-single use node1 comfyui` **不會**停 TP2（GROUP=llm）。TP2 停用走 `scripts/tp2-down`（Node0，全 2 節點）。本次預先同意「tp2-down → ComfyUI」。
- Node0 仍 headless（無 repo）；`gb10-single node1` 對 comfyui 生效（此次已真正啟動，非 placeholder）。

## 17.3 Flux 2 Dev 模型（~71 GB，Node1 獨立）

| 檔案 | 位置 | 大小 |
|---|---|---|
| `flux2_dev_fp8mixed.safetensors`（Comfy-Org/flux2-dev） | `models/diffusion_models/` | 35.46 GB |
| `mistral_3_small_flux2_bf16.safetensors`（text encoder，best quality） | `models/text_encoders/` | 35.58 GB |
| `flux2-vae.safetensors` | `models/vae/` | 336 MB |
| `full_encoder_small_decoder.safetensors`（FLUX.2-small-decoder） | `models/vae/` | 250 MB |
| `Flux2TurboComfyv2.safetensors`（turbo LoRA） | `models/loras/` | 2.76 GB |

- Node1 需 HF token（gated access），自 Node0 經 scp（`~/.ssh/id_gb10_cluster`）複製至 `workspace/.cache/huggingface/token`。
- AEON `download_models.py` 是 all-or-nothing（Flux 2 Dev-first，含 LTX 2.3）。本次用 selective downloader 只取 Flux 2 Dev。

### ⚠️ 關鍵坑：`split_files/` 巢狀路徑

`hf_hub_download(local_dir=...)` 寫入 `<sub>/split_files/<sub>/file.safetensors`；ComfyUI 掃描 model 目錄**不遞迴**，須**拍平**（檔案為 root 擁有，需 sudo）：
```bash
echo "$SUDO_PASS" | sudo -S mv \
  models/diffusion_models/split_files/diffusion_models/flux2_dev_fp8mixed.safetensors \
  models/diffusion_models/flux2_dev_fp8mixed.safetensors
```
拍平後刪空 `split_files` 樹。驗證：`curl http://127.0.0.1:8188/models/<sub>` 回傳檔名。

## 17.4 出圖 workflow 注意事項

Flux 2 Dev 是 **diffusion model** → 用 `UNETLoader`（**非** `CheckpointLoaderSimple`），搭配 `CLIPLoader`、`VAELoader`、`FluxGuidance`、`Flux2Scheduler`、`SamplerCustomAdvanced`。必填：`UNETLoader.weight_dtype="default"`、`CLIPLoader.type="flux2"`。範例 workflow 詳 `docs/ComfyUI_DEPLOYMENT_2026-08-31.md`（已入統一 repo）。

## 17.5 檔案位置

- 統一 repo（source of truth，Node0）：`~/ai-gb10-cluster-runtime-manager/`
  - `runtimes.d/comfyui.conf`（正式 conf）、`docs/ComfyUI_DEPLOYMENT_2026-08-31.md`（部署指南）
  - commits：`f218651`（comfyui.conf Flux 2 Dev）、`799a624`（ComfyUI deployment doc）
- Node1 stack：`/home/eye/docker-stacks/comfyui-aeon/`（`docker-compose.yml`、`.env`、`workspace/` + 模型）

## 17.6 後續（Stage 2 / 3）

- **Stage 2**：TP2 time-sharing switch（Node0↔Node1 時分共用）。
- **Stage 3**：TP2-xDiT CLI pipeline（Qwen-Image 20B，bare-diffusers + torchrun）。⚠️ xdit-poc 用 bf16；Node0 現存 Qwen-Image 為 fp8/nvfp4，與 xdit-poc sm_121a NaN 疑點尚未解決（open），落地前需先確認。
