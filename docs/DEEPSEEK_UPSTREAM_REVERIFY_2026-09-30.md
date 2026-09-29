# DeepSeek / DeepSeek-Vision 上游再查核（2026-09-30）

> 觸發：使用者要求確認「cluster 運行的 `deepseek` 與 `deepseek-vision` 的來源配方與
> docker image 是否有更新」。**結果：皆無有效更新 —— 兩 lane 的 image、配方、官方權重
> 全部維持現狀，現行 pin 即為最新。** 本次只做唯讀查核，**未變更任何 runtime/profile/檔案設定**
> （唯一變更是本紀錄文件）。

## 一、查證基準（現行 pin）

| lane | image | `IMG_SHA256`（manifest） | 權重 pin |
|---|---|---|---|
| `deepseek` | `ghcr.io/anemll/dspark-vllm-gx10:0.1.1` | `sha256:a83948492cf13df455170fb42885f5ef4db54fefe0feff0f841ecbff464ac9d8` | 官方 0731 release commit `9e165c306e…`（`deepseek-v4-flash-0731-official`，Weschera gate `9ab9b79d…`） |
| `deepseek-vision` | 同上（同一顆 image / digest） | 同上 | `deepseek-v4-flash-vision-exp` = HF `main` HEAD `6821d6ad…`；vision 支援由 vendored patch（MiaAI `97e8733…`）於啟動時注入 |

兩 lane **共用同一顆 image**；vision lane 的差異全在 `CMD_WRAPPER` + `patches/dspark-vision/`（in-repo，read-only mount）。

## 二、Docker image — 無更新

- GHCR `ghcr.io/anemll/dspark-vllm-gx10` `tags/list`：只有 **`0.1.0`、`0.1.1`**，無 `0.2.0`/`latest`/`main`/`dev`。
- tag **`0.1.1` digest 仍為 `sha256:a8394849…`**（＝本 repo `IMG_SHA256`，**逐字相同**）→ 未重新推送、無新 image。
- **node0 現役確認**：`cluster-node0` 執行 `ghcr.io/anemll/dspark-vllm-gx10:0.1.1@sha256:a8394849…`，與 profile pin 完全一致（09-30 實機 `docker ps` + `docker image inspect .RepoDigests`）。

## 三、vision 配方（`MiaAI-Lab/DeepSeek-v4-Flash-DSpark-2x-DGX-Spark`）— 無更新

- vendored commit **`97e8733238f81f5fdc44b241f8996a7858825744`**（2026-09-16）＝ upstream `main` 目前 HEAD（`compare(97e8733…HEAD)` **ahead 0 / behind 0**）。
- 上游 README **仍以 `ghcr.io/anemll/dspark-vllm-gx10:0.1.1` 為預設 image**，與本 repo 相同。
- 無需 re-vendor。

## 四、官方權重（`deepseek-ai` HF repos）— 無有效更新 ✦（本次新增查證項）

> 09-29 僅查 image 與 patch 上游，**未查官方權重**；本次補上，為主要新增證據。

### `deepseek-ai/DeepSeek-V4-Flash-0731`（deepseek lane 的 body）
- 本 repo pin commit **`9e165c30e2704aec5d9d593cce3eebd58bbef1cb`** = 官方 **「Release DeepSeek-V4-Flash-0731」** 發佈 commit。
- pin 之後 upstream `main` 僅有 **1 個 commit**：
  - `7872f01b1d1fe23eabc4c98b48bffcef5a386062` — **「add sglang cookbook to model card (#20)」（2026-08-01）** → **純 README/model card 文件變更，不碰任何 safetensors/config/tokenizer**。
- 結論：**權重未變**。我們釘在官方發佈 commit，反比追 HEAD（多一行文件腳註）更精準。**無需 update。**

### `deepseek-ai/DeepSeek-V4-Flash-Vision-Exp`（deepseek-vision lane 的 body）
- 本 repo pin **`6821d6ad3681a4b137b066b76094fa82ebd0a380`** ＝ HF `main` 目前 HEAD（**完全一致**）。
- 結論：**無更新。**

### 關於更新的同族模型（非本 lane 之更新）
- `deepseek-ai/DeepSeek-V4.1-Flash`（763B，約 2026-09 中更新）是**更新的另一款模型**，不是 0731 lane 的「更新」；其 2×GB10 EXL3 適用性已於 `docs/DSV41_FLASH_EXL3_2X_SPARK_EVAL_2026-09-29.md` 查核為**不採用**（不自行 build image 前提下僅 ~26 tok/s）。本文不予納入。

## 五、結論

| 面向 | 09-29 結果 | 09-30 再查核 | 有無更新 |
|---|---|---|---|
| Docker image | 無新 image | `0.1.1` digest `a8394849…` 不變、node0 現役同 pin | 無 |
| vision patch 上游（MiaAI） | pin = HEAD | `main` HEAD 仍 `97e8733…` | 無 |
| text 權重（0731） | （未查）✦ | pin `9e165c30` 之後僅 1 個 **docs-only** commit | 無（有效更新＝0） |
| vision 權重（Vision-Exp） | （未查）✦ | pin `6821d6ad` = HF HEAD | 無 |

**淨結果**：`deepseek`、`deepseek-vision` 兩 lane 現行 image／配方／權重皆為**當下最新且正確**。
**無需任何 profile、image、patch 或程式碼變更。** 下次檢討時點沿用「定期檢討追蹤」：每當
`patches/` 上游或 image 更新，或每次 27b/35b 重大變更時。
