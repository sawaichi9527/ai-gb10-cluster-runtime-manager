# DGX Spark Node1 — SGLang + MiniMax H3 NVFP4 部署任務書（Runtime Manager 整合版）

> **用途**：交付另一台 OpenCode 電腦執行。  
> OpenCode 需以現有 GitHub repo `sawaichi9527/ai-gb10-cluster-runtime-manager` 為控制面，透過 Node0 管理 Node1，完成 **SGLang Diffusion + MiniMax H3 FL2VA NVFP4** 的候選部署、驗證、OOM 邊界測試與 production cutover。
>
> 日期：2026-09-03  
> 目標節點：**Node1 / spark-8095 / 192.168.23.216 / 10.0.101.102**  
> 控制節點：**Node0 / spark-25d5 / 192.168.23.215 / 10.0.101.101**  
> Runtime manager repo：`~/ai-gb10-cluster-runtime-manager/`（**只存在 Node0**）  
> 現有 H3 runtime：`minimaxh3`，vLLM-Omni FP8，已部署並驗證  
> 新候選 backend：SGLang Diffusion + MiniMax H3 FL2VA pruned NVFP4

---

# 0. 先理解現有架構：不可自行重構

## 0.1 現有控制模式

```text
OpenCode 工作站
      │
      │ SSH
      ▼
Node0 / spark-25d5
~/ai-gb10-cluster-runtime-manager/
      │
      ├─ bin/gb10              → TP2 cluster manager
      │
      └─ bin/gb10-single       → single-node runtime manager
                                  │
                                  └─ SSH → Node1 / spark-8095
```

Node1 **不應 clone runtime-manager repo**。

Node1 只需要：

- Docker / NVIDIA runtime
- `~/docker-stacks/...`
- models / HF cache
- 可被 Node0 以既有 cluster SSH key 控制

## 0.2 Source of Truth

必須遵守 repo 現有規則：

```text
Compose = deployed runtime source of truth
CLI     = convenience/orchestration layer
```

日常 runtime 操作應由：

```bash
gb10
gb10-single
```

完成。

**禁止另做一套與 `gb10-single` 平行的 start/stop/status runtime manager。**

---

# 1. 目前 Node1 已存在的 MiniMax H3

現有 production runtime：

```text
RUNTIME_ID = minimaxh3
GROUP      = video
MODE       = exclusive
STACK_DIR  = ~/docker-stacks/minimax-h3
PORT       = 8000
```

現有 backend：

```text
vLLM-Omni
+
MiniMax H3 FL2VA
+
online FP8 / SM121 patch
```

已驗證：

- `/health` = 200
- `/v1/videos/sync` 可用
- 768×448 / 24fps / native AAC stereo PASS
- cold start 約 11.9 分鐘
- image：`minimax-h3-dgx-spark:sm121-fp8`
- 原始 FL2VA weights 約 134 GiB
- runtime memory footprint 很高

本次工作目標：

> **降低 H3 runtime weight/resident memory，將節省的 UMA 換成更大的 `resolution × frames` capacity。**

---

# 2. 本次架構決策

## 2.1 不直接覆蓋現有 production stack

第一階段新增候選 stack：

```text
Node1
~/docker-stacks/minimax-h3-sglang/
```

現有：

```text
~/docker-stacks/minimax-h3/
```

完整保留。

不得：

- rm 現有 image
- rm 現有 model
- overwrite 現有 `.env`
- 改寫現有 `compose.yaml`
- 刪除 `minimaxh3` runtime conf

在新 SGLang stack 驗證通過以前，現有 vLLM-Omni H3 是唯一 production fallback。

---

# 3. Runtime Manager 整合策略

## 3.1 Candidate bring-up 階段

**不要先把 candidate 寫進 `runtimes.d/`。**

原因：

`runtimes.d/*.conf` 是 node0 / node1 共用 registry，目前沒有 per-node availability metadata。

本次明確只在 Node1 bring-up，因此 candidate 階段先：

1. 由 Node0 runtime manager 釋放 Node1 GPU。
2. 再透過 SSH 到 Node1 手動啟動 candidate compose。
3. 完成所有驗證。
4. 最後才進 production cutover。

### Candidate bring-up 前必須執行

在 Node0：

```bash
cd ~/ai-gb10-cluster-runtime-manager

bin/gb10 status
bin/gb10-single status node1
```

然後：

```bash
bin/gb10-single free node1
```

若 TP2 active，必須使用 repo 既有邏輯拆除：

```bash
bin/gb10 stop
```

或由 `gb10-single use/start` 的 protection path 處理。

**不要直接 `docker rm -f tp2-*` 作為正常操作方式。**

---

# 4. Production Cutover 策略

候選 SGLang stack完全驗證通過後：

> **沿用 runtime ID `minimaxh3`，只切換其 backend implementation。**

理由：

- Operator 指令不變
- 上層語意不變
- `GROUP=video`
- `MODE=exclusive`
- 仍使用 OpenAI-style `/v1/videos`
- 不需要增加新的 runtime manager abstraction

Production 最終仍應：

```bash
gb10-single use node1 minimaxh3
```

## 4.1 Cutover 時修改

更新：

```text
runtimes.d/minimaxh3.conf
```

使其指向：

```text
STACK_DIR="${HOME}/docker-stacks/minimax-h3-sglang"
COMPOSE_FILE="compose.yaml"
PROJECT="minimax-h3-sglang"
SERVICE="minimax-h3-sglang"
CONTAINER="minimax-h3-sglang-fl2va"
HEALTH_URL="http://127.0.0.1:8000/health"
```

保留：

```text
RUNTIME_ID="minimaxh3"
ALIASES="minimax mm-h3 h3"
MODE="exclusive"
GROUP="video"
PLACEHOLDER="false"
```

### 很重要

`PROJECT / SERVICE / CONTAINER` 必須與舊 vLLM stack **明確不同**。

不要兩個 implementation 共用相同 Docker identity。

這可以避免 runtime manager 出現：

```text
錯把另一個 compose project 判斷成目前 runtime
```

的問題。

---

# 5. API 與 Port 策略

## 5.1 Production port 維持 8000

候選驗證階段可暫用：

```text
30010
```

避免意外撞到舊 H3。

Production cutover 後改成：

```text
8000
```

如此既有 client endpoint 可以保持：

```text
http://192.168.23.216:8000/v1
```

主要 endpoint：

```text
POST /v1/videos
GET  /v1/videos/{id}
GET  /v1/videos/{id}/content
GET  /v1/models
GET  /health
```

## 5.2 Auth

現有 vLLM H3 使用：

```text
H3_API_KEY
Authorization: Bearer ...
```

SGLang candidate 必須確認其目前使用的 Python diffusion server 是否可由 native `--api-key` 保護 `/v1/*`。

### Acceptance requirement

如果 native API-key 可用：

```text
沿用既有 H3_API_KEY
```

如果該版 SGLang diffusion server 沒有可驗證的 API-key enforcement：

- candidate 階段僅限 localhost / trusted LAN
- production 前必須補上等價 access control
- 不可把 unauthenticated `0.0.0.0:8000` 當 production 完成

**不要只因 OpenAI client 送了 Authorization header，就假設 server 有驗證。**

---

# 6. SGLang 版本策略

第一個 baseline：

```text
lmsysorg/sglang:v0.5.18-cu130
```

原則：

```text
stable immutable tag first
```

禁止 production 使用：

```text
latest
dev
floating nightly
```

## 6.1 Preflight stable image

先確認：

```bash
docker pull lmsysorg/sglang:v0.5.18-cu130

docker image inspect lmsysorg/sglang:v0.5.18-cu130 \
  --format '{{.Architecture}} {{.Os}}'
```

必須為：

```text
arm64 linux
```

測試：

```bash
docker run --rm --gpus all \
  lmsysorg/sglang:v0.5.18-cu130 \
  bash -lc '
    uname -m
    python - <<PY
import torch
print(torch.__version__)
print(torch.cuda.is_available())
print(torch.cuda.get_device_name(0))
PY
    sglang serve --help >/tmp/sglang-help.txt
    grep -i minimax /tmp/sglang-help.txt || true
  '
```

---

# 7. Diffusion extras 政策

SGLang 官方 Diffusion Docker recipe 目前仍有：

```bash
python -m pip install -e "/sgl-workspace/sglang/python[diffusion]"
```

的流程。

因此：

> **不要假設 stable image 一定已帶齊 H3 diffusion extras。**

先做：

```bash
python - <<'PY'
import sglang
print("sglang import OK")
PY
```

並嘗試：

```bash
sglang serve --help
```

以及最小 H3 model config dry-run。

若缺 dependency，才建立：

```text
~/docker-stacks/minimax-h3-sglang/Dockerfile
```

例如：

```dockerfile
ARG SGLANG_BASE=lmsysorg/sglang:v0.5.18-cu130
FROM ${SGLANG_BASE}

RUN python -m pip install -e "/sgl-workspace/sglang/python[diffusion]"
```

禁止：

- clone SGLang main
- pip upgrade torch
- pip replace CUDA runtime
- 自行 patch SGLang source
- 安裝不必要的 ComfyUI stack

---

# 8. 模型方案

第一階段：

```text
MiniMax H3 FL2VA
```

量化：

```text
Transformer:
MiniMax_H3_FL2VA_pruned_nvfp4.safetensors

Text Encoder:
qwen3vl_32b_minimax_h3_nvfp4_awq.safetensors

Video VAE:
minimax_h3_video_vae_fp16.safetensors

Audio VAE:
minimax_h3_audio_vae_fp32.safetensors
```

來源候選：

```text
Abiray/Minimax-H3-nvfp4-INT4-INT8-Convrot
```

約略靜態檔案：

```text
DiT           ~12.5 GB
Text encoder  ~15.7 GB
Video VAE      ~5.2 GB
Audio VAE      ~0.6 GB
----------------------
Total         ~34 GB
```

注意：

> checkpoint size != runtime peak memory。

---

# 9. Model storage

Candidate 建議：

```text
~/docker-stacks/minimax-h3-sglang/
├── compose.yaml
├── .env
├── Dockerfile          # only if needed
├── models/
│   └── quantized/
├── input/
├── output/
└── scripts/
```

不要覆蓋：

```text
~/docker-stacks/minimax-h3/models/MiniMax-H3/
```

既有 134 GiB reference weights。

這些 reference weights 是 rollback / quality baseline 的資產。

---

# 10. SGLang H3 component override

SGLang H3 使用 native pipeline：

```bash
sglang serve \
  --model-path MiniMaxAI/MiniMax-H3 \
  --model-variant fl2va \
  --component-weights-paths.transformer <NVFP4_DIT> \
  --component-weights-paths.text_encoder <NVFP4_ENCODER> \
  --component-weights-paths.video_vae <VIDEO_VAE> \
  --component-weights-paths.audio_vae <AUDIO_VAE>
```

## 10.1 不要加

```text
--quantization nvfp4
```

因為上述 pre-quantized files 是 self-describing。

---

# 11. 初始保守 profile

第一輪必須降低變數：

```text
single GB10
TP=1
SP=1
concurrency=1
FL2VA
exact attention first
torch.compile OFF
CPU offload OFF
layerwise offload OFF
FastH3 OFF
Cache-DiT OFF
Sol-Attn OFF
SageAttention OFF
```

理由：

本次第一個目標是：

> **驗證 GB10 SM121 + SGLang native H3 + NVFP4 是否穩定。**

不是先追求 latency。

---

# 12. Docker Compose 要求

Candidate compose 必須具備：

```text
unique project
unique container name
network exposure explicit
GPU all
sufficient shm
HF cache volume
model read-only mount
output volume
restart policy conservative
```

概念：

```yaml
services:
  minimax-h3-sglang:
    image: ${SGLANG_IMAGE}
    container_name: minimax-h3-sglang-fl2va
    gpus: all
    ipc: host
    shm_size: "16gb"
    ports:
      - "${H3_PORT:-30010}:${H3_PORT:-30010}"
    volumes:
      - ./models:/models:ro
      - ./input:/data/minimax-h3:ro
      - ./output:/output
      - ${HF_CACHE_DIR}:/root/.cache/huggingface
    environment:
      PYTORCH_CUDA_ALLOC_CONF: expandable_segments:True
```

實際 command 必須依當前 `sglang serve --help` 驗證後填入。

**不可把未驗證 flag 硬寫進 production compose。**

---

# 13. Remote 部署操作規則

OpenCode 工作站：

```text
不要把 Node1 當 control-plane
```

Primary remote entry：

```bash
ssh eye@<NODE0_LAN_IP>
```

Node0 repo：

```bash
cd ~/ai-gb10-cluster-runtime-manager
git status
git log -5 --oneline
```

任何 runtime-manager repo 變更：

```text
edit → bash -n → git diff → commit
```

Node1 provisioning 才透過：

```bash
ssh -i ~/.ssh/id_gb10_cluster eye@10.0.101.102
```

---

# 14. Candidate bring-up sequence

## Phase A — collect baseline

Node0：

```bash
cd ~/ai-gb10-cluster-runtime-manager

bin/gb10 status
bin/gb10-single status node0
bin/gb10-single status node1
```

Node1：

```bash
free -h
swapon --show
df -h / /home
docker ps
docker images
```

記錄目前：

- MemAvailable
- SwapUsed
- old H3 image size
- old H3 stack disk usage
- current containers
- current runtime-manager git commit

---

## Phase B — free Node1

Node0：

```bash
bin/gb10-single free node1
```

確認：

```bash
bin/gb10-single status node1
docker ps
```

Node1 MemAvailable 應回到接近 idle 水準。

---

## Phase C — deploy SGLang candidate

在 Node1 建立：

```bash
mkdir -p ~/docker-stacks/minimax-h3-sglang/{models,input,output,scripts}
cd ~/docker-stacks/minimax-h3-sglang
```

建立：

```text
.env
compose.yaml
Dockerfile (only if needed)
```

先跑：

```bash
docker compose config --quiet
```

PASS 後：

```bash
docker compose up -d
docker logs -f minimax-h3-sglang-fl2va
```

---

# 15. Health validation

candidate 暫時使用：

```text
127.0.0.1:30010
```

至少驗證：

```bash
curl -fsS http://127.0.0.1:30010/health
curl -fsS http://127.0.0.1:30010/v1/models
```

必須記錄：

```text
startup elapsed
idle MemAvailable
idle SwapUsed
container RSS
```

---

# 16. API smoke test

先固定最小 T2VA：

```text
short edge = 768
aspect     = 16:9
duration   = 5s
steps      = 50
seed       = fixed
concurrency= 1
```

API：

```text
POST /v1/videos
```

取得：

```text
video_id
```

poll：

```text
GET /v1/videos/{video_id}
```

下載：

```text
GET /v1/videos/{video_id}/content
```

驗證 MP4：

```bash
ffprobe
```

必須包含：

```text
H.264 video
24fps
AAC
32kHz
stereo
```

---

# 17. FL2VA smoke test

加入：

```text
first-frame image
```

驗證：

```text
task = fl2va
```

必須確認：

- image condition 真正生效
- video generation PASS
- native audio PASS
- output 完整可 decode

---

# 18. UMA / OOM 監控

DGX Spark 不可只看 `nvidia-smi`。

每個 case 至少同步記錄：

```bash
free -h
grep -E 'MemTotal|MemAvailable|SwapTotal|SwapFree' /proc/meminfo
swapon --show
docker stats --no-stream
```

建議背景採樣：

```bash
while true; do
  printf '%s ' "$(date -Is)"
  awk '/MemAvailable|SwapFree/ {printf "%s=%s ",$1,$2} END {print ""}' /proc/meminfo
  sleep 2
done
```

記錄：

```text
idle
text encode peak
denoise peak
VAE decode peak
post-request
```

---

# 19. Capacity test matrix

目標不是最快，而是：

> **最大 safe `resolution × frames`。**

固定：

```text
concurrency = 1
seed        = fixed
steps       = fixed
prompt      = fixed
audio       = enabled
```

測試：

| Stage | Resolution / target | Duration | Result |
|---|---|---:|---|
| Baseline | 960×576 class | 5s | |
| A | 1344×768 class | 5s | |
| B | 1344×768 class | 8s | |
| C | 1344×768 class | 10s | |
| D | 1344×768 class | 12s | |
| E | 1344×768 class | 15s | |

第一次 OOM 後：

- 不要繼續向上
- 回退前一級
- 重跑至少 2 次
- 確認不是 allocator fragmentation / leftover process

如果 768-class 15s OOM：

固定 15s，再降低 pixel count：

```text
1216×704 class
1152×640 class
960×576 class
```

---

# 20. Quality comparison

與舊 vLLM-Omni FP8 reference 使用：

```text
same prompt
same seed where semantically supported
same duration
closest geometry
same step count
```

比較：

- subject consistency
- motion
- temporal stability
- audio sync
- audio quality
- prompt adherence
- artifacts

NVFP4/pruned 不要求 bit-exact。

目標是確認：

> memory capacity 提升是否值得品質 trade-off。

---

# 21. Production Cutover Gate

只有全部符合才允許切 production：

- SGLang container cold start PASS
- `/health` PASS
- `/v1/models` PASS
- T2VA PASS
- FL2VA PASS
- audio PASS
- fixed-seed repeated generation PASS
- 至少一個 768-class case PASS
- OOM recovery PASS
- restart PASS
- API auth/access-control PASS
- runtime manager integration PASS
- rollback 已演練

---

# 22. Cutover

候選通過後：

## 22.1 repo 修改

Node0：

```text
runtimes.d/minimaxh3.conf
docs/MINIMAX_H3_SGLANG_DEPLOYMENT_2026-09-03.md
AGENTS.md（只補必要 factual change）
```

不要重寫 `gb10-single`，除非真的發現 manager bug。

## 22.2 最終 runtime conf

概念：

```bash
RUNTIME_ID="minimaxh3"
DISPLAY_NAME="MiniMax H3 (SGLang FL2VA NVFP4)"
ALIASES="minimax mm-h3 h3"
MODE="exclusive"
GROUP="video"
PLACEHOLDER="false"

STACK_DIR="${HOME}/docker-stacks/minimax-h3-sglang"
COMPOSE_FILE="compose.yaml"
PROJECT="minimax-h3-sglang"
SERVICE="minimax-h3-sglang"
CONTAINER="minimax-h3-sglang-fl2va"

IDENTITY_MOUNT=""
HEALTH_URL="http://127.0.0.1:8000/health"
TIMEOUT="2400"
```

## 22.3 production port

Candidate：

```text
30010
```

Production：

```text
8000
```

---

# 23. Production manager test

Node0：

```bash
bin/gb10-single use node1 minimaxh3
```

必須確認：

1. TP2 被正確拆除（若 active）。
2. Node1 其他 exclusive runtime 被停止。
3. SGLang H3 compose 啟動。
4. `wait_ready` 最終 READY。
5. `status node1` 只顯示正確 runtime running。
6. `logs node1 minimaxh3` 可正常 follow。

---

# 24. Rollback

舊 stack 必須完整保留：

```text
~/docker-stacks/minimax-h3/
```

以及：

```text
minimax-h3-dgx-spark:sm121-fp8
```

rollback 方法：

1. revert `runtimes.d/minimaxh3.conf`
2. production port 8000 釋放
3. `gb10-single use node1 minimaxh3`
4. `/health`
5. old smoke test

最好將 production cutover 做成單一 git commit。

這樣：

```bash
git revert <cutover-commit>
```

即可把 runtime-manager pointer 回復。

---

# 25. SGLang upgrade policy

Production baseline 驗證完成後記錄：

```text
SGLang image tag
image digest
Python version
torch version
CUDA version
SGLang version
H3 model files
model sha256 / HF revision
compose sha256
```

未來升級：

```text
v0.5.18
→ v0.5.19
→ v0.5.20
→ ...
```

不要直接覆蓋 production。

建立 candidate image：

```text
new tag
same model
same compose except image
same test matrix
```

只有：

```text
smoke + quality + memory + capacity + restart
```

全部 PASS 才切 production。

---

# 26. 不要做的事情

OpenCode 執行者不得自行：

1. 把 repo clone 到 Node1 當第二份 control plane。
2. 新建平行 runtime-manager scripts。
3. 直接修改 `gb10-single` exclusive policy。
4. 直接刪除舊 vLLM H3。
5. 刪除 134 GiB reference model。
6. 把 quantized model bake 進 Docker image。
7. 使用 floating `dev/latest` production。
8. 一開始開 FastH3。
9. 一開始開 Sol-Attn/SageAttention。
10. 一開始用 CPU/layerwise offload。
11. 一開始嘗試 TP2 H3。
12. 因 `nvidia-smi` 數字看起來還有空間就判斷不會 OOM。
13. 把 unauthenticated LAN API 當 production finished。

---

# 27. OpenCode 最終交付內容

任務完成後，必須回傳：

## A. Repo

```text
git status
git log -5 --oneline
git diff <before>..<after>
```

## B. Node1 stack

```text
~/docker-stacks/minimax-h3-sglang/
├── compose.yaml
├── .env.example
├── Dockerfile       # if used
├── scripts/
└── HANDOFF.md
```

**不要回傳 secret `.env`。**

## C. Runtime evidence

```text
docker image inspect
docker compose config
docker ps
/health
/v1/models
```

## D. Video evidence

至少：

```text
T2VA 5s
FL2VA 5s
highest safe capacity case
```

附：

```text
ffprobe
file size
sha256
elapsed time
```

## E. Memory evidence

每 case：

```text
MemAvailable minimum
Swap peak
container RSS
OOM / PASS
```

## F. Comparison table

| Runtime | Geometry | sec | steps | elapsed | peak UMA | swap | result |
|---|---|---:|---:|---:|---:|---:|---|
| old vLLM FP8 | | | | | | | |
| SGLang NVFP4 | | | | | | | |

---

# 28. Definition of Done

本任務不是「container 有起來」就完成。

完成定義：

```text
Node1
  ↓
gb10-single 管理
  ↓
minimaxh3 runtime
  ↓
SGLang Diffusion
  ↓
MiniMax H3 FL2VA NVFP4
  ↓
OpenAI-style /v1/videos
  ↓
native video + audio
  ↓
768-class capacity boundary verified
  ↓
old vLLM FP8 rollback retained
```

並且：

```text
Node0 remains the only runtime-manager control plane.
Node1 remains a managed runtime host.
```

---

# 29. Repo source-of-truth files that must be read before editing

OpenCode 執行者開始前必讀：

```text
README.md
AGENTS.md
bin/gb10-single
runtimes.d/minimaxh3.conf
docs/RESTRUCTURE_2026-08-31.md
docs/MINIMAX_H3_DEPLOYMENT_2026-09-01.md
```

任何本文件與 repo 最新內容衝突時：

> **以 repo 最新 `AGENTS.md` + 實際 runtime state 為準，並把衝突回報。**

---

# 30. 建議實作順序摘要

```text
1. Clone/read GitHub repo on OpenCode workstation
2. SSH Node0
3. Read live repo + git HEAD
4. gb10 / gb10-single status
5. Free Node1 using manager
6. SSH Node1
7. Create candidate minimax-h3-sglang stack
8. Pull pinned ARM64 SGLang image
9. Verify diffusion extras
10. Build thin wrapper only if required
11. Download/mount NVFP4 components
12. Start candidate on :30010
13. /health + /v1/models
14. T2VA 5s
15. FL2VA 5s
16. Capacity/OOM matrix
17. Auth/access-control verification
18. Restart/recovery test
19. Compare old FP8 vs new NVFP4
20. Update minimaxh3.conf
21. Switch production port to :8000
22. gb10-single use node1 minimaxh3
23. Production smoke
24. Rollback drill
25. Commit docs + conf
26. Return evidence
```

---

# 31. 執行實況與決策演進（2026-09-03  實際部署 log）

> **用途**：這段是「實際執行到目前」的完整記錄，包含遇到的問題、驗證到的事實、路徑切換的決策歷程，以及目前卡關狀態。  
> 此段為 **append-only 事件記錄**，上面第 0–30 節的原始任務書原樣保留作為參考。  
> 交付對象：丟回 ChatGPT 質問時，以本段為「已發生事實」的 ground truth。

## 31.1 時間軸總覽

| 階段 | 內容 | 狀態 |
|---|---|---|
| Phase 0/A/B/C | git snapshot、確認舊 H3、建立 stack 目錄、下載 4 個量化權重 | ✅ 完成 |
| SGLang 鏡像 | `lmsysorg/sglang:v0.5.18-cu130`（arm64）拉取成功 | ✅ 完成 |
| CLI 調查 | 確認 v0.5.18 支援的 diffusion flags | ✅ 完成 |
| **路徑 A → 官方 BF16 → 本地 fp8** | 三次策略轉向（詳下） | 🔀 已切換 |
| 現況 | 本地官方 FL2VA + `--quantization fp8` 啟動中，**Node SSH 卡死** | ⏸️ 阻塞 |

---

## 31.2 原始假設 vs 實地真相（關鍵落差）

### 落差 1：我們下載的不是官方 repo 布局

任務書第 8 節假設用 **4 個 ComfyUI 慣例的量化單檔**走 `--component-weights-paths.*` 餵給 SGLang：

| 下載檔 | 官方 repo 對應 | 實況 |
|---|---|---|
| `MiniMax_H3_FL2VA_pruned_nvfp4.safetensors`（12.5GB 單檔） | `transformer/` 14 份 **BF16 shards** + index | ❌ 我們是 **ComfyUI NVFP4 量化單檔** |
| `qwen3vl_32b_minimax_h3_nvfp4_awq.safetensors`（15.7GB 單檔） | `text_encoder/` 14 份 BF16 shards | ❌ 我們是 **AWQ 量化單檔** |
| `minimax_h3_video_vae_fp16.safetensors`（5.2GB） | `FL2VA/video_vae/source/model.safetensors`（10.4GB fp16） | ⚠️ 尺寸差一倍 |
| `minimax_h3_audio_vae_fp32.safetensors`（605MB） | `audio_vae/model.safetensors`（605MB） | ✅ 完全吻合 |

**結論**：任務書的 NVFP4 方案源自 ComfyUI/Abiray 慣例，**與官方 `MiniMaxAI/MiniMax-H3` HF repo 的 diffusers sharded BF16 布局不同**。v0.5.18 loader 依 diffusers 慣例解析，預設吃官方 BF16 分片，無法直接吃這些量化單檔。

### 落差 2：v0.5.18 不支援任務書寫的 CLI flags

任務書第 10 節寫的：

```bash
--component-weights-paths.transformer <NVFP4_DIT>
--component-weights-paths.text_encoder <NVFP4_ENCODER>
--api-key ...
```

**v0.5.18-cu130 全部不認可**（連 `--model-type diffusion` 下也報 `unrecognized arguments`）：

- 實測 v0.5.18 **沒有** `--component-weights-paths.*`（那些屬新版 docs）
- `transformer_weights_path`（singular）+ `component_transformer_weights_paths`（dict）是 **config 驅動**（`model_index.json` / `nunchaku_config`），不是 CLI dot-flags
- `--api-key` 也不支援

v0.5.18 實際支援的 diffusion flags：

```text
--model-type {auto,llm,diffusion}
--model-variant fl2va
--quantization {fp8,...}
--quantization-ignored-layers <...>
--performance-mode
--component-attention-backends
--component-residency COMPONENT=MODE
--cpu-offload-components
--layerwise-offload-components
```

### 落差 3：NVFP4 DiT 需要 nunchaku，但鏡像沒裝

- v0.5.18 的 NVFP4 DiT 載入路徑靠 **nunchaku（SVDQuant W4A4）**：`NunchakuConfig(precision="nvfp4")` + `transformer_weights_path` + `_patch_nunchaku_scales` 讀 `wtscale/wcscales`
- **但 `nunchaku` 套件沒裝** 在 `v0.5.18-cu130` 鏡像裡（`ModuleNotFoundError`）
- AWQ text encoder 在 v0.5.18 的載入路徑未驗證（雖有 `text_encoder_loader.py`/`vl_encoder_loader.py`）
- 若要走 NVFP4：需裝 nunchaku + 組本地 diffusers repo + 接 `transformer_weights_path` + 賭 AWQ 也吃得下 → **高風險、多次實驗、未驗證**

### 落差 4：官方 BF16 FL2VA 權重其實早已在 Node1（不用下載）

查舊 vLLM-Omni stack 的 `.env` / `start-fp8.sh` 發現：

```bash
MINIMAX_H3_MODEL_DIR=/home/eye/docker-stacks/minimax-h3/models/MiniMax-H3/FL2VA
# 135G，已存在，含 model_index.json + audio_vae/processor/text_encoder/tokenizer/transformer/video_vae
```

**官方 FL2VA 權重（135GB）一直都在這台 Node1**，由舊 stack 掛載使用。**完全不必下載 134GB**。

### 落差 5：官方 BF16 134GB 塞不進 128GB 單卡 — 但舊 stack 用 FP8 證明可行

- FL2VA 官方 BF16 權重總量 = **134.2 GB**
- DGX Spark 統一記憶體 = **128 GB** → **BF16 權重本身單卡就放不下**（還沒算 activation/attention/denoise）
- cookbook 的「FL2VA BF16 = 83.5GB/GPU」是 **8 顆 B300**（134GB 攤 8 顆 ≈ 17GB/GPU）
- **舊 vLLM-Omni H3 在 Node1 用 FP8 單卡跑得動**（`minimax-h3-dgx-spark:sm121-fp8`，`--num-gpus 1`）→ **FP8 是本機已被驗證的可行方式**

---

## 31.3 路徑切換決策歷程

| 序 | 方案 | 決策 | 原因 |
|---|---|---|---|
| 1 | **路線 A**：用我們下載的 NVFP4/AWQ 單檔重組成官方 diffusers repo 布局 | 🔀 放棄 | v0.5.18 loader 不吃 ComfyUI 量化單檔；需裝 nunchaku + AWQ 路徑未驗證 |
| 2 | **選項 2**：下載官方 BF16 後用 v0.5.18（cookbook 驗證路） | 🔀 再修正 | 官方 BF16 134GB **放不下 128GB 單卡**（最好也只算到 8 GPU） |
| 3 | **最終方案（進行中）**：用**已存在的本地官方 FL2VA 135GB** + `--quantization fp8` 線上量化 | ✅ 採納 | ① 不用下載 ② 與舊 vLLM-Omni FP8 部署一致（本機已被驗證）③ cookbook 有 FL2VA FP8 驗證數字（51.9GB/GPU / load 116s / latency 18s） |

---

## 31.4 目前的部署設定（本地官方 FL2VA + fp8）

### compose: `~/docker-stacks/minimax-h3-sglang/compose.sglang.yaml`

```yaml
image: lmsysorg/sglang:v0.5.18-cu130
container_name: minimax-h3-sglang-fl2va
network_mode: host
ipc: host
shm_size: 32gb
gpus: all
volumes:
  - .../launch.sh:/launch.sh:ro
  - /home/eye/docker-stacks/minimax-h3/models/MiniMax-H3:/models/MiniMax-H3:ro   # 掛父目錄
  - .../models/quantized:/models/quantized:ro
  - .../output:/data/minimax-h3
  - .../.cache/huggingface:/root/.cache/huggingface
entrypoint: ["/bin/bash"]
command: ["/launch.sh"]
```

### launch.sh（第 3 版，最終）

```bash
python3 -m pip install -e "/sgl-workspace/sglang/python[diffusion]"   # 每次 boot 都會跑，耗時
exec sglang serve \
  --model-path /models/MiniMax-H3 \
  --model-variant fl2va \
  --quantization fp8 \
  --quantization-ignored-layers "video_patch_proj audio_patch_proj time_embedder.proj_in time_embedder.proj_out final_layer.video_out final_layer.audio_out" \
  --host 0.0.0.0 \
  --port 30010
```

> **踩雷記錄**（load 路徑解析）：
> - `--model-path /models/MiniMax-H3/FL2VA --model-variant fl2va` → sglang 會**再 append `/FL2VA`**，跑去找 `/models/MiniMax-H3/FL2VA/FL2VA`（不存在）→ `ValueError: ... does not contain model_index.json`
> - 解法：**改成掛父目錄 `/models/MiniMax-H3`**，讓 `--model-variant fl2va` 正確解析到 `/models/MiniMax-H3/FL2VA`

---

## 31.5 目前卡關：Node1 SSH 卡死（fp8 量化打滿）

### 症狀
- Node1 **alive**：ping OK、TCP port 22/8000 通
- **但 sshd 握手完成不了**：`New-SSHSession -ConnectionTimeout 120` 也失敗（socket read timeout）
- 舊 H3 **port 8000 仍正常服務**（回滾安全）
- 新 sglang **port 30010 還沒 listen**
- 判定：新的 sglang 容器正在對 **135GB 官方 BF16 做線上 fp8 量化**，把 Node1 CPU/記憶體頻寬打滿，連帶 sshd 加密握手都被餓死

### 影響
- **暫時失去對 Node1 的互動控制權**
- 無法即時抓 loadavg / 是否已 listen 30010 / 是否 OOM
- 量化 135GB 是大工程，且這台同時跑著舊 H3，可能要 **15–40+ 分鐘**甚至更久

### 風險
- 若量化/載入在 128GB 單卡上仍 OOM，容器會死，shhd 會恢復——屆時可重抓 log 修正
- 舊 H3（port 8000）全程無關，安全

---

## 31.6 已驗證 / 已確認事實（給 ChatGPT 當 ground truth）

1. **官方 FL2VA 135GB 已在 Node1**，舊 stack 一直用它跑 FP8 單卡。
2. **FP8 是 DGX Spark 單卡可行方案**（舊 stack 證明）。
3. **v0.5.18 路線**：`--model-path <FL2VA父目錄> --model-variant fl2va --quantization fp8 --quantization-ignored-layers <6層>`，port 30010。
4. **sglang 的 MiniMax-H3 pipeline** 從 `model_index.json` 的 `_minimax_h3`（`schema_version=1, partition="fl2va"`）認得 FL2VA。
5. **`--model-variant fl2va` 會對 model-path append `/FL2VA`** → 必須掛父目錄。
6. **舊 vLLM-Omni fp8 的 ignored_layers**（= launch.sh 的 6 層）：
   `video_patch_proj, audio_patch_proj, time_embedder.proj_in, time_embedder.proj_out, final_layer.video_out, final_layer.audio_out`。
7. **`pip install -e ...[diffusion]` 每次 boot 都跑** → Rust crate rebuild ~4-5min，是迭代最大時間成本（計劃內已記：可建 derived image 做一次性安裝）。

---

## 31.7 下一步（等 SSH 恢復後）

1. 抓 `cat /proc/loadavg`、`free -g`、`docker ps`、`ss -ltn | grep 30010`，判定量化是否完成 / 是否 OOM。
2. 若成功 → `curl /health` + `/v1/models`（port 30010）→ 進入 Phase E/F。
3. 若 OOM → 簽上 `--cpu-offload-components text_encoder,image_encoder,vae`（server_args 已顯示 auto memory policy 預設選了 layerwise offload text_encoder/vae，代表 sglang 已知權重太重）或 layerwise offload / 降解析度。
4. **優化**：把 `pip install -e ...[diffusion]` 從每次 boot 移除，改 bake 成 derived image，省 ~4-5min/次。
5. 成功後才切 production：停舊 H3 → 改 `runtimes.d/minimaxh3.conf` → port 8000 → `gb10-single use node1 minimaxh3`。

---

## 31.8 給 ChatGPT 的質問建議（供使用者複製）

- 「grep 到 fp8-quant.json 有 6 個 ignored_layers，launch.sh 照抄 —— sglang v0.5.18 的 `--quantization-ignored-layers` 語意是否與 vLLM 的 `--diffusion-quantization-config` 完全一致？6 個層名逐字對得上嗎？有沒有更好的層要 exempt？」
- 「sglang 對 135GB BF16 線上 fp8 量化，在 128GB 單卡上會不會因為要同時持有 BF16 來源 + fp8 產物而 OOM？正確的記憶體控制順序是 `--cpu-offload-components` / `--layerwise-offload-components` / `--dit-layerwise-offload` 哪個？」
- 「`--model-variant fl2va` 對 model-path append `/FL2VA` 是 v0.5.18 的固定行為嗎？官方 cookbook 用 `--model-path MiniMaxAI/MiniMax-H3 --model-variant fl2va` 之所以有效，是不是因為 HF repo 的父目錄真的含 `FL2VA/` 子目錄？」

