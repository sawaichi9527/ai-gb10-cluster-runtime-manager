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

**執行日**：2026-11-26 19:13–21:21（node0 `spark-25d5`；TP2 現役 `deepseek-nvfp4` 於 19:13 由
`gb10 use 27b` 拆除，21:21 `gb10 stop` 交還 `:1234`）。

### 8.1 四臂全掃（`bench-sweep.sh`，`BENCH_IGNORE_EOS=1`、400 tok、預設取樣、每格 3 reps 取中位）

| 臂 | C1 | C2 | C3 | C4 | C5 | C6 | C7 | C8 | Σ |
|---|---|---|---|---|---|---|---|---|---|
| **27B** 09-18 boot1 | 42.1 | 68.6 | 81.2 | 112.5 | 122.1 | 133.0 | 157.9 | 172.4 | **889.8** |
| **27B** 09-18 boot2 | 35.6 | 61.3 | 83.8 | 97.9 | 118.7 | 123.4 | 145.0 | 159.7 | **825.4** |
| 27B 09-18（兩 boot 均值） | 38.9 | 65.0 | 82.5 | 105.2 | 120.4 | 128.2 | 151.5 | 166.1 | 857.6 |
| **27B 0.33** boot1 | 34.3 | 58.0 | 78.4 | 104.7 | 105.7 | 130.0 | 137.6 | 143.5 | **792.2** |
| **27B 0.33** boot2 | 30.7 | 63.7 | 76.1 | 101.3 | 119.6 | 121.3 | 131.7 | 137.1 | **781.5** |
| 27B 0.33（兩 boot 均值） | 32.5 | 60.9 | 77.3 | 103.0 | 112.7 | 125.7 | 134.7 | 140.3 | 786.9 |
| **Δ 27B** | −16.4 % | −6.3 % | −6.3 % | −2.1 % | −6.4 % | −2.0 % | −11.1 % | −15.5 % | **−8.2 %** |
| **35B** 09-18 | 109.8 | 204.3 | 280.1 | 322.4 | 400.5 | 399.3 | 428.4 | 494.9 | **2639.7** |
| **35B 0.33** | 123.8 | 190.1 | 258.9 | 318.2 | 371.0 | 395.8 | 411.8 | 472.6 | **2542.2** |
| **Δ 35B** | **+12.8 %** | −6.9 % | −7.6 % | −1.3 % | −7.4 % | −0.9 % | −3.9 % | −4.5 % | **−3.7 %** |

**245K cold prefill**（`BENCH_COLD=1`，2 次）：

| 臂 | run1 | run2 | Δ vs 基準 |
|---|---|---|---|
| 27B 09-18 | 606.5 / 621.0 | 611.9 / 625.3 | — |
| 27B 0.33 | 685.1 / 688.8 | 698.9 / 697.6 | **+12.4 %** |
| 35B 09-18 | 3983.0 | 4013.6 | — |
| 35B 0.33 | 4170.7 | 4164.2 | **+4.2 %** |

### 8.2 必須先講的 A/A 漂移

**09-18 這條 lane 自己就 drift**：boot1 **889.8**、boot2 **825.4**（−7.2 %），而 2026-10-22
公布的歷史值是 **819.3**。也就是「同一個 image、同一個協定」今天量出三個值
819.3 / 825.4 / 889.8。**任何小於 ~8 % 的跨 boot 差異在這條 lane 上都不算結果**，
因此 27B 的判定用「兩 boot 均值」而不是取最漂亮的那一次。

### 8.3 判定（對照 §5 預註冊門檻）

| 車道 | Σ decode | prefill | 逐格 <−7 % | coherence | 判定 |
|---|---|---|---|---|---|
| **27B** | **−8.2 %**（均值；兩 boot 區間 781.5–792.2 完全不與基準區間 825.4–889.8 重疊） | +12.4 % | **4 格**（C1/C7/C8 及 C5 −6.4 邊緣） | 全過 | **FAIL — 不 promote** |
| **35B** | **−3.7 %**（噪聲內） | +4.2 % | 2 格（C3 −7.6 / C5 −7.4，邊緣） | 全過 | **PASS（parity）** |

**27B 的形狀很一致**：低併發（C1 −16 %、C7 −11 %、C8 −16 %）明顯掉，中併發（C4/C6）
持平，而 **prefill +12 %**。不是隨機噪聲，也不是 acceptance 造成（兩臂 acceptance 都 ~25 %）。

### 8.4 功能 gate（兩條候選臂都過）

| 檢查 | 27B 0.33 | 35B 0.33 |
|---|---|---|
| `/health` 200 → READY | 冷啟 **6m45s**／暖啟 **4m10s** | 冷啟 **6m59s** |
| `cluster-compose-verify` | 2/2 PASS | 2/2 PASS |
| `verify_profile_image_gate`（**兩節點同一 digest**） | PASS `71c2b82b…` | PASS 同值 |
| `gb10 smoke` / `HELLO-TP2-OK` 逐字 | PASS | PASS |
| `17*19=323` | PASS | PASS |
| `bench-multiturn` 6 輪（2048 tok） | 6/6 | 6/6 |
| dflash CUDA graph 捕獲 | 正常 | **8/8 FULL**（移除 0.29 patch 後仍正常） |
| KV pool | 3,770,216 tok（0.29：3,162,707，**+19.2 %**） | — |
| acceptance | ~25 %（0.29 ~26 %） | ~46 %（0.29 ~44 %） |

> `bench-multiturn` 的 300-token 預設對 35B 不成立：thinking 會吃光預算，**09-18 基準臂
> 在 300 下只有 2/6**（`finish=length`、content 空，屬既有契約非回歸），1024 下 5/6、
> **2048 下 6/6**。gate 因此統一用 2048。

### 8.5 未完成／已知缺口

1. **35B 只量了 1 個 boot**（×3 reps）。它 PASS 但樣本比 27B 少；**promote 前建議再補一個
   boot 複驗**（本車道未見 A/A 數據，保守起見）。
2. **27B 的單流退化未定位**：已排除 runner（0.33 仍印 `Using V2 Model Runner`）、acceptance、
   patch（27B 本來就沒有）、cache（候選臂用獨立 tree）。下一個值得測的單旋鈕是
   `VLLM_USE_FLASHINFER_SAMPLER=1`（兩臂目前都是 0）與 `--compilation-config` 的
   `cudagraph_capture_sizes`；本輪**沒有**做，屬下一輪調優。
3. **單節點四臂（S1）尚未執行**：需在 node0 依序量 27B/35B × 舊/新，使用
   `2026-11-25-…-ngram-disk` 那顆（`standalone.env` `AEON_IMAGE` 切換）。
4. 收工狀態：TP2 已 `gb10 stop`（`:1234` 交還）；`deepseek-nvfp4` 由使用者自行恢復。
   0.33 兩顆 image 留在兩節點，候選 conf 仍在 repo（未 promote）。

### 8.6 S1 — 單節點四臂（2026-11-26 22:37–00:08，全在 node0）

`image` 由 `standalone.env` `AEON_IMAGE` 決定（0.29 臂）、`AEON_IMAGE_35B` 覆寫（0.33 臂）。
臂間把 `~/.cache/vllm-<lane>-single` 改名隔離（0.29 樹保留為 `-029bak`）。
`PREFILL_RUNS=1`：單節點 27B 的 245K prefill 只有 ~350 tok/s，兩次要 ~23 分鐘。

| 車道 | C1 | C2 | C3 | C4 | C5 | C6 | C7 | C8 | Σ | 245K prefill |
|---|---|---|---|---|---|---|---|---|---|---|
| **27B single** 09-18 | 22.7 | 39.7 | 45.8 | 58.5 | 63.8 | 73.3 | 86.9 | 96.4 | **487.1** | 346.2 |
| **27B single** 11-25 | 19.1 | 36.1 | 44.0 | 54.4 | 58.2 | 73.7 | 82.9 | 98.7 | **467.1** | 390.5 |
| **Δ** | −15.9 % | −9.1 % | −3.9 % | −7.0 % | −8.8 % | +0.5 % | −4.6 % | +2.4 % | **−4.1 %** | **+12.8 %** |
| **35B single** 09-18 | 87.0 | 144.9 | 173.5 | 200.1 | 235.5 | 260.2 | 266.4 | 323.0 | **1690.6** | 2584.4 |
| **35B single** 11-25 | 97.6 | 132.9 | 160.0 | 199.0 | 246.5 | 251.5 | 282.6 | 298.2 | **1668.3** | 2708.2 |
| **Δ** | **+12.2 %** | −8.3 % | −7.8 % | −0.5 % | +4.7 % | −3.3 % | +6.1 % | −7.7 % | **−1.3 %** | **+4.8 %** |

**與 10-22 公布值互校**：27B single 468.0 → 今日基準 487.1（+4.1 %）、35B single 1685.3 →
1690.6（+0.3 %）；prefill 346.2 / 2584.4 對公布 348.7 / 2580.1 → 協定沒有跑掉。

**結論與叢集完全一致**：27B 的 Σ 在噪聲內（−4.1 %）但**單流 C1 仍 −16 %**（預註冊的逐格
規則不過）；35B parity（−1.3 %）且 **C1 +12.2 %**。

### 8.7 Promote 記錄（2026-11-26）

| 對象 | 決定 | 證據 |
|---|---|---|
| **35B cluster** | **升到 `2026-11-23-v0.33.0-omni-dflash2`**（commit `ed3ae4f`；`IMG_SHA256` pin，兩節點同值） | 兩 boot Σ −3.1 %、C1 +12.8 %、prefill +4.2 %；所有 gate 過 |
| **35B single** | **升到 `2026-11-25-…-ngram-disk`** | S1 Σ −1.3 %、C1 +12.2 %、prefill +4.8 % |
| **27B（兩種模式）** | **維持 `2026-09-18`** | Σ −8.2 %（叢集）／−4.1 %（單節點，但 C1 −16 %），退化可重現 |

**單節點 image 的實作**：`AEON_IMAGE` 是兩條 lane 共用的，因此新增 **per-lane 覆寫**
`AEON_IMAGE_35B`，只有 `docker-compose-35b-single.yml` 讀它
（`image: ${AEON_IMAGE_35B:-${AEON_IMAGE}}`）；27b single 仍只看 `AEON_IMAGE`（09-18）。
兩節點的 `.env` 與 compose 已改且**sha256 相同**（`3b519a45…` / `88f5cc60…`），舊檔備份為
`*.bak-20261127-*`。

**Cache 現況**：`~/.cache/vllm-27b-single` = 0.29（已還原）、`-033bak` 保留；
`~/.cache/vllm-35b-single` = 0.33、`-029bak` 保留；叢集側 35b 用
`~/.cache/vllm-35b-cluster`（0.29 的 autotune 目錄由每次 boot 的
`ensure_autotune_cache_reset` 自動清掉），27b 兩臂各自的 tree 都留著。

**驗證**：promote 後 35B cluster `gb10 restart` → READY **7m05s**、image gate PASS、
compose-verify PASS、C1 140.5 / C8 461.8；35B single 以 11-25 開機 READY **6m15s**、C1 91.2。
收工：`gb10 stop` + `gb10-single stop node0 35b`，`:1234` 已釋放（僅剩既有 `c0918` Created）。

## 9. 27B drafter 調查（2026-11-27）— 找到 +32% 的組合，**不動 image**

**觸發**：27B single 只有 C1 22.7 tok/s，而社群／官方同級配置報 32–38 tok/s。查 card 後發現
我們用的是 **vLLM 預設 greedy draft**，且沒有用官方給單 Spark 的 **per-concurrency lattice**。

**官方（AEON DFlash2）的 DGX Spark 設定**（`configs/dgx-spark.speculative-config.json`，
經核對適用於我們的 image `2026-09-18-v0.29.0-omni`）：

```json
{"method":"dflash","model":"/draft","num_speculative_tokens":9,
 "num_speculative_tokens_per_batch_size":[[1,2,9],[3,8,7],[9,12,6],[13,16,4]],
 "attention_backend":"TRITON_ATTN","draft_sample_method":"probabilistic"}
```

**三臂（node0 single，09-18 image，`BENCH_IGNORE_EOS=1`／400 tok／預設取樣／3 reps 中位）**：

| 臂 | drafter | spec config | C1 | C2 | C3 | C4 | C5 | C6 | C7 | C8 | Σ |
|---|---|---|---|---|---|---|---|---|---|---|---|
| **G0** 生產（09-18） | z-lab DFlash2 | K7 greedy | 22.7 | 39.7 | 45.8 | 58.5 | 63.8 | 73.3 | 86.9 | 96.4 | **487.1** |
| **G1** `27b-tune-prob` | z-lab DFlash2 | K7 **probabilistic** | 25.2 | 39.2 | 56.8 | 64.8 | 73.9 | 85.9 | 112.4 | 108.3 | **566.5**（**+16.3 %**） |
| **G2** `27b-tune-df2aeon` | **AEON DFlash2 NVFP4 1.93 GB** | **K9 + lattice + probabilistic** | 24.5 / 27.3 | 43.8 / 49.6 | 65.8 / 64.6 | 76.6 / 72.6 | 91.4 / 91.4 | 100.5 / 106.6 | 112.6 / 114.9 | 122.3 / 122.3 | **637.5 / 649.3 → 均值 643.4（+32.1 %）** |

- **單一旋鈕（G1）就有 +16.3 %**：acceptance 由 21–28 % 升到 28–33 %。這是因為 vLLM 預設
  `draft_sample_method="greedy"`，而官方 measured 設定是 `probabilistic`（原始碼註解：
  多花一點 GPU 記憶體換取正確的機率比值檢定）。
- **G2 再 +12.5 %（對 G1）**：AEON drafter 的 acceptance 更好（C8：G0 21.3 % → G1 31.0 % →
  G2 34.0 %），且 lattice 讓低併發用 9 drafts、高併發自動降到 7/6/4。
- **不動 image、不動權重（body 不變）**、lossless（rejection sampling 由 target 逐一驗證）。

**新增的 A/B lane**（`runtimes.d/`，非服務）：`27b-tune-prob`、`27b-tune-df2aeon`；
compose 由 `docker-compose-27b-single.yml` 腳本衍生，差異僅 container name／drafter mount／
cache root／`--speculative-config`。

**drafter 落地**：`~/docker-stacks/models/qwen3.8-27b-dflash2-aeon/`（30 檔，含
`model.safetensors` 1,926,977,716 B、sha256 `02d956cf…` ＝ HF LFS oid、`SHA256SUMS`
`4b0ada30…`，兩節點相同）。`bf16/` 未下載（NVFP4 W4A16 才是 Blackwell/vLLM 的正解）。

**尚未做**：TP2 的對應測試（官方對 TP=2 建議 fixed **n=7**、不用 lattice，但同樣應開
`probabilistic`）；以及 27B 0.33 是否會因為 drafter 設定正確而翻盤。

**注意**：本節數字是「預設取樣（T=1.0）」。官方量到的 32.7 tok/s 是 **T=0.6 + thinking on +
512 tok + util 0.57**，所以兩者不可直接相減；同一協定下的**相對**增益（+16 %／+32 %）才是結論。

### 9.1 Promote — 27B single 已改（2026-11-27 02:03）

`docker-compose-27b-single.yml`（兩節點，備份 `*.bak-20261127-020317`）：
drafter → `../models/qwen3.8-27b-dflash2-aeon`，spec → 官方 K9＋lattice＋probabilistic。
sha256 兩節點相同；boot READY 9m15s（冷 cache）。

**暖機複測**（4×C1 / 2×C8）：C1 `27.3 / 33.5 / 23.9 / 23.6`（中位 **25.7**）、C8 `119.0 / 111.0`。
注意 **C1 的 run-to-run 變異很大（±18 %）** —— 這條 lane 的 Σ 才是可靠指標，單格 C1 不要當結論。
boot 後第一個請求會偏低（本例 20.7），量測前先暖機。

### 9.2 TP2 對照（2026-11-27 02:23–02:45）

候選 lane `27b-df2aeon`（image 與 body 不變；官方 TP=2 形狀：**fixed n=7、不用 lattice**，
但 `probabilistic` + AEON drafter；獨立 cache tree）。

| 臂 | C1 | C2 | C3 | C4 | C5 | C6 | C7 | C8 | Σ | 245K prefill |
|---|---|---|---|---|---|---|---|---|---|---|
| 生產 27b（boot1） | 42.1 | 68.6 | 81.2 | 112.5 | 122.1 | 133.0 | 157.9 | 172.4 | 889.8 | 606–612 |
| 生產 27b（boot2） | 35.6 | 61.3 | 83.8 | 97.9 | 118.7 | 123.4 | 145.0 | 159.7 | 825.4 | 621–625 |
| **候選 run1** | 39.5 | 69.8 | 87.5 | 105.7 | 139.3 | 164.4 | 175.5 | 183.4 | **965.1** | — |
| **候選 run2** | 42.0 | 74.2 | 100.7 | 117.8 | 142.4 | 157.0 | 173.8 | 183.6 | **991.5** | 618.3 |
| **Δ（兩 boot 均值 vs 生產均值）** | +5.3 % | +10.6 % | +13.8 % | +8.1 % | +16.6 % | +27.1 % | +14.9 % | +9.9 % | **+14.1 %** | ±0 |

- 候選兩個 boot（965.1 / 991.5）與生產兩個 boot（825.4 / 889.8）**完全不重疊**。
- 即使拿生產最好的一次（889.8）比，候選仍是 **+9.9 %**。
- acceptance C8：生產 **24.6 %**（2.11 mean）→ 候選 **29–30 %**；C6/C7 增益最大（+27 %／+15 %）。
- **TP2 的增益（+14 %)小於單節點（+32 %）**：TP2 依官方只能用 fixed n=7（無 lattice），
  且跨節點 verify 的固定成本較高。

### 9.3 用調好的 drafter 重測 27B 0.33（2026-11-27 08:46–09:00）

問題：0.33 的退化是不是「小 draft 長度下的 verify 成本」造成的？把 0.33 候選 lane 改成
**與 promote 後生產 27b 完全相同的 drafter/spec**（AEON DFlash2、fixed n=7、probabilistic），
只留引擎一個變數。

| 臂 | C1 | C2 | C3 | C4 | C5 | C6 | C7 | C8 | Σ | 245K prefill |
|---|---|---|---|---|---|---|---|---|---|---|
| **0.29 + tuned**（生產，兩 boot 均值） | 40.8 | 72.0 | 94.1 | 111.8 | 140.9 | 160.7 | 174.7 | 183.5 | **978.3** | 618.3 |
| 0.33 + tuned（run1） | 40.3 | 69.0 | 101.6 | 117.5 | 125.0 | 137.1 | 152.7 | 152.0 | 895.2 | — |
| 0.33 + tuned（run2） | 39.3 | 70.1 | 94.6 | 116.8 | 113.7 | 131.2 | 150.8 | 151.3 | 867.8 | 697.0 |
| **0.33 + tuned（均值）** | 39.8 | 69.6 | 98.1 | 117.2 | 119.4 | 134.2 | 151.8 | 151.7 | **881.5** | — |
| **Δ** | −2.5 % | −3.3 % | **+4.3 %** | **+4.8 %** | −15.3 % | −16.5 % | −13.1 % | −17.4 % | **−9.9 %** | **+12.7 %** |

**結論：0.33 沒有翻盤。** 換上最佳 drafter 後形狀反而更清楚：

- 0.33 在 **C1–C4 持平甚至略勝**（+0~+5 %），但 **C5–C8 一律低 13–17 %**；
- 0.29 的 drafter 升級在 0.33 上同樣有效（同 drafter：`786.9 → 881.5`，+12 %），
  所以 **不是 drafter 的問題，是 0.33 引擎在高併發端每步成本較高**；
- prefill 仍是 0.33 的強項（**+12.7 %**，697.0 vs 618.3）。

**最終判定（2026-11-27）**：`27b` 兩種模式都留在 **`2026-09-18-v0.29.0-omni`**，
並採用 AEON DFlash2 drafter（TP2 +14.1 %、single +32.1 %）。`35b` 兩模式在 0.33。






## 9. 回滾

1. revert 該 commit（conf 回到 09-18 `IMAGE`），或只改 `IMAGE`/`IMG_SHA256**`。
2. `gb10 use 27b`／`gb10 restart`；cache 若已改名，`~/.cache/vllm-*-0.29bak` 可還原暖機。
3. 09-18 image 仍在兩節點；`IMG_SHA256` 世代 pin 見 §3。
4. 35b 的 `flash_attn_029_patched.py` 在 stack 目錄**保留未刪**，回滾時把 mount 加回
   `cluster-profiles.d/35b.conf` 與 single compose 即可。
