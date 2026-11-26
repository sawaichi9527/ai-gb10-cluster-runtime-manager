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

### 7.0 下載路徑（2026-11-26 事故與處置）

- **node0（classic `overlay2`）拉不動**：`docker pull` 的 classic fetcher 對 7.45 GB 那一層
  （`sha256:a3f5a01f59ac…`）反覆 `Retrying`，每次重試都是**整層重下**，45 分鐘後以
  `unexpected EOF` 失敗；同一層在 `11-25` 共用，所以第二顆也一定失敗。
- **量測**：同一 blob 的 100 MB ranged GET，node0 **2.11 MB/s**、node1 **3.53 MB/s**；
  1.82 GB 那層在 node0 撐了約 20 分鐘後成功 → 失敗是間歇性、不是權限或 blob 損壞
  （HEAD 200、`206` ranged 正常）。
- **處置**：改在 **node1** 拉。node1 的 `docker info` 是 `driver=overlayfs`
  （containerd image store），其 fetcher 是**分塊 ranged ＋ 可續傳**，對斷線容忍度高得多。
  兩顆拉完後用 **`ssh node1 'docker save' | docker load`** 走 CX7 回傳 node0（不落中間檔）。
- **digest 的副作用**：`docker load` 出來的 image **不帶 `RepoDigests`**（docker-archive 只有
  RepoTags），所以若之後要用 `IMG_SHA256` gate，需要先 `docker pull` 一次把 registry digest
  接回去（layers 已存在時理論上不會重下）；本輪先不啟用 pin，以 `.Id`／`.Config`／
  `.RootFS.Layers` 做內容同一性證明，並把 index／子 manifest digest 寫在本檔 §2。

`PENDING`（稽核輸出：`vllm serve --help` 旗標、版本、`use_mm_prefix`、`/ple`）。

### 7.1 稽核結果（node0，2026-11-26 18:5x）

| | 09-18（基準） | 11-23（TP2） | 11-25（single） |
|---|---|---|---|
| python | `3.12.13` | `3.12.3` | `3.12.3` |
| vLLM | `0.29.0+aeon.sm121a.dspark` | `0.33.0+aeon.sm121a` | 同左 |
| torch | — | `2.14.0+cu130` | 同左 |
| flashinfer | — | `0.7.2.post1` | 同左 |
| site-packages | `/usr/local/lib/python3.12/…` | **`/opt/venv/lib/python3.12/…`** | 同左 |
| 解壓後（node0 overlay2） | 52.3 GB | **26.13 GB** | 26.13 GB |
| `.RepoDigests` | `cc91c515…` | **`71c2b82b…`** | **`4749bd06…`** |
| `.Id`（node0 classic） | `b29f305f…` | `2893164a…`（＝config digest） | `2e8751e4…` |
| 內容同一性（node0 vs node1 `.Config`+`.RootFS.Layers`） | — | **`be817fd1…` 相同** | **`7705f9db…` 相同** |

**旗標稽核（`vllm serve --help=all`，159,504 B / 2,455 行）**：我們 profile 會送出的旗標
**全部存在** —— `--tensor-parallel-size`、`--served-model-name`、`--api-key`、
`--kv-cache-dtype`、`--attention-backend`、`--max-model-len`、`--max-num-seqs`、
`--max-num-batched-tokens`、`--gpu-memory-utilization`、`--enable-chunked-prefill`、
`--enable/--no-enable-prefix-caching`、`--generation-config`、`--reasoning-parser`、
`--tool-call-parser`、`--enable-auto-tool-choice`、`--compilation-config`、
`--speculative-config`、`--mm-encoder-tp-mode`、`--limit-mm-per-prompt`、
`--disable-custom-all-reduce`、`--trust-remote-code`、`--dtype`、`--quantization`。
唯一不在清單內的是 `--disable-log-requests`（**我們沒用到**）。
`--kv-cache-dtype` 仍含 `fp8_e4m3`（27b）與 `bfloat16`（35b）；`CompilationConfig` 仍有
`pass_config` 欄位（`{"pass_config":{"fuse_allreduce_rms":false}}` 的形狀不變，實際接受與否
boot 時確認）；`qwen3_coder` 仍在 tool-parser enum 內、`reasoning/qwen3` 模組存在。
`--mamba-cache-mode` 已標 **deprecated / no effect**（我們沒有使用，無影響）。

**兩個 0.33 的 CLI 行為變化（寫給未來的自己）**：
1. `vllm serve --help` 現在只印**摘要**，要完整清單得用 `--help=all`（或用
   `--help=<flag>` 查單一旗標）。任何 grep `vllm serve --help` 的工具都會靜默失效。
2. `--help` 需要可見 GPU：無 `--gpus all` 時會在 device 推斷階段 `RuntimeError`（與模型無關）。

**0.29 的 `flash_attn` patch 已確定不需要**：`flash_attn.py` 的 `use_mm_prefix` 參照在
0.29 是 2 處、0.33 是 **3 處**（含 signature），而 `qwen3_dflash2.py` 已無任何
`use_mm_prefix` 參照。再加上 0.33 的 site-packages 已搬到 `/opt/venv/…`，舊 bind 的
目標路徑**根本不存在** —— 所以 35b 的 `flash_attn_029_patched.py` 必須在換版時移除，
不可重新綁定。

**image 配對**：11-23 與 11-25 的 `vllm serve --help=all` 輸出**逐 byte 相同**（僅時間戳
不同）→ 兩者的 CLI 介面一致，差別只在 baked 進去的 offload 程式碼。

**MIXED / ModelOpt**：兩個世代的 `modelopt.py` 都沒有 `MergedColumnParallelLinear` 參照，
而 27b body 在 0.29 上從未需要 bind → 0.33 也預期不需要（boot 時確認，不需預先準備 patch）。



## 8. Phase 1 — boot 與 bench

`PENDING`

## 9. 回滾

1. revert 該 commit（conf 回到 09-18 `IMAGE`），或只改 `IMAGE`/`IMG_SHA256**`。
2. `gb10 use 27b`／`gb10 restart`；cache 若已改名，`~/.cache/vllm-*-0.29bak` 可還原暖機。
3. 09-18 image 仍在兩節點；`IMG_SHA256` 世代 pin 見 §3。
4. 35b 的 `flash_attn_029_patched.py` 在 stack 目錄**保留未刪**，回滾時把 mount 加回
   `cluster-profiles.d/35b.conf` 與 single compose 即可。
