# DGX Spark GB10 本地 AI 部署狀態交接

> 更新日期：2026-07-31  
> 主機：NVIDIA DGX Spark / GB10  
> 主機名稱：`spark-25d5`  
> 使用者：`eye`  
> 區網 IP：`192.168.23.215`  
> 作業系統：Ubuntu 24.04 ARM64  
> 用途：本地 LLM 推理 + ComfyUI 生圖，並以 Docker Stack 分離管理

---

## 1. 文件目的

本文件用於交接目前 GB10 本地 AI 部署狀態，讓後續 AI 或維護人員能先了解：

- Docker Stack 整體架構
- `gb10` Runtime Manager 的定位與操作方式
- vLLM 27B / 35B 模型切換架構
- ComfyUI Work / Personal 隔離架構
- 已部署模型、工作流與驗證結果
- 已知問題、踩坑經驗與操作禁忌
- 後續可改善項目

此文件不包含任何私密 Token、API Key 或密碼。

---

# 2. 整體架構

```text
/home/eye/
├─ bin/
│  └─ gb10
│     └─ symbolic link
│        → /home/eye/docker-stacks/ai-runtime-manager/gb10
│
└─ docker-stacks/
   ├─ ai-runtime-manager/
   │  ├─ gb10
   │  ├─ runtimes.d/
   │  └─ state/
   │
   ├─ aeon-vllm/
   │  ├─ docker-compose.27b.yml
   │  ├─ docker-compose.35b.yml
   │  ├─ .env
   │  └─ models/
   │
   └─ comfyui-aeon/
      ├─ docker-compose.yml
      ├─ docker-compose.personal.yml
      ├─ .env
      ├─ workspace-work/
      └─ workspace-personal/
```

核心原則：

```text
ai-runtime-manager
＝方便操作的控制層

Docker Compose stacks
＝真正的部署來源與服務定義
```

Runtime Manager 不應取代 Compose，也不應把模型參數硬寫進 `gb10` 主程式。

---

# 3. 主機與基礎環境

## 3.1 SSH

```bash
ssh eye@192.168.23.215
```

## 3.2 Docker

目前版本：

```text
Docker Engine：29.2.1
Docker Compose：v5.0.2
```

## 3.3 GPU 容器方式

目前 Docker daemon 沒有名為 `nvidia` 的傳統 runtime，但 GPU 容器已可透過 Compose GPU device reservation / CDI 正常使用。

重要禁忌：

```text
不要重新加入 runtime: nvidia
不要為了 GPU runtime 調整而重啟 Docker daemon
```

目前 GPU 已正常運作，不需額外修改。

---

# 4. `gb10` Runtime Manager

## 4.1 實際程式與符號連結

真正程式：

```text
/home/eye/docker-stacks/ai-runtime-manager/gb10
```

命令入口：

```text
/home/eye/bin/gb10
```

`~/bin/gb10` 是 symbolic link：

```text
~/bin/gb10
→ ~/docker-stacks/ai-runtime-manager/gb10
```

因此不是兩份程式，不需要同步。

確認方式：

```bash
command -v gb10
readlink -f "$(command -v gb10)"
```

## 4.2 Runtime Profiles

目前 profiles：

```text
aeon-qwen36-27b
aeon-qwen36-35b-a3b
comfyui-work
comfyui-personal
```

查詢：

```bash
gb10 status
gb10 doctor
```

## 4.3 建議使用完整 Runtime ID

日常操作統一使用：

```bash
gb10 start comfyui-work
gb10 start comfyui-personal
```

雖然短別名目前仍可用：

```bash
gb10 start work
gb10 start personal
```

但不建議，因為 `work` / `personal` 語意太廣，未來可能與其他服務衝突。

目前不需要修改 `gb10` 主程式。

## 4.4 Runtime 群組

```text
GROUP=llm
- aeon-qwen36-27b
- aeon-qwen36-35b-a3b

GROUP=image
- comfyui-work
- comfyui-personal
```

同一群組互斥：

```text
27B 與 35B 不可同時運行
Work 與 Personal 不可同時運行
```

不同群組可共存：

```text
27B + ComfyUI Work
27B + ComfyUI Personal
```

---

# 5. vLLM Stack

## 5.1 Stack 路徑

```text
/home/eye/docker-stacks/aeon-vllm/
```

## 5.2 映像

```text
ghcr.io/aeon-7/aeon-vllm-ultimate:2026-07-16-v0.25.1
```

## 5.3 API

```text
Port：1234
OpenAI 相容 API：
http://192.168.23.215:1234/v1

served model ID：
aeon
```

## 5.4 API Key

API Key 存放於：

```text
/home/eye/docker-stacks/aeon-vllm/.env
```

不可把實際 Key 寫入文件、截圖、Git 或對外訊息。

## 5.5 27B Runtime

Profile：

```text
aeon-qwen36-27b
```

Compose：

```text
docker-compose.27b.yml
```

Target model：

```text
models/qwen3.6-27b-aeon-mm-mtp
```

Drafter：

```text
models/qwen3.6-27b-dflash
```

目前 27B 為日常預設。

切換：

```bash
gb10 use 27b
```

## 5.6 35B Runtime

Profile：

```text
aeon-qwen36-35b-a3b
```

Compose：

```text
docker-compose.35b.yml
```

Target model：

```text
models/qwen3.6-35b-a3b-heretic-nvfp4
```

Drafter：

```text
models/qwen3.6-35b-a3b-dflash
```

切換：

```bash
gb10 use 35b
```

除非明確需要，不要隨意切離 27B。

## 5.7 常用檢查

```bash
gb10 status
gb10 logs aeon-qwen36-27b
```

API 驗證：

```bash
curl -fsS http://127.0.0.1:1234/v1/models
```

---

# 6. ComfyUI Stack

## 6.1 Stack 路徑

```text
/home/eye/docker-stacks/comfyui-aeon/
```

## 6.2 映像

使用 AEON slim image，已 pin digest：

```text
ghcr.io/aeon-7/comfyui-aeon-spark@sha256:7fda74d7af1d86455bfa58df5d36e761964017c7bce6f5d2f3564ba0b2deee3a
```

映像特性：

```text
ARM64
CUDA 13.0.2
PyTorch 2.9.1+cu130
ComfyUI
SageAttention
```

## 6.3 服務

```text
Container：comfyui-spark
Port：8188
URL：http://192.168.23.215:8188
```

啟動方式：

```text
on-demand
restart: "no"
```

沒有 Ollama sidecar。

```text
SKIP_MODEL_DOWNLOAD=1
```

不要下載 AEON 的完整大型模型 bundle。

---

# 7. Work / Personal 隔離

## 7.1 Work

Compose：

```text
docker-compose.yml
```

Workspace：

```text
/home/eye/docker-stacks/comfyui-aeon/workspace-work
```

Container 內：

```text
/workspace/ComfyUI
```

確認：

```bash
docker inspect comfyui-spark \
  --format '{{range .Mounts}}{{if eq .Destination "/workspace/ComfyUI"}}{{.Source}} -> {{.Destination}}{{end}}{{end}}'
```

應顯示：

```text
/home/eye/docker-stacks/comfyui-aeon/workspace-work -> /workspace/ComfyUI
```

啟動：

```bash
gb10 start comfyui-work
```

## 7.2 Personal

Compose：

```text
docker-compose.personal.yml
```

Workspace：

```text
/home/eye/docker-stacks/comfyui-aeon/workspace-personal
```

啟動：

```bash
gb10 start comfyui-personal
```

## 7.3 隔離內容

Work / Personal 分開保留：

```text
models/
user/
workflows/
input/
output/
custom_nodes/
.cache/
```

但共用：

```text
Docker image
Container name
Port 8188
Compose project
.env
HF_TOKEN
```

Work / Personal 不能同時運行，但都可與 LLM Runtime 共存。

---

# 8. Hugging Face Token

主機 Token：

```text
/home/eye/.cache/huggingface/token
```

目前帳號：

```text
Sawaichi
```

Token 已安全寫入：

```text
/home/eye/docker-stacks/comfyui-aeon/.env
```

權限：

```text
600
```

Work / Personal 共用 `.env`，因此兩邊都能存取 Hugging Face。

不要把 Token 寫入：

```text
Docker image
workflow JSON
Markdown
Git
聊天訊息
```

---

# 9. ComfyUI Work：Qwen-Image-2512

## 9.1 用途

```text
公司 Work
正式簡報插圖
企業科技背景圖
```

授權方向：

```text
Apache-2.0
```

## 9.2 已部署模型

Diffusion：

```text
workspace-work/models/diffusion_models/
qwen_image_2512_fp8_e4m3fn.safetensors
```

大小：

```text
20,430,679,144 bytes
```

SHA256：

```text
5dc80554d5d83390046a2f4a94ece06afb7700bf7b0aaf8bde9769793875876b
```

VAE：

```text
workspace-work/models/vae/
qwen_image_vae.safetensors
```

大小：

```text
253,806,246 bytes
```

SHA256：

```text
a70580f0213e67967ee9c95f05bb400e8fb08307e017a924bf3441223e023d1f
```

Lightning LoRA：

```text
workspace-work/models/loras/
Qwen-Image-2512-Lightning-4steps-V1.0-fp32.safetensors
```

## 9.3 Text Encoder

### 錯誤／不建議版本

```text
qwen_2.5_vl_7b_nvfp4.safetensors
```

此版本在目前 ComfyUI / Qwen-Image-2512 工作流中出現嚴重 conditioning 異常：

```text
提示詞與生成內容無關
重複圖樣
抽象花紋
罐子、裝飾圖樣等無關物件
```

目前判定為主要問題來源。

保留作 A/B 研究用途，但不要再用於正式 Work workflow。

### 正式使用版本

```text
workspace-work/models/text_encoders/
qwen_2.5_vl_7b_fp8_scaled.safetensors
```

大小：

```text
9,384,670,680 bytes
```

此版本已驗證：

```text
提示詞理解正常
右側主體正常
左側留白正常
物件結構完整
```

## 9.4 Work Workflow

原始：

```text
workspace-work/user/default/workflows/
11_qwen_image_2512_work.json
```

備份：

```text
11_qwen_image_2512_work.before-tuning.json
```

建議最終另存：

```text
11_qwen_image_2512_work_quality.json
11_qwen_image_2512_work_fast.json
```

### Quality

```text
enable_turbo_mode = false
Steps = 50
CFG = 4
Sampler = euler
Scheduler = simple
```

用途：

```text
正式簡報
高品質交付
最終定稿
```

### Fast

```text
enable_turbo_mode = true
Lightning LoRA
Steps = 4
CFG = 1
Sampler = euler
Scheduler = simple
```

用途：

```text
快速構圖
草稿
多 Seed 挑圖
```

## 9.5 建議解析度

官方 16:9：

```text
1664 × 928
```

其他官方模板建議：

```text
1:1   1328 × 1328
16:9  1664 × 928
9:16  928 × 1664
4:3   1472 × 1104
3:4   1104 × 1472
3:2   1584 × 1056
2:3   1056 × 1584
```

## 9.6 Work 驗證結果

已成功生成：

```text
右側黑色 AI computing appliance
左側大面積深藍留白
青色狀態燈
無明顯錯亂
```

Fast 模式也可正常生成，但可能：

```text
材質較像數位插畫
細節略少
偶爾生成 AI 字樣
邊緣銳化較明顯
```

---

# 10. ComfyUI Personal：FLUX.2 Klein 9B

## 10.1 用途

```text
私人研究
非公司交付
非商業用途
```

授權：

```text
FLUX Non-Commercial License
```

不要用於正式公司產品、營運或交付，除非另行確認商業授權。

## 10.2 已部署模型

Diffusion：

```text
workspace-personal/models/diffusion_models/
flux-2-klein-9b-fp8.safetensors
```

大小：

```text
9,433,061,528 bytes
```

Text Encoder：

```text
workspace-personal/models/text_encoders/
qwen_3_8b_fp8mixed.safetensors
```

大小：

```text
8,664,848,742 bytes
```

VAE：

```text
workspace-personal/models/vae/
full_encoder_small_decoder.safetensors
```

大小：

```text
249,519,092 bytes
```

## 10.3 Workflow

預置 workflow：

```text
08_flux2_klein_9b_text_to_image
```

原 workflow 指向：

```text
flux-2-klein-base-9b-fp8.safetensors
```

但實際部署的是 Distilled：

```text
flux-2-klein-9b-fp8.safetensors
```

因此已手動改為 Distilled 模型與參數。

建議保存：

```text
08_flux2_klein_9b_text_to_image_distilled
```

## 10.4 Distilled 參數

```text
Diffusion:
flux-2-klein-9b-fp8.safetensors

Text Encoder:
qwen_3_8b_fp8mixed.safetensors

VAE:
full_encoder_small_decoder.safetensors

Steps:
4

CFG:
1

Sampler:
euler

weight_dtype:
default
```

## 10.5 驗證結果

已成功生成：

```text
768 × 768 產品圖
1344 × 768 簡報橫式圖
右側設備
左側乾淨留白
深藍企業科技背景
```

Personal 生圖速度明顯比 Work 快，原因：

```text
FLUX.2 Klein 9B 模型較小
原生 4-step Distilled
常用解析度較低
Text Encoder / Diffusion 負擔較小
```

---

# 11. Work 與 Personal 效能差異

大致比較：

| 項目 | Personal | Work Fast | Work Quality |
|---|---:|---:|---:|
| Diffusion | FLUX.2 Klein 9B | Qwen-Image-2512 | Qwen-Image-2512 |
| 模型檔 | 約 9.43 GB | 約 20.4 GB | 約 20.4 GB |
| Steps | 4 | 4 | 50 |
| CFG | 1 | 1 | 4 |
| 常用解析度 | 1344×768 | 1664×928 | 1664×928 |
| 速度 | 最快 | 中等 | 最慢 |

第一張通常更慢，因為模型需從 NVMe 載入 UMA。

ComfyUI 節點顯示的局部時間，例如：

```text
0.396s
```

通常只是 SaveImage 節點時間，不是整體生圖時間。

總時間可查：

```bash
docker logs comfyui-spark --since 30m 2>&1 \
  | grep -E 'Prompt executed in|loaded completely|loaded partially|Requested to load'
```

---

# 12. Swap

系統 Swap：

```text
/swap.img
```

大小：

```text
16 GiB
```

`/etc/fstab`：

```text
/swap.img none swap sw 0 0
```

已啟用：

```bash
sudo swapon /swap.img
```

確認：

```bash
swapon --show
free -h
cat /proc/swaps
```

目前 Swap 定位：

```text
短暫記憶體尖峰緩衝
不是模型常態記憶體
```

現階段 16 GiB 足夠。

不要隨意執行：

```bash
swapoff -a
```

---

# 13. 已知警告

以下警告目前多數非致命：

```text
pynvml deprecation
PyTorch capability 12.1 vs binary max 12.0
Crystools 無法正確顯示 UMA GPU memory
舊 ComfyUI Manager blocked
ComfyUI-Ollama node 存在但無 Ollama
SyntaxWarning
rgthree Node 2.0 warning
```

AEON image 依賴：

```text
PTX forward JIT
SageAttention sm_121a
DynamicVRAM
async offload
```

ComfyUI UI 中 GPU / VRAM 可能顯示 0，屬於 UMA 監控限制，不代表 GPU 沒使用。

---

# 14. 操作禁忌

```text
不要加 runtime: nvidia
不要為 GPU runtime 調整而重啟 Docker
不要新增 Ollama sidecar
不要下載 AEON 約 285 GB 全模型 bundle
不要把 Personal FLUX 模型放進 Work
不要把 Work 與 Personal 合併 workspace
不要把 API Key / HF Token 寫進文件或 Git
不要把 NVFP4 Text Encoder 用於正式 Qwen-Image Work
不要輕易刪除 cache，模型可能以 hardlink 方式共用 inode
不要隨意 swapoff -a
```

---

# 15. 常用操作

## 查看狀態

```bash
gb10 status
gb10 doctor
```

## 使用 27B

```bash
gb10 use 27b
```

## 使用 35B

```bash
gb10 use 35b
```

## 啟動 Work

```bash
gb10 start comfyui-work
```

## 啟動 Personal

```bash
gb10 start comfyui-personal
```

## 重啟 Work

```bash
gb10 restart comfyui-work
```

## ComfyUI Log

```bash
docker logs -f comfyui-spark
```

## ComfyUI 健康檢查

```bash
curl -fsS http://127.0.0.1:8188/system_stats
```

## ComfyUI 模型索引

```bash
curl -fsS http://127.0.0.1:8188/object_info | jq
```

## Container 掛載確認

```bash
docker inspect comfyui-spark \
  --format '{{range .Mounts}}{{if eq .Destination "/workspace/ComfyUI"}}{{.Source}} -> {{.Destination}}{{end}}{{end}}'
```

## vLLM API

```bash
curl -fsS http://127.0.0.1:1234/v1/models
```

## 記憶體

```bash
free -h
swapon --show
```

## 容器資源

```bash
docker stats --no-stream aeon-vllm comfyui-spark
```

---

# 16. 部署完成狀態

目前已完成：

```text
[OK] Docker / Compose
[OK] GPU container
[OK] vLLM 27B
[OK] vLLM 35B profile
[OK] Runtime Manager
[OK] Work / Personal 隔離
[OK] ComfyUI Work
[OK] ComfyUI Personal
[OK] Hugging Face Token 注入
[OK] Qwen-Image-2512 Work 模型
[OK] Qwen-Image FP8 Scaled Text Encoder
[OK] Qwen-Image Lightning LoRA
[OK] FLUX.2 Klein 9B Personal 模型
[OK] Work Quality 生圖
[OK] Work Fast 生圖
[OK] Personal Distilled 生圖
[OK] 27B + ComfyUI 共存
[OK] 16 GiB Swap
```

---

# 17. 尚未完成／可後續改善

```text
1. 將 Work workflow 正式另存為 Quality / Fast 兩份
2. 將 Personal workflow 正式另存為 Distilled 命名
3. 清理或封存 NVFP4 Text Encoder
4. 評估是否加入 Work 用 FLUX.1 Schnell
5. 建立固定 benchmark：
   - 冷啟動時間
   - 第二張時間
   - Peak RAM
   - Swap 使用量
   - Qwen3.6-27B latency 影響
6. gb10 status 的 Active runtime 區塊目前偏向只顯示 LLM
7. 未進行 35B + ComfyUI 壓力測試
8. 未進行 5 併發 + 256K Context + ComfyUI 的正式壓力測試
9. 未建立自動化 workflow backup / version control
10. 未建立模型 manifest 與 SHA256 完整清單
```

---

# 18. 下一位 AI 接手建議

接手時先執行：

```bash
gb10 status
gb10 doctor
free -h
swapon --show
docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Image}}'
```

再依目標確認：

```text
LLM 問題
→ 檢查 aeon-vllm stack

Work 生圖
→ gb10 start comfyui-work

Personal 生圖
→ gb10 start comfyui-personal
```

若 Work 再出現提示詞完全不相干的圖片，第一個檢查點：

```text
clip_name 是否誤切回 qwen_2.5_vl_7b_nvfp4.safetensors
```

正確值應為：

```text
qwen_2.5_vl_7b_fp8_scaled.safetensors
```

---

# 19. 最終結論

目前 GB10 已形成一套低耦合、可切換、可交接的本地 AI 架構：

```text
vLLM 負責本地 LLM
ComfyUI Work 負責正式企業生圖
ComfyUI Personal 負責私人研究生圖
gb10 僅負責 Runtime 操作便利性
Compose 保留真正部署主權
```

目前整體部署可視為：

```text
功能完成
服務可用
Work / Personal 可切換
LLM / ComfyUI 可共存
後續進入效能優化與流程固化階段
```
