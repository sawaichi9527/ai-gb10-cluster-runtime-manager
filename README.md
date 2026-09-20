# ai-gb10-cluster-runtime-manager

DGX Spark **GB10 runtime manager** — 統合 **2-node TP2 叢集** 與 **單節點 runtimes** 於單一 repo。

- **`bin/gb10`** — TP2 叢集 CLI（thin layer 於 `scripts/cluster-*`）
- **`bin/gb10-single`** — 單節點 CLI（`node0` 本機 / `node1` 經 ssh）
- **`runtimes.d/*.conf`** — 單節點 runtime 定義
- **`cluster-profiles.d/*.conf`** — TP2 叢集 profile 定義（data-driven registry）
- **`scripts/cluster-*`** — 叢集部署腳本（ver detail 見 `docs/TP2_DEPLOYMENT_2026-08-30.md`）


## Deployed services & benchmark results (latest image)

> 2026-09-13 實測。27B/35B 原使用 `ghcr.io/aeon-7/aeon-vllm-ultimate:2026-09-11-v0.29.0-omni`；DeepSeek 為歷史主力線 `ghcr.io/anemll/dspark-vllm-gx10:0.1.1` 之既有結果。
> **2026-09-19 更新**：35B 與 27B 皆已升 `2026-09-18-v0.29.0-omni` 並重新實測（單節點啟用 `VLLM_USE_V2_MODEL_RUNNER=1`）。27B 先前在 09-18 首次冷啟動觸及 `cluster-up` 硬編碼 2400s health timeout 而誤判失敗（非 image 缺陷）；已改為 profile 可覆寫（27B `HEALTH_TIMEOUT=3600`），實測 READY 並完成 cluster/single benchmark。
> **2026-09-20 新增**：DeepSeek V4 Flash **Vision-Exp**（多模態）以**與 mainline deepseek 同一顆** Anemll image + 啟動 wrapper 上線（`gb10 use deepseek-vision`，互斥）；bench-c / bench-ctx 實測見下方。
> **2026-09-20 新增**：**Qwen3.8 Flash-Next 125B NVFP4**（TP2+EP、內建 MTP3）上線（`gb10 use qwen38flash`）；同日起 compose 為**唯一**啟動 lane（原 docker-run 分支移除），見下方實測。

### 已部署服務

| service | 模型 / 方法 | image | endpoint | 狀態 |
|---|---|---|---|---|
| 27B single (TP1) | `qwen3.8-27b-aeon-ultimate-uncensored-nvfp4-mixed` + DFlash2 n=7 | `2026-09-18-v0.29.0-omni` | `:1234/v1` | deployed（09-19 實測） |
| 27B cluster (TP2) | 同上 | `2026-09-18-v0.29.0-omni` | `http://192.168.23.215:1234/v1` | deployed（09-19 實測） |
| 35B single (TP1) | `qwen3.6-35b-a3b-heretic-nvfp4` + DFlash n=6 | `2026-09-18-v0.29.0-omni` | `:1234/v1` | deployed（09-19 實測） |
| 35B cluster (TP2) | 同上 | `2026-09-18-v0.29.0-omni` | `http://192.168.23.215:1234/v1` | deployed（09-19 實測） |
| DeepSeek V4 Flash cluster (TP2) | `deepseek-v4-flash-0731-official` + DSpark n=7 | `anemll/dspark-vllm-gx10:0.1.1` | `http://192.168.23.215:1234/v1` | deployed (mainline) |
| DeepSeek V4 Flash **Vision-Exp** cluster (TP2) | `deepseek-v4-flash-vision-exp` + DSpark n=6 (multimodal) | `anemll/dspark-vllm-gx10:0.1.1`（**與 deepseek 同 image / 同 digest**） | `http://192.168.23.215:1234/v1` | deployed（09-20 實測，文字＋圖片） |
| Qwen3.8 Flash-Next **125B** cluster (TP2+EP) | `qwen3.8-flash-next-nvfp4`（ModelOpt NVFP4）+ 內建 MTP n=3 | `vllm/vllm-openai:qwen38-flash-next` | `http://192.168.23.215:1234/v1` | deployed（09-20 上線實測） |

### 27B v0.29.0-omni (bench-c C1-C8, MAX_TOKENS=2048; 245k cold prefill)

> **2026-09-19 實測（09-18 image；single node0 與 TP2 cluster 皆本次重測）。** 先前的「啟動失敗」為 `cluster-up` 硬編碼 2400s health timeout 短於 27B 首次冷啟動（~40min）所致，非 image 缺陷；已改為 profile 可覆寫（27B `HEALTH_TIMEOUT=3600`，詳見 `docs/ISSUE_27B_BROKEN_2026-09-18_IMAGE_2026-09-19.md`）。與 09-11 基準相比：single 幾近持平（245k 348.7 vs 347.2）；cluster 於 C1/C2/C4 與長 prefill 略升、C3/C8 略降（run-to-run 變異，各 stream completion 長度不同）。

| C | Single tok/s | Cluster tok/s | Speedup |
|---|---|---|---|
| 1 | 23.8 | 46.1 | 1.94x |
| 2 | 36.6 | 76.8 | 2.10x |
| 3 | 54.4 | 87.9 | 1.62x |
| 4 | 80.3 | 105.3 | 1.31x |
| 8 | 117.2 | 172.7 | 1.47x |
| 245k prefill (tok/s) | 348.7 | 611.5 | 1.75x |

### 35B v0.29.0-omni (bench-c C1-C8, MAX_TOKENS=2048; 245k cold prefill)

> **2026-09-19 實測（09-18 image；single node0 與 TP2 cluster 皆本次重測）。** `scripts/bench-c.sh` / `bench-ctx.sh` 實測。與 09-11 基準大致持平（single 245k 2580.1 vs 2601.0）。註：先前記錄的 245k prefill `180398.5` tok/s 為量測瑕疵（245k 僅 ~1.4s，不可能）；本次 cluster 62.0s / 3951.9、single 95.0s / 2580.1 為可信值。

| C | Single tok/s | Cluster tok/s | Speedup |
|---|---|---|---|
| 1 | 76.2 | 120.6 | 1.58x |
| 2 | 115.5 | 177.4 | 1.54x |
| 3 | 148.2 | 218.5 | 1.47x |
| 4 | 198.6 | 291.6 | 1.47x |
| 8 | 262.7 | 416.4 | 1.59x |
| 245k prefill (tok/s) | 2580.1 | 3951.9 | 1.53x |

> 245k prefill 用 `bench-ctx.sh 245000 1`（max_tokens=1 純 prefill）。
> **踩雷（已自動化）**：FlashInfer autotune cache **無法跨 rank 共用**——持久化的 `file_key` 內含 `tp_rank/ep_rank/cluster_rank`，而 vLLM 只在 leader（world rank 0）存檔、再把該 leader 檔 broadcast 給所有 rank；follower 用 rank-local key 永遠 miss → 兩 rank 要 benchmark 的 tactic 數不同 → 每 tactic 的 `dist.all_reduce` 死鎖（rank0 高 GPU spin-wait、rank1 閒置、`/health` 永不 ready）。故 `scripts/cluster-up` 於每次 boot 前呼叫 `ensure_autotune_cache_reset`（`cluster-common.sh`）**無條件清掉兩節點快取**，讓兩 rank 冷啟 lockstep；`AUTOTUNE_CACHE_POLICY=off` 可跳過（僅診斷）。單節點 runtime 另用獨立 cache root（`~/.cache/vllm*`），不污染 TP2 路徑（`gb10-single-boot` 會檢查）。

### DeepSeek V4 Flash fp8 mainline (bench-c C1-C8; 200K probe) - 歷史結果

| C | Cluster tok/s | Acceptance |
|---|---|---|
| 1 | 35.3 | 23.8% |
| 2 | 45.9 | 25.1% |
| 4 | 56.6 | 31.0% |
| 8 | 85.9 | 26.8% |
| 200K prefill (tok/s) | 1600.3 | - |

> 完整報告：maintenance repo `docs/BENCHMARK_27B_MIXED_V3_V029_SINGLE_CLUSTER_2026-09-13.md`、`docs/BENCHMARK_35B_V029_SINGLE_CLUSTER_2026-09-13.md`；DeepSeek 見 handoff §23.3。

### DeepSeek V4 Flash Vision-Exp (TP2, 與 deepseek 同 image) — 2026-09-20 實測

> `cluster-profiles.d/deepseek-vision.conf` 使用**與 mainline deepseek 完全相同**的 image
> `ghcr.io/anemll/dspark-vllm-gx10:0.1.1`（digest `a8394849…`）。Vision-Exp 支援不在 image 內，
> 而是靠**啟動 wrapper**（`entrypoint: []` + `bash -lc`：安裝 checkpoint 的 ViT/Aligner encoder
> → 套 17 個社群 hotfix → `exec vllm serve`）；hotfix 已 vendored 於 `patches/dspark-vision/`
> （MiaAI-Lab，MIT）。`nvfp4_ds_mla` KV、`flashinfer_b12x` MoE、DSpark k=6、
> **262144 ctx / 8-way（與 mainline 0731 相同）**、**prefix caching ON**（搭
> `dspark-swa-prefix` hotfix + `VLLM_PREFIX_CACHE_RETENTION_INTERVAL=4096`）。兩 profile 互斥切換
> （`gb10 use deepseek` ↔ `gb10 use deepseek-vision`）。實測 `/v1/chat/completions` 文字與
> `image_url` 圖片輸入皆正常；KV pool 381,364 tokens（0731 為 405,179，差異來自 ViT encoder 佔用權重記憶體）。

| C | Vision-Exp tok/s | accept % |
|---|---|---|
| 1 | 36.7 | 29.9% |
| 2 | 48.8 | 29.6% |
| 3 | 58.0 | 32.5% |
| 4 | 67.3 | 30.9% |
| 8 | 73.4 | 30.1% |

| prefill probe (`bench-ctx.sh`, max_tokens=1) | Vision-Exp tok/s |
|---|---|
| 32K | 1941.0 |
| 131K | 1825.3 |
| 200K | 1710.2 |
| 245K | 1671.3 |
| 260K | 1638.0 |
| 261K | 1803.9 |

| 圖片輸入 (`bench-mm.sh`, max_tokens=200) | prompt tok | wall (s) | agg tok/s |
|---|---|---|---|
| 1 img, C=1 | 407 | 3.76 | 53.1 |
| 4 img, C=1 | 1346 | 5.51 | 36.3 |
| 8 img, C=1 | 2598 | 12.37 | 16.2 |
| 1 img, C=4 | 407 ×4 | 7.21 | 111.0 |
| 1 img, C=8 | 407 ×8 | 10.95 | 146.1 |
| 1 img, C=16 | 407 ×16 | 20.08 | 159.4 |
| 4 img, C=8 | 1346 ×8 | 16.31 | 90.6 |

> 多模態：OpenAI `image_url`（base64）正常，每張圖約 320–390 prompt tokens（checkpoint `vision_max_n_token=384`）；`--limit-mm-per-prompt {"image":8}`。長上下文 prefill 到 261K 仍線性（1803.9 tok/s @ 261K）；**262144-word（=上限）請求被拒**（`maximum context length is 262144`，prompt 262144 + 1 output > 上限）→ 實用上限 prompt ≤ 262143 tokens。
> Prefix caching 實測：同一 32K prompt 連兩次，第 2 次命中前綴 → prefill **16.95s → 2.30s（1938 → 14314 tok/s）**；重複同 prompt 三次輸出皆完整（無 DSpark 退化，hotfix 生效）。
> 節點部署：vision 的 hotfix 目錄由 `cluster-up` 的 `SYNC_DIRS` 於每次 boot 從 repo 自動同步到兩節點（node1 不 host repo）。

### DeepSeek V4 Flash 0731 mainline — 2026-09-20 同 session 重測

> 與上方 Vision-Exp 同一顆 image、同一台 TP2、同一組 `bench-c.sh` / `bench-ctx.sh`（`MAX_TOKENS=400`），作為對照。`bench-c` 之 prompt：0731 約 118 tok、Vision-Exp 約 197 tok（同文字，tokenizer/chat template 差異）。

| C | 0731 tok/s | accept % |
|---|---|---|
| 1 | 35.7 | 25.1% |
| 2 | 55.7 | 29.3% |
| 3 | 45.1 | 25.4% |
| 4 | 55.5 | 27.1% |
| 8 | 93.1 | 28.8% |

| prefill probe (`bench-ctx.sh`, max_tokens=1) | 0731 tok/s |
|---|---|
| 32K | 1516.9 |
| 131K | 1682.3 |
| 200K | 1725.0 |

> 觀察：C≥4 兩者吞吐相近；C=8 0731 較高（93.1 vs 73.4）；短/中長 prefill Vision-Exp 略快、200K 同級。

### Qwen3.8 Flash-Next 125B NVFP4 (TP2+EP, MTP3) — 2026-09-20 上線實測

> **新 lane（09-20 上線）。** `cluster-profiles.d/qwen38flash.conf`：官方
> `vllm/vllm-openai:qwen38-flash-next` image（vLLM ≥0.28、Qwen4Exp 支援）、NVIDIA ModelOpt
> **NVFP4 125B** checkpoint（本機為 10-shard repack，另有 `model-fp8-mtp-ple.safetensors`）、
> **TP2 + EP**（`--enable-expert-parallel --all2all-backend allgather_reducescatter`）、內建
> **MTP n=3**（`--speculative-config {"method":"mtp","num_speculative_tokens":3,"use_local_argmax_reduction":true}`）
> 在**精簡 47,149-id 詞表**上起草（A/B 見下）、`fp8_e4m3` KV、`bfloat16` SSM state、
> `--compilation-config {"mode":0,...}`（eager：不做 torch.compile，避免 Inductor 在 GB10 上複製 PLE
> 表）、GMU 0.835、`--max-num-batched-tokens 8192`、`--mm-encoder-tp-mode data`。
>
> MiaAI-Lab 配方的 5 個 runtime patcher vendored 於 `patches/qwen38flash/`（AGPL-3.0，見 NOTICE），
> 由 `CMD_WRAPPER` 在容器內**就地**套用於 image 自身的 vLLM 原始碼（PLE / ModelOpt MXFP8 +
> FP8_BLOCK_SCALES / QSA FP8-KV / 精簡詞表 MTP drafter），不重建 image；47k 詞表唯讀掛載於
> `/etc/vllm-draft-vocab.txt`。checkpoint 的 MTP 層索引別名由
> `patches/qwen38flash/prepare.sh` 預先產生後唯讀掛載。
>
> 服務：`:1234`、model id `aeon`、262144 ctx。**KV pool 34.01 GiB / 4,245,234 tokens**
> （262144 請求下 16.19x）。`bench-c.sh`：prompt = 171 tok、`MAX_TOKENS=400`、`any_errors=0`；
> 下表為多次重複之**中位數**（每 C 3 次）。

#### MTP draft 詞表 A/B（同機同 session，僅換 drafter 詞表）

| C | 完整 248,320 vocab | 精簡 47k | Δ |
|---|---|---|---|
| 1 | 35.7 | 40.4 | +13.2% |
| 2 | 54.8 | 58.9 | +7.5% |
| 3 | 82.3 | 88.2 | +7.2% |
| 4 | 90.9 | 101.0 | +11.1% |
| 8 | 146.5 | 156.2 | +6.6% |

| C | 完整 accept % | 47k accept % |
|---|---|---|
| 1 | 44.5 | 47.4 |
| 2 | 49.8 | 43.0 |
| 3 | 45.3 | 42.8 |
| 4 | 44.9 | 46.5 |
| 8 | 47.4 | 45.6 |

> 精簡詞表把 drafter 的 lm_head 讀取縮到 rank-0 的 id 區間，並以
> `use_local_argmax_reduction` 把 draft all-gather 由 O(vocab_size) 降為 O(2*tp_size)；五個 C 全部較快
> （**平均 +9.1%**，與 MiaAI 量測的 +9.6% 相符），**接受率與 mean accept length 幾乎不變**
> （輸出安全：落在子集外的 draft 在驗證階段被丟棄，不會被輸出）。精簡版另使 KV pool 由
> 33.64 → **34.01 GiB**（drafter 權重省下的記憶體）。`bench-c` 的 `max_tokens=400` 會提前停止、
> 各 stream 長度不同，故單次數字變異較大（C=1 尤甚），上表取中位數。

> 對照同機 TP2：**27B**（v0.29.0-omni, DFlash2 n=7）46.1 / 76.8 / 87.9 / 105.3 / 172.7；
> **35B**（DFlash n=6）120.6 / 177.4 / 218.5 / 291.6 / 416.4。
> 125B NVFP4 MoE 每 token 僅啟用約 6B 參數，故 C=1 單流偏低（~40 tok/s），C=8 聚合達 156.2 tok/s
> （相對 C=1 約 3.9x）。
>
> **上線時修掉的 5 個問題**（皆已進 main）：① Docker Compose 對整份 render 檔做變數插值，把
> `CMD_WRAPPER` 內的 `$W`/`$P` 吃掉 → 啟動即死於 `mkdir -p ""`（改以 `$$` 逃逸；deepseek-vision
> 的 `${PATH}` 同類隱患一併修好）；② `cluster-compose-verify` 不支援 `CMD_WRAPPER` lane；
> ③ 同工具以 `||` 當欄位分隔符，與 wrapper 內 `|| exit 1` 衝突；④ autotune 快取路徑未納入
> `ensure_autotune_cache_reset`（本 lane 用獨立 cache root；新增 profile 可宣告的
> `AUTOTUNE_CACHE_REL`）；⑤ 該 cache 目錄由 docker 以 root 建立，`eye` 無法搬移 → reset 先
> `mkdir -p` parent 並於兩節點一次性 chown。

#### qwen38flash 進一步實測（2026-09-20）

固定長度版（`bench-c.sh` 新增 `BENCH_IGNORE_EOS=1`，強制每 stream 恰好 `MAX_TOKENS=400`，
變異遠小於會提前停止的預設模式）：

| C | 固定長度 tok/s | （對照）變動長度中位數 |
|---|---|---|
| 1 | 41.7 | 40.4 |
| 2 | 55.3 | 58.9 |
| 3 | 93.7 | 88.2 |
| 4 | 105.0 | 101.0 |
| 8 | 161.1 | 156.2 |

| prefill probe (`bench-ctx.sh`, max_tokens=1) | qwen38flash tok/s |
|---|---|
| 32K | 2644.2（含暖機） |
| 131K | 2900.2 |
| 200K | 2716.9 |
| 245K | 2630.2 |

| 圖片輸入 (`bench-mm.sh`, max_tokens=200) | prompt tok | wall (s) | agg tok/s |
|---|---|---|---|
| 1 img, C=1 | 768 | 3.14 | 40.5 |
| 4 img, C=1 | 2886 | 3.40 | 32.7 |
| 1 img, C=4 | 768 × 4 | 7.16 | 86.3 |
| 1 img, C=8 | 768 × 8 | 7.86 | 135.7 |

> 每張圖約 597 prompt tokens（1 圖總 prompt 768）。profile 未設 `--limit-mm-per-prompt`，
> vLLM 預設即允許 ≥8 張（C=8 無錯誤）。
> 多輪穩定（`scripts/bench-multiturn.sh 6 300`）：**6/6 clean turns**（每輪 `finish=stop`、內容非空）。
> **`PLE_OFFLOAD=true` 不適用於 TP2**：實測啟動即被 vLLM 拒絕 ——
> `VLLM_PLE_CPU_OFFLOAD does not support the requested configuration. Unsupported settings: nnodes=2`。
> PLE CPU offload 是**單節點**功能；本 lane 維持 `PLE_OFFLOAD=false`（配方預設），
> `ULIMITS` profile 欄位仍為通用能力（實測 `nofile=1048576` 確實套用）。

## Topology

```text
Node0  spark-25d5  (192.168.23.215 / 10.0.101.101 interconnect)  rank0 = API server :1234
Node1  spark-8095  (192.168.23.216 / 10.0.101.102 interconnect)  rank1 = headless worker
```

**Unified LLM endpoint convention** — all LLM runtimes serve the OpenAI-compatible
API on **port 1234, sharing one `VLLM_API_KEY`** (set the same value in `cluster.env`
and both nodes' `docker-stacks/config/standalone.env`):

| runtime | endpoint | notes |
|---|---|---|
| TP2 cluster (rank0) | `http://192.168.23.215:1234/v1` | this repo, `API_PORT=1234` |
| Node0 single LLM | `http://192.168.23.215:1234/v1` | `gb10-single use node0 27b\|35b` |
| Node1 single LLM | `http://192.168.23.216:1234/v1` | `gb10-single use node1 27b\|35b` |

TP2 and the single-node LLMs are **mutually exclusive** (same port):
`gb10 use` frees both nodes' singles; a `gb10-single use/start` on either node
tears down TP2 first. Image/video runtimes (ComfyUI / MiniMaxH3) are out of scope.

Node0 is single side of control: every `cluster-*`/`gb10` command runs on Node0 and
orchestrates Node1 over `ssh -i ~/.ssh/id_gb10_cluster eye@10.0.101.102`.
`gb10-single` can also drive single-node compose on `node0` (local) or `node1` (ssh).

**Where the repo lives:** checkout on **Node0 only**, at
**`~/workspace/ai-gb10-cluster-runtime-manager/`** — under home, *outside* `~/docker-stacks/`
(which stays purely for deployed runtime stacks). Node1 does **not** host the repo;
Node0 reaches it over ssh. Node1 only needs the image + model dirs + sudo docker.

## Cluster CLI — `gb10`

```bash
gb10 list                     # profile list (27b/35b + placeholders)
gb10 use 27b                  # default; TP2 up (cold ~7-15 min), waits /health
gb10 use 35b                  # switch exclusive cluster profile
gb10 stop                     # cluster-down (both nodes)
gb10 restart [27b|35b]
gb10 status                   # both nodes, RDMA, KV, health
gb10 inspect <profile>        # sanitized resolved-profile report (dry-run)
gb10 logs                     # follow cluster-node0
gb10 smoke                    # chat smoke
gb10 load                     # concurrent load
gb10 doctor
```

Current deployed TP2 profiles are 27B, 35B, DeepSeek (mainline 0731) and
DeepSeek Vision-Exp (data-driven from `cluster-profiles.d/`). `qwen38flash` and
`glm53flash` are single-node placeholders until their runtimes land.

### TP2 profile registry (completed 2026-09-05)

The TP2 profile layer is a **data-driven cluster profile registry** (see
`docs/TP2_PROFILE_REFACTOR_VALIDATION_2026-09-05.md`):

```text
cluster-profiles.d/
  27b.conf          # deployed + live-validated (world_size=2, maxlen 262144)
  35b.conf          # deployed + live-validated (world_size=2, maxlen 131072)
  deepseek.conf     # deployed + live-validated (fp8 DSpark mainline, 256k ctx)
  deepseek-vision.conf  # deployed + live-validated (Vision-Exp, same image as deepseek)
```

Each conf carries the **profile-scoped image** and per-model vLLM arguments, loaded once by
`scripts/cluster-common.sh`. Rank0 builds the authoritative argv; rank1 receives it as a
shell-escaped array (no eval). Networking/orchestration (TP2, SSH, RoCE/NCCL, API/auth,
resource exclusion) stays generic and cluster-owned. The existing 27B and 35B serves are the
regression controls and retained their effective launch behavior during the refactor.

Implementation handoff: **`[REDACTED:entropy:56].md`** (completed).

Separation of concerns:

```text
image / kernel patches
        !=
cluster profile / model settings
        !=
TP2 orchestration / networking
```

DeepSeek V4 Flash 0731 is deployed as a **TP2 cluster profile** (the legacy single-node
`runtimes.d/deepseek.conf` placeholder was retired 2026-09-05). The mainline uses the
official fp8 checkpoint (`deepseek-v4-flash-0731-official`, weights under
`~/docker-stacks/models`) with the public Anemll runtime
`ghcr.io/anemll/dspark-vllm-gx10:0.1.1`, SHA256SUMS-gated and validated with a real
generation. It serves the unified :1234 API at 256K context (same-model DSpark draft,
8 concurrent streams). The retired NVFP4 AEON lane is archived to
`~/_archieve/cluster-profiles.d/deepseek-nvfp4.conf`.

## Single-node CLI — `gb10-single`

```bash
gb10-single list [node0|node1]
gb10-single use {node0|node1} <runtime>     # exclusive switch
gb10-single start {node0|node1} <runtime>   # start
gb10-single stop {node0|node1} [runtime]
gb10-single restart {node0|node1} [runtime]
gb10-single status [node]
gb10-single logs {node0|node1} <runtime>
gb10-single doctor
```

Runtimes (`runtimes.d/*`):

| conf | id | group | status |
|---|---|---|---|
| `27b.conf` | 27b | llm (exclusive) | deployed (MTP) |
| `35b.conf` | 35b | llm (exclusive) | deployed (DFlash) |
| `qwen38flash.conf` | qwen38flash | llm | **placeholder** |
| `glm53flash.conf` | glm53flash | llm | **placeholder** |
| `comfyui.conf` | comfyui | image | deployed (Node1, Flux 2 Dev) |
| `minimaxh3.conf` | minimaxh3 | video (exclusive) | deployed (FL2VA) |

`use` on an exclusive runtime frees every OTHER active exclusive runtime on that
node across groups (e.g. starting `minimaxh3` on node1 also stops a running
`comfyui` there) and auto-tears down an active TP2 cluster first (做法 B).
Placeholders print "not deployed yet"; they are CLI skeletons until models/versions land.

## Config

- `cluster.env` (gitignored) — cluster/site knobs: `MASTER_ADDR/PORT`, `NODE0/1_IP`,
  `NCCL_*`, `API_PORT`, `VLLM_API_KEY`, `SUDO_PASS`. Each cluster profile may override/select
  its own image; the profile-scoped `IMG` in `cluster-profiles.d/*.conf` wins over the
  cluster default when present.
- Single-node compose files live under `~/docker-stacks/` on each host (referenced
  by `runtimes.d/*.conf` via `STACK_DIR`/`COMPOSE_FILE`).

## Non-negotiables (see docs/TP2_DEPLOYMENT_2026-08-30.md)

- Same resolved image **byte-identical on BOTH nodes** for TP2.
- RoCE v2 env as pinned in `cluster.env`/`cluster-common.sh`.
- `--disable-custom-all-reduce` load-bearing cross-node.
- Existing Qwen TP2 profiles use `--kv-cache-dtype fp8_e4m3`; do not generalize that into a
  universal rule for future model families. DeepSeek gets its own profile policy.
- Prefix caching remains deliberately OFF for TP2 27B DFlash2; see
  `[REDACTED:entropy:42].md`.
- GB10 `nvidia-smi` is unreliable — trust engine metrics.

## Layout

```text
bin/            gb10 (cluster), gb10-single (single-node)
scripts/        cluster-up|down|status|smoke|load + cluster-common.sh
runtimes.d/     *.conf single-node runtime definitions
cluster-profiles.d/  data-driven TP2 profile registry (active ownership by cluster-common.sh)
state/          last-runtime marker files (gitignored, empty = normal)
docs/           deployment notes, ADRs, restructure + active handoffs
cluster.env.example cluster/site config template (NEVER commit real values)

~/docker-stacks/    node-local deploy artifacts (NOT in this repo):
  <stack>/          one dir per lane, named after the image source —
                    aeon-vllm-omni (27b/35b) · anemll-dspark-vllm-gx10 (deepseek)
                    anemll-dspark-vllm-gx10-miaFlaver (deepseek-vision)
                    mia-vllm-openai-qwen38flashNext (qwen38flash)
    docker-compose.<profile>.yml            (cluster-only lanes, materialized)
    docker-compose-<profile>-cluster.yml    (lanes that also run single: 27b/35b)
    docker-compose-<profile>-single.yml
    patches/                                SYNC_DIRS staging (lanes that need it)
  logs/<profile>/   unified boot + compose/container logs (not per-stack)
  config/           cluster.env / standalone.env (secrets, gitignored)
~/.cache/vllm-<profile>[-cluster|-single]   per-lane compile/autotune cache
```

### state/ — 執行期「最後狀態」標記（非架構內容，空目錄屬正常）

`state/` 是 **執行期快取／便利記憶層**，不是部署契約；`docker-stacks/` 的 compose 與
`cluster-profiles.d/*.conf` 才是 source of truth。這個目錄刻意 **不納入版本控制**
（`.gitignore`），因此**內容為空、甚至目錄不存在，都是正常狀態**——代表「目前沒有可
記憶的上次選擇」，CLI 會落回預設值（如 TP2 預設 `27b`）。

目前已定義的標記檔：

- **`state/last-runtime`** — 由 `bin/gb10-single` 寫入／讀取（`STATE=${REPO_DIR}/state`）。
  - **寫入**：`use`／`start` 成功啟動一個單機 runtime 後，寫入 `node/runtime_ID`
    （例如 `node1/minimaxh3`），記住「這個 node 上次選了哪個 runtime」。
  - **讀取**：後續 `use`／`start` 在某台 node 上未指定 runtime 時，以此作為上次選擇的
    回退依據（`awk -F/ '{print $2}'` 拆出 runtime ID）；若無此檔，則視為「該 node
    沒有 active 或 previous runtime」並提示。
  - 注意：TP2 主動使用時，單機端**不該**有 `last-runtime`（單機與 TP2 互斥，見上方
    Unified LLM endpoint 說明）。

- **`state/last-cluster-profile`** — 由 `bin/gb10` 讀取
  （`P="${2:-$(cat "${REPO_DIR}/state/last-cluster-profile" ... || echo 27b)}"`），
  在未指定 TP2 profile 時，回退到「上次選用的 cluster profile」，否則預設 `27b`。

**所以如果你檢查時發現 `state/` 是空目錄：那不是沒用的架構，而是正常的初始／乾淨
狀態**，只是還沒觸發過任何寫入動作（或某台 node 從未成功 `use`／`start` 過）。只要
`gb10 use 27b`、`gb10-single use node1 minimaxh3` 這類動作真正跑過一次，對應的標記檔
就會出現；之後記得它是執行期產物即可。
