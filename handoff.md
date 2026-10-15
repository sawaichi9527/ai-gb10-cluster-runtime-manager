# handoff.md — ai-gb10-cluster-runtime-manager（本機 checkout）

> 本檔是本機中繼 checkout 的交接摘要。主要開發在 **node0**（`~/workspace/ai-gb10-cluster-runtime-manager`，branch **`main`**；2026-09-29 實測 node0 為 `main`／upstream `origin/main`、工作區乾淨 —— 舊文件寫的 `keystone` 已於 `496c9b1` 併入 main、**非**現役 checkout）＋ Forgejo `829522`；本機僅作中繼存取，修改前先確認是否應改在 node0。
> 建立：2026-09-18；更新：**2026-09-20**（DeepSeek V4 Flash **Vision-Exp** lane 上線：同一顆 Anemll image + 啟動 wrapper；bench-c / bench-ctx / bench-mm 實測；`cluster-up` 新增 `SYNC_DIRS` 自動同步 patch 目錄；**vision 開 prefix caching + `dspark-swa-prefix` hotfix**、長上下文邊界 261K/262144、圖片高併發 C=8/16；本檔納入版控並同步三方）；**2026-09-29** 上游查核（Anemll 無新 image/tag、MiaAI-Lab main 未動且 23 檔 byte 全同）→ 見「定期檢討追蹤」；**2026-09-29（後續）** qwen38flash 對齊上游 `2c86a1d0`（GMU 0.80／prefix caching ON／block-drop backport／index share）並完成冷啟驗證（READY、KV 29.88 GiB、無回歸）→ 見「qwen38flash 對齊上游 + 冷啟驗證」；**2026-09-29（後續之二）** DeepSeek-V4.1-Flash **EXL3 2×GB10 選型查核**（取得兩顆可下載 arm64 image 的 digest、證實 sfxnz image 未發佈、TP=2 對 3.5bpw 不可行、各線 benchmark 與 NVIDIA 論壇口碑）→ **本輪不新增 lane**（維持 `deepseek-vision` 為 2-Spark 多模態），詳見 `docs/DSV41_FLASH_EXL3_2X_SPARK_EVAL_2026-09-29.md`；**2026-09-30** 上游再查核（deepseek 與 deepseek-vision 的 **image／配方／官方權重皆無更新** → 兩 lane 現行設定即為最新、無需變更，含首度補查官方權重 commit 比較，見 `docs/DEEPSEEK_UPSTREAM_REVERIFY_2026-09-30.md`）；**2026-09-30（續）** 27b／35b 上游再查核（兩 lane 共用的 `ghcr.io/aeon-7/aeon-vllm-ultimate` 最新 dated tag 仍 `2026-09-18-v0.29.0-omni`＝現行 pin、digest 不變；27B/35B 四個 HF 來源 body/drafter 最後 commit 為 09-18／08-19／07-15／06-28，**皆無 09-19 後更新** → 無需變更，見 `docs/QWEN_27B_35B_UPSTREAM_REVERIFY_2026-09-30.md`）；**2026-10-03** `mimo26flash` lane 上線（MiMo V2.6 Flash MOPD，TP2 vLLM+DFlash，見同名章節）；**2026-10-05** `mimo26flash` NVFP4 變體 A/B + DFlash cliff 探測（兩變體皆過）→ **定案 MXFP4**、延後調優 C/D/E 註記於 docs §7、**服務切回 `deepseek`**、README 同步 → 見「2026-10-05」章節；**2026-10-07** DeepSeek **V4 Flash Vision** 同 image 調優 A/B（V0–V5 + V-win，獨立 `deepseek-vision-tune` lane）→ **只升一個旋鈕 `--long-prefill-token-threshold 1024→0`（V3）**，`deepseek.conf` 全程未動、生產 gate 全過；記錄 production lane boot 散佈 8.1% 無法驗證 2.7% 效應、cold prefill 32K 判為噪聲、garble soak `thinking:true` false alarm → 見「2026-10-07 — DeepSeek V4 Flash Vision」章節；**2026-10-07（續）** `deepseek-nvfp4` lane **建置**（NVIDIA NVFP4 0731 checkpoint + `eugr/spark-vllm-b12x`，Phase 1–2：下載/傳輸 + profile/白名單/文件，**Phase 3 開機另排**）→ 見「2026-10-07 — deepseek-nvfp4 lane 建置」章節；**2026-10-08（續）** `deepseek-nvfp4` **Phase 3 完成**（boot ×4：seccomp/safetensors 兩個啟動修復 → DSpark acceptance 垃圾 draft 根因＝共享 NVFP4 quant dict 把原生 MXFP4 draft 建成 ModelOptNvFp4（上游 #49133 closed）→ `hotfix-dspark-draft-mxfp4` 容器啟動補丁 → **全 gate PASS**：acceptance 2%→**27%**（temp0，pos0 0.629）／**49–59%**（temp0.7）、單流 16→**33.6 tok/s**、prefix-hit 44.8×、garble 3/3、compose-verify 過）→ 見同章節「Phase 3」；**2026-10-08（三）** C1–C8 完整併發 benchmark（47.1→**129.9 tok/s**、**2.76×**、accept 41–50% 全程不崩）+ `bench-c.sh` metrics scrape auth 修正（`/metrics` 401）、**NVFP4 KV（`nvfp4_ds_mla`）A/B 負結果**（三重硬閘、回退 fp8）→ README「已部署服務」正式列入 `deepseek-nvfp4`（**現役**）+ benchmark 區塊重寫，tag **`v1.5.0`** → 見 Phase 3 第 6/7 項與「版本標記」
> **2026-10-14**：**`comfyui-jdaln` 上線（Node1 唯一 ComfyUI runtime）** —— clone `ef7a677b`、建置 144 s、`:8188` 200、ComfyUI 0.38.0、2812 node types；過程中修掉 **17.5 h 掛死**（404 的 `ComfyUI-VDN-H3` clone 卡 credential prompt）與 **`gb10-single-boot` 假 READY**（commit `537c64e`），並依使用者裁定**裁剪 asset 範圍**（allowlist 置空：預設 93 GiB + workflow-asset 階段 +174 GiB 起跳 → 只保留 `z-image-turbo-core`，`use`→READY 46 秒）。詳見 `docs/COMFYUI_JDALN_DEPLOYMENT_2026-10-14.md`。
> **2026-10-14（續）**：**兩條 Node1 runtime 同日退役**（使用者裁定）—— ① `comfyui`／aeon：HF token 先搬至 `~/docker-stacks/config/hf_token` 再刪 stack（71 GB）+ image（26.7 GB），flux2 權重**無備份**；② `minimaxh3`：**先驗證後拆** —— jdaln 的原生 MiniMax H3 節點跑通 i2v（`prompt_id d91692b7`、`status=success`、204.5 s、產出合法 MP4）才拆 stack（135 GB）+ image（32 GB）+ 輸出目錄；repo 側 `git rm` 兩個 conf 與 `src/minimax-h3/`（45 檔）；③ **同日稍後追加：`minimax-h3-sglang` 也一併清除**（依使用者追加指示）—— 目錄 **56 GB**（全在 `models/quantized`）+ 2 個 image **≈105 GB**，各 `Untagged`+`Deleted` rc=0，image 總數 11→9；其 `FAILURE_ANALYSIS.md` 內容已於刪除前擷取、留存於下方「`FAILURE_ANALYSIS.md` 原文留存」。三者合計磁碟 `used 2.1T→1.8T`、`avail 1.5T→1.8T`、59%→51%。詳見 `docs/COMFYUI_JDALN_DEPLOYMENT_2026-10-14.md` §11–§12。④ **同日再追加（續二）**：盤點發現退役只做一半 —— Node0 還留著 `minimax-h3` 135 GB + `comfyui-aeon` 54 GB + image 16.8 GB（~204 GB），已全數清除；並依使用者指示「經 CX7 用 rsync」把 `comfyui-jdaln` 鏡像到 Node0（stack 124 GB／114,316 檔 rsync 335 s ~396 MB/s，image `docker save|load` 128 s，**byte 驗證通過**；Node0 端**未實測 boot**）→ 見「2026-10-14（續二）」。
> **2026-10-09**：`deepseek-vision` **配方繼承（promote）**——對決 `eugr/spark-vllm-b12x:latest` + `deepseek-v4-flash-vision-exp-ablit`（候選 lane `deepseek-vision-b12x`，B0/B1/B2 三 boot）vs README 舊配方記錄：decode Σ 535.3/545.9 vs 538.1（−0.5%/+1.4%，持平）、prefill 131K–261K 全欄 **+9~14%**、accept +1pp、prefix-hit 正確性 gate **無需任何 hotfix 即過**（HIT 50.9×、輸出位元組一致）→ 條件成立。**唯一升版旋鈕 `CUDAGRAPH_CAPTURE 48→56`**（上游 verbatim 48 於 C7/C8 掉 capture range，Σ −6%）。新 `deepseek-vision.conf` 已改寫（原生 vision、無 `CMD_WRAPPER`/`SYNC_DIRS`）；舊 Anemll 配方 byte-identical 封存於 `_overdue_recipe/deepseek-vision_anemll-dspark-vllm-gx10-011_20261009/`（conf+compose+patches+`recipe_README.md` 自帶、含還原步驟）；**舊官方模型 `models/deepseek-v4-flash-vision-exp` 依使用者決定兩節點暫留、後續再議**。詳見 `docs/DEEPSEEK_VISION_B12X_RECIPE_AB_2026-10-09.md`。另依使用者決定，舊配方的 A/B lane `deepseek-vision-tune{,.conf.base}` 同日**歸檔**至同一 `_overdue_recipe/` 目錄（白名單移除；未來 vision 調優需從新配方另立 lane）。
> **2026-10-09（續）**：`deepseek`（mainline）**配方繼承（promote）**——對決 `eugr/spark-vllm-b12x:latest` + `deepseek-v4-flash-0731-dspark-ablit`（drowzeys Anchored-Tensors；候選 lane `deepseek-b12x`，D0 單 boot）vs README E5 記錄：decode Σ **693.3 vs 670.7（+3.4%，8/8 格全正）**、prefill 131K–261K **+16~18%**、accept **+2.3pp（33.4%）**、prefix-hit 正確性 gate **無需任何 hotfix 即過**（HIT 38.5×、輸出逐字一致）、soak（3×3 完整性、garble 3/3、262K 近硬限、health 200）全過 → 條件成立。配方差異：KV fp8（nvfp4_ds_mla 此 image 不可行）、**capture 64**（公式 8×(k+1) 配保留的 k=7；上游 48 是配 k=5）、batched 8192、GMU 0.85、無 `CMD_WRAPPER`/`SYNC_DIRS`/patches。新 `deepseek.conf` 已改寫；舊 Anemll 配方 byte-identical 封存於 `_overdue_recipe/deepseek_anemll-dspark-vllm-gx10-011_20261009/`（`deepseek-anemll.conf` SHA256 `3147b4e9…` + compose + patches + `recipe_README.md` 自帶、含還原步驟）；**舊官方模型 `models/deepseek-v4-flash-0731-official` 依使用者裁定兩節點暫留、後續再議**。候選 lane `deepseek-b12x.conf` 已刪、白名單還原。過程記錄：profile 寫入 `COMPILATION_JSON` 轉義反斜線導致 boot arg 錯誤（修正＋harness 加 90s 早錯檢查）；soak 兩個假警報（腳本未 source `cluster-common.sh` 致 401；verbose 列舉格式打滿 400 tok 預算——皆非模型回歸）。詳見 `docs/DEEPSEEK_B12X_RECIPE_AB_2026-10-09.md`。另依使用者決定，舊配方的 A/B lane `deepseek-tune{,.conf.base}` 同日**歸檔**至同一 `_overdue_recipe/` 目錄（白名單移除；未來 mainline 調優需從新配方另立 lane）。
> **2026-10-09（續二）**：**退役配方歸檔結構整併**——依使用者決定新設 repo 根目錄 `_overdue_recipe/`，子目錄命名 `<profile>_<image+tag>_<yyyymmdd>/`：`deepseek_anemll-dspark-vllm-gx10-011_20261009/` 與 `deepseek-vision_anemll-dspark-vllm-gx10-011_20261009/`。每個子目錄自帶：封存 conf（byte-identical，含 tune `.conf.base`）、**由封存 conf 現場重新渲染的 compose yml**（`--api-key` 已脫敏為 `<REDACTED:from-cluster.env>` placeholder，實 key 仍在 `~/docker-stacks/config/cluster.env`）、`patches/dspark-vision/` 副本（17 patch + `vision_exp/` + `NOTICE.md`；原 repo 根 `patches/dspark-vision/` 已移入兩份封存，**還原時須複製回 repo 根**——封存 conf 的 `SYNC_DIRS` 解析 `${REPO_DIR}/patches/dspark-vision`）、**`recipe_README.md`（該配方歷史 benchmark 記錄 + 退役對決 + 還原步驟 + 模型保留註記）**、頂層 `_overdue_recipe/README.md`（命名慣例/Inventory/還原總綱/封存 SHA256 表）。**Docker image 與模型檔不上傳**（digest pin 與模型路徑記錄於說明檔）。原 `cluster-profiles.d/_backup/` 全數移入後撤銷（loader 只掃 `cluster-profiles.d/*.conf`，新目錄在 repo 根永遠非 live）；AGENTS／README／兩份 A/B doc／現役 conf header／`bin/gb10` 註解的 `_backup/` 引用同步改寫。
> **2026-09-20（後續）**：**Qwen3.8 Flash-Next 125B NVFP4（TP2+EP、MTP3）上線**；同日起 **compose 為唯一啟動 lane**（移除 docker-run 分支）；**27b/35b 改走 compose**；node0 `~/docker-stacks/aeon-vllm-omni/` 清理。詳見下方「已完成（2026-09-20 後續）」。
> **2026-09-20（後續之二）**：**node-local 佈局歸位**——每個 lane 一個以 image 命名的 `~/docker-stacks/<stack>/`（`STACK_DIR`+`COMPOSE_FILE` materialize）、**cache 每 lane 獨立**（`~/.cache/vllm-<lane>[-cluster|-single]`，移除共用的 `~/.cache/huggingface` 容器掛載）、**log 統一** `~/docker-stacks/logs/<profile>/`；刪除單機 `runtimes.d/{qwen38flash,glm53flash}.conf`。詳見「已完成（2026-09-20 後續之二）」。

## 目前狀態（本機 checkout）

- 分支：`main`，HEAD = 本檔所在的 commit（`git log -1`）；最新正式版本 tag = **`v1.7.0`**（`32e79c4`；`v1.6.0`→`84f343c`、`v1.5.0`→`3201363`、`v1.4.1`→`cc76cbd`、`v1.4.0`→`6aff00d`、`v1.3.4`→`a92d2bc`、`v1.3.0`→`2474cf8`、`v1.3.1`→`276348c`、`v1.3.2`→`168cb99`、`v1.3.3`→`9bb2006`）。早期：2026-09-20 session 共 22 個 commit `a1cba34`…`79a79cb`，其後為本檔的 sync commit。live lane = **`deepseek-nvfp4`**（**2026-10-08** Phase 3 完成上線，README/handoff 詳載；主線 `deepseek` 待命 —— 使用者裁定「先不恢復」，`gb10 use deepseek` 隨時切回；`mimo26flash` 自 10-03 上線做 NVFP4 A/B + cliff 探測，**權重定案 MXFP4** 待命，見 `docs/…2026-10-03.md` §11）
- 同步狀態：**本機＝Forgejo（origin，`829522`）＝GitHub（`sawaichi9527`）＝node0 已 pull**（四方同一 commit；node0 live lane = **`deepseek`**（10-05 切回）；`mimo26flash` 定案 **MXFP4**、一鍵可切回）
- `handoff.md` 已納版控（`37bee4c` 起；本次更新亦將 commit）
- `.gitignore` 已覆蓋 `config/cluster.env`、`state/last-runtime`、logs、`*.bak-*`

## 兩個 CLI

| CLI | 角色 |
|---|---|
| `gb10` | 叢集（TP2），thick layer over `scripts/cluster-*`；Node0 控制面，Node1 headless |
| `gb10-single` | 單節點 runtime manager；`node0` local compose，`node1` 經 `ssh -i ~/.ssh/id_gb10_cluster eye@10.0.101.102` |

## 存取方式（開發機 → node0）

> 供 agent／維護者在 Windows 開發機上操作 node0。**本節不含任何密碼**（密碼向維護者索取，勿寫入 repo）。

| 項目 | 值 |
|---|---|
| 主機 | node0＝`spark-25d5`＝**`192.168.23.215`**（Node1＝`spark-8095`＝`192.168.23.216`） |
| 使用者 | `eye` |
| Repo 路徑 | `~/workspace/ai-gb10-cluster-runtime-manager`（branch `main`，upstream `origin/main`） |
| 認證 | **登入密碼**。sshd 同時開放 `publickey,password`；但本機 `~/.ssh/id_gb10_maint`（`opencode-gb10-maint`）與 `~/.ssh/id_rsa` **皆受 passphrase 保護**，且 Windows `ssh-agent` 服務為 `Disabled`，非互動 ssh 無法解鎖私鑰 → 實務上走 password。 |
| 工具 | `Posh-SSH`：`New-SSHSession -ComputerName '192.168.23.215' -Credential (New-Object System.Management.Automation.PSCredential('eye', (ConvertTo-SecureString '<pw>' -AsPlainText -Force))) -AcceptKey`，執行完 `Remove-SSHSession`（2026-09-29 實測可用） |
| 常見誤判 | 公鑰**已在** node0 `~/.ssh/authorized_keys`（第 3 行，fingerprint `SHA256:jcGtEB2cn4hLffmTiWCtPxZksYqBNMh8q6zGwYLD77I`）；金鑰登入失敗**不是**授權問題，而是私鑰 passphrase／agent 未啟動。以 admin 啟用 `ssh-agent` 並 `ssh-add` 後即可免密碼。 |

node0 對 node1 的連線（由 node0 發起）走 CX7 區網：`ssh -i ~/.ssh/id_gb10_cluster eye@10.0.101.102`（見上表 `gb10-single`）。

## 關鍵事實（勿當 bug「修」）

- **`cluster-common.sh` 自動解析 `REPO_DIR`**，腳本可攜；保持此方式。
- **Compose＝合約，CLI＝便利層**；發展合約在 `~/docker-stacks/`。
- **Node-local 佈局**：每個 runtime 的節點側產物在 `~/docker-stacks/<stack>/`（stack 名＝image 來源）：`aeon-vllm-omni`(27b/35b)、`anemll-dspark-vllm-gx10`(deepseek)、`anemll-dspark-vllm-gx10-miaFlaver`(deepseek-vision)、`mia-vllm-openai-qwen38flashNext`(qwen38flash)。stack 內含 materialize 的 compose 與 `patches/`。**`~/` 根不得有佈署產物**。同時跑 cluster+single 的 lane（27b/35b）compose 加 `-cluster`/`-single`；cluster-only 用 `docker-compose.<profile>.yml`。
- **Cache 每 lane 獨立**：`~/.cache/vllm-<profile>`（cluster-only）或 `~/.cache/vllm-<profile>-{cluster,single}`；各 conf 的 `AUTOTUNE_CACHE_REL` 指向自己的根。**Log 統一** `~/docker-stacks/logs/<profile>/`（boot + compose/container）。
- **統一 AEON stack**：`~/docker-stacks/aeon-vllm-omni/`（`docker-compose-27b-single.yml` + `docker-compose-35b-single.yml` + `docker-compose-{27b,35b}-cluster.yml` + `models/` + `*_029_patched.py`）；27b/35b 皆 v0.29.0-omni image。`aeon-vllm-reasoning-eos` 已退休。
- **Profiles 資料驅動**：`cluster-profiles.d/`（27b / 35b / deepseek / **deepseek-vision** / **qwen38flash** / **mimo26flash** / **deepseek-nvfp4**（2026-10-07 建置、**未開機**）），由 `cluster-common.sh` 載入；勿在 `cluster-*` 重寫死 profile 資料。
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
- **ComfyUI 部署在 Node1 —— 自 2026-10-14 起只有一條**：
  - `comfyui-jdaln` = `jdaln/ComfyUI-DGX-Spark-Docker-opinionated`（**2026-10-14 上線**，`GROUP=image`+`MODE=exclusive`，見下方同名章節）。
  - `comfyui`（aeon / Flux 2 Dev）**已於同日退役**（stack + image 刪除、conf 移除），不再是 rollback。
    **不要**回退到更早的 `comfyui-personal`/`comfyui-work` 分拆。
- **`minimaxh3` 已於 2026-10-14 退役**：vLLM-API lane（`:8000`、OpenAI-compatible）的 stack（135 GB）與 image（32 GB）已刪，`runtimes.d/minimaxh3.conf` 與 `src/minimax-h3/` 已移除。MiniMax H3 圖生影片改由 `comfyui-jdaln` 的原生節點（`:8188`）提供，**拆之前已 render 驗證**。兄弟目錄 `~/docker-stacks/minimax-h3-sglang/`（目錄 56 GB + 2 image ≈105 GB）**同日稍後也已清除** —— 它是 2026-09-04 的失敗實驗封存、從未是 lane；`FAILURE_ANALYSIS.md` 內容已擷取留存於下方退役章節。現在 `~/docker-stacks/` 底下已無任何 `sglang` 痕跡。
- **刪 root 擁有的節點目錄不要用 `rm -rf`**：容器以 root 建立的子樹，`eye` 無父目錄寫入權 → `rm` 只會印「拒絕不符權限的操作」然後「成功」結束。改用 `docker run --rm -v <dir>:/t … sh -c 'rm -rf /t/*'`（在 namespace 裡就是 root，免 sudo）。同理，`bash -c "rm …; echo DONE > f"` 的 `DONE` **不算成功證據**（`;` 一定會寫），要 `rc=$?; echo $rc > f` 分開記。SSH `has timed out` 既可能代表遠端已完成、也可能代表被殺 → 重送前先查狀態。
- **`comfyui-jdaln` 的上游 healthcheck 是假陽性**（`curl ... || pgrep -af 'curl .* models/...'` 會匹配到 healthcheck 自己的 `sh -c` 指令列 → 永遠 `healthy`）。**可信閘門是 gb10-single 對 `:8188/` 的 loopback curl**，不要看 `docker ps` 的 health。
- **`comfyui-jdaln` 資產範圍已裁剪**（2026-10-14）：`.env` 的 `COMFY_CUSTOM_NODE_EXAMPLE_WORKFLOWS_ALLOWLIST` 置空 + `docker-compose.yml:49` 預設值改 `${VAR-}` + `UPDATE_DEPS=false`。**要恢復 workflow gallery 就把 pack 名單寫回 `.env` 並把 `UPDATE_DEPS` 改回 `true`**；下載是冪等的（`download_if_missing` 跳過已存在檔）。
- **`comfyui-jdaln` 重建前必做**：複製 `SelfBuiltWheels/*` → `DGX-Spark-WheelsBuilder/Wheels/`（上游 LFS 內容在我們的 checkout 缺失，只留 `.gitkeep`），否則 onnxruntime 會從原始碼編譯（數小時）。

## 2026-10-14 — `comfyui-jdaln` 上線（Node1 第二個 ComfyUI）

**完整記錄：`docs/COMFYUI_JDALN_DEPLOYMENT_2026-10-14.md`。** 此處只留交接重點。

- **新 runtime `comfyui-jdaln`**（`runtimes.d/comfyui-jdaln.conf`，`GROUP=image`、`MODE=exclusive`），
  當時與既有 `comfyui`（aeon / Flux 2 Dev）**並存**而非取代。commit `72716a8`。
  **同日稍後依使用者裁定，`comfyui` 已退役**（見 §11 退役章節），本 runtime 成為 Node1 唯一 ComfyUI。
- Stack：`~/docker-stacks/comfyui-dgx-spark/ComfyUI-DGX-Spark-Docker-opinionated/`（clone `ef7a677b` +
  submodule `ComfyUI @ a5a00900`），模型/使用者資料 `~/docker-stacks/comfyui-dgx-spark/ComfyData/`，
  log `~/docker-stacks/logs/comfyui-jdaln/`。**建置 rc=0 / 144 s** → image
  `comfyui-dgx-spark-docker-opinionated-comfy:latest`（上游 compose 有 `build:.` 無 `image:`，
  tag 由 project name 推導，`PROJECT` 必須等於目錄名小寫）。
- **驗證**：`:8188` loopback+LAN 皆 **200**、ComfyUI **0.38.0**、**2812** node types、
  `gb10-single status node1` → `running / READY`、磁碟 106 G（1.5 T 剩餘）。
- **渲染 smoke test 過**：`POST /prompt` 排隊真 z-image turbo（1024×576、**4 步、cfg 1、
  res_multistep/simple**、`ModelSamplingAuraFlow` shift 3、`CLIPLoader type=lumina2`）→
  `status: success`、產出 `ComfyData/output/z-image_00001_.png`（709,670 bytes，約 30 秒）。
  完整 loader 參數見 `docs/COMFYUI_JDALN_DEPLOYMENT_2026-10-14.md` §8.0。

**三件踩坑（都已修，勿重犯）**：

1. **17.5 小時掛死**：`custom_nodes.txt` 指向的 `Saganaki22/ComfyUI-VDN-H3` 已 **404** →
   `git clone` 退回 credential prompt 卡在容器 stdin（`wchan=anon_pipe_read`、`read_bytes=0`）。
   **處置順序不可反**：先 `rm -rf` 殘缺目錄 → 再 `pkill -9 -f 'ComfyUI-VDN-H3[.]git'` →
   最後註解該行（先殺會讓迴圈下一輪重新 clone 再掛）。註解該行**必須等 entrypoint 讀取迴圈結束**才安全，
   中途改會位移 fd offset。
2. **`gb10-single-boot` 假 READY**：健康探測從未成功卻仍寫 `boot-ready.*` → `wait` 說 READY 實為死服務
   （本次直接踩到：`state/boot-ready.node1.comfyui-jdaln` 假稱 `10-12 21:52:30 READY`）。
   **修復 commit `537c64e`**（`+14/−2`）：`_ready` 旗標只在探測真成功時設；迴圈後為 0 → `exit 1`，
   迴圈內超時分支只 `break`。已 push 兩遠端 + node0 pull + `check-git-sync` SYNC_OK + 模擬兩情境通過。
3. **資產範圍爆量**：預設只有 `z-image-turbo-core`（19.27 GiB），但 `.env` 有**未註解**的
   `COMFY_CUSTOM_NODE_EXAMPLE_WORKFLOWS_ALLOWLIST`（6 個 pack）→ helper `profiles.extend(...)` 擴成
   3 個 profile 共 **93 GiB**；緊接著 stage ② 掃 118 個 example workflow JSON 得 **204 個模型引用**，
   direct-URL 可解析 54 個 → 實測**再 +174 GiB / 約 8.8 h**（且 WanVideoWrapper 走 repo-候選路徑，
   97 個引用未量化，174 GiB 只是下限）。當時磁碟已 111 GiB。
   **三個陷阱**：(a) 預設值不在 `.env` 而在 `docker-compose.yml:49`；(b) `${VAR:-}` 把空值當未設，
   必須改成 `${VAR-}`；(c) `UPDATE_DEPS=true` 會在重啟時對 32 個 pack 逐個 `git pull`（GitHub 實測
   ~150 KB/s，每個都是新的掛死機會）。
   **使用者裁定「砍 ALLOWLIST，先讓服務上線」** → 註解 `custom_nodes.txt:56` + compose 改 `${VAR-}` +
   `.env` 設 `ALLOWLIST=`（空）與 `UPDATE_DEPS=false` → **`use` 到 READY 只花 46 秒**
   （00:13:46 → 00:14:32），已下的 111 GiB 全數保留。**已知殘餘**：
   `ComfyUI-SAM3-DGX-Spark` 匯入失敗（其 pin `comfy-env==0.2.61` 已被 PyPI 下架，最舊只剩 `0.3.0`）——
   **無功能影響**，11 個 `SAM3_*` 節點其實由 ComfyUI **core**（`comfy_extras.nodes_sam3d_body`）提供，
   該第三方 pack 貢獻 0 個節點。

## 2026-10-14 — Node1 兩條 runtime 退役（`comfyui`／aeon + `minimaxh3`）

**完整記錄：`docs/COMFYUI_JDALN_DEPLOYMENT_2026-10-14.md` §11–§12。** 此處只留交接重點。
兩者都在 `comfyui-jdaln` 上線並驗證**之後**才拆。

### ① `comfyui`（comfyui-aeon / Flux 2 Dev）— 使用者裁定「直接退役移除」

- **順序不可反**：HF token 原本在
  `~/docker-stacks/comfyui-aeon/workspace/.cache/huggingface/token`（**即將被刪的樹內**），
  且當時仍是 `minimax-h3/launch-download.sh` 的活憑證 → **先**搬至
  `~/docker-stacks/config/hf_token`（mode 600、37 B、sha256 prefix `7f871a56841c699c`），
  兩處 `TOKEN_FILE` 都改指過去，**再**動手。
- 刪除：image `ghcr.io/aeon-7/comfyui-aeon-spark:slim`（26.7 GB）+ stack（71 GB）。
  `grep -rn comfyui-aeon ~/docker-stacks` → 乾淨。
- **無備份的 flux2 權重（已永久刪除）**：`flux2_dev_fp8mixed` 34 GiB、
  `mistral_3_small_flux2_bf16` 34 GiB、`Flux2TurboComfyv2` 2.6 GiB、`flux2-vae` 321 MiB、
  `full_encoder_small_decoder` 238 MiB、4× KJNodes intrinsic LoRA 各 6.2 MiB。
  `comfyui-jdaln` **零 flux2 權重**，沒有遷移對象 → 要用只能重抓。
- **踩了三次才成功，兩個假成功訊號**（勿重犯，見「關鍵事實」）：root 子樹刪不動 +
  `;` 串接的 `DONE` 標記 + SSH 逾時的雙重語意。

### ② `minimaxh3` — 使用者裁定「退役」，但**先驗證再拆**

- **起因**：使用者問「jdaln 範本也有 MiniMax H3 圖生影片，是不是與 `minimax-h3/`、
  `minimax-h3-sglang/` 重複？」→ 查證結果是**三種不同層**（vLLM API `:8000` / SGLang 死實驗 /
  ComfyUI `:8188`），**介面不同、權重量化也不同**（原始 HF 分片 64 GB / NVFP4 12.5 GB /
  int8-convrot 20.9 GB），功能重疊但非替代品。仍依使用者裁定退役。
- **`minimax-h3-sglang` 從頭到尾不是 lane**，**且已於同日稍後依使用者指示一併清除**：
  `archive_sglang_experiment_2026-09-04/` 內有 `FAILURE_ANALYSIS.md`、
  `compose.*.failed.yaml`、`launch.*.failed.sh`，最後活動 09-04，repo 無任何 conf 引用。
  - **刪除範圍**：目錄 `~/docker-stacks/minimax-h3-sglang/` **56 G**（全部在
    `models/quantized`）+ 2 個 image **105 GB**（`429ac2d-cu134-ffmpeg` 45.8 GB、
    `429ac2d-nvfp4` 59.2 GB，各 `Untagged`+`Deleted` rc=0）。image 總數 11→9。
  - **為何可安全刪**：`qwen3vl_32b_minimax_h3_nvfp4_awq`(15 GiB)、
    `minimax_h3_video_vae_fp16`(4.9 GiB)、`minimax_h3_audio_vae_fp32`(578 MiB)
    三個 **jdaln 已有同檔**（在 `ComfyData/models/`，不同路徑）；其餘
    `.sglang.safetensors`／`.upstream.safetensors`／`.corrupt` 三個各 12 GiB
    是 SGLang 專用轉檔格式，只對已死的 runtime 有用（其中一個本身已損壞）。
  - **`.cache` 是 root 擁有** → 沿用容器內 `rm`，`rc=[0 0]`。
  - **刪除前先把 `FAILURE_ANALYSIS.md` 內容存進本檔**（見緊接的下一則「
    原文留存」），因為刪了就沒了。
- **`FAILURE_ANALYSIS.md` 原文留存（2026-09-04 stop-loss，刪除前擷取）**：
  > **Status: STOP-LOSS TRIGGERED (user decision). Experiment archived, NOT deleted.**
  > **Verified wins**: 上游 `MiniMax_H3_FL2VA_pruned_nvfp4.safetensors` byte-complete +
  > SHA256 `6ab7f0c4…9976f` (12528636865 B)；其 65-byte non-safetensors `L2P_bypass`
  > trailer（在 header tensor data 之外）會讓 strict `safe_open` 拒絕 → 清除後的
  > `.sglang.safetensors` = `truncate -s 12528636800`、`cmp -n` PASS、checksum
  > `9d49beb6`（記錄於 `SHA256SUMS.txt`）；transformer NVFP4 載入成功（`group_size=16`、
  > 274 excluded、12.87 GB）；text_encoder NVFP4-AWQ 載入成功（350 comfy_nvfp4 linear）。
  > **Failure (blocker)**: boot 走到 `audio_vae` → `ComponentCheckpointUnsupportedError`：
  > `audio_vae` 使用自訂 Diffusers 類別，無法吃 weights-only override
  > （`vae_loader.py:512`）。在允許規則內**無解**（不得移除/修改 override、無
  > `--component-paths.audio_vae` 開關、不能打 loader patch、無 nightly、不重建 image）。
  > **Retry path (future)**: 改用已淨化的 `.sglang.safetensors` 並重新量化，讓所有元件
  > 皆用標準 safetensors layout；或提供 loader 相容的 weights-only `audio_vae` override。
- **驗證閘門（使用者選「先跑一次 i2v 驗證」）**：jdaln 的 MiniMax 從未被 render 過
  （先前只測 z-image），所以先用**內建 blueprint 的原始接線**（把
  `ComfyUI/blueprints/Image to Video (MiniMax H3).json` 的 litegraph subgraph 展開）
  建 15 節點 API 圖 → `node_errors: {}` → `prompt_id d91692b7` → `status=success`、
  **204.52 s** → `MiniMax_H3_verify_00001_.mp4`（935,097 B、magic `ftyp isom`）。
  伺服器 log 確認四件套載入：`MiniMaxH3TEModel_` 14956 MB / `MiniMaxH3VideoVAE` 4965 MB /
  `MiniMaxH3` 19995 MB（`model_type FLOW_AV`）/ `MiniMaxH3AudioVAE` 312 MB。
  **注意接線事實**：blueprint **不含** `MiniMaxH3SigmaShift`、`MiniMaxH3AddGuide`、
  `EmptyMiniMaxH3LatentAV` —— `MiniMaxH3ImageToVideo` 自己產出 `positive`+`LATENT`，
  錨定由 `first_frame` 處理；預設不掛 LoRA、20 steps。
- **已知缺口**：`minimax_h3_ref2va` 沒下（§7 裁剪時被砍）→ `MiniMaxH3ReferenceToVideo`
  與「Reference to Video」範本仍跑不起來；`ImageToVideo`/`TextToVideo` 正常。
  51 個 MiniMax 節點中 **39 個本機**、12 個是雲端 API（`ComfyCloudMiniMaxH3*`/`MinimaxHailuo*`）。
- **刪除**：stack 135 G（64 G 權重 + 73 G HF cache + 1.6 G `.git`）、
  image `minimax-h3-dgx-spark:sm121-fp8` 32 GB、`~/Downloads/minimax-h3-output` 19 M
  （使用者：「一起刪」；其 `storage/*` 是 root 擁有 → 容器回退）、
  `runtimes.d/minimaxh3.conf`、`src/minimax-h3/`（45 檔）。
  **共享池 `~/docker-stacks/models/`（453 G）查證不含 minimax** → 拆它不影響他者。
- **失去的**：`:8000` 的 OpenAI-compatible API endpoint（腳本/批量/CI 路徑）。
  要用得改走 `:8188` 的 ComfyUI `/prompt` API；權重可依
  `docs/MINIMAX_H3_DEPLOYMENT_2026-09-01.md` 重抓，但實測 5–7 MB/s 是多小時等級。

### 磁碟

兩者合計：`used 2.1T → 1.9T`、`avail 1.5T → 1.7T`、**59% → 53%**。

## 2026-10-14（續二） — Node0 殘留清除 + `comfyui-jdaln` failover 鏡像建立

**起因**：Node1 側三項退役完成後，使用者提醒「Node0 與 Node1 之間的同步要透過 CX7 網路
作 rsync 比較快」。盤點後發現**退役只做了一半** —— Node0 還留著兩個退役 runtime 的副本。

### 1. Node0 殘留清除（~204 GB）

| 項目 | 大小 | 說明 |
|---|---|---|
| `~/docker-stacks/minimax-h3/` | 135 GB（217 檔） | 就是 2026-09-01 部署文件裡的「Node0 failover mirror rsync in progress」；最新 mtime 2026-09-01 23:17，含 `compose.yaml` + `.env`(600) |
| `~/docker-stacks/comfyui-aeon/` | 54 GB（3,919 檔，**5,054 個非 eye**） | 最新 mtime 2026-07-31 —— 比 Node1 那份還舊 |
| image `ghcr.io/aeon-7/comfyui-aeon-spark:slim` | 16.8 GB | Node1 當時是 26.7 GB，兩節點版本本就不同 |

**刪前查證**：repo conf 無人引用這兩個路徑、`state/` 無標記、**無任何容器**（running 或
stopped）使用。`minimax-h3-sglang` 從未出現在 Node0。

**執行**：兩目錄一次容器內 `rm`（`comfyui-aeon` 含 root 擁有 → 必須容器內）`rc=0`；
image `Untagged`+`Deleted` `rc=0`。

**磁碟**：`used 1.8T / avail 1.8T / 51%` → `1.6T / 2.0T / 46%`。

**未動**：Node0 的 `c0918`（`Created` 自 2026-09-18、image `ghcr.io/aeon-7/aeon-vllm-ultimate:
2026-09-18-v0.29.0-omni`、`cmd=null`、無 mount）—— 那是 AEON runtime 的 `docker create`
殘骸，與本次無關。

### 2. `comfyui-jdaln` failover 鏡像（經 CX7，124 GB + image）

使用者裁定：「把 node1 的 jdaln 鏡像到 node0」。全程由 Node0 發起、走 CX7：

```bash
# stack（在 node0 執行）
rsync -aHAX --no-o --no-g --delete \
  -e 'ssh -i ~/.ssh/id_gb10_cluster -o BatchMode=yes -o StrictHostKeyChecking=no' \
  eye@10.0.101.102:~/docker-stacks/comfyui-dgx-spark/ ~/docker-stacks/comfyui-dgx-spark/

# image —— 方向：Node1 才有，所以 Node1 save、Node0 load
ssh -i ~/.ssh/id_gb10_cluster eye@10.0.101.102 \
  'docker save comfyui-dgx-spark-docker-opinionated-comfy:latest' | docker load
```

**結果**：rsync **rc=0**、335 s、**114,316 檔 / 132.79 GB / ~396 MB/s**（磁碟瓶頸，NIC 尚有
餘裕）；image **rc=0/0**、128 s。

**驗證（byte-mirror）**：

- 檔案／目錄／symlink 數兩端**完全相同**：`114,316 / 16,298 / 6`，size 都是 124G。
- 抽查 >2 GB 權重 `hunyuan_video_720_fp8_e4m3fn.safetensors` 的 sha256
  `07ae20b5…d62426` **兩端一致**。
- 鏡像上非 eye 擁有條目 = **0**。`--no-o --no-g` 是刻意的：來源只有 1 個 uid 0 的目錄
  （`ComfyUI-DGX-Spark-Docker-opinionated/ComfyUI/user`），不加會在 Node0 複製出
  root-owned 檔 —— 本 repo 今天已經被這件事咬兩次。

**image「看起來不一樣」不是 bug**：Node1 用 containerd image store 存**壓縮**層
（`.Size` 6.87 GB），Node0 用經典 `overlay2` 存**解壓**層（`.Size` 10.28 GB）。**31 層
diff-ID chain byte-identical**、`Created`/`Entrypoint`/arch 相同，且 `docker save` 的
tarball 大小正好等於 Node1 的 `.Size`（多出的 36 KB 是 tar 元資料）。image ID 不同是
config 重序列化所致。`--entrypoint /bin/sh` smoke test 通過（Python 3.12.3、`/workspace`
完整；`ComfyUI`/`custom_nodes`/`venv` 是 runtime bind-mount、本來就不在 image 內）。

**我自己踩的方向 bug**：第一次把 `docker save` 放在 Node0 執行 → `reference does not
exist` + `unrecognized image format`，因為 Node0 根本沒有那顆 image。方向必須是
Node1 save → Node0 load。

**尚未驗證（重要）**：Node0 端**沒有實際 boot ComfyUI**。當時 Node0 正跑 27b TP2 cluster，
起 ComfyUI 會搶同一顆 GB10 GPU。所以這是**被動 byte-mirror，不是自動 failover lane**：
`runtimes.d/comfyui-jdaln.conf` 沒有 `NODE` 欄位（`gb10-single` 以參數指定節點），真要切換
得手動 `gb10 stop`（TP2）→ `gb10-single use comfyui-jdaln node0`，而**這條路徑尚未實測**。
重新鏡像就用上面同一行 rsync，不需要排除任何東西。

### 3. 輸出目錄改到 `~/Downloads/output/` + 測試產物清除

使用者指示：以後 jdaln 產出放 `~/Downloads/output/`，順便清掉兩個 Node 的
`ComfyData/output/` 測試檔。

**為什麼不能用 override 檔**：`scripts/gb10-single-boot:106` 是
`docker compose -p "$PROJECT" -f "$COMPOSE_FILE"` —— 明確 `-f` 會讓
`docker-compose.override.yml` **不被自動載入**。而輸出掛載位於**上游 git 追蹤的**
`ComfyUI-DGX-Spark-Docker-opinionated/docker-compose.yml` 第 30 行。因此改動直接落在
compose 本身，但做成**保留預設值**的參數化形式：

```yaml
      - ${COMFY_OUTPUT_DIR:-../ComfyData/output}:/workspace/ComfyUI/output
```

`.env`（gitignored）第 22 行設 `COMFY_OUTPUT_DIR=/home/eye/Downloads/output`。變數未設時
上游行為完全不變。

**前置查證**：`ComfyData/user/default/comfy.settings.json`（13 KB）**沒有任何 output 相關
鍵** → ComfyUI 不會釘住絕對路徑，只換掛載即生效。UID/GID `.env` 為 1000:1000、與 `eye`
一致。compose 改後 `config --quiet` **rc=0**。

**執行（node1）**：備份 `docker-compose.yml` 與 `.env` → `mkdir ~/Downloads/output` →
sed 改第 30 行 → 寫 `.env` → `docker compose up -d`（`Container comfyui Recreated`）。
容器掛載確認為 `/home/eye/Downloads/output -> /workspace/ComfyUI/output rw=true`，容器內
`touch` 寫入測試 **YES**，**`:8188` 約 10 秒即 READY**、`health=healthy`、`restarts=0`、
`/` 與 `/system_stats` 皆 200。

**清除**：兩節點的 `ComfyData/output/` 各刪 2 檔（`MiniMax_H3_verify_00001_.mp4` 935,097 B、
`z-image_00001_.png` 709,670 B）與空的 `video/` 目錄。node0 那份是靠**重跑同一條 rsync**
帶走的（`--delete` → `Number of deleted files: 3 (reg: 2, dir: 1)`，rc=0、4 秒）。目錄本身
保留（仍是上游預設路徑），底下剩 `qwen3-tts_voices/`、`exp_data/` 兩個 **空目錄**（custom
node 啟動時建的，不是測試輸出）。

**驗證**：node0/node1 的 `docker-compose.yml` 與 `.env` **sha256 完全相同**；node0 compose
解析 rc=0；node0 無 comfyui 容器（仍是被動鏡像），只有 `aeon-vllm-27b Up 2 days` +
`c0918 Created`。

**三個要記的限制**：

1. **compose 現在與上游分歧 2 行**（另一行是舊有的
   `COMFY_CUSTOM_NODE_EXAMPLE_WORKFLOWS_ALLOWLIST` 預設值，與 `.env` 重複）。未來
   `git pull` 可能在這兩行衝突 —— 解法是保留 `${COMFY_OUTPUT_DIR:-../ComfyData/output}`。
2. **`~/Downloads/output/` 在鏡像範圍之外**（`~/docker-stacks/comfyui-dgx-spark/` 以外），
   所以產出**不會**被鏡像到 node0。這是刻意的：產物可重新產生。
3. 舊 mp4 已在刪除前撈到 Windows `C:\Users\Sawaichi\Downloads\`（sha256 一致）。

### 磁碟（Node0）

`1.8T used / 1.8T avail / 51%` →（刪殘留）`1.6T / 2.0T / 46%` →（+124 GB stack + image）
**`1.8T / 1.8T / 49%`**。

## 2026-10-07 — aeon 舊 image 清理（兩節點）

**背景**：使用者確認現行服務用 `ghcr.io/aeon-7/aeon-vllm-ultimate:2026-09-18-v0.29.0-omni`
（= 27b/35b profile 的 `IMAGE` pin），舊版可刪。

**⚠️ 根因（第一次刪除後 09-11 又回來）**：兩節點各有一個 **9月13 session 遺留的
`/tmp/pull_watchdog.sh`**（`setsid` 起的 `while true` 迴圈，30 秒一次），內容是
「若沒有 `docker pull ghcr.io/aeon-7` 進程就自動重啟 `2026-09-11` 的 pull、log 停 600s
就 pkill 重拉」——所以第一次 rmi 後 9 秒即被拉回（`docker events` 可見連續 `pull` 事件，
`/tmp/pull029.log` 有 "watchdog: pull gone, restarting"）。**處置**：兩節點
`pkill -f 'pull_watch[d]og'` + 刪 script + 殺殘留 pull + 再 rmi；90s/120s 兩輪複查：
無 watchdog、無 pull 進程、**pull 事件為零**、aeon 僅剩 09-18、無任何 `/tmp/*.sh` loop
在跑。兩節點皆無 crontab / user timer 可疑項目（僅 launchpadlib）。
**教訓**：刪除鏡像前先查 `pgrep -af 'pull_watch[d]og'` 這類自動化殘留，否則會跟它打架
（`pkill -f` 注意自噬：模式內放 `[d]`/`[r]` 字元類，且指令列不要出現字面目標字串）。

**清理內容**：
- **node0**：刪 `2026-08-16-v0.27.1`（50.6 GB）與 `2026-09-11-v0.29.0-omni`（52.3 GB）、
  dangling `ab047f03a432`（20.6 GB）；先移除擋路的殘留容器 `c0911`（Created 狀態、
  2026-09-18 建、掛舊 image）。`c0918`（掛 09-18）保留。
- **node1**：刪 `2026-09-11-v0.29.0-omni`（74.6 GB）與 2 個 dangling（38.1 + 38 GB，
  回收 37.46 GB）。
- **設定指向同步**（否則刪完指向壞掉）：兩節點 `config/cluster.env` 的 `IMG` 與
  node1 `config/standalone.env` 的 `AEON_IMAGE`（node0 早已是 09-18）→ 全部改
  `2026-09-18-v0.29.0-omni`；repo `cluster-common.sh` 的 `IMG` fallback 預設值
  09-11 → 09-18。`~/docker-stacks` 內 config/compose/env/sh **零殘留**（複查）。
- 執行中服務不受影響：兩節點 `cluster-node*` 跑的是 `anemll/dspark-vllm-gx10:0.1.1`，
  未觸碰；`2026-09-18` 兩節點皆保留。

## 2026-10-07 — deepseek-nvfp4 lane 建置（Phase 1–2；Phase 3 完成 2026-10-08）

**動機**：mainline/vision 鎖在 `anemll/dspark-vllm-gx10:0.1.1`（上游疑似停止維護）。
新 lane 把同一代 0731 模型搬到**有持續 nightly CI** 的 `eugr/spark-vllm-b12x`
（`eugr/spark-vllm-docker`，DockerHub ~10.2 GB），**完全不動**
`deepseek.conf` / `deepseek-vision.conf`。

**選型定案（使用者拍板）**：
- checkpoint = `nvidia/DeepSeek-V4-Flash-0731-NVFP4`（0731 = 主線同代；DSpark heads
  保留未量化；~172 GB / 48 shards，非 gated、MIT、無上游 `SHA256SUMS` → 以 HF LFS
  sha256 oid 比對）
- stack dir = `~/docker-stacks/eugr-spark-vllm-b12x/` + compose
  `docker-compose.deepseek-nvfp4.yml`（full-convention）
- image 先 pull `:latest` 再把 manifest digest 鎖進 `IMG_SHA256`
- **模型與 image 只在 node0 下載一次**，經 10.0.101.x CX7 內網
  （rsync／`docker save|ssh docker load`）送 node1 —— 對外頻寬有限，不雙邊 pull
  （node1 先前誤啟的 eugr pull 已停止；node1 另有一個**非本 session** 的
  `aeon-vllm-ultimate:2026-09-11-v0.29.0-omni` pull —— 後續已結束，並連同舊 image 清理，
  見下方「2026-10-07 — aeon 舊 image 清理」）

**已完成（Phase 1–2，2026-10-07）**：
- 1.1 磁碟預檢：node0 2.2 T / node1 2.1 T 可用 ✅
- 1.2 `nohup hf download … --local-dir ~/docker-stacks/models/deepseek-v4-flash-0731-nvfp4`
  （log：`~/docker-stacks/logs/deepseek-nvfp4/hf-download.log`）＋ 1.4 node0
  `nohup docker pull eugr/spark-vllm-b12x:latest` —— **皆完成**（模型 48/48 shards、
  image digest `036c3076…`）
- **1.3 模型校驗 PASS**：49/49 LFS 檔（48 shards + index）對 HF `lfs.sha256` 全中、
  0 缺漏；`SHA256SUMS`（75 檔）產出於模型目錄
- **1.5 rsync PASS**：經 CX7 傳 node1（rsync log 0 bytes 無錯、兩端 59 條目）→
  `gb10 verify-models deepseek-nvfp4` **兩節點 PASS**（node0 75 OK、node1 全驗，rc=0）
- **1.4a image 已完成並經 CX7 內網送達 node1**（`docker save | ssh docker load`，
  log `docker-transfer-node1.log`；node1 早先誤啟的 eugr pull 已停）。
  **digest 兩節點表述不同是已知且已處理**：node0（registry pull）`sha256:036c3076…`、
  node1（containerd 重建 manifest）`sha256:dc0e9faa…`；**內容同一性已證**
  （29 層 diff ID 摘要與 `.Config` 摘要兩節點完全相同）。因此 gate 加了
  選用性 `IMG_SHA256_NODE1` 每節點 pin（其他 profile 未設＝行為不變），
  node0 實跑 `verify_profile_image_gate` **PASS**，bogus digest 反向測試**正確 fail**。
- `cluster-profiles.d/deepseek-nvfp4.conf`：eugr `deepseek-v4-flash-0731.yaml` 配方
  （B12X backends、dspark k=5 probabilistic、block 256、capture 48、GMU 0.85、
  `HEALTH_TIMEOUT=3600`（B12X JIT 首啟））× NVFP4 差異（`QUANTIZATION=none` 自動偵測、
  `KV_DTYPE=fp8`、per-lane cache `~/.cache/vllm-deepseek-nvfp4`）；boot-stage 候選與
  KNOWN RISK（prefix-hit 截斷、spec decode 未驗證、Marlin fallback 觀察）全寫在 conf 頭部
- `bin/gb10` 六處白名單（usage ×2、`PROFILES_BY_NAME`、`list`、use/start、restart）
- `scripts/cluster-common.sh` loader `unset` 列表補 `HEALTH_TIMEOUT`
  （27b/mimo26flash 既有的洩漏缺口）
- README（新 section、registry tree、deployed 清單、**同名舊 lane 警告**）＋本檔
- **驗證**：`bash -n`（gb10/conf/cluster-common）全過；node0 上 A/B render ——
  八條既有 lane（27b/35b/deepseek/deepseek-tune/deepseek-vision/deepseek-vision-tune/
  qwen38flash/mimo26flash）**byte-identical**、新 profile render 242 行正常、
  `gb10 list` 顯示正確

### Phase 3 完成（2026-10-08）

boot ×4，兩個啟動修復 + 一個 acceptance 根因 hotfix：

1. **boot #1 fail（io_uring/seccomp）**：Docker 預設 seccomp 擋 io_uring → 新增通用
   profile 欄位 `SECURITY_OPT=("seccomp=unconfined")`、`cluster-compose-verify`
   SecurityOpt 改 **subset match**（`10fff38` + `2cdec55`）。
2. **boot #2 fail（b12x loader strided conversion）**：`--load-format b12x` 對
   `mtp.1.ffn.experts.0.w1.scale` 嘗試 E8M0→e4m3 轉換 `NotImplementedError` →
   改 `--load-format safetensors`（commit `d2b090d`；**事後證實此錯正是下面
   draft 量化 bug 的另一表現**——b12x loader 發現 param 期待 e4m3）。
3. **boot #3 READY 但 DSpark acceptance 崩**（~1.1 tok/step、pos0 0.10、單流 16 tok/s）
   → 根因（詳見 conf KNOWN RISK #2）：checkpoint 的 DSpark draft 專家（`mtp.*`）
   **原生 MXFP4**（int8+E8M0 g32，checkpoint `ignore` 明列豁免），但 draft 的
   quant 實例 `moe_quant_algo` 懶解析自**與 target 共享的 NVFP4 hf quant dict**
   → draft 專家建成 `ModelOptNvFp4FusedMoE` → E8M0 g32 scale 靜默灌進 e4m3 g16
   buffer → **draft MoE 算垃圾**。= 上游 `vllm-project/vllm#49133`（closed unmerged；
   本 image 已吃一半修法——fresh draft quant 實例，但資料源仍共享 → 同捆 draft
   照樣解析 NVFP4）。鐵證：`Mxfp4 MoE backend` 行兩節點 **0 次**（PR 給的診斷特徵）、
   modelopt w1/w3 警告與 draft load 同秒、draft 與官方 ckpt 逐位相同卻 10× 驗收差。
   **已排除**：取樣語義（temp=0 本來就 greedy）、heterogeneous vocab、prefix cache、
   停用 spec decode（使用者選「再調查」→ 根因定位）。
4. **hotfix（boot #4 採用）**：`patches/eugr-spark-vllm-b12x/hotfix-dspark-draft-mxfp4.py`
   —— SWA hotfix 同模式（region 恰一次 + 全檔 sha pin、fail-closed、原子寫入；
   容器內實測 apply／冪等／篡改 fail-closed 全過）：在 draft 自己的 quant 實例上
   預清空 `_resolved_moe_quant_algo`（僅當共享 dict 明列 `mtp.*` 豁免時）→
   dispatch 走 `Mxfp4MoEMethod` = 官方 ckpt 同路徑；target 自己的實例不變。
   conf 接線：`CMD_WRAPPER`（fail-closed）+ `EXTRA_MOUNTS` ro 掛 `/opt/eugr-patches`
   + `SYNC_DIRS`（雙節點佈署，Node1 無 repo）。
5. **boot #4 全 gate PASS**（01:23:52 → 01:45:08 READY，~21 min）：
   - hotfix `applied` ×2 rank；`Mxfp4 MoE backend`（`B12X_MXFP4_MXFP8`）出現；
     modelopt w1/w3 警告 **0/0**；target `B12X NvFp4` 不變、`expert_dtype fp4`；
     health 200、smoke `HELLO-TP2-OK`、compose-verify 兩 rank PASS
   - **DSpark acceptance（門檻 pos0≥0.3 / >16 tok/s）**：
     temp0（483 tok）→ pos0 **0.629**、avg **27.0%**、AL **2.35**/5、
     單流 **33.6 tok/s**（基線 16，**+110%**）；temp0.7（`gb10 load` 3 輪）
     → avg **49.6–59.0%**、AL 3.5–4.0（官方 ckpt 社區基準 46–60% 同級）
   - prefix-hit：**HIT 44.8×**、3 輪 `PREFIX-OK` 完全一致、無截斷
   - garble soak 3/3（`finish=stop`、`uniq=1.0`、primes 10/10）
   - Marlin **無 fallback**（唯一提及是候選清單字串）

6. **C1~C8 完整併發 benchmark（2026-10-08，`bench-c.sh` ×8、`BENCH_IGNORE_EOS=1`
   固定 400 tok/流、thinking 預設開、混合 code+JSON prompt）**：
   聚合 **47.1 / 69.0 / 71.3 / 90.7 / 87.1 / 110.1 / 123.4 / 129.9 tok/s**（C1→C8
   = **2.76×**、C8 單流攤提 16.2 tok/s、全格 `finish=length` `any_errors=0`）；
   acceptance **41.4–50.0%**（AL 2.07–2.50）、pos0 **73.8–83.8%**、per-pos 遞減
   至 pos4 15.8–26.2%（pos5/6 恆 0 = n=5 結構性上限）——**8 路下 DSpark 驗收
   不崩**，多流併發原生可用（keys/drowzeys 7 月 patch 已內建於 10-06 image）。
   同輪修 `bench-c.sh`：本 image `/metrics` 掛在同一把 `VLLM_API_KEY` 後
   （no-auth **401**）但兩處 scrape 沒帶 `AUTH_ARGS` → 每格 `(no draft delta)`；
   已補 auth + 註解（無 key 時陣列為空、其他 lane 行為不變）。首輪（未修）與
   重跑（已修）吞吐逐格誤差 ≤9%（單跑 vs 單跑，比 ±7% 中位噪聲帶略寬，方向一致）。
   備註：此測試 thinking **預設開**（payload 無 `chat_template_kwargs`），
   token 進 reasoning 故 acceptance 低於先前 thinking:false 純 code 探針的 78.2%。
7. **NVFP4 KV A/B（2026-10-08，(c) 題唯一未用槓桿）：B cell 單旋鈕
   `KV_DTYPE=nvfp4_ds_mla` → 決定性開機失敗，已回退 `fp8`**。Root cause
   三重獨立硬閘（image 2026-10-06）：① DeepSeekV4 模型層
   `use_fp8_ds_mla_layout=True`，`_resolve_dsv4_kv_cache_dtype` 只收 `fp8*`
   （`config/cache.py` 通用接受清單會誤導——模型層覆蓋它）；②
   `b12x_mla_sparse.py` "B12X nvfp4_ds_mla requires GLM5Next"（backend init
   也擋）；③ `flashmla_sparse.py` 需 `device_capability.major==10`（SM100）。
   → DeepSeekV4 on GB10 在此 image **無可行路**，未有上游變更勿重試；
   完整註記已寫入 conf `KV_DTYPE` 段。A 側參考值（fp8，2026-10-08 實測）：
   KV pool **343,549 tok**（1.31x@262144）、`bench-ctx 200000 cold`
   **1984.6 tok/s**（200101 tok / 100.8s）。過程教訓：① B 開機 rank0/rank1
   皆 `Exited(1)`，但 `gb10 wait` 只輪詢 health、不偵測 container exit，
   直到 SSH 逾時才暴露——**可選改善：wait 應在 container exit 時提早報錯**；
   ② SSH 逾時後孤兒背景 boot 仍存續（其 3600s health timeout 到點才自盡），
   期間 `gb10 use` 拒絕新 boot（`background boot for another profile already
   running (PID …)`）→ 復原前須確認孤兒 PID 已死；③ **`gb10 down` 非法子
   命令**（印 usage、rc=2 靜默 no-op），清場正確指令是 `gb10 stop`。

**狀態（2026-10-08 更新）**：Phase 2–3 改動**已提交並推送**——`2cdec55`
（compose-verify subset 修正）、`c0ef7fd`（hotfix 接線 + `patches/eugr-spark-vllm-b12x/`
+ Phase 3 記錄），origin 與 github 雙推、node0 pull 對齊，四樹清潔；
**主線恢復經使用者裁決「先不恢復」——`deepseek-nvfp4` 維持在線**，
之後隨時以 `gb10 use deepseek` 切回主線（nvfp4 ↔ deepseek 互斥，`gb10 use` 自動拆）。
本節第 6 項的 `bench-c.sh` auth 修正為 2026-10-08 新增（另輪 commit）。

## 2026-10-07 — DeepSeek V4 Flash Vision 同 image 調優 A/B（V0–V5, V-win）→ V3 promote

**問題**：在**與 mainline 完全相同的 pin image**（`anemll/dspark-vllm-gx10:0.1.1`）
之下，把 `deepseek-vision`（deepseek-v4-flash-vision-exp）調快。範圍由使用者明確劃定：
**只動這一個 profile、只動同一顆 image、其餘模型服務不變**。全程 pull-only，
不重建 image、不碰 `deepseek.conf`。mainline 的 E6 階段（要改 `deepseek.conf`）
因此**主動取消**。

**方法**：複製 mainline 的做法 —— 獨立 lane
`cluster-profiles.d/deepseek-vision-tune.conf`（+ `.base`），`scripts/ab-setcell.sh V<n>`
每次從 `.base` 還原再套單一旋鈕（anchor 斷言 + `bash -n` + diff 稽核），
`scripts/ab-run-cell.sh <cell> <label> <profile>` 三參數全必填跑 use → wait →
compose-verify → smoke → bench。**`.base` 對生產 conf 只差 lane 識別欄位
（`PROFILE_ID`/`DISPLAY_NAME`/`STACK_DIR`/`COMPOSE_FILE`/cache 路徑），argv 與 env 等價**
—— 升版時逐欄驗過。

> **`deepseek-tune` / `deepseek-vision-tune` 不是服務**：兩者只是 tooling 做
> **單一旋鈕 A/B 評比**時的臨時 profile（各為生產 profile 的 byte-copy，僅換
> `PROFILE_ID` 等識別欄）。它們會拆掉現行 live lane、永遠不是部署目標，
> 勝出的旋鈕必須 promote 回生產 profile 並在那邊重跑 gate。
> 自 **v1.4.1** 起 `gb10 list` 已把兩者移出服務清單、另列
> 「A/B evaluation only」；`gb10 use <name>` 仍可呼叫。

**量測**：沿用 `bench-ab-deepseek.sh`（C1…C8 × 3 中位數 + 冷 prefill + engine diag
+ 3× 重複 prompt + 自動 Δ 表）與 `bench-prefix-hit.sh`。
**Vision 不能照抄 mainline 的旋鈕也不能照抄它的判準**：V0 的 `cudagraph_capture_sizes`
是 `[1,2,4,8,16,24,32,40,48,56]`（mainline 是 128），且 vision 有 17 個 hotfix
與 `CUDAGRAPH_CAPTURE`／`MTP_NUM_TOKENS` 的取捨不同，故另開 V1–V5 + V-win 格。

**決策門檻（重要，與 mainline 不同）**：mainline 的「7/8 cells ≥+10%」在這條 lane
**不可移植**（單格散佈 ±13.2% tok/s、±6.6 pp acceptance）。定案規則：
**主指標 = `Σ` 八段中位數相加；任何 < ~2% 的 `Σ` 移動視為 boot 變異，必須兩次 boot 同號；
acceptance 與冷 prefill 為副指標；cold prefill 的 32K 這格判定為結構性噪聲，一律不採信。**

**結果**：

| cell | 旋鈕 | Σ vs V0 | 判定 |
|---|---|---|---|
| V0 | （基準，run A/B） | 529.4 / 528.0 | 基準 |
| V1 | 移除 `VLLM_USE_BREAKABLE_CUDAGRAPH=0` | +2.99% / +0.81% | 兩次同號但幅度不穩，且壓 C8 → 不升版 |
| V2 | `--block-size 256→128` | 無 | **無法啟動**（`kv_cache_utils` assert → `Engine core initialization failed`） |
| **V3** | **`--long-prefill-token-threshold 1024→0`** | **+2.58% / +2.94%**（兩次僅差 0.35%） | **升版** |
| V4 | `CUDAGRAPH_CAPTURE 56→8` | −5.19% | 退化 |
| V5 | `MTP_NUM_TOKENS 6→9` | −15.41%、accept −7.25 pp | 最差格 |
| V-win | V1+V3 合體 | +1.91%，**低於 V3 單獨** | 不符合「`V-win ≥ V3` 才留 V1」→ V1 淘汰 |

**升版**：只寫 `cluster-profiles.d/deepseek-vision.conf` **一行**
（`--long-prefill-token-threshold 1024 → 0`），`deepseek.conf` 的 `git diff` 為空。
生產 lane 完整 gate 全過：`cluster-compose-verify` 雙 rank PASS、`gb10 smoke` `HELLO-TP2-OK`、
live container argv 證明**單一旋鈕**（`--block-size 256` / `capture 56` / `k=6 probabilistic` /
`prefix_caching=True` / `BREAKABLE=0` 全同 V0）、`patches/` 兩 lane `diff -rq` 為空、
暖前綴 **8.6× HIT**、261K `1657.7 tok/s` `finish=length`、garble soak 3/3、
3×3 完整性 3/3、`/health 200`、`check-git-sync --block` rc=0。

**⚠️ 生產 lane 的坑（下次別再踩）**：升版後第一次 boot 量到 `Σ 497.7`（比 tune lane
任何一格都低），第二次 boot（conf 完全相同）卻是 **538.1** —— **同一台機器、同一份 conf、
boot-to-boot 差 8.12%**，且 `jit_spike_lines` 1→0、model load 241.4→233.3 s。
最可能是**生產 lane 當次是本 campaign 首次 boot、`~/.cache/vllm-deepseek-vision` 冷**，
重編譯落在量測窗口內；tune lane 連續 8 次 boot 都用同一份熱快取。
**結論：production lane 實測 boot 散佈 8.1% > 效應量 2.7%，因此這條 lane 根本無法驗證
此旋鈕，升版依據取自 tune lane（V3 兩次 boot 吻合 0.35%）。**
→ **操作教訓：生產 vision lane 改設定後先再 boot 一次，再看 benchmark。**

**另外三個 false alarm（都是方法/工具工件，不是真的壞）**：
1. 一則捏造的「V3 hung at 103 lines」poller 讀數；
2. `curl http://…` 未加引號 → `curl: (3) bad range in URL position 2`；
3. **garble soak 用預設 `thinking:true`** → `finish=length` / `content` 空 / `uniq_ratio=0.00`，
   看起來像亂碼，其實是 400 token 被 reasoning block 吃掉（`bench-prefix-hit.sh` L61–L66
   已記載的陷阱）。加 `"chat_template_kwargs":{"thinking":false}` 後 3/3 PASS。
**懷疑 gate 失敗時，先讀機制再判。**

**六個 harness bug 已修**（`ab-run-cell.sh` 三參數全必填、`wait_or_fail()` watchdog
防止 `gb10 wait` 燒 2400 s、V-cell 必須指定 `AB_CONF`/`AB_BASE`、`fail()` 不再吞掉子腳本
錯誤、`bench-c.sh` pipefail、`bench-prefix-hit.sh` 的 `PH_MAX_TOKENS` + `thinking:false`）。

**文件**：`docs/DEEPSEEK_VISION_TUNE_AB_2026-10-07.md`（完整證據與判定）、
README Vision-Exp 區已改成 V0 vs 升版對照。
**範圍紀律**：`deepseek.conf` 全程未動；唯一寫入的生產檔是 `deepseek-vision.conf` 一行。

---

## 2026-10-06/07 — DeepSeek TP2 同 image 調優 A/B（E0–E5）→ E5 promote 進主線

**問題**：在 **pin 住的同一顆 image**（`anemll/dspark-vllm-gx10:0.1.1`，manifest
`sha256:a8394849…`）之下，第三方配方（AlexLJC／twinspark／Reederey87）與主線之間還剩多少
空間？不重建 image、不重拉 image，只動 profile／runtime 層（pull-only 規則全程守住）。

**方法**：新增獨立 lane `cluster-profiles.d/deepseek-tune.conf`，**實驗期間完全不動
`deepseek.conf`**（它同時是 production 與 rollback 目標）。一格一個旋鈕：
`scripts/ab-setcell.sh E<n>` 先把 conf 還原成 `.base` 再套單一改動（附 anchor 斷言 +
`bash -n` + diff 稽核，所以沒有任何一格會繼承上一格的改動）→ `cell.sh E<n>`
（use → wait → compose-verify → smoke → bench）。六格全部冷啟動，互相可比。

**量測**：`scripts/bench-ab-deepseek.sh` = C1…C8 × 3 取**中位數**
（`BENCH_IGNORE_EOS=1`，每 stream 固定 400 tok）+ `BENCH_COLD=1` prefill 32K/131K/200K
+ **engine diag（證明旋鈕真的生效，例如 `draft_sample_method': 'probabilistic'`）** +
3× 重複 prompt 完整性 + 自動印 Δ-vs-E0 表。
`scripts/bench-prefix-hit.sh` = 暖前綴命中探針（同一長 prompt 不加 nonce 跑 3 輪、
`temp=0` 檢查輸出一致性）。

**實測雜訊底（重要，先講這個）**：**decode ≈ ±7 %、prefill ≈ ±8 %**。
E0→E1→E2→E3→E4 的 131K prefill 橫跨 1741–1908 tok/s，其中兩格根本沒動 prefill 相關
設定 —— 所以「單格大跳動」多半是假訊號（E1 的 C5 −20.5 %／C6 +14.5 % 就是）。
只有「跨全部 8 個 C 同向」或「改變結構性 regime」才算發現。

### 結果

| cell | 旋鈕 | Σ tok/s | 判定 |
|---|---|---|---|
| E0 | 基線（≡ promote 前的 `deepseek.conf`） | 594.2 | 參照 |
| E1 | `CUDAGRAPH_CAPTURE` 8→128 | 606.5 (+2.1 %) | ✗ 雜訊內，卻 +16 s 啟動 +1.9 GiB graph pool |
| E2 | `draft_sample_method` greedy→probabilistic | 635.2 (+6.9 %) | ✓ acceptance **8/8 同向**（p≈0.4 %） |
| E3 | prefix caching + SWA-prefix hotfix | 603.7 (+1.6 %) | ✓ 暖前綴 **8.8×**，decode 中性 |
| E4 | `VLLM_USE_BREAKABLE_CUDAGRAPH=0`（inductor 重啟） | 585.2 (−1.5 %) | ✗ 雜訊內；boot 也沒變慢，純粹不賺 |
| **E5** | **E2 + E3** | **655.5 (+10.3 %)** | **✓ 勝出** |

**E5 已 promote 進 `deepseek.conf`**（使用方同意），六個改動：
`ENABLE_PREFIX_CACHING=true`、`draft_sample_method=probabilistic`（k=7 不變）、
`CMD_WRAPPER`（fail-closed，啟動時套 `hotfix-vllm-dspark-swa-prefix.py`）、
`VLLM_PREFIX_CACHE_RETENTION_INTERVAL=4096`、EXTRA_MOUNTS 掛 `${STACK_DIR}/patches`
唯讀、`SYNC_DIRS` 把 `patches/dspark-vision` 佈署到兩節點（node1 沒 repo）。

### production 驗收（2026-10-07 00:18，全過）

promote 後是**在 production lane 上重跑同一套 gate**（不是拿 tune lane 的數字充數）：

- decode Σ **594.2 → 670.7 tok/s（+12.9 %，8 格中 7 格 ≥+10 %）**
- acceptance 中位 **26.9 % → 31.1 %（+4.5 pp，8/8 全正）**
- 暖前綴 **7.6× HIT**（15.50 s → 2.03 s，2065 → 15786 tok/s）
- cold prefill 32K/131K/200K = 1785/1869/1747（±8 % 底內）
- 261K 長文 261021 tok @ **1648 tok/s**、garble soak 3/3（`uniq_ratio` 0.70/1.00/0.83）
- `cluster-compose-verify` 雙 rank、`gb10 smoke`、3×3 完整性、`/health 200`
- 另外單獨驗過 promoted conf 的 render 與 E5 tune **逐字相同**：`PARITY: IDENTICAL`（跑兩次）

**E3 為什麼安全（沒有 hotfix 就不能開 prefix caching）**：cache hit 會讓 DSpark draft 的
128-token sliding window 沒有前綴，verifier 接受**截斷**答案。實測 `PREFIX-OK` 三輪
byte 一致。**E4 是探針的對照組**：caching 關 → `1.1× no-hit`，caching 開 → `8.8× HIT`，
同一支探針、同一 prompt 給出相反結果，所以 E3 的倍率是量測不是巧合。

### 沒有做（勿過度解讀）

- 品質只做了短 prompt 抽查 + 400-token garble soak，**沒有長文風格／事實性 A/B**。
- acceptance 是固定 ~118 tok prompt 上的數字，與自由跑 `bench-c` 的 30–57 % 是**不同口徑**，
  不要混在同張表。
- 8.5×/7.6× 是**暖前綴**才有；首次觸發的 prefill 沒變。

### 本次 commits（Forgejo `origin/main`）

- `4513c3d` `feat(deepseek): same-image A/B harness + deepseek-tune lane`
  （`ab-setcell.sh`、`bench-ab-deepseek.sh`、`bench-prefix-hit.sh`、
  `deepseek-tune{,.base}.conf`、`bin/gb10` whitelist —— 2026-10-07 起
  tune lane 已在 `gb10 list` 改列「A/B evaluation only」，不再是服務）
- `434f166` `feat(deepseek): promote E5 -- probabilistic drafts + prefix caching`
  （`deepseek.conf` 六改動 + README C1…C8 新基線 + AGENTS fact + 本 campaign 文件）

**詳見**：`docs/DEEPSEEK_TUNE_AB_2026-10-06.md`（Cell plan／逐格 Results／Winner table／
Verdict／production acceptance／limits）。
**下次調優起點**：harness 留著，`E6` 候選 = `--long-prefill-token-threshold`、
`--block-size 256`、`--reasoning-parser deepseek_v4`（都在 image 裡，都還沒測）。

## 2026-10-05 — `mimo26flash` 變體定案 MXFP4 + 服務切回 deepseek

- **同日完成的三件事**：① DFlash cliff 探測（A，兩變體皆過）、② NVFP4↔MXFP4 完整 A/B 與
  **最終定案 = MXFP4**、③ 延後調優 **C/D/E** 註記（`repetition_penalty 1.05` A/B、
  `--long-prefill-token-threshold 2048`、tool-parser truncation — 均非現行問題）。
  詳細數據與理由見上一節 bullets 及 `docs/MIMO26FLASH_TP2_2026-10-03.md` §7/§11
  （含「Patch 01 upstream 狀態」：QKV 半邊 = vLLM #57508 同款、image 未含前 MXFP4 不可少；
  `cache_config`/`sliding_window` 兩變體皆必要、upstream 無對應）。
- **Commits**（皆 push origin+github、node0 同步）：`dc49051`（flip NVFP4 跑 cliff）→
  `b34e2e2`（flip 回 MXFP4 + §11 定案與 cliff/upstream 文件）→ `667f666`（C/D/E 註記）。
- **13:32:15 `gb10 use deepseek` 切回主線**：t+8m READY（13:40）、`gb10 smoke` =
  `HELLO-TP2-OK`、status = `deepseek-v4-flash-0731-official` / `anemll/dspark-vllm-gx10:0.1.1`
  / TP2 / **KV 11.01 GiB** / `:1234` health ready；SHA256SUMS gate 兩節點 PASS。
- 操作途中兩個坑（供後續參考）：① 遠端 `pkill -f '<pattern>'` 會殺到**含同一字串的自身
  shell**（指令字串即 cmdline）→ 用 PID 殺；② Windows 側把指令中的 API key 明文
  **自動遮蔽成 `[REDACTED]`** 導致 401 → key 一律在 node0 端執行時從
  `~/docker-stacks/config/cluster.env` 讀取，勿在指令中打明文。
- cliff 探測腳本留在 **`node0:/tmp/dflash-cliff.sh`**（臨時工具，未入 repo）；
  `node0:/tmp/nv-cliff-boot.log`、`/tmp/mx-reboot.log`、`/tmp/deepseek-boot.log` 為當日 boot 記錄。
- **README.md 同步**：2026-10-05 現況註記、部署表加 `mimo26flash` 列、現役改回 deepseek
  （KV 11.01）、新增 mimo26flash benchmark/AB/cliff 章節、`gb10 list`/profile registry/
  node-local layout/`state/` 說明補上 `mimo26flash`。

## 2026-10-03 — MiMo V2.6 Flash MOPD lane 上線（`mimo26flash`，TP2 vLLM + DFlash）

新叢集 lane **`mimo26flash`**：Xiaomi MiMo-V2.6-Flash-**MOPD**（官方 MXFP4 QAT，
revision `2479e2d0`）在 2×GB10 TP2 上以 vLLM + checkpoint 內建 DFlash drafter
服務；cluster-only、互斥，對外 `aeon`、`:1234`、256K、8 併發。完整數據見
`docs/MIMO26FLASH_TP2_2026-10-03.md`。

- 配方：`tonyd2wild/MiMo-V2.6-Flash-DGX-Spark-Recipe`（MIT, `13621bb3`）；image
  `ghcr.io/tonyd2wild/vllm-glm53-flash:sm121-v11-dflash2`（digest
  `sha256:4def0ef6…be85a6`）；3 支 patched vLLM 源碼 + 修好的 dflash config
  vendored 於 `patches/mimo26flash/`（bind-mount，無重建 image）。
- **GHCR 卡關的解法（重要經驗）**：本站對 GHCR CDN 一度掉到 ~0.1–0.5 MB/s 且大層
  反覆 `unexpected EOF`（docker 不續傳單層 → 迴圈）。改用匿名鏡像
  **`ghcr.nju.edu.cn`**（~2–5 MB/s、支援 range），以 manifest digest 驗證與
  ghcr.io **byte 相同**，再 `docker tag` 成 ghcr.io 名稱。`IMG_SHA256` 仍可 pin。
- Model：HF 下載 5h34m（~8–9 MB/s），node0 完成後 rsync 到 node1（CX7 ~350 MB/s）；
  `SHA256SUMS` 154 行，4 檔與 HF LFS sha256 交叉驗證 PASS。
- `cluster-common.sh` 擴充：`BATCHED` / `ENABLE_CHUNKED_PREFILL` / prefix caching
  **未設即不帶旗標**，讓本 lane 完全對齊 recipe；既有 5 lane 渲染逐 byte 不變（已驗）。
- 冷啟 ~16 分（權重 11m18s、engine init 117s）；**KV cache 2,337,906 tokens、
  262144 每請求最大併發 8.92x**（8 併發 256K 裝得下，GMU 0.90）。
- `gb10 smoke` PASS（`HELLO-TP2-OK`）。bench：fixed-length `bench-c` C1 21.1 →
  C8 **67.9** tok/s；`bench-ctx` cold 32K **1553.7** / 131K **1015.4** / 245K
  **724.3** tok/s。（← MXFP4 初測，2026-10-03；**2026-10-05 的正規 A/B
  3×取中位數數字見下**，同為 MXFP4：C1 18.1 / C2 33.9 / C4 53.3 / C8 62.2，
  prefill 32K 1552.8 / 131K 1010.6 / 245K 722.9）
- Tool-call repetition（MOPD 的存在理由）：以 `scripts/bench-toolcalls.py`（重建
  trigger）實測，**所有 run 零重複呼叫、每回應中位 2 calls（最多一次 9 個不重複
  calls）**，對照 RL 文件記載的 148/446 重複、659–709 calls → MOPD 的修復成立
  （caveat：合成 trigger，非 recipe 的 captured body，非受控 MOPD-vs-RL A/B）。
- Multimodal（2026-10-03 啟用）：掛載預建的 `soundfile`+`PyAV`（`${STACK_DIR}/pyextra`
  → `/cache/pyextra` + `PYTHONPATH`）並設 `--limit-mm-per-prompt {image:16,video:1,audio:4}`。
  實測 `scripts/bench-mm-mimo.py`：**image 正確**（形狀/顏色/文字）、**audio 兩種格式正確**
  （轉錄出 password）、**video** object/color 正確、方向判讀為「對角」略有偏差。
  image 吞吐 `bench-mm.sh`：C=1 22.5 / C=4 62.9 tok/s。
- GMU 0.90 評估（2026-10-04）：C=8 soak + C=4×32K prefill 全程，node0 MemAvailable
  最低 6.23 GiB、node1 7.39 GiB，swap 無增長、未重啟 → **0.90 安全，無需調降**。
- NVFP4：`ProCreations/MiMo-V2.6-Flash-MOPD-NVFP4`（W4A16，排除 gguf/，198.83GB）
  已下載**並**同步到 node1（CX7 rsync 329MB/s，9m35s），node0/node1 各一份、
  SHA256 抽驗皆 MATCH。**TP2-only**（194GB 權重放不進單節點 121.69GiB，無
  gb10-single 變體）。
- **NVFP4 評估（2026-10-05）＝通過，並與 MXFP4 完整 A/B**：只改 `BODY_REL` 一項
  （`5ffbf9d` 切 NVFP4 → `b750caa` 切回 MXFP4），其餘欄位與三支 patch 全不動。
  兩側各冷啟 ~16 分、各跑 `scripts/bench-ab.sh`（decode 固定 400tok × C=1/2/4/8 ×
  3 輪 + 32K/131K/245K 冷 prefill）。**相容性全過**：vLLM 認得 `modelopt_mixed`、
  MoE 走 MARLIN、DiffKV 照舊、tool-call/multimodal 皆正常；patch 01 的 `ckpt_tp`
  QKV 分支在 NVFP4 上是死碼（qkv 已被重排成全域 Q/K/V 且降成 F32）但另外兩處
  仍必要 → **三支 patch 照掛**。
  **結果（decode 取中位數 / 冷 prefill）**：prefill **NVFP4 全勝**（32K
  1552.8→**1995.0**、131K 1010.6→**1190.5**、245K 722.9→**809.8** tok/s）；decode
  **看併發**（C1 18.1→**23.3**、C2 33.9→**37.3** NV 較快；C4 53.3→42.6、
  C8 62.2→55.7 MX 較快）；**容量 MXFP4 明顯勝**（KV 16.71→10.58 GiB、
  2,310,732→1,366,981 tokens、256K 併發 8.81x→**5.21x**，consumed
  85.39→91.63 GiB，磁碟 177.8→198.83 GB）。根因是 GB10 無原生 FP4，vLLM 啟動
  即警告改走 Marlin weight-only fallback。**現役＝MXFP4**；回 NVFP4 只需改
  `BODY_REL`+`DISPLAY_NAME` 後 `gb10 use`。詳見
  `docs/MIMO26FLASH_TP2_2026-10-03.md` §11。
- **DFlash cliff 探測（2026-10-05）＝兩變體皆過**：Plaaasma 報的 1024-token
  滑窗 NaN cliff（drafter/target KV dtype 不一致觸發）在本棧無法重現。工具
  `node0:/tmp/dflash-cliff.sh`（長 `ignore_eos` 生成期間每 2s 抓 `spec_decode`
  Prometheus 指標對 token index 看接受率）：counting 2500tok/temp0 兩變體接受率
  **7.000/8 恆定**（NVFP4 與 MXFP4 位元相同的 313 steps / 2191 acc）、essay
  3000tok/temp0.8 過 1024 無崩塌，engine log 0 NaN。400-tok 的 bench 抓不到
  cliff，`>1070 tok` 接受率是 image/draft 變更後的常設回歸檢查。
- **最終決定（2026-10-05）＝留在 MXFP4**（`dc49051` 切 NVFP4 探測後切回）。
  理由：容量 +41%（8.81x 撐得起 NUMSEQ=8）、decode 差距多在噪聲內（僅 C8 是
  MX 明確贏）、官方 QAT + SHA256SUMS 已驗證 + 磁碟省 21GB/節點；NVFP4 唯一紮實
  優勢 prefill (+12~28%)，留作一鍵切換。Patch 01 upstream 狀態（research
  2026-10-05）：QKV/`ckpt_tp` 半邊 = vLLM #57508 同款但 image stock 未含 →
  MXFP4 上仍必要、image 升級後才可刪；`cache_config`/`sliding_window` 兩處兩
  變體皆 load-bearing 且 upstream main 仍無對應 → 無論如何都要掛。
- **緩辦調優註記（2026-10-05，非現行問題）**：C = `repetition_penalty 1.05`
  override 的 A/B、D = `--long-prefill-token-threshold 2048` 評估、E =
  tool-parser truncation 修正（Plaaasma kit）——三項均記錄在
  `docs/MIMO26FLASH_TP2_2026-10-03.md` §7 open items，日後要調優再做。

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
- 啟動參數：`nvfp4_ds_mla` KV、`flashinfer_b12x` MoE、DSpark `k=6 probabilistic`、`MAXLEN=262144`、`NUMSEQ=8`、`BATCHED=16384`、`GMU=0.80`、`CUDAGRAPH_CAPTURE=56`、**prefix caching ON（搭 `dspark-swa-prefix` hotfix + `VLLM_PREFIX_CACHE_RETENTION_INTERVAL=4096`）**、`VLLM_USE_BREAKABLE_CUDAGRAPH=0`、`--limit-mm-per-prompt {"image":8}`、**`--long-prefill-token-threshold 0`（2026-10-07 由 1024 改，本 repo 唯一的 vision 調優升版，見「2026-10-07」章節）**、`--generation-config vllm`、reasoning/tool parser `deepseek_v4`。

### 權重版本釐清（重要）
- MiaAI 釘 `86f746b36186f0e567729a5c06a8c918caba82a9`；本機/節點是 `6821d6ad3681a4b137b066b76094fa82ebd0a380`（= HF main HEAD）。
- 兩者差異**僅 README/.eval_results**；**48 shards + config.json + tokenizer + encoding/ + inference/ 全部 byte-identical** → **不需重下載**。

### 零污染保證（deepseek 未受影響）
- `cluster-profiles.d/deepseek.conf`、`bin/gb10` 未動；`CMD_WRAPPER`/`SYNC_DIRS` 未設時**渲染／行為完全不變**（已用 HEAD 版 `cluster-common.sh` 對現版渲染 deepseek，**逐 byte 相同**）。
- 共用 `/cache/huggingface/vllm-cache` 的 compile cache；`cluster-up` 每次 boot 都清 FlashInfer autotune cache，且 vLLM 快取以 model/config 為 key。
  > **2026-09-20 後續更新**：此共用路徑已退役；每個 lane 改用獨立的 `~/.cache/vllm-<profile>`（cluster-only）或 `~/.cache/vllm-<profile>-{cluster,single}`。

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

- **2026-10-07 vision campaign 已收尾**：當日 13:53–15:05 TP2 由 vision 調優 campaign
  佔用（現役 profile 一度為 `deepseek-vision`，已套 V3 升版
  `--long-prefill-token-threshold 0`，生產 gate 全過）；**15:05 已以 `gb10 use deepseek`
  切回 mainline** —— `status: ready`、node0+node1 up、`/health` 200、
  `gb10 smoke` `HELLO-TP2-OK`、KV 11.37 GiB。以下 2026-09-29 的紀錄即現行狀態。
- 現役＝**deepseek（DeepSeek V4 Flash 0731 fp8 DSpark mainline）** —— 2026-09-29 以
  `gb10 use deepseek` 由 qwen38flash 切換（`cluster-down` 拆掉舊 TP2 → free node1 singles →
  cold start）。當日共 boot 兩次，皆在一次到位後量測：
  - ①切換：`22:30:59` 啟動 → `gb10 wait` 回報 READY `22:38:43`（約 **7 分 44 秒**），KV **12.02 GiB**。
  - ②`state/last-cluster-profile` 修正後的端到端驗證：`22:47:33` 啟動 →
    **`state/boot-ready.deepseek` = `22:55:02`**（`gb10 wait` 於下一次 5 秒輪詢回報 `22:55:07`；
    約 **7 分 34 秒**），KV **12.15 GiB**（現役即此 boot；`gb10 wait` 的時間戳是輪詢時刻，
    `boot-ready.*` 才是啟動端的權威時間）。
  - `gb10 status` = ready／node0+node1 up／image `ghcr.io/anemll/dspark-vllm-gx10:0.1.1`／
    model `deepseek-v4-flash-0731-official`／TP2；`/v1/models` id `aeon`、max_model_len 262144；
    `gb10 smoke` = HTTP 200 `HELLO-TP2-OK`（prompt 16 / completion 9 tokens）。
  - KV 對照：2026-09-06 baseline 記 **12.93 GiB**，兩次皆略低，差異在 GB10 boot 間離散範圍內
    （本次未改任何 profile，渲染與既有 lane 一致）。
  - 切回用 `gb10 use qwen38flash`（再往前是 deepseek-vision）。
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
  移入 `~/_archieve/aeon-vllm-omni-cleanup-20260920/`；刪除可再生的 `*_029_orig.py`。

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
- **全 lane 實測**：qwen38flash / deepseek / 27b / 35b / deepseek-vision（TP2）與 27b single(node0)、
  35b single(**node1**) 皆 `READY`；`cluster-compose-verify` 兩 rank PASS、`gb10 smoke` OK。
- **`~/_archieve` 已整批刪除**（兩節點），首頁根僅剩標準目錄。

### 已完成（2026-09-20 後續之三）— qwen38flash 加測

- **固定長度 benchmark**：`bench-c.sh` 新增 `BENCH_IGNORE_EOS=1`（每 stream 恰好 MAX_TOKENS）。
  qwen38flash C1/C2/C3/C4/C8 = **41.7 / 55.3 / 93.7 / 105.0 / 161.1 tok/s**（與變動長度中位數一致 ±6%）。
- **prefill 曲線**（`bench-ctx.sh`）：32K 2644 / 131K 2900 / 200K 2717 / 245K **2630** tok/s。
- **圖片輸入**（`bench-mm.sh`）：1 圖 ≈597 prompt tok；1img C=1 40.5、4img C=1 32.7、1img C=4 86.3、
  1img C=8 **135.7** tok/s，無錯誤（未設 `--limit-mm-per-prompt`，預設允許 ≥8 張）。
- **多輪穩定**：新增 `scripts/bench-multiturn.sh`；6 輪 **6/6 clean**。
- **`PLE_OFFLOAD=true` 對 TP2 不可行**：vLLM 直接拒絕（`Unsupported settings: nnodes=2`）——
  它是單節點功能。lane 維持 `PLE_OFFLOAD=false`；`ULIMITS` 欄位仍通用（`nofile` 實測生效）。

### 已完成（2026-09-20 後續之四）— SGLang 路線廢棄 + README 整併

- **移除 SGLang launcher**（原始需求「廢棄 SGLang 路線提案與記錄」）：刪除 `build_sglang_args()`
  與**所有** `ENGINE == "sglang"` 分支——`cluster-common.sh`（`build_sglang_args` /
  `_compose_service` / `inspect_profile`）、`cluster-up`（`ENTRY`）、`cluster-compose-verify`
  （`exp_entry_json` / `exp_cmd_json`）。`unset` 清單並移除 12 個 sglang 專屬欄位
  （`TP_SIZE` `NNODES` `MEM_FRACTION_STATIC` `CHUNKED_PREFILL_SIZE` `CUDA_GRAPH_MAX_BS_DECODE`
  `MAX_RUNNING_REQUESTS` `MOE_RUNNER_BACKEND` `SPEC_MOE_RUNNER_BACKEND` `SPEC_ALGORITHM`
  `DISABLE_SHARED_EXPERTS_FUSION` `API_HOST` `MODEL_ID`）。`ENGINE` 保留（預設 `vllm`）但已固定。
  **驗證**：5 個 lane 的 `args(rank0/rank1)`／`env`／`mounts`／`compose` 移除前後**逐位元不變**；
  `bash -n` 全過；repo 內 `sglang` 參照 = 0。已於 `AGENTS.md` 記錄。
- **README benchmark 章節整併**：不再累計歷史——4 條 dated 更新註記合併為單一「2026-09-20 現況」；
  **每個模型只保留最新一次實測**；刪除已被取代的 `DeepSeek … 歷史結果` 表與舊 maintenance-repo 報告連結；
  27B/35B 去掉 09-11 基準比較等歷史敘述（保留 health-timeout 教訓與 FlashInfer 踩雷說明）；
  cache root 說明改為 `~/.cache/vllm-<profile>[-cluster|-single]`。
- **`~/_archieve` 整批刪除**（兩節點；原本集中於此的備份/poc/log 一併消失）。
- **修掉 stale ready marker 問題**：`cluster-down` 與 `gb10-single stop_file` 過去不清
  `state/boot-ready.*`，停掉 lane 後 `gb10 wait/status` 會誤報 READY。

## 定期檢討追蹤

> 下列事項不是「待辦」，而是**定期檢討**項目（2026-09-20 標註）。檢討時點：每當 `patches/` 上游或 image 更新，或每次進行 27b/35b 重大變更時。

1. **Patches 上游追蹤**：`patches/dspark-vision/` pin 在 MiaAI commit `97e8733…`（23 檔）；`patches/qwen38flash/` 已於 2026-09-29 由 `d2f54b7…` 改 pin 到 **`2c86a1d0…`（10 檔）** —— 原 8 檔在該 commit 經 blob 比對**逐 byte 相同**，另新增 `patch_block_drop.py` / `patch_determinism.py`（皆見各自 `NOTICE.md`）。上游更新時需 **re-vendor** 並重新比對 byte。
2. **Vision 進一步驗證（可選）**：長圖文混搭 prompt、多輪 agent chain 長時間穩定性。
3. **已收斂（2026-09-20，原 3/4/5 項）**：27b/35b/deepseek/deepseek-vision/qwen38flash 全部在新 node-local 佈局下 boot 驗證（`health` 200 + `cluster-compose-verify` 兩 rank PASS + `gb10 smoke` OK），`$$` 逃逸、per-lane cache、STACK_DIR materialize、統一 log 皆實證；單機 27b(node0) 與 **35b(node1)** 亦 READY。`bench-c.sh` 已加 `BENCH_IGNORE_EOS`（固定長度）；qwen38flash 的 prefill 曲線／圖片輸入／多輪穩定已測；**`PLE_OFFLOAD=true` 確認對 TP2（nnodes=2）不可行**，維持 false。
4. **DeepSeek-V4.1-Flash EXL3（2× GB10）— 已查核、暫不採用（2026-09-29）**：完整證據（兩顆 image 的 digest、TP=2 硬限制、各線 benchmark、論壇引述）見 **`docs/DSV41_FLASH_EXL3_2X_SPARK_EVAL_2026-09-29.md`** 與下方小節。檢討時點：上游出現**已發佈**的 2-node image，或有人驗證「Mia image + sfxnz 2.0bpw pack」可載入時。

### DSV4.1-Flash EXL3 2×GB10 選型查核（2026-09-29，本機）

> 觸發：sfxnz/DeepSeek-V4.1-Flash-EXL3 2.0bpw Viterbi（CyberQ 2026-09-29）。**未變更任何 runtime 檔**（未新增 profile、未改 `cluster-profiles.d/`、`bin/gb10`、`scripts/`），未 pull image、未下載權重。使用者約束：**不自行 `docker build`**，目標是可下載的成熟 image（最多接受 runtime patch）。

- **sfxnz 的衍生 image 沒有發佈**：`dsv41-flash-exl3-sm121:canonical-e14` 在任何 registry 都查無（`sfxnz/*` Docker Hub namespace = 0 repo），只有 `docker build` 配方。其**基底** `vllm/vllm-openai:deepseekv41-flash-0909` 反而是官方公開 tag、arm64 digest `sha256:d84a1232…77d58`（＝其 Dockerfile `FROM` 逐字相同）→ 基底可 digest 釘選。
- **兩顆可下載的 arm64 image（digest 已取得，匿名可拉）**：
  - `ghcr.io/miaai-lab/deepseek-v4.1-flash-exl3-2x-dgx-sparks:latest` → `sha256:2f0cf3adc0f989c1d446be274df864eb799630175f604c3b22b71b7205971dce`（**專為 2×GB10 / TP2 / CX7 / sm_121a**；EXL3 **2.9bpw/mul1**、196 GiB；DSpark 內建；**~26 tok/s**）。
  - `littlecedar/dgx-spark-dsv41:exl3a` → `sha256:71e23ff986f4ab58353bfd0c71062d6d256c290edca55bf7773a779f5076128d`（= **tonyd2wild `vllm-dsv41:exl3a` retag**，label `kai.exl3a=cuda-exl3-6a1ffc34`；**TP3/TP4/TP6 reference lane**；**必配** `mods/mount-dsv41-exl3-patches`，否則 Engram 留 UMA、約 25 分後 OOM）。
- **TP=2 硬限制（VERIFIED）**：littlecedar `recipes/ds4/AGENTS.md` §3 以 cluster-RAM 預算證明 3.5bpw 線 TP=2 不可行（非 Engram 權重 ~257 GB vs 可用 220 GB），故其 registry **無 TP2 recipe**。TP=2 唯一可行的是 **2.0bpw** pack（routed experts ~133.6 GiB → **~72 GiB/rank**）。
- **benchmark 對照（單路 decode）**：Mia 2.9bpw TP2 **~26**｜sfxnz 2.0bpw TP2 **41.3–44.9**（L.A.I.L 42.6、prose c1 50.4）｜exl3a TP3/TP4/TP6 = 34.3 / 38.8 / 40.0。littlecedar 的 DSpark **k-sweep（13 boots）**顯示 **k=3 優於上游預設 k=5**（k=1 在 C8 +27%），**k=6 非法**（須為 `n_predict=5` 的因數）。GB10 boot 間離散度 7–25%，單次開機不可排名。
- **NVIDIA 論壇口碑**（討論串 `382725`，187 篇）：`say3` 對 Mia 2× EXL3 的評語是「**26 tok/s… too slow**」；`0rand`「**2bpw … not for any production use**」；`stu.miller`（生產使用者）指 4.1 的 TP4 recipe「**hacky**」且他人 recipe **12 次開不起來**，並明確說 **DS4 Vision-Exp 在 2 sparks 上 works great**；`helge` 則說 2.9bpw 品質損失「within narrow limits」但 TP=4 速度優勢顯著。
- **為何不採用**：免 build 的成熟 image 只有 ~26 tok/s；要 42–50 tok/s 就得用 sfxnz stack（＝要 build）。兩者在「不自行 build」約束下無法同時成立 → 維持 2-Spark 多模態由 `deepseek-vision` 承接。
- **重啟最短路徑**：① 直接用 Mia 那顆（`IMG_SHA256` 可沿用現有 registry gate）② 探針「Mia image + sfxnz 2.0bpw-mcg-viterbi pack」是否可載入（mul1 vs mcg、per-tensor K-map、`exllamav3 v1.4.5` 相容性**未知**）→ 成功即「免 build + 44 tok/s」。
- **授權**：sfxnz scripts MIT／權重 MIT／`vllm-exl3` **AGPL-3.0**；tonyd2wild patch Apache-2.0 vLLM 衍生；MiaAI-Lab 系列 AGPL-3.0。未來採用須比照 `patches/qwen38flash/NOTICE.md` 慣例（pin + sha256），且不得再散布衍生 image。

### gb10 `state/last-cluster-profile` 修正（2026-09-29）

- **問題**：`state/last-cluster-profile` 被 `bin/gb10`（`restart` 未帶參數時的預設值）與 README
  描述為「上次選用的 cluster profile」，但**全 repo 沒有任何地方寫入它** —— 本次切到 deepseek
  後實測該檔不存在 → `gb10 restart`（無參數）永遠回退 `27b`，不會沿用剛用過的 profile
  （誤操作陷阱：想 restart deepseek 卻拉起 27b）。
- **修正**（`e626298`）：`bin/gb10` 的 `use|start` 與 `restart` 在背景 boot 啟動後寫入該
  profile ID；placeholder 分支在該行之前就 short-circuit，仍不會寫入。檔案在 `.gitignore` 內，
  屬執行期產物，因此不會讓 `check-git-sync.sh --block` 的乾淨樹判定失敗。README 的 `state/`
  說明同步改為「由 `bin/gb10` 寫入／讀取」。
- **驗證**：node0 上 `bin/gb10` **CR bytes = 0**（LF）、`bash -n bin/gb10` OK（shellcheck 未安裝，
  略過）；修正前 marker **不存在** → `gb10 use deepseek` 後 marker = **`deepseek`**，且該次 boot
  READY `22:55:07`、`gb10 smoke` HTTP 200。

### 上游查核紀錄（2026-09-29，本機）

> 觸發於 `patches/` 上游追蹤（上列 #1）。**未變更任何 runtime 檔**，僅記錄查核結果。

- **Anemll（`Anemll/dspark-vllm-gx10`，image 來源）— 無更新：**
  - GHCR `tags/list` 僅 `0.1.0`、`0.1.1`；tag **`0.1.1` digest 仍為 `sha256:a83948492cf13df455170fb42885f5ef4db54fefe0feff0f841ecbff464ac9d8`**
    ＝本 repo `IMG_SHA256` → **未重新推送、無新 image**。
  - GitHub Releases 最新仍 **`v0.1.1`**（2026-07-15，tag commit `47503f8e`，"Fix long-prefill crash caused by B12X route-pack JIT"）。
  - `main` HEAD＝**`081fda97`**（2026-09-03），比 tag 多 3 個 commit，唯一實質變更為
    **PR #2 `4afc5e7e`＝DSpark draft SWA prefix-cache 修正**（作者 Simon Blom，merge `f2ea1f37`）。
    該修正**不在 image 內**（image 建於 `47503f8e`）；本 repo 已以
    `patches/dspark-vision/hotfix-vllm-dspark-swa-prefix.py`（*opt-in port of Anemll#2*）承載 → **無缺口**。
  - 未併入 image 的 open PR：#6（kv_offload `/dev/shm` leak）、#7（packed block stride）、#12（DSpark graph
    replay safety）、#13（torch profiler）；open issues 待觀察：#3（MTP=5 repeats reasoning）、#8（TileLang
    重編譯後 freeze）、#9/#10（tool-call path）、#11（TP=2 rank divergence wedges GPU）。
- **MiaAI-Lab（`MiaAI-Lab/DeepSeek-v4-Flash-DSpark-2x-DGX-Spark`，patches vendor 來源）— 無更新、無漂移：**
  - `main` HEAD＝**`97e8733238f81f5fdc44b241f8996a7858825744`**（2026-09-16），**與本 repo pin 相同**；
    `compare(97e8733…HEAD)` = **`identical`（ahead 0 / behind 0）**，自 pin 後 `main` 無新 commit。
  - **Byte 比對**（`git hash-object`，走 git filter 以免 Windows CRLF 假陽性）：`patches/dspark-vision/` 全部
    **23 個 payload 檔 = 8 個 `hotfix-*.sh` + 10 個 `hotfix-*.py` + 5 個 `vision_exp/*.py`，23/23 blob SHA 相同**
    → **無需 re-vendor**。（`patches/dspark-vision/NOTICE.md` 為本地自撰，不列入比對。）
  - 上游 `patches/` 另有本 repo **刻意未納入**的 hotfix（`hotfix-vllm-dspark-block-k.py`、
    `hotfix-vllm-c128a-prefill-cache.py`、`hotfix-vllm-issue117-shm-ring-buffer.py`、
    `hotfix-vllm-issue191-toolcall-failclosed.py`、`hotfix-dsv4-issue141/144/31-v2` 等）— 非更新，屬既有路線差異。
  - 追蹤待辦（僅記錄，未動作）：open PR #267（agent clients + prefix cache）、#256（NFS root_squash）、
    #220（disk-backed KV cache）、#253（ci gate compose/hotfix）、#152（#82 loop-breaker）、#126（crash precursor observer）。
- **註（雙 remote 同步）**：本次僅本紀錄 commit。已推送至**兩個 remote**：Forgejo `origin`（`829522`）與
  GitHub `sawaichi9527/ai-gb10-cluster-runtime-manager`（本機為此新增 remote 名稱 `github`）；兩邊 `main`
  皆為 `d2bd689`。推送時一併把 GitHub 缺少的 **7 支分支**（`keystone`、`feature/tp2-profile-registry`、
  `feature/tp2-qwen38-flashnext`、`experiment/deepseek-v4-{128k,256k,393k}-r1`、`experiment/deepseek-v4-dspark-k5-r2`）
  與 **2 個 tag**（`v1.0.0`、`v1.1.0`）補齊 → 兩邊 refs 已 **1:1 一致（17 分支 + 3 tag）**。
- **node0 同步（2026-09-29）**：在 node0（`spark-25d5`／`192.168.23.215`／user `eye`）執行
  `git pull --ff-only`，由 `48b2813` 快進、僅動 `handoff.md`、工作區乾淨。node0 checkout 追蹤
  `origin/main`（Forgejo）；每次 push 後在 node0 再 pull 一次即可對齊。
- **文件勘誤（同次）**：`AGENTS.md`「Canonical repo path」與本檔開頭原寫 node0 checkout 為 branch
  `keystone`；2026-09-29 實測**實為 `main`**（`UPSTREAM=origin/main`、工作區乾淨），兩處已更正。
  `keystone`（`a5fcc54`）仍存在於兩個 remote，但已於 `496c9b1` 併入 `main`、**非**現役 checkout。

### 上游再查核（2026-09-30，本機）

> 觸發：使用者要求確認 `deepseek` 與 `deepseek-vision` 的來源配方與 docker image 是否有更新。
> **結果：皆無有效更新。** 只用唯讀查核（registry tags/digest、GH repo、HF commit 比較、
> node0 `docker ps`/`inspect`），**未變更任何 runtime/profile/檔案設定**。完整證據見
> `docs/DEEPSEEK_UPSTREAM_REVERIFY_2026-09-30.md`。

- **Image（兩 lane 共用）— 無更新**：`ghcr.io/anemll/dspark-vllm-gx10` `tags/list` 僅 `0.1.0`/`0.1.1`，
  `0.1.1` digest 仍 `sha256:a8394849…`（＝`IMG_SHA256` 逐字相同）；node0 `cluster-node0` 現役
  `@sha256:a8394849…` 同 pin。
- **vision 配方（MiaAI）— 無更新**：`main` HEAD 仍 `97e8733…`（= vendored pin），README 仍用
  `ghcr.io/anemll/dspark-vllm-gx10:0.1.1`。
- **官方權重 — 首度補查（09-29 未查）：**
  - 0731（deepseek body）：pin `9e165c30…` = 官方發佈 commit；其後 upstream 僅 **1 個 docs-only**
    commit `7872f01b`「add sglang cookbook to model card (#20)」→ **權重未變**。
  - Vision-Exp（deepseek-vision body）：pin `6821d6ad…` = HF `main` HEAD（一致）→ 無更新。
- **同族更新模型**（`deepseek-ai/DeepSeek-V4.1-Flash`）為另一款模型、非本 lane 之更新，且已於
  `docs/DSV41_FLASH_EXL3_2X_SPARK_EVAL_2026-09-29.md` 判為 2×GB10 不採用。
- **淨結論**：兩 lane 現行 image／配方／權重皆為**當下最新且正確**，**無需任何變更**。

### 上游再查核（2026-09-30，27b／35b）

> 觸發：使用者要求確認 `27b` 與 `35b`（cluster TP2 與單機 TP1 皆同）的 docker image 與
> HuggingFace 模型來源「自 2026-09-19 之後」是否有更新。**結果：皆無更新。** 唯讀查核
> （registry tags/digest、HF commit、node0 `docker inspect` + 本機快照），**未變更任何 runtime/profile**。
> 完整證據見 `docs/QWEN_27B_35B_UPSTREAM_REVERIFY_2026-09-30.md`。

- **Image（兩 lane 共用）— 無更新**：`ghcr.io/aeon-7/aeon-vllm-ultimate` 最新 dated tag 仍
  **`2026-09-18-v0.29.0-omni`**（digest `sha256:cc91c515…` ＝ 本 repo pin、node0 同值）；
  `2026-09*` dated tag 僅 `09-07-reasoning-eos`／`09-11-v0.29.0-omni`／`09-18-v0.29.0-omni(×2)`，
  **無 09-19 後或 10 月 tag**；`latest` 指向同 digest。（`edge` 為 rolling dev、不跟隨。）
- **HF 來源（四個）— 無更新**：
  - 27B body `AEON-7/Qwen3.8-27B-AEON-ULTIMATE-UNCENSORED-NVFP4-MIXED` → `282e6775`（**09-18**，
    即 pin image `2026-09-18-v0.29.0-omni` 的同日配套 commit）
  - 27B drafter `z-lab/Qwen3.8-27B-DFlash2`（git clone HEAD `50307d4c` = 上游 HEAD）（**08-19**）
  - 35B body `AEON-7/Qwen3.6-35B-A3B-heretic-NVFP4` → `a4837491`（**07-15**）
  - 35B drafter `AEON-7/AEON-DFlash-Qwen3.6-35B-A3B` → `7f5324ae`（**06-28**）
- 上游基底（`Qwen/Qwen3.8-27B` 08-14、`Qwen/Qwen3.6-35B-A3B` 04-24、`tvall43/Qwen3.6-35B-A3B-heretic`
  04-16、`incoai/Qwen3.8-27B-DFlash2` 09-17、`AEON-7/Ornith-1.0-35B…` 07-15）亦全部 ≤ 9/17。
- **淨結論**：兩 lane 現行 image／模型來源皆為**當下最新且正確**，**無需任何變更**。

### 版本標記（2026-09-29）

- 在 `main` 打 **annotated tag `v1.3.0`**（接續既有 `v1.2.0`），正式標記本線的穩定狀態。
- **既有 tag 全部保留、未改動**：`v1.0.0`（→ `496c9b1`，2026-09-10）、`v1.1.0`（→ `71ccf20`，2026-09-10）
  皆為 annotated；`v1.2.0`（→ `ffd02ea`，2026-09-13）為 lightweight。
  （註：`v1.0.0` 早已於 2026-09-10 用於「keystone 併入 main」，故本次接續為 `v1.3.0` 而非重用 `v1.0.0`。）
- 標記後同步：`main` 與 tag 推至 Forgejo `origin` 與 GitHub `sawaichi9527`，node0 再 `git pull`
  並 `git fetch --tags`。
- **`v1.3.1`（同日稍晚）**：在 `main` = `276348c` 打 annotated tag，並在 GitHub 建立本 repo 的
  **第一個 Release**：
  <https://github.com/sawaichi9527/ai-gb10-cluster-runtime-manager/releases/tag/v1.3.1>
  （以 API 建立，憑證取自本機 GCM 既有的 github 憑證，**未寫入任何檔案**。）
  動機：`v1.3.0`（`2474cf8`）早於本次 qwen38flash 對齊與 bench 協定，任何從 tag／Release
  進入的人都會看到舊 README；`v1.3.1` 才涵蓋 GMU 0.80／prefix caching ON／block-drop、
  determinism 預設 ON、bench 協定與冷探針。
- **`v1.3.2`（同日稍晚，docs-only）**：`168cb99` —— README「已部署服務」表把 qwen38flash 由
  `deployed（09-20 上線實測）` 改為 **`deployed（09-29 重新驗證）← 現役`**（GMU 0.80／prefix
  caching ON／determinism 預設 ON），並更新章節標題與簡介（GMU 0.835→0.80、spec config 補
  `disable_eagle_block_drop`／`index_share_for_mtp_iteration`、「5 個 patcher」→ 10 檔案 pin
  `2c86a1d0`、KV 34.01→29.15 GiB）、MTP A/B 標註為 09-20 量測；另修掉兩處**錯誤**描述
  （qwen38flash 非單機 placeholder；`runtimes.d/{qwen38flash,glm53flash}.conf` 已於 09-20 刪除）
  與 35b maxlen `131072`→`262144`。同樣建了 GitHub Release，並在 v1.3.1 的 Release 說明末尾
  補上指標。**無 runtime 變更**。
- **`v1.3.3`（2026-09-29，docs + 一處 CLI 修正）**：`9bb2006` —— ① 新增
  `docs/DSV41_FLASH_EXL3_2X_SPARK_EVAL_2026-09-29.md`：DeepSeek-V4.1-Flash **EXL3**（2× GB10）
  選型查核，含兩顆可下載 arm64 image 的 digest、TP=2 residency 硬限制、各線 benchmark 與
  NVIDIA 論壇口碑 —— **研究用，未新增 lane、未變更 runtime**。② 修正 `state/last-cluster-profile`
  從未被寫入的缺口（`e626298`）：`bin/gb10` 的 `use|start` 與 `restart` 於背景 boot 啟動後
  寫入該 profile ID，README 的 `state/` 說明同步改為「寫入／讀取」。③ README 首頁（`9bb2006`）
  把現役自 qwen38flash 改為 **deepseek**（KV 12.15 GiB、`gb10 smoke` = `HELLO-TP2-OK`、
  cold boot 約 7.5 分），並加註「已評估、未新增 lane」與 `gb10 restart` 無參數回退的說明。
  唯一程式碼變更即 `bin/gb10` 的標記寫入（15 行內），**無 profile/image/args 變更**。
  **GitHub Release 已建**（`id 399323160`，以 API 建立，憑證取自本機 GCM 既有的 github 憑證，
  **未寫入任何檔案**；先前一度以為取不到憑證，實為 pwsh pipe `git credential fill` 的編碼瑕疵 ——
  以 LF-only 檔 + `cmd /c` redirect 即可正常取得，與 v1.3.2 相同）。
- **`v1.3.4`（2026-09-30，docs-only）**：`a92d2bc` —— 兩個**上游再查核**紀錄：①
  `docs/DEEPSEEK_UPSTREAM_REVERIFY_2026-09-30.md`（`deepseek`／`deepseek-vision` 的 image／配方／
  官方權重皆無更新；首度補查官方權重 commit 比較）②
  `docs/QWEN_27B_35B_UPSTREAM_REVERIFY_2026-09-30.md`（`27b`／`35b` 共用 image 最新 dated tag
  仍 `2026-09-18-v0.29.0-omni`、四個 HF 來源自 09-19 起皆無更新）。README 首頁同步兩則 dated note。
  **無 runtime／profile／程式碼變更**。含本日前述 `v1.3.3` tag 與其 Release 的紀錄 commit（`0869c39`／`6fa388b`）。
  **GitHub Release 已建**（`id 399699345`，比照 v1.3.1／v1.3.2／v1.3.3；以 API + 本機 GCM 憑證，**未寫入任何檔案**）。
- **`v1.4.0`（2026-10-05，新 lane — minor bump）**：`6aff00d` —— 自 v1.3.4 起 24 個
  commit 全為 `mimo26flash`：① lane 上線（`b553426`..`2a0e433`：MXFP4 QAT + tonyd2wild
  image + DFlash2 n=7、三 patch、256K/8-way、GMU 0.90、TP2-only）② 驗證（tool-call 重複
  探測零重複；multimodal image/audio/video 全過）③ NVFP4 變體 A/B（`scripts/bench-ab.sh`：
  prefill NVFP4 +12~28%、容量 MXFP4 +41%、decode 差距多在噪聲內）④ DFlash cliff 探測
  **兩變體皆過** → **定案 MXFP4**，patch 01 upstream 狀態與延後調優 C/D/E 註記（docs §7/§11）
  ⑤ README/handoff 同步（現役切回 `deepseek`）。annotated tag 打於 `6aff00d`（本記錄
  commit 之前，比照 v1.3.x 慣例）。**GitHub Release 已建**（`id 403407422`，比照
  v1.3.1～v1.3.4；以 API + 本機 GCM 憑證，**未寫入任何檔案**）。
- **`v1.4.1`（2026-10-07，patch）**：`cc76cbd` —— 自 v1.4.0 起 **11 個 commit**，全是
  **同 image A/B 調優與其記錄**，**沒有新增部署服務 lane**（故判級為 patch；`-tune`
  profile 不算服務，見 ④）：① mainline `deepseek` E0–E5 → **E5 promote**
  （decode C1..C8 median Σ 594.2→670.7 tok/s **+12.9%**、acceptance 26.9→31.1%
  **+4.5pp**、暖前綴 prefill **7.6×**；E1/E4 判噪聲／回歸；production gate 2026-10-07
  全過）② `deepseek-vision` V0–V5 + V-win → **只 promote V3**
  （`--long-prefill-token-threshold 1024→0`，兩次 boot Σ +2.6%／+2.9%、acceptance 中性；
  `deepseek.conf` 全程未動）③ A/B harness（`ab-setcell.sh`、`ab-run-cell.sh`、
  `bench-ab-deepseek.sh`、`bench-prefix-hit.sh`）與兩條 eval-only lane
  （`deepseek-tune{,.base}.conf`、`deepseek-vision-tune{,.base}.conf`）
  ④ **`gb10 list` 把兩條 tune lane 移出服務清單**（改列「A/B evaluation only —
  NOT services」；`PROFILES_BY_NAME` 保留，`gb10 use <name>` 仍可呼叫）。
  annotated tag 打於 `cc76cbd`（本記錄 commit 之前，比照 v1.3.x／v1.4.0 慣例）。
  **GitHub Release 已建**（`id 405498459`，比照 v1.3.x／v1.4.0；以 API + 本機 GCM
  憑證，**未寫入任何檔案**）。
- **`v1.5.0`（2026-10-08，新 lane — minor bump）**：`3201363`（README「已部署服務」正式
  列入 `deepseek-nvfp4` 為**現役** + benchmark 區塊重寫 + 本檔第 4 行條目）。自 v1.4.1 起
  **13 個 commit**（`b458133`…`3201363`）—— ① lane Phase 1–2 建置（`1f8a1e8` profile +
  bin 白名單、`7cef7d5` 每節點 image digest pin、`3a9b7bf` 資產兩節點驗證）② **Phase 3
  上線**（`10fff38` seccomp `SECURITY_OPT`、`d2b090d` `--load-format safetensors`、
  `2cdec55` compose-verify SecurityOpt subset、`c0ef7fd` **DSpark draft MXFP4 根因 hotfix**
  —— 共享 NVFP4 quant dict 把原生 MXFP4 的 `mtp.*` draft 建成 ModelOptNvFp4，上游
  #49133 closed unmerged；全 gate PASS、成為現役）③ `f2eb2dd` `bench-c.sh` metrics scrape
  補 auth + C1–C8 記錄（47.1→**129.9 tok/s**、accept 41–50%）④ `d7bda45` **NVFP4 KV
  （`nvfp4_ds_mla`）A/B 負結果**（三重硬閘，回退 fp8）。使用者裁定主線 `deepseek` 先不
  恢復。**annotated tag 重建一次**：初版 message 誤植「12 commits」，經使用者授權在**尚無
  Release 指向時**刪兩端重建為 13，無痕。**GitHub Release 已建**（`id 406384910`，
  比照歷版；以 API + 本機 GCM 憑證，**未寫入任何檔案**）。
- **`v1.6.0`（2026-10-09，兩條生產 lane 配方換代 + 歸檔結構 — minor bump）**：`84f343c`
  —— 自 v1.5.0 起 **10 個 commit**（`5ef23d0`…`84f343c`）—— ① `deepseek-vision`
  **配方繼承**：eugr-b12x + Vision-EXP-ablit 三 boot 對決過關（B1/B2 decode 持平
  535.3/545.9 vs 538.1、prefill +9~14%、prefix-hit 50.9× **無需任何 hotfix**；唯一
  升版旋鈕 `CUDAGRAPH_CAPTURE 48→56`），原生 vision、`CMD_WRAPPER`/`SYNC_DIRS`/patches
  全撤（`8a3cfc3`、`9c350da`、`50372b3`）② 主線 `deepseek` **配方繼承**：eugr-b12x +
  Dspark-Ablit 對決 D0 **+3.4%**（Σ 693.3、8/8 正）/ P0 生產複閘 **+0.4%**（673.2）、
  prefill +16~18%、prefix-hit 38.5×/38.3× 逐字一致**無需 SWA-prefix hotfix**
  （`22e246e`、`2039b8a`、`2cf92a6`）③ `deepseek-nvfp4` spec-decode A/B lane + N-campaign
  記錄（eval-only、未 promote，`af8c808`）④ **退休配方歸檔結構整併**：`_backup/` → repo 根
  `_overdue_recipe/<profile>_<image+tag>_<yyyymmdd>/` 自帶式 bundle（byte-identical conf +
  重渲染 compose（api-key 脫敏）+ `patches/dspark-vision/` 副本 + `recipe_README.md`
  歷史 benchmark／還原步驟；image/模型不上傳，`84f343c`）。判級：**非「同 image 調優」**
  （v1.4.1 的 patch 判準）—— 兩條生產 lane 換 image 譜系與權重，但無新增服務 lane
  → **minor**。annotated tag 打於 `84f343c`（本記錄 commit 之前，比照歷版慣例）。
  **GitHub Release 已建**（`id 407909226`，比照歷版；以 API + 本機 GCM 憑證，
  **未寫入任何檔案**）。
- **`v1.7.0`（2026-10-14，新增 lane + 退休 2 lane + boot 修正 — minor bump）**：`32e79c4`
  —— 自 v1.6.0 起 **9 個 commit**（`6ead700`…`32e79c4`）—— ① **新增 service lane
  `comfyui-jdaln`**（`72716a8`）：jdaln opinionated ComfyUI（自建 image、ComfyUI
  0.38.0、2812 node types）落 Node1 `:8188`、`GROUP=image MODE=exclusive`、stack
  `~/docker-stacks/comfyui-dgx-spark/`；`docs/COMFYUI_JDALN_DEPLOYMENT_2026-10-14.md`
  完整記錄，**MiniMax H3 i2v 作為退休前驗證關卡**實測過（`prompt_id d91692b7`、
  `status=success`、204.5 s → 935,097 B mp4），HF token 移至 `config/hf_token`（600）。
  ② **退休 2 lane**（`c377edc`，使用者 2026-10-14 裁定）：`comfyui`（comfyui-aeon /
  Flux 2 Dev，stack ~71 GB + image 26.7 GB 已刪）與 `minimaxh3`（`:8000` vLLM-API，
  stack 135 GB + image 32 GB + 輸出目錄已刪），repo 側 conf 與所有引用一併重寫；從未
  promote 的 `minimax-h3-sglang` 同伴（56 GB + 2 image）一併移除，其
  `FAILURE_ANALYSIS.md` **逐字保留在本檔**（`f989cb0`）。③ **Node0 失效切換鏡像 +
  殘留清理**（`3a98fb6`）：以 CX7（`10.0.101.101↔10.0.101.102`）rsync 建立 jdaln 鏡像，
  並清掉 Node0 上兩個退休 runtime 的殘留 **~204 GB**；驗證 114,316 檔 / 16,298 目錄 /
  6 symlink 兩端完全一致、>2 GB 權重 sha256 一致、非 `eye` 條目 0、image diff-ID 鏈跨
  overlay2（Node0）／containerd（Node1）一致 —— **被動鏡像、刻意未在 Node0 開機**
  （會與同顆 GB10 上的 27b TP2 爭用）。④ **`fix(gb10-single-boot)` health timeout
  誤報 READY**（`537c64e`）：等待圈在 `sleep 10` 期間 TIMEOUT 到期時，`while` 條件直接
  結束圈、圈內逾時檢查變不可達，於是 `mark ready` 照樣執行卻從未探測 `HEALTH_URL`；
  2026-10-12 於 node1/comfyui-jdaln 實測 —— `TIMEOUT=14400` 於 21:52:21 到期、
  21:52:30 卻記 READY、`:8188` 從未監聽。⑤ **輸出目錄改到 `~/Downloads/output/`**
  （`32e79c4`）：掛載位於**上游 git 追蹤**的 compose，而 `gb10-single-boot` 明確傳 `-f`
  （`docker-compose.override.yml` 不會被載入），故改動做成**保留預設值**的參數
  `${COMFY_OUTPUT_DIR:-../ComfyData/output}`、值放 gitignored `.env`，兩節點
  compose+`.env` sha256 一致；兩份部署測試產物自兩節點 `ComfyData/output/` 清除。
  ⑥ 其餘 2 個 commit（`6ead700`、`241b8b9`）為 v1.6.0 的 tag／Release／session-close 記錄。
  判級：**新增 service lane**（v1.4.0／v1.5.0 慣例）＋ boot 腳本正確性修正 —— 非「同
  image 調優」（v1.4.1 的 patch 判準）→ **minor**。annotated tag 打於 `32e79c4`
  （本記錄 commit 之前，比照歷版慣例）。**GitHub Release 已建**（`id 412399294`，
  比照歷版；以 API + 本機 GCM 憑證，**未寫入任何檔案**，body 與 tag 訊息**逐字相同**
  3009 字元、LF）。
- **tag 現況**：`v1.0.0`→`496c9b1`、`v1.1.0`→`71ccf20`、`v1.2.0`→`ffd02ea`、
  `v1.3.0`→`2474cf8`、`v1.3.1`→`276348c`、`v1.3.2`→`168cb99`、`v1.3.3`→`9bb2006`、
  `v1.3.4`→`a92d2bc`、`v1.4.0`→`6aff00d`、`v1.4.1`→`cc76cbd`、`v1.5.0`→`3201363`、
  `v1.6.0`→`84f343c`、**`v1.7.0`→`32e79c4`**。

### 2026-10-08 — README 發布 + v1.5.0 版號：session close Validation evidence

- **範圍**：本收尾輪僅改 `README.md`（`3201363`）與 `handoff.md`（`3201363` 第 4 行、
  `5ef23d0` 版本記錄）＋ tag/Release 中繼資料 —— `git show --stat` 證實兩 commit 各只含
  這兩個檔，**docs-only ⇒ Runtime test = N/A**（無 profile/script/args 變更；runtime 行為
  證據仍為 Phase 3 項 1–7，前輪已驗，本輪未觸碰）。
- **結構與內容檢查**（本地 worktree；2026-10-08 11:41–11:42 +08:00，每項 <1s、exit 0）：
  1. `git status` → clean；`git diff --stat` → 空（兩 commit 已入庫）→ **Pass**
  2. README 陳舊字串掃描（`建置中|not yet booted|boot PENDING|另排時段|現役（2026-10-05|
     現役（10-05`）→ **0 命中 = Pass**
  3. 內容到位：`現役` 命中 L14 現況塊／L72 服務表列／L77 現役註記／L250 章節標題／
     L297 benchmark 標題；`129.9`×3、`Phase 3 完成`×3、`1984.6`×2（README）、
     `406384910`×1（handoff）→ **Pass**
  4. tag 檢查：`git for-each-ref refs/tags/v1.5.0` → `type=tag`（annotated）、target
     `3201363`；message 首行 `v1.5.0 (2026-10-08) - minor`、`13 commits since v1.4.1` →
     **Pass**（授權重建後計數正確）
  5. 四端一致：local／`origin/main`／`github/main` 皆 `5ef23d0`；node0 於 push 後同步驗證
     （ff-only 至 `5ef23d0`、`git fetch --tags --force` 顯示 `[標籤更新] v1.5.0`、
     tag→`3201363`、tree clean）→ **Pass**
  6. GitHub Release API `GET /releases/tags/v1.5.0` → `id=406384910`、`tag=v1.5.0`、
     `name=v1.5.0`、`draft=false`、`published_at=2026-10-08T03:35:08Z`、body 46 行 →
     **Pass**（憑證走本機 GCM `git credential fill`，LF-only 檔 + `cmd /c`，**未寫入任何檔案**）
- **統計：Pass 6 組 / Fail 0 / Skip 0**（Runtime = N/A，docs-only）。
- **Test environment**：本機 Windows + pwsh 7.4.6 + git 2.56.0.windows.1；node0
  `192.168.23.215`（Posh-SSH）；GitHub API。
- **Artifacts**：tag message（`git show v1.5.0`）、Release
  <https://github.com/sawaichi9527/ai-gb10-cluster-runtime-manager/releases/tag/v1.5.0>、
  commits `3201363`／`5ef23d0`。
- **尚未驗證／不在本輪範圍**：README 的瀏覽器實際渲染（僅文字檢查）；Release body 的
  GitHub UI 顯示效果；runtime 面 —— `deepseek-nvfp4` 維持前輪 READY 服務中（本輪未重啟，
  預期行為）。

### 2026-10-09 — `_overdue_recipe/` 歸檔結構 + 兩條配方繼承收尾 + v1.6.0 版號：session close Validation evidence

- **範圍**：本 session 產出 2 個 commit —— `84f343c`（70 檔：`_overdue_recipe/` 61、
  `cluster-profiles.d` 3（live conf header ×2 + `_backup/README.md` 刪除）、docs ×2、
  AGENTS／README／`bin/gb10`／handoff 各 1；`git show --name-only` 證實 **`scripts/` 與
  `runtimes.d/` 零改動**，live conf 僅 header 註釋、`bin/gb10` 僅 heredoc 註解 ——
  註釋不進 render 產物）＋ `6ead700`（handoff.md 版本記錄）⇒ **Runtime test = N/A**
  （loader／launcher 未觸碰；docs＋封存檔＋註釋-only）。
- **結構與內容檢查**：
  1. 渲染證據（node0，19:59，rc=0）：以 `load_profile`+`render_tp2_compose` 就地重渲染
     4 份封存 compose → `<REDACTED:from-cluster.env>` placeholder 每檔 ×1、原始 JWT ×0、
     暫存 conf 已清、tree clean
  2. 脫敏／LF 檢查（本地 20:07、node0 20:54 各一次）：封存 yml `eyJ`=0 ×4、
     placeholder=1 ×4；`_overdue_recipe/` 全 LF（無 CR 位元組）
  3. byte-identity（node0 20:13、20:54 重驗）：`deepseek-anemll.conf`
     `3147b4e9…78f0562`、`deepseek-vision-anemll.conf` `0df27c38…9eaafe` 與退役當日
     記錄一致；兩組 tune `.conf`==`.base`（`e0c1f265…`／`5e70ec4e…`）
  4. `bash -n`（node0 20:13、20:54）：`bin/gb10` + 2 live conf + 4 封存 conf 全 rc=0（7/7）
  5. loader smoke（node0 20:13、20:54）：`gb10 list` rc=0（7 服務 + `deepseek-nvfp4-tune`
     A/B only）；`_backup/` 與根 `patches/dspark-vision/` 已不存在，根 `patches/` 僅剩
     active 三目錄（eugr-spark-vllm-b12x／mimo26flash／qwen38flash）
  6. 機密掃描（node0 20:54，取 `cluster.env` 的 `VLLM_API_KEY` 對整棵 repo tree
     `grep -rqF`）：**無原始 key**（僅 placeholder 入庫）
  7. tag：annotated `v1.6.0`→`84f343c`（首行 `v1.6.0 (2026-10-09) - minor`）；
     `ls-remote --tags` origin／github 皆 object `8b0602e`；node0 `fetch --tags` 後
     `git tag --points-at 84f343c` = `v1.6.0`
  8. GitHub Release `GET /releases/tags/v1.6.0` → `id=407909226`、published
     （2026-10-09T12:48:39Z）、body 43 行（GCM 憑證、**未寫入任何檔案**）
  9. 四端一致（20:49–20:54）：local＝origin＝github＝node0 皆 `6ead700`、node0
     tree clean（0 dirty）
- **環境參考（非本次修改產出）**：使用者同窗自行啟動 `deepseek-nvfp4` 背景 boot
  （20:11:39 起、20:32:52 READY、冷啟約 21 分）—— 與 repo 變更無關；收尾批次複量
  `/health` rc=0（20:54）。
- **統計：Pass 9 組 / Fail 0 / Skip 0**（Runtime = N/A；首輪 node0 批次 B4–B7 因
  `source cluster-common.sh` 帶入 `set -e`、grep 零命中 exit 1 中斷，已以防護版重跑
  補齊）。
- **Test environment**：本機 Windows + pwsh 7.4.6 + git 2.56.0.windows.1；node0
  `192.168.23.215`（Posh-SSH，repo `main`）；GitHub API。
- **Artifacts**：commits `84f343c`／`6ead700`；tag message（`git show v1.6.0`）；Release
  <https://github.com/sawaichi9527/ai-gb10-cluster-runtime-manager/releases/tag/v1.6.0>；
  封存 bundle `_overdue_recipe/*/`（含 `recipe_README.md` 歷史 benchmark 與還原步驟）；
  前輪 A/B 證據 `docs/evidence/{deepseek,vision}-b12x-recipe-ab-2026-10-09/`。
- **尚未驗證／不在本輪範圍**：封存配方的還原路徑未端到端演練（步驟僅文件化，未執行
  rollback）；Release／歸檔 README 的 GitHub UI 顯示效果；封存 compose 為參考產物、
  不直接部署（`cluster-up` 每次啟動由 conf 重渲染，屬設計行為）。

### 2026-10-14 — `comfyui-jdaln` 上線 + 退休 2 lane + 輸出目錄改到 `~/Downloads/output/` + v1.7.0 版號：session close Validation evidence

- **範圍**：本 session（10-12～10-14）產出 v1.6.0 之後的全部 9 個 commit
  （`6ead700`…`32e79c4`），其中 `72716a8`／`c377edc` 動了 `runtimes.d/`、`537c64e`
  動了 `scripts/gb10-single-boot`。**本收尾輪**則只含 2 個 commit —— `a80ae2c`
  （版本記錄）與本記錄，`git show --stat` 證實兩者**各只含 `handoff.md`**
  （33 insertions／2 deletions）⇒ 收尾輪 **docs-only ⇒ Runtime test = N/A**。
  runtime 行為證據為本 session 前段已驗、本輪未再觸碰的：node1 `comfyui-jdaln`
  `:8188` → 200 且 `health=healthy`、掛載換新後容器內 `touch` 寫入成功、node0 鏡像
  三計數一致 + >2 GB 權重 sha256 一致、`runtimes.d` 只增 1 刪 2（`A comfyui-jdaln.conf`／
  `D comfyui.conf`／`D minimaxh3.conf`）。
- **結構與內容檢查**（pwsh 7.4.6 腳本逐項執行，2026-10-14 14:53 +08:00，27 項）：
  1. **worktree／文件完整性**：`git status` → clean（0 entry）、`git diff --stat` → 空；
     三份文件 code fence 全為偶數（`handoff.md` 4／`AGENTS.md` 2／
     `docs/COMFYUI_JDALN_DEPLOYMENT_2026-10-14.md` 18）、**CR 位元組皆 0**
     → Pass×3
  2. **tag**：`git for-each-ref refs/tags/v1.7.0` → `objecttype=tag`（**annotated**）；
     `git rev-parse 'v1.7.0^{commit}'` →
     `32e79c45f25ab64cdbe4377ab2fe9369237bcaa5`；message 首行
     `v1.7.0 (2026-10-14) - minor`、含 `9 commits since v1.6.0 (84f343c):` 與
     `-> minor bump` 判級句；`git rev-list --count v1.6.0..32e79c4` = **9**
     （與宣告相符）；message **CR=0** → Pass×7
  3. **四端一致**：local／`origin/main`／`github/main` 皆 `a80ae2c`；node0 經
     Posh-SSH 實測 `git rev-parse HEAD origin/main` 亦 `a80ae2c`、
     `git tag | wc -l` = **13**（由 12 增 1）、`status --porcelain | wc -l` = 0、
     `git pull --ff-only` rc=0、`git fetch --tags --force` 顯示 `[新標籤] v1.7.0`；
     `git ls-remote --tags` 兩個 remote 皆見 `v1.7.0` → Pass×3
  4. **GitHub Release**：憑證走本機 GCM `git credential fill`（LF-only 請求檔 +
     `cmd /c`，**憑證未寫入任何檔案**）。`GET /repos/…/releases` → v1.7.0 恰好
     **1 個**（無重複）；`id=412399294`、`name=v1.7.0`、`draft=false`、
     `prerelease=false`、`target_commitish=main`、`published_at=2026-10-14T06:25:13Z`；
     **Release body 與 tag 訊息逐字相同（皆 3009 字元、CR=0）**；歷前 8 個 Release
     （v1.3.1…v1.6.0）id 未變 → Pass×9
  5. **handoff 內容到位**：L15 指標已改指 `v1.7.0`（`32e79c4`）、
     版本標記 bullet L1176、Release id L1204、tag 現況清單 L1207 → Pass×4
  6. **repo gate**：`scripts/check-git-sync.sh --block` → **rc=0** → Pass
  - 註：初版驗證腳本 L15 的 regex 漏了粗體 `**` 而誤報 1 FAIL，修正 pattern 後重跑
    **27/27** —— 是檢查本身的 bug，文件無誤，故未改動 handoff 內容。
- **統計：Pass 27 / Fail 0 / Skip 0**（收尾輪 docs-only ⇒ Runtime = N/A）。
- **Test environment**：本機 Windows + pwsh 7.4.6 + git 2.56.0.windows.1；node0
  `192.168.23.215`（Posh-SSH）；GitHub REST API（`X-GitHub-Api-Version: 2022-11-28`）。
- **Artifacts**：tag message（`git show v1.7.0`，tag object `30d677a2`）、Release
  <https://github.com/sawaichi9527/ai-gb10-cluster-runtime-manager/releases/tag/v1.7.0>、
  commits `32e79c4`（tag 所在）／`a80ae2c`（版本記錄）／本記錄 commit。
- **尚未驗證／不在本輪範圍**：Release body 的 GitHub UI 顯示效果；真正的 failover
  演練（`gb10 stop` → `gb10-single use comfyui-jdaln node0`）**仍未測** —— node0 維持
  **被動鏡像刻意未開機**（會與同顆 GB10 上的 27b TP2 爭用），此限制已同時寫入
  `AGENTS.md` 與 `docs/COMFYUI_JDALN_DEPLOYMENT_2026-10-14.md` §13.4／§14.5；
  `~/Downloads/output/` 在鏡像範圍外，故兩節點的實際產出**不互相同步**（刻意設計，
  產物可重新產生）。

### 2026-10-14（續） — `gb10-single status`／`list` 無參數改列兩節點 + 修 node1 `null` 狀態：session close Validation evidence

- **範圍**：本輪 3 個 commit（`984ce74`、`d9fb74a`、`bf60c62`）。`git diff --stat
  dc67e40..bf60c62` 只含 **`README.md`（4 行）與 `bin/gb10-single`（43 行）**，
  `runtimes.d/`、`cluster-profiles.d/`、`scripts/` **零改動** ⇒ 只動 CLI dispatch
  與兩處 helper，**不需重啟任何 lane，runtime 面 N/A**。
- **起因**：使用者執行 `gb10-single status` 看到 `comfyui-jdaln … inactive`，以為
  node1 服務停了。實際上該指令不帶參數時預設查 **node0**（原 `node="${2:-node0}"`），
  而 node0 是**刻意不開機的被動鏡像** —— 輸出標題列 `===== node0 =====` 即為證據；
  node1 直查為 `comfyui | Up 2 hours (healthy)`、`:8188 → 200`。
- **改動 1（`984ce74`、`bf60c62`）**：`status` 與 `list` 無參數都改列**兩個節點**
  （node0 → 空行 → node1）；帶明確節點維持原行為 —— 其中 `list` 顯式單節點仍
  **不印 header**，只有無參數分支走 `show_status` 取得標題（兩張表堆在一起才讀得懂）；
  非法節點仍 `ERROR: unknown node` rc=1。改列兩節點**順帶暴露既有 bug**：node1 區段
  所有不在跑的 lane 顯示 `null` 而非 `inactive`。
- **根因（`null`，`d9fb74a`）** —— node0 實測四項證據：
  1. `docker inspect <missing>` **不是輸出空的**：stdout 實測 **3 bytes**
     （`raw docker inspect stdout bytes: 3`），內容為 `[]`，錯誤走 stderr
  2. `echo -n '[]' | jq -r '.[0].State.Status'` → **`null`**
  3. node0 分支 `docker inspect -f '{{.State.Status}}' || echo ""` → 空字串 →
     `state_of` 正確判 `inactive`；node1 分支
     `docker inspect … | jq -r '$jqf'` **無兜底** → `null`
  4. node1 對該容器實測 `error: no such object: aeon-vllm-27b`（確實不存在）

  而 `state_of` 原判準只擋空字串與 `<no value>`，`null` 非空 → 被當成有效狀態印出。
  **修法兩層**（任一單獨存在都太脆）：① `inspect_q` node1 分支改
  `jq -r '($jqf) // empty'`（同時覆蓋 compose-project label 與 `.[0]` 預設分支）
  ② `state_of` 連 `null` 也判 `inactive`，讓未來未加兜底的呼叫者仍安全。
- **結構與內容檢查**（node0 實測，全部 PASS）：
  1. `status` 無參數：2 個節點標題、`null` **0** 處、inactive **4**、running **2**、
     READY **2**（4 個 inactive = node0 的 35b + comfyui-jdaln、node1 的 27b + 35b，
     與兩節點實際容器吻合）
  2. `status node0`／`status node1` 各只出 1 個標題；`status bogus` → **rc=1**；
     `out of sync` 警告（僅 stderr）= **0**
  3. `list` 無參數：2 標題、`null` **0**、資料列 **6**、running 2、inactive 4；
     `list bogus` → **rc=1**
  4. `list node0`／`list node1` **header 數 = 0**（顯式單節點維持原無標題輸出）
  5. `bash -n` OK、CR **0**、mode `100755` 保留；`check-git-sync --block` **rc=0**
  6. 四端一致：local = origin = github = node0 = **`bf60c62`**（node0 ff-only、
     tree clean、部署測試檔已捨棄後歸位）
- **過程中兩次假結果（已修正，以修正後為準）**：
  1. `git pull … 2>&1 | tail -3` 之後取 `$?` 抓到的是 **`tail` 的返回碼**，誤報
     `pull rc=0`；實際 pull **失敗**（`請在合併前提交或貯存您的修改。正在終止`），
     node0 卡在 `dc67e40` 且帶著直接部署的測試檔。已先核對**三個 sha256 完全相同**
     （本地檔／node0 部署檔／`d9fb74a` git blob 皆 `c3ee8706…`）確認捨棄零損失，
     再 `git checkout --` 後 pull，**REAL pull rc=0**。
  2. 檢查 `out of sync` 警告用 `2>&1 >/dev/null | grep` 得 0 卻標 PASS —— 該警告實際
     走 **stdout**，被 `>/dev/null` 丟掉才 grep 不到。改為只撈 stderr 後，樹乾淨時
     確實 0。
  （另：`list` 與 `status` 顯式單節點輸出的 diff rc=1 **不是失敗** —— 差異正是刻意
  引入的節點標題。）
- **統計：Pass 20 項 / Fail 0 / Skip 0**（`status` 面 10 + `list` 面 10；CLI-only ⇒
  Runtime = N/A，lane 全程未重啟）。
- **Test environment**：本機 Windows + pwsh 7.4.6 + git 2.56.0.windows.1；node0
  `192.168.23.215`（Posh-SSH + `Set-SCPItem` 部署測試檔）；node1 `10.0.101.102`
  （僅用來驗證真實容器與 `:8188`）。
- **Artifacts**：commits `984ce74`（status 兩節點）、`d9fb74a`（null 修正）、
  `bf60c62`（list 兩節點）；根因證據取自 node0 的 `docker inspect` stdout bytes、
  `[] | jq` 輸出，與 node1 的 `no such object` 回應。
- **尚未驗證／不在本輪範圍**：`doctor`／`logs`／`wait` 等其他子命令的無參數行為
  （未改，維持原樣）；在 node1 端直接執行 `gb10-single` —— 本 CLI 設計為**在 node0
  執行、以 SSH 遠端查詢 node1**，node1 不 host repo checkout，故不適用；輸出格式若
  被外部工具解析需另行確認（repo 內**無任何**呼叫者解析，唯一內部呼叫 `poll:` 已
  帶明確節點）。

### 2026-10-14（續二） — Forgejo Releases 與 GitHub 不同步：診斷＋補齊 13/13＋「兩端都建」慣例入法：session close Validation evidence

- **起因**：使用者發現 Forgejo（`origin`，`http://192.168.23.167:3000`）的 Releases
  頁面停在 `v1.2.0`，GitHub 同一 repo 卻顯示到 `v1.7.0`，懷疑是兩種服務的機制差異。
- **結論：不是機制差異，是 workflow 斷層。** 兩邊規則完全相同 —— `git push --tags`
  只建立 **tag**，永遠不會建立 **Release**；Release 是各平台自己的資料庫物件，必須
  另外用 UI/API POST。GitHub 端每版都另外打了一次 `POST /repos/…/releases`，
  Forgejo 端從 `v1.3.1` 起就沒再打過。
  （使用者「Release 是平台層物件、不是 git 層」的直覺正確，但兩平台機制無差異；
  「停在 v1.2.0」是 Releases 分頁只列 Release 物件，**Tags 分頁一直看得到 `v1.7.0`**。）
- **四項證據**：
  1. **git 層完全同步**：`git ls-remote --tags` 兩端各 **13** 個 tag、SHA 逐位相同
     （`v1.0.0`…`v1.7.0`）；Forgejo `GET /tags` 亦回傳同樣 13 個
  2. **Release 物件原本完全不重疊**（補建前）：Forgejo **3** 個（`v1.0.0`／`v1.1.0`／
     `v1.2.0`，建立於 2026-09-10～09-13）vs GitHub **9** 個（`v1.3.1`…`v1.7.0`，首個
     2026-09-29）；`only_forgejo=[v1.0.0,v1.1.0,v1.2.0,v1.3.0]`、`only_github=[]`。
     **`v1.3.0` 兩邊都只有 tag、沒有 Release** —— 它掉在換手的縫裡
  3. **handoff 既有慣例只寫 GitHub**：L1088（v1.3.1「並在 GitHub 建立…」）、L1101
     （v1.3.2「同樣建了 GitHub Release」）、L1121／L1129／L1144／L1157／L1174／L1204 同
  4. **沒有自動化可補**：`.github/workflows`、`.gitea/workflows`、`.forgejo/` 皆不存在，
     repo 內也無 release 腳本
  - 既有 L1321「Release body 與 tag 訊息逐字相同（皆 3009 字元、CR=0）」**僅指 v1.7.0
    本身**；後半句「歷前 8 個 Release id 未變」只驗 id、未驗 body —— 故本輪發現的
    body 分歧**不是**推翻既有聲明。
- **修復動作**（全經 API；憑證取自本機 credential store，**未寫入任何檔案、未印出**）：
  1. **Forgejo 補建 10 個**（`v1.3.0`…`v1.7.0`）→ 10×`status=201`，id `13`…`19`、
     `21`…`23`（`20` 為既有 id）；body 來源＝本機 annotated tag 訊息
  2. **GitHub 補建 4 個**（`v1.0.0`…`v1.3.0`）→ 4×`status=201`，id `412515193`／
     `412515211`／`412515232`／`412515250`；來源＝Forgejo 現有 name+body 逐字鏡像。
     **`v1.2.0` 是 lightweight tag** —— `%(contents)` 只回 250 字元 commit 訊息，而
     Forgejo 該 Release body 有 2004 字元手寫內容，故不能取 tag 訊息
  3. **發現 7 個 body 分歧**：`v1.3.1`…`v1.5.0` 的 GitHub body 是**手寫豐富 Markdown**
     （3922／1839／1606／1188／1799／2075／2279 字元），本輪新建的 Forgejo 用的是
     tag 訊息（524／434／586／704／1644／1052／1946）。`git grep` 證實**豐富版只存在於
     GitHub**（repo 無 release/changelog 檔）。經裁定方案 A：**把 GitHub 豐富版 PATCH
     回 Forgejo**（就地更新、id 不變）→ 7×`status=200`、`exactMatch=True`
  4. **慣例入法**：AGENTS.md Conventions 新增「標記新版本時兩端都建 Release」規則
- **過程中三次判讀錯誤（皆已修正，以修正後為準）**：
  1. payload 的「剝掉尾端空行」迴圈吃掉最後的 `\n`，`v1.7.0` body 算成 **3008**；
     拿 GitHub 實測的 **3009** 當驗證點才抓到 → 拿掉迴圈後 3009 MATCH（LF-only、CR=0）
  2. 第一次 parity 報告顯示 7 個 `BODY-DIFF` 卻「`bodyLen` 兩邊相同」—— 腳本的
     `bodyLen` 取的是 **Forgejo** 的長度，「相同」是假象；改為逐字元比對才看到
     GitHub 實際是 3922 vs 524
  3. 首次 parity 的 `mismatched` 判定用 `-ceq` 比 body 正確，但**呈現欄位**取錯來源，
     導致先誤報「僅 7 個 body 不同、其餘全等」的半套結論
- **最終狀態（兩端逐字相同）**：GitHub **13**、Forgejo **13**、`mismatched=0` →
  **FULL 13/13 PARITY**；逐版 bodyLen：547／1136／2004／425／3922／1839／1606／1188／
  1799／2075／2279／2340／3009
- **結構與內容檢查**（node0 與本機 API 層，全部 PASS）：
  1. 兩端 tag 13/13、SHA 逐位相同
  2. 補建後 Forgejo release 數 3→13；GitHub 9→13
  3. 13 個版本逐一 `name` 與 `body` `-ceq` 比對 → 全等
  4. Forgejo PATCH 後 **id 未變**（`14`…`19`、`21`…`23`）
  5. 憑證處理：LF-only 請求檔 + `cmd /c`、用畢即刪、輸出從未含密碼/token
- **統計：Pass 53（13 tag 比對 + 10 Forgejo 建立 + 4 GitHub 建立 + 7 PATCH +
  13 版逐版比對 + 3 payload 驗證 + 3 憑證安全）/ Fail 0 / Skip 0** —— 純遠端
  Release 物件，**不觸碰任何 node、不動任何 lane、不改任何 git 內容**，故 runtime
  面 N/A、與前三個 commit 無依賴關係。
- **Test environment**：本機 Windows + pwsh 7.4.6 + git 2.56.0.windows.1；Forgejo
  `192.168.23.167:3000`（`GET /user` → `login=829522`、`admin=True`/`push=True`）；
  GitHub API（Bearer，來自本機 GCM，`user=sawaichi9527`）。
- **Artifacts**：Forgejo release id `13`…`19`／`21`…`23`；GitHub `412515193`／
  `412515211`／`412515232`／`412515250`；既有 `412399294`（v1.7.0）id 未變。
- **尚未驗證／不在本輪範圍**：兩端 Releases **頁面的瀏覽器實際渲染**（僅 API 層驗證）；
  Release **assets**（兩端皆 0，從未有附件）；Forgejo 的 draft／prerelease UI 分頁；
  **下一個版本是否真的兩端都建**（規則已入法，但尚未實作過一次）。

### qwen38flash 對齊上游 + 冷啟驗證（2026-09-29）

觸發：上游 `MiaAI-Lab/Qwen3.8-Flash-Next-Dual-DGX-Sparks` 的 `main` 已前進到 **`2c86a1d0`**
（相對原 pin `d2f54b7…` **ahead 11**）。

- **image 未變**：`vllm/vllm-openai:qwen38-flash-next` digest 仍為 `sha256:fc120ece…be05bf8`
  ＝本 profile `IMG_SHA256`；Docker Hub `last_updated` 仍 2026-08-26（未重推）。
- **變更範圍**：只動 `cluster-profiles.d/qwen38flash.conf` 與 `patches/qwen38flash/`（4 個檔案），
  共用 loader 與其他 profile **零改動**；qwen38flash 為 cluster-only，node1 單機 lane 不受影響。
  - GMU `0.835` → **`0.80`**（上游 2026-09-26：0.835 使節點僅剩 0.3–0.9 GiB MemAvailable，GB10 會硬重置）
  - prefix caching **OFF → ON**（對齊上游；須搭配下述 block-drop backport）
  - `SPEC_CONFIG` += `disable_eagle_block_drop`、`index_share_for_mtp_iteration`
  - `EXTRA_ARGS` += `--enable-prompt-tokens-details`（每請求 cached-token 統計）
  - vendor `patch_block_drop.py`（vllm#53388 backport）、`patch_determinism.py`（**opt-in，預設關**）
  - `CMD_WRAPPER` 新增 block-drop（fail-closed）與 determinism（未設環境變數時不套用）步驟；
    pin 由 `d2f54b7…` 改為 **`2c86a1d0…`（10 檔）**
- **冷啟驗證**（`gb10 use qwen38flash`；13:54:32 起、14:08:21 READY，約 14 分；**KV 29.88 GiB**）：
  - boot log：image digest gate **PASS**（兩節點）、`SYNC_DIRS` 同步至兩節點
  - 容器內：block-drop 的 **6 個目標檔全部 `patched`**；mark 數 `speculative.py`=2、
    `kv_cache_utils.py`=1、`scheduler.py`=5；rank1 同為 2（與 rank0 一致）
  - scheduler 記錄 `EAGLE trailing prefix-cache block dropping is disabled` ×1（僅 rank0 跑 scheduler，
    rank1 = 0 屬正常）→ **backport 確實在運作**
  - `cluster-compose-verify qwen38flash` → **兩 rank PASS**
  - `gb10 smoke` → HTTP 200（`HELLO-TP2-OK`），usage 含 `prompt_tokens_details`（證明新參數生效）
  - 引擎實測 argv：`--gpu-memory-utilization 0.80`、`--enable-prefix-caching`、spec config 兩新鍵
  - **prefix cache 實測**（8,452-token 同一 prompt ×3，`max_tokens=1`）：
    **5.53 s → 0.31 s → 0.23 s**，`cached_tokens` **0 → 8320 → 8320**；只重算 **132** tokens
    （不是一整個 1,664-token block）→ `disable_eagle_block_drop` 亦證實有效；`/metrics`
    `prefix_cache_hits_total`=16640 > 0
  - **`bench-c`（`BENCH_IGNORE_EOS=1`, max_tokens=400）vs 2026-09-20 基準**：C1 連測
    35.6/40.2/45.4/40.1（中位 ≈40.1 vs 41.7 → 變異範圍內；acceptance 在 32.8–50.5% 間擺動）、
    C4 107.2（vs 105.0）、C8 連測 169.0/165.0/162.6（中位 ≈165 vs 161.1）→ **無回歸**
- **determinism knobs（能力已備、預設關）**：2026-09-29 起改由 profile 的 opt-in 開關控制
  （`Q38_DET_TOPK=1` / `Q38_MOE_DET_FINALIZE=1`，見下節）；本次一般 boot 容器內已驗證 `_SORTED_TOPK`=0。
- 驗證後 live lane 留在 qwen38flash；切回 mainline 用 `gb10 use deepseek`。

### benchmark 協定 + 可重現性（2026-09-29）

- `scripts/bench-c.sh` 新增 opt-in 取樣旋鈕（`9e60eff`）：`BENCH_DETERMINISTIC=1` →
  `temperature=0, seed=0`；`BENCH_TEMPERATURE=` / `BENCH_SEED=` 可單獨覆寫。**未設＝payload
  逐 byte 不變**，只在 qwen38flash 採用（其他模型 benchmark 暫不導入）。
- `scripts/bench-ctx.sh` / `bench-mm.sh` 新增 opt-in 冷探針（`d8f530e`）：`BENCH_COLD=1` →
  每次呼叫（ctx）／每個 stream（mm）前綴唯一 nonce。**這是必要的**：prefix caching 現為 ON，
  兩者 prompt 皆固定（且 ctx 的長探針天然是短探針的前綴），不除霧會直接從快取回答而虛胖。
  預設關＝其他模型 probe 逐 byte 不變。
- `cluster-profiles.d/qwen38flash.conf`：determinism knobs 自 `5dcf1c4` 起改為**預設 ON**，
  `Q38_DET_OFF=1` 可單次關閉（注入 `VLLM_QSA_DET_TOPK=1` / `VLLM_MOE_DET_FINALIZE=1`，由
  CMD_WRAPPER 套用 `patch_determinism.py`）。**故意不設** `VLLM_FLASHINFER_AUTOTUNE_CACHE_DIR`
  （upstream 指向另一個 `_unfused` 目錄），讓 unfused 調校落在 lane 常規的
  `flashinfer_autotune_cache`，仍由每 boot 的 rank-keyed reset 覆蓋。
- **為什麼**（vllm-project/vllm#53436，DeepSeek-V4-Flash / Blackwell SM120 / spec decode）：
  `temperature=0` + 固定 seed 下**輸出文字一致、但吞吐仍抖**；根因是 target forward 非逐 bit
  可重現 → accept/reject near-tie 翻轉 → acceptance 變化（與吞吐 r=0.98）。官方
  `VLLM_BATCH_INVARIANT` 在 Blackwell + MXFP4 MoE 直接 `NotImplementedError`（無官方路可走）。
  報告亦指出 **3 次重複常掩蓋抖動，需 ≥10 次**。
- **完整實測**（`BENCH_IGNORE_EOS=1`, `max_tokens=400`, `temp=0/seed=0`，每 C **10 次**）：

  | C | 中位數 tok/s OFF → ON | tok/s CV OFF → ON | acc CV OFF → ON |
  |---|---|---|---|
  | 1 | 46.9 → 45.5 | 9.2% → 5.2% | 19.4% → **0.0%** |
  | 2 | 73.8 → 78.6 | 12.2% → **1.1%** | 16.6% → 4.9% |
  | 3 | 101.7 → 102.7 | 6.6% → 6.4% | 5.4% → 7.1% |
  | 4 | 117.9 → 145.9 | 9.8% → 8.4% | 8.4% → 10.7% |
  | 5 | 140.2 → 119.5 | 9.8% → 10.9% | 14.3% → 11.3% |
  | 6 | 165.4 → 158.6 | 9.4% → 5.4% | 7.5% → 1.7% |
  | 7 | 167.1 → 177.2 | 7.3% → 7.6% | 8.9% → 9.9% |
  | 8 | 180.8 → 196.8 | 8.7% → **2.2%** | 11.1% → 3.3% |

  C1 acceptance 十次恆為 46.9%；C2/C6/C8 明顯收斂、C3/C5/C7 改善有限，中位數互有高低
  → **無系統性吞吐代價**。C4/C5 在兩種設定下皆呈雙峰，中位數代表性有限。
- **prefill 重測**（`bench-ctx.sh` + `BENCH_COLD=1`, max_tokens=1）：32K **2784.6**、131K
  **2853.6**、200K **2698.9**、245K **2592.5** tok/s（prompt_tokens 32084 / 131084 / 200084 /
  245084）。冷探針自我檢查：32K 連兩次 **3100.5 / 3099.8** tok/s（差 0.02%）。
- **圖片重測**（`bench-mm.sh` + `BENCH_COLD=1`, max_tokens=200）：1img C=1 **47.7**、4img C=1
  **33.1**、1img C=4 **126.3**、1img C=8 **125.2** tok/s，`any_errors=0`；每張圖約 693 prompt
  tokens（09-20 為 597，圖檔／解析度已變，**不可直接對比**）。
- 完整表格見 `README.md` 的 qwen38flash benchmark 段（**比較須同取樣模式**）。
- 現役仍為 qwen38flash（**新預設**：determinism ON；KV 29.15 GiB）。

### 2026-10-15 — `comfyui-jdaln` asset profiles 1 → 9（工具／字幕／語音／影片放大）+ SAM3 靜音 + 鏡像落後：session close Validation evidence

**背景**：node1 的 `comfyui-jdaln` 上線時 `.env` 只啟用單一 `z-image-turbo-core`，其餘 90 個上游
asset profile 全未下載。在磁碟（1.8T 可用）與記憶體（115G available）都充裕的前提下，把六個工具類、
字幕、語音設計與 z-image 控制延伸一次補齊。

**決策記錄**：

- 一次加入 **9 個 profile**（原 1 個）：`z-image-turbo-core`（原）、`z-image-turbo-union-control`、
  `frame-interpolation-film`、`lucida-background-removal`、`lotus-depth-support`、
  `ltx-2.5-latent-upscale`、`whisper-subtitles`、`seedvr2-video-upscale`、`qwen3-tts-voice-design`。
- **`HF_TOKEN` 接入 `.env` 第 5 行**，經 compose 既有的 `env_file: - .env`（第 64 行）進容器。
  **compose 一行未動** —— lane 維持只有原本兩條本地分歧（`${COMFY_OUTPUT_DIR:-…}` 與 allowlist
  預設），未產生 AGENTS.md 所說的第 3 條。
- **`.env` 第 11 行 `COMFY_NODE_BLACKLIST=ComfyUI-SAM3-DGX-Spark` 啟用**，靜音上游已知的
  `No module named 'comfy_env'` 每次 boot `[ERROR]`；代價是 node 類型 **2812 → 2811**。
- 用戶決定**保留原 HF token 不輪替**（`read` 權限、本機 transcript，曝險限於可讀取的 repo）。

**Validation evidence**：

- 乾跑先行：`scripts/smoke/plan_downloads.py`（host-side、read-only）確認 9 個 profile 皆取得大小、
  **無任何 401/403**（LTX-2.5 除外，見下）；並確認 `bootstrap_comfy_assets.sh`
  `download_if_missing()` 第 26-28 行會跳過已存在檔案 → z-image 的 20.69 GB 不會重下
  （planner 在主機上算出該數字是路徑假象：存在檢查用 manifest 的原始
  `/workspace/ComfyUI/models/…`，該路徑只在容器內成立）。
- 下載分兩批，皆以 `gb10-single restart node1 comfyui-jdaln`（node0 執行、走 CX7、
  `up -d --force-recreate` 重讀 `env_file`）：第一批 8 個 profile（17.71 GB）於
  **23:57:30 READY**；第二批 LTX-2.5（2.47 GB）於 **00:25:17 READY**。
- **資產齊全**：13 個權重檔 + 4 個範例輸入全數存在，`missing count: 0`。實測位元組：
  controlnet 3101572408、film 68882302、lucida 884878856、lotus 1735197352、
  vae-ft-mse 334641190、ltx-2.5 VAE 1472223346、ltx-2.5 spatial upscaler 995778752、
  whisper 3087130976、seedvr2 3458259704、seedvr2 VAE 501324814、
  Qwen3-TTS snapshot 4.3 GB（含 `.asset-profile-complete` 標記）。
- **既有權重未被觸碰**：逐一比對位元組與 106G baseline 完全一致（minimax_h3_fl2va
  20970379616、hunyuan_video_720 13185035336、qwen3vl_32b 15687142551、umt5-xxl 11361845464、
  minimax_h3_video_vae 5207808496、z_image_turbo 12309866400、qwen_3_4b 8044982048、ae 335304388）。
- ComfyData **106G → 124G**；`:8188` HTTP 200；`object_info` 註冊 **2811** 個 node 類型
  （黑名單前 2812，正好少 1）；`comfy_env` ERROR 命中數 **0**。
- compose `dirty tracked files: 0`；`.env` 無 CRLF，md5 `bf9680cd…` → `fe42c04f…` → `ebaceadc…`；
  備份 `.env.bak-20261014-231133` / `.env.bak-20261015-001832` 保留。

**LTX-2.5 閘控**（本次最重要的判斷修正）：

- 第一輪判斷錯誤：以為 `ltx-2.5-latent-upscale` 不依賴 Gemma 文字編碼器故不受閘控。
  乾跑顯示兩個檔案皆 **HTTP 401** —— **`Lightricks/LTX-2.5` repo 本身是 `gated: auto`**。
- 帶 token 重跑變成 **HTTP 403**：token 有效（帳號 `Sawaichi`、`read`）但該帳號**未接受授權**。
  **403 ≠ token 錯誤**，此點已寫入 AGENTS.md。
- 用戶於瀏覽器以該帳號點一次 "Agree and access repository" 後，乾跑 rc=0 無 PROBLEM，
  重啟即自動補齊（兩個檔案留在 `.env` 補齊了失敗只會 WARNING 不會中止，故可自癒）。
- 對照：`Lightricks/LTX-2`（LTX 2.0/2.3 lanes）是 `gated: false`，不需要任何動作。

**⚠️ 自我記錄的三個錯誤**：

1. **HF token 洩漏**：驗證容器環境時寫了 `echo "${HF_TOKEN:+YES}${HF_TOKEN:-NO}"` ——
   `${VAR:-word}` 在變數**有值時會展開成那個值**，於是 token 值被印出並進入對話紀錄
   （亦即模型供應商側 log）。之前幾次跑這段時變數未設、印出 `NO`，看起來完全正確，故未察覺。
   正確寫法：`if [ -n "${HF_TOKEN:-}" ]; then echo YES; else echo NO; fi`。用戶評估後決定保留原 token。
2. **誤稱 AGENTS.md 路徑寫錯**：兩次向用戶表示 AGENTS.md 的 HF token 路徑為
   `~/docker-stacks/comfyui-dgx-spark/config/hf_token`（該位置不存在）。實際檔案第 180 行本來就是
   正確的 `~/docker-stacks/config/hf_token`；`git log -S 'comfyui-dgx-spark/config/hf_token'`
   證明該錯誤字串**從未存在於 AGENTS.md 歷史**。依據的是 session 開頭的過期快照而非磁碟實檔，
   幸好動手前先 grep 驗證，否則會把一條正確規則「修正」成錯的。
3. **安全檢查誤擋刪除**：`grep -c` 在計數為 0 時回傳 exit code 1，導致 `|| echo '?'` 也觸發、
   變數變成 `"0\n?"`，比對失敗而拒絕刪除。修正為先 `head -1` 再 `tr -dc '0-9'` 後通過。

**清理**：刪除 node1 上與本次無關的殘檔 `models/diffusion_models/LongCat/LongCat-Avatar_bf16.safetensors.part`
（911 MB、mtime 2026-10-14 00:12:47、age 86828s、0 個開啟 fd）與其空目錄。manifest 中從未出現
LongCat，判斷為更早某次 boot 的中斷下載。`.part` 檔數歸零。

**✅ node0 failover mirror 已補齊（2026-10-15 09:23，經 CX7 rsync）**（AGENTS.md 該 bullet 已同步改寫）

- 鏡射前快照：node0 **19** 個 safetensors / node1 **31** 個（**缺 12 檔**；兩端 stack
  `du -sh` **124G vs 142G**），node0 `.env` md5 `bf9680cd…`（變更前版本）、node1 `ebaceadc…`。
- 執行：在 **node0** 以既有 CX7 rsync（`rsync -aHAX --no-o --no-g --delete --stats`，
  `-e 'ssh -i ~/.ssh/id_gb10_cluster …' eye@10.0.101.102:…`）背景啟動 + 輪詢
  （log `~/docker-stacks/logs/comfyui-jdaln/mirror-sync-20261015.log`）。
- 結果：**rc=0、39 秒（09:23:10 → 09:23:49）、511 MB/s、received 20.2 GB**；
  create 94（reg 72 / dir 22）、delete 2（reg 1 / dir 1）、transferred 1,153 檔
  （literal 20,187,022,178 B / 22.7 s）。
- 鏡射後驗證（兩端同一組指令）：
  - 檔案／目錄／symlink = **114,388 / 16,318 / 6**，**兩端完全一致**。
  - safetensors **31 / 31**；`du -sh` stack **142G / 142G**。
  - node0 `.env` md5 = **`ebaceadc8c94eba01e3e55702777bc09`** = node1（**rsync 已自動帶過來，
    不需手動複製** —— AGENTS.md 原先「copy the .env across」的前提在此不成立）。
  - sha256 抽查：既有 >2 GB 權重 `hunyuan_video_720_fp8_e4m3fn` = `07ae20b5…d62426`
    與 2026-10-14 記錄相同（本次未動）；新傳檔 `Z-Image-Turbo-Fun-Controlnet-Union`
    = `86c085c0d7853f12ce5183499934b54d08371c60f549c5a6b20615cd23989388`，兩端一致。
  - node0 非 `eye` 擁有條目 = **0**（`--no-o --no-g` 生效；node1 為 1，即已知 uid 0 的
    `ComfyUI/user`）。
  - node0 仍**無 comfyui 容器**（被動鏡像）；`aeon-vllm-27b Up 2 days` + `c0918 Created`
    未受影響；磁碟 49% → **50%**。
- **仍未 boot 測試**：Node0 未實際啟動 ComfyUI（與 TP2 共用同一顆 GB10 GPU），failover
  仍須手動 `gb10 stop` → `gb10-single use comfyui-jdaln node0`。
- **工具教訓**：Windows 端以 Posh-SSH（pwsh7）連 node0；腳本**必須先 base64 落地成遠端
  檔案再 `bash <file>`**，不可用 `echo … | base64 -d | bash` —— 腳本內第一個 `ssh` 會
  吃掉剩下的 stdin，實測會**靜默截斷**後續所有輸出（第一次執行只印到 CX7 檢查就結束）。

**已知無害殘留**：boot log 仍有一條
`[WARNING] Skipping import of cpp extensions ... torch >= 2.11.0 (found 2.10.0+cu130)` ——
來自另一個 custom node，torch 2.10 是燒在 image 裡的，該 node 自行降級運作。屬 WARNING 非 ERROR，
修正需重燒 image，收益不划算，決定放著。

**文件變更本身的 Validation evidence**（AGENTS.md + handoff.md，2026-10-15 01:27:25）

本次僅修改 Markdown 文件，**Runtime test = N/A**（依 session-close skill 第 5 步，不為形式啟動
不相關的 DUT／容器）。下列為文件結構與內容檢查，證明「文件修改正確」，不推論 node1 lane 的
Runtime 行為 —— 那部分的證據見上方資產驗證段。

- 命令：`scripts/check-git-sync.sh --block`（repo 既有檢查，經 git bash `C:\Program Files\Git\bin\bash.exe`
  執行；`bash` 不在 PATH 上）→ **exit code 0**。輸出 `WARN: repo is out of sync with origin/main`，
  內容為 `working tree has uncommitted changes to tracked files` —— 即本次待 commit 的兩份文件；
  `HEAD 8ced936 (0 ahead, 0 behind)`、`origin/main 8ced936` 同步，**不需 pull**。
- Markdown fence 平衡：`AGENTS.md` fences=2、`handoff.md` fences=4，皆為偶數 → **BALANCED**
  （對應 AGENTS.md「文件結尾必須是關閉 fence」規則）。
- 換行／縮排：`AGENTS.md` CRLF=0 TAB=0、`handoff.md` CRLF=0 TAB=0 → **LF-only OK**（repo 規則）。
- 內容檢查（`git diff -U0` 新增行）：無 HTML entity 逸出（`&lt;`／`&gt;`／`&amp;`）、無行尾空白、
  **diff 中無 `hf_` token 字串、無密碼／secret 字樣**（對應 skill 的安全要求）。
- 測試環境：Windows 10 NT 10.0.19044.0、pwsh 7.4.6、git bash（Git for Windows）。基線 commit `8ced936`。
- **尚未驗證**：AGENTS.md 新增的 5 條 bullet 與 handoff 新增段的**語意正確性**僅經人工撰寫，
  未經任何 Markdown linter（repo 無 linter 設定、無 CI、無 `tests/` 目錄 —— 先前誤用的
  `tests\validate.ps1` 屬於另一個 repo，已確認不存在）。node0 failover mirror 落後一事已於
  **同輪補齊**（見上一節「✅ node0 failover mirror 已補齊」）。

### 2026-10-15（續三）— 本輪收尾：鏡射補齊紀錄入庫 + 文件驗證（第二次）

**做了什麼**：① 先把 node0 failover mirror 補齊（見上，經 CX7 rsync rc=0 / 39 s / 511 MB/s）；
② 把 AGENTS.md 的 `⚠️ mirror is BEHIND` 與 handoff 的 `⚠️ 未處理` 兩處**改寫為完成紀錄**，
  並把 AGENTS.md 的 Node0 鏡射數字（124 GB / 114,316 / 16,298 → **142 GB / 114,388 / 16,318**）
  與磁碟（49% → **50%**）更新；③ 兩份文件一次 commit。

**Validation evidence（本輪文件變更，2026-10-15）**

- `scripts/check-git-sync.sh --block`（經 git bash）→ **exit 0**；輸出
  `WARN: working tree has uncommitted changes to tracked files`（= 本次待 commit 的兩份文件），
  `HEAD 8ced936 (0 ahead, 0 behind)` / `origin/main 8ced936`。
- Markdown fence 平衡：`AGENTS.md` fences=**2**、`handoff.md` fences=**4**，皆偶數 → BALANCED。
- 換行／縮排：`AGENTS.md` CRLF=**0** TAB=**0**、`handoff.md` CRLF=**0** TAB=**0** → LF-only OK。
- 內容：`git diff -U0` 新增行掃 `hf_|token|secret|password` 僅命中**散文用詞**
  （`HF_TOKEN` 變數名、`hf_snapshot` 類型名、403≠token 錯誤的說明），**無任何實際憑證值**；
  真 token 只在 gitignored 的 `~/docker-stacks/config/hf_token` 與節點 `.env`。
- **Runtime test = N/A**：本輪**未變更任何 runtime 設定** —— node1 lane 未重啟、node0 未 boot
  ComfyUI、TP2 容器（`aeon-vllm-27b Up 2 days`）未觸碰；鏡射是 node0 上的檔案同步。
- **仍未驗證**：node0 failover 的**實際 boot** 路徑（`gb10 stop` → `gb10-single use comfyui-jdaln
  node0`）依然沒跑過 —— 被動鏡像已 byte 對齊，但「切得過去」仍未被實測。
- **另有發現（未改動文件）**：handoff「目前狀態」段宣稱 node0 live lane 為 `deepseek`／
  `deepseek-nvfp4`，但本輪 09:22 快照顯示 node0 實際跑的是 **`aeon-vllm-27b`（Up 2 days）**；
  此落差本輪**不處理**（非本次範圍）；使用者已裁定（2026-10-15）：現行 `gb10-single` 模式的
  `comfyui-jdaln` 是**刻意進行中**的部署／調試狀態，TP2 `deepseek`／`deepseek-nvfp4` 為
  **後續目標態** → 「目前狀態」該段**暫不校正**。

### 2026-10-15（續四）— 外部 agent 遠端使用指南 + 三個已實測 payload（生圖／生影片）

**起因**：使用者以 hermes-agent（本地 strix-halo + LM Studio 為 text provider）／presenton
（image provider = Node1 `:8188`）呼叫 `comfyui-jdaln`，agent 回報
「`CheckpointLoaderSimple` 是空的、要求把 Z-Image-Turbo 主模型裝進 `models/checkpoints/`」。

**根因（實證，非部署故障）**：Z-Image Turbo 是**三段式**資產（UNET + text encoder + VAE），
不是 all-in-one checkpoint。node1 上 `ComfyData/models/checkpoints/` **目錄不存在** →
`CheckpointLoaderSimple.ckpt_name` 回傳 `[]`（**觀察正確、結論錯誤**）；正確的 loader 清單
齊全：`UNETLoader` 有 `z_image_turbo_bf16.safetensors`、`CLIPLoader` 有 `qwen_3_4b`
（`type=lumina2`）、`VAELoader` 有 `ae.safetensors`。機器上的官方範本
（`custom_nodes/ComfyUI-Simple-Prompt-Batcher/examples/z-image_simple_prompt_batcher.json`）
自己的 MarkdownNote 就寫明是 `diffusion_models/` + `text_encoders/` + `vae/`，**沒有**
`checkpoints/`。2026-10-14 的 smoke test 用的是 `UNETLoader` 系接線，故「當時成功」與
「現在 checkpoints 空」**不矛盾**。⚠️ **不可**把 UNET 檔複製進 `checkpoints/`：
`CheckpointLoaderSimple` 需要檔案內同時含 CLIP+VAE，UNET-only 的 safetensors 會載入失敗。

**本輪實測（node1 `spark-8095`，ComfyUI 0.38.0，`http://192.168.23.216:8188`）**

| 任務 | 結果 | 耗時 | 產出 | sha256 |
|---|---|---|---|---|
| z-image（文生圖）| `success / completed` | **~16 s** | `z-image_check_00001_.png` 709,638 B | `70150063…b8e5` |
| MiniMax H3 **i2v**（圖生影片）| `success / completed` | **834 s** | `MiniMax_H3_i2v_guide_00001_.mp4` 2,248,032 B | `5025954c…7a12` |
| MiniMax H3 **t2v**（文生影片）| `success / completed` | **755 s** | `MiniMax_H3_t2v_guide_00001_.mp4` 4,627,422 B | `af32cc38…5d4a` |

三個檔案以 `GET /view?type=output&filename=…`（LAN，免認證）抓到操作機 Windows `Downloads\`，
**sha256 與節點端逐一相符**；兩支 mp4 皆為 `ftyp isom`、24 fps、124 幀（≈5.2 s）含音訊軌。

**MiniMax H3 接線重點（取自原生 blueprint `ComfyUI/blueprints/Image to Video (MiniMax H3).json`
的 subgraph 展開）**：`UNETLoader`（`minimax_h3_fl2va_pruned_int8_convrot.safetensors`）+
`CLIPLoader`（`qwen3vl_32b_minimax_h3_nvfp4_awq.safetensors`，`type=minimax`）+
video/audio 兩個 `VAELoader`；`MiniMaxH3ImageToVideo` 同時輸出 `CONDITIONING` 與 `LATENT`
（**不需要** `MiniMaxH3SigmaShift`／`MiniMaxH3AddGuide`／`EmptyMiniMaxH3LatentAV`）；
`BasicScheduler(simple, 20, 1.0)` + `KSamplerSelect(res_multistep)` + `RandomNoise` +
`BasicGuider` + `SamplerCustomAdvanced` → `VAEDecode`/`VAEDecodeAudio` → `CreateVideo(fps 24)`
→ `SaveVideo(format="mp4")`。`length` 必須落在 **17k+5 格**（124 ≈ 5.2 s；訓練範圍約 124–362）。
**文生影片＝同一張圖省略 `first_frame`**（實測通過）。預設值為**無 LoRA、20 steps**（blueprint 的
`PrimitiveBoolean=false`）；要 8 步可掛 `loras/minimax_h3_fl2v_turbo_8step_v1.0_comfyui_bf16.safetensors`。
**一支約 13 分鐘**（暖機後仍相同），客戶端 timeout 必須放大。已知限制：
`MiniMaxH3ReferenceToVideo` 缺 `minimax_h3_ref2va` 權重**不可用**；51 個 MiniMax 節點中 12 個是
雲端 API 節點。

**交付**：`docs/COMFYUI_JDALN_REMOTE_USAGE_GUIDE_2026-10-15.md`（端點／黃金規則／API 合約／
兩份可直接照抄的 payload／輸出輸入位置／bash 流程／症狀對照表；repo 版另加維護規則
「換 image 或 asset profile 後須重驗 §2/§4/§5」）；`AGENTS.md` 的 comfyui-jdaln bullet 加指標。

**清理**：node1 `~/Downloads/output/` 的三個測試產出與 node1 `/tmp/{h3i2v,h3t2v,zprompt}.json`
已刪除（該目錄現只剩 `exp_data/`、`qwen3-tts_voices/` 兩個 custom-node 空目錄；
`~/Downloads/output/` 在鏡像範圍之外，node0 無需同步）。

### 2026-10-15（續五）— Qwen-Image 2.1 上線（簡報圖文主力）+ 解析度對齊發現 + 鏡像第二次補齊

**起因**：使用者要把「面向高階主管的簡報圖文」從 ChatGPT Plus 搬回地端，要求品質可比或更優。
選定 **Qwen-Image 2.1**（中英文字排版最強、同一份權重兼生成與編輯、原生 2K、RGBA alpha）。

**profile 擴充（node1）**：`qwen-image-2.1-t2i`、`qwen-image-2.1-edit`、`qwen-image-2.1-remove-background`
→ `COMFY_ASSET_PROFILES` 由 9 增為 **12**（`.env` md5 `a617684f…` → `53328eeb…`，逐次備份）。
下載 **33.2 GB**（UNET 7.26 GB + 文字編碼器 6.31 GB + VAE 0.68 GB + 兩個 9B prompt-enhancer 各 9.47 GB；
別名 `qwen3vl_8b_int8_convrot` → `w4a8` 由 bootstrap 自動建立）。實測速率 ~8 MB/s，約 1 小時；
`ComfyData/models` 124 GB → **173 GB**。

**我的錯誤（重要）**：第一次編輯 `.env` 時腳本只跑在 **node0**（未 ssh 進 node1），改到的是
**node0 鏡像副本**；`gb10-single restart node1` 讀的是 node1 的 `.env`，所以**什麼都沒下載**
（40 分鐘毫無動靜、容器 log 只有正常啟動訊息）。修正：node0 `.env` 還原回 `ebaceadc…`（parity 回復），
改在 **node1** 套用後重啟才真正下載。**教訓：`gb10-single` 的目標節點是 node1，`.env` 必須改在 node1。**

**實測結果（node1，25 步 / cfg 1 / euler / simple，同 seed）**

| 任務 | 輸出 | 耗時 |
|---|---|---|
| t2i 1280×720（兩者皆 /16）| 1280×720 | 20 s |
| t2i 1920×1080（1080 非 /16）| **1920×1088**（被補齊）| 60 s（含冷載入）|
| t2i 1920×1088 | 1920×1088 | **50 s** |
| t2i 2752×1536（原生 2K 16:9 桶）| 2752×1536 | **111 s** |
| t2i 1920×1088 + cfg 2.5 + 品質負面詞 | 1920×1088 | 90 s |
| edit（2 參考圖、1024²）| 1024×1024 | 20 s |
| **remove-background**（`angry_broccoli.png`）| 1024×1024，**alpha (0,255) 真透明** | 20 s |
| **16:9 簡報改圖**（EmptyLatent 1920×1088 + resolution 1440）| 1920×1088 | 50 s |

**四個技術發現（都已寫進指南 §5b）**

1. **輸出寬高必須是 16 的倍數**：非 /16 會被 `pad_to_patch_size`（circular padding）補齊且**不裁回**。
   1920×1080 → 1920×1088（=1.7647）→ 16:9 全螢幕會左右各約 7 px 黑邊（使用者實際觀察到）。
   1080p 產線 = **渲 1920×1088 → 裁 8 列**；或用原生 2752×1536 降採樣。官方 `ResolutionSelector`
   （`aspect_ratio` + **`megapixels`** + `multiple`）以 16:9 + 2.0 MP + multiple 32 精算即得 1920×1088。
2. **`TextEncodeQwenImage21` 的 `latent` 輸出恆為方形**（= `resolution`×`resolution`），與其 tooltip 不符
   → 16:9 編輯必須改用自備的 `EmptyLatentImage`（官方範本也是走這條）。
3. **autogrow 在 API 格式是巢狀 dict**：`"images": {"image_1": ["6",0], "image_2": ["7",0]}`（名稱 `image_1`…`image_16`）。
   傳扁平 `"image_1": [...]` 會得到 `execute() got an unexpected keyword argument 'image_1'`。
   編輯／去背**必須接 `vae`**（參考 latent 會 splice 進序列）。
4. **t2i 的 RGBA 不等於去背**：一般生成 alpha 實測 `(244,255)` 幾乎全不透明；只有明確要求去背才會得到 `(0,255)`。

**官方依據（查證）**：ComfyUI 內建 `ResolutionSelector` 文件；Qwen-Image 2.1 原生桶
2048²/2400×1792/2528×1696/**2752×1536**；comfy.org Q&A（原生 2K、RGBA、「遠超 2048 級會讓曝光不穩」、
`resolution` 為參考圖重設大小）；ComfyUI Wiki（**小 CFG + 品質負面提示詞可讓圖內文字更銳利**；
CFG 不可 <1）。

**交付**：`docs/COMFYUI_JDALN_REMOTE_USAGE_GUIDE_2026-10-15.md` **rev 2**（新增 §5b：三 profile 表、
`/16` 規則、A/B/C 三種品質模式與實測時間、t2i payload、edit/去背的兩個陷阱、巢狀 autogrow 範例）
→ 同日再 **rev 3**（新增 **§0「給 AI client 的 TL;DR」**：最小迴圈 bash、依任務選模型對照表、
四條會讓 naive client 失敗的規則；新增 **§9 node0 failover**：`gb10 stop` → `gb10-single use
comfyui-jdaln node0`、兩節點對照表、信任鏡像前的驗證值）；
`AGENTS.md` 的 comfyui-jdaln bullet 更新（12 profiles、/16 規則、指南指標）。使用者已確認 A（直接渲 1088
裁成 1080）為預設、B 為 hero 用、C 為文字加強。

**鏡像第二次補齊（node1 → node0，CX7）**：`rsync -aHAX --no-o --no-g --delete`，**rc=0、53 秒、621 MB/s、
收到 33.2 GB**（create 11 = 10 檔 + 1 連結、delete 4）；驗證兩端 **114,396 檔 / 16,317 目錄 / 7 連結**、
`.env` md5 **`53328eeb…`** 相同、`qwen_image_2.1_int8_convrot` sha256 `cb74113c…` 相同、node0 非 eye 條目 **0**；
node0 stack 173 GB、磁碟 51%（node1 53%）。

**清理**：node1 `ComfyData/input/slide16x9_source.png`（我為 16:9 測試複製的臨時檔）已刪除；
`~/Downloads/output/` 的測試產出留在 node1（在鏡像範圍外），本機 `C:\Users\Sawaichi\Downloads\`
保有 A/B/C/D 四個 1080p 對照版本與各原始檔。

**待辦（未做）**：把 edit／去背也一併做成 16:9 的標準步驟（已驗證可行，尚未寫成固定模板）；
簡報用的 prompt 模板與風格固定（同一 seed + 模板）尚未系統化。

### 2026-10-15（續八）— (a) Z-Image Base + (b) FLUX.2 Klein 4B + (c) Qwen-Image Layered 三項安裝與實測（指南 rev 6）

**使用者指示**：先做 (a) Z-Image Base → (b) FLUX.2 Klein 4B；並且「Qwen-Image Layered 也補安裝下載」。

**安裝結果**（全部 node1，最後一次 mirror 後兩端一致）

| 項目 | 檔案 / 大小 | 方式 |
|---|---|---|
| **Z-Image Base** | `z_image_bf16.safetensors` 12,309,866,400 B（sha256 `996a67d3…`）| **手動檔**：套件無此 profile，藍圖 `Text to Image (Z-Image-Base)` 期待此檔名；encoder/VAE 與 Turbo 共用 |
| **FLUX.2 Klein 4B** | `flux-2-klein-4b-nvfp4` 2.46 GB + `flux2-vae` 336 MB（`qwen_3_4b` 已在）+ 2 官方樣本 | profile `flux2-klein-4b-edit` |
| **Qwen-Image Layered** | **改用 `qwen_image_layered_fp8mixed` 20,533,591,821 B**（原 manifest 指向 bf16 40.86 GB）+ `qwen_2.5_vl_7b_fp8_scaled` 9.38 GB + layered VAE 253,816,616 B | profile `qwen-image-layered-core`；並建立 `qwen_image_layered_bf16 → fp8mixed` **symlink**（套件 alias 慣例）讓 bootstrap 不再抓 40 GB bf16 |

`.env` 由 12 → **14 個 profile**（md5 `53328eeb…` → **`394b3c61…`**）；重啟 **21 秒 READY**。
**nvfp4 查證**：Comfy-Org 對 Layered **沒有** nvfp4（只有 bf16 與 fp8mixed）；社群有 QuantStack/Unsloth 的
GGUF（Q2–Q8），且本機 **已裝 ComfyUI-GGUF**（`UnetLoaderGGUF` 等節點在）→ 需要省資源時可走 GGUF。

**實測**

| 測試 | 結果 | 耗時 |
|---|---|---|
| Z-Image **Turbo** 1280×720（4 步 cfg 1）| 成功 | **10 s** |
| Z-Image **Base** 1280×720（**40 步 cfg 4.5**，真負面詞）| 成功 | **60 s** |
| Z-Image **Base** 1920×1088（同上）| 成功 | **141 s** |
| seed 多樣性（同 prompt，seed 111 vs 222，MAD 0–255）| **Turbo 55.75 / Base 67.53** | — |
| **FLUX.2 Klein** 樣本（1 MP）| 成功 752×1360 | **20 s** |
| **FLUX.2 Klein** 簡報改字（2.09 MP）| 成功 **1952×1104** | **10 s**（暖機） |
| **Qwen-Image Layered** 3 層 @1920×1088 | 成功 3 張 RGBA；**第 2/3 層 alpha (0,255) 真透明** | **814 s（13.6 分）** |

⚠️ **社群說法未重現**：常見「Turbo 換 seed 幾乎不變」在本機**不成立**（MAD 55.75 vs 67.53，兩者都變化明顯）；
已在指南 §10.3 據實標註「Base 變化較大，但 Turbo 並非靜態」。

**新接線（已寫入指南 §5c / §5d）**

- **Klein 4B distilled**：`UNETLoader(flux-2-klein-4b-nvfp4)` + `CLIPLoader(qwen_3_4b, type=flux2)` +
  `flux2-vae`；**4 步、CFGGuider cfg=1、euler、`Flux2Scheduler(4)`**；參考圖以 `VAEEncode → ReferenceLatent`
  注入正/負分支（負分支 = `CLIPTextEncode → ConditioningZeroOut → ReferenceLatent`）；
  輸出尺寸**跟隨縮放後的參考圖**（`ImageScaleToTotalPixels` → `GetImageSize` → `EmptyFlux2LatentImage`）。
- **Qwen-Image Layered**：`UNETLoader(qwen_image_layered_bf16/fp8mixed)` + `CLIPLoader(qwen_2.5_vl_7b_fp8_scaled, qwen_image)`
  + `qwen_image_layered_vae`；`ModelSamplingAuraFlow shift 1`；**KSampler 20 步 / cfg 2.5 / euler-simple**；
  latent 用 **`EmptyQwenImageLayeredLatentImage(w,h,layers,batch)`**（layer 數是節點參數）；
  輸出經 **`LatentCut(dim=t,index=1,amount=16384) → LatentCutToBatch(dim=t,slice_size=1)`** → `VAEDecode`
  → 每層一張 PNG。成本隨 **像素 × 層數** 成長（藍圖預設僅 640×640 / 2 層）。

**兩個流程失誤（同一根因，已寫進指南 §11.4 紅字警示）**

1. 第一次改 `.env` 時腳本跑在 **node0**（未 ssh 進 node1）→ 改到鏡像副本，服務毫無變化（40 分鐘無下載）。
2. 下載 Z-Image Base 的啟動腳本同樣在 **node0** 執行 → 12.3 GB 下到 **node0**（事後經 CX7 修正並驗證 sha256 相同）。
   → 規則：**所有 lane 變更必須在 node1 執行**；並改用「**主機側預抓 → 之後一次快速重啟**」避免 bootstrap
   在下載期間（50 GB 級）讓服務停機。

**鏡像第三次補齊**：`rsync -aHAX --no-o --no-g --delete`（**注意：`--no-own` 不存在，會 rc=1**），
**rc=0、33.0 GB、653 MB/s**；兩端 **114,406 / 16,317 / 9**、`.env` md5 `394b3c61…`、4 個新權重 sha256 全部相同、
node0 非 eye 條目 0；node0 stack 215 GB、磁碟 52%（node1 54%）。

**交付**：指南 **rev 6**（新增 §5c Klein、§5d Layered；§10.3 填入 Base 實測值並更正 seed 多樣性說法；
§11.2/11.3 標記已安裝；§0 決策表加 3 列）；`AGENTS.md`（14 profiles、Base 手動檔、Layered fp8mixed+symlink、鏡像事實）。

**本機成品**（`C:\Users\Sawaichi\Downloads\`）：`zt_s1/s2`（Turbo 兩 seed）、`zb_s1/s2`（Base 兩 seed）、
`zb_final`（Base 1920×1088）、`klein_s1`（樣本）、`klein_slide`（簡報改字、1952×1104）、
`layered_00001..3`（三層，含透明層）。

### 2026-10-15（續九）— MiniMax H3 能力擴充：turbo LoRA 實測 + Easy 分段長片 + ref2v（指南 rev 6 續）

**turbo / 4-step LoRA（0 GB，已有權重）實測**（t2v, 1344×768, 124 幀, seed 7, 暖機）：

| 設定 | 耗時 | 加速 |
|---|---|---|
| 20 步（基準）| **755 s** | 1.0× |
| + `fl2v_turbo_8step_v1.0` LoRA，steps=8 | **362 s** | **2.1×** |
| + `fl2v_turbo_4step_v1.2_768p` LoRA，steps=4 | **201 s** | **3.8×** |

擬合得 **每步 ≈40 s + 固定開銷 ≈40 s** → 可預測排程。

**Easy 分段長片（3D latent upscaler 安裝 + 驗證）**：`minimax-h3-easy` profile 加入 `.env`；
唯一缺檔 **3D latent upscaler** —— **套件 manifest 的 URL 是錯的（404 → 15-byte 錯誤頁）**，正確檔在
`LBH-123-AI/Minimax_h3_latent_Upscaler` 的 `minimax_h3_latent_upscaler_3d_conv_v1/…_fp16.safetensors`
（690,592,672 B），以 manifest 期望檔名裝入 `latent_upscale_models/`（bootstrap 之後會跳過）。
**實測：10 秒影片（2 段 ×5 s、16:9、1344×768、480P）＝ 181 秒**，用官方配方
`MiniMaxH3EasyLoader → ContextSegments(context_segments) → ModelAttentionBackend("comfy kitchen attention")
→ 4 步 LoRA → BasicScheduler(beta, 4) → SegmentRender → SegmentDecode → SaveVideo`。
兩個 API 陷阱：① **`ModelAttentionBackend.attention` 是 UI widget，API 模式必須明示**（否則
`validate_inputs() missing 'attention'`）；② `SegmentRefine` 需要 `latent_upscale_model`（即上述 upscaler）。

**ref2v（+20.97 GB）安裝與實測**：新增 `minimax_h3_ref2va_pruned_int8_convrot.safetensors`
（20,970,379,616 B）＋ profile `minimax-h3-ref2v` 加入 `.env`（**16 個 profile**，md5 `f3525434…`）。
**實測：`MiniMaxH3ReferenceToVideo` + 參考圖（`portrait_model_denim.png`）→ `h3_ref2v_00001_.mp4`
（2,274,025 B），768 秒（20 步、1344×768、124 幀）** —— 與 t2v 基準同級。
兩個 API 陷阱：① 參考輸入是 **autogrow**，API 格式為**巢狀 dict 且名稱為 `ref_image_0…8`／
`ref_video_0…2`／`ref_video_audio_0…2`／`ref_audio_0…2`**（扁平 key 會驗證失敗）；②
**`ref_image_size` 只接受 `match` / `max`**（不是 Easy 的 1k/2k 清單；`max` = 2048 短邊、身分保真最佳）。

**下載插曲**：ref2v 下載在 3.15 GB 時遇到 **curl rc=92（HTTP/2 stream error）**、runner 因未涵蓋該錯誤類別
而結束、`.part` 靜靜停住（log 才有跡象）→ 以 `-C -` 續傳並補上
**`--retry-all-errors --speed-time 60 --speed-limit 1024`**；此教訓已寫進指南 §11.4。

**鏡像第四次補齊**：**rc=0、21.68 GB、447 MB/s**；兩端 **114,412 / 16,320 / 9**、`.env` md5 `f3525434…`、
ref2va 與 3D upscaler sha256 MATCH、node0 非 eye = 0；node0 stack **236 GB**、磁碟 52%。

**交付**：指南新增 **§5.1**（LoRA 加速階梯 + 三個擴充選項對照）、**§5.2**（Easy 分段長片配方與參數表）、
**§5.3**（ref2v 完整 payload 與兩個陷阱）；§0 決策表加長片列；§11.2 更新 H3 列；
`AGENTS.md`：16 profiles、upscaler URL 缺陷、鏡像第四次事實。
commit `04f83c6`（LoRA 階梯）→ `d26611b`（Easy）→ `a8d90d8`（預抓強化）→ 本輪 ref2v 追加。

### 2026-10-16（續十）— (c) 簡報 prompt 模板 + `scripts/comfy-slide.py`（指南 rev 7）

**使用者裁定**：影片擴充先告一段落，回到 (c)：讓 hermes-agent 能**一致地**產出整份簡報。

**新增 `scripts/comfy-slide.py`**（stdlib-only；PIL 有就用、否則退 ImageMagick、否則回報略過）：
輸入提示／模式／尺寸／seed → 組出**已驗證的 payload** → `POST /prompt` → 輪詢 `/history`
→ `/view` 下載 → **自動裁成精確 1920×1080** → 印出可解析的 JSON 摘要。
子指令：`--check`（服務版本＋佇列）、`--models`（列出可用 unet/clip/vae/input 檔名）、`--dry-run`。
模式：`qwen21 a/b/c`、`z-image a/b`、`edit`（需 `--reference`）、`layers`（需 `--reference`，每層一張 PNG）。
`COMFY_URL` 可切 node0；`COMFY_WAIT` 可調等待上限；prompt 拒絕／`execution_error`／逾時皆**非零退出**。

**五條路徑實測（本機 Windows 直接呼叫 node1）**

| 指令 | 耗時 | 產出 |
|---|---|---|
| `--model qwen21 --mode a` | **56 s** | 1920×1088 → 自動裁 **1920×1080**（offset 0,4）|
| `--model qwen21 --mode b`（hero）| **116 s** | 2752×1536 → 縮成 1935×1080 → 裁 **1920×1080** |
| `--model z-image --mode a` | **20 s** | 1280×720（草稿）|
| `--model edit --reference …` | **51 s** | 1920×1080 |
| `--model layers --reference angry_broccoli.png --layers 2 --size 640x640` | **261 s** | 2 張 PNG（`out-1/-2`）；**尺寸跟隨參考圖**（896×1152，`--size` 無效 → 已在說明中標註）|

**指南 §12（新）**：三分塊 prompt 模板（LAYOUT＝整份簡報固定／CONTENT＝每頁視覺／TEXT＝僅在圖上需有字時，
且**精確引號 + 「must read exactly」**）；一致性規則（`--style deck-style.txt`、固定負面詞、整份用模式 A、
seed family＝base+頁碼、逐頁記錄）；已驗證的完整範例與指令；輔助腳本的用法、JSON 契約與**不做的事**
（不批次、不檢查文字正確性、不含影片）；交稿前 QA 指向 §10.8。同步更新 §0 指標與版本行（rev 7）。

**本機成品**：`C:\Users\Sawaichi\Downloads\c-slide-test\`（q21_a、q21_b、zi_a、edit、layer-1/2）。

### 2026-10-15（續六）— 簡報產線定案：兩條獨立工作流 + 模型選擇查證（指南 rev 4）

**使用者指正**：我原本把「Z-Image Turbo 出草稿 → Qwen-Image 定稿」寫成一條混用管線，那是我的
假設而非事實。使用者指出 z-image 與 qwen-image **可以各自獨立成流程**，且 **Qwen-Image 2.1 的
t2i + edit 本身就是完整產線**。查證後確認使用者正確，已據此改寫指南 §10。

**查證結果（2026-10-15 網路）**

- Qwen-Image 系＝**文字準確度冠軍**：「posters, banners, UI mockups, product labels, social graphics」；
  「Nothing local renders text better」；Qwen-Image 2.1 = 同一份權重同時做生成與編輯（t2i + edit
  ＋remove-background 共用核心，**不需要第二個模型**）。
- Z-Image Turbo＝**速度與寫實**：6B 蒸餾、8 步、資料中心 ~2–3 s；強項寫實/人像/產物；評語「realism
  better, diversity narrower」。可信評測（diffusiondoodles）：「Text rendering is not as strong as
  Qwen Image or Flux.2. It will do the basics but **do not expect longer text to work**」。
- **混用管線只是零星說法，非主流做法**；主流建議是「用對的模型做對的事」。
- ⚠️ **有行銷比較頁聲稱「Z-Image Turbo lacks text rendering support entirely」＝錯的**（本機實測
  Z-Image 就生出了可讀的 headline）→ 這類比較頁可信度低，以本機 A/B 為準。

**本輪實測（node1）**

| 項目 | 結果 |
|---|---|
| Z-Image Turbo 草稿 1280×720（4 步）| **10 s**（RGB）|
| Z-Image Turbo 1920×1088（4 步）| **20 s**（RGB，**無 alpha**）|
| Z-Image 草稿 → Qwen-Image 2.1 **edit 定稿**（cfg 2.5, resolution 1440, EmptyLatent 1920×1088）| **100 s** → 1920×1088（RGBA）；版面保留、字重繪 |
| Qwen-Image 2.1 1920×1088 定稿 | 50 s（RGBA）|

可供肉眼比較的檔案（本機 `C:\Users\Sawaichi\Downloads\`）：`E_草稿_zimage_1920x1080.png`（Z-Image 同 prompt）
vs `F_定稿_qwen21_1920x1080.png`（Qwen 2.1 重繪）。

**交付**：指南 **rev 4** 新增 **§10 簡報產線**：§10.1 選模型對照表（附社群依據與「別信行銷比較頁」的提醒）、
**§10.2 Workflow A = Qwen-Image 2.1 t2i+edit 自成完整產線**（A1 草稿 1280×720 20 s → A2 定稿 A/B/C →
A3 用 edit 改字改版面 → A4 裁 1080p；全程同一模型、無切換成本）、§10.3 Workflow B = Z-Image Turbo 純影像
（含 union ControlNet 鎖版面、RGB 無 alpha 的限制）、§10.4 可選混用（已驗證但非標準）、
§10.5 1080p 16:9 裁切契約（渲 1920×1088 → 裁 8 列；PIL / ImageMagick / PowerShell 三種指令；
hero 模式 2752×1536 → 1935×1080 → 裁邊）、§10.6 批次與排程（單 GPU 序列化、**依模型分組**避免權重反覆載入、
10 張簡報 ≈ 10 分鐘 GPU 時間、可直接用的 python helper）、§10.7 一致性與可重現（記錄 prompt/seed/模式、
固定 style block 與負面詞、同一 seed family）、§10.8 交稿前 QA 清單。

### 2026-10-15（續七）— Z-Image「Base + Turbo」同家族配對 + 模型組合擴充框架（指南 rev 5）

**使用者指正（第二次）**：z-image / z-image turbo 本身也是「一個組合」——快速簡單純圖像時的另一個選擇；
不排除與 qwen-image 混用，但要看需求目的與工作流；且未來會擴充 FLUX.2 / Krea 2 / Ideogram 等別的
圖像生成路徑（目的不一定是簡報，也可能混用）。查證後全部成立，已改寫指南 §10.3 並新增 §11。

**Z-Image 查證重點**（ComfyUI 官方部落格 + 評測）

- **Base 與 Turbo 是同一個 6B 架構、共用同一個 text encoder（`qwen_3_4b`, lumina2）與 VAE（`ae.safetensors`），
  只差一顆 UNET**（Base = `z_image_bf16.safetensors`，Turbo = `z_image_turbo_bf16.safetensors`）。
- **Turbo**：4–8 步、**CFG 1**（官方 `guidance_scale 0.0`，**負面提示詞等於無效**；ComfyUI 只有 CFG>1 才會
  重新引入負面減除，並開始出現 Turbo 副作用）；**不同 seed 會生出很相似的圖**（已知缺點 → 草稿要多變 prompt）。
- **Base**：**30–50 步、CFG 3–5**（官方部落格原文）、細節/藝術上限更高、**seed 多樣性高**、**負面提示詞有效**、
  也是 LoRA 訓練的基礎；官方定位兩者為搭檔（*"Z-Image Base: A Partner for Z-Image Turbo"*）。
- **本機現況**：只有 `z-image-turbo-core` 與 `z-image-turbo-union-control` 兩個 profile，**沒有 base profile**，
  但藍圖 `Text to Image (Z-Image-Base)` 已內建並期待 `z_image_bf16.safetensors` → 要開 Base 只需**手動放一顆
  ~12 GB 的 UNET**（encoder/VAE 已共用），不需 .env profile。

**擴充框架（§11）**：定調「**每個家族都要能自成完整流程**（t2i + edit + turbo/lightning 變體共用核心）」，
跨家族混用**必須有理由**（鎖構圖、超解析、去背、風格轉移），不是預設。候選清單含實測下載量：
FLUX.2 Klein 4B **+2.8 GB**（最便宜的實質升級）、Krea 2 Turbo 13.16 GB／RAW 18.63 GB、Ideogram v4 NVFP4
21.91 GB、Qwen-Image 2512 Lightning 31.76 GB、Mage-Flow Edit Turbo 17.46 GB、Z-Image Base ≈12 GB（單顆 UNET）、
FLUX.2 Dev（**只有藍圖、無 profile** → 手動放檔）；另註明 LTX-2.5 是 `gated`（需一次性授權）。
並寫入「新增家族的六步程序」（plan_downloads 乾跑 → 改 node1 `.env` → 重啟（下載期間 `:8188` 是關的、
約 8 MB/s）→ 驗證 `/object_info` → 實測一張 → rsync 鏡像回 node0）與選型對照表。
