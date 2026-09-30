# ai-gb10-cluster-runtime-manager

DGX Spark **GB10 runtime manager** — 統合 **2-node TP2 叢集** 與 **單節點 runtimes** 於單一 repo。

- **`bin/gb10`** — TP2 叢集 CLI（thin layer 於 `scripts/cluster-*`）
- **`bin/gb10-single`** — 單節點 CLI（`node0` 本機 / `node1` 經 ssh）
- **`runtimes.d/*.conf`** — 單節點 runtime 定義
- **`cluster-profiles.d/*.conf`** — TP2 叢集 profile 定義（data-driven registry）
- **`scripts/cluster-*`** — 叢集部署腳本（ver detail 見 `docs/TP2_DEPLOYMENT_2026-08-30.md`）


## Deployed services & benchmark results (latest image)

> **2026-09-29 現況。** qwen38flash 於當日對齊上游並重新驗證（GMU 0.835→0.80、prefix caching
> ON + vllm#53388 block-drop、deterministic greedy 預設 ON；見其章節）；**當日稍晚以
> `gb10 use deepseek` 切回 DeepSeek 0731 mainline**（見下方「現役」）；其餘 lane 仍為
> 09-19／09-20 實測。27B/35B 走 `ghcr.io/aeon-7/aeon-vllm-ultimate:2026-09-18-v0.29.0-omni`
> （單節點啟用 `VLLM_USE_V2_MODEL_RUNNER=1`）；DeepSeek 0731 與 Vision-Exp 共用
> `ghcr.io/anemll/dspark-vllm-gx10:0.1.1`；qwen38flash 用 `vllm/vllm-openai:qwen38-flash-next`。
> **每個模型只保留最新一次實測**；舊結果不累計（歷史完整報告見 maintenance repo 的
> `docs/BENCHMARK_*.md` 與 handoff）。
>
> **已評估、未新增 lane**：DeepSeek-V4.1-Flash **EXL3**（2× GB10）同日完成選型查核 ——
> 兩顆可下載 arm64 image 的 digest、TP=2 硬限制、各線 benchmark 與 NVIDIA 論壇口碑均已記錄；
> 因「不自行 build image」的前提與 sfxnz 2.0bpw 的 42–50 tok/s 無法同時成立，**本輪不採用**，
> 2-Spark 多模態維持 `deepseek-vision`。完整證據見
> [`docs/DSV41_FLASH_EXL3_2X_SPARK_EVAL_2026-09-29.md`](docs/DSV41_FLASH_EXL3_2X_SPARK_EVAL_2026-09-29.md)。
>
> **2026-09-30 上游再查核：** `deepseek` 與 `deepseek-vision` 的 **image／配方／官方權重皆無更新**
> —— Anemll image 仍為唯一 tag `0.1.1`（digest `a8394849…` 不變、node0 現役同 pin）；照 MiaAI vision
> 配方仍 pin 在 upstream HEAD `97e8733…`；官方 0731 權重自發佈 commit `9e165c30…` 後僅加了一個
> **model-card（docs-only）** commit，Vision-Exp 權重 pin `6821d6ad…` = HF HEAD。**兩 lane 現行
> 設定即為最新，無需變更。** 完整證據見
> [`docs/DEEPSEEK_UPSTREAM_REVERIFY_2026-09-30.md`](docs/DEEPSEEK_UPSTREAM_REVERIFY_2026-09-30.md)。
>
> **2026-09-30 上游再查核（27B／35B）：** `27b` 與 `35b`（TP2 + 單機）共用的
> `ghcr.io/aeon-7/aeon-vllm-ultimate` 最新 dated tag 仍為 **`2026-09-18-v0.29.0-omni`**
> （＝現行 pin，digest `cc91c515…` 不變、`latest` 同 digest、無 09-19 後/10 月 tag）；四個 HF 來源
> —— 27B body `AEON-7/…NVFP4-MIXED`（09-18）、27B drafter `z-lab/Qwen3.8-27B-DFlash2`（08-19）、
> 35B body `AEON-7/Qwen3.6-35B-A3B-heretic-NVFP4`（07-15）、35B drafter `AEON-7/AEON-DFlash-Qwen3.6-35B-A3B`（06-28）
> —— **自 09-19 起皆無更新**。完整證據見
> [`docs/QWEN_27B_35B_UPSTREAM_REVERIFY_2026-09-30.md`](docs/QWEN_27B_35B_UPSTREAM_REVERIFY_2026-09-30.md)。

### 已部署服務

| service | 模型 / 方法 | image | endpoint | 狀態 |
|---|---|---|---|---|
| 27B single (TP1) | `qwen3.8-27b-aeon-ultimate-uncensored-nvfp4-mixed` + DFlash2 n=7 | `2026-09-18-v0.29.0-omni` | `:1234/v1` | deployed（09-19 實測） |
| 27B cluster (TP2) | 同上 | `2026-09-18-v0.29.0-omni` | `http://192.168.23.215:1234/v1` | deployed（09-19 實測） |
| 35B single (TP1) | `qwen3.6-35b-a3b-heretic-nvfp4` + DFlash n=6 | `2026-09-18-v0.29.0-omni` | `:1234/v1` | deployed（09-19 實測） |
| 35B cluster (TP2) | 同上 | `2026-09-18-v0.29.0-omni` | `http://192.168.23.215:1234/v1` | deployed（09-19 實測） |
| DeepSeek V4 Flash cluster (TP2) | `deepseek-v4-flash-0731-official` + DSpark n=7 | `anemll/dspark-vllm-gx10:0.1.1` | `http://192.168.23.215:1234/v1` | **← 現役（09-29 切換）**：KV 12.15 GiB、smoke `HELLO-TP2-OK` |
| DeepSeek V4 Flash **Vision-Exp** cluster (TP2) | `deepseek-v4-flash-vision-exp` + DSpark n=6 (multimodal) | `anemll/dspark-vllm-gx10:0.1.1`（**與 deepseek 同 image / 同 digest**） | `http://192.168.23.215:1234/v1` | deployed（09-20 實測，文字＋圖片） |
| Qwen3.8 Flash-Next **125B** cluster (TP2+EP) | `qwen3.8-flash-next-nvfp4`（ModelOpt NVFP4）+ 內建 MTP n=3 | `vllm/vllm-openai:qwen38-flash-next` | `http://192.168.23.215:1234/v1` | deployed（09-29 重新驗證）：GMU 0.80／prefix caching ON／determinism 預設 ON |

> **現役（2026-09-29）＝ deepseek**（DeepSeek V4 Flash 0731 mainline；`:1234` READY、
> KV 12.15 GiB、`gb10 smoke` = `HELLO-TP2-OK`；`gb10 use deepseek` 由 qwen38flash 切換，
> cold boot 約 7.5 分）。TP2 各 lane **互斥**，同一時間只有一條在線；其他列的 `deployed`
> 表示**已部署並實測過**，非同時運行。

### 27B v0.29.0-omni (bench-c C1-C8, MAX_TOKENS=2048; 245k cold prefill) — 2026-09-19

> **2026-09-19 實測**（`2026-09-18-v0.29.0-omni`；single node0 與 TP2 cluster）。
> 註：27B 冷啟動可達 ~40 min；`cluster-up` 的 health timeout 由 profile 覆寫
> （27B `HEALTH_TIMEOUT=3600`，詳見 `docs/ISSUE_27B_BROKEN_2026-09-18_IMAGE_2026-09-19.md`）。

| C | Single tok/s | Cluster tok/s | Speedup |
|---|---|---|---|
| 1 | 23.8 | 46.1 | 1.94x |
| 2 | 36.6 | 76.8 | 2.10x |
| 3 | 54.4 | 87.9 | 1.62x |
| 4 | 80.3 | 105.3 | 1.31x |
| 8 | 117.2 | 172.7 | 1.47x |
| 245k prefill (tok/s) | 348.7 | 611.5 | 1.75x |

### 35B v0.29.0-omni (bench-c C1-C8, MAX_TOKENS=2048; 245k cold prefill) — 2026-09-19

> **2026-09-19 實測**（`2026-09-18-v0.29.0-omni`；single node0 與 TP2 cluster）。

| C | Single tok/s | Cluster tok/s | Speedup |
|---|---|---|---|
| 1 | 76.2 | 120.6 | 1.58x |
| 2 | 115.5 | 177.4 | 1.54x |
| 3 | 148.2 | 218.5 | 1.47x |
| 4 | 198.6 | 291.6 | 1.47x |
| 8 | 262.7 | 416.4 | 1.59x |
| 245k prefill (tok/s) | 2580.1 | 3951.9 | 1.53x |

> 245k prefill 用 `bench-ctx.sh 245000 1`（max_tokens=1 純 prefill）。
> **踩雷（已自動化）**：FlashInfer autotune cache **無法跨 rank 共用**——持久化的 `file_key` 內含 `tp_rank/ep_rank/cluster_rank`，而 vLLM 只在 leader（world rank 0）存檔、再把該 leader 檔 broadcast 給所有 rank；follower 用 rank-local key 永遠 miss → 兩 rank 要 benchmark 的 tactic 數不同 → 每 tactic 的 `dist.all_reduce` 死鎖（rank0 高 GPU spin-wait、rank1 閒置、`/health` 永不 ready）。故 `scripts/cluster-up` 於每次 boot 前呼叫 `ensure_autotune_cache_reset`（`cluster-common.sh`）**無條件清掉兩節點快取**，讓兩 rank 冷啟 lockstep；`AUTOTUNE_CACHE_POLICY=off` 可跳過（僅診斷）。單節點 runtime 另用獨立 cache root（`~/.cache/vllm-<profile>-single`，TP2 為 `~/.cache/vllm-<profile>[-cluster]`），不污染 TP2 路徑（`gb10-single-boot` 會檢查）。

### DeepSeek V4 Flash Vision-Exp (TP2, 與 deepseek 同 image) — 2026-09-20 實測

> `cluster-profiles.d/deepseek-vision.conf` 使用**與 mainline deepseek 完全相同**的 image
> `ghcr.io/anemll/dspark-vllm-gx10:0.1.1`（digest `a8394849…`）。Vision-Exp 支援不在 image 內，
> 而是靠**啟動 wrapper**（`entrypoint: []` + `bash -lc`：安裝 checkpoint 的 ViT/Aligner encoder
> → 套 17 個社群 hotfix → `exec vllm serve`）；hotfix 已 vendored 於 `patches/dspark-vision/`
> （MiaAI-Lab，MIT）。`nvfp4_ds_mla` KV、`flashinfer_b12x` MoE、DSpark k=6、
> **262144 ctx / 8-way（與 mainline 0731 相同）**、**prefix caching ON**（搭
> `dspark-swa-prefix` hotfix + `VLLM_PREFIX_CACHE_RETENTION_INTERVAL=4096`）。兩 profile 互斥切換
> （`gb10 use deepseek` ↔ `gb10 use deepseek-vision`）。實測 `/v1/chat/completions` 文字與
> `image_url` 圖片輸入皆正常；KV pool 381,364 tokens（0731 為 405,179，差異來自 ViT encoder 佔用權重記憶體）。

| C | Vision-Exp tok/s | accept % |
|---|---|---|
| 1 | 36.7 | 29.9% |
| 2 | 48.8 | 29.6% |
| 3 | 58.0 | 32.5% |
| 4 | 67.3 | 30.9% |
| 8 | 73.4 | 30.1% |

| prefill probe (`bench-ctx.sh`, max_tokens=1) | Vision-Exp tok/s |
|---|---|
| 32K | 1941.0 |
| 131K | 1825.3 |
| 200K | 1710.2 |
| 245K | 1671.3 |
| 260K | 1638.0 |
| 261K | 1803.9 |

| 圖片輸入 (`bench-mm.sh`, max_tokens=200) | prompt tok | wall (s) | agg tok/s |
|---|---|---|---|
| 1 img, C=1 | 407 | 3.76 | 53.1 |
| 4 img, C=1 | 1346 | 5.51 | 36.3 |
| 8 img, C=1 | 2598 | 12.37 | 16.2 |
| 1 img, C=4 | 407 ×4 | 7.21 | 111.0 |
| 1 img, C=8 | 407 ×8 | 10.95 | 146.1 |
| 1 img, C=16 | 407 ×16 | 20.08 | 159.4 |
| 4 img, C=8 | 1346 ×8 | 16.31 | 90.6 |

> 多模態：OpenAI `image_url`（base64）正常，每張圖約 320–390 prompt tokens（checkpoint `vision_max_n_token=384`）；`--limit-mm-per-prompt {"image":8}`。長上下文 prefill 到 261K 仍線性（1803.9 tok/s @ 261K）；**262144-word（=上限）請求被拒**（`maximum context length is 262144`，prompt 262144 + 1 output > 上限）→ 實用上限 prompt ≤ 262143 tokens。
> Prefix caching 實測：同一 32K prompt 連兩次，第 2 次命中前綴 → prefill **16.95s → 2.30s（1938 → 14314 tok/s）**；重複同 prompt 三次輸出皆完整（無 DSpark 退化，hotfix 生效）。
> 節點部署：vision 的 hotfix 目錄由 `cluster-up` 的 `SYNC_DIRS` 於每次 boot 從 repo 自動同步到兩節點（node1 不 host repo）。

### DeepSeek V4 Flash 0731 mainline (TP2) — 2026-09-20

> `cluster-profiles.d/deepseek.conf`：官方 `deepseek-v4-flash-0731-official` fp8 checkpoint +
> `anemll/dspark-vllm-gx10:0.1.1`（同 Vision-Exp 的 image），DSpark n=7 greedy、256K / 8-way。
> `bench-c` 之 prompt 約 118 tok（Vision-Exp 約 197 tok——同文字，tokenizer/chat template 差異）。

| C | 0731 tok/s | accept % |
|---|---|---|
| 1 | 35.7 | 25.1% |
| 2 | 55.7 | 29.3% |
| 3 | 45.1 | 25.4% |
| 4 | 55.5 | 27.1% |
| 8 | 93.1 | 28.8% |

| prefill probe (`bench-ctx.sh`, max_tokens=1) | 0731 tok/s |
|---|---|
| 32K | 1516.9 |
| 131K | 1682.3 |
| 200K | 1725.0 |

> 觀察：C≥4 兩者吞吐相近；C=8 0731 較高（93.1 vs 73.4）；短/中長 prefill Vision-Exp 略快、200K 同級。

### Qwen3.8 Flash-Next 125B NVFP4 (TP2+EP, MTP3) — 2026-09-29（上游對齊＋重新驗證）

> **2026-09-29：對齊上游 MiaAI 配方 `2c86a1d0`。** `cluster-profiles.d/qwen38flash.conf`：官方
> `vllm/vllm-openai:qwen38-flash-next` image（vLLM ≥0.28、Qwen4Exp 支援；digest 未變）、NVIDIA
> ModelOpt **NVFP4 125B** checkpoint（本機為 10-shard repack，另有 `model-fp8-mtp-ple.safetensors`）、
> **TP2 + EP**（`--enable-expert-parallel --all2all-backend allgather_reducescatter`）、內建
> **MTP n=3**（`--speculative-config {"method":"mtp","num_speculative_tokens":3,
> "use_local_argmax_reduction":true,"disable_eagle_block_drop":true,
> "index_share_for_mtp_iteration":true}`）在**精簡 47,149-id 詞表**上起草（A/B 見下）、
> `fp8_e4m3` KV、`bfloat16` SSM state、`--compilation-config {"mode":0,...}`（eager：不做
> torch.compile，避免 Inductor 在 GB10 上複製 PLE 表）、**GMU 0.80**（09-26 上游：0.835 會讓
> 節點只剩 0.3–0.9 GiB MemAvailable，GB10 會硬重置）、`--max-num-batched-tokens 8192`、
> `--mm-encoder-tp-mode data`、`--enable-prompt-tokens-details`、**prefix caching ON**。
>
> MiaAI-Lab 配方 vendored 於 `patches/qwen38flash/`（AGPL-3.0，見 NOTICE；**10 個檔案 pin 在
> `2c86a1d0`**），由 `CMD_WRAPPER` 在容器內**就地**套用於 image 自身的 vLLM 原始碼（PLE /
> ModelOpt MXFP8 + FP8_BLOCK_SCALES / QSA FP8-KV / 精簡詞表 MTP drafter / **vllm#53388
> block-drop backport** / opt-in determinism），不重建 image；47k 詞表唯讀掛載於
> `/etc/vllm-draft-vocab.txt`。checkpoint 的 MTP 層索引別名由
> `patches/qwen38flash/prepare.sh` 預先產生後唯讀掛載。
>
> 服務：`:1234`、model id `aeon`、262144 ctx。**KV pool 29.15 GiB**（GMU 0.80；09-20 的 0.835
> 為 34.01 GiB / 4,245,234 tokens）。**deterministic greedy decoding 為預設**（`Q38_DET_OFF=1` 可關）。
> `bench-c.sh`：prompt = 171 tok、`MAX_TOKENS=400`、`any_errors=0`。

#### MTP draft 詞表 A/B（**2026-09-20 實測**；同機同 session，僅換 drafter 詞表）

| C | 完整 248,320 vocab | 精簡 47k | Δ |
|---|---|---|---|
| 1 | 35.7 | 40.4 | +13.2% |
| 2 | 54.8 | 58.9 | +7.5% |
| 3 | 82.3 | 88.2 | +7.2% |
| 4 | 90.9 | 101.0 | +11.1% |
| 8 | 146.5 | 156.2 | +6.6% |

| C | 完整 accept % | 47k accept % |
|---|---|---|
| 1 | 44.5 | 47.4 |
| 2 | 49.8 | 43.0 |
| 3 | 45.3 | 42.8 |
| 4 | 44.9 | 46.5 |
| 8 | 47.4 | 45.6 |

> 精簡詞表把 drafter 的 lm_head 讀取縮到 rank-0 的 id 區間，並以
> `use_local_argmax_reduction` 把 draft all-gather 由 O(vocab_size) 降為 O(2*tp_size)；五個 C 全部較快
> （**平均 +9.1%**，與 MiaAI 量測的 +9.6% 相符），**接受率與 mean accept length 幾乎不變**
> （輸出安全：落在子集外的 draft 在驗證階段被丟棄，不會被輸出）。精簡版另使 KV pool 由
> 33.64 → **34.01 GiB**（drafter 權重省下的記憶體；此為 09-20 GMU 0.835 下的數字）。
> `bench-c` 的 `max_tokens=400` 會提前停止、各 stream 長度不同，故單次數字變異較大（C=1 尤甚），
> 上表取中位數。**以上 A/B 於 2026-09-20 量測**（GMU 0.835、prefix caching OFF）；
> 現行 09-29 設定的數字見下方 benchmark 段。

> 對照同機 TP2：**27B**（v0.29.0-omni, DFlash2 n=7）46.1 / 76.8 / 87.9 / 105.3 / 172.7；
> **35B**（DFlash n=6）120.6 / 177.4 / 218.5 / 291.6 / 416.4。
> 125B NVFP4 MoE 每 token 僅啟用約 6B 參數，故 C=1 單流偏低，C=8 聚合約 3.9x（09-20 量測）。
>
> **上線時修掉的 5 個問題**（皆已進 main）：① Docker Compose 對整份 render 檔做變數插值，把
> `CMD_WRAPPER` 內的 `$W`/`$P` 吃掉 → 啟動即死於 `mkdir -p ""`（改以 `$$` 逃逸；deepseek-vision
> 的 `${PATH}` 同類隱患一併修好）；② `cluster-compose-verify` 不支援 `CMD_WRAPPER` lane；
> ③ 同工具以 `||` 當欄位分隔符，與 wrapper 內 `|| exit 1` 衝突；④ autotune 快取路徑未納入
> `ensure_autotune_cache_reset`（本 lane 用獨立 cache root；新增 profile 可宣告的
> `AUTOTUNE_CACHE_REL`）；⑤ 該 cache 目錄由 docker 以 root 建立，`eye` 無法搬移 → reset 先
> `mkdir -p` parent 並於兩節點一次性 chown。

#### qwen38flash benchmark（最新：2026-09-29）

一律標明取樣模式；**跨取樣模式或跨 prefix-caching 狀態的數字不可直接互比**。

解碼（`bench-c.sh` + `BENCH_IGNORE_EOS=1`，每 stream 恰好 `max_tokens=400`）。2026-09-29 起
qwen38flash 採 `BENCH_DETERMINISTIC=1`（`temperature=0, seed=0`），每 C 量 **10 次**：

| C | 09-29 knobs ON（最終設定） | 09-29 knobs OFF | 09-20 基準※ |
|---|---|---|---|
| 1 | 45.5 | 46.9 | 41.7 |
| 2 | 78.6 | 73.8 | 55.3 |
| 3 | 102.7 | 101.7 | 93.7 |
| 4 | 145.9 | 117.9 | 105.0 |
| 5 | 119.5 | 140.2 | — |
| 6 | 158.6 | 165.4 | — |
| 7 | 177.2 | 167.1 | — |
| 8 | 196.8 | 180.8 | 161.1 |

> ※09-20 那欄同時差在取樣模式與 prefix caching（當時 OFF），僅供趨勢參考。
> C4/C5 在兩種設定下都呈雙峰分布，中位數代表性有限（raw 值見 handoff）。

##### 可重現性（2026-09-29）

`temperature=0` + 固定 seed 只移除「取樣」變異；剩餘抖動來自 **target forward 非逐 bit
可重現** → spec-decode 的 accept/reject near-tie 翻轉（vllm-project/vllm#53436，同為
DeepSeek-V4-Flash / Blackwell SM120 / spec decode；該報告並指出 3 次重複常會掩蓋抖動，需 ≥10 次）。
本 repo 的 determinism knobs 正好對症，**自 2026-09-29 起為 profile 預設**（`Q38_DET_OFF=1` 可單次關閉）：

```bash
Q38_DET_OFF=1 gb10 use qwen38flash   # opt-out；預設即含 VLLM_QSA_DET_TOPK + VLLM_MOE_DET_FINALIZE
```

| C | knobs OFF：tok/s CV / acc CV | knobs ON：tok/s CV / acc CV |
|---|---|---|
| 1 | 9.2% / 19.4% | 5.2% / **0.0%**（acceptance 十次恆為 46.9%） |
| 2 | 12.2% / 16.6% | **1.1%** / 4.9% |
| 3 | 6.6% / 5.4% | 6.4% / 7.1% |
| 4 | 9.8% / 8.4% | 8.4% / 10.7% |
| 5 | 9.8% / 14.3% | 10.9% / 11.3% |
| 6 | 9.4% / 7.5% | 5.4% / 1.7% |
| 7 | 7.3% / 8.9% | 7.6% / 9.9% |
| 8 | 8.7% / 11.1% | **2.2%** / 3.3% |

C1 的接受率十次完全相同 → 驗證路徑已逐 bit 可重現；中位數互有高低、**無系統性吞吐代價**，
C2/C6/C8 明顯收斂而 C3/C5/C7 改善有限。官方 `VLLM_BATCH_INVARIANT` 這條路在
Blackwell + MXFP4 MoE 會拋 `NotImplementedError`，故這是本地唯一手段。

##### prefill（`bench-ctx.sh` + `BENCH_COLD=1`, max_tokens=1；2026-09-29 實測）

`BENCH_COLD=1` 每次前綴唯一 nonce，避免 prefix caching 直接從快取回答探針（本 lane prefix
caching 已開，且較長探針天然是較短者的前綴，不除霧會嚴重虛胖）。
自我檢查：32K 連兩次 **3100.5 / 3099.8 tok/s**（差 0.02%）。

| prompt | prompt_tokens | wall (s) | prefill tok/s |
|---|---|---|---|
| 32K | 32084 | 11.52 | 2784.6 |
| 131K | 131084 | 45.94 | 2853.6 |
| 200K | 200084 | 74.13 | 2698.9 |
| 245K | 245084 | 94.53 | 2592.5 |

##### 圖片（`bench-mm.sh` + `BENCH_COLD=1`, max_tokens=200；2026-09-29 實測）

每 stream 一個唯一 nonce，否則 C 個相同請求會被 prefix cache 去重而虛胖。

| 測試 | prompt tok | wall (s) | agg tok/s |
|---|---|---|---|
| 1 img, C=1 | 794 | 4.19 | 47.7 |
| 4 img, C=1 | 2912 | 3.11 | 33.1 |
| 1 img, C=4 | 794 × 4 | 6.33 | 126.3 |
| 1 img, C=8 | 794 × 8 | 7.61 | 125.2 |

> 每張圖約 693 prompt tokens。全部 `any_errors=0`。profile 未設 `--limit-mm-per-prompt`，
> vLLM 預設即允許 ≥8 張。注意 09-20 的圖片表為 597/768 tokens／不同圖檔，**不可與上表直接對比**。
> 多輪穩定（`scripts/bench-multiturn.sh 6 300`）：**6/6 clean turns**（每輪 `finish=stop`、內容非空）。
> **`PLE_OFFLOAD=true` 不適用於 TP2**：實測啟動即被 vLLM 拒絕 ——
> `VLLM_PLE_CPU_OFFLOAD does not support the requested configuration. Unsupported settings: nnodes=2`。
> PLE CPU offload 是**單節點**功能；本 lane 維持 `PLE_OFFLOAD=false`（配方預設），
> `ULIMITS` profile 欄位仍為通用能力（實測 `nofile=1048576` 確實套用）。

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
gb10 list                     # profile list (27b/35b/deepseek/deepseek-vision/qwen38flash)
gb10 use 27b                  # default; TP2 up (cold ~7-15 min), waits /health
gb10 use 35b                  # switch exclusive cluster profile
gb10 use qwen38flash          # cluster-only lane (determinism on by default)
gb10 stop                     # cluster-down (both nodes)
gb10 restart [profile]        # no arg = last used profile (state/last-cluster-profile)
gb10 status                   # both nodes, RDMA, KV, health
gb10 inspect <profile>        # sanitized resolved-profile report (dry-run)
gb10 logs                     # follow cluster-node0
gb10 smoke                    # chat smoke
gb10 load                     # concurrent load
gb10 doctor
```

Current deployed TP2 profiles are 27B, 35B, DeepSeek (mainline 0731), DeepSeek Vision-Exp
and **qwen38flash** (all data-driven from `cluster-profiles.d/`). `qwen38flash` is
**cluster-only** — it has no single-node lane (the `runtimes.d/qwen38flash.conf`
placeholder was removed 2026-09-20, and so was `glm53flash.conf`).

### TP2 profile registry (completed 2026-09-05)

The TP2 profile layer is a **data-driven cluster profile registry** (see
`docs/TP2_PROFILE_REFACTOR_VALIDATION_2026-09-05.md`):

```text
cluster-profiles.d/
  27b.conf          # deployed + live-validated (world_size=2, maxlen 262144)
  35b.conf          # deployed + live-validated (world_size=2, maxlen 262144)
  deepseek.conf     # deployed + live-validated (fp8 DSpark mainline, 256k ctx)
  deepseek-vision.conf  # deployed + live-validated (Vision-Exp, same image as deepseek)
  qwen38flash.conf  # deployed + live-validated (Qwen3.8 Flash-Next 125B NVFP4 TP2+EP,
                    # cluster-only; see its section for the 2026-09-29 realignment)
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

~/docker-stacks/    node-local deploy artifacts (NOT in this repo):
  <stack>/          one dir per lane, named after the image source —
                    aeon-vllm-omni (27b/35b) · anemll-dspark-vllm-gx10 (deepseek)
                    anemll-dspark-vllm-gx10-miaFlaver (deepseek-vision)
                    mia-vllm-openai-qwen38flashNext (qwen38flash)
    docker-compose.<profile>.yml            (cluster-only lanes, materialized)
    docker-compose-<profile>-cluster.yml    (lanes that also run single: 27b/35b)
    docker-compose-<profile>-single.yml
    patches/                                SYNC_DIRS staging (lanes that need it)
  logs/<profile>/   unified boot + compose/container logs (not per-stack)
  config/           cluster.env / standalone.env (secrets, gitignored)
~/.cache/vllm-<profile>[-cluster|-single]   per-lane compile/autotune cache
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

- **`state/last-cluster-profile`** — 由 `bin/gb10` 寫入／讀取。
  - **寫入**：`use`／`start`／`restart` 啟動一個 cluster profile 的背景 boot 後，寫入該
    profile ID（僅限 27b/35b/deepseek/deepseek-vision/qwen38flash；placeholder profile
    不會寫入，因為它不會啟動任何 container）。檔案在 `.gitignore` 內，屬執行期產物，
    不會讓 `check-git-sync.sh` 的乾淨樹判定失敗。
  - **讀取**：`restart` 未指定 profile 時回退到此值
    （`P="${2:-$(cat "${REPO_DIR}/state/last-cluster-profile" ... || echo 27b)}"`），
    否則預設 `27b`。

**所以如果你檢查時發現 `state/` 是空目錄：那不是沒用的架構，而是正常的初始／乾淨
狀態**，只是還沒觸發過任何寫入動作（或某台 node 從未成功 `use`／`start` 過）。只要
`gb10 use 27b`、`gb10-single use node1 minimaxh3` 這類動作真正跑過一次，對應的標記檔
就會出現；之後記得它是執行期產物即可。
