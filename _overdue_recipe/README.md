# `_overdue_recipe/` — retired recipe archives (NOT loaded, NOT deployed)

本目錄封存**已退役（退休）配方**的完整快照：封存的 profile conf、它當時部署的
compose yml、它依賴的 runtime patches，以及 `recipe_README.md`（該配方的歷史
量測／benchmark 記錄與退役原因）。

**Docker image 與模型檔不上傳**（repo 體積與授權考量）；每個子目錄在
`recipe_README.md` 記錄還原時該去哪裡取回 image／模型。

## 命名慣例

```text
<profile>_<image name + tag>_<yyyymmdd>/

deepseek_anemll-dspark-vllm-gx10-011_20261009/
deepseek-vision_anemll-dspark-vllm-gx10-011_20261009/
```

image ref（`ghcr.io/anemll/dspark-vllm-gx10:0.1.1`）中的 `/` `:` 以 `-` 取代、
tag 的點去掉（`0.1.1` → `011`）；日期 = 退役（封存）日。

## Inventory

| 目錄 | profile | image | 退役日 | 說明 |
|---|---|---|---|---|
| `deepseek_anemll-dspark-vllm-gx10-011_20261009/` | `deepseek` + `deepseek-tune` | `ghcr.io/anemll/dspark-vllm-gx10:0.1.1` | 2026-10-09 | 舊主線（官方 0731 fp8 + DSpark k=7）；被 eugr-b12x + Dspark-Ablit 配方繼承 |
| `deepseek-vision_anemll-dspark-vllm-gx10-011_20261009/` | `deepseek-vision` + `deepseek-vision-tune` | 同上 | 2026-10-09 | 舊 Vision-Exp lane（`CMD_WRAPPER` + 17 個 MiaAI hotfix）；被 eugr-b12x 原生 vision 配方繼承 |

每個子目錄包含：

- `*.conf` / `*.conf.base` — byte-identical 封存 profile（SHA256 見下表）
- `docker-compose.<profile>.yml` — **於 2026-10-09 由封存 conf 重新渲染**的
  deploy-contract compose（conf 才是 source of truth；compose 每次啟動都重渲染，
  此檔供比對／參考）。`--api-key` 已置換為 placeholder `<REDACTED:from-cluster.env>`
  —— 真實 key 在 `~/docker-stacks/config/cluster.env`，永不同時入庫。
- `patches/dspark-vision/` — 對應 repo 根目錄相對路徑的 runtime patch 快照
  （conf 的 `SYNC_DIRS` 解析 `${REPO_DIR}/patches/dspark-vision`），含 `NOTICE.md`
- `recipe_README.md` — 配方身分、歷史 benchmark 記錄、退役對決、還原步驟

封存檔案 SHA256（2026-10-09 驗證）：

| 檔案 | sha256 |
|---|---|
| `deepseek-anemll.conf` | `3147b4e99e6b040f2318b865666132f79d4ed72f9f475db0f0c48eaee78f0562` |
| `deepseek-tune.conf` = `.base` | `e0c1f2655c9c3b85686abe6d9b22097721641c4987ee2946578433a5ddfef6c` |
| `deepseek-vision-anemll.conf` | `0df27c387a380e40cb9549c20147956047429db801c76337cc2664f5869eaafe` |
| `deepseek-vision-tune.conf` = `.base` | `5e70ec4e012440b46a9e615a4cc07ac470b54e37baa71134bbb720ff0b3c7470` |

（兩組 tune `.conf` 與 `.base` 相同 = campaign 結束時已還原成 pristine 基線。）

**不入庫（by design）：**

- Docker image `ghcr.io/anemll/dspark-vllm-gx10:0.1.1` — digest pin 在各 conf
  （`IMG_SHA256`），還原步驟會要求雙節點驗證；若已被 prune 需 re-pull 到 node0
  再經 CX7 byte-transfer 到 node1
- 模型權重 — 各配方的模型路徑、pinned revision 與保留狀態見
  `recipe_README.md`

## Loader 安全性

loader（`cluster-common.sh: list_cluster_profiles`）只掃描
`cluster-profiles.d/*.conf` 頂層；本目錄在 repo 根目錄，**永遠不會被當成
live profile**。原 `cluster-profiles.d/_backup/`（2026-09/10 用途）已於
**2026-10-09 依使用者決定整併至此**：檔案 byte 內容不變，只是改成
配方自帶（conf + compose + patches + recipe_README）的目錄形態。

## 還原（rollback）總綱

各配方完整步驟見其 `recipe_README.md` 的「還原」節；通用形態：

```sh
# 1. conf 放回 live 路徑
cp _overdue_recipe/<dir>/<conf>.conf cluster-profiles.d/<live>.conf
# 2. runtime patches 放回 repo 根目錄（conf 的 SYNC_DIRS 依 ${REPO_DIR}/patches/dspark-vision 解析）
mkdir -p patches
cp -r _overdue_recipe/<dir>/patches/dspark-vision patches/
# 3. 雙節點確認 image + 模型存在（pin 見 conf；模型路徑見 recipe_README.md）
# 4. 啟動
gb10 use <profile>
#    （SYNC_DIRS 會在啟動時自動佈署 patch 目錄；fail-closed wrapper 套不上就不起服）
```

封存的 compose yml **不直接部署** —— `cluster-up` 每次啟動都從 conf 重渲染；
還原後第一次 `gb10 use` 會在節點的 stack dir 產生當下版的 compose。
