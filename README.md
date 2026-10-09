# ai-gb10-cluster-runtime-manager

DGX Spark **GB10 runtime manager** — 統合 **2-node TP2 叢集** 與 **單節點 runtimes** 於單一 repo。

- **`bin/gb10`** — TP2 叢集 CLI（thin layer 於 `scripts/cluster-*`）
- **`bin/gb10-single`** — 單節點 CLI（`node0` 本機 / `node1` 經 ssh）
- **`runtimes.d/*.conf`** — 單節點 runtime 定義
- **`cluster-profiles.d/*.conf`** — TP2 叢集 profile 定義（data-driven registry）
- **`scripts/cluster-*`** — 叢集部署腳本（ver detail 見 `docs/TP2_DEPLOYMENT_2026-08-30.md`）


## Deployed services & benchmark results (latest image)

> **2026-10-08 現況。** **現役 lane 切換為 `deepseek-nvfp4`**（NVFP4 0731 on eugr b12x）。
> Phase 3 完成：4 次 boot 依序修復 **seccomp/io_uring**（`SECURITY_OPT`）→ **b12x loader
> strided scale**（改 `--load-format safetensors`）→ **DSpark draft MXFP4 根因 hotfix**
> （in-checkpoint `mtp.*` 原生 MXFP4 被建成 NVFP4 → draft 垃圾；fail-closed 容器啟動
> patch，= vllm#49133 半修補）後 **READY、全 gate PASS**。C1–C8 聚合 **47.1 → 129.9
> tok/s（2.76×）**、acceptance 41–50% 全程不崩、prefix-hit 44.8×、garble 3/3、
> cold ctx 200K **1984.6 tok/s**。同日 **NVFP4 KV（`nvfp4_ds_mla`）A/B 負結果**
> （三重硬閘、已回退 fp8）與 `bench-c.sh` metrics auth 修正。使用者裁定
> **先不恢復主線**（`deepseek` 待命，`gb10 use deepseek` 隨時切回，TP2 互斥自動拆）。
> 詳見其章節與 handoff Phase 3。
>
> **2026-10-05 現況。** **現役 lane 切回 `deepseek`**（13:32 boot、t+8m READY、smoke
> `HELLO-TP2-OK`、KV 11.01 GiB）。10-03 上線的新 lane **`mimo26flash`**（MiMo V2.6 Flash
> MOPD，TP2 vLLM+DFlash，詳見其章節）完成 **NVFP4 變體評估 + 完整 A/B + DFlash cliff 探測**
> 後**定案 MXFP4** 並交還執行權：NVFP4 唯一紮實優勢是 prefill（+12~28%），MXFP4 勝在容量
> （+41% KV、8.81x@256K 撐得起 NUMSEQ=8）、官方 QAT + SHA256SUMS 與磁碟（−21GB/節點），
> decode 差距多在噪聲內；cliff 探測兩變體皆過（1024-token 滑窗後接受率不崩、0 NaN）。
> 完整證據見 [`docs/MIMO26FLASH_TP2_2026-10-03.md`](docs/MIMO26FLASH_TP2_2026-10-03.md)（§7 延後調優、§11）。
>
> **2026-09-29 現況。** qwen38flash 於當日對齊上游並重新驗證（GMU 0.835→0.80、prefix caching
> ON + vllm#53388 block-drop、deterministic greedy 預設 ON；見其章節）；**當日稍晚以
> `gb10 use deepseek` 切回 DeepSeek 0731 mainline**（見下方「現役」）；其餘 lane 仍為
> 09-19／09-20 實測。27B/35B 走 `ghcr.io/aeon-7/aeon-vllm-ultimate:2026-09-18-v0.29.0-omni`
> （單節點啟用 `VLLM_USE_V2_MODEL_RUNNER=1`）；DeepSeek 0731 用
> `ghcr.io/anemll/dspark-vllm-gx10:0.1.1`，**Vision-Exp 自 2026-10-09 起轉
> `eugr/spark-vllm-b12x:latest` + ablit 權重（配方繼承）**；qwen38flash 用
> `vllm/vllm-openai:qwen38-flash-next`。
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
| DeepSeek V4 Flash cluster (TP2) | `deepseek-v4-flash-0731-official` + DSpark n=7 | `anemll/dspark-vllm-gx10:0.1.1` | `http://192.168.23.215:1234/v1` | deployed（10-05 由 mimo26flash 切回；**10-07 E5 promote 實測**；10-08 讓位給 `deepseek-nvfp4` 待命） |
| DeepSeek V4 Flash **0731 NVFP4** cluster (TP2) | `DeepSeek-V4-Flash-0731-NVFP4`（MoE routed experts NVFP4，~172 GB／48 shards）+ DSpark n=5（in-checkpoint `mtp.*`，draft MXFP4 hotfix） | `eugr/spark-vllm-b12x:latest`（**2026-10-06** nightly，雙節點 digest pin） | `http://192.168.23.215:1234/v1` | **← 現役（2026-10-08 Phase 3 完成）**：C8 129.9 tok/s、accept 41–50%、KV 344,195 tok、smoke `HELLO-TP2-OK` |
| DeepSeek V4 Flash **Vision-Exp** cluster (TP2) | `deepseek-v4-flash-vision-exp-ablit` + DSpark n=6 (multimodal) | `eugr/spark-vllm-b12x:latest`（**10-09 配方繼承**；舊 Anemll 配方封存 `_backup/`） | `http://192.168.23.215:1234/v1` | deployed（10-09 對決勝出：decode 持平、prefill +9~14%） |
| Qwen3.8 Flash-Next **125B** cluster (TP2+EP) | `qwen3.8-flash-next-nvfp4`（ModelOpt NVFP4）+ 內建 MTP n=3 | `vllm/vllm-openai:qwen38-flash-next` | `http://192.168.23.215:1234/v1` | deployed（09-29 重新驗證）：GMU 0.80／prefix caching ON／determinism 預設 ON |
| MiMo V2.6 Flash **MOPD** cluster (TP2) | `mimo-v2.6-flash-mopd`（官方 MXFP4 QAT）+ DFlash2 n=7 | `tonyd2wild/vllm-glm53-flash:sm121-v11-dflash2` | `http://192.168.23.215:1234/v1` | deployed（10-03 上線；**10-05 定案 MXFP4**，NVFP4 A/B + cliff 探測見下） |

> **現役（2026-10-08）＝ deepseek-nvfp4**（NVIDIA NVFP4 0731 checkpoint on
> `eugr/spark-vllm-b12x`；`:1234` READY、smoke `HELLO-TP2-OK`、KV 344,195 tok。
> Phase 3 四次 boot 修復 seccomp → safetensors → DSpark draft 根因 hotfix；使用者裁定
> **先不恢復主線**，`gb10 use deepseek` 隨時切回——TP2 各 lane **互斥**，同一時間只有一條
> 在線，切換由 `gb10 use` 自動拆）。其他列的 `deployed`
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

### DeepSeek V4 Flash Vision-EXP-ablit (TP2, eugr b12x) — 2026-10-09 配方繼承

> `cluster-profiles.d/deepseek-vision.conf`：**2026-10-09 配方繼承（promote）**——
> `eugr/spark-vllm-b12x:latest`（與 `deepseek-nvfp4` 同款 image、雙節點 digest pin
> `036c3076…`/`dc0e9faa…`）+ `deepseek-v4-flash-vision-exp-ablit`
> （167.8 GB、48 shards；abliterated 官方 Vision-EXP，26 個 tensor 編輯、
> **MTP/draft tensor 與官方位元組相同**）。Vision 支援**原生內建**
> （上游 `recipes/deepseek-v4-flash-vision-exp.yaml`、`mods: []`）——
> **不再需要啟動 wrapper 與 17 個 MiaAI hotfix**，`CMD_WRAPPER`、`SYNC_DIRS`、
> `patches/` 掛載全部移除。fp8 KV（`nvfp4_ds_mla` 在此 image 對 DeepSeekV4
> 結構性不可行，見 `deepseek-nvfp4` A/B cell B）、B12X kernel trio、DSpark k=6
> probabilistic B12X、block 256 / batched 8192 / 8-way / GMU 0.85、
> **prefix caching ON（此 fork 無需 hotfix 即過 prefix-hit gate）**、
> **`CUDAGRAPH_CAPTURE=56`**（對決唯一升版旋鈕：上游 verbatim 48 於 C7/C8
> 掉 capture range，Σ −6%；56 = 舊配方 miaai 公式值，兩 boot 同號拉回持平）。
> 兩 profile 互斥切換（`gb10 use deepseek` ↔ `gb10 use deepseek-vision`）。
> KV pool **413,967 tokens**（舊配方 nvfp4_ds_mla 381,364，**反而更大**）。
>
> **舊 Anemll 配方封存為備用方案**（非實時佈署）：
> `cluster-profiles.d/_backup/deepseek-vision-anemll.conf`（byte-identical）
> + `patches/dspark-vision/`（原地保留，含 `NOTICE.md`）；還原步驟見
> `cluster-profiles.d/_backup/README.md`。對決全紀錄：
> `docs/DEEPSEEK_VISION_B12X_RECIPE_AB_2026-10-09.md`（證據
> `docs/evidence/vision-b12x-recipe-ab-2026-10-09/`）。
>
> **2026-10-09 配方對決**（新配方 B1/B2 兩 boot vs 舊配方 README 記錄）：

**Decode（C1…C8 × 3 取中位數，`scripts/bench-ab-deepseek.sh`；`Σ` = 八段中位數相加）**

| C | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | Σ | accept % |
|---|---|---|---|---|---|---|---|---|---|---|
| **新配方 B1（capture 56）** | 39.7 | 43.9 | 55.7 | 69.7 | 74.9 | 74.1 | 81.2 | 96.1 | **535.3** | 25.0 |
| **新配方 B2（同設定確認 boot）** | 34.8 | 50.1 | 60.0 | 67.3 | 70.2 | 83.7 | 86.9 | 92.9 | **545.9** | 25.4 |
| 新配方 B0（上游 verbatim capture 48） | 31.3 | 48.9 | 55.7 | 62.5 | 76.6 | 76.7 | 72.1 | 82.3 | 506.1 | 23.7 |
| 舊配方記錄（V3 production warm boot） | 33.6 | 46.5 | 64.6 | 69.4 | 70.9 | 78.4 | 85.3 | 89.4 | 538.1 | 23.95 |
| 舊配方記錄（V3 tune run A/B） | 36.8 | 43.3 | 56.6 | 66.3 | 73.7 | 87.1 | 87.9 | 89.9 | 541.6 / 543.5 | 24.25 / 24.30 |
| **Δ 新配方(B1/B2) vs 舊記錄** | | | | | | | | | **−0.5% / +1.4%（持平）** | **+1.0~1.4 pp** |

> B0（上游配方 verbatim、`CUDAGRAPH_CAPTURE=48`）Σ −6.0%，缺口集中在 C7/C8
> （−15.5% / −8.0%，超出 capture range `[1…48]` 的高併發 fallback）；
> **單旋鈕 B1（48→56，= 舊配方 miaai 公式 seqs×(k+1)=8×7）**一次修復，
> 兩次 boot 同號（散佈 2.0%，在 `<~2%` 決策門檻內）→ **decode 持平成立**。
> decode 噪聲底 ±7%（2026-10-06/08 campaign 實測）。
> 舊配方完整 V0/V3 調優記錄見 `docs/DEEPSEEK_VISION_TUNE_AB_2026-10-07.md`。

| prefill probe (`bench-ctx.sh` BENCH_COLD=1, max_tokens=1) | 新配方 tok/s (B0/B1/B2) | 舊配方記錄 | Δ |
|---|---|---|---|
| 131K | 2005.8 / 2007.9 / 2029.5 | 1794.1（V3 受控） / 1825.3（V0） | **+9.4 ~ +13.1%** |
| 200K | 1907.7 / 1887.2 / 1917.0 | 1772.5（V3 受控） / 1710.2（V0） | **+6.5 ~ +12.1%** |
| 245K | 1844.8 | 1671.3 | **+10.4%** |
| 261K | 1823.7 | 1657.7（V3） | **+10.0%** |

> prefill 三 boot 同號、全欄超出 ±8% 噪聲底 → **更優**（`bench-ab` 內建 32K/131K/200K
> 與 `bench-ctx` 長探針讀數互相吻合）。**32K 冷 prefill 仍為結構性噪聲
> （跨 boot 1783~2234 tok/s，±23%），不可當證據。**

| 圖片輸入 (`bench-mm.sh` BENCH_COLD=1, max_tokens=200) | 新配方 B2 | 舊配方記錄 | 說明 |
|---|---|---|---|
| 1 img, C=1 | 46.6（冷） / 53.9（非冷首跑, B0） | 53.1 | **非冷跑 ≈ 持平**；冷跑 −11% 來自 nonce 前綴失配 |
| 4 img, C=1 | 34.5 | 36.3 | 早停格（82 tok），不可比 |
| 8 img, C=1 | 32.4 | 16.2 | 早停格（75 tok vs 記錄 200 tok），不可比 |
| 1 img, C=4 | 116.0 | 111.0 | **+4.5%** |
| 1 img, C=8 | 135.0 | 146.1 | −7.6%（含早停） |
| 1 img, C=16 | 152.1 | 159.4 | −4.6% |
| 4 img, C=8 | 147.3 | 90.6 | 早停灌水，不可比 |

> 多模態：OpenAI `image_url`（base64）正常，每張圖約 320–390 prompt tokens
> （checkpoint `vision_max_n_token=384`）；`--limit-mm-per-prompt {"image":8}`。
> **262144-word（=上限）請求被拒** → 實用上限 prompt ≤ 262143 tokens。
> 自然早停（`finish=stop` <200 tok）的格 wall 偏短，不可直接與記錄比。
> Prefix caching 實測（新配方，無需任何 hotfix）：同一 32K prompt 三連發
> → **17.87s → 0.35s（50.9×）**，三輪輸出位元組一致（`PREFIX-OK`）、無
> truncation/garble——舊配方 `dspark-swa-prefix` hotfix 防的退化類別在此 fork 未重現。

### DeepSeek V4 Flash 0731 mainline (TP2) — 2026-10-06/07（E5 promote 後）

> `cluster-profiles.d/deepseek.conf`：官方 `deepseek-v4-flash-0731-official` fp8 checkpoint +
> `anemll/dspark-vllm-gx10:0.1.1`（舊 Vision 配方同 image；vision 已於 10-09 轉 eugr b12x），DSpark n=7 **probabilistic**、
> 256K / 8-way、**prefix caching ON**（2026-10-06 E5 promote；見下）。
> `bench-c` 之 prompt 約 118 tok（Vision-Exp 約 197 tok——同文字，tokenizer/chat template 差異）。
>
> **三欄對照怎麼讀**（下面兩張表的 Δ 欄一律只對 **E0** 計算）：
>
> * `改動前 2026-09-20` = 參數改動前的**舊版**量測：greedy、prefix caching off、
>   **單次**、只跑 C1/2/3/4/8、舊 harness（prefill 也沒有 `BENCH_COLD` 開關）。
> * `改動前 E0 2026-10-06` = **同樣是改動前的設定**，但換成新 harness 重測：
>   C=1…8、每格 3 次取**中位數**。所以 **09-20 → E0 這一段的差異是量測方法，不是效能提升**
>   （09-20 欄本身非單調：C3 45.1 < C2 55.7，正是單次抖動的證據）。
> * `改動後 E5/PROD 2026-10-07` = promote 進 `deepseek.conf` 後在 **production lane** 上的驗收量測。
> * `—` = 舊版沒測那格。只有 E0 ↔ E5 是同 harness、可直接相減。
>
> **改了什麼（E0 → E5，六個、全在 profile 層、不重建 image）**：
> `draft_sample_method` greedy → **probabilistic**、`ENABLE_PREFIX_CACHING` → **true**、
> `CMD_WRAPPER` 啟動時套 `hotfix-vllm-dspark-swa-prefix.py`（fail-closed）、
> `VLLM_PREFIX_CACHE_RETENTION_INTERVAL=4096`、EXTRA_MOUNTS 掛 `patches/`、
> `SYNC_DIRS` 同步到兩節點。
>
> **量測方法**：harness = `scripts/bench-ab-deepseek.sh`（`BENCH_IGNORE_EOS=1` 固定 400
> tok/stream、`BENCH_COLD=1` prefill、engine diag、3× 重複 prompt 完整性）+
> `scripts/bench-prefix-hit.sh`（暖前綴命中探針）。
> **實測雜訊底：decode ≈ ±7 %、prefill ≈ ±8 %** —— 小於此的差異不是結果。

單格格式 **`tok/s · accept %`**。

| C | 改動前 2026-09-20（單次） | 改動前 E0 2026-10-06（中位×3） | **改動後 E5/PROD 2026-10-07（中位×3）** | Δ vs E0 |
|---|---|---|---|---|
| 1 | 35.7 · 25.1 | 38.4 · 27.1 | **42.3 · 30.2** | **+10.2 % · +3.1 pp** |
| 2 | 55.7 · 29.3 | 50.3 · 25.0 | **56.9 · 30.1** | **+13.1 % · +5.1 pp** |
| 3 | 45.1 · 25.4 | 62.5 · 25.0 | **71.7 · 31.8** | **+14.7 % · +6.8 pp** |
| 4 | 55.5 · 27.1 | 67.7 · 26.3 | **79.8 · 30.2** | **+17.9 % · +3.9 pp** |
| 5 | — | 88.8 · 28.4 | **91.8 · 33.6** | +3.4 % · +5.2 pp |
| 6 | — | 82.5 · 28.8 | **99.3 · 31.5** | **+20.4 % · +2.7 pp** |
| 7 | — | 100.2 · 26.7 | **113.2 · 33.5** | **+13.0 % · +6.8 pp** |
| 8 | 93.1 · 28.8 | 103.8 · 28.7 | **115.7 · 30.6** | **+11.5 % · +1.9 pp** |
| **Σ / 中位** | —（僅 C1/2/3/4/8，不可比） | 594.2 · 26.9 | **670.7 · 31.1** | **+12.9 % · +4.5 pp** |

> **Σ 行的兩個 Δ 口徑不同，請照這個讀**：
> `Σ tok/s` = 八格中位數相加後相除（594.2 → 670.7 = **+12.9 %**）；
> **`Δ accept` = 八格 delta 的中位數 = +4.5 pp**（與 campaign 文件同口徑，欄名 `acc Δ (median pp)`；
> 逐格 delta 全正 ⇒ **8/8 positive**）。
> 直接相減兩欄中位數 31.1 − 26.9 會得到 +4.2 pp ——「差的中位數」≠「中位數的差」，兩者都對，別混用。

| cold prefill（`bench-ctx.sh`, `max_tokens=1`） | 改動前 2026-09-20<br>（舊 harness，無 `BENCH_COLD`） | 改動前 E0 2026-10-06<br>（`BENCH_COLD=1`） | **改動後 E5/PROD 2026-10-07**<br>（`BENCH_COLD=1`） | Δ vs E0 |
|---|---|---|---|---|
| 32K | 1516.9 | 1510.1 | **1784.8** | +18.2 % |
| 131K | 1682.3 | 1907.6 | **1868.8** | −2.0 % |
| 200K | 1725.0 | 1791.8 | **1747.3** | −2.5 % |

> 131K/200K 在 ±8 % 底內＝持平；32K 的 +18.2 % 是該探針最吵的一格（E0…E4 各格橫跨
> 1106–1711 tok/s）且另兩格沒動 → **不算提升**。
> E0 與 PROD 兩欄為 `BENCH_COLD=1`（每次重起容器後首測）；09-20 舊欄當時沒有這個開關，
> 跨欄只能參考。prefix caching 的收益三欄都看不到（都是冷啟動），見下方暖前綴 probe。

> **promote 後的正式設定驗收（2026-10-07 00:18，全過）**，詳見
> `docs/DEEPSEEK_TUNE_AB_2026-10-06.md`（E0–E5 六格完整記錄、Winner table、Verdict）：
>
> * **暖前綴 prefill 7.6× HIT**（15.50 s → 2.03 s，2065 → 15786 tok/s）——
>   cold prefill／啟動時間／graph pool／KV 皆不變；首次觸發的 prefill 沒變快
> * gate：`cluster-compose-verify`（雙 rank）、`gb10 smoke`、3×3 完整性、
>   261K 長文（261021 tok / 1648.2 tok/s）、garble soak 3/3、`/health 200` 全過
> * **E1**（`CUDAGRAPH_CAPTURE` 8→128）與 **E4**（`VLLM_USE_BREAKABLE_CUDAGRAPH=0`）
>   落在雜訊內已排除（E1 還要多花 16 s 啟動 + 1.9 GiB graph pool）
> * 為什麼 prefix caching 必須配 hotfix：沒有 `hotfix-vllm-dspark-swa-prefix.py` 時，
>   cache hit 會讓 DSpark draft 的 128-token sliding window 沒有前綴，
>   verifier 接受**截斷**答案 —— 所以 `CMD_WRAPPER` 是 fail-closed（套不上就不起服）

### DeepSeek V4 Flash 0731 NVFP4 on eugr b12x (TP2) — 2026-10-08（Phase 3 完成，**現役**）

> `cluster-profiles.d/deepseek-nvfp4.conf`：NVIDIA `DeepSeek-V4-Flash-0731-NVFP4` checkpoint
> （MoE routed experts 為 NVFP4、DSpark heads 保留未量化，~172 GB / 48 shards，非 gated、MIT）+
> **`eugr/spark-vllm-b12x:latest`**（DockerHub nightly CI，`eugr/spark-vllm-docker`
> `recipes/deepseek-v4-flash-0731.yaml` 為配方基準；image created **2026-10-06**、
> vLLM `0.1.dev21554+geda1715e9.d20261006`，**雙節點 digest pin**
> `IMG_SHA256=sha256:036c3076…` + `IMG_SHA256_NODE1=sha256:dc0e9faa…`）。
>
> **動機**：mainline/vision 鎖在 `anemll/dspark-vllm-gx10:0.1.1`（上游疑似停止維護）；
> 本 lane 把同一代 0731 模型搬到有持續 CI 的 runtime，**不動** `deepseek.conf` /
> `deepseek-vision.conf`。TP2 專屬、與所有 lane 互斥（同 port 1234 + 同 GPU），
> 以 `gb10 use deepseek-nvfp4` 啟動。合約與 aeon 同級：**262144 ctx / 8-way /
> 8192 batched / GMU 0.85**（KV pool 344,195 tok ⇒ 全長 256K 單流 1.31x；
> 8 路一般長度足夠，8×256K 同時為物理上限外——conf 註解已記）。

**Phase 1–2（2026-10-07，資產 + repo）**：模型 49/49 LFS 對 HF sha256 全中、`SHA256SUMS`
（75 檔）rsync 經 CX7 傳 node1、`gb10 verify-models` 兩節點 PASS；image 經 `docker save |
ssh` 傳 node1（對外頻寬只吃一次）、節點間內容同一性已證（29 層 diff ID + `.Config` 摘要）；
profile/bin 白名單通過 `bash -n` + 八條既有 lane byte-identical render（`1f8a1e8`、`7cef7d5`）。

**Phase 3（2026-10-08，4 次 boot → READY ~21 min，全 gate PASS）**：

1. **boot #1 fail（io_uring/seccomp）**：Docker 預設 seccomp 擋 io_uring → 通用 profile
   欄位 `SECURITY_OPT=("seccomp=unconfined")` + `cluster-compose-verify` SecurityOpt
   改 **subset match**（`10fff38` + `2cdec55`）。
2. **boot #2 fail（b12x loader strided conversion）**：`--load-format b12x` 對
   `mtp.1.ffn.experts.0.w1.scale` 嘗試 E8M0→e4m3 轉換 `NotImplementedError` →
   改 **`--load-format safetensors`**（`d2b090d`；事後證實此錯正是 #3 的另一表現）。
3. **boot #3 READY 但 DSpark acceptance 崩**（~16 tok/s、pos0 0.10）→ **根因**：
   checkpoint 的 draft 專家（`mtp.*`，quant `ignore` 明列豁免）**原生 MXFP4**
   （int8+ue8m0 g32），但 draft 的 quant 實例 `moe_quant_algo` 懶解析自**與 target
   共享的 NVFP4 hf dict** → 建成 `ModelOptNvFp4FusedMoE` → ue8m0 g32 scale 靜默灌進
   e4m3 g16 buffer → **draft MoE 算垃圾**。= 上游 `vllm-project/vllm#49133`
   （closed unmerged；本 image 只吃了一半修法）。鐵證：`Mxfp4 MoE backend` 兩節點 0 次、
   modelopt w1/w3 警告與 draft load 同秒。
4. **boot #4 hotfix 接線 → READY、全 gate PASS**：
   `patches/eugr-spark-vllm-b12x/hotfix-dspark-draft-mxfp4.py` —— fail-closed
   容器啟動 patch（region 恰一次 + 全檔 sha pin、原子寫入；在 draft 自己的 quant
   實例上預清空 `_resolved_moe_quant_algo` → dispatch 走官方 `Mxfp4MoEMethod`；
   target 不動），由 `CMD_WRAPPER` + `EXTRA_MOUNTS`（ro `/opt/eugr-patches`）+
   `SYNC_DIRS`（雙節點，Node1 無 repo）接線。完整根因見 conf 頭部 **KNOWN RISK #2**。
   Gate：hotfix `applied` ×2 rank、`Mxfp4 MoE backend`（`B12X_MXFP4_MXFP8`）出現、
   modelopt 警告 0/0、health 200、smoke `HELLO-TP2-OK`、compose-verify 兩 rank PASS、
   prefix-hit **HIT 44.8×**（3 輪 `PREFIX-OK` 一致無截斷）、garble soak **3/3**
   （`finish=stop`、`uniq=1.0`、primes 10/10）、**無 Marlin fallback**。

#### Benchmark（2026-10-08，現役 boot）

`scripts/bench-c.sh` + `BENCH_IGNORE_EOS=1`（每 stream 恰 400 tok；prompt 197 tok
混合 code+JSON；**thinking 預設開**——payload 無 `chat_template_kwargs`）。
acceptance 由 `/metrics` spec-decode 計數 delta 取得（期間修掉 `bench-c.sh` 的
metrics scrape 缺 auth bug：本 image `/metrics` 掛在 `VLLM_API_KEY` 後，401 → 全格
`(no draft delta)`）。首輪/重跑吞吐逐格誤差 ≤9%；decode 噪聲底 ≈ ±7%。

| C | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 |
|---|---|---|---|---|---|---|---|---|
| aggregate tok/s | 47.1 | 69.0 | 71.3 | 90.7 | 87.1 | 110.1 | 123.4 | **129.9** |
| accept % | 47.6 | 50.0 | 41.4 | 43.0 | 44.8 | 43.9 | 48.8 | 45.2 |
| mean accept len /5 | 2.38 | 2.50 | 2.07 | 2.15 | 2.24 | 2.19 | 2.44 | 2.26 |
| pos0 accept % | 83.8 | 79.0 | 73.8 | 79.8 | 79.6 | 77.9 | 83.0 | 79.5 |

> **判讀**：C1→C8 **2.76× 擴展**（Σ=728.7 tok/s），C6→C8 仍爬升未見高原；
> **acceptance 全程 41–50% 不隨併發崩落**（pos0 穩 74–84%，pos5/6 恆 0 = n=5 結構上限）
> ⇒ 多流 DSpark 健康、併發原生可用。per-pos 遞減至 pos4 15.8–26.2%。
> 單流對照（thinking off）：**code 66.4 tok/s / accept 78.2% / AL 4.91**
> （per-pos 0.93/0.86/0.81/0.70/0.61）；warm prose 37.3 tok/s（temp0）／36.9（temp0.7）。
> temp0 驗收 gate（pos0 ≥ 0.3）：**pos0 0.629 / avg 27.0% / AL 2.35**（基線 16 tok/s → 33.6，
> **+110%**）。`temp0.7`（`gb10 load` 3 輪）avg **49.6–59.0%** —— 官方 ckpt 社區基準
> 46–60% 同級。cold prefill `bench-ctx 200000` = **1984.6 tok/s**（200101 tok / 100.8 s）。
> 社區對照（pnivek/vllm-dspark-nvfp4：code 59.7 / prose 38.5 tok/s）——本 lane code 超越、
> prose 相近；60+ tok/s 的「community 數字」= code-gen／thinking-off／warm，與 workload 相符。

#### NVFP4 KV A/B（2026-10-08）＝**負結果，已回退 fp8**

`KV_DTYPE=nvfp4_ds_mla` 單旋鈕 B cell **決定性開機失敗**（雙 rank `EngineCore init` →
`ValueError`）。三重獨立硬閘（image 2026-10-06）：① DeepSeekV4 模型層
`use_fp8_ds_mla_layout=True`，resolver 只收 `fp8*`（`config/cache.py` 的通用接受清單
會誤導）；② `b12x_mla_sparse.py`「B12X nvfp4_ds_mla requires **GLM5Next**」；
③ `flashmla_sparse.py` 需 **SM100**。→ **DeepSeekV4 on GB10 無可行路**，未有上游
變更勿重試（完整註記在 conf `KV_DTYPE` 段與 handoff Phase 3 第 7 項）。

**配方差異點（相對 eugr recipe，皆記錄於 conf）**：`QUANTIZATION=none`
（checkpoint 自帶 `hf_quant_config.json`，vLLM 自動偵測）、**`--load-format
safetensors`**（`b12x` loader 對 draft strided scale 崩，見 Phase 3 #2）、
prefix caching 按 recipe 開啟且**已過截斷探針**、`--attention_config.
use_fp4_indexer_cache` / `--enable-expert-parallel` 列為 boot-stage 候選不預設。
NVIDIA **未驗證**此 checkpoint 的 DSpark spec decode——已在 Phase 3 實測。
同名舊 lane（AEON NVFP4 實驗）已刪，非復活。

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

### MiMo V2.6 Flash MOPD (TP2, vLLM + DFlash) — 2026-10-03 上線；2026-10-05 定案 MXFP4

> `cluster-profiles.d/mimo26flash.conf`：Xiaomi 官方 **MXFP4 QAT** MOPD checkpoint（RL/base
> 的 tool-call 重複問題的官方修復版）+ community image `tonyd2wild/vllm-glm53-flash:sm121-v11-dflash2`
> （vLLM fork，pin manifest digest）+ **DFlash2 n=7**（drafter 內嵌於 checkpoint 的 `dflash/`）。
> **256K ctx / 8-way、GMU 0.90、prefix caching ON**、`--kv-cache-dtype fp8`、MoE `marlin`；
> 三支 vendored patch bind-mount 於 `patches/mimo26flash/`（image 內建 `mimo_v2.py` 缺
> `cache_config`/`sliding_window` 修正 + ckpt_tp QKV 分片，見 docs §2/§11）。cluster-only、
> exclusive；model id `aeon`。**TP2-only**（178GB 權重放不進單節點，無 gb10-single lane）。

Decode（`bench-c.sh` + `BENCH_IGNORE_EOS=1`，每 stream 恰好 400 tok）與冷 prefill —
2026-10-03 實測：

| C | 1 | 2 | 4 | 8 |
|---|---|---|---|---|
| aggregate tok/s | 21.1 | 33.9 | 49.1 | **67.9** |

| prefill (`BENCH_COLD=1`) | 32K | 131K | 245K |
|---|---|---|---|
| tok/s | 1,553.7 | 1,015.4 | 724.3 |

#### NVFP4 變體 A/B + 定案（2026-10-05，單一變量＝只 flip `BODY_REL`）

`ProCreations/MiMo-V2.6-Flash-MOPD-NVFP4`（W4A16，同 MOPD 檢查點的第三方重轉）評估通過
（smoke/tool-call/多模態全過），與 MXFP4 同 harness 各跑 `scripts/bench-ab.sh`：

| | MXFP4 | NVFP4 | 勝方 |
|---|---|---|---|
| 冷 prefill 32K/131K/245K | 1552.8 / 1010.6 / 722.9 | **1995.0 / 1190.5 / 809.8**（+12~28%） | **NVFP4**（超噪聲） |
| decode C1 / C2 | 18.1 / 33.9 | 23.3 / 37.3 | NVFP4（邊緣，範圍重疊） |
| decode C4 / C8 | 53.3 / **62.2** | 42.6 / 55.7 | MXFP4（僅 C8 超噪聲） |
| KV tokens @256K 併發 | **2,310,732 / 8.81x** | 1,366,981 / 5.21x | **MXFP4**（+41%） |
| SHA256SUMS / 磁碟 | **有 / 177.8 GB** | 無（boot WARN）/ 198.83 GB | **MXFP4** |

> **定案（2026-10-05）＝ MXFP4**：GB10 無原生 FP4（vLLM boot 即警告走 Marlin weight-only），
> NVFP4 只買到 prefill/低併發的權重讀取優勢、卻以 41% KV 容量與官方 QAT+SHA256SUMS 為代價。
> 回 NVFP4 只需 flip `BODY_REL`+`DISPLAY_NAME` + `gb10 use`。
>
> **DFlash cliff 探測（同日）兩變體皆過**：Plaaasma 報的 1024-token 滑窗 NaN cliff 在本棧
> 無法重現（`>1070 tok` 長生成接受率不崩、engine 0 NaN）；400-tok bench 抓不到此類問題，
> image/draft 變更後應以 `node0:/tmp/dflash-cliff.sh` 重跑。延後調優 C/D/E（
> `repetition_penalty 1.05` A/B、`--long-prefill-token-threshold 2048`、tool-parser truncation）
> 見 docs §7。完整報告：[`docs/MIMO26FLASH_TP2_2026-10-03.md`](docs/MIMO26FLASH_TP2_2026-10-03.md)。

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
gb10 list                     # profile list (27b/35b/deepseek/deepseek-nvfp4/deepseek-vision/qwen38flash/mimo26flash)
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

Current deployed TP2 profiles are 27B, 35B, DeepSeek (mainline 0731), **DeepSeek NVFP4
(0731 on eugr b12x)**, DeepSeek Vision-Exp, **qwen38flash** and **mimo26flash** (all
data-driven from `cluster-profiles.d/`). The last two plus deepseek-nvfp4 are
**cluster-only** — no single-node lane (the `runtimes.d/qwen38flash.conf` placeholder was removed
2026-09-20, and so was `glm53flash.conf`; `mimo26flash` never had one — its weights are TP2-only;
`deepseek-nvfp4` is TP2-only by design). **deepseek-nvfp4 completed Phase 3 on 2026-10-08 and
is the current live lane** — see its section for boot fixes and benchmarks.

### TP2 profile registry (completed 2026-09-05)

The TP2 profile layer is a **data-driven cluster profile registry** (see
`docs/TP2_PROFILE_REFACTOR_VALIDATION_2026-09-05.md`):

```text
cluster-profiles.d/
  27b.conf          # deployed + live-validated (world_size=2, maxlen 262144)
  35b.conf          # deployed + live-validated (world_size=2, maxlen 262144)
  deepseek.conf     # deployed + live-validated (fp8 DSpark mainline, 256k ctx)
  deepseek-vision.conf  # deployed + live-validated (Vision-EXP-ablit on eugr b12x —
                        # 2026-10-09 recipe succession; old Anemll recipe archived in
                        # cluster-profiles.d/_backup/ + patches/dspark-vision/)
  qwen38flash.conf  # deployed + live-validated (Qwen3.8 Flash-Next 125B NVFP4 TP2+EP,
                    # cluster-only; see its section for the 2026-09-29 realignment)
  mimo26flash.conf  # deployed + live-validated (MiMo V2.6 Flash MOPD MXFP4 + DFlash2,
                    # cluster-only; BODY_REL flips MXFP4/NVFP4 — see its section)
  deepseek-nvfp4.conf   # deployed + live-validated (2026-10-08 Phase 3; NVFP4 0731 on
                        # eugr spark-vllm-b12x; draft MXFP4 hotfix, see its README section)
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
`~/_archieve/cluster-profiles.d/deepseek-nvfp4.conf` — **name collision warning**: the
active `deepseek-nvfp4` profile (2026-10-07, `nvidia/DeepSeek-V4-Flash-0731-NVFP4` on
`eugr/spark-vllm-b12x`) is a **different, unrelated lane** that reuses the name; the
archived one was an AEON-image experiment and is not being revived.

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
                    eugr-spark-vllm-b12x (deepseek-nvfp4)
                    eugr-spark-vllm-b12x-vision (deepseek-vision, since 10-09;
                      the old anemll-dspark-vllm-gx10-miaFlaver is retired —
                      recipe archived in cluster-profiles.d/_backup/)
                    mia-vllm-openai-qwen38flashNext (qwen38flash)
                    tonyd2wild-vllm-mimo26flash (mimo26flash)
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
    profile ID（僅限 27b/35b/deepseek/deepseek-nvfp4/deepseek-vision/qwen38flash/mimo26flash；placeholder profile
    不會寫入，因為它不會啟動任何 container）。檔案在 `.gitignore` 內，屬執行期產物，
    不會讓 `check-git-sync.sh` 的乾淨樹判定失敗。
  - **讀取**：`restart` 未指定 profile 時回退到此值
    （`P="${2:-$(cat "${REPO_DIR}/state/last-cluster-profile" ... || echo 27b)}"`），
    否則預設 `27b`。

**所以如果你檢查時發現 `state/` 是空目錄：那不是沒用的架構，而是正常的初始／乾淨
狀態**，只是還沒觸發過任何寫入動作（或某台 node 從未成功 `use`／`start` 過）。只要
`gb10 use 27b`、`gb10-single use node1 minimaxh3` 這類動作真正跑過一次，對應的標記檔
就會出現；之後記得它是執行期產物即可。
