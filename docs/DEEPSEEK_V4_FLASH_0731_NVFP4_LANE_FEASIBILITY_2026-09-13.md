# DeepSeek-V4-Flash-0731 NVFP4 併行路線可行性調查（2026-09-13）

> 範圍：`nvidia/DeepSeek-V4-Flash-0731-NVFP4`（NVFP4 權重）作為現役 `gb10 use deepseek`
> 以外之獨立路線（`gb10 use deepseek-nvfp4`）的可行性調查。核心問題：**有無可直接 pull 部署的
> 獨立成熟 SGLang / vLLM docker image**。調查不限於 Anemll 0.1.1 配方與 image，擴及 HF 模型卡
> /discussion 與 NVIDIA 官方 DGX Spark/GB10 論壇、GitHub。
>
> 結論摘要：**2x GB10 上沒有「可 pull 的獨立成熟 SGLang/vLLM image」能服務 NVFP4 權重**；
> 唯一可 pull 的 Anemll 0.1.1 就是現役路線（官方 0731 FP8 權重 + `nvfp4_ds_mla` KV）——
> NVFP4 在 Anemll 語境是 KV 格式、不是權重。全部 NVFP4 權重實跑實例都是本地 fork build +
> patch mount（SM121 compile），非 pull-able。追蹤政策見文末 §7。

## 1. 語義澄清：Anemll 的「NVFP4」＝ KV，NVIDIA 的「NVFP4」＝ 權重

- `ghcr.io/anemll/dspark-vllm-gx10:0.1.1` 的 `kv_cache_dtype=nvfp4_ds_mla` = **4-bit MLA
  KV cache 格式**（584-byte packed sparse-MLA envelope），權重仍是 FP8（官方 `deepseek-ai/
  DeepSeek-V4-Flash-0731`，`QUANTIZATION=none`）。這是 Anemll 標準設計，也是現役
  `cluster-profiles.d/deepseek.conf` 的部署內容。
- `nvidia/DeepSeek-V4-Flash-0731-NVFP4`（HF，Model Optimizer v0.46.0）＝ **權重量化版**：
  僅 quantize routed MoE experts（`expert_dtype: fp4`、`quant_method: fp8`、ignore attn/
  shared_experts/head/mtp），DSpark heads 未量化；被驗證平台為 B200（SGLang 與 vLLM），非 GB10。

## 2. 四條候選路線逐一排查

| 路線 | 內容 | 結論 |
|---|---|---|
| **SGLang** cookbook（`sgl-project/sglang#37479`，2026-09-01 merged） | DGX Spark（2x GB10）recipe 用**官方 FP4 checkpoint** + `lmsysorg/sglang:dev-v4f-2dgx`（DGX Spark-only preview，bake SM12x b12x MoE W4A8 + compressed-MLA，ctx 327680、mem 0.80、32 slots、GSM8K ~224 tok/s） | 非 NVFP4 權重；preview 非成熟；text-only |
| **vLLM 官方（upstream）** | 0.26.0 在雙 GB10 A/B 實測後 rollback：無 `nvfp4_ds_mla`（最佳僅 `fp8_ds_mla` → KV pool 小 27.3%、ctx ceiling 高 2.6% 頁差）、SM120-family DSpark sparse-MLA decode warmup crash（`sparse_mla_sm120_paged_attention` num_tokens=5 FlashInfer 拒絕）、sm_121 不在 published aarch64 wheels（→ FP4 MoE 在 published build 落回 Marlin，304B NVFP4 無法合理服務） | 無成熟上游映像可用 |
| **Anemll 0.1.1**（唯一可 pull） | `ghcr.io/anemll/dspark-vllm-gx10:0.1.1`，官方 0731 FP8 + `nvfp4_ds_mla` KV | 即現役路線；NVFP4=KV 非權重 |
| **community fork**（tonyd2wild → dkmode22） | vLLM **0.21.1rc1** fork lineage + 4 個 bind-mount patches + `TORCH_CUDA_ARCH_LIST=12.1a` 本地 build | NVFP4 權重唯一實跑處；**非 pull-able** |

## 3. NVFP4 權重實跑實例（非檢察官，是當下唯一證據）

### 3.1 dkmode22/DeepSeek-V4-Flash-0731-3.23x1M-context-653-toks-2x-DGX-Spark-GB10
- **DeepSeek-V4-Flash-0731 (NVFP4)** 於 2x DGX Spark（GB10, SM121）TP=2，max len **1,048,576**、
  4-bit MLA KV（`nvfp4_ds_mla`）、KV pool 3,386,611 tokens。峰值 list 653.2 tok/s（c=16, accept 0.96），
  mixed-kind c=12 ~310 tok/s；spec acceptance pooled 0.63 / 4.16 tok/step（k=5）。
- 權重 `~79 GiB/rank @ TP=2`（官方 0731 FP8 ~155GiB/pair → NVFP4 幾乎同大，無記憶體省）。FP4 GEMM
  於 sm_121 為軟體模擬（無原生指令集）。
- Stack：vLLM 0.21.1rc1 fork（tonyd2wild DSpark build）、torch 2.11.0+cu130、FlashInfer 0.6.12、
  nvidia-cutlass-dsl 4.5.1、SM121 compile。
- **4 個 bind-mount patches**（非 bake）：ragged-batch spec decode 修正、DSpark proposer 同構、
  chunked-prefill scheduler、**shared-expert loader fix**（12 個 w1/w3 tensors 被 draft loader 靜默
  丟棄 → 3 個 MTP stage 共用 expert 未初始化；此 patch 使 pooled acceptance 0.514 → 0.633）。
- **「0731 REQUIRES Patch-4 loader fix」**：不修，官方 0731 checkpoint acceptance 崩到 ~0.14
  （比 preview 受害更重）。
- 4 patches 已 upstream ≥ 0.26.0；但 NVFP4 路線仍離不開 0.21.1rc1 fork，原因：上游缺
  `nvfp4_ds_mla`（會 27.3% 縮 KV pool）＋ SM120 sparse-MLA warmup crash。
- Env 提示（適用於本 fork）：`VLLM_USE_B12X_MOE=1` 為加速旗標；`VLLM_USE_BREAKABLE_CUDAGRAPH=0`；
  絕不 `VLLM_USE_V2_MODEL_RUNNER=1`；**絕不啟 `VLLM_USE_B12X_FP8_GEMM`**（DeepGEMM layout assert
  於 drafter warmup —— 此即 DSpark draft 量化 config 繼承問題的直接面）。

### 3.2 tonyd2wild/DeepSeek-v4-Flash-0731-DSpark-1M-NVFP4-KV-2x-DGX-Spark
- 自包含兩節點 vLLM recipe：TP=2、DSpark、`nvfp4_ds_mla` KV、1M context（experimental 至 1.5M）。
- 用官方 `deepseek-ai/DeepSeek-V4-Flash-0731`（或 unsloth 整合）**非 NVFP4 權重**；Patch 4
  提升 acceptance 25.7% → 60.2%、mean tok/s 32.7 → 55.4。→ 此路線屬 KV-NVFP4，不是權重 NVFP4。

### 3.3 HF discussion #2（nvidia/DeepSeek-V4-Flash-0731-NVFP4，takashito，2026-09-13 開啟）
- 模型卡明言「speculative decoding 未於此 checkpoint 驗證」。於 2x RTX PRO 6000 Blackwell（TP=2,
  vLLM v0.29.0, no patches）：as-shipped 時 DSpark 幾乎無效。
- **Root cause**：主模型 routed experts 為 NVFP4，但 DSpark experts（`mtp.0/1/2`）仍是 MXFP4，
  且 `hf_quant_config.json` 排除 `mtp.*`；vLLM 載入後 tensor 改名 `layers.43+` → 排除失配 →
  vLLM 把 MXFP4 draft experts 錯讀為 NVFP4。不 crash，但 drafts 幾乎全拒（accept length 1.4–1.5）。
- **Lossless fix**：Model-Optimizer `--cast_mxfp4_to_nvfp4`（draft experts MXFP4→NVFP4）+ 移除
  `mtp.*` 排除。6 億 blocks bit-exact；僅 shards 46–48 + 3 JSON 變（+11GB）。效果：1 req
  98.5→212 tok/s（2.1x）、4 req 264→415 tok/s、accept length 3.1–3.7；IFBench 79.0 vs 卡片 75.5。
- NVIDIA 已在 `nvidia/DeepSeek-V4-Flash-nvfp4-DSpark` 出預轉換版（draft 也用 NVFP4）。
- 驗證平台為 RTX PRO 6000 / B200，**非 GB10**；但此 fix 與 §3.1 的 `VLLM_USE_B12X_FP8_GEMM=Off`
  為同一問題的兩面（checkpoint 層修 vs environment 層繞）。

### 3.4 NVIDIA 官方論壇 thread 378824（DeepSeek-V4-Flash-0731-DSpark-1M-NVFP4-KV-2x-DGX-Spark）
- 確認 DSpark draft **繼承 target 的 NVFP4 config**；trunk experts 打包 NVFP4（uint8）、
  MTP/DSpark expert blocks 為 FP8-style int8 + UE8M0 scales → 需 vLLM PR #49133 類修法
  （draft MoE backend `b12x` alias in spec config）。

## 4. 為什麼「不建議現在建」NVFP4 權重併行路線（Tier 2）

1. **沒有可 pull 的獨立成熟映像**。Anemll 0.1.1（唯一 pull-able）= 現役 FP8 路線；SGLang DGX
   Spark 映像跑官方 FP4；NVFP4 權重唯一實跑 = 單一維護者 fork build + bind-mount patches。
2. **GB10 上無可量測優勢**。NVFP4 權重 ≈ FP8 大小（~79 vs ~77.7 GiB/rank）；FP4 GEMM 在 sm_121
   為軟體模擬，無原生加速；真正效能槓桿是 KV cache —— 現役已取得 `nvfp4_ds_mla`。
3. **額外風險疊加**。NVFP4 checkpoint 帶 `mtp.*` exclusion 失配坑（§3.3/§3.4），須轉換或
   特化 env byte 繞；fork 維護依賴第三方程式碼線。
4. 論壇共識（懷疑方）：NVFP4 權重比官方 FP8 約大 1%，無記憶體/時間收益 —— 主要在改 KV 密度
   而非權重。NVIDIA ModelOpt 此版「權重之路」不改變 GB10 的執行面軟肋。

## 5. 對現役路線的提示（未被動消耗）

- 現役 = 官方 0731 FP8 + Anemll 0.1.1。dkmode22 強調「0731 REQUIRES shared-expert loader
  fix」；該 4 patches 已 upstream ≥ 0.26.0，Anemll 0.1.1（vLLM 0.27.x omni 系）**很可能已含**，
  但現役 DSpark acceptance 從未量測驗證。
- 便宜驗證方式（僅當未來要動手時）：`vllm:spec_decode_num_{accepted,draft}_tokens_total` 對照
  pooled ~0.63 基準。Tier 1 政策 = 不主動動手，等待 Anemll 新版本成熟 image（見 §7）。
- 協議坑（寫 smoke/bench 時）：`reasoning_content` 於此協議已 deprecated 恆空 → 讀
  `message.reasoning` / `delta.reasoning`。

## 6. 追蹤信號（3 條獨立線）

| 代號 | 追蹤標的 | 動作觸發 |
|---|---|---|
| (a) | **Anemll `dspark-vllm-gx10` 新 release/tag image**（0.1.1 為最新；main 已合 PR #2 DSpark SWA prefix-cache fix 但未發 image） | 成熟新 image 發布 → 才評估升級並考慮量測 acceptance；否則不動 |
| (b) | **上游 vLLM** 三條件：`nvfp4_ds_mla` + SM120-family DSpark sparse-MLA decode fix + sm_121 進 published aarch64 wheels | 三者全落地 → 重估現役線是否移出 Anemll |
| (c) | **SGLang `lmsysorg/sglang:dev-v4f-2dgx` 成熟度 + NVFP4 權重涵蓋度**（現為官方 FP4） | 若開始涵蓋 NVFP4 checkpoint → 成為可 pull 之 NVFP4 路線候選 |

Tier 1 併入 (a)；Tier 2 併入 (c)。重估 Tier 2 的獨立觸發：上游三條件 / NVIDIA 出
GB10-validated NVFP4 image / SGLang NVFP4 涵蓋。

## 7. 追蹤政策（月檢，下次檢查 ~2026-09-30）

```text
Do-nothing default：現役 deepseek lane（Anemll 0.1.1，官方 0731 FP8 + nvfp4_ds_mla KV）原地不動。
月檢內容：
  (a) anemll/dspark-vllm-gx10 tags/releases 是否有 >0.1.1 之新 image（含 PR #2 是否發佈）
  (b) vLLM 上游是否落地 §6 三條件（nvfp4_ds_mla / SM120 fix / sm_121 wheels）
  (c) sglang dev-v4f-2dgx 是否仍為 preview、是否擴及 NVFP4 權重
僅在任一觸發成立時進入評估；不成立的月份只記錄「未觸發」。
```

## 8. 來源清單

```text
Anemll        github.com/Anemll/dspark-vllm-gx10（v0.1.1；issues #1/#3/#8/#9/#10/#11；PR #2）
NVIDIA 模型   huggingface.co/nvidia/DeepSeek-V4-Flash-0731-NVFP4（Discussion #1/#2）
NVIDIA 兄弟    huggingface.co/nvidia/DeepSeek-V4-Flash-nvfp4-DSpark
NVFP4 實跑    github.com/dkmode22/DeepSeek-V4-Flash-0731-3.23x1M-context-653-toks-2x-DGX-Spark-GB10
KV-NVFP4      github.com/tonyd2wild/DeepSeek-v4-Flash-0731-DSpark-1M-NVFP4-KV-2x-DGX-Spark
NVIDIA 論壇    forums.developer.nvidia.com thread 378824
SGLang        sgl-project/sglang#37479（merged 2026-09-01）；lmsysorg/sglang:dev-v4f-2dgx
vLLM 部落格   vllm.ai/blog/2026-06-01-vllm-dgx-spark
```