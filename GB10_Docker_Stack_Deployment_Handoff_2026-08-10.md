# DGX Spark GB10 本地 AI 部署狀態交接（最新版）

> 更新日期：2026-08-10  
> 主機：NVIDIA DGX Spark / GB10  
> 主機名稱：`spark-25d5`  
> 使用者：`eye`  
> 區網 IP：`192.168.23.215`  
> 作業系統：Ubuntu 24.04 ARM64  
> NVIDIA DGX Spark 系統版本：`7.5.0`  
> Kernel：`6.17.0-1029-nvidia`  
> 用途：本地 vLLM LLM 推理 + ComfyUI 生圖，以 Docker Stack 分離管理  
> 文件定位：提供後續 AI／維護人員進行 Docker image 升級、模型切換、故障排查、效能觀察與部署變更時的主要參考

---

# 1. 本文件目的

本文件整合：

1. 2026-07-31 既有 GB10 Docker / ComfyUI deployment handover。
2. 2026-08-10 實際完成的 AEON vLLM `v0.25.1 → v0.26.0` 升級。
3. 目前 27B / 35B-A3B 的實際 Docker Compose 架構。
4. `gb10` Runtime Manager 與真正 Docker Compose deployment 的分層關係。
5. 模型與 Docker image 的解耦方式。
6. vLLM image 升級、驗證、回滾、cache、冷啟動與 swap 排查經驗。

核心原則：

```text
gb10 Runtime Manager
= 操作便利層 / runtime switching layer

Docker Compose
= 真正 deployment source of truth

Host bind-mounted models/cache
= 持久化資料層

Docker image
= 可替換 runtime layer
```

因此：

```text
升級 Docker image
≠ 重新下載模型
≠ 修改模型檔
≠ 修改 gb10 主程式
```

只要 `/model`、`/drafter`、cache 都由 Host bind mount，刪除／重建 container 不會刪除模型。

---

# 2. 整體目錄架構

```text
/home/eye/
├─ bin/
│  └─ gb10
│     └─ command entry / symbolic link
│        → /home/eye/docker-stacks/ai-runtime-manager/gb10
│
└─ docker-stacks/
   ├─ ai-runtime-manager/
   │  ├─ gb10
   │  ├─ runtimes.d/
   │  │  ├─ aeon-qwen36-27b.conf
   │  │  ├─ aeon-qwen36-35b-a3b.conf
   │  │  ├─ comfyui-work.conf
   │  │  └─ comfyui-personal.conf
   │  └─ state/
   │
   ├─ aeon-vllm/
   │  ├─ .env
   │  ├─ docker-compose.yml
   │  ├─ docker-compose.27b.yml
   │  ├─ docker-compose.35b.yml
   │  ├─ models/
   │  ├─ cache/
   │  └─ logs/
   │
   └─ comfyui-aeon/
      ├─ docker-compose.yml
      ├─ docker-compose.personal.yml
      ├─ .env
      ├─ workspace-work/
      └─ workspace-personal/
```

---

# 3. 分層架構

```text
                 ┌────────────────────────────┐
                 │         gb10 CLI           │
                 │ Runtime Manager / Helper   │
                 └──────────────┬─────────────┘
                                │
                       reads runtimes.d
                                │
                                ▼
                 ┌────────────────────────────┐
                 │       Docker Compose       │
                 │   deployment source truth  │
                 └──────────────┬─────────────┘
                                │
                 ┌──────────────┴──────────────┐
                 │                             │
                 ▼                             ▼
          aeon-vllm stack               comfyui-aeon stack
                 │                             │
          27B / 35B profiles             Work / Personal
                 │                             │
                 └──────────────┬──────────────┘
                                ▼
                         Docker Engine
                                │
                 ┌──────────────┴──────────────┐
                 ▼                             ▼
            Host models                    Host cache
        persistent bind mounts         persistent bind mounts
```

重要觀念：

- `gb10` 不承載模型參數本身。
- 27B / 35B 的模型參數仍在各自 Compose。
- `gb10` 可以完全繞過；直接執行對應 `docker compose` 也能完成部署與切換。
- `gb10` 額外提供：
  - runtime profile 解析
  - exclusive group 切換
  - mount identity 檢查
  - health check
  - wait until READY
  - status / logs / doctor
  - last runtime state

---

# 4. `gb10` Runtime Manager

## 4.1 程式位置

真正程式：

```text
/home/eye/docker-stacks/ai-runtime-manager/gb10
```

命令入口：

```text
/home/eye/bin/gb10
```

確認：

```bash
command -v gb10
readlink -f "$(command -v gb10)"
```

## 4.2 目前 Runtime Profiles

### LLM

```text
RUNTIME_ID="aeon-qwen36-27b"
DISPLAY_NAME="AEON Qwen3.6 27B"
ALIASES="27b aeon-27b"
MODE="exclusive"
GROUP="llm"

STACK_DIR="${HOME}/docker-stacks/aeon-vllm"
COMPOSE_FILE="docker-compose.27b.yml"
PROJECT="aeon-vllm"
SERVICE="vllm"
CONTAINER="aeon-vllm"

IDENTITY_MOUNT="/model"
HEALTH_URL="http://127.0.0.1:1234/health"
TIMEOUT="1800"
```

```text
RUNTIME_ID="aeon-qwen36-35b-a3b"
DISPLAY_NAME="AEON Qwen3.6 35B-A3B"
ALIASES="35b aeon-35b"
MODE="exclusive"
GROUP="llm"

STACK_DIR="${HOME}/docker-stacks/aeon-vllm"
COMPOSE_FILE="docker-compose.35b.yml"
PROJECT="aeon-vllm"
SERVICE="vllm"
CONTAINER="aeon-vllm"

IDENTITY_MOUNT="/model"
HEALTH_URL="http://127.0.0.1:1234/health"
TIMEOUT="1800"
```

### Image / ComfyUI

```text
comfyui-work
comfyui-personal
```

兩者同屬：

```text
GROUP=image
MODE=exclusive
```

## 4.3 Runtime Group 原則

```text
GROUP=llm
- aeon-qwen36-27b
- aeon-qwen36-35b-a3b

GROUP=image
- comfyui-work
- comfyui-personal
```

同 group 互斥：

```text
27B 與 35B 不同時常駐
Work 與 Personal 不同時常駐
```

不同 group 可共存：

```text
27B + ComfyUI Work
27B + ComfyUI Personal
35B + ComfyUI Work/Personal
```

但 35B + ComfyUI 尚未完成正式壓力驗證。

## 4.4 常用指令

```bash
gb10 list
gb10 status
gb10 doctor

gb10 use 27b
gb10 use 35b

gb10 start comfyui-work
gb10 start comfyui-personal

gb10 stop 27b
gb10 restart 27b
gb10 logs 27b
```

---

# 5. vLLM Stack

## 5.1 Stack 路徑

```text
/home/eye/docker-stacks/aeon-vllm/
```

目前主要檔案：

```text
.env
docker-compose.27b.yml
docker-compose.35b.yml
docker-compose.yml
models/
cache/
logs/
```

## 5.2 API

```text
Port: 1234

OpenAI-compatible base URL:
http://192.168.23.215:1234/v1

served model ID:
aeon
```

Health：

```text
http://127.0.0.1:1234/health
```

## 5.3 API Key

API key 存放在：

```text
/home/eye/docker-stacks/aeon-vllm/.env
```

本 handoff 不保存實際值。

---

# 6. 目前 AEON vLLM Docker Image

2026-08-10 已完成：

```text
v0.25.1
→
v0.26.0
```

目前已下載並保留：

```text
ghcr.io/aeon-7/aeon-vllm-ultimate:2026-07-16-v0.25.1
ghcr.io/aeon-7/aeon-vllm-ultimate:2026-07-27-v0.26.0
```

v0.26.0 image digest（本次 pull 所見）：

```text
sha256:1aa47363e4c9cfa0a85411c669d39b7f9fa3adb3e735ef1ca5760be3044dacd7
```

v0.25.1 暫時不要刪除，保留 rollback。

---

# 7. `.env` 共用設定

2026-08-10 已確認非敏感設定：

```text
AEON_IMAGE=ghcr.io/aeon-7/aeon-vllm-ultimate:2026-07-27-v0.26.0

VLLM_MAX_MODEL_LEN=229376
VLLM_MAX_NUM_SEQS=16
VLLM_GPU_MEMORY_UTILIZATION=0.60
VLLM_PORT=1234
```

另外 27B 實際 resolved config 已確認：

```text
VLLM_MAX_BATCHED_TOKENS=32768
```

注意：

若使用：

```bash
grep -v -Ei 'key|token|secret|password' .env
```

`VLLM_MAX_BATCHED_TOKENS` 會因字串包含 `TOKEN` 被一起排除，不代表變數不存在。

---

# 8. 27B Runtime

## 8.1 Profile / Compose

Runtime：

```text
aeon-qwen36-27b
```

Compose：

```text
docker-compose.27b.yml
```

目前 image 定義：

```yaml
image: ${AEON_IMAGE}
```

因此真正版本由 `.env` 控制。

目前 resolved image：

```text
ghcr.io/aeon-7/aeon-vllm-ultimate:2026-07-27-v0.26.0
```

## 8.2 Host model mounts

Target model：

```text
/home/eye/docker-stacks/aeon-vllm/models/qwen3.6-27b-aeon-mm-mtp
→ /model
```

DFlash drafter：

```text
/home/eye/docker-stacks/aeon-vllm/models/qwen3.6-27b-dflash
→ /drafter
```

Cache：

```text
/home/eye/docker-stacks/aeon-vllm/cache
→ /root/.cache
```

Mount mode：

```text
/model   ro
/drafter ro
/cache   rw
```

因此 Docker image 升級不需要重新下載模型。

## 8.3 27B 實際 vLLM 參數

```text
serve /model

--host 0.0.0.0
--port 1234

--served-model-name aeon
--tensor-parallel-size 1
--dtype auto

--quantization modelopt
--kv-cache-dtype fp8_e4m3
--attention-backend TRITON_ATTN

--max-model-len 229376
--max-num-seqs 16
--max-num-batched-tokens 32768
--gpu-memory-utilization 0.60

--enable-chunked-prefill
--enable-prefix-caching

--generation-config vllm
--reasoning-parser qwen3
--tool-call-parser qwen3_coder
--enable-auto-tool-choice

--mm-encoder-tp-mode data

--speculative-config
{"method":"dflash","model":"/drafter","num_speculative_tokens":12,"attention_backend":"TRITON_ATTN"}

--trust-remote-code
```

## 8.4 27B v0.26.0 驗證

2026-08-10 已成功啟動：

```text
version 0.26.0+aeon.sm121a.dflash
```

模型架構解析：

```text
Qwen3_5ForConditionalGeneration
```

Drafter：

```text
DFlashDraftModel
```

Quantization：

```text
modelopt_fp4 / NVFP4
```

vLLM Engine：

```text
V1 LLM engine
```

Health：

```text
READY
```

Restart count：

```text
0
```

---

# 9. 35B-A3B Runtime

## 9.1 Profile / Compose

Runtime：

```text
aeon-qwen36-35b-a3b
```

Compose：

```text
docker-compose.35b.yml
```

2026-08-10 已將 image **單變量**從：

```text
2026-07-16-v0.25.1
```

改為：

```text
2026-07-27-v0.26.0
```

目前 35B image 仍是 **Compose 內直接 pin**，不是 `${AEON_IMAGE}`。

這是刻意保留目前架構，方便不同 model profile 可獨立 pin runtime version。

## 9.2 Host model mounts

Target：

```text
./models/qwen3.6-35b-a3b-heretic-nvfp4
→ /model
```

DFlash：

```text
./models/qwen3.6-35b-a3b-dflash
→ /drafter
```

Cache：

```text
./cache/huggingface
→ /root/.cache/huggingface

./cache/vllm-35b
→ /root/.cache/vllm
```

Logs：

```text
./logs
→ /logs
```

35B cache 與 27B 有較明顯隔離。

## 9.3 35B vLLM 參數

目前保持原 0.25.1 時期設定，只換 Docker image：

```text
serve /model

--host 0.0.0.0
--port 1234

--served-model-name aeon
--tensor-parallel-size 1
--dtype auto

--quantization compressed-tensors
--attention-backend flash_attn

--max-model-len 229376
--max-num-seqs 16
--max-num-batched-tokens 32768
--gpu-memory-utilization 0.60

--enable-chunked-prefill
--enable-prefix-caching

--load-format safetensors

--generation-config vllm
--reasoning-parser qwen3
--tool-call-parser qwen3_coder
--enable-auto-tool-choice

--speculative-config
{"method":"dflash","model":"/drafter","num_speculative_tokens":11}

--trust-remote-code
```

## 9.4 35B 與 27B 不應強行同步的項目

```text
27B                            35B-A3B
--------------------------------------------------
modelopt                       compressed-tensors
fp8_e4m3 KV                    default KV
TRITON_ATTN                    flash_attn
DFlash 12                      DFlash 11
drafter TRITON_ATTN            drafter default
MM encoder TP=data             no explicit setting
load-format auto               safetensors
```

這些是各 profile 的模型專屬 tuning，不應因 image 升級而一起修改。

---

# 10. 27B / 35B Runtime Slot 設計

目前不是兩個大型 vLLM container 同時常駐，而是共用同一個 slot：

```text
container_name:
aeon-vllm

Compose project:
aeon-vllm

service:
vllm
```

架構：

```text
                  aeon-vllm runtime slot
                           │
             ┌─────────────┴─────────────┐
             │                           │
         27B profile                35B-A3B profile
             │                           │
       model/drafter                model/drafter
       backend tuning               backend tuning
       cache policy                 cache policy
             │                           │
             └──────── gb10 ─────────────┘
                    exclusive switch
```

因此：

```bash
gb10 use 27b
```

與：

```bash
gb10 use 35b
```

會透過各自的 Compose profile 重建同一個 `aeon-vllm` slot。

---

# 11. Docker Image 與模型檔解耦

27B 已確認：

```text
Type: bind

Host:
.../models/qwen3.6-27b-aeon-mm-mtp
→ /model

Host:
.../models/qwen3.6-27b-dflash
→ /drafter

Host:
.../cache
→ /root/.cache
```

因此：

```text
docker compose down
docker container remove
docker image upgrade
docker compose up
```

都不會刪除 Host model。

檢查方式：

```bash
docker inspect aeon-vllm \
  --format '{{range .Mounts}}{{println .Source " -> " .Destination}}{{end}}'
```

只要 `/model`、`/drafter` 的 Source 指向 Host models，即為持久化安全架構。

---

# 12. vLLM Docker Image 升級 SOP

以下流程適用未來同類 AEON image 升級。

## 12.1 原則

```text
先 pull
→ 不影響現行服務

保留舊 image
→ 可 rollback

只改 image version
→ 第一輪不要同時調參

Compose config 驗證
→ 再重建 container

Health / logs / mount
→ 完整驗證
```

## 12.2 Pull 新 image

所在資料夾其實不影響 `docker pull`，但為操作一致建議：

```bash
cd ~/docker-stacks/aeon-vllm
```

例如：

```bash
docker pull ghcr.io/aeon-7/aeon-vllm-ultimate:<NEW_TAG>
```

確認：

```bash
docker images ghcr.io/aeon-7/aeon-vllm-ultimate
```

## 12.3 SSH 可能斷線

大型 image layer 下載期間若 SSH 容易斷線，可使用：

```bash
tmux new -s aeon-pull
```

重新連線：

```bash
tmux attach -t aeon-pull
```

Docker layer 已完成者會保留；重跑同一 `docker pull` 不會從零開始。

## 12.4 27B 升級

27B image 由 `.env`：

```text
AEON_IMAGE=
```

控制。

備份：

```bash
cd ~/docker-stacks/aeon-vllm
cp .env .env.bak-before-upgrade-$(date +%Y%m%d-%H%M%S)
```

改 tag 後驗證：

```bash
docker compose \
  -p aeon-vllm \
  -f docker-compose.27b.yml \
  config >/dev/null && echo "Compose OK"
```

確認 resolved image：

```bash
docker compose \
  -p aeon-vllm \
  -f docker-compose.27b.yml \
  config | grep 'image:'
```

重建：

```bash
docker compose \
  -p aeon-vllm \
  -f docker-compose.27b.yml \
  down

docker compose \
  -p aeon-vllm \
  -f docker-compose.27b.yml \
  up -d
```

## 12.5 35B 升級

目前 35B image 是直接 pin 在：

```text
docker-compose.35b.yml
```

升級時只修改：

```yaml
image: ghcr.io/aeon-7/aeon-vllm-ultimate:<NEW_TAG>
```

備份：

```bash
cp docker-compose.35b.yml \
  docker-compose.35b.yml.bak-before-upgrade-$(date +%Y%m%d-%H%M%S)
```

驗證：

```bash
docker compose \
  -p aeon-vllm \
  -f docker-compose.35b.yml \
  config >/dev/null && echo "35B Compose OK"
```

## 12.6 第一輪不要同時調參

升級時原則：

```text
Docker image version
= 唯一變量

model
drafter
quantization
attention
KV dtype
max context
max seqs
max batched tokens
GPU memory utilization
speculative tokens
= 全部先維持
```

這樣出現 regression 時才能歸因。

---

# 13. Rollback SOP

舊 image 不刪除。

例如回到舊版：

```text
2026-07-16-v0.25.1
```

27B：

```bash
cd ~/docker-stacks/aeon-vllm
# 將 .env AEON_IMAGE 改回舊 tag

docker compose \
  -p aeon-vllm \
  -f docker-compose.27b.yml \
  up -d --force-recreate
```

35B：

```bash
# 將 docker-compose.35b.yml image 改回舊 tag

docker compose \
  -p aeon-vllm \
  -f docker-compose.35b.yml \
  up -d --force-recreate
```

確認：

```bash
docker inspect aeon-vllm --format '{{.Config.Image}}'
```

---

# 14. v0.26.0 首次冷啟動經驗

27B 第一次使用 v0.26.0 啟動較久。

本次時間約：

```text
API server process start:
10:25:46

Application startup complete:
10:41:31

約 15 分 45 秒
```

Engine init：

```text
init engine:
699.60 s
```

主要一次性／冷啟動工作：

```text
Target model safetensors load
DFlash drafter load
torch.compile
initial profiling/warmup
FlashInfer FP4 autotune
CUDA graph capture
multi-modal warmup
```

本次 target：

```text
Checkpoint size: 26.59 GiB
Loading weights: 166.20 s
```

Drafter：

```text
Checkpoint size: 3.22 GiB
Loading weights: 20.08 s
```

Model total loading：

```text
29.34 GiB memory
188.4 s
```

---

# 15. v0.26.0 Cache 行為

27B cache bind mount：

```text
./cache
→ /root/.cache
```

首次 v0.26.0 產生：

```text
/root/.cache/vllm/torch_compile_cache/
/root/.cache/vllm/flashinfer_autotune_cache/
```

本次 FlashInfer：

```text
version:
0.6.14

FP4 autotune:
92 configs
```

已保存：

```text
/root/.cache/vllm/flashinfer_autotune_cache/0.6.14/121a/...
```

因此後續 restart 應可重用 cache。

不要為了「乾淨」而隨意刪除整個 cache。

---

# 16. 27B v0.26.0 Memory / KV 觀察

啟動 log：

```text
Available KV cache memory:
36.02 GiB

GPU KV cache size:
622,671 tokens

Maximum concurrency for 229,376 tokens per request:
2.71x
```

重要解讀：

```text
max-num-seqs=16
≠
16 個 request 都能同時各吃滿 229,376 tokens
```

229376 是單 request 上限。

若粗略平均 5 concurrent：

```text
622,671 / 5
≈ 124K tokens/request
```

因此 5 concurrent 實務上可行，但不能假設五條 session 同時全部滿 229K。

---

# 17. v0.26.0 Swap 觀察與結論

## 17.1 現象

第一次 v0.26.0 冷啟動後：

```text
Swap:
約 3.8 GiB / 16 GiB
```

沒有立刻釋放。

## 17.2 Process 檢查

主要 VmSwap：

```text
VLLM::EngineCore
≈ 1.85 GB (decimal)
≈ 1.77 GiB

vllm
≈ 0.57 GB
≈ 0.54 GiB
```

vLLM private VmSwap 合計約：

```text
2.31 GiB
```

EngineCore：

```text
VmHWM:
~28 GiB

VmRSS after startup:
~2.45 GiB

VmSwap:
~1.77 GiB
```

推論：首次 compile / profiling / autotune 的 transient memory pressure 導致 Linux 把 cold anonymous pages swap out。

## 17.3 系統 memory

當時：

```text
MemAvailable:
~42 GiB

Swap used:
~3.77 GiB

SwapCached:
~1.38 GiB
```

代表並非 3.8 GiB 全部都正在磁碟上等待 page-in。

## 17.4 vmstat

檢查：

```bash
vmstat 1 10
```

第一行是自開機平均值，不用來判斷現在。

實際後續每秒：

```text
si = 0
so = 0
wa = 0
CPU idle ~99-100%
```

結論：

```text
目前沒有 swap thrashing
目前 3.8 GiB 可視為 cold/historical swap
不需清除
```

目前不要：

```bash
swapoff -a
```

也不要只因 swap 數字存在就降低：

```text
gpu-memory-utilization=0.60
```

只有在推理負載期間：

```text
si / so 持續明顯 > 0
```

才需要進一步調整。

---

# 18. vLLM Troubleshooting 常用指令

## 18.1 Status

```bash
gb10 status
gb10 doctor
```

## 18.2 Container

```bash
docker ps --filter name=aeon-vllm
docker inspect aeon-vllm --format '{{.Config.Image}}'
```

## 18.3 Logs

```bash
docker logs -f --tail=200 aeon-vllm
```

`Ctrl+C` 只退出 log follow，不會停止 container。

## 18.4 Health

```bash
curl -i http://127.0.0.1:1234/health
```

## 18.5 Mounts

```bash
docker inspect aeon-vllm \
  --format '{{range .Mounts}}{{println .Source " -> " .Destination}}{{end}}'
```

## 18.6 真正執行參數

```bash
docker inspect aeon-vllm \
  --format '{{json .Config.Cmd}}' \
  | python3 -m json.tool
```

## 18.7 Compose resolved config

27B：

```bash
docker compose \
  -p aeon-vllm \
  -f docker-compose.27b.yml \
  config
```

35B：

```bash
docker compose \
  -p aeon-vllm \
  -f docker-compose.35b.yml \
  config
```

JSON command：

```bash
docker compose -p aeon-vllm \
  -f docker-compose.27b.yml \
  config --format json \
  | jq '.services.vllm.command'
```

## 18.8 比較 27B / 35B

```bash
diff -u docker-compose.27b.yml docker-compose.35b.yml
```

Resolved：

```bash
docker compose -p aeon-vllm -f docker-compose.27b.yml \
  config > /tmp/27b-resolved.yml

docker compose -p aeon-vllm -f docker-compose.35b.yml \
  config > /tmp/35b-resolved.yml

diff -u /tmp/27b-resolved.yml /tmp/35b-resolved.yml
```

---

# 19. Swap Troubleshooting

查看：

```bash
free -h
swapon --show
cat /proc/swaps
```

Process VmSwap：

```bash
for p in /proc/[0-9]*; do
    pid=${p##*/}
    swap=$(awk '/^VmSwap:/ {print $2}' "$p/status" 2>/dev/null)
    name=$(awk '/^Name:/ {print $2}' "$p/status" 2>/dev/null)
    if [[ -n "$swap" && "$swap" -gt 0 ]]; then
        printf "%10d kB  PID=%-8s %s\n" "$swap" "$pid" "$name"
    fi
done | sort -nr | head -30
```

即時 swap I/O：

```bash
vmstat 1
```

判斷：

```text
swpd 高但 si/so=0
→ 通常只是歷史 cold swap

si/so 持續跳動
→ 才是 active swapping / memory pressure
```

---

# 20. ComfyUI Stack（沿用 2026-07-31 Handover，2026-08-10 未全面重驗）

> 本節保留既有部署資訊；本次工作重點為 vLLM 0.26.0 升級，ComfyUI 模型與 workflow 未重新逐項驗證。

Stack：

```text
/home/eye/docker-stacks/comfyui-aeon/
```

Image：

```text
ghcr.io/aeon-7/comfyui-aeon-spark@sha256:7fda74d7af1d86455bfa58df5d36e761964017c7bce6f5d2f3564ba0b2deee3a
```

Container：

```text
comfyui-spark
```

Port：

```text
8188
```

Work：

```text
docker-compose.yml
workspace-work/
```

Personal：

```text
docker-compose.personal.yml
workspace-personal/
```

Work / Personal：

```text
同 GROUP=image
互斥
```

LLM 與 image group：

```text
可共存
```

---

# 21. ComfyUI Work（沿用 2026-07-31）

用途：

```text
公司正式簡報插圖
企業科技背景圖
```

主要 Qwen-Image-2512：

```text
Diffusion:
qwen_image_2512_fp8_e4m3fn.safetensors

Text Encoder:
qwen_2.5_vl_7b_fp8_scaled.safetensors

VAE:
qwen_image_vae.safetensors

Lightning LoRA:
Qwen-Image-2512-Lightning-4steps-V1.0-fp32.safetensors
```

已知不要正式使用：

```text
qwen_2.5_vl_7b_nvfp4.safetensors
```

原因：

```text
conditioning 異常
提示詞與生成內容不相關
重複 / 抽象圖樣
```

Work Quality：

```text
turbo=false
Steps=50
CFG=4
Sampler=euler
Scheduler=simple
```

Work Fast：

```text
turbo=true
Steps=4
CFG=1
Sampler=euler
Scheduler=simple
```

---

# 22. ComfyUI Personal（沿用 2026-07-31）

用途：

```text
私人研究
非商業
```

主要：

```text
FLUX.2 Klein 9B Distilled

Diffusion:
flux-2-klein-9b-fp8.safetensors

Text Encoder:
qwen_3_8b_fp8mixed.safetensors

VAE:
full_encoder_small_decoder.safetensors
```

參數：

```text
Steps=4
CFG=1
Sampler=euler
```

---

# 23. 系統 Swap

Swap：

```text
/swap.img
```

容量：

```text
16 GiB
```

用途：

```text
短暫記憶體尖峰緩衝
不是模型常態記憶體
```

不要因為 swap used 非零就直接：

```bash
swapoff -a
```

---

# 24. 操作禁忌

```text
不要重新加入 runtime: nvidia
不要為 GPU runtime 調整而隨意重啟 Docker daemon
不要把模型權重存進 container writable layer
不要把 API Key / HF Token 寫入 handoff / Git / 公開截圖
不要因 image 升級順便大量調整模型參數
不要把 27B / 35B tuning 強行統一
不要隨意刪除 /root/.cache 對應的 Host cache
不要隨意 swapoff -a
不要把 max-num-seqs=16 解讀成 16 × 229K 都能同時常駐
不要在尚未驗證前刪除舊 AEON image
```

ComfyUI：

```text
不要新增 Ollama sidecar
不要下載 AEON 完整大型模型 bundle
不要把 Personal FLUX 模型放進 Work
不要把 Work / Personal workspace 合併
不要把 NVFP4 Text Encoder 用於正式 Qwen-Image Work
```

---

# 25. Docker / Compose 版本紀錄

2026-07-31 handover 記錄：

```text
Docker Engine: 29.2.1
Docker Compose: v5.0.2
```

注意：

```text
2026-08-10 本次 vLLM 升級流程未重新執行 docker --version /
docker compose version 驗證，因此上述版本屬 7/31 最近一次文件紀錄。
```

如未來排查 Compose 行為差異，先重新確認：

```bash
docker --version
docker compose version
```

---

# 26. 目前部署完成狀態（2026-08-10）

```text
[OK] DGX Spark / GB10
[OK] Docker / Compose deployment
[OK] gb10 Runtime Manager
[OK] 27B / 35B exclusive LLM runtime profiles
[OK] Qwen3.6 27B model bind mount
[OK] 27B DFlash bind mount
[OK] 35B-A3B model bind mount
[OK] 35B DFlash bind mount
[OK] AEON vLLM v0.26.0 image pull
[OK] 27B → v0.26.0
[OK] 27B v0.26.0 startup / health READY
[OK] 27B v0.26.0 cache / FlashInfer autotune generated
[OK] 35B Compose image → v0.26.0
[OK] 35B Compose syntax / resolved image validation
[NOT YET RE-VALIDATED] 35B v0.26.0 actual startup
[OK] 16 GiB swap
[OK] v0.26.0 cold-start swap observation
[OK] idle vmstat si/so = 0
[OK] ComfyUI Work / Personal deployment inherited from 7/31
```

---

# 27. 後續建議

1. 下次需要 35B 時，以：

```bash
gb10 use 35b
```

實際驗證 35B + v0.26.0。

2. 第一次 35B v0.26.0 啟動可能產生新的：

```text
torch compile cache
FlashInfer autotune cache
```

其 cache 已與 27B 有一定隔離。

3. 建議建立固定 benchmark：

```text
27B:
- cold startup
- warm restart
- 1 concurrent
- 3 concurrent
- 5 concurrent
- TTFT
- output tok/s
- aggregate tok/s
- prefix cache behavior
- active context
- peak RAM
- swap si/so

35B:
同上
```

4. 目前不要急著把 35B image 改成 `${AEON_IMAGE}`。

原因：

```text
27B / 35B 可各自 pin vLLM image
方便 A/B 與 rollback
```

待 35B v0.26.0 實際驗證穩定後，再決定是否統一版本管理。

5. 未來 image 升級仍採：

```text
pull
→ backup
→ single-variable image change
→ compose config
→ recreate
→ logs
→ health
→ mount
→ benchmark
→ 保留舊版 rollback
```

---

# 28. 下一位 AI / 維護人員接手時先跑

```bash
gb10 status
gb10 doctor

free -h
swapon --show

docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Image}}'

docker images ghcr.io/aeon-7/aeon-vllm-ultimate
```

vLLM：

```bash
docker inspect aeon-vllm --format '{{.Config.Image}}'

docker inspect aeon-vllm \
  --format '{{range .Mounts}}{{println .Source " -> " .Destination}}{{end}}'

docker inspect aeon-vllm \
  --format '{{json .Config.Cmd}}' \
  | python3 -m json.tool

curl -i http://127.0.0.1:1234/health
```

Compose：

```bash
cd ~/docker-stacks/aeon-vllm

docker compose -p aeon-vllm -f docker-compose.27b.yml config
docker compose -p aeon-vllm -f docker-compose.35b.yml config
```

若發生 memory / swap 問題：

```bash
vmstat 1
```

若 `si/so` 為 0，即使 swap used 非 0，也不要先假定為故障。

---

# 29. 最終架構結論

目前 GB10 已形成：

```text
                    GB10 / DGX Spark
                          │
          ┌───────────────┴────────────────┐
          │                                │
      LLM group                         Image group
          │                                │
   ┌──────┴──────┐                  ┌──────┴──────┐
   │             │                  │             │
 27B           35B-A3B             Work         Personal
   │             │                  │             │
 vLLM          vLLM                ComfyUI       ComfyUI
 v0.26.0       v0.26.0 config
   │             │
   └──────┬──────┘
          │
     aeon-vllm slot
          │
       Docker Compose
          │
        Host models/cache
```

治理原則：

```text
gb10
= runtime 操作便利層

Compose
= deployment 主權

Host models/cache
= persistent data

Docker image
= 可升級 / 可回滾 runtime

27B / 35B
= 各自獨立 tuning profile
```

截至 2026-08-10：

```text
27B v0.26.0
已實際啟動並 READY

35B-A3B v0.26.0
Compose 已完成 image 升級與語法驗證
尚待下一次實際切換時做 runtime 驗證

ComfyUI
沿用 2026-07-31 已完成部署
本次未變更
```
