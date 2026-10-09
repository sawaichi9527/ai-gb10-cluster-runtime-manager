# handoff.md — ai-gb10-cluster-runtime-manager（本機 checkout）

> 本檔是本機中繼 checkout 的交接摘要。主要開發在 **node0**（`~/workspace/ai-gb10-cluster-runtime-manager`，branch **`main`**；2026-09-29 實測 node0 為 `main`／upstream `origin/main`、工作區乾淨 —— 舊文件寫的 `keystone` 已於 `496c9b1` 併入 main、**非**現役 checkout）＋ Forgejo `829522`；本機僅作中繼存取，修改前先確認是否應改在 node0。
> 建立：2026-09-18；更新：**2026-09-20**（DeepSeek V4 Flash **Vision-Exp** lane 上線：同一顆 Anemll image + 啟動 wrapper；bench-c / bench-ctx / bench-mm 實測；`cluster-up` 新增 `SYNC_DIRS` 自動同步 patch 目錄；**vision 開 prefix caching + `dspark-swa-prefix` hotfix**、長上下文邊界 261K/262144、圖片高併發 C=8/16；本檔納入版控並同步三方）；**2026-09-29** 上游查核（Anemll 無新 image/tag、MiaAI-Lab main 未動且 23 檔 byte 全同）→ 見「定期檢討追蹤」；**2026-09-29（後續）** qwen38flash 對齊上游 `2c86a1d0`（GMU 0.80／prefix caching ON／block-drop backport／index share）並完成冷啟驗證（READY、KV 29.88 GiB、無回歸）→ 見「qwen38flash 對齊上游 + 冷啟驗證」；**2026-09-29（後續之二）** DeepSeek-V4.1-Flash **EXL3 2×GB10 選型查核**（取得兩顆可下載 arm64 image 的 digest、證實 sfxnz image 未發佈、TP=2 對 3.5bpw 不可行、各線 benchmark 與 NVIDIA 論壇口碑）→ **本輪不新增 lane**（維持 `deepseek-vision` 為 2-Spark 多模態），詳見 `docs/DSV41_FLASH_EXL3_2X_SPARK_EVAL_2026-09-29.md`；**2026-09-30** 上游再查核（deepseek 與 deepseek-vision 的 **image／配方／官方權重皆無更新** → 兩 lane 現行設定即為最新、無需變更，含首度補查官方權重 commit 比較，見 `docs/DEEPSEEK_UPSTREAM_REVERIFY_2026-09-30.md`）；**2026-09-30（續）** 27b／35b 上游再查核（兩 lane 共用的 `ghcr.io/aeon-7/aeon-vllm-ultimate` 最新 dated tag 仍 `2026-09-18-v0.29.0-omni`＝現行 pin、digest 不變；27B/35B 四個 HF 來源 body/drafter 最後 commit 為 09-18／08-19／07-15／06-28，**皆無 09-19 後更新** → 無需變更，見 `docs/QWEN_27B_35B_UPSTREAM_REVERIFY_2026-09-30.md`）；**2026-10-03** `mimo26flash` lane 上線（MiMo V2.6 Flash MOPD，TP2 vLLM+DFlash，見同名章節）；**2026-10-05** `mimo26flash` NVFP4 變體 A/B + DFlash cliff 探測（兩變體皆過）→ **定案 MXFP4**、延後調優 C/D/E 註記於 docs §7、**服務切回 `deepseek`**、README 同步 → 見「2026-10-05」章節；**2026-10-07** DeepSeek **V4 Flash Vision** 同 image 調優 A/B（V0–V5 + V-win，獨立 `deepseek-vision-tune` lane）→ **只升一個旋鈕 `--long-prefill-token-threshold 1024→0`（V3）**，`deepseek.conf` 全程未動、生產 gate 全過；記錄 production lane boot 散佈 8.1% 無法驗證 2.7% 效應、cold prefill 32K 判為噪聲、garble soak `thinking:true` false alarm → 見「2026-10-07 — DeepSeek V4 Flash Vision」章節；**2026-10-07（續）** `deepseek-nvfp4` lane **建置**（NVIDIA NVFP4 0731 checkpoint + `eugr/spark-vllm-b12x`，Phase 1–2：下載/傳輸 + profile/白名單/文件，**Phase 3 開機另排**）→ 見「2026-10-07 — deepseek-nvfp4 lane 建置」章節；**2026-10-08（續）** `deepseek-nvfp4` **Phase 3 完成**（boot ×4：seccomp/safetensors 兩個啟動修復 → DSpark acceptance 垃圾 draft 根因＝共享 NVFP4 quant dict 把原生 MXFP4 draft 建成 ModelOptNvFp4（上游 #49133 closed）→ `hotfix-dspark-draft-mxfp4` 容器啟動補丁 → **全 gate PASS**：acceptance 2%→**27%**（temp0，pos0 0.629）／**49–59%**（temp0.7）、單流 16→**33.6 tok/s**、prefix-hit 44.8×、garble 3/3、compose-verify 過）→ 見同章節「Phase 3」；**2026-10-08（三）** C1–C8 完整併發 benchmark（47.1→**129.9 tok/s**、**2.76×**、accept 41–50% 全程不崩）+ `bench-c.sh` metrics scrape auth 修正（`/metrics` 401）、**NVFP4 KV（`nvfp4_ds_mla`）A/B 負結果**（三重硬閘、回退 fp8）→ README「已部署服務」正式列入 `deepseek-nvfp4`（**現役**）+ benchmark 區塊重寫，tag **`v1.5.0`** → 見 Phase 3 第 6/7 項與「版本標記」
> **2026-10-09**：`deepseek-vision` **配方繼承（promote）**——對決 `eugr/spark-vllm-b12x:latest` + `deepseek-v4-flash-vision-exp-ablit`（候選 lane `deepseek-vision-b12x`，B0/B1/B2 三 boot）vs README 舊配方記錄：decode Σ 535.3/545.9 vs 538.1（−0.5%/+1.4%，持平）、prefill 131K–261K 全欄 **+9~14%**、accept +1pp、prefix-hit 正確性 gate **無需任何 hotfix 即過**（HIT 50.9×、輸出位元組一致）→ 條件成立。**唯一升版旋鈕 `CUDAGRAPH_CAPTURE 48→56`**（上游 verbatim 48 於 C7/C8 掉 capture range，Σ −6%）。新 `deepseek-vision.conf` 已改寫（原生 vision、無 `CMD_WRAPPER`/`SYNC_DIRS`）；舊 Anemll 配方 byte-identical 封存 `cluster-profiles.d/_backup/`（含還原步驟），`patches/dspark-vision/` 原地保留為備用方案；**舊官方模型 `models/deepseek-v4-flash-vision-exp` 依使用者決定兩節點暫留、後續再議**。詳見 `docs/DEEPSEEK_VISION_B12X_RECIPE_AB_2026-10-09.md`。另依使用者決定，舊配方的 A/B lane `deepseek-vision-tune{,.conf.base}` 同日**歸檔**至 `cluster-profiles.d/_backup/`（白名單移除；未來 vision 調優需從新配方另立 lane）。
> **2026-10-09（續）**：`deepseek`（mainline）**配方繼承（promote）**——對決 `eugr/spark-vllm-b12x:latest` + `deepseek-v4-flash-0731-dspark-ablit`（drowzeys Anchored-Tensors；候選 lane `deepseek-b12x`，D0 單 boot）vs README E5 記錄：decode Σ **693.3 vs 670.7（+3.4%，8/8 格全正）**、prefill 131K–261K **+16~18%**、accept **+2.3pp（33.4%）**、prefix-hit 正確性 gate **無需任何 hotfix 即過**（HIT 38.5×、輸出逐字一致）、soak（3×3 完整性、garble 3/3、262K 近硬限、health 200）全過 → 條件成立。配方差異：KV fp8（nvfp4_ds_mla 此 image 不可行）、**capture 64**（公式 8×(k+1) 配保留的 k=7；上游 48 是配 k=5）、batched 8192、GMU 0.85、無 `CMD_WRAPPER`/`SYNC_DIRS`/patches。新 `deepseek.conf` 已改寫；舊 Anemll 配方 byte-identical 封存 `cluster-profiles.d/_backup/deepseek-anemll.conf`（SHA256 `3147b4e9…`，含還原步驟），`patches/dspark-vision/` 原地保留為備用方案依賴；**舊官方模型 `models/deepseek-v4-flash-0731-official` 依使用者裁定兩節點暫留、後續再議**。候選 lane `deepseek-b12x.conf` 已刪、白名單還原。過程記錄：profile 寫入 `COMPILATION_JSON` 轉義反斜線導致 boot arg 錯誤（修正＋harness 加 90s 早錯檢查）；soak 兩個假警報（腳本未 source `cluster-common.sh` 致 401；verbose 列舉格式打滿 400 tok 預算——皆非模型回歸）。詳見 `docs/DEEPSEEK_B12X_RECIPE_AB_2026-10-09.md`。**待辦**：`deepseek-tune` 是舊配方的 byte-copy，sibling 前提已過時（re-base 或歸檔，待使用者裁定）。
> **2026-09-20（後續）**：**Qwen3.8 Flash-Next 125B NVFP4（TP2+EP、MTP3）上線**；同日起 **compose 為唯一啟動 lane**（移除 docker-run 分支）；**27b/35b 改走 compose**；node0 `~/docker-stacks/aeon-vllm-omni/` 清理。詳見下方「已完成（2026-09-20 後續）」。
> **2026-09-20（後續之二）**：**node-local 佈局歸位**——每個 lane 一個以 image 命名的 `~/docker-stacks/<stack>/`（`STACK_DIR`+`COMPOSE_FILE` materialize）、**cache 每 lane 獨立**（`~/.cache/vllm-<lane>[-cluster|-single]`，移除共用的 `~/.cache/huggingface` 容器掛載）、**log 統一** `~/docker-stacks/logs/<profile>/`；刪除單機 `runtimes.d/{qwen38flash,glm53flash}.conf`。詳見「已完成（2026-09-20 後續之二）」。

## 目前狀態（本機 checkout）

- 分支：`main`，HEAD = 本檔所在的 commit（`git log -1`）；最新正式版本 tag = **`v1.5.0`**（`3201363`；`v1.4.1`→`cc76cbd`、`v1.4.0`→`6aff00d`、`v1.3.4`→`a92d2bc`、`v1.3.0`→`2474cf8`、`v1.3.1`→`276348c`、`v1.3.2`→`168cb99`、`v1.3.3`→`9bb2006`）。早期：2026-09-20 session 共 22 個 commit `a1cba34`…`79a79cb`，其後為本檔的 sync commit。live lane = **`deepseek-nvfp4`**（**2026-10-08** Phase 3 完成上線，README/handoff 詳載；主線 `deepseek` 待命 —— 使用者裁定「先不恢復」，`gb10 use deepseek` 隨時切回；`mimo26flash` 自 10-03 上線做 NVFP4 A/B + cliff 探測，**權重定案 MXFP4** 待命，見 `docs/…2026-10-03.md` §11）
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
- **ComfyUI** 部署在 Node1 為 `comfyui-aeon` / Flux 2 Dev；不回退 `comfyui-personal`/`comfyui-work`。

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
- **tag 現況**：`v1.0.0`→`496c9b1`、`v1.1.0`→`71ccf20`、`v1.2.0`→`ffd02ea`、
  `v1.3.0`→`2474cf8`、`v1.3.1`→`276348c`、`v1.3.2`→`168cb99`、`v1.3.3`→`9bb2006`、
  `v1.3.4`→`a92d2bc`、`v1.4.0`→`6aff00d`、`v1.4.1`→`cc76cbd`、**`v1.5.0`→`3201363`**。

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
