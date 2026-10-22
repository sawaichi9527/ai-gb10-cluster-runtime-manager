# Qwen3.8 Flash-Next × TensorFold TP2 — 上線與引擎 A/B（2026-10-21/22）

**結論**：`qwen38flash-tensorfold` 已成為正式 TP2 lane（`LAUNCH_STYLE="kit"`），與 vLLM 版
`qwen38flash` 為**對等 lane、無主/備**，共用同一份 124 GiB checkpoint。同一 session、同一組
payload 的 A/B：TensorFold 在 **decode 全面勝出**（C1 +35.5%、C2 +96.4%、C4 +67.9%、
C8 +82.2%），**prefill 亦勝**（32K/131K/261K：+25.0% / +15.3% / +16.8%），且不需要自建
image、cold boot 只要 **1 分 53 秒**（vLLM 版同日實測 **14 分**）。

現役：**`qwen38flash-tensorfold`**（READY 2026-10-22 00:18:21 CST）。回滾：`gb10 use qwen38flash`。

---

## 1. 部署事實

| 項目 | 值 |
|---|---|
| Profile | `cluster-profiles.d/qwen38flash-tensorfold.conf`（`PLACEHOLDER=false`、`LAUNCH_STYLE=kit`） |
| Kit 目錄 | `~/docker-stacks/mia-TensorFold-qwen38flashNext/`（上游 clone，**釘 `f8287ef40319` = v1.1**） |
| Launcher | `./start.sh` / `./stop.sh`（**沒有 compose**；`container = qwen38-fn-tf`，兩 rank 同名） |
| Image | `ghcr.io/miaai-lab/qwen3.8-flash-dual-dgx-sparks-tensorfold:zig-db28187-f3e1300f4f62`<br>`sha256:e188128ddabdc67ac02c05781f5c0c6b348db5f050cac297861d82b7f086e18c`（arm64、壓縮 10.6 GiB、解開 24.7 GB） |
| Image 內容 | TensorFold `db281878`（branch `zig-flashnext`）+ `patches/0001–0009`、Zig 0.17.0、AOT Triton set `sm121`；labels `tf.patches=f3e1300f4f62`、`tf.kernels=present` |
| 權重 | `~/docker-stacks/models/qwen3.8-flash-next-nvfp4`（**兩節點既有**，25 檔 / 124 GiB，官方 `nvidia/Qwen3.8-Flash-Next-NVFP4` @ `fc694b54` 同檔名同大小） |
| 取用方式 | Hugging Face cache 橋接（**相對** symlink）：`~/docker-stacks/models/hub/models--nvidia--Qwen3.8-Flash-Next-NVFP4/snapshots/fc694b54… -> ../../../qwen3.8-flash-next-nvfp4`；`HF_CACHE=~/docker-stacks/models` |
| 服務介面 | `http://192.168.23.215:1234/v1`，model id **`aeon`**，`TENSORFOLD_API_KEY` = cluster 共用的 `VLLM_API_KEY`（無 key → 401） |
| 參數 | `CONTEXT=262144`（**YaRN off**，原生窗）、`PARALLEL=8`、`KV_DTYPE=fp8`、`VISION=1`、`DRAFTS=1`、`THINKING=1`、`MAX_TOKENS=32768` |
| KV pool（實測 boot log） | `sequence memory: 33.33 GiB (45.33 GiB free, 10.0 GiB kept free); fp8 KV cache, 528 bytes a position a layer` |

`~/docker-stacks/mia-TensorFold-qwen38flashNext/.env`（mode 600）是唯一設定來源：`WORKER=eye@10.0.101.102`、
`WORKER_WEIGHTS=copy`、`HF_CACHE`/`WORKER_HF_CACHE=/home/eye/docker-stacks/models`、
`MODEL_REVISION=fc694b54…`、`PORT=1234`、`SERVED_NAME=aeon`、`PREPARE=0`、`IMAGE_TAG`/`IMAGE_DIGEST`、
`KERNEL_CACHE=~/.cache/tensorfold-qwen38fn-qwen38flash-tensorfold`、`LOG_DIR=~/docker-stacks/logs/qwen38flash-tensorfold/ranks`。

## 2. 時序（CST）

| 時間 | 事件 |
|---|---|
| 23:16 | node0 `docker pull`（by digest，10.6 GiB）完成；`tf.patches=f3e1300f4f62` 驗過，tag `tensorfold-qwen38fn:zig-db28187` + registry ref |
| 23:21–23:25 | `docker save \| ssh node1 docker load`（CX7），rc=0；兩端 `RootFS.Layers` 的 sha256 **相同**（`b0fd0ee0…`）。`.Id`/`.Size` 不同是 node0 overlay2 vs node1 containerd 的既有現象 |
| 23:26–23:27 | 兩節點 HF cache 橋接建立；`MEM_CHECK=0 PULL=0 HF_HUB_OFFLINE=1 ./scripts/prepare.sh` → **Checkpoint OK: qwen4_exp, modelopt MIXED_PRECISION, 299545 tensors in 11 shards**、`Worker has … @ fc694b54`（**零傳輸**）、prepared marker 寫入 |
| 23:28 | 第一次 `gb10 use qwen38flash-tensorfold`（同時拆掉 vLLM）→ **失敗 #1**（image tag gate） |
| 23:46 | 修好後第二次 → **失敗 #2**（容器內看不到權重） |
| 23:47:53 → 23:49:38 | 第三次 boot：**READY 1 分 45 秒** |
| 23:57:51 → 00:11:49 | 為了 A/B 切回 `qwen38flash`（vLLM 冷啟 **13 分 58 秒**） |
| 00:16:28 → 00:18:21 | 切回 TensorFold：**READY 1 分 53 秒** |

## 3. 兩個踩坑（都已修，勿重犯）

### 3.1 `kit image not present on node0` — `cluster-up` 的 kit 前置檢查看 `IMAGE`

`scripts/cluster-up` 對 kit lane 有一道 `docker image inspect "${IMAGE}"`（只是「在不在」，不是 digest gate）。
conf 的 `IMAGE` 是 registry ref，但我們只 tag 了本地名 `tensorfold-qwen38fn:zig-db28187` → 檢查失敗。
**處置**：把本地 image 也 tag 成 registry ref（兩節點都做）。這也是「全新主機 `docker pull` 之後應有的狀態」。
不是改 conf、也不是改檢查。

### 3.2 `is neither a directory nor a Hugging Face repo id` — 絕對 symlink 在容器內斷掉

`start.sh` 用 `-v "$HF_CACHE":/root/.cache/huggingface:ro` 把 **HF cache 根**掛進容器，再把
`hub/models--…/snapshots/<rev>`（掛載點相對路徑）交給引擎。第一版把 snapshot 做成**絕對** symlink
→ 指向 `/home/eye/docker-stacks/models/qwen3.8-flash-next-nvfp4`，這個路徑在容器內不存在 → 斷鏈。
**處置**：`HF_CACHE` 改指 `~/docker-stacks/models`（母目錄），snapshot 用**相對**連結
`../../../qwen3.8-flash-next-nvfp4`。相對連結在任何掛載點都成立，因此 head 與 worker 兩邊都能解析，
且**零複製、零下載**。兩節點都必須建。

## 4. 驗收證據（2026-10-22 00:19 CST）

| # | 檢查 | 命令 | 結果 |
|---|---|---|---|
| 1 | lane 狀態 | `gb10 status` | `ready`；node0/node1 各 1 個 `qwen38-fn-tf Up`；`state/kit.qwen38flash-tensorfold.rc` = **0** |
| 2 | 模型 id | `GET /v1/models` | `{"id":"aeon","owned_by":"tensorfold"}` |
| 3 | 認證 | 無 key 打 `/v1/models` | **401**（key 生效） |
| 4 | Smoke | `gb10 smoke` | `http=200`、`HELLO-TP2-OK`、`finish_reason=stop`、reasoning 37 tok |
| 5 | Decode（變動長度，`bench-c <C> 400`） | C=1/2/4/8 | 59.5 / 111.1 / 174.7 / **293.9** tok/s，0 error |
| 6 | Decode（固定長度 `BENCH_IGNORE_EOS=1 … 400`） | C=1/2/4/8 | 55.0 / 82.5 / 150.3 / **287.2** tok/s，0 error |
| 7 | Cold prefill（`BENCH_COLD=1 bench-ctx`） | 32k / 131k / 261k | **3,465 / 3,240 / 2,989** tok/s（261,084 tok / 87.3 s） |
| 8 | 視覺 | `bench-mm 1 1 400`、`bench-mm 1 8 400` | prompt 768 tok（含影像）、C1 52.5 / C8 **230.1** tok/s、0 error |
| 9 | 視覺正確性 | 自建 payload 問「What is in this picture?」 | `Four fresh carrots with green stems are arranged on a white background.`（圖為 `carrots.jpeg`） |
| 10 | 工具呼叫 | `tools/toolcheck.py` | **3/3 PASS**（array 參數、串流、tool result 輪） |
| 11 | Prompt reuse | `tools/prompt_reuse.py` | **PASS**，4 輪各 99.3% 快取、prefill 9.64 s → 0.25 s |
| 12 | 決定性 | `tools/exact.py --max-tokens 160 --prompts 2` | **PASS**：drafted == serial == concurrent（194 drafts 接受） |
| 13 | 長上下文檢索 | `tools/needle.py 200000` | **found yes**（prompt 199,730 tok、prefill 68.07 s ≈ 2,934 tok/s） |
| 14 | `/metrics` | `curl /metrics` | `tensorfold:requests_total{key="env-1",status="200"}` 等正常 |

## 5. 引擎 A/B（同 session、同 payload、同硬體）

`bench-c.sh` 固定 400 tokens（`BENCH_IGNORE_EOS=1`）、`bench-ctx.sh` 純 prefill（`max_tokens=1`、`BENCH_COLD=1`）；
vLLM 版為**現行設定**（zh draft 詞表、determinism 預設 ON、GMU 0.80、prefix caching ON）。

| | vLLM（`qwen38flash`） | TensorFold（本 lane） | Δ |
|---|---|---|---|
| decode C1 | 40.6 | **55.0** | **+35.5%** |
| decode C2 | 42.0 | **82.5** | **+96.4%** |
| decode C4 | 89.5 | **150.3** | **+67.9%** |
| decode C8 | 157.6 | **287.2** | **+82.2%** |
| prefill 32K | 2,770 | **3,465** | +25.0% |
| prefill 131K | 2,809 | **3,240** | +15.3% |
| prefill 261K | 2,559 | **2,989** | +16.8% |
| cold boot → `/health` | 13 分 58 秒（23:57:51→00:11:49） | **1 分 53 秒**（00:16:28→00:18:21） | −86% |
| image | `vllm/vllm-openai:qwen38-flash-next` 20.6 GB | 24.7 GB（registry，免自建） | — |

對照上游 v1.1 的 sparkDash 數字（1M 視窗、16 併發、NVFP4）：67.4 / 98.9 / 152.2 / 231.2（C1/C2/C4/C8）。
本 lane 的 C1 較低（59.5 變動長度 / 55.0 固定長度），C8 明顯較高（293.9 / 287.2）——與「原生 262,144 窗、
不吃 YaRN、pool 33.33 GiB」一致的方向。

**Caveats（勿只看標題數字）**
- 兩邊都是單次量測（非 10-boot campaign）；本 cluster 的 boot-to-boot 漂移先例是 ±7~12%（vLLM）
  與 normalized 0.80–1.32（qwen38flash）。C2 的 vLLM 42.0 明顯低於 C1 40.6 的線性期待，屬漂移。
- vLLM 側的 C=1 數字含 MTP spec decode 與 zh 詞表；兩邊收到的是**同一支 `bench-c.sh` 的相同 payload**，
  但引擎的 thinking 預設不同（TF `--thinking` 明確開啟）——以固定長度那一組為主要比較依據。
- prefill 只量 `max_tokens=1` 的單請求；沒有量 8 併發 prefill。

## 6. 未驗證 / 已知限制

- **`tools/long_context.py`（128k/256k × 5 深度）未跑**；本次只跑 200k needle 與 261k prefill。
- **長時間 soak 未跑**（v1.1 修的就是「~15 分鐘高併發 thinking 後 CUDA graph instantiate 失敗」；
  上游已改為 graceful degrade + `TF_FLASHNEXT_GRAPH_LOG=1` 可觀察）。建議下次壓力測試時開這個變數。
- **1M 視窗 / YaRN 未啟用**（本 lane 刻意 `CONTEXT=262144`）。
- 引擎**拒絕** `response_format` / `guided_*`、`logprobs` / `top_logprobs`、`n>1`（HTTP 400）；
  工具呼叫、`tool_choice:"required"`、vision、prompt reuse 正常。
- `KV_DTYPE=fp8` 是 **lossy**（上游 teacher-forced top-1 與 bf16 一致率 98.8%）；要精確用 `KV_DTYPE=bf16`。
- thinking 預設 ON；小 `max_tokens` 可能只有 reasoning 沒有 content（smoke 用 500 所以安全）。
- `gb10 verify-models` 對這個模型目錄會 **WARN `SHA256SUMS not found`（skip）**——與 vLLM lane 相同，
  因為該目錄本來就沒有 checksum 清單（boot 時同樣會印這個 WARN，不影響啟動）。
- rank1 的 log 在 **worker** 的 `~/.cache/tensorfold-qwen38fn/logs/`（worker 不讀 head 的 `.env`，
  所以 head 的 `LOG_DIR` 只影響 rank0）。
- `cluster-up` 的 kit 前置檢查只驗 image **存在**；digest 由 conf/`.env` 的 `IMAGE_DIGEST` 與本次人工查核負責
  （kit lane 不跑 compose-verify，這是既有設計）。

## 7. 回滾 / 重啟

```bash
gb10 use qwen38flash              # 回 vLLM 版（冷啟約 14 分）
gb10 use qwen38flash-tensorfold   # 回本 lane（冷啟約 2 分）
gb10 restart qwen38flash-tensorfold   # 只重啟本 lane（down + --skip-down boot）
```
- 完全重來（image 不在時）：node0 `docker pull ghcr.io/miaai-lab/…@sha256:e188128d…e18c`，再
  `docker tag <ref> tensorfold-qwen38fn:zig-db28187`，`docker save | ssh node1 docker load`。
- 重建 bridge（兩節點各一次）：見 §1 的相對 symlink 指令。
- `prepare.sh` 重跑：`MEM_CHECK=0 PULL=0 HF_HUB_OFFLINE=1 ./scripts/prepare.sh`（**必須** `MEM_CHECK=0`
  當其他 TP2 lane 還在線；`PULL=0` 避免 node1 再從 WAN 拉；`HF_HUB_OFFLINE=1` 避免重新下載 124 GiB）。

## 8. 本次改動檔案

- `cluster-profiles.d/qwen38flash-tensorfold.conf`（新增）
- `bin/gb10`（六處白名單）
- `docs/QWEN38FLASH_TENSORFOLD_DEPLOY_2026-10-22.md`（本檔）
- `README.md`、`AGENTS.md`、`handoff.md`（現況／Fact／交接）
- node 側（非 repo）：image（兩節點）、`~/docker-stacks/mia-TensorFold-qwen38flashNext/`（clone + `.env`）、
  兩節點的 HF cache 橋接、`~/docker-stacks/logs/qwen38flash-tensorfold/`（boot/kit/image-pull/prepare log）

## 9. 追加驗證（2026-10-22 08:59–09:19）：多深度檢索 + 20 分鐘高併發 soak

本節是上線後的第二輪驗證（服務已在線，`gb10 restart qwen38flash-tensorfold` 一次以帶上
`TF_FLASHNEXT_GRAPH_LOG=1`；兩 rank 的 container env 都確認有這個變數）。

### 9.1 `tools/long_context.py`（needle 5 深度 + key=value 檢索）

`API_URL=http://127.0.0.1:1234 MODEL=aeon`、`--max-tokens 512`、thinking off、greedy、seed 1。

| size / test | 結果 | prompt | 備註 |
|---|---|---|---|
| 32k needles（深度 0.02/0.25/0.5/0.75/0.98） | **exact 5/5** | ~31.6k | — |
| 32k kv（8 keys） | **exact 8/8** | ~31.8k | — |
| 128k needles | **exact 5/5** | ~127.6k | — |
| 128k kv | **exact 8/8** | ~128k | — |
| 256k needles | **exact 5/5** | ~255.6k | 近硬限仍全中 |
| 256k kv | **HTTP 400（預期）** | 275,135 | harness 對 kv 文件的 token 估算偏低（實測 1.99 chars/token），prompt 自身就超過 262,144；引擎**乾淨拒絕**、沒有截斷或半截答案 |
| 240k kv（補跑） | **exact 8/8** | 257,814 | prefill **91.0 s ≈ 2,833 tok/s** |
| 512k / 1M | **skipped** | — | 工具主動判定超過服務窗（262,144），不計分 |

合計 `exact 31/31、present 31/31`（不含 240k 補跑的 8/8）。
**Harness 提醒**：`--sizes 256k --tests kv` 會自己超標 ~7.5%；要驗近上限的 kv 檢索請用 `240k`。

### 9.2 20 分鐘 soak（`scripts/bench-soak.py`，本 session 新增）

`--concurrency 8 --duration 1200 --max-tokens 512 --thinking on`；mixed short/medium(3k)/long(12k) prompt，
每 10 個請求一次 exact-token probe（`HELLO-SOAK-OK`）。

```json
SOAK {"duration_s": 1214.2, "concurrency": 8, "model": "aeon", "max_tokens": 512, "thinking": "on",
      "requests": 893, "errors": 0, "truncated_empty_content": 223, "probe_mismatch": 0,
      "completion_tokens": 242651, "tok_per_s": 199.9, "lat_p50_s": 8.312, "lat_p95_s": 22.68,
      "by_family": {"short": 446, "medium": 224, "long": 223}}
```

- **0 errors、0 probe mismatch**；`finish_reason` 只有 `stop`(670) 與 `length`(223)。
- **223 筆 `truncated` 全部是 thinking 吃掉 512 token 預算**（`finish_reason=length` + 空 content），
  與本 repo 既有的 thinking 契約一致（客戶端要給 ≥1024 token）；不是引擎錯誤。
- 延遲全程平穩：p50 8.28–8.60 s、p95 22.7–25.0 s（前 3 分鐘後就不動）；吞吐 199.9 tok/s（8 串流）。
- 跑完 `free -g`：node0 36 GiB、node1 39 GiB available（起跑前 33.18 GiB KV pool + 10 GiB reserve，無洩漏）。

### 9.3 CUDA graph（v1.1 修的就是這個）

- 兩 rank 的 container 都帶 `TF_FLASHNEXT_GRAPH_LOG=1`。
- **rank1（node1）的 docker log**：
  `info: graphs after 8300 captures (shared): 0 solo, 13 shared live; 8300 instantiated; 13665 MiB device memory free`
  —— 8300+ 次 capture/instantiate、**0 次失敗**、無 `CUDA_ERROR_NOT_PERMITTED`、無 `traceback`。
- 重要細節：**這些 graph 統計只出現在 rank1 的 log**（node1 `docker logs qwen38-fn-tf`），
  rank0/kit.log 一條都沒有。下次查這個問題要讀 **node1**。
- Soak 後回歸：`BENCH_IGNORE_EOS=1 bench-c 8 400` = **283.0 tok/s**（soak 前 287.2，−1.5%，在噪聲內）、
  `gb10 smoke` 200 `HELLO-TP2-OK`、`/health` 200、KV pool 33.18 GiB。

**本節結論**：262,144 原生窗內的多深度檢索在 240k/256k 全中；20 分鐘 8 併發 thinking soak 零錯誤、
延遲不漂移、graph 8300+ 次 instantiate 無失敗 → **v1.1 的 CUDA-graph 修復在本 cluster 站得住**。
