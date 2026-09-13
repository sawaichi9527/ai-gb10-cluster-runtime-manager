# DGX Spark Node1 — SGLang + MiniMax H3 NVFP4 部署任務書 v3
## Runtime Manager 整合版 / post-v0.5.18 fixed-nightly 路線

> **狀態：本文件取代 2026-09-03 v2。**
>
> v2 的 `SGLang v0.5.18 + H3 NVFP4 component override` 假設已被實機部署證明不成立。
> **不得再依 v2 的 v0.5.18 online-FP8 路徑繼續嘗試。**
>
> 本文件交付另一台 OpenCode 電腦執行，目標是在 **Node1** 上建立：
>
> **SGLang Diffusion + MiniMax H3 FL2VA pruned NVFP4 + Qwen3-VL NVFP4-AWQ + OpenAI-style `/v1/videos`**
>
> 並整合既有 `sawaichi9527/ai-gb10-cluster-runtime-manager`。
>
> 日期：2026-09-04  
> Target：Node1 / `spark-8095`  
> Control plane：Node0 / `spark-25d5`  
> Production fallback：既有 vLLM-Omni FP8 MiniMax H3，**必須完整保留**

---

# 0. Executive Decision

本輪只允許這條 candidate 路徑：

```text
DGX Spark Node1 / GB10 / 128GB UMA
        │
        ▼
Pinned SGLang fixed nightly
lmsysorg/sglang:nightly-cu134-20260903-429ac2d
        │
        ▼
SGLang native MiniMax-H3 pipeline
        │
        ├─ FL2VA pruned NVFP4 DiT       ~12.5 GB
        ├─ Qwen3-VL-32B NVFP4-AWQ      ~15.7 GB
        ├─ Video VAE FP16                ~5.2 GB
        └─ Audio VAE FP32                ~0.6 GB
        │
        ▼
OpenAI-style /v1/videos
```

## 明確禁止

```text
MiniMax official 135GB BF16
        ↓
--quantization fp8
        ↓
online FP8 conversion
```

**不得再執行。**

理由：

1. v0.5.18 不具備 v2 任務書所假設的完整 component override CLI。
2. 135GB BF16 在 GB10 128GB UMA 上做 post-load online FP8，實測造成嚴重整機資源壓力，Node1 SSH 幾乎失去互動能力。
3. 本次真正目的就是直接使用 pre-quantized components，避免載入 135GB BF16 作為正常 serving startup path。

---

# 1. Source-of-Truth 與版本鎖定

## 1.1 SGLang Docker image

固定：

```text
lmsysorg/sglang:nightly-cu134-20260903-429ac2d
```

此 tag 對應 post-v0.5.18 commit family：

```text
429ac2d
```

並已確認 Docker Hub 提供：

```text
linux/arm64
```

### 不可替換成

```text
nightly-cu134
latest
dev
main
其他 floating tag
```

本輪所有結果必須可由固定 tag 重現。

## 1.2 為什麼不用 v0.5.18

v0.5.18 實機確認不接受 v2 所寫：

```text
--component-weights-paths.transformer
--component-weights-paths.text_encoder
```

而 commit `429ac2d` 對應的 H3 文件明確宣告：

```text
--component-weights-paths.transformer
--component-weights-paths.text_encoder
--component-weights-paths.video_vae
--component-weights-paths.audio_vae
```

並支援：

```text
NVFP4 DiT
NVFP4-AWQ text encoder
```

因此本輪是：

> **固定新版功能所在 commit/image，而不是把新版 docs 套在舊 stable image。**

---

# 2. 現有 GB10 Runtime Manager 架構不可改壞

現有 repo：

```text
Node0 only:
~/ai-gb10-cluster-runtime-manager/
```

Node1 **不 clone repo**。

控制模型：

```text
OpenCode PC
     │
     ▼
Node0
~/ai-gb10-cluster-runtime-manager/
     │
     ├── bin/gb10
     │      └── TP2 cluster
     │
     └── bin/gb10-single
            ├── node0 local
            └── node1 via SSH
```

原則：

```text
Compose = deployed runtime source of truth
CLI     = orchestration/convenience layer
```

不得新增另一套與 `gb10-single` 競爭的 runtime manager。

---

# 3. 現有 Production H3 必須保留

Node1 現有：

```text
~/docker-stacks/minimax-h3/
```

backend：

```text
vLLM-Omni
+
MiniMax H3 FL2VA
+
SM121 FP8 route
```

現有 runtime registry：

```text
RUNTIME_ID=minimaxh3
GROUP=video
MODE=exclusive
PORT=8000
```

已驗證：

- `/health` PASS
- `/v1/videos/sync` PASS
- native H.264 + AAC stereo
- 768×448 / 24fps smoke PASS

本輪不得：

- 刪除舊 image
- 刪除舊 135GB official model
- 修改舊 `~/docker-stacks/minimax-h3/`
- 覆蓋舊 `.env`
- 提前修改 production `runtimes.d/minimaxh3.conf`

舊 runtime 是 rollback baseline。

---

# 4. 先處理昨晚失敗 candidate 的殘留

OpenCode **第一步不是直接重新啟動新 image**。

先從 Node0：

```bash
cd ~/ai-gb10-cluster-runtime-manager

git status
git log -5 --oneline

bin/gb10 status
bin/gb10-single status node0
bin/gb10-single status node1
```

再確認 Node1 是否已恢復 SSH。

```bash
ssh -i ~/.ssh/id_gb10_cluster eye@10.0.101.102
```

Node1：

```bash
date
hostname
uptime
cat /proc/loadavg
free -h
swapon --show
docker ps -a
ss -ltn | grep -E ':(8000|30010)\b' || true
```

## 4.1 若舊失敗 SGLang candidate 還在

查看：

```bash
docker logs --tail=500 minimax-h3-sglang-fl2va
```

保存 log：

```bash
mkdir -p ~/docker-stacks/minimax-h3-sglang/forensics

docker logs minimax-h3-sglang-fl2va \
  > ~/docker-stacks/minimax-h3-sglang/forensics/v0518-online-fp8.log 2>&1 || true
```

然後只停止 candidate stack：

```bash
cd ~/docker-stacks/minimax-h3-sglang

docker compose -f compose.sglang.yaml down || true
docker compose -f compose.yaml down || true
```

**不要停止/刪除既有 port 8000 production H3，除非後續正式進入 candidate GPU 測試階段。**

## 4.2 保存昨晚失敗設定

若存在：

```text
launch.sh
compose.sglang.yaml
compose.yaml
```

複製：

```bash
cp -a launch.sh launch.v0518-online-fp8.failed.sh 2>/dev/null || true
cp -a compose.sglang.yaml compose.v0518-online-fp8.failed.yaml 2>/dev/null || true
```

這些是 forensic evidence，不要覆蓋掉。

---

# 5. Candidate Stack

候選 stack 維持：

```text
Node1:
~/docker-stacks/minimax-h3-sglang/
```

建議結構：

```text
~/docker-stacks/minimax-h3-sglang/
├── compose.yaml
├── Dockerfile
├── .env
├── .env.example
├── launch.sh
├── models/
│   └── quantized/
│       ├── MiniMax_H3_FL2VA_pruned_nvfp4.safetensors
│       ├── text_encoders/
│       │   └── qwen3vl_32b_minimax_h3_nvfp4_awq.safetensors
│       └── vae/
│           ├── minimax_h3_video_vae_fp16.safetensors
│           └── minimax_h3_audio_vae_fp32.safetensors
├── input/
├── output/
├── logs/
└── forensics/
```

可沿用已下載的檔案，不要重新下載已有完整檔案。

---

# 6. Quantized Weights

來源：

```text
Abiray/Minimax-H3-nvfp4-INT4-INT8-Convrot
```

本輪固定：

## 6.1 DiT

```text
MiniMax_H3_FL2VA_pruned_nvfp4.safetensors
~12.5 GB
```

## 6.2 Text Encoder

```text
text_encoders/qwen3vl_32b_minimax_h3_nvfp4_awq.safetensors
~15.7 GB
```

## 6.3 Video VAE

```text
vae/minimax_h3_video_vae_fp16.safetensors
~5.21 GB
```

## 6.4 Audio VAE

```text
vae/minimax_h3_audio_vae_fp32.safetensors
~605 MB
```

總靜態檔案約：

```text
~34 GB
```

注意：

> 34GB 是 checkpoint storage，不是 runtime peak。

---

# 7. 必做的 Image Preflight — Failure Gate

這是 v3 最重要的新規則。

先 pull：

```bash
docker pull lmsysorg/sglang:nightly-cu134-20260903-429ac2d
```

確認：

```bash
docker image inspect \
  lmsysorg/sglang:nightly-cu134-20260903-429ac2d \
  --format 'arch={{.Architecture}} os={{.Os}} id={{.Id}}'
```

必須看到：

```text
arch=arm64
os=linux
```

保存完整 digest / image ID：

```bash
docker image inspect \
  lmsysorg/sglang:nightly-cu134-20260903-429ac2d \
  > ~/docker-stacks/minimax-h3-sglang/logs/image-inspect-429ac2d.json
```

## 7.1 CLI Capability Gate

進 image：

```bash
docker run --rm --gpus all \
  lmsysorg/sglang:nightly-cu134-20260903-429ac2d \
  bash -lc '
    set -e
    uname -m
    python - <<PY
import torch
import sglang
print("torch", torch.__version__)
print("cuda", torch.version.cuda)
print("cuda_available", torch.cuda.is_available())
print("device", torch.cuda.get_device_name(0))
print("sglang", getattr(sglang, "__version__", "unknown"))
PY

    sglang serve --help > /tmp/serve-help.txt 2>&1 || true

    echo "=== required H3 component flags ==="
    grep -F -- "--component-weights-paths.transformer" /tmp/serve-help.txt
    grep -F -- "--component-weights-paths.text_encoder" /tmp/serve-help.txt
    grep -F -- "--component-weights-paths.video_vae" /tmp/serve-help.txt
    grep -F -- "--component-weights-paths.audio_vae" /tmp/serve-help.txt
  '
```

### Gate

四個 grep 必須全部成功。

如果任何一個不存在：

```text
STOP
```

不得：

- 改用 `--quantization fp8`
- 改回 v0.5.18
- 自行猜 CLI syntax
- 重組 135GB BF16
- 直接開始長時間 loading

必須回報 ChatGPT / operator。

---

# 8. Diffusion Extras — Bake Once，不要每次 boot 安裝

昨晚已證明：

```text
pip install -e "/sgl-workspace/sglang/python[diffusion]"
```

若每次 container boot 都執行，會帶來數分鐘 rebuild / startup noise。

因此本輪直接做 **thin derived image**。

Dockerfile：

```dockerfile
ARG SGLANG_BASE=lmsysorg/sglang:nightly-cu134-20260903-429ac2d
FROM ${SGLANG_BASE}

RUN python -m pip install -e "/sgl-workspace/sglang/python[diffusion]"
```

禁止：

```text
pip install --upgrade torch
pip install --upgrade triton
pip replace CUDA
git clone another SGLang
git checkout main
source patch
```

build：

```bash
cd ~/docker-stacks/minimax-h3-sglang

docker build \
  --build-arg SGLANG_BASE=lmsysorg/sglang:nightly-cu134-20260903-429ac2d \
  -t minimax-h3-sglang:429ac2d-nvfp4 .
```

完成後記錄：

```bash
docker image inspect minimax-h3-sglang:429ac2d-nvfp4
```

---

# 9. Model Path 規則 — 保留昨晚已驗證結論

Node1 已有完整 official model root：

```text
/home/eye/docker-stacks/minimax-h3/models/MiniMax-H3/
```

其中含：

```text
FL2VA/
```

SGLang H3 的正確語意：

```text
--model-path <ROOT>
--model-variant fl2va
```

所以：

```text
CORRECT:
--model-path /models/MiniMax-H3
--model-variant fl2va
```

不得：

```text
WRONG:
--model-path /models/MiniMax-H3/FL2VA
--model-variant fl2va
```

否則會再次解析到：

```text
.../FL2VA/FL2VA
```

本輪 mount：

```text
/home/eye/docker-stacks/minimax-h3/models/MiniMax-H3
→
/models/MiniMax-H3
```

official model root 主要提供：

- model_index/config
- processor/tokenizer/config metadata

真正的大型 component weights 必須被 NVFP4/quantized override 取代。

---

# 10. 正確的 H3 NVFP4 Serve Command

`launch.sh` baseline：

```bash
#!/usr/bin/env bash
set -Eeuo pipefail

exec sglang serve \
  --model-type diffusion \
  --model-path /models/MiniMax-H3 \
  --model-variant fl2va \
  --component-weights-paths.transformer \
    /models/quantized/MiniMax_H3_FL2VA_pruned_nvfp4.safetensors \
  --component-weights-paths.text_encoder \
    /models/quantized/text_encoders/qwen3vl_32b_minimax_h3_nvfp4_awq.safetensors \
  --component-weights-paths.video_vae \
    /models/quantized/vae/minimax_h3_video_vae_fp16.safetensors \
  --component-weights-paths.audio_vae \
    /models/quantized/vae/minimax_h3_audio_vae_fp32.safetensors \
  --encoder-parallel auto \
  --performance-mode speed \
  --enable-torch-compile false \
  --host 127.0.0.1 \
  --port 30010
```

## 10.1 絕對不要加入

```text
--quantization fp8
--quantization nvfp4
--quantization-ignored-layers ...
```

目前 pre-quantized files 是 self-describing。

新版 H3 contract 明確要求：

> pre-quantized component override 不與 online quantization 混用。

---

# 11. Attention Backend

第一輪：

> **不要手動指定 Sol-Attn、SageAttention、Cache-DiT。**

也暫時不要為了速度修改 attention backend。

先讓 fixed nightly 的平台預設執行。

記錄 startup log 中實際選用的 backend。

只有 baseline PASS 後，才另開 optimization phase。

---

# 12. Candidate API Security

第一輪 candidate：

```text
--host 127.0.0.1
--port 30010
```

理由：

- 尚未確認這個 fixed nightly 的 diffusion server 是否提供可驗證的 native API-key enforcement。
- candidate 不需要直接暴露 LAN。

Node0 可透過 SSH 到 Node1 執行 curl。

## 12.1 API-key Preflight

另外執行：

```bash
docker run --rm \
  minimax-h3-sglang:429ac2d-nvfp4 \
  bash -lc '
    sglang serve --help 2>&1 |
      grep -E -- "--api-key|api.key|authentication" || true
  '
```

若存在 native `--api-key`：

- 驗證「無 key = 401/403」
- 驗證「正確 key = PASS」
- production 可考慮 `0.0.0.0:8000`

若不存在或 enforcement 無法證明：

> production cutover 暫停。

後續只能：

1. 保持 loopback + SSH tunnel，或
2. 加 reverse proxy / gateway 做 Bearer authentication。

不得把未驗證 auth 的 `0.0.0.0:8000` 視為完成。

---

# 13. Compose Baseline

`compose.yaml` 建議：

```yaml
services:
  minimax-h3-sglang:
    image: minimax-h3-sglang:429ac2d-nvfp4
    container_name: minimax-h3-sglang-fl2va
    network_mode: host
    ipc: host
    shm_size: "32gb"
    gpus: all

    volumes:
      - ./launch.sh:/launch.sh:ro
      - /home/eye/docker-stacks/minimax-h3/models/MiniMax-H3:/models/MiniMax-H3:ro
      - ./models/quantized:/models/quantized:ro
      - ./input:/data/minimax-h3:ro
      - ./output:/output
      - ${HF_CACHE_DIR}:/root/.cache/huggingface

    environment:
      PYTORCH_CUDA_ALLOC_CONF: expandable_segments:True

    entrypoint: ["/bin/bash"]
    command: ["/launch.sh"]

    restart: "no"
```

第一輪 candidate 使用：

```text
restart: "no"
```

避免 loader crash/OOM 後無限重啟，再次把 Node1 壓死。

---

# 14. 在真正啟動前：Memory / Process Preflight

在 Node0：

```bash
cd ~/ai-gb10-cluster-runtime-manager

bin/gb10 status
bin/gb10-single status node1
```

正式 candidate GPU test 前：

```bash
bin/gb10-single free node1
```

確認 Node1：

```bash
docker ps
free -h
swapon --show
ps aux --sort=-%mem | head -20
```

要求：

- 沒有 vLLM/H3/ComfyUI heavy runtime
- 無殘留 python/sglang loading process
- MemAvailable 回到接近 idle
- swap 沒有持續快速增加

---

# 15. Candidate Start — 不准長時間盲等

Node1：

```bash
cd ~/docker-stacks/minimax-h3-sglang

docker compose config --quiet

docker compose up -d
```

立即：

```bash
docker logs -f --tail=200 minimax-h3-sglang-fl2va
```

另一個 session：

```bash
watch -n 2 '
  date
  cat /proc/loadavg
  grep -E "MemAvailable|SwapFree" /proc/meminfo
  docker ps --format "table {{.Names}}\t{{.Status}}"
'
```

## 15.1 重要判定

新版 NVFP4 component override 正常時：

> 不應再出現「必須把完整 135GB BF16 transformer 載入並做 online FP8 conversion」的 startup 行為。

若 log 明確顯示正在：

```text
online fp8 quantization
loading full BF16 transformer shards as active serving weights
```

立即停止 candidate。

這代表 component override 沒有生效。

---

# 16. Startup Acceptance Gate

candidate 必須做到：

```bash
curl -fsS http://127.0.0.1:30010/health
```

以及：

```bash
curl -fsS http://127.0.0.1:30010/v1/models
```

記錄：

```text
startup elapsed
MemAvailable before
minimum MemAvailable during load
Swap used before/peak
container RSS
selected attention backend
model/component loader messages
```

## 16.1 Loader evidence 必須保存

log 中必須能證明：

```text
transformer = NVFP4 override
text_encoder = NVFP4-AWQ override
video_vae = provided FP16 file
audio_vae = provided FP32 file
```

若無法從 log 確認，應從 `/server_info`、model metadata 或 SGLang debug information 補證據。

不能只因 `/health=200` 就假設量化檔真的被使用。

---

# 17. 最小 API Smoke Test

先只做：

```text
T2VA
5 sec
768 short-edge class
24 fps
50 steps
seed fixed
concurrency 1
```

raw request：

```bash
video_id=$(
  curl -sS -X POST http://127.0.0.1:30010/v1/videos \
    -H "Content-Type: application/json" \
    -d '{
      "model": "MiniMaxAI/MiniMax-H3",
      "prompt": "A cinematic futuristic laboratory, subtle camera movement, synchronized ambient machine sounds.",
      "seconds": 5,
      "task": "t2va",
      "conditions": [],
      "target": {
        "short_edge": 768,
        "aspect_ratio": "16:9",
        "duration_seconds": 5.0
      },
      "num_outputs_per_prompt": 1,
      "num_inference_steps": 50,
      "flow_shift": 12.0,
      "audio_flow_shift": 3.0,
      "seed": 1101
    }' |
  jq -r '.id'
)

echo "$video_id"
```

poll：

```bash
while true; do
  status=$(
    curl -sS \
      "http://127.0.0.1:30010/v1/videos/${video_id}" |
    jq -r '.status'
  )

  echo "$(date -Is) $status"

  [ "$status" = "completed" ] && break
  [ "$status" = "failed" ] && exit 1

  sleep 2
done
```

download：

```bash
curl -sS -L \
  "http://127.0.0.1:30010/v1/videos/${video_id}/content" \
  -o output/smoke-t2va-5s.mp4
```

---

# 18. Output Validation

```bash
ffprobe -hide_banner output/smoke-t2va-5s.mp4
```

至少確認：

```text
Video:
H.264
24 fps

Audio:
AAC
32 kHz
stereo
```

另外：

```bash
sha256sum output/smoke-t2va-5s.mp4
stat -c '%s bytes' output/smoke-t2va-5s.mp4
```

---

# 19. FL2VA Smoke

T2VA PASS 後才做 FL2VA。

放入：

```text
input/first-frame.png
```

request condition：

```json
{
  "type": "image",
  "uri": "file:///data/minimax-h3/first-frame.png",
  "role": "keyframe",
  "frame_index": 0
}
```

要求：

- first frame condition 真正生效
- video PASS
- audio PASS
- full decode PASS

---

# 20. UMA 監控

DGX Spark 不只看 `nvidia-smi`。

每個 case：

```bash
free -h

grep -E \
  'MemTotal|MemAvailable|SwapTotal|SwapFree' \
  /proc/meminfo

swapon --show

docker stats --no-stream
```

建議：

```bash
mkdir -p logs

(
while true; do
  printf '%s ' "$(date -Is)"
  awk '
    /MemAvailable|SwapFree/ {
      printf "%s=%s ",$1,$2
    }
    END {print ""}
  ' /proc/meminfo
  sleep 2
done
) >> logs/memory.log &
echo $! > logs/memory.pid
```

測完：

```bash
kill "$(cat logs/memory.pid)" || true
```

---

# 21. Capacity Test Matrix

目標：

> **單台 Spark 在不 OOM 前提下最大化 resolution × duration。**

固定：

```text
concurrency = 1
prompt      = same
seed        = same
steps       = 50
audio       = ON
```

建議：

| Stage | Target | Duration | Result |
|---|---|---:|---|
| Baseline | short_edge 768 / 16:9 | 5s | |
| A | short_edge 768 / 16:9 | 8s | |
| B | short_edge 768 / 16:9 | 10s | |
| C | short_edge 768 / 16:9 | 12s | |
| D | short_edge 768 / 16:9 | 15s | |

不要硬編假想 `1344×768` 如果 API 最終是由 H3 target resolver 根據 short-edge/aspect ratio 對齊 canvas。

每次實際產出的 width/height/frame count：

```bash
ffprobe
```

實測記錄。

---

# 22. OOM Rule

第一次 OOM：

1. 停止往更高 duration。
2. 等待 container/process memory 完整釋放。
3. 確認 swap / MemAvailable。
4. 重啟 candidate。
5. 回退前一個成功 case。
6. 重跑至少 2 次。

若 15s OOM：

> 以 duration=15s 固定，再降低 short-edge / geometry。

不得在 OOM 後直接連續送下一 request。

---

# 23. 與既有 vLLM-Omni FP8 Comparison

至少比較：

```text
old vLLM FP8
vs
new SGLang NVFP4
```

固定：

- prompt
- duration
- closest geometry
- step count
- seed where supported

記錄：

| Runtime | Duration | Geometry | Steps | Startup | Gen time | Min MemAvailable | Swap peak | Result |
|---|---:|---|---:|---:|---:|---:|---:|---|
| vLLM FP8 | | | | | | | | |
| SGLang NVFP4 | | | | | | | | |

品質觀察：

- prompt adherence
- subject consistency
- temporal stability
- motion
- artifacts
- audio sync
- audio quality

pruned NVFP4 不要求與 FP8 bit-exact。

---

# 24. Optimization Phase — Baseline 成功前禁止進入

只有：

```text
T2VA PASS
FL2VA PASS
repeat PASS
capacity baseline PASS
```

後才可以獨立研究：

- Sol-Attn
- SageAttention
- Cache-DiT
- FastH3
- torch.compile
- lower inference steps
- alternative DiT formats

每一項必須一次只改一個變數。

本任務 **不要求** 完成 optimization phase。

---

# 25. Production Cutover Gate

只有以下全部成立：

- fixed nightly image preflight PASS
- 4 個 component override CLI PASS
- thin derived image build PASS
- NVFP4 loader evidence PASS
- no online BF16→FP8 conversion
- `/health` PASS
- `/v1/models` PASS
- T2VA PASS
- FL2VA PASS
- native audio PASS
- restart PASS
- capacity advantage 有實際數據
- access control 有 production 解法
- rollback drill ready

才允許切 production。

---

# 26. Production Cutover

Production runtime ID 維持：

```text
minimaxh3
```

不新增：

```text
minimaxh3-sglang
```

作為永久 operator-facing runtime ID。

更新 Node0：

```text
runtimes.d/minimaxh3.conf
```

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

`PROJECT/SERVICE/CONTAINER` 必須與舊 vLLM implementation 不同。

---

# 27. Production API Port

candidate：

```text
127.0.0.1:30010
```

production：

```text
:8000
```

只有 API auth/access-control 驗證後才能：

```text
0.0.0.0:8000
```

若無 native auth，先不要 expose。

---

# 28. Runtime Manager Production Test

Node0：

```bash
cd ~/ai-gb10-cluster-runtime-manager

bin/gb10-single use node1 minimaxh3
```

確認：

1. active TP2 正確 teardown。
2. Node1 其他 exclusive runtime 正確停止。
3. SGLang compose 正確啟動。
4. `wait_ready` 到 READY。
5. `status node1` 正確。
6. `logs node1 minimaxh3` 可正常追 log。
7. client endpoint 可用。

---

# 29. Rollback

舊 stack：

```text
~/docker-stacks/minimax-h3/
```

舊 image：

```text
minimax-h3-dgx-spark:sm121-fp8
```

舊 official model：

```text
~/docker-stacks/minimax-h3/models/MiniMax-H3/
```

全部保留。

Production pointer cutover 最好獨立一個 git commit。

rollback：

```text
git revert <cutover-commit>
        ↓
restore old runtimes.d/minimaxh3.conf
        ↓
gb10-single use node1 minimaxh3
        ↓
/health
        ↓
old smoke test
```

---

# 30. SGLang Upgrade Policy

本次若成功：

```text
429ac2d fixed nightly
```

是 **candidate validation baseline**，不是永久版本策略。

如果後續：

```text
v0.5.19
```

或更新 stable release 已包含相同 H3 component override path：

優先重新驗證 stable：

```text
same models
same compose
same API test
same capacity matrix
```

PASS 後才把 production 從 nightly 移到 stable。

每次記錄：

```text
image tag
full image digest
SGLang git commit
torch
CUDA
Python
quantized model SHA256/HF revision
compose SHA256
launch.sh SHA256
```

---

# 31. 昨晚失敗得到的永久規則

以下列為後續 maintainer 必知：

### Rule 1
**不要把 current/main docs 的 CLI 功能直接套用到舊 stable tag。**

每個關鍵功能都要：

```text
docs commit
↕
code commit
↕
docker tag
```

對得上。

### Rule 2
GB10 的 128GB 是 unified memory。

不要把：

```text
host RAM
+
GPU VRAM
```

當成兩個獨立 128GB pool。

### Rule 3
135GB BF16 online FP8 startup 不是本專案 capacity solution。

### Rule 4
`--model-variant fl2va` 使用 root model path，由 SGLang 自己解析 `FL2VA/`。

### Rule 5
pre-quantized NVFP4 component：

```text
不要再加 --quantization
```

### Rule 6
candidate crash/OOM 時：

```text
restart: no
```

先保護 Node1 可管理性。

---

# 32. OpenCode 必須回傳的證據

## A. Preflight

```text
image arch
image ID/digest
sglang version
torch
CUDA
4 x component-weights-paths flags
```

## B. Loader

證明：

```text
DiT NVFP4 used
Qwen NVFP4-AWQ used
Video VAE override used
Audio VAE override used
NO online FP8 conversion
```

## C. Runtime

```text
startup duration
/health
/v1/models
docker ps
memory baseline/peak
swap
```

## D. Video

至少：

```text
T2VA 5 sec
FL2VA 5 sec
highest safe duration @ 768 short edge class
```

附：

```text
ffprobe
elapsed
file size
sha256
```

## E. Git

若 repo 有修改：

```bash
git status
git log -5 --oneline
git diff <before>..<after>
```

不得提交 secret。

---

# 33. Definition of Done

成功標準：

```text
Node1
  ↓
fixed SGLang 429ac2d image
  ↓
MiniMax H3 native pipeline
  ↓
FL2VA pruned NVFP4 DiT
  ↓
Qwen3-VL NVFP4-AWQ
  ↓
OpenAI-style /v1/videos
  ↓
video + native stereo audio
  ↓
capacity matrix completed
  ↓
runtime-manager production integration
  ↓
vLLM FP8 fallback retained
```

如果只做到：

```text
container starts
```

不算完成。

如果又回到：

```text
135GB BF16 → online FP8
```

視為偏離任務，不可繼續。

---

# 34. 執行順序摘要

```text
01. SSH Node0
02. Read repo / AGENTS.md / current git HEAD
03. Inspect Node1 recovery state
04. Preserve failed-v0.5.18 logs/config
05. Stop failed candidate if still active
06. Verify old production fallback is intact
07. Pull fixed nightly 429ac2d
08. Verify ARM64
09. REQUIRED CLI FLAG GATE
10. Build thin diffusion-derived image
11. Verify existing quantized files / hashes
12. Prepare launch.sh with four component overrides
13. Candidate binds 127.0.0.1:30010
14. gb10-single free node1
15. Start candidate
16. Monitor UMA/load/swap from second session
17. Confirm no online FP8 conversion
18. /health
19. /v1/models
20. T2VA 5s
21. ffprobe
22. FL2VA 5s
23. capacity 5→8→10→12→15s
24. compare old vLLM FP8
25. verify API auth/access control
26. production cutover only if all gates pass
27. gb10-single production test
28. rollback drill
29. commit docs/conf
30. return evidence
```

---

# 35. 必讀來源 / Version Contract

本次實作不可只看 floating `main`。

固定對照：

### SGLang image

```text
lmsysorg/sglang:nightly-cu134-20260903-429ac2d
```

### SGLang source/docs commit

```text
429ac2d82ccc931712a866e6e0991cf0413e82d4
```

### H3 docs

```text
docs/cookbook/diffusion/MiniMax/MiniMax-H3.mdx
@ 429ac2d82ccc931712a866e6e0991cf0413e82d4
```

### Quantized weights

```text
Abiray/Minimax-H3-nvfp4-INT4-INT8-Convrot
```

### Existing runtime manager

```text
sawaichi9527/ai-gb10-cluster-runtime-manager
```

開始修改前必讀：

```text
README.md
AGENTS.md
bin/gb10-single
runtimes.d/minimaxh3.conf
docs/MINIMAX_H3_DEPLOYMENT_2026-09-01.md
```

任何本文件與 repo **較新的 factual state** 衝突：

> 停止修改 production，先回報衝突與證據。

---

# 36. 給 OpenCode 的一句話任務

> **不要再救 v0.5.18 online FP8。先證明固定 SGLang `429ac2d` ARM64 image 能直接載入現有 H3 FL2VA pruned NVFP4 + Qwen NVFP4-AWQ 四個 pre-quantized components，並在 Node1 以 `/v1/videos` 產生含原生音訊的影片；成功後才做 capacity test 與 runtime-manager cutover。**

---

# 37. v3.09 CLI Flag Gate 執行報告（STOP — 前提不存在）

> 2026-09-04，Operator 未決策前不得修改 production；本節為 v3.9 硬性 gate 之失敗證據（append-only）。

## 驗證目標

v3 任務書第 3.09 條假設 pinned 鏡像 `lmsysorg/sglang:nightly-cu134-20260903-429ac2d` 支援 4 個 `--component-weights-paths.transformer|text_encoder|video_vae|audio_vae` overrides，可讓既有 4 個 pre-quantized components(NVFP4 DiT / NVFP4-AWQ encoder / FP16 video VAE / FP32 audio VAE, flat layout ~34GB) 直接載入。

## 驗證方式與結果（全部在 Node1，透過 gb102 ssh-mcp `docker run --rm` 執行）

| 檢查 | 命令（容器內） | 結果 |
|---|---|---|
| 鏡像與版本 | `sglang version` | `0.0.0.dev1+g429ac2d82.d20260903` / git rev `429ac2d`（與 pinned 一致）|
| Diffusion help 是否存在 | `sglang serve --model-type diffusion --help` | 存在（811 lines / 51KB）|
| 4 flags 是否存在 | `grep -cF -- --component-weights-paths` | **0**（不存在）|
| `weights-paths` / `component_weights` | `grep -nE` | 空（不存在）|
| MiniMax H3 是否內建 | help 內 `--minimax-h3-adaln-online` / `--pipeline` / `--load-diffusion-decoder` | 是（H3 diffusion backend 存在）|

## 關鍵分歧：此鏡像實際的權重載入機制 ≠ v3 任務書假設

實際 diffusion help 提供的相關 flags：

- `--transformer-weights-path TRANSFORMER_WEIGHTS_PATH`（pre-quantized DiT 單一檔案路徑或 HF repo；用於 Nunchaku SVDQuant 與 quantized single-file checkpoints）
- `--quantization QUANTIZATION`（transformer 量化方法；可從 BF16/FP16 線上量化，或要求 pre-quantized checkpoint）
- `--quantization-precision {int4,nvfp4}`（量化精度，含 nvfp4）
- `--quantization-ignored-layers`、`--quantization-rank`、`--quantization-act-unsigned`
- `--dit-config.quant-config`、`--model-variant`、`--model-subfolder`
- `--text-encoder-precisions`、`--vae-precision`、`--vae-decode-precision`、`--vae-cpu-offload`、`--image-encoder-cpu-offload`、`--text-encoder-cpu-offload`
- `--direct-gpu-weight-loading`（載入完整未量化 DiT→135GB，v3 明文禁止）
- `--minimax-h3-adaln-online`（v3 明文禁止走此路徑）
- `--layerwise-*` offload / `--component-residency` / `--cpu-offload-components` / `--component-attention-backends`

**結論：`--component-weights-paths.<component>`（4 個點分 flag）在 pinned `429ac2d` 的 CLI 中不存在。** v3 任務書 3.09 之前的假設與此鏡像實際 CLI 不合。這是「本文件與較新 factual state 衝突」，依第 36 節衝突規則應 STOP 回報。

## 需要 Operator 決策的問題

1. **是否以 `--transformer-weights-path` + `--quantization-precision nvfp4`（及其他 encoder/vae flag）重建 launch.sh？** 這是此鏡像支援的機制；但需確認是否能一對一載入 4 個既有 pre-quantized flat 檔（尤其第 4 個 audio VAE FP32 與 `--transformer-weights-path` 單檔模型在語意上是否涵蓋 encoder+vae）。
2. **是否改用／重驗其他 nightly 或 fork**（例如確認是否存在更新 commit 補回 `--component-weights-paths.*`）？以符合 v3 原本語意。
3. **是否接受此鏡像語意改寫 v3 的 component 對應表**（transformer→DiT nvfp4、text_encoder→qwen nvfp4_awq、video_vae→fp16、audio_vae→fp32）後再往下走。

未決策前不啟動 candidate、不改 production（舊 vLLM-Omni :8000 維持 Up）。

---

---

# 37.1 v3.09 Gate 重驗 — 解析為 False Alarm，gate PASS

> 2026-09-04，依 Operator 指示「先在容器內 cross-check docs/source，再回報，之後才寫 launch.sh」完成重驗。

## 根因

`--component-weights-paths.<component>` 是 **dynamic component map flag**，並非以 `argparse.add_argument` 註冊，因此 **`sglang serve --help`（含 `--model-type diffusion --help`）永遠不會列出它們**。這些 dotted flags 是在 `ServerArgs.from_cli_args()` 中，於 argparse 之後、從 raw `unknown_args` 以字首 `--component-weights-paths.`（與 `--component_weights_paths.`）**預先抽取**注入 `component_weights_paths` dict。故第 37 節「4 flags 不存在」係 **False Alarm（測錯 surface）**。

## Source 證據（容器內 `/sgl-workspace/sglang/python/sglang/multimodal_gen/`）

- `runtime/server_args/server_args.py`
  - `component_weights_paths: dict[str,str]` (L329)
  - component 合法 key map 含 `transformer`、`video_vae`、`audio_vae` (L496-499)，text encoder 由 `is_text_encoder_component_name` 認可
  - `_extract_component_weights_paths()` (L2969) 字首 `--component-weights-paths.`，alias_suffix `-weights-path`
  - `from_cli_args()` 依序抽取：`component-quantizations.`、`component-precisions.`、`component-direct-gpu-weight-loading.`、`component-quantization-ignored-layers.`、`component-weights-paths.`、`component-paths.`、`component-attention-backends.`，均需解析成功否則 `unrecognized arguments` (SystemExit)
- 另有 companion flags：`--component-paths.`、`--component-quantizations.`、`--component-precisions.`、`--component-attention-backends.` 等
- `runtime/loader/component_loaders/`：`component_loader.py`、`transformer_loader.py` 等實作載入
- 大量 unit tests（`test_server_args.py` 明確測 `--component-weights-paths.text_encoder`）

## 權威 Doc 證據（`docs/cookbook/diffusion/MiniMax/MiniMax-H3.mdx` @429ac2d）

- L75-101 component table：DiT NVFP4 → `--component-weights-paths.transformer`；text encoder NVFP4-AWQ → `--component-weights-paths.text_encoder`；video/audio VAE → `--component-weights-paths.video_vae|audio_vae`
- L103-106：**registered H3 component names = `transformer`, `text_encoder`, `video_vae`, `audio_vae`**（即 v3 假設的 4 個）
- L107-108：`--transformer-weights-path` 與 `--text-encoder-path` 為**短別名**
- L111-112：plain video/audio VAE safetensors 可用 `--component-weights-paths.video_vae|audio_vae`；SGLang 目前無原生 quantized H3 VAE 格式（FP16/FP32 即可）
- L115：**pre-quantized 檔 self-describing，勿再搭配 `--quantization` / `--component-quantizations.*`**

## Gate 結論

- **4 flags 存在、已註冊、會被解析、官方 doc 明文記載** → **v3.09 gate PASS**。
- 修正第 37 節之「不存在」結論為誤判。

## 尚未驗證／待決事項（進 v3.10/3.12 前）

1. **compute capability ≥ 10.0**：NVFP4 execution 需 NVIDIA CC 10.0+（DGX Spark GB10 / Blackwell = 10.0，應 OK，但須在 Node1 確認 `nvidia-smi` CC）。
2. **base model path**：mdx 範例 `--model-path MiniMaxAI/MiniMax-H3 --model-variant fl2va`（HF repo）再 override 4 components。我們用**本機 flat quantized 檔**，需確認 base config/tokenizer 來源（本機已有舊 vLLM-Omni 用之 BF16 FL2VA 於 `/home/eye/docker-stacks/minimax-h3/models/MiniMax-H3/FL2VA`，勿刪；可作為 base path 或另以 HF repo 為 base）。
3. **4 檔語意對應**：`transformer`→`MiniMax_H3_FL2VA_pruned_nvfp4.safetensors`、`text_encoder`→`qwen3vl_32b_minimax_h3_nvfp4_awq.safetensors`、`video_vae`→`minimax_h3_video_vae_fp16.safetensors`、`audio_vae`→`minimax_h3_audio_vae_fp32.safetensors`（flat layout，實際路徑以 Node1 探勘為準）。

## 下一步（待 Operator 確認後執行）

- v3.10 bake derived image（`[diffusion]` extra + 一次性 pip install，避免每次 boot 重編 Rust crate）。
- v3.12 依上述 4-component 對應 + `--model-variant fl2va` 寫 launch.sh（不帶 `--quantization`）。
- v3.14-15 preflight（free Node1）→ 啟動 candidate 監聽 127.0.0.1:30010。

---

## § 停止實驗＋還原 production（2026-09-04，Stop-loss 收尾）

### 決策（user 明示）
- **停止 SGLang/NVFP4 整合實驗，不再修 audio_vae**（bliger 移往 `audio_vae`：`ComponentCheckpointUnsupportedError: 'audio_vae' uses a custom Diffusers class that cannot consume a weights-only override`，vae_loader.py:512）。實驗**封存，不刪除**，供日後 retry。
- 透過既有 **Runtime Manager** 還原並啟動既有 production MiniMax-H3（vLLM-Omni FP8, `minimaxh3`）。

### 執行紀錄（Node0=gb101/.215 control plane；Node1=gb102/.216）
- **封存**（Node1 `~/docker-stacks/minimax-h3-sglang/archive_sglang_experiment_2026-09-04/`）：
  `compose_candidate.yaml`、`launch.sh`、`SHA256SUMS.txt`、`checksum_verify.txt`、`startup_logs_2026-09-04.txt`（35,774B）、`monitor.log`、`quantized_dir_listing.txt`、`FAILURE_ANALYSIS.md`（root cause＋retry path）。
- **cleanup**：`docker rm minimax-h3-sglang-fl2va`；GPU 回歸 0%（DiffusionWorker 已移除）；**保留** sanitized `…_nvfp4.sglang.safetensors`（12,528,636,800B）＋ upstream（12,528,636,865B）＋污染 image `minimax-h3-sglang:429ac2d-nvfp4` 供 retry。
- **production restore（透過 RTM，未手發 Docker command）**：Node0 `ai-gb10-cluster-runtime-manager` → `./bin/gb10-single use node1 minimaxh3`。
  - `runtimes.d/minimaxh3.conf`（STACK_DIR=`~/docker-stacks/minimax-h3`、CONTAINER=`minimax-h3-fl2va`、PROJECT=`minimax-h3-dgx-spark`、HEALTH=`http://127.0.0.1:8000/health`、TIMEOUT=2400）— **production 從未 cut over 到 SGLang**。image `minimax-h3-dgx-spark:sm121-fp8`（vLLM-Omni FP8）。
  - 冷啟動：container Up → VAE 13 shards 載入 155.1s → encoder 50 layers → APIServer routes 註冊 → `/health` 200 OK（body 空＝healthy）。
  - RTM `status node1`：`minimaxh3 = running / READY`。

### 驗證（production smoke PASS）
- `/v1/videos/sync` **multipart form**（非 JSON body — 該 endpoint 走 `_parse_video_form`）：
  `model=/models/MiniMax-H3/FL2VA`、`prompt=a red cube rotating slowly on a white background`、`size=768x448`、`num_inference_steps=20`、`fps=24`、`seconds=2`、`seed=42`、`generate_sound=true`，`Authorization: Bearer $VLLM_API_KEY`（container env）。
- 結果：**HTTP 200 in 131.51s**（對上驗證 ~132s）、471,242 B MP4。
  - ffprobe：`h264` video **768×448**、`aac` audio、`mov,mp4,m4a,3gp,3g2,mj2`、duration 2.357s。
  - sha256 `818e1ab8…c69417`。**H.264 + AAC PASS**。
- 教訓：`/v1/videos/sync` 收 **form** 不收 JSON；JSON body 會以 `body.prompt Field required / input None` 回 400。MCP wrapper 會剝除命令列雙引號 → 一律以 base64 寫遠端檔再 `-F`/`-d @file` 傳。

### 收尾狀態
- Node1：production `minimax-h3-fl2va` Up、port 8000 listening、SGLang 實驗無殘留 container。
- Node0：RTM `minimaxh3 running/READY`。
