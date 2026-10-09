# recipe_README — DeepSeek V4 Flash 0731 mainline（Anemll 配方，2026-10-09 退役）

> 本目錄封存 `deepseek` **主線舊配方**（Anemll runtime + 官方模型）與其 A/B tune
> lane `deepseek-tune` 的完整部署資料。2026-10-09 配方繼承（eugr b12x +
> Dspark-Ablit）後退役為**備用方案**（非實時佈署）。

## 1. 配方身分（本目錄檔案）

| 項目 | 值 |
|---|---|
| profile | `deepseek`（prod，服役 2026-09-07 → 2026-10-09）；`deepseek-tune`（E0–E5 單旋鈕 A/B lane，已移出 `bin/gb10` 白名單） |
| image | `ghcr.io/anemll/dspark-vllm-gx10:0.1.1`（manifest `sha256:a83948492cf13df455170fb42885f5ef4db54fefe0feff0f841ecbff464ac9d8`，雙節點 2026-09-19 驗證） |
| 模型 | `~/docker-stacks/models/deepseek-v4-flash-0731-official`（官方 deepseek-ai fp8 checkpoint，pinned revision `9e165c30e27…`，Weschera SHA256SUMS gate；**無 /drafter mount**，同模型 DSpark draft） |
| 關鍵設定 | DSpark `k=7` **probabilistic**、ctx 262144、8-way、batched 16384、GMU 0.80、KV **`nvfp4_ds_mla`**、capture **8**、`--async-scheduling` + `--generation-config vllm` + flashinfer-autotune、**prefix caching ON + fail-closed `hotfix-vllm-dspark-swa-prefix.py`**（`VLLM_PREFIX_CACHE_RETENTION_INTERVAL=4096`） |
| stack / compose | `~/docker-stacks/anemll-dspark-vllm-gx10/`；`docker-compose.deepseek.yml`（tune lane: `docker-compose.deepseek-tune.yml`） |
| 封存檔案 | `deepseek-anemll.conf`（SHA256 `3147b4e99e6b040f2318b865666132f79d4ed72f9f475db0f0c48eaee78f0562`，退役當日 byte-identical）、`deepseek-tune.conf` = `deepseek-tune.conf.base`（campaign 結束已還原 pristine E0）、2× compose（2026-10-09 由 conf 渲染、API key 脫敏）、`patches/dspark-vision/` |

## 2. 歷史量測結果（benchmark）

量測方法：`scripts/bench-ab-deepseek.sh`（C1..C8 每格 3 次取中位、
`BENCH_IGNORE_EOS=1` 固定 400 tok/stream、`BENCH_COLD=1` cold prefill）+
`scripts/bench-prefix-hit.sh`（暖前綴命中探針）。
**實測雜訊底：decode ≈ ±7%、prefill ≈ ±8%** —— 小於此的差異不算結果。

### 2.1 最終記錄 E5/PROD（2026-10-07 production 驗收 —— 對決基準）

單格格式 `tok/s · accept %`：

| C | 改動前 2026-09-20（單次） | E0 2026-10-06（中位×3） | **E5/PROD 2026-10-07（中位×3）** | Δ vs E0 |
|---|---|---|---|---|
| 1 | 35.7 · 25.1 | 38.4 · 27.1 | **42.3 · 30.2** | **+10.2% · +3.1 pp** |
| 2 | 55.7 · 29.3 | 50.3 · 25.0 | **56.9 · 30.1** | **+13.1% · +5.1 pp** |
| 3 | 45.1 · 25.4 | 62.5 · 25.0 | **71.7 · 31.8** | **+14.7% · +6.8 pp** |
| 4 | 55.5 · 27.1 | 67.7 · 26.3 | **79.8 · 30.2** | **+17.9% · +3.9 pp** |
| 5 | — | 88.8 · 28.4 | **91.8 · 33.6** | +3.4% · +5.2 pp |
| 6 | — | 82.5 · 28.8 | **99.3 · 31.5** | **+20.4% · +2.7 pp** |
| 7 | — | 100.2 · 26.7 | **113.2 · 33.5** | **+13.0% · +6.8 pp** |
| 8 | 93.1 · 28.8 | 103.8 · 28.7 | **115.7 · 30.6** | **+11.5% · +1.9 pp** |
| **Σ / accept 中位** | —（僅 5 格，不可比） | 594.2 · 26.9 | **670.7 · 31.1** | **+12.9% · +4.5 pp（8/8 格正）** |

* cold prefill（`bench-ctx.sh` `BENCH_COLD=1`）：32K **1784.8**（+18.2%，該格為
  結構性噪音）／131K **1868.8**／200K **1747.3**（131K/200K 在 ±8% 底內＝持平）
* 261K 長文 gate：261021 tok @ **1648.2 tok/s**
* 暖前綴 prefill：**7.6× HIT**（15.50 s → 2.03 s；2065 → 15786 tok/s）
* KV pool **405,179 tok**（`nvfp4_ds_mla`）
* 驗收 gate（2026-10-07 00:18 全過）：`cluster-compose-verify` 雙 rank、
  `gb10 smoke`、3×3 完整性、261K/262K 長文、garble soak 3/3、`/health 200`

### 2.2 E0 → E5 調優 campaign（六旋鈕、全 profile 層、不重建 image）

* **採用**：`draft_sample_method` greedy → **probabilistic**、prefix caching
  **off → on**、`CMD_WRAPPER` 啟動時套 `hotfix-vllm-dspark-swa-prefix.py`
  （fail-closed：套不上就不起服）、retention 4096、EXTRA_MOUNTS 掛 `patches/`、
  `SYNC_DIRS` 雙節點佈署
* **拒絕**（量測落在雜訊內）：E1 `CUDAGRAPH_CAPTURE 8→128`（+2.1% 但 +16 s
  啟動 +1.9 GiB graph pool）、E4 `VLLM_USE_BREAKABLE_CUDAGRAPH=0`（−1.5%）
* **為何 prefix 必須配 hotfix**：cache hit 不補 DSpark draft 的 128-token
  sliding window → verifier 會接受**截斷**答案
* 完整記錄（E0–E5 六格、Winner table、Verdict）：
  `docs/DEEPSEEK_TUNE_AB_2026-10-06.md`

### 2.3 退役對決（2026-10-09 配方繼承 A/B，vs 本區 E5 記錄）

新配方（eugr b12x + drowzeys Dspark-Ablit，現役 `deepseek.conf`）兩個獨立 boot：

| boot | decode Σ | vs 記錄 670.7 | cold prefill vs 記錄 | prefix-hit |
|---|---|---|---|---|
| D0（候選 lane） | **693.3** | **+3.4%（8/8 格全正）** | 131K +16.3%／200K +16.9%／261K 1947.1（+18.1%） | **38.5×、無需 hotfix** |
| P0（promoted 生產線） | **673.2** | **+0.4%（持平偏正）** | 與 D0 ±0.7% 一致／261K 1925.1 | **38.3×、逐字一致** |

acceptance 31.1% → D0 33.4%（+2.3 pp）／P0 31.9%（+0.8 pp）；soak（3×3、
garble 3/3、262K 近硬限、health 200）全過。**兩 boot 皆 ≥ 記錄 → 條件成立 →
新配方繼承、本配方退役。**（新配方差異：KV fp8 —— `nvfp4_ds_mla` 在 eugr
image 結構性不可行 —— capture 64、batched 8192、GMU 0.85、prefix ON 但無 hotfix。）

* 報告：`docs/DEEPSEEK_B12X_RECIPE_AB_2026-10-09.md`
* 證據：`docs/evidence/deepseek-b12x-recipe-ab-2026-10-09/`
  （`ab-D0.txt` / `ab-P0.txt` / cycle outputs）

### 2.4 歷史索引

* 主線 onboard 2026-09-07（40K reference gate → 256KB + DSpark + 8-stream 契約）
* 三欄對照（09-20／E0／E5）與說明：repo `README.md`「DeepSeek V4 Flash 0731
  mainline (TP2) — 2026-10-06/07（E5 promote 後；舊配方記錄）」區
* 續作（現役新配方）：README「mainline on eugr b12x — 2026-10-09」區
* 上游 re-verify（2026-09-30）：`docs/DEEPSEEK_UPSTREAM_REVERIFY_2026-09-30.md`

## 3. 還原（rollback 到 Anemll 舊配方）

```sh
# 1. conf 放回 live 路徑
cp _overdue_recipe/deepseek_anemll-dspark-vllm-gx10-011_20261009/deepseek-anemll.conf \
   cluster-profiles.d/deepseek.conf
# 2. runtime patches 放回 repo 根目錄（conf 的 SYNC_DIRS 解析 ${REPO_DIR}/patches/dspark-vision）
mkdir -p patches
cp -r _overdue_recipe/deepseek_anemll-dspark-vllm-gx10-011_20261009/patches/dspark-vision patches/
# 3. 確認 pinned image 還在兩節點（docker images ghcr.io/anemll/dspark-vllm-gx10）；
#    若被 prune：node0 re-pull → 經 CX7 byte-transfer 到 node1 → 驗證 IMG_SHA256
# 4. 確認 models/deepseek-v4-flash-0731-official 兩節點存在
# 5. 啟動：gb10 use deepseek
#    （SYNC_DIRS 啟動時自動佈署 hotfix 目錄；fail-closed wrapper 套不上就不起服）
```

`deepseek-tune` 若需一併還原（A/B lane），conf 放回
`cluster-profiles.d/deepseek-tune.conf` 並加回 `bin/gb10` 白名單 ——
但其「production sibling」前提已隨配方繼承失效；**未來 mainline 調優請從
現役配方另立新 lane + 新 `.base`，不要直接複活這份**。

## 4. 模型保留（使用者決定 2026-10-09）

**舊官方模型 `~/docker-stacks/models/deepseek-v4-flash-0731-official`
依使用者決定暫留兩節點（node0 + node1），後續再議** —— 不要當成 promotion
殘渣清掉；它是本備用配方的模型依賴（還原步驟 4）。
