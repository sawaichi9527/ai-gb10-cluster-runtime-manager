# 客戶端多模態能力宣告（`aeon` 統一 id）— 2026-11-26

> 起因：切到 `deepseek-vision`（`deepseek-v4-flash-vision-exp-ablit`）後，前端 **dsh** 讀取
> PowerPoint 簡報圖時仍走 **OCR 轉文字**，追問後 dsh 回答「**aeon 沒有宣告 image input 能力**」。
>
> 結論先講：**dsh 是對的，而且這不是 aeon 的設定漏了什麼** —— OpenAI 相容協定沒有任何
> 能力欄位，三個實際使用的 client（dsh / OpenCode / hermes-agent）**都不會向 endpoint 查詢
> 能力**，能力必須在 **client 端宣告**。伺服器端改 `/v1/models` 對這三者是零效果。

## 1. 為什麼 server-side 宣告無效（三個硬事實）

| # | 事實 | 證據 |
|---|---|---|
| 1 | vLLM 的 `/v1/models` 從來沒有 capability/modality 欄位 | vLLM v0.10.2 `entrypoints/openai/serving_models.py` 只回 `id / object / created / owned_by / root / parent / max_model_len / permission`；main 分支的 `ModelCard` 相同 |
| 2 | 三個 client 都不查 endpoint | dsh 原始碼註解：**"nothing can interrogate a gateway for its modalities"**，`DEFAULT_INPUT = ["text"]`；OpenCode 的 `modalities` 在 config schema；hermes 走 models.dev catalog 或 `supports_vision` |
| 3 | client 在**送出前**就把圖擋掉 | dsh 文件：**"Under-claiming refuses the image before it is attached, naming the model."** 圖片位元組從未離開 client → 任何 server 端補救都無法讓它出現 |

第 3 點是關鍵：這不是「伺服器回錯」，而是「請求根本沒帶圖」。因此，
**patch image、加 served name、加 gateway 注入 capability，都無法讓 dsh 使用視覺。**

實測（2026-11-26，node0 `:1234`，當時在線為純文字 DeepSeek lane）：

```json
POST /v1/chat/completions  (128×128 PNG, "What single capital letter is shown?")
-> 400 {"message":"aeon is not a multimodal model","type":"BadRequestError","code":400}
```

`GET /version` = `0.1.dev21830+g8244d1c44.d20261102`（b12x `nightly-20261102`）；
`GET /health` = 200。也就是說：lane 本身正常，只是**該 lane 真的沒有視覺**。

## 2. 三個 client 的宣告面（一次性設定，之後切 lane 不用再動）

因為對外 id 永遠是 `aeon`，宣告綁在 **endpoint/模型 id** 上，與 lane 無關。

### 2.1 dsh（`@deepseek-ai/dsh` 0.2.2-rc.5）

- 真正生效的檔案是 **profile patch layer**：`~/.dsh/profiles/<profile>/cordis.patch.yml`。
- 自 0.2.2 起，舊的 `~/.dsh/settings.yaml` 會被遷移並改名為 `settings.yaml.imported`
  （**死檔，改了沒用**；`dsh-settings` 會把 section 併進 profile 後 rename）。
- 宣告位置（`llm-pi-ai` provider）：優先序 = model `input` → pi-ai 內建 catalog →
  route `defaultInput` → `["text"]`。

```yaml
- id: llm-pi-ai
  config:
    providers:
      aeon-vllm:
        api: openai-completions
        baseURL: http://<node0>:1234/v1
        models:
          - id: aeon
            name: aeon
            input: [text, image]     # ← 必要
```

- **能力字彙只有 `text | image`**：`pi-ai` 的 `ModelInputModalitySchema = "image" | "text"`，
  寫 `input: [text, audio]` 會被 schema 拒絕。
- 驗證：`dsh --profile <name> --dump-config` 應看到 `input: [text, image]`。

### 2.2 OpenCode

`~/.config/opencode/opencode.jsonc`（`providers.<provider>.models.<id>`）：

```jsonc
"aeon": {
  "name": "Aeon",
  "modalities": { "input": ["text", "image"], "output": ["text"] }
}
```

- Schema 的 `modalities.input` enum 是 `text | audio | image | video | pdf`
  （`https://opencode.ai/config.json`）。
- 另有 per-model 布林 `tool_call` / `reasoning` / `attachment`；未設通常即開啟，
  **不需要為 aeon 加**（多寫只是多一個漂移點）。

### 2.3 hermes-agent（NousResearch）

- 能力來源是 provider metadata / **models.dev**；custom endpoint 不在 catalog 時，
  用單一旋鈕 `model.supports_vision: true`（或 `providers.<name>.models.<id>.supports_vision`）。
- 另有 `agent.image_input_mode: auto | native | text`；`native` 可強制送像素。
- 它對「OpenCode 模型 id 帶 `-vision`」有內建 heuristic，但 `aeon` 不帶，所以仍需宣告。

## 3. lane 能力矩陣（同一 id `aeon`，能力隨 lane 改變）

| lane | image | video | audio | tools | reasoning |
|---|---|---|---|---|---|
| `27b` / `35b` | ❌ | ❌ | ❌ | ✅ `qwen3_coder` | ✅ `qwen3` |
| `deepseek` | ❌ | ❌ | ❌ | ✅ `deepseek_v4` | ✅ thinking on |
| `deepseek-vision` | ✅ ×8 | ❌ | ❌ | ✅ | ✅ |
| `deepseek-nvfp4` | ❌ | ❌ | ❌ | ✅ | ✅ |
| `qwen38flash` | ✅ | ❌ | ❌ | ✅ `qwen3_coder` | ✅ `qwen3` |
| `qwen38flash-tensorfold` | ✅ | ❌ | ❌ | ✅（但拒絕 `response_format`/`guided_*`/`logprobs`/`n>1`） | ✅ on |
| `mimo26flash` | ✅ ×16 | ✅ ×1 | ✅ ×4 | ✅ `mimo` | ✅（預設 off） |
| `dsv41flash-exl3-vllm` | ✅ | ? | ❌ | ✅ | ? |
| `dsv41flash-tensorfold` | ✅ | ? | ❌ | ✅ | ? |

→ 所以 `aeon` **不存在單一能力真相**：宣告 image 是「視覺 lane 在線時正確、純文字 lane 在線時
會失敗」。這是統一 id 的固有代價。

## 4. 這次實際做的改動（client-only）

| 位置 | 改動 | 狀態 |
|---|---|---|
| dsh `~/.dsh/profiles/web/cordis.patch.yml` | `aeon` 加 `input: [text, image]` | ✅ 已改，`--dump-config` 驗證 |
| OpenCode `~/.config/opencode/opencode.jsonc` | `aeon` 加 `modalities` | ✅ 已改 |
| hermes-agent `~/.hermes/config.yaml` | `model.supports_vision: true` | ⬜ 未做（機器不在本機） |

**node0 / lane / repo 的 runtime 設定完全未動。**

## 5. 工具調用與音頻：不能與 image 一起宣告

| 能力 | dsh | OpenCode | hermes |
|---|---|---|---|
| tools | **不 gate**；`compat` 只改請求形狀（`supportsStrictTools`、`requiresToolResultName`…） | 有 `tool_call: boolean` | 不 gate（agent loop 常開） |
| audio | **不是 modality**（schema 只有 text/image）→ 走 STT 外掛轉文字 | `modalities.input` 可含 `audio` | voice/STT 外掛 |

→ 對這三個 client，**只有 image 值得處理**；`audio`/`video`/`tools` 的多維度宣告在此沒有
消費者（留給未來 gateway / Codex 型 client）。

## 6. 未完成與後續選項

**(a) 視覺 lane 驗證**（卡在當時在線的是純文字 lane）

- 切 `gb10 use deepseek-vision` → dsh 貼圖 → node0 vLLM log 的 `prompt_tokens` 每張圖
  +300~400，且回覆描述圖面（不再 OCR）。

**(b) 純文字 lane 的 over-claim 失敗**（dsh 不會自動降級）

- 選項 1（建議）：在**兩個純文字 image**（`eugr/spark-vllm-b12x:nightly-20261102`、
  `aeon-vllm-ultimate:2026-09-18-v0.29.0-omni`）加 fail-closed hotfix：把不支援的
  `image_url` 換成明確佔位文字（例：`[image omitted: the active lane has no vision input]`），
  而不是 400。env-gated、預設關閉，vision lane 不動。
- 選項 2：保留 400，切到純文字 lane 時 client 端不要送圖（回到「每次要記得」）。
- 選項 3：視覺 lane 增加第二個 id `aeon-vision`，client 設定兩個 entry；語意正確但要切 id
  （TensorFold 引擎的 id 寫死，做不到）。

**(c) 契約定案**

- 目前契約：`aeon` = **文字保證**；影像能力**需 client 宣告**，且**依在線 lane 而定**。
- 若接受 (b) 選項 1，則 `aeon` 可升級為「永遠接受 image」：視覺 lane 原生處理，
  純文字 lane 明確回報看不到圖 —— 這才是真正「設定一次、永久被動」。

## 7. 引用錨點（未來查證用）

- vLLM `ModelCard` 欄位：`vllm/entrypoints/openai/engine/protocol.py`
- vLLM 錯誤字串：`<served-name> is not a multimodal model`（multimodal registry / serving_chat）
- dsh：`node_modules/@deepseek-ai/dsh-llm-pi-ai/lib/index.js`（`DEFAULT_INPUT`）、
  `docs/config-catalog.md`（`PiAiModelProfile.input` / route `defaultInput`）、
  `docs/subsystems/voice-input.md`（audio 走 STT）
- pi-ai：`dist/providers/model-schema.d.ts`（`ModelInputModalitySchema = "image" | "text"`）
- OpenCode：`https://opencode.ai/config.json`（`modalities` / `tool_call` / `reasoning`）
- hermes：官方 Vision & Image Paste 文件（`supports_vision`、`image_input_mode`、models.dev）
