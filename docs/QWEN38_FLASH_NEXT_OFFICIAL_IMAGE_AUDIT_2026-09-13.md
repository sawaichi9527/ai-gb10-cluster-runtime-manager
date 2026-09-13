# Qwen3.8-Flash-Next 官方 Image 審計（2026-09-13）

只讀研究定調：**現役官方 `vllm/vllm-openai:qwen38-flash-next` tag 仍不能跑官方 NVIDIA NVFP4 權重**，本輪不動 engine / image / profile，採每週手動 diff 追蹤。

## 1. 結論

```text
· 官方 tag 自 2026-08-26 後未更新：Hub tag API last_pushed = 2026-08-26T13:04:07Z（vllmbot），
  manifest-list digest = sha256:fc120ece0a388cc0aa1caad4a9f1cd92113484ab7ec2fd0efadd62585be05bf8
  至 2026-09-13 不變。本週沒有新版。
· 兩節點本地 image CREATED = 2026-08-26T09:14:37.44811988Z，與 tag push 一致，確認為同一顆來源。
· 內建 vLLM 為舊樹：vllm/models/qwen3_8_flash_next/（§24 plefix patch 之目標路徑）。
  上游 2026-09-13 已全數改名 qwen4_exp（search_code qwen3_8_flash_next → 0 hits）。
· 官方 NVIDIA NVFP4 model card 要求 vLLM > d4d703caf…：
    d4d703caf908786416585ceb1f369e2e0363358b = PR #54882
    [Bugfix][Model] Fix FP8 PLE loading in mixed ModelOpt checkpoints（2026-09-03，sychen52）
  → 該修補比 08-26 image 晚一週，現役官方 tag 不含。
· 因此官方 tag 直接跑 Nvidia/Qwen3.8-Flash-Next-NVFP4 仍會踩 §24 crash #3（PLE selector /
  MIXED ModelOpt config）與 crash #4（MTP experts w2_weight_scale_inv）同一領域。
```

## 2. 各 crash 的上游修復對照

```text
crash #3  PLE FP8 selector 只認 Fp8Config / ModelOptNvFp4Config，實際收到 ModelOptMixedPrecisionConfig
          → 上游修復 = #54882 (d4d703caf, 2026-09-03)。
crash #4  MTP experts 缺 w2_weight_scale_inv（draft MoE scale 未載入）
          → 上游 v0.29.0（git tag 指向 commit 98dff2a8…, 2026-09-08）於架構層修復：
          Qwen4ExpMTP 繼承 Qwen4ExpMixtureOfExperts（真實 MoE base）+ get_draft_quant_config /
          configure_quant_config(_, Qwen4ExpMTP) / set_moe_parameters(self.model.layers) /
          _remap_ignored_layers（excluded/ignored → mtp 層），並以 _remap_mtp_weight_name
          （mtp.→model.、shared_head.head.→lm_head.）載入權重。
          w2_weight_scale_inv 為 ModelOpt loader 在 process_weights_after_loading 時動態掛上
          （deep_gemm_warmup 以 hasattr 判斷、test_quark 斷言 quant 未套用時不存在）。
```

## 3. 每週追蹤程序（使用者自行執行）

```text
# Node0/Node1 任一：
docker manifest inspect vllm/vllm-openai:qwen38-flash-next
  → 對比 manifest-list digest 是否仍為 sha256:fc120ece…
# 或 Hub API：
curl -s https://hub.docker.com/v2/repositories/vllm/vllm-openai/tags/qwen38-flash-next \
  | python3 -c 'import sys,json; d=json.load(sys.stdin); print(d["last_pushed"], d["digest"])'
  → last_pushed 與 digest 雙異動才代表可能內建 fix（需 ≥ d4d703caf / v0.29.0）
```

觸發條件（重新評估 boot）：

```text
· 官方 tag digest != fc120ece… 且 last_pushed > 2026-08-26；再驗證 image 內 vLLM 是否達
  v0.29.0（含 qwen4_exp tree）與 #54882。
· 或上游有官方發行之 >= d4d703caf 的可 pull 標籤（非僅 nightly）。
```

## 4. node1 Image ID 語意（2026-09-13 釐清）

先前質疑「node1 image ID fc120ece… = manifest-list digest 別名，可能另一平台/未完全解析」——**收回**。實查結論：

```text
· node1 = containerd snapshotter（docker info：Storage Driver overlayfs,
  driver-type: io.containerd.snapshotter.v1, containerd dea7da59…）
  → docker images 的 ID 欄直接顯示 content digest（相等於 RepoDigest）；
  而 node1 所有 image 的 ID 皆恰等於各自的 digest（2421bb…/04bb42…/107590…），行為一致。
· node0 = classic overlay2 → ID = config digest（真實 image ID），與 RepoDigest 不同；
  arm64 config digest = sha256:d464f3b466fa… 恰等於 node0 顯示的 qwen38-flash-next ID d464f3b466fa。
· 兩節點同 RepoDigest sha256:fc120ece…、同 arm64 platform、同 CREATED 2026-08-26T09:14:37Z。
· 30.6GB（node1）/ 20.6GB（node0）差異 = overlay2 vs containerd 的 image 層計量方式，非內容不同。
· 結論：node1 平台正確、cache 正確，不需要 re-pull。
```

## 5. 舊 image 清理紀錄（2026-09-13 執行）

清理前兩節點 `docker ps -a` 均無 container；移除後 `docker images` 複核。

### 移除（使用者指定清單）

| image | node0 | node1 |
|---|---|---|
| ghcr.io/aeon-7/aeon-vllm-ultimate:2026-09-07-reasoning-eos | 18.8GB | 19.3GB |
| ghcr.io/aeon-7/aeon-vllm-ultimate:2026-08-24-v0.27.1-omni | 18.8GB | 19.3GB |
| lmsysorg/sglang:nightly-cu134-20260903-429ac2d | — | 45.5GB |
| lmsysorg/sglang:v0.5.18-cu130 | — | 44.6GB |

合計回收：node0 ≈ 37.6GB、node1 ≈ 128.7GB。

### 保留

```text
node0 (8)：
  aeon-vllm-ultimate:2026-09-11-v0.29.0-omni  52.3GB（現役 TP2 27b/35b）
  aeon-vllm-ultimate:2026-08-16-v0.27.1       50.6GB（rollback 用）
  vllm/vllm-openai:qwen38-flash-next          20.6GB（每週 diff 留底）
  anemll/dspark-vllm-gx10:0.1.1               18.8GB
  comfyui-aeon-spark:slim                     16.8GB（Node0 保留＝使用者決策）
  busybox:latest                               4.2MB
  nvcr.io/nvidia/cuda:13.0.1-base             415MB
node1 (8)：
  aeon-vllm-ultimate:2026-09-11-v0.29.0-omni  74.6GB（現役）
  minimax-h3-sglang:429ac2d-cu134-ffmpeg      45.8GB
  minimax-h3-sglang:429ac2d-nvfp4             59.2GB
  minimax-h3-dgx-spark:sm121-fp8              32GB
  vllm/vllm-openai:qwen38-flash-next          30.6GB
  anemll/dspark-vllm-gx10:0.1.1               38GB
  comfyui-aeon-spark:slim                     26.7GB（現役）
  nvcr.io/nvidia/cuda:13.0.1-base             560MB
```

## 6. 相關連結

- handoff.md §37；§24（qwen38flash 中止紀錄，crash #1–#4）
- §24 plefix 資產：`docker/qwen38flash-plefix/`（08-26 image patch，於 v0.29 已過時）
- commit d4d703caf… = github.com/vllm-project/vllm PR #54882
- upstream v0.29.0 `vllm/models/qwen4_exp/nvidia/mtp.py`（crash #4 架構層修復）