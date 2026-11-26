# Qwen 27B / 35B — aeon-vllm-ultimate 0.33 image bump（2026-11-26 起）

> 狀態：**進行中**（Phase 0）。本檔在 campaign 過程中逐步補齊；未填的欄位一律標
> `PENDING`，不要用推測值。
>
> 範圍：`27b` / `35b` 兩條 lane × 兩種部署模式（TP2 cluster、single node0），
> image 由 `2026-09-18-v0.29.0-omni` 升到 0.33 世代。**不動任何權重、不動 CLI 契約、
> 不改 sampling 預設**。

## 1. 選型（使用者裁示 2026-11-26）

| 場景 | image | 依據 |
|---|---|---|
| **TP2**（`27b` / `35b` cluster） | `ghcr.io/aeon-7/aeon-vllm-ultimate:2026-11-23-v0.33.0-omni-dflash2` | upstream 明寫多 Spark 配方留在這顆 |
| **single**（`27b` / `35b` single） | `ghcr.io/aeon-7/aeon-vllm-ultimate:2026-11-25-v0.33.0-omni-dflash2-ngram-disk` | upstream 的 1-Spark image；與前者的差別只有 file-backed n-gram/PLE offload |

- 兩顆 tag 屬**同一個** image repo，因此 stack 目錄不編碼模式或世代
  （`~/docker-stacks/aeon-vllm-ultimate/`，2026-11-26 由 `aeon-vllm-omni` 改名）。
- `--engram-config` / `/ple` **不啟用**：27b（`qwen3.8-27b-…-nvfp4-mixed`）與 35b
  （`qwen3.6-35b-a3b-heretic-nvfp4`）都沒有 Engram/PLE 表。
- **不綁任何 Python patch 檔**（0.33 release note 明文要求）；0.29 的
  `flash_attn_029_patched.py` 只在回滾時才有意義。

## 2. 新 image 事實（觀測值，非 upstream 宣稱值）

以 node0 `docker manifest inspect --verbose` 解出 arm64 子 manifest：

| | 11-23（TP2） | 11-25（single） |
|---|---|---|
| arm64 manifest digest | `sha256:37a75a0866a89cbad4f9cbf0531c72ba796483ca986858937e7d44167353ee00` | `sha256:f9080126a0649a5e209b764d5728829f15436729a89edc07122d7ee97d6ad4fb` |
| config digest | `sha256:2893164a5a11c775310ba2ee00f0198c999a878a9d2d1882c412d6e6d811d114` | `sha256:2e8751e44803bb80108e85a2ded737bab38fbb9dda30f6732776ab7693b344a0` |
| layers / 壓縮總量 | 25 / **10.52 GB** | 28 / **10.52 GB** |
| upstream 公布的 digest | `sha256:71c2b82b…0f11ab` | `sha256:4749bd06…c3a1ad` |

> digest 表述差異：upstream 公布的是 **index（manifest list）** digest，上表是其中的
> **arm64 子 manifest**。`verify_profile_image_gate` 比的是 `.RepoDigests`（docker pull
> 實際記錄的值），因此**pin 要用 pull 之後的 `.RepoDigests`**，並用
> `.RootFS.Layers` + `.Config` 證明 node1 的 re-manifest 內容相同（b12x 的既定做法）。
> `PENDING`：pull 完成後填入兩個節點的 `.RepoDigests`。

## 3. 被取代的基準（09-18，回滾目標）

| 項目 | 值 |
|---|---|
| image | `ghcr.io/aeon-7/aeon-vllm-ultimate:2026-09-18-v0.29.0-omni` |
| RepoDigest（manifest） | `sha256:cc91c51559d66854718fd9a8db6423e605ba76fb338bb55902caccb62aa9c677` |
| 本機 image Id | `sha256:b29f305f229f36b78c5462b13dd1fdaa6fcd75f361a2f8638156005817c9f2ee` |
| python / vLLM | `3.12.13` / `0.29.0+aeon.sm121a.dspark` |
| 解壓後大小（node0 overlay2） | 52.3 GB |
| 磁碟（2026-11-26 15:5x） | node0 `1.8T used / 1.7T avail / 52%`；node1 `2.0T / 1.6T / 56%` |

**09-18 保留在兩個節點，不刪**（`IMG_SHA256` 世代回滾只需改 conf + `gb10 use`）。

## 4. 前置佈局（已於 2026-11-26 完成，commit `5db136f`）

- stack 目錄改名 `aeon-vllm-ultimate`；4 個 checkpoint 移入共用池
  `~/docker-stacks/models/`（兩節點）。
- 這 4 個目錄原本**沒有 `SHA256SUMS`**（`verify_model_checksum` 只會 WARN 就回 0，
  等於沒有 gate）。已補生成並全量驗證：

| 目錄 | entries | SHA256SUMS sha256（兩節點相同） |
|---|---|---|
| `qwen3.8-27b-aeon-ultimate-uncensored-nvfp4-mixed` | 78 | `5ac1b141e8b09173…` |
| `qwen3.8-27b-dflash2` | 5 | `ad4560ff8225f6c7…` |
| `qwen3.6-35b-a3b-heretic-nvfp4` | 42 | `b15737d2bec70c9d…` |
| `qwen3.6-35b-a3b-dflash` | 4 | `3cc1ea1995983a0a…` |

  `gb10 verify-models 27b` / `35b` 兩條 lane 於兩節點 **PASS**（full check，78/78、5/5、
  42/42、4/4）。

## 5. 判定門檻（**量測前先寫死**）

| 類別 | 檢查 | 通過條件 |
|---|---|---|
| Hard | `gb10 use` → `/health` 200 | 在 `HEALTH_TIMEOUT=3600` 內 READY |
| Hard | `scripts/cluster-compose-verify` | 2/2 rank PASS |
| Hard | `gb10 smoke` | `HELLO-TP2-OK` 逐字 |
| Hard | coherence（固定字串／大小寫／計數）＋ `bench-multiturn` 6 輪 ＋ garble 3/3 | 全過，無「salad」（0.29 TP2 的失敗模式） |
| Hard | engine log | 0 個 `ERROR`（plugin-load 雜訊除外） |
| Hard | 記憶體 | bench 期間 `MemAvailable` ≥ 1 GiB |
| Hard | prefix caching | 27b 維持 OFF、35b 維持 ON 且 warm 命中正常 |
| 效能 | Σ decode（C1..C8 中位相加） | ≥ 同 session 09-18 基準 **−7 %**（本 repo 噪聲底） |
| 效能 | 逐格 decode | 低於 −7 % 的格子 ≤1，且需可歸因 |
| 效能 | 245K cold prefill | ≥ 基準 **−8 %** |
| 資訊 | KV pool／acceptance %／冷啟秒數 | 全部記錄（KV 掉 >5 % 註記） |

## 6. 基準（09-18，2026-10-22 全掃；同 session 會再重測一次）

`BENCH_IGNORE_EOS=1`、400 tok、warm：

| C | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | Σ |
|---|---|---|---|---|---|---|---|---|---|
| 27B cluster | 41.0 | 57.2 | 82.8 | 91.1 | 101.0 | 144.2 | 131.7 | **170.3** | 819.3 |
| 35B cluster | 125.5 | 221.4 | 290.6 | 311.9 | 355.4 | 387.7 | 414.0 | **471.8** | 2578.3 |
| 27B single | 22.3 | 33.3 | 45.4 | 61.2 | 59.3 | 69.1 | 76.2 | **101.2** | 468.0 |
| 35B single | 93.5 | 160.4 | 187.9 | 204.3 | 230.7 | 257.7 | 304.2 | **346.6** | 1685.3 |

## 7. Phase 0 — image 稽核

`PENDING`（pull 完成後執行 `vllm serve --help` 旗標稽核、版本、`use_mm_prefix` 檢查、
`/ple` 需求；結果貼在下方）。

## 8. Phase 1 — boot 與 bench

`PENDING`

## 9. 回滾

1. revert 該 commit（conf 回到 09-18 `IMAGE`），或只改 `IMAGE`/`IMG_SHA256**`。
2. `gb10 use 27b`／`gb10 restart`；cache 若已改名，`~/.cache/vllm-*-0.29bak` 可還原暖機。
3. 09-18 image 仍在兩節點；`IMG_SHA256` 世代 pin 見 §3。
4. 35b 的 `flash_attn_029_patched.py` 在 stack 目錄**保留未刪**，回滾時把 mount 加回
   `cluster-profiles.d/35b.conf` 與 single compose 即可。
