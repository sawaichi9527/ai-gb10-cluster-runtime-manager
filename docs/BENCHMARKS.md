# BENCHMARKS — 量測總覽與歷史

本檔是 `README.md` 的**詳細數據附錄**：README 只留每個模型最新一次量測，這裡保留完整表格、
A/B 對決、噪聲底、量測協定與歷史數字。原始舊版 README（v1.x）另存於
[`docs/_archive/README_ARCHIVE_2026-10-22.md`](_archive/README_ARCHIVE_2026-10-22.md)。

**最後整理：2026-10-22（v2.0.0）。** 表格後的日期＝該次量測日期，不是文件更新日期。

---

## 0. 怎麼讀這些數字

**噪聲底（決策門檻）**

| 指標 | 可重現噪聲底 | 來源 |
|---|---|---|
| decode（`bench-c`，固定 400 tok） | **±7 %** | 2026-10-06/08 DeepSeek campaign |
| prefill（`bench-ctx`，`BENCH_COLD=1`） | **±8 %** | 同上 |
| 32K 冷 prefill | **結構性噪聲 ±23 %**（跨 boot 1783–2234 tok/s） | 2026-10-09 vision 對決 |
| boot-to-boot（同一設定兩次開機） | qwen38flash lane 實測 normalized **0.80–1.32** | 2026-10-21 draft 詞表 A/B |

小於噪聲底的差異**不是結果**。跨**取樣模式**（greedy／temperature／fixed-seed）或跨
**prefix-caching 狀態**的數字不可直接互比。

**Harness 對照**

| 工具 | 用途 | 關鍵旗標 |
|---|---|---|
| `scripts/bench-c.sh <C> [MAX_TOKENS]` | 併發 decode | `BENCH_IGNORE_EOS=1`（每 stream 恰好 N tok）、`BENCH_DETERMINISTIC=1`（temp 0 + seed） |
| `scripts/bench-ctx.sh <NUM_WORDS> [MAX_TOKENS]` | prefill | `max_tokens=1`＝純 prefill；`BENCH_COLD=1`＝每次加唯一 nonce（避免 prefix cache 直接命中） |
| `scripts/bench-mm.sh [NUM_IMAGES] [C] [MAX_TOKENS]` | 圖片 | `BENCH_COLD=1`；`MM_IMAGE=` 可覆寫測試圖 |
| `scripts/bench-ab.sh` / `ab-setcell.sh` / `ab-run-cell.sh` | 單旋鈕 A/B cell | 逐格套用 → 重啟 → 量測 |
| `scripts/bench-ab-deepseek.sh` | DeepSeek 全 recipe A/B | C1..C8 ×3 中位數、cold prefill、engine diag、自動 Δ |
| `scripts/bench-prefix-hit.sh` | 暖前綴命中探針 | 三輪輸出比對（`PREFIX-OK`） |
| `scripts/bench-1017.py` | 1017 兩條 lane | `prefill`／`conc`／`tools`／`soak`，輸出 JSONL 證據 |
| `scripts/bench-soak.py` | 長時間高併發 | 混短/3k/12k prompt、每 10 請求一次 exact-token probe、per-request JSONL |
| `scripts/bench-draft-vocab.py` | draft 詞表 A/B | 英文控制組、`ignore_eos`、`--reps 6`、`/metrics` acceptance 差值 |
| `scripts/bench-multiturn.sh` | 多輪穩定 | 每輪檢查 `finish=stop` 且內容非空 |

**三欄對照法**（2026-10-06 DeepSeek 舊配方）：`改動前（單次）` → `改動前 E0（中位×3）` →
`改動後（中位×3）`。只有 **E0 ↔ 改動後** 是同 harness、可直接相減；`—` 表示當時沒測。

**Σ 的定義**：八段中位數**相加**（C1…C8），不是平均。`Δ accept` 一律取**逐格 delta 的中位數**
（「差的中位數」≠「中位數的差」，兩者都對、不可混用）。

---

## 1. Lane 索引

| lane | 最新量測 | 本檔章節 | 證據 |
|---|---|---|---|
| `27b` / `35b` | 2026-09-19 | §2 | handoff 09-19 |
| `deepseek` | 2026-10-09（D0／P0） | §3 | `docs/DEEPSEEK_B12X_RECIPE_AB_2026-10-09.md`、`docs/evidence/deepseek-b12x-recipe-ab-2026-10-09/` |
| `deepseek-vision` | 2026-10-09（B1／B2） | §4 | `docs/DEEPSEEK_VISION_B12X_RECIPE_AB_2026-10-09.md`、`docs/evidence/vision-b12x-recipe-ab-2026-10-09/` |
| `deepseek-nvfp4` | 2026-10-08（Phase 3） | §5 | `docs/DEEPSEEK_NVFP4_SPECDECODE_AB_2026-10-08.md`、`docs/evidence/nvfp4-ab-2026-10-08/` |
| `qwen38flash` | 2026-09-29 | §6 | `docs/QWEN38_FLASH_NEXT_TP2_COMPOSE_2026-09-20.md`、`docs/QWEN38FLASH_DRAFT_VOCAB_AB_2026-10-21.md` |
| `qwen38flash-tensorfold` | 2026-10-22 | §7 | `docs/QWEN38FLASH_TENSORFOLD_DEPLOY_2026-10-22.md` |
| `mimo26flash` | 2026-10-03／05 | §8 | `docs/MIMO26FLASH_TP2_2026-10-03.md` |
| `dsv41flash-exl3-vllm` / `dsv41flash-tensorfold` | 2026-10-20／21 | §9 | `docs/evidence/dsv41-1017-validation-2026-10-21/` |
| 已評估不採用 | — | §10 | `docs/DSV41_FLASH_EXL3_2X_SPARK_EVAL_2026-09-29.md` |

**量測覆蓋範圍**：**10 條服務 lane ＋ 27B/35B 單節點都有完整 C1–C8**（2026-10-22 補測；§2.1、§2.2）。
三種協定**不可互比**：① `27b`/`35b`/`qwen38flash`/`qwen38flash-tensorfold`/`mimo26flash` = `ignore_eos`
400 tok、預設取樣；② 兩條 1017 = `ignore_eos` 250 tok、temp 0、thinking off；③ 2026-09-19 舊記錄 =
2048 tok、非定長。

---

## 2. `27b` / `35b` — Qwen 27B / 35B-A3B NVFP4

### 2.1 全掃（2026-10-22；`BENCH_IGNORE_EOS=1`、400 tok、warm）

| C | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 |
|---|---|---|---|---|---|---|---|---|
| 27B cluster | 41.0 | 57.2 | 82.8 | 91.1 | 101.0 | 144.2 | 131.7 | **170.3** |
| 35B cluster | 125.5 | 221.4 | 290.6 | 311.9 | 355.4 | 387.7 | 414.0 | **471.8** |
| 27B single（node0） | 22.3 | 33.3 | 45.4 | 61.2 | 59.3 | 69.1 | 76.2 | **101.2** |
| 35B single（node0） | 93.5 | 160.4 | 187.9 | 204.3 | 230.7 | 257.7 | 304.2 | **346.6** |

8/8 格 `any_errors=0`。cluster↔single 比值：27B **1.68×**、35B **1.36×**（C8）。
boot（`gb10 use`／`gb10-single use` → `/health`）：27b cluster **250 s**、single **5m43s**；
35b cluster **386 s**、single **7m06s**。C6 > C7（27B cluster）屬噪聲。
證據：node0 `~/docker-stacks/logs/{27b,35b}/bench-c-{full,single}-2026-10-22.txt`。

> 2026-09-19 的 single 量測是在 **node1** 跑的（35B），本次兩者都在 node0；同型硬體，差異應在噪聲內。
> 舊表用 `MAX_TOKENS=2048` 非定長，與上表不可直接相減。

### 2.2 首發記錄（2026-09-19；`bench-c` `MAX_TOKENS=2048`、非定長）

Image `ghcr.io/aeon-7/aeon-vllm-ultimate:2026-09-18-v0.29.0-omni`；
245k prefill 用 `bench-ctx.sh 245000 1`（`max_tokens=1` 純 prefill）。

| C | 27B single | 27B cluster | speedup | 35B single | 35B cluster | speedup |
|---|---|---|---|---|---|---|
| 1 | 23.8 | 46.1 | 1.94× | 76.2 | 120.6 | 1.58× |
| 2 | 36.6 | 76.8 | 2.10× | 115.5 | 177.4 | 1.54× |
| 3 | 54.4 | 87.9 | 1.62× | 148.2 | 218.5 | 1.47× |
| 4 | 80.3 | 105.3 | 1.31× | 198.6 | 291.6 | 1.47× |
| 8 | 117.2 | **172.7** | 1.47× | 262.7 | **416.4** | 1.59× |
| 245k prefill (tok/s) | 348.7 | 611.5 | 1.75× | 2580.1 | 3951.9 | 1.53× |

**回歸實 boot（2026-10-21，`74ca594` 之後）**：27b READY **261 s**、35b **380 s**；兩者
`gb10 smoke` HTTP 200、`bench-c 1` 0 error（27b 34.5／35b 93.9 tok/s）。

> **FlashInfer autotune cache 死鎖（已自動化）**：持久化的 `file_key` 內含 `tp_rank`/`ep_rank`/`cluster_rank`，
> 而 vLLM 只在 world rank 0 存檔再把該檔 broadcast 給所有 rank → follower 用 rank-local key 永遠 miss →
> 兩 rank 要 benchmark 的 tactic 數不同 → 每 tactic 的 `dist.all_reduce` 死鎖（rank0 高 GPU spin-wait、
> rank1 閒置、`/health` 永不 ready）。`scripts/cluster-up` 每次 boot 前呼叫 `ensure_autotune_cache_reset`；
> `AUTOTUNE_CACHE_POLICY=off` 僅供診斷。單節點 runtime 另用 `~/.cache/vllm-<profile>-single`。
>
> **27B 冷啟可達 ~40 min** → `27b.conf` 覆寫 `HEALTH_TIMEOUT=3600`
> （`docs/ISSUE_27B_BROKEN_2026-09-18_IMAGE_2026-09-19.md`）。

---

## 3. `deepseek` — DeepSeek-V4-Flash-0731 mainline

### 3.1 舊配方（官方 fp8 ＋ Anemll `dspark-vllm-gx10:0.1.1`）— **已封存**

`docs/DEEPSEEK_TUNE_AB_2026-10-06.md`（E0–E5 六格完整記錄、Winner table、Verdict）。
promote 進 `deepseek.conf` 的是 **E5**：`draft_sample_method` greedy → probabilistic、
prefix caching ON ＋ `hotfix-vllm-dspark-swa-prefix.py`（fail-closed）、
`VLLM_PREFIX_CACHE_RETENTION_INTERVAL=4096`、`EXTRA_MOUNTS` 掛 `patches/`、`SYNC_DIRS` 同步兩節點。

單格格式 `tok/s · accept %`；`Δ` 只對 **E0** 計算：

| C | 09-20 單次 | E0（10-06，中位×3） | **E5/PROD（10-07，中位×3）** | Δ vs E0 |
|---|---|---|---|---|
| 1 | 35.7 · 25.1 | 38.4 · 27.1 | **42.3 · 30.2** | +10.2 % · +3.1 pp |
| 2 | 55.7 · 29.3 | 50.3 · 25.0 | **56.9 · 30.1** | +13.1 % · +5.1 pp |
| 3 | 45.1 · 25.4 | 62.5 · 25.0 | **71.7 · 31.8** | +14.7 % · +6.8 pp |
| 4 | 55.5 · 27.1 | 67.7 · 26.3 | **79.8 · 30.2** | +17.9 % · +3.9 pp |
| 5 | — | 88.8 · 28.4 | **91.8 · 33.6** | +3.4 % · +5.2 pp |
| 6 | — | 82.5 · 28.8 | **99.3 · 31.5** | +20.4 % · +2.7 pp |
| 7 | — | 100.2 · 26.7 | **113.2 · 33.5** | +13.0 % · +6.8 pp |
| 8 | 93.1 · 28.8 | 103.8 · 28.7 | **115.7 · 30.6** | +11.5 % · +1.9 pp |
| **Σ / 中位** | 不可比 | 594.2 · 26.9 | **670.7 · 31.1** | **+12.9 % · +4.5 pp（8/8 正）** |

| cold prefill | 09-20（無 `BENCH_COLD`） | E0 | **E5/PROD** | Δ vs E0 |
|---|---|---|---|---|
| 32K | 1516.9 | 1510.1 | **1784.8** | +18.2 %（該格最吵，不算提升） |
| 131K | 1682.3 | 1907.6 | **1868.8** | −2.0 %（噪聲內） |
| 200K | 1725.0 | 1791.8 | **1747.3** | −2.5 %（噪聲內） |

暖前綴 probe：**7.6× HIT**（15.50 s → 2.03 s，2065 → 15786 tok/s）；cold prefill／啟動時間／graph pool／KV 不變。
被排除的兩個旋鈕：**E1** `CUDAGRAPH_CAPTURE` 8→128（雜訊內，且 +16 s 啟動、+1.9 GiB graph pool）、
**E4** `VLLM_USE_BREAKABLE_CUDAGRAPH=0`（−1.5 %）。

生產驗收（2026-10-07 00:18 全過）：`cluster-compose-verify` 雙 rank、`gb10 smoke`、3×3 完整性、
261K 長文（261021 tok / 1648.2 tok/s）、garble soak 3/3、`/health` 200。

### 3.2 現行配方（eugr b12x ＋ dspark-ablit）— D0／P0

`docs/DEEPSEEK_B12X_RECIPE_AB_2026-10-09.md`。配方差異：KV **fp8**、`CUDAGRAPH_CAPTURE=64`（8×8）、
batched 8192、GMU 0.85、k=7 保留、prefix caching ON **無 hotfix**。

| C | E5 記錄（舊配方） | **D0（新配方 2026-10-09）** | Δ |
|---|---|---|---|
| 1 | 42.3 | **43.2** | +2.1 % |
| 2 | 56.9 | **58.9** | +3.5 % |
| 3 | 71.7 | **72.2** | +0.7 % |
| 4 | 79.8 | **88.9** | +11.4 % |
| 5 | 91.8 | **93.2** | +1.5 % |
| 6 | 99.3 | **100.3** | +1.0 % |
| 7 | 113.2 | **116.7** | +3.1 % |
| 8 | 115.7 | **119.9** | +3.6 % |
| **Σ** | **670.7** | **693.3** | **+3.4 %（8/8 全正）** |

- acceptance：per-cell median 30.0–36.7 %，均值 **33.4 %** vs 31.1 %（**+2.3 pp**）。
- cold prefill：32K 2408.4（+35 %，結構性噪音）／131K 2174.1（+16.3 %）／200K 2042.9（+16.9 %）／
  261K **1947.1**（+18.1 %）／262K 近硬限 1951.7 過。
- 暖前綴：**HIT 38.5×**（13.60 s → 0.35 s），三輪 `PREFIX-OK` 逐字一致。
- KV pool **407,775 tok**；boot 12.8 min READY；`--load-format b12x` 無 fallback。
- **P0 生產複驗**（promoted `deepseek` 19:18 READY）：Σ **673.2 vs 670.7（+0.4 %）**、prefill 與 D0 ±0.7 %、
  prefix-hit 38.3× 逐字一致、KV 423,356 tok、全 gate 綠（C1 −12.7 % 為單流最吵格）。
- 過程兩個**假警報**（測試面，非模型）：腳本未 source `cluster-common.sh` 導致 401；verbose 列舉格式打滿 400 tok 預算。

---

## 4. `deepseek-vision` — DeepSeek-V4-Flash-Vision-EXP（2026-10-09）

`docs/DEEPSEEK_VISION_B12X_RECIPE_AB_2026-10-09.md`；`docs/evidence/vision-b12x-recipe-ab-2026-10-09/`。
Decode 為 C1…C8 ×3 中位數（`scripts/bench-ab-deepseek.sh`），`Σ` ＝ 八段中位數相加：

| C | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | Σ | accept % |
|---|---|---|---|---|---|---|---|---|---|---|
| **B1（capture 56）** | 39.7 | 43.9 | 55.7 | 69.7 | 74.9 | 74.1 | 81.2 | 96.1 | **535.3** | 25.0 |
| **B2（同設定確認）** | 34.8 | 50.1 | 60.0 | 67.3 | 70.2 | 83.7 | 86.9 | 92.9 | **545.9** | 25.4 |
| B0（上游 verbatim 48） | 31.3 | 48.9 | 55.7 | 62.5 | 76.6 | 76.7 | 72.1 | 82.3 | 506.1 | 23.7 |
| 舊配方記錄（V3 production） | 33.6 | 46.5 | 64.6 | 69.4 | 70.9 | 78.4 | 85.3 | 89.4 | 538.1 | 23.95 |
| 舊配方（V3 tune A/B） | 36.8 | 43.3 | 56.6 | 66.3 | 73.7 | 87.1 | 87.9 | 89.9 | 541.6／543.5 | 24.25／24.30 |

> B0（`CUDAGRAPH_CAPTURE=48`）Σ −6.0 %，缺口集中在 C7/C8（−15.5 %／−8.0 %）；
> 單旋鈕 48→56（＝舊配方 miaai 公式 `seqs×(k+1)`=8×7）一次修復，兩 boot 同號（散佈 2.0 %）。
> 判定 **decode 持平**（−0.5 %／+1.4 %）、accept **+1.0~1.4 pp**。

| prefill probe（`BENCH_COLD=1`） | B0／B1／B2 | 舊配方記錄 | Δ |
|---|---|---|---|
| 131K | 2005.8 / 2007.9 / 2029.5 | 1794.1（V3）／1825.3（V0） | **+9.4 ~ +13.1 %** |
| 200K | 1907.7 / 1887.2 / 1917.0 | 1772.5（V3）／1710.2（V0） | **+6.5 ~ +12.1 %** |
| 245K | 1844.8 | 1671.3 | **+10.4 %** |
| 261K | 1823.7 | 1657.7（V3） | **+10.0 %** |

| 圖片（`bench-mm`，`BENCH_COLD=1`，max_tokens 200） | 新配方 B2 | 舊配方記錄 | 說明 |
|---|---|---|---|
| 1 img C=1 | 46.6（冷）／53.9（非冷首跑，B0） | 53.1 | 非冷跑≈持平；冷跑 −11 % 是 nonce 前綴失配 |
| 4 img C=1 | 34.5 | 36.3 | 早停格（82 tok），不可比 |
| 8 img C=1 | 32.4 | 16.2 | 早停格（75 vs 200 tok），不可比 |
| 1 img C=4 | 116.0 | 111.0 | +4.5 % |
| 1 img C=8 | 135.0 | 146.1 | −7.6 %（含早停） |
| 1 img C=16 | 152.1 | 159.4 | −4.6 % |
| 4 img C=8 | 147.3 | 90.6 | 早停灌水，不可比 |

- 每張圖約 320–390 prompt tokens（checkpoint `vision_max_n_token=384`）；`--limit-mm-per-prompt {"image":8}`。
- Prefix caching（新配方，**無任何 hotfix**）：同一 32K prompt 三連發 **17.87 s → 0.35 s（50.9×）**，
  三輪輸出位元組一致（`PREFIX-OK`）、無 truncation／garble。
- 舊配方完整調優（V0–V5、V-win）見 `docs/DEEPSEEK_VISION_TUNE_AB_2026-10-07.md`（只升
  `--long-prefill-token-threshold 1024→0`，+2.6/+2.9 % decode）。

---

## 5. `deepseek-nvfp4` — 0731 NVFP4（2026-10-08 Phase 3）

`docs/DEEPSEEK_NVFP4_SPECDECODE_AB_2026-10-08.md`；`docs/evidence/nvfp4-ab-2026-10-08/`。

**Phase 3 四次 boot 的修復鏈**：

1. **boot #1 fail（io_uring/seccomp）** → 通用 `SECURITY_OPT=("seccomp=unconfined")` ＋
   `cluster-compose-verify` 的 SecurityOpt 改 subset match（`10fff38`、`2cdec55`）。
2. **boot #2 fail（b12x loader strided conversion）**：`mtp.1.ffn.experts.0.w1.scale` 嘗試 E8M0→e4m3 →
   `NotImplementedError` → 改 `--load-format safetensors`（`d2b090d`；事後證實此錯正是 #3 的另一表現）。
3. **boot #3 READY 但 acceptance 崩**（~16 tok/s、pos0 0.10）：`mtp.*` 是原生 MXFP4（int8+ue8m0 g32），
   卻被與 target 共享的 NVFP4 hf quant dict 建成 `ModelOptNvFp4FusedMoE` → scale 靜默灌進錯的 buffer →
   draft MoE 算垃圾。＝上游 `vllm-project/vllm#49133`（closed unmerged，image 只吃一半修法）。
4. **boot #4 hotfix**：`patches/eugr-spark-vllm-b12x/hotfix-dspark-draft-mxfp4.py`（fail-closed：region 恰一次、
   全檔 sha pin、原子寫入；在 draft 自己的 quant 實例上預清空 `_resolved_moe_quant_algo`）經
   `CMD_WRAPPER` ＋ `EXTRA_MOUNTS` ＋ `SYNC_DIRS` 接線 → **READY、全 gate PASS**。

`bench-c` ＋ `BENCH_IGNORE_EOS=1`（每 stream 恰 400 tok；prompt 197 tok；thinking 預設開）：

| C | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 |
|---|---|---|---|---|---|---|---|---|
| aggregate tok/s | 47.1 | 69.0 | 71.3 | 90.7 | 87.1 | 110.1 | 123.4 | **129.9** |
| accept % | 47.6 | 50.0 | 41.4 | 43.0 | 44.8 | 43.9 | 48.8 | 45.2 |
| mean accept len /5 | 2.38 | 2.50 | 2.07 | 2.15 | 2.24 | 2.19 | 2.44 | 2.26 |
| pos0 accept % | 83.8 | 79.0 | 73.8 | 79.8 | 79.6 | 77.9 | 83.0 | 79.5 |

- C1→C8 **2.76×**（Σ 728.7 tok/s），C6→C8 仍爬升；acceptance 全程 41–50 % 不隨併發崩落
  （pos0 穩 74–84 %，pos5/6 恆 0 ＝ n=5 結構上限），per-pos 遞減至 pos4 15.8–26.2 %。
- 單流對照（thinking off）：**code 66.4 tok/s／accept 78.2 %／AL 4.91**；warm prose 37.3（temp0）／36.9（temp0.7）。
  temp0 驗收 gate（pos0 ≥ 0.3）：pos0 0.629／avg 27.0 %／AL 2.35（16 → 33.6 tok/s，**+110 %**）。
- cold prefill 200K **1984.6 tok/s**（200101 tok / 100.8 s）；KV pool 344,195 tok（256K 單流 1.31×）。
- 社區對照（pnivek/vllm-dspark-nvfp4）：code 59.7／prose 38.5 tok/s（本 lane code 超越、prose 相近）。

### NVFP4 KV（`nvfp4_ds_mla`）— **負結果，已回退 fp8**

單旋鈕 B cell **決定性開機失敗**（雙 rank `EngineCore init` → `ValueError`）。三重獨立硬閘：
① DeepSeekV4 `use_fp8_ds_mla_layout=True`，resolver 只收 `fp8*`；② `b12x_mla_sparse.py`
「B12X nvfp4_ds_mla requires **GLM5Next**」；③ `flashmla_sparse.py` 需 **SM100**。
→ DeepSeekV4 on GB10 無可行路，**未有上游變更勿重試**。

---

## 6. `qwen38flash` — Qwen3.8 Flash-Next 125B NVFP4（vLLM）

### 6.1 MTP draft 詞表 A/B（2026-09-20；同機同 session，僅換 drafter 詞表）

| C | 完整 248,320 vocab | 精簡 47k | Δ |
|---|---|---|---|
| 1 | 35.7 | 40.4 | +13.2 % |
| 2 | 54.8 | 58.9 | +7.5 % |
| 3 | 82.3 | 88.2 | +7.2 % |
| 4 | 90.9 | 101.0 | +11.1 % |
| 8 | 146.5 | 156.2 | +6.6 % |

| C | 完整 accept % | 47k accept % |
|---|---|---|
| 1 | 44.5 | 47.4 |
| 2 | 49.8 | 43.0 |
| 3 | 45.3 | 42.8 |
| 4 | 44.9 | 46.5 |
| 8 | 47.4 | 45.6 |

平均 **+9.1 %**（MiaAI 量測 +9.6 %），接受率與 mean accept length 幾乎不變；精簡版另使 KV pool
33.64 → **34.01 GiB**（09-20 GMU 0.835 下）。輸出安全：落在子集外的 draft 在驗證階段被丟棄。
**上表是 09-20 量測**（GMU 0.835、prefix caching OFF），現行設定見 §6.2。

### 6.2 Decode（2026-09-29，`BENCH_IGNORE_EOS=1`，每 stream 恰 400 tok，每 C 量 10 次）

| C | knobs ON（最終設定） | knobs OFF | 09-20 基準※ |
|---|---|---|---|
| 1 | 45.5 | 46.9 | 41.7 |
| 2 | 78.6 | 73.8 | 55.3 |
| 3 | 102.7 | 101.7 | 93.7 |
| 4 | 145.9 | 117.9 | 105.0 |
| 5 | 119.5 | 140.2 | — |
| 6 | 158.6 | 165.4 | — |
| 7 | 177.2 | 167.1 | — |
| 8 | **196.8** | 180.8 | 161.1 |

※ 09-20 那欄同時差在取樣模式與 prefix caching（當時 OFF），僅供趨勢。C4/C5 兩種設定都呈雙峰，
中位數代表性有限（raw 值見 handoff）。

**可重現性**：`temperature=0` ＋ 固定 seed 只移除取樣變異；剩餘抖動來自 target forward 非逐 bit 可重現
→ spec-decode 的 accept/reject near-tie 翻轉（`vllm-project/vllm#53436`，同為 DeepSeek-V4-Flash /
Blackwell SM120 / spec decode；該報告指出 3 次重複常掩蓋抖動，需 ≥10 次）。本 repo 的 determinism knobs
自 2026-09-29 起為 profile 預設（`Q38_DET_OFF=1` 可單次關閉）。

| C | knobs OFF：tok/s CV / acc CV | knobs ON：tok/s CV / acc CV |
|---|---|---|
| 1 | 9.2 % / 19.4 % | 5.2 % / **0.0 %**（十次恆 46.9 %） |
| 2 | 12.2 % / 16.6 % | **1.1 %** / 4.9 % |
| 3 | 6.6 % / 5.4 % | 6.4 % / 7.1 % |
| 4 | 9.8 % / 8.4 % | 8.4 % / 10.7 % |
| 5 | 9.8 % / 14.3 % | 10.9 % / 11.3 % |
| 6 | 9.4 % / 7.5 % | 5.4 % / 1.7 % |
| 7 | 7.3 % / 8.9 % | 7.6 % / 9.9 % |
| 8 | 8.7 % / 11.1 % | **2.2 %** / 3.3 % |

官方 `VLLM_BATCH_INVARIANT` 這條路在 Blackwell + MXFP4 MoE 會拋 `NotImplementedError`，故這是本地唯一手段。

### 6.3 Prefill（`BENCH_COLD=1`，max_tokens=1；2026-09-29）

`BENCH_COLD=1` 每次前綴唯一 nonce，避免 prefix caching 直接從快取回答（本 lane prefix caching 已開，
且長探針天然是短探針的前綴，不除霧會嚴重虛胖）。自我檢查：32K 連兩次 **3100.5 / 3099.8 tok/s**（差 0.02 %）。

| prompt | prompt_tokens | wall (s) | prefill tok/s |
|---|---|---|---|
| 32K | 32084 | 11.52 | 2784.6 |
| 131K | 131084 | 45.94 | 2853.6 |
| 200K | 200084 | 74.13 | 2698.9 |
| 245K | 245084 | 94.53 | **2592.5** |

### 6.4 圖片與多輪（2026-09-29）

每 stream 一個唯一 nonce，否則 C 個相同請求會被 prefix cache 去重而虛胖。

| 測試 | prompt tok | wall (s) | agg tok/s |
|---|---|---|---|
| 1 img C=1 | 794 | 4.19 | 47.7 |
| 4 img C=1 | 2912 | 3.11 | 33.1 |
| 1 img C=4 | 794 × 4 | 6.33 | 126.3 |
| 1 img C=8 | 794 × 8 | 7.61 | 125.2 |

每張圖約 693 prompt tokens，全部 `any_errors=0`。09-20 的圖片表（597/768 tokens、不同圖檔）**不可直接對比**。
多輪（`scripts/bench-multiturn.sh 6 300`）：**6/6 clean turns**。`PLE_OFFLOAD=true` 對 TP2 不可行
（`Unsupported settings: nnodes=2`）。

### 6.5 語言 draft 詞表 A/B（2026-10-21）→ 預設 `zh`

`docs/QWEN38FLASH_DRAFT_VOCAB_AB_2026-10-21.md`；`docs/evidence/qwen38-draft-vocab-2026-10-21/`。
node0 兩臂各 `--reps 6`（每個 C 覆蓋 6 個 prompt，避免 C=1 永遠只打 prompt 0）：

- 中文 decode **+45~61 %**（C1 27.7 → 44.5、C8 114.4 → 165.8 tok/s），acceptance **+30 pp**（四格全正）。
- 英文控制組落在本 lane 的 boot 漂移帶內（同設定兩次開機 normalized 0.80–1.32）。
- **副產品**：第一版 harness 的「英文掉 35 %」是假訊號 —— C=1 只打 prompt 0（該 prompt 英文 acceptance
  74.8 %，其餘 4–58 %），已修為每 rep 輪換 prompt。
- 上游 TP2 原始量測（對同 boot 英文控制組正規化）：ru +53~77 %、ja +35~44 %、zh +19~39 %、
  de +31~36 %、es +19/20 %、fr +10/24 %、pt +9/16 %。輸出位元不變（子集外 draft 驗證階段被拒）。

---

## 7. `qwen38flash-tensorfold` — 同一 checkpoint，TensorFold 引擎（2026-10-22）

`docs/QWEN38FLASH_TENSORFOLD_DEPLOY_2026-10-22.md`。

### 7.1 全掃（現役 lane，`BENCH_IGNORE_EOS=1`，固定 400 tok，2026-10-22 11:20 CST）

| C | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 |
|---|---|---|---|---|---|---|---|---|
| aggregate tok/s | 55.5 | 90.6 | 129.0 | 150.9 | 176.7 | 212.6 | 246.9 | **284.4** |

8 格 `any_errors=0`（wall 7.2–11.3 s、各 400 tok）。與 00:00 的 A/B 四格（55.0 / 82.5 / 150.3 / 287.2）
相差 **+0.9 / +9.8 / +0.4 / −1.0 %**，在本 lane 的 boot 漂移帶（normalized 0.80–1.32）內。
證據：node0 `~/docker-stacks/logs/qwen38flash-tensorfold/bench-c-full-2026-10-22.txt`。

### 7.2 同 session 引擎 A/B（2026-10-22 00:00–00:20）同 session、同 payload 的引擎 A/B：

| | `qwen38flash-tensorfold`（TF） | `qwen38flash`（vLLM） | Δ |
|---|---|---|---|
| decode C1/C2/C4/C8（固定 400） | **55.0 / 82.5 / 150.3 / 287.2** | 40.6 / 42.0 / 89.5 / 157.6 | **+35.5 ~ +96.4 %** |
| cold prefill 32K/131K/261K | **3465 / 3240 / 2989** | 2770 / 2809 / 2559 | **+15 ~ +25 %** |
| cold boot → `/health` | **1 min 53 s** | 13 min 58 s | **7.4×** |

- 可變長度 decode（`BENCH_IGNORE_EOS` 未開）59.5 / 111.1 / 174.7 / 293.9（C1/2/4/8）。
- vision：`bench-mm 1 1 400` → C1 52.5／C8 230.1 tok/s、0 error；描述請求正確辨識 `carrots.jpeg`。
- 長上下文（`tools/long_context.py --max-tokens 512`）：32k/128k/256k needles **5/5 exact**、32k/128k kv **8/8**；
  256k kv 因 harness 自己把 prompt 做到 275,135 tok 被引擎**正確 400** 拒絕，改跑 240k kv
  （prompt 257,814、**8/8 exact**、prefill 91.0 s ≈ 2833 tok/s）；512k/1M 判定超出 262,144 而 skipped。
  合計 **exact 31/31（＋8/8）**。
- soak（`scripts/bench-soak.py --concurrency 8 --duration 1200 --max-tokens 512 --thinking on`）：
  **893 requests、0 errors、0 probe mismatch**、242,651 completion tok、**199.9 tok/s**、
  p50 8.31 s／p95 22.68 s；223 筆 `truncated` 全是 thinking 吃掉 512 預算（`finish_reason=length` ＋
  空 content，符合既有契約）。
- CUDA graph（`TF_FLASHNEXT_GRAPH_LOG=1`）：`graphs after 8300 captures (shared): … 8300 instantiated`、
  **0 失敗**、無 `CUDA_ERROR_NOT_PERMITTED`；統計**只出現在 rank1（node1）** 的 `docker logs qwen38-fn-tf`。
- soak 後回歸：`bench-c 8` **283.0 tok/s**（前 287.2，−1.5 % 噪聲內）、smoke 200、KV pool 33.18 GiB。
- **未驗證**：8 併發 prefill（僅單請求）、>1 h soak、1M／YaRN（刻意不啟用）。

---

## 8. `mimo26flash` — MiMo V2.6 Flash MOPD（2026-10-03／05／22）

`docs/MIMO26FLASH_TP2_2026-10-03.md`（§7 延後調優、§11 變體定案）。

### 8.1 全掃（2026-10-22，`BENCH_IGNORE_EOS=1`、400 tok、預設取樣、warm）

| C | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 |
|---|---|---|---|---|---|---|---|---|
| aggregate tok/s | 29.3 | 36.2 | 44.0 | 55.9 | 59.6 | 61.6 | 58.5 | **63.1** |

8 格 `any_errors=0`。**冷啟後第一發 C1 只有 9.1 tok/s**（JIT/compile 未熱、wall 44 s vs 熱 13.7 s），
所以上表是 warm（先丟一發 warmup）；C7 < C6 屬噪聲。與 10-03 首發記錄（21.1 / 33.9 / — / 49.1 / — / — / — / 67.9）
相比 C1 高、C8 略低，屬 lane 狀態與 warmup 差異，**不是效能變化**。
證據：node0 `~/docker-stacks/logs/mimo26flash/bench-c-full-2026-10-22{,-warm}.txt`。

### 8.2 首發記錄（2026-10-03）

| C | 1 | 2 | 4 | 8 |
|---|---|---|---|---|
| MXFP4 aggregate tok/s | 21.1 | 33.9 | 49.1 | **67.9** |

| prefill（`BENCH_COLD=1`） | 32K | 131K | 245K |
|---|---|---|---|
| tok/s | 1,553.7 | 1,015.4 | 724.3 |

### NVFP4 變體 A/B（2026-10-05，單一變量＝只 flip `BODY_REL`）

| | MXFP4 | NVFP4 | 勝方 |
|---|---|---|---|
| 冷 prefill 32K/131K/245K | 1552.8 / 1010.6 / 722.9 | **1995.0 / 1190.5 / 809.8**（+12~28 %） | NVFP4（超噪聲） |
| decode C1 / C2 | 18.1 / 33.9 | 23.3 / 37.3 | NVFP4（邊緣，範圍重疊） |
| decode C4 / C8 | 53.3 / **62.2** | 42.6 / 55.7 | MXFP4（僅 C8 超噪聲） |
| KV tokens @256K 併發 | **2,310,732 / 8.81×** | 1,366,981 / 5.21× | **MXFP4（+41 %）** |
| SHA256SUMS / 磁碟 | **有 / 177.8 GB** | 無（boot WARN）/ 198.83 GB | **MXFP4** |

**定案 MXFP4**：GB10 無原生 FP4（vLLM boot 即警告走 Marlin weight-only），NVFP4 只買到 prefill／低併發的
權重讀取優勢，卻以 41 % KV 容量與官方 QAT + `SHA256SUMS` 為代價。要回 NVFP4 只需 flip
`BODY_REL` ＋ `DISPLAY_NAME` ＋ `gb10 use`。

**DFlash cliff 探測（同日，兩變體皆過）**：Plaaasma 回報的 1024-token 滑窗 NaN cliff 在本棧無法重現
（`>1070 tok` 長生成接受率不崩、engine 0 NaN）。400-tok bench 抓不到這類問題 —— image／draft 變更後
應以 `node0:/tmp/dflash-cliff.sh` 重跑。

---

## 9. 1017 兩條 lane（`dsv41flash-exl3-vllm` / `dsv41flash-tensorfold`）

`docs/evidence/dsv41-1017-validation-2026-10-21/`（JSONL：prefill／conc／tools／soak）。

### 首次開機（2026-10-20，`dsv41flash-exl3-vllm`）

- `SPEC_METHOD` 掃描：DSpark k=3 **13.8 tok/s**（接受率 20.7 %）、k=5 **11.5**（14.5 %，
  per-pos 39.8/20.4/6.9/3.5/1.7 %）、**no-spec 24.5–24.7**；C2 聚合 36.2；冷 prefill 1,110–1,183 tok/s。
  → 定案 **`SPEC_METHOD=none`**（另已套 1017 的 MTP dense K6 修正：k=3 22.5 %、k=5 13.3 %，仍不足）。
- 加 x00byte 旋鈕後 **C1 24.2／C2 36.9／C8 79.3**；vision、600K context、prefix cache
  （同 prompt 17.62 s → 0.48 s ≈ **37×**）皆正常；首啟 ~11 分鐘。

### `dsv41flash-tensorfold`（2026-10-20／21）

- decode **C1 39.3／C2 61.7／C4 88.2／C8 120.7**（drafts off；drafts on 只有 27.5／60.8）、
  prefill 848–916 tok/s、vision ✅；`gb10 use` → READY ~6 分鐘、`cluster.py check` PASS；`restart` 327 s。
- drafter 本身正常（首 token 57.5 %、~2.1 tokens/round），但 verify 成本（1 row 22.4 ms、4 rows 46.8 ms）
  讓投機打平偏虧 → **drafts off**。

### 2026-10-22 全掃（`BENCH_IGNORE_EOS=1`、temp 0、thinking off、固定 250 tok、warm）

| C | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 |
|---|---|---|---|---|---|---|---|---|
| `dsv41flash-exl3-vllm` | 23.8 | 36.1 | 46.2 | 63.9 | 60.0 | 87.8 | 82.2 | **90.2** |
| `dsv41flash-tensorfold` | **41.9** | 64.1 | 74.7 | 109.4 | 123.4 | 137.5 | 158.4 | **158.9** |

兩條 lane 各 8 格 `any_errors=0`。同日 `gb10 use` → `/health`：exl3 **6m25s**（11:51:02→11:57:27）、
tensorfold **5m45s**（12:00:26→12:06:11）。與 2026-10-20 記錄相比：C1/C2 吻合（−1.7 %／−2.2 % 與
+6.6 %／+3.9 %），**C4/C8 偏高**（TF +24 %／+32 %）——10-20 那次沒有記錄 `ignore_eos`/`max_tokens`，
差異**不宣稱是效能變化**，需同協定複驗。證據：node0
`~/docker-stacks/logs/{dsv41flash-exl3-vllm,dsv41flash-tensorfold}/bench-c-full-2026-10-22.txt`。

### 2026-10-21 驗證（維持 262144 契約，不做 1M）

| 項目 | `dsv41flash-tensorfold` | `dsv41flash-exl3-vllm` |
|---|---|---|
| cold prefill 128K / 200K / 255K | 1,085.6 / 1,066.5 / 1,029.3 tok/s | — / — / **1,250.1** tok/s |
| 併發 32K × C4 / C8 | 147 s / 307 s，**0 error** | **111 s** / —，**0 error** |
| `json_schema` + 單一 tool-call | 20/20 + 20/20 | 10/10 + 10/10 |

---

## 10. 已評估、未採用

| 候選 | 結論 | 理由 | 文件 |
|---|---|---|---|
| DeepSeek-V4.1-Flash **EXL3**（sfxnz 2.0bpw，2× GB10） | **不採用** | 「不自行 build image」與 2.0bpw 的 42–50 tok/s 無法同時成立；TP=2 對 3.5bpw 不可行 | `docs/DSV41_FLASH_EXL3_2X_SPARK_EVAL_2026-09-29.md` |
| `deepseek-nvfp4` **NVFP4 KV**（`nvfp4_ds_mla`） | **負結果、已回退** | 三重硬閘（fp8 layout resolver／B12X 需 GLM5Next／FlashMLA 需 SM100） | §5、conf `KV_DTYPE` 註記 |
| `nvidia/…-Qwen3.8-…-FP4-Local`（QAD）於 dual 引擎 | **dual 不支援、非候選** | checkpoint 95.2 GiB／載入 ~81 GiB，設計給單顆 128 GB Spark；dual 配方 `QUANT` 只收 `nvfp4\|int4ar`、patches 只到 0009，NVFP4 的 CSF 壓縮 scale 上游 vLLM 未支援 | `docs/QWEN38FLASH_TENSORFOLD_DEPLOY_2026-10-22.md` |
| `PLE_OFFLOAD=true` | **TP2 不可行** | vLLM 直接拒絕 `nnodes=2` | §6.4 |
| 27B TP2 prefix caching | **維持 OFF** | 見 ADR；復活前需檢查 5 個上游 issue | `docs/ADR_2026-09-01_prefix_caching_dflash2.md` |

> FP4-Local 的**真正適用情境**（記錄以免重開）：要再放大 KV pool（每 rank 省 ~14 GiB ≈ +1.9M tokens）
> 或跑 1M/YaRN，且得先把 single 配方的 `patches/0011-vision-nvidia-fp4` ＋ `0012-engine-nvidia-fp4`
> 移植進 dual 引擎（等於維護 fork）→ 現階段不做。

---

## 11. 證據檔位置

| 類型 | 位置 |
|---|---|
| 逐次量測原始輸出 | `docs/evidence/<campaign>-<date>/`（`*.txt`／`*.jsonl`） |
| 節點側 log／JSONL | node0 `~/docker-stacks/logs/<profile>/`（`boot-cluster.log`、`kit.log`、`soak-*.jsonl`…） |
| 舊版 README（含 v1.x 全部表格） | `docs/_archive/README_ARCHIVE_2026-10-22.md` |
| 逐 session 驗證證據 | `handoff.md` 各章節的 Validation evidence 表 |
