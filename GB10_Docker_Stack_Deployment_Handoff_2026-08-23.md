# DGX Spark GB10 本地 AI 部署狀態交接（最新版）

> 更新日期：2026-08-23  
> 主機：NVIDIA DGX Spark / GB10  
> 主機名稱：`spark-25d5`  
> 使用者：`eye`  
> 區網 IP：`192.168.23.215`  
> 作業系統：Ubuntu 24.04 ARM64  
> 用途：本地 vLLM LLM 推理 + ComfyUI 生圖，以 Docker Stack 分離管理  
> 文件定位：接續 `GB10_Docker_Stack_Deployment_Handoff_2026-08-18.md`，記錄 2026-08-23 完成之 **27B 模型 `qwen3.6-27b-aeon-mm-mtp → qwen3.8-27b-aeon-ultimate-uncensored-nvfp4` (sakamakismile NVFP4) 遷移**、**Thinking Looping Trap 修復**、以及首次冷啟動與基準測試。ComfyUI 與 35B 相關沿用 08-18 文件。

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

`docker compose config` 通過，`image ghcr.io/aeon-7/aeon-vllm-ultimate:2026-08-16-v0.27.1` 不變。

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

---

# 9. 操作禁忌 (新增)

```text
不要刪除 qwen3.8 內 15 個 mtp.* 的 bf16 (quantization_config.ignore)
不要以 xhigh (預設) 在 uncensored 上跑長文/邊緣問題 (必用 medium, 1-3k)
不要因 KV 從 32→42 GiB 就貿然提高 gpu-memory-utilization (先觀察併發)
不要把 qwen3_5_mtp 當作永久寫法 (已改 mtp)
不要刪除三個 image (v0.25.1/26.0/27.1) 與兩代 27B 模型
```

---

# 10. 部署完成狀態 (2026-08-23)

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
[OK] 目前運行：27B Qwen3.8 (日常預設)
```

---

# 11. 後續建議

```text
1. 正式 benchmark 補齊 (TTFT, 1/2/4/8 conc, prefix cache)
2. 評估 mtp n=3 → 6 的增益 (sakamakismile 9-case gate 通過)
3. 修復 Windows ssh 金鑰 host-bound 問題
4. 35B + Qwen3.8 共存壓力測試
5. 評估 qwen3.6 舊模型/ v0.25.1 image 除役時機
```

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
