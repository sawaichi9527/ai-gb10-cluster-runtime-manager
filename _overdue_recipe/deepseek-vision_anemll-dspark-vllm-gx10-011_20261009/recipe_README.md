# recipe_README — DeepSeek V4 Flash Vision-Exp（Anemll 配方，2026-10-09 退役）

> 本目錄封存 `deepseek-vision` **舊配方**（Anemll runtime + 官方 Vision-Exp
> 模型 + 17 個 MiaAI hotfix 的啟動 wrapper）與其 A/B tune lane
> `deepseek-vision-tune` 的完整部署資料。2026-10-09 配方繼承（eugr b12x
> 原生 vision）後退役為**備用方案**（非實時佈署）。

## 1. 配方身分（本目錄檔案）

| 項目 | 值 |
|---|---|
| profile | `deepseek-vision`（prod，退役 2026-10-09）；`deepseek-vision-tune`（V0–V5 單旋鈕 A/B lane，已移出 `bin/gb10` 白名單） |
| image | `ghcr.io/anemll/dspark-vllm-gx10:0.1.1`（manifest `sha256:a83948492cf13df455170fb42885f5ef4db54fefe0feff0f841ecbff464ac9d8`，與舊主線同顆） |
| 模型 | `~/docker-stacks/models/deepseek-vision-exp`（官方 Vision-Exp checkpoint，revision `6821d6ad3681a4b137b066b76094fa82ebd0a380` = HF main HEAD；MiaAI pin `86f746b…` 僅 README/.eval_results 差異，48 safetensors + config + tokenizer + `encoding/` 全部 byte 相同；**同模型 DSpark draft，無 /drafter mount**） |
| 關鍵設定 | DSpark `k=6` **probabilistic**、ctx 262144、8-way、batched 16384、GMU 0.80、KV **`nvfp4_ds_mla`**、capture **56**（miaai 公式 `seqs×(k+1)=8×7`）、block-size 256、`--long-prefill-token-threshold 0`、limit-mm `{"image":8}`、`thinking=true / effort=low` chat template、**prefix caching ON + 17 hotfix fail-closed** |
| vision 機制 | `CMD_WRAPPER` 啟動時在容器內：複製 `/model/encoding/encoding_dsv4.py` → vLLM tokenizer 路徑，再依序跑 `patches/dspark-vision/` 的 17 個 hotfix（含 `hotfix-vllm-dspark-swa-prefix.py`）；patch 目錄由 `SYNC_DIRS` 佈署兩節點、read-only 掛載（`vision_exp/` 內的 ViT/Aligner 支援同掛） |
| stack / compose | `~/docker-stacks/anemll-dspark-vllm-gx10-miaFlaver/`；`docker-compose.deepseek-vision.yml`（tune lane: `…-miaFlaver-tune/` + `docker-compose.deepseek-vision-tune.yml`） |
| 封存檔案 | `deepseek-vision-anemll.conf`（SHA256 `0df27c387a380e40cb9549c20147956047429db801c76337cc2664f5869eaafe`，退役當日 byte-identical）、`deepseek-vision-tune.conf` = `.base`（campaign 結束已還原 pristine 基線）、2× compose（2026-10-09 由 conf 渲染、API key 脫敏）、`patches/dspark-vision/`（17 patch + `vision_exp/` + `NOTICE.md`，MiaAI-Lab MIT、pin `97e8733…`） |

## 2. 歷史量測結果（benchmark）

量測方法：decode/prefill 用 `scripts/bench-ab-deepseek.sh`（C1..C8 ×3 取中位、
`BENCH_COLD=1`）、圖片用 `scripts/bench-mm.sh`（`BENCH_COLD=1`）。
**實測雜訊底：decode ≈ ±7%、prefill ≈ ±8%。**

### 2.1 最終記錄 V3 production（README 記錄基準）

單格格式 `tok/s`（最後欄為 accept %）：

| C | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | Σ | accept % |
|---|---|---|---|---|---|---|---|---|---|---|
| **V3 production warm boot** | 33.6 | 46.5 | 64.6 | 69.4 | 70.9 | 78.4 | 85.3 | 89.4 | **538.1** | 23.95 |
| V3 tune run A/B | 36.8 | 43.3 | 56.6 | 66.3 | 73.7 | 87.1 | 87.9 | 89.9 | **541.6 / 543.5** | 24.25 / 24.30 |

cold prefill（`bench-ctx.sh` `BENCH_COLD=1`，舊配方記錄）：

| 欄位 | V3 受控 | V0 |
|---|---|---|
| 131K | 1794.1 | 1825.3 |
| 200K | 1772.5 | 1710.2 |
| 245K | 1671.3 | — |
| 261K | 1657.7 | — |

* 圖片輸入（`bench-mm.sh`，舊配方記錄）：1 img C=1 **53.1**／C=4 **111.0**／
  C=8 **146.1**／C=16 **159.4**；4 img C=1 **36.3**；8 img C=1 **16.2**
  （每張圖約 320–390 prompt tokens，checkpoint `vision_max_n_token=384`）
* KV pool **381,364 tok**（`nvfp4_ds_mla`）
* 已知量測 caveat：32K 冷 prefill 為結構性噪音（跨 boot 1783~2234，±23%）；
  自然早停（`finish=stop` <200 tok）格不可比；**262144-word（=上限）請求被拒**
  → 實用上限 prompt ≤ 262143 tokens
* prefix caching 在本配方**必須**配 `hotfix-vllm-dspark-swa-prefix.py`
  （與主線同一退化類別）
* V0–V5 + V-win 完整調優記錄：
  `docs/DEEPSEEK_VISION_TUNE_AB_2026-10-07.md`

### 2.2 退役對決（2026-10-09 配方繼承 A/B，vs 本區 V3 記錄）

新配方（eugr b12x + `deepseek-v4-flash-vision-exp-ablit`，原生 vision、
無 CMD_WRAPPER/patches）三個 boot：

| boot | decode Σ | vs 記錄 538.1 | cold prefill vs 記錄 | prefix-hit |
|---|---|---|---|---|
| B0（上游 verbatim capture 48） | 506.1 | **−6.0%**（缺口集中 C7/C8，掉出 capture range `[1…48]`） | — | — |
| B1（capture **56**，單旋鈕修正） | 535.3 | **−0.5%（持平）** | 131K +9.4~13.1%／200K +6.5~12.1% | **50.9×、無需任何 hotfix** |
| B2（同設定確認 boot） | 545.9 | **+1.4%（持平偏正）** | 全欄同向、261K 1823.7（+10.0%） | 輸出位元組一致 |

* acceptance +1.0~1.4 pp；圖片輸入非冷跑 ≈ 持平、1 img C=4 +4.5%
* **唯一升版旋鈕 `CUDAGRAPH_CAPTURE 48→56`**（= 本配方 miaai 公式值）
* → decode 持平 + prefill 全欄超噪聲底 + 正確性 gate 無 hotfix 通過
  → **條件成立 → 新配方繼承、本配方退役**
* 報告：`docs/DEEPSEEK_VISION_B12X_RECIPE_AB_2026-10-09.md`
* 證據：`docs/evidence/vision-b12x-recipe-ab-2026-10-09/`

### 2.3 歷史索引

* 三欄對照與說明：repo `README.md`「DeepSeek V4 Flash Vision-Exp cluster (TP2)」
  對決區（B0/B1/B2 vs 舊配方記錄）
* 舊配方 V0/V3 調優全記錄：`docs/DEEPSEEK_VISION_TUNE_AB_2026-10-07.md`
* 上游共識：本配方 = MiaAI-Lab `DeepSeek-v4-Flash-DSpark-2x-DGX-Spark`
  的同 image、同機制（其預設 image 即 `anemll/dspark-vllm-gx10:0.1.1`）

## 3. 還原（rollback 到 Anemll 舊配方）

```sh
# 1. conf 放回 live 路徑
cp _overdue_recipe/deepseek-vision_anemll-dspark-vllm-gx10-011_20261009/deepseek-vision-anemll.conf \
   cluster-profiles.d/deepseek-vision.conf
# 2. runtime patches 放回 repo 根目錄（conf 的 SYNC_DIRS 解析 ${REPO_DIR}/patches/dspark-vision）
mkdir -p patches
cp -r _overdue_recipe/deepseek-vision_anemll-dspark-vllm-gx10-011_20261009/patches/dspark-vision patches/
# 3. 確認 pinned image 還在兩節點（docker images ghcr.io/anemll/dspark-vllm-gx10）；
#    若被 prune：node0 re-pull → 經 CX7 byte-transfer 到 node1 → 驗證 IMG_SHA256
# 4. 確認 models/deepseek-v4-flash-vision-exp 兩節點存在
# 5. 啟動：gb10 use deepseek-vision
```

`deepseek-vision-tune` 若需一併還原，conf 放回
`cluster-profiles.d/deepseek-vision-tune.conf` 並加回 `bin/gb10` 白名單 ——
但其基線已隨配方繼承失效；**未來 vision 調優請從現役配方另立新 lane +
新 `.base`，不要直接複活這份**。

## 4. 模型保留（使用者決定 2026-10-09）

**舊官方模型 `~/docker-stacks/models/deepseek-v4-flash-vision-exp`
依使用者決定暫留兩節點（node0 + node1），後續再議** —— 不要當成 promotion
殘渣清掉；它是本備用配方的模型依賴（還原步驟 4）。
