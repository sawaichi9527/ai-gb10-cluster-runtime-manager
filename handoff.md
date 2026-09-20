# handoff.md — ai-gb10-cluster-runtime-manager（本機 checkout）

> 本檔是本機中繼 checkout 的交接摘要。主要開發在 **node0**（`~/workspace/ai-gb10-cluster-runtime-manager`，branch `keystone`）＋ Forgejo `829522`；本機僅作中繼存取，修改前先確認是否應改在 node0。
> 建立：2026-09-18；更新：**2026-09-20**（DeepSeek V4 Flash **Vision-Exp** lane 上線：同一顆 Anemll image + 啟動 wrapper；bench-c / bench-ctx / bench-mm 實測；`cluster-up` 新增 `SYNC_DIRS` 自動同步 patch 目錄；**vision 開 prefix caching + `dspark-swa-prefix` hotfix**、長上下文邊界 261K/262144、圖片高併發 C=8/16；本檔納入版控並同步三方）
> **2026-09-20（後續）**：**Qwen3.8 Flash-Next 125B NVFP4（TP2+EP、MTP3）上線**；同日起 **compose 為唯一啟動 lane**（移除 docker-run 分支）；**27b/35b 改走 compose**；node0 `~/docker-stacks/aeon-vllm-omni/` 清理。詳見下方「已完成（2026-09-20 後續）」。
> **2026-09-20（後續之二）**：**node-local 佈局歸位**——每個 lane 一個以 image 命名的 `~/docker-stacks/<stack>/`（`STACK_DIR`+`COMPOSE_FILE` materialize）、**cache 每 lane 獨立**（`~/.cache/vllm-<lane>[-cluster|-single]`，移除共用的 `~/.cache/huggingface` 容器掛載）、**log 統一** `~/docker-stacks/logs/<profile>/`；刪除單機 `runtimes.d/{qwen38flash,glm53flash}.conf`。詳見「已完成（2026-09-20 後續之二）」。

## 目前狀態（本機 checkout）

- 分支：`main`，HEAD = **`01870a8`**（qwen38flash MTP 詞表 A/B；本 session 共 11 個 commit `a1cba34`…`01870a8`）
- 同步狀態：**本機＝Forgejo（origin，`829522`）＝GitHub**；node0 已 pull（live lane = `qwen38flash`）
- `handoff.md` 已納版控（`37bee4c` 起；本次更新亦將 commit）
- `.gitignore` 已覆蓋 `config/cluster.env`、`state/last-runtime`、logs、`*.bak-*`

## 兩個 CLI

| CLI | 角色 |
|---|---|
| `gb10` | 叢集（TP2），thick layer over `scripts/cluster-*`；Node0 控制面，Node1 headless |
| `gb10-single` | 單節點 runtime manager；`node0` local compose，`node1` 經 `ssh -i ~/.ssh/id_gb10_cluster eye@10.0.101.102` |

## 關鍵事實（勿當 bug「修」）

- **`cluster-common.sh` 自動解析 `REPO_DIR`**，腳本可攜；保持此方式。
- **Compose＝合約，CLI＝便利層**；發展合約在 `~/docker-stacks/`。
- **Node-local 佈局**：每個 runtime 的節點側產物在 `~/docker-stacks/<stack>/`（stack 名＝image 來源）：`aeon-vllm-omni`(27b/35b)、`anemll-dspark-vllm-gx10`(deepseek)、`anemll-dspark-vllm-gx10-miaFlaver`(deepseek-vision)、`mia-vllm-openai-qwen38flashNext`(qwen38flash)。stack 內含 materialize 的 compose 與 `patches/`。**`~/` 根不得有佈署產物**。同時跑 cluster+single 的 lane（27b/35b）compose 加 `-cluster`/`-single`；cluster-only 用 `docker-compose.<profile>.yml`。
- **Cache 每 lane 獨立**：`~/.cache/vllm-<profile>`（cluster-only）或 `~/.cache/vllm-<profile>-{cluster,single}`；各 conf 的 `AUTOTUNE_CACHE_REL` 指向自己的根。**Log 統一** `~/docker-stacks/logs/<profile>/`（boot + compose/container）。
- **統一 AEON stack**：`~/docker-stacks/aeon-vllm-omni/`（`docker-compose-27b-single.yml` + `docker-compose-35b-single.yml` + `docker-compose-{27b,35b}-cluster.yml` + `models/` + `*_029_patched.py`）；27b/35b 皆 v0.29.0-omni image。`aeon-vllm-reasoning-eos` 已退休。
- **Profiles 資料驅動**：`cluster-profiles.d/`（27b / 35b / deepseek / **deepseek-vision** / **qwen38flash**），由 `cluster-common.sh` 載入；勿在 `cluster-*` 重寫死 profile 資料。
- **統一 LLM endpoint**：所有 runtime 走 OpenAI API **port 1234**，共用一組 `VLLM_API_KEY`。TP2 與 node0 single 共用 port → **互斥**（`gb10 use` 釋放 singles；`gb10-single use/start` 先拆 TP2）。
- **Lazy sudo**：`sudo_pass()` 重用 `SUDO_PASS`，無 prompt；unset 時互動或報錯，不 hang。
- **Placeholder**：`PLACEHOLDER=true` 的 conf 只印 "not deployed yet"。
- **Exclusive groups**：`runtimes.d/*.conf` 用 `MODE=exclusive` + `GROUP`（llm/image/video）；`use` 在同 group 內切換；`start` 對 exclusive 等同 `use`。
- **DeepSeek 僅叢集**：single `deepseek.conf` 已退休；`cluster-profiles.d/deepseek.conf` 為主線（official fp8 checkpoint + `ghcr.io/anemll/dspark-vllm-gx10:0.1.1`，pool 權重）。
- **`deepseek` 與 `deepseek-vision` 共用同一顆 image**（Anemll `dspark-vllm-gx10:0.1.1`，digest `a8394849…`），互斥切換；vision 支援來自**啟動 wrapper**（見下節）。
- **新增（2026-09-20）兩個預設關閉的 profile hook，勿以為沒用**：
  - `CMD_WRAPPER`（`_compose_service`）：設定時改以 `entrypoint: []` + `bash -lc "<wrapper>; exec vllm serve <args>"` 啟動；未設＝輸出 **byte 不變**。
  - `SYNC_DIRS`（`cluster-up`，`"SRC:DEST"`）：boot 前把 SRC（Node0，repo）佈署到兩節點 DEST；未設＝no-op。
- **Cold start** TP2 約 7–15 min（vision 類似）；`cluster-up`/`gb10 use` 等到 `/health` 200 才報 READY。
- **TP2 27B prefix caching 刻意關閉**（見 `docs/ADR_2026-09-01_prefix_caching_dflash2.md`）。35b 已啟用 prefix caching（`a5fcc54`）。
- **ComfyUI** 部署在 Node1 為 `comfyui-aeon` / Flux 2 Dev；不回退 `comfyui-personal`/`comfyui-work`。

## 2026-09-20 — DeepSeek V4 Flash Vision-Exp lane 上線（本次重點）

### 結論
Vision-Exp（多模態）已用**與 mainline deepseek 完全相同**的 image 在 GB10 TP2 跑起來；文字與圖片輸入皆正常，並完成 benchmark。

### 為什麼先前的官方路線失敗
- 先前用官方通用 image `vllm/vllm-openai:deepseekv4-flash-vision`（PR #54566）在 GB10 **engine init 失敗**：
  1. `enable_adaptive_verification=true` 與 `DeepseekV4IndexerBackend` 衝突（已改 false）。
  2. 硬限制：`Unsupported sparse-MLA prefill configuration`（`index_topk=512`）。GB10/sm_12 上唯一可用的 DSV4 sparse-MLA 後端＝FlashInfer SM120，其 prefill kernel 不支援此 config；FlashMLA DSV4 後端只支援 major 9/10（不含 sm_12）。
- 正解：用 **GB10 原生 b12x image＝Anemll `dspark-vllm-gx10:0.1.1`**（與 deepseek 同顆）＋ **啟動時套 MiaAI-Lab 的 vision hotfix**。

### 機制（MiaAI-Lab 配方，已內化到本 repo）
- `cluster-profiles.d/deepseek-vision.conf`：
  - `IMAGE="ghcr.io/anemll/dspark-vllm-gx10:0.1.1"`、`IMG_SHA256` 同 deepseek。
  - `BODY_REL="deepseek-v4-flash-vision-exp"`（`.hf_revision=6821d6ad3681a4b137b066b76094fa82ebd0a380`）。
  - `CMD_WRAPPER`：先 `cp /model/encoding/encoding_dsv4.py → vllm/tokenizers/deepseek_v4_encoding.py`，再套 17 個 hotfix（含 `hotfix-dsv4-vision-exp.py`＝ViT/Aligner + `image_url`），最後 `exec /usr/local/bin/vllm serve …`（args 由共用 `build_vllm_args` 產生）。
  - `SYNC_DIRS=("${REPO_DIR}/patches/dspark-vision:${STACK_DIR}/patches")` → 每次 boot 自動佈署到兩節點（`STACK_DIR=~/docker-stacks/anemll-dspark-vllm-gx10-miaFlaver`）。
- **Patches vendored**：`patches/dspark-vision/`（17 patch + `vision_exp/` + `NOTICE.md`），來自 MiaAI-Lab `DeepSeek-v4-Flash-DSpark-2x-DGX-Spark` @ `97e8733238f81f5fdc44b241f8996a7858825744`，MIT，**LF**（Windows clone 會轉 CRLF，需 `-c core.autocrlf=false`）。
- 啟動參數：`nvfp4_ds_mla` KV、`flashinfer_b12x` MoE、DSpark `k=6 probabilistic`、`MAXLEN=262144`、`NUMSEQ=8`、`BATCHED=16384`、`GMU=0.80`、`CUDAGRAPH_CAPTURE=56`、**prefix caching ON（搭 `dspark-swa-prefix` hotfix + `VLLM_PREFIX_CACHE_RETENTION_INTERVAL=4096`）**、`VLLM_USE_BREAKABLE_CUDAGRAPH=0`、`--limit-mm-per-prompt {"image":8}`、`--long-prefill-token-threshold 1024`、`--generation-config vllm`、reasoning/tool parser `deepseek_v4`。

### 權重版本釐清（重要）
- MiaAI 釘 `86f746b36186f0e567729a5c06a8c918caba82a9`；本機/節點是 `6821d6ad3681a4b137b066b76094fa82ebd0a380`（= HF main HEAD）。
- 兩者差異**僅 README/.eval_results**；**48 shards + config.json + tokenizer + encoding/ + inference/ 全部 byte-identical** → **不需重下載**。

### 零污染保證（deepseek 未受影響）
- `cluster-profiles.d/deepseek.conf`、`bin/gb10` 未動；`CMD_WRAPPER`/`SYNC_DIRS` 未設時**渲染／行為完全不變**（已用 HEAD 版 `cluster-common.sh` 對現版渲染 deepseek，**逐 byte 相同**）。
- 共用 `/cache/huggingface/vllm-cache` 的 compile cache；`cluster-up` 每次 boot 都清 FlashInfer autotune cache，且 vLLM 快取以 model/config 為 key。

### Benchmark（2026-09-20，同一 session、同一台 TP2）
`bench-c.sh`（MAX_TOKENS=400）：

| C | Vision-Exp tok/s (accept) | 0731 mainline tok/s (accept) |
|---|---|---|
| 1 | 36.7 (29.9%) | 35.7 (25.1%) |
| 2 | 48.8 (29.6%) | 55.7 (29.3%) |
| 3 | 58.0 (32.5%) | 45.1 (25.4%) |
| 4 | 67.3 (30.9%) | 55.5 (27.1%) |
| 8 | 73.4 (30.1%) | 93.1 (28.8%) |

`bench-ctx.sh`（max_tokens=1，純 prefill）：

| prompt | Vision-Exp tok/s | 0731 tok/s |
|---|---|---|
| 32K | 1941.0 | 1516.9 |
| 131K | 1825.3 | 1682.3 |
| 200K | 1710.2 | 1725.0 |
| 245K | 1671.3 | — |
| 260K | 1638.0 | — |
| 261K | 1803.9 | — |
| 262144 | **400 錯誤**（超上限） | — |

`bench-mm.sh`（新增，圖片；max_tokens=200）：

| 測試 | prompt tok | wall (s) | agg tok/s |
|---|---|---|---|
| 1 img, C=1 | 407 | 3.76 | 53.1 |
| 4 img, C=1 | 1346 | 5.51 | 36.3 |
| 8 img, C=1 | 2598 | 12.37 | 16.2 |
| 1 img, C=4 | 407 ×4 | 7.21 | 111.0 |
| 1 img, C=8 | 407 ×8 | 10.95 | 146.1 |
| 1 img, C=16 | 407 ×16 | 20.08 | 159.4 |
| 4 img, C=8 | 1346 ×8 | 16.31 | 90.6 |

- 全部 `any_errors=0`。每張圖約 320–390 prompt tokens（`vision_max_n_token=384`）。
- KV pool：vision **381,364** tokens @ 262144（1.45x）；0731 **405,179**（1.55x）——差異來自 ViT encoder 佔權重記憶體。
- **Prefix caching 實測**：同一 32K prompt 連兩次 → prefill **16.95s → 2.30s（1938 → 14314 tok/s，~7.4×）**；重複同 prompt 三次輸出皆完整（無 DSpark 退化 → `dspark-swa-prefix` hotfix 生效）。
- **長上下文邊界**：261K 可用（1803.9 tok/s）；**262144-word（= 上限）被拒**（`maximum context length is 262144`，prompt 262144 + 1 output > 262144）→ 實用上限 prompt ≤ **262143** tokens。

### 本次 commits（Forgejo `origin/main`）
`c87f907` vision lane（placeholder 骨架）→ `ced0e47` unlock → `f72786f` list 標記 → `0ecfa23` 關 adaptive verification → **`9305034` 改用同一 Anemll image + `CMD_WRAPPER`** → `e2d162f` vendor patches → `63c3ca6` mount 改節點本地路徑 → `44ef532` README（vision 結果）→ **`5e36955` `SYNC_DIRS`** → `f4c4a15` `bench-mm.sh` → `3f73933` bench-mm fix → **`c76c93e` README 補 245K/260K + 圖片** → `37bee4c` handoff.md 納版控（並同步 GitHub）→ **`7b6be60` vision 開 prefix caching + vendor `dspark-swa-prefix` hotfix**

## 近期主線（較早）

- `99181d3` **cluster-up**：每次 TP2 boot 前無條件清兩節點 FlashInfer autotune cache（rank-keyed；`ensure_autotune_cache_reset`，policy `clear`(預設)`|off`）
- `5c1f240` cluster-up 初版 `ensure_autotune_cache_symmetry`（後被 `99181d3` 取代）+ 單節點 cache 隔離守門
- `2075ae1` docs(readme)：35B 09-18 re-bench + 修 245k prefill 假數據 `180398.5`→`3951.9`
- `38f7b9a` docs(readme)：27B 09-18 re-bench + 移除 BROKEN 標記
- `78c5ff7` docs：27B TP2 on 09-18 image **RESOLVED**（冷啟超過硬編碼 2400s health timeout）
- `4c6b1a2` cluster-up：health timeout 可被 profile 覆寫（`HEALTH_TIMEOUT`）；27b=3600s
- `b1595ad` docs(readme)：35B cluster 09-18 image 重測 + 27B BROKEN flag
- `b7e2d7b` 三方 main 對齊（tree 等同 `ffd02ea`）
- `cc491a9` stale checkout 部署防呆（git drift guard）
- `ffd02ea` README：deployed services + latest-image benchmark tables
- `4232a89` 27b/35b 統一 stack 目錄 `aeon-vllm-omni` + 修 35b v0.29 env
- `b97a9c8` 升級 v0.29.0-omni image（27b cluster+single C1-8 + 245k ctx benchmark）
- `87f59a9` 背景 boot 預設（boot-*.pid / boot-ready.* markers）
- `496c9b1` keystone 併入 main
- `a5fcc54` 35b NSPEC 11→6 + 啟用 TP2 prefix caching
- `2c70316` 35b KV_DTYPE bfloat16 + flash_attn + `VLLM_TEST_FORCE_FP8_MARLIN=1`
- `bc74288` 27b ModelOpt MIXED 硬規則
- `55b6c7f` 27b body → mixed（nvfp4-mixed）

## Profile 現況

| Profile | body | drafter | image | 備註 |
|---|---|---|---|---|
| 27b | `qwen3.8-27b-aeon-ultimate-uncensored-nvfp4-mixed` | `qwen3.8-27b-dflash2` | `2026-09-18-v0.29.0-omni` | dflash n=7, maxlen 262144, GMU 0.85, num_seqs 8, :1234；prefix cache OFF；`HEALTH_TIMEOUT=3600` |
| 35b | `qwen3.6-35b-a3b-heretic-nvfp4` | `qwen3.6-35b-a3b-dflash` | `2026-09-18-v0.29.0-omni` | n=6, maxlen 262144, GMU 0.80, num_seqs 8；prefix cache ON |
| deepseek | `deepseek-v4-flash-0731-official` | — (內建 DSpark n=7) | `anemll/dspark-vllm-gx10:0.1.1` | 主線；池化權重；262144/8；nvfp4_ds_mla + flashinfer_b12x |
| **deepseek-vision** | `deepseek-v4-flash-vision-exp` | — (內建 DSpark k=6) | **同上（同 image/digest）** | 多模態；`CMD_WRAPPER` 裝 encoder+hotfix；262144/8；`SYNC_DIRS` 佈署 patches |

### 09-18 image benchmark（`bench-c` C1-C8 tok/s；245k 純 prefill）

| Profile | | C1 | C2 | C3 | C4 | C8 | 245k prefill |
|---|---|---|---|---|---|---|---|
| 27b | single | 23.8 | 36.6 | 54.4 | 80.3 | 117.2 | 348.7 |
| 27b | cluster | 46.1 | 76.8 | 87.9 | 105.3 | 172.7 | 611.5 |
| 35b | single | 76.2 | 115.5 | 148.2 | 198.6 | 262.7 | 2580.1 |
| 35b | cluster | 120.6 | 177.4 | 218.5 | 291.6 | 416.4 | 3951.9 |

## 分支

- `docs-carrier-9041`（HEAD `a83188e`）：無共同祖先的舊歷史線，非殘留物，勿刪。
- `experiment/deepseek-v4-dspark-k5-r2`（`88e5b3e`，origin behind 5）
- `feature/tp2-qwen38flash-next`（`1dc122c`）
- `image-workstream/dspark-k5-topk256-backport`（`e2fe3a9`）
- `master` / `transport-docs-1634`（`5de82c2`）

## 現役狀態（session 結束時）

- 現役＝**deepseek-vision（READY, :1234）**（本次 benchmark 後未切回；`gb10 use deepseek` 可切回 mainline）。
- 節點：node0＝`spark-25d5`（rank0/API），node1＝`spark-8095`（rank1/headless）。

## 下一步（建議）

- ~~**GitHub remote 未推**~~（已完成 2026-09-20：三方已同步 `fd9adf2`，`ls-remote` 驗證）。
- ~~**`handoff.md` 未追蹤**~~（已完成：已納版控，見「目前狀態」）。
- **驗證 27b/35b 未受影響**（暫緩，見「定期檢討追蹤」#3）：本次改了共用 `cluster-common.sh`（`CMD_WRAPPER`/`SYNC_DIRS` 加入 unset 清單）與 `cluster-up`（新增 `SYNC_DIRS` 區塊，預設 no-op）。已驗證 deepseek 渲染 byte-identical，但**尚未再 boot 27b/35b 實測**（低風險，兩者走 docker-run 路徑）。
- （可選）長圖文混搭、`--limit-mm-per-prompt` 上限（目前 8）、多輪 agent chain 長時間穩定性（見「定期檢討追蹤」#2）。
- **benchmark 工具**：`scripts/bench-c.sh <C> [MAX_TOKENS]`（C=1 時 exit 1 為邊緣狀況，數值仍有效）、`scripts/bench-ctx.sh <NUM_WORDS> [MAX_TOKENS]`（`max_tokens=1`＝純 prefill）、**`scripts/bench-mm.sh [NUM_IMAGES] [C] [MAX_TOKENS]`（圖片；預設用 deepseek-vision profile 的測試圖，可用 `MM_IMAGE=` 覆寫）**。
- 若有跨節點／部署問題，先在 node0 確認，勿在本機直接改。
- 修改前查 `git rev-parse --show-toplevel` 確認 repo 邊界；本機變更要推回 Forgejo 才有意義。

### 已完成（2026-09-20）

- **Vision 調校**：prefix caching 已開啟並套 `dspark-swa-prefix` hotfix（`7b6be60`）；同一 32K prompt 重複請求 prefill 16.95s→2.30s（~7.4×），重複同 prompt 輸出完整（無退化）。
- **Vision 進一步 benchmark**：長上下文邊界（261K 可用 1803.9 tok/s；262144 被拒 → 實用上限 prompt ≤ 262143）、圖片 C=8（146.1）/C=16（159.4）/4 圖 C=8（90.6）tok/s。

### 已完成（2026-09-20 後續）

- **Qwen3.8 Flash-Next 125B NVFP4（TP2+EP、MTP3）上線**（`qwen38flash.conf`）：官方
  `vllm/vllm-openai:qwen38-flash-next` image（pin `IMG_SHA256`）、ModelOpt NVFP4 125B
  checkpoint（本機 10-shard repack + `model-fp8-mtp-ple.safetensors`）、`fp8_e4m3` KV、
  `bfloat16` SSM、`--compilation-config {"mode":0}`（eager）、GMU 0.835、batched 8192。
  MiaAI-Lab 的 6 個 runtime patcher vendored 於 `patches/qwen38flash/`（AGPL-3.0，NOTICE 有
  sha256），由 `CMD_WRAPPER` 在容器內就地套用（不重建 image）；MTP 層索引別名由 `prepare.sh`
  產生後唯讀掛載。實測：`/health` 200、`cluster-compose-verify` 兩 rank PASS、smoke OK、
  KV pool 34.01 GiB / 4,245,234 tokens。
- **MTP draft 詞表 A/B**：精簡 47k vs 完整 248,320，五個 C 全部較快（中位數 40.4/58.9/88.2/
  101.0/156.2 vs 35.7/54.8/82.3/90.9/146.5，**平均 +9.1%**），接受率幾乎不變；lane 已預設 47k。
- **單一 compose lane**：`scripts/cluster-up` 移除 docker-run 分支；27b/35b 加
  `LAUNCH_STYLE="compose"`；`cluster-compose-verify` 支援 `CMD_WRAPPER`。loader 新增 3 個通用欄位
  `COMPILATION_JSON` / `CAP_ADD` / `ULIMITS`（未設＝不變）與 profile 可宣告的 `AUTOTUNE_CACHE_REL`。
- **node0 清理**：`~/docker-stacks/aeon-vllm-omni/` 的 3 個 compose 備份 + 3 個孤兒 `*_029_patched.py`
  移入 `~/.archieve/aeon-vllm-omni-cleanup-20260920/`；刪除可再生的 `*_029_orig.py`。

### 已完成（2026-09-20 後續之二）— node-local 佈局歸位

- **Stack dir（image 命名）**：`cluster-profiles.d/*.conf` 新增 `STACK_DIR` + `COMPOSE_FILE`（loader
  解析；未設＝沿用 `mktemp`）。`cluster-up` 把 render 產物 materialize 到 `<STACK_DIR>/<COMPOSE_FILE>`
  （兩節點同路徑，仍每次 render＝零漂移）。單機 `runtimes.d` 的 `COMPOSE_FILE` 同步改為
  `docker-compose-{27b,35b}-single.yml`。
- **Cache 每 lane 獨立**：移除共用的 `~/.cache/huggingface` 容器掛載；改用
  `~/.cache/vllm-<lane>`（cluster-only）或 `-{cluster,single}`（27b/35b），並在容器內掛到
  `/cache/vllm` + `VLLM_CACHE_ROOT=/cache/vllm`（deepseek/vision 的 `FLASHINFER_WORKSPACE_BASE`、
  vision 的 `TILELANG/TRITON/B12X` 一併改）。各 conf 的 `AUTOTUNE_CACHE_REL` 指向自己的根。
- **Log 統一**：`bin/gb10`、`bin/gb10-single`、`cluster-up` 的 boot/compose log 由 repo `state/`
  與 `/tmp` 改到 `~/docker-stacks/logs/<profile>/`。
- **刪除**：`runtimes.d/qwen38flash.conf`、`runtimes.d/glm53flash.conf`（不可能跑單機）；
  `gb10-single` usage 同步更新。另修正 `gb10-single-boot` 的 cache 隔離 guard（改比對
  `.cache/vllm-<lane>-cluster`）與兩處引用不存在函式 `ensure_autotune_cache_symmetry` 的註解。
- **node0/node1 歸位**：`~/qwen38flash-patches/` → `.../mia-vllm-openai-qwen38flashNext/patches/`；
  `~/dspark-vision-patches/` → `.../anemll-dspark-vllm-gx10-miaFlaver/patches/`；
  `~/dspark-vision-poc/`、`~/logs/`、`~/.archieve/` 併入 `~/_archieve/`。

## 定期檢討追蹤

> 下列事項不是「待辦」，而是**定期檢討**項目（2026-09-20 標註）。檢討時點：每當 `patches/` 上游或 image 更新，或每次進行 27b/35b 重大變更時。

1. **Patches 上游追蹤**：`patches/dspark-vision/` pin 在 MiaAI commit `97e8733…`；`patches/qwen38flash/` pin 在 `d2f54b7…`（皆見各自 `NOTICE.md`）。上游更新時需 **re-vendor** 並重新比對 byte。
2. **Vision 進一步驗證（可選）**：長圖文混搭 prompt、`--limit-mm-per-prompt` 上限（目前 8）的邊界行為、多輪 agent chain 長時間穩定性。
3. **27b/35b 共用層回歸**：`cluster-common.sh`（`CMD_WRAPPER`/`SYNC_DIRS`/`_yaml_dq` 的 `$$` 逃逸/`AUTOTUNE_CACHE_REL`）與 `cluster-up`（移除 docker-run、`SYNC_DIRS` 區塊）改動後，**尚未 boot 27b/35b 實測**（渲染已驗證 byte-identical；`$$` 逃逸對 27b/35b/deepseek 無 `$` 故無影響，但 **deepseek-vision 的 CMD_WRAPPER 渲染確實改變**——其 `${PATH}` 等由 host 取代改為容器內展開，需在下次 vision boot 時確認行為）。
4. **bench-c 方法論（可選）**：`max_tokens=400` 會提前停止，單次數字變異大。若要更嚴謹可加 `ignore_eos` 固定長度。
5. **qwen38flash 未測項（可選）**：`bench-ctx` 長上下文 prefill 曲線、`--limit-mm-per-prompt`／圖片輸入（`mm-encoder-tp-mode data`）、多輪穩定性、`PLE_OFFLOAD=true` 變體（需 `ULIMITS=(nofile=…)`）。
