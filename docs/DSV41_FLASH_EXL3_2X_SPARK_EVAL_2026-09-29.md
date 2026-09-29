# DeepSeek-V4.1-Flash EXL3 on 2× GB10 — 選型查核（2026-09-29）

> **結論：本輪不新增 lane。** 維持現役 `qwen38flash`；2-Spark 多模態路線繼續由既有
> `deepseek-vision` 承接。本文記錄查核到的兩顆**可下載 arm64 image**（含 digest）、
> TP=2 的硬限制、各線 benchmark，以及 NVIDIA 論壇的實地口碑，供日後重啟評估時直接取用。
>
> **狀態：純研究。未變更任何 runtime 檔**（`cluster-profiles.d/`、`bin/gb10`、
> `scripts/`、`AGENTS.md`、`README.md` 皆未動），未 `docker pull`、未下載任何權重、
> 未新增 profile。唯一變更是本文件與 `handoff.md` 的紀錄。

- 觸發：sfxnz 釋出的 `DeepSeek-V4.1-Flash EXL3 Viterbi 2.0bpw`
  （[CyberQ 2026-09-29](https://cyberq.tw/2026/09/29/sfxnz-deepseek-v41-flash-viterbi-20bpw/)）
  作為新 cluster profile `deepseekv41flash` 的評估。
- 前置約束（使用者指定）：**不自行 `docker build` image**；目標是可下載的成熟 image，
  最多接受 runtime patch。
- 查核日期：2026-09-29（本機中繼 checkout，Windows）。

## 1. 決策摘要

| 問題 | 結論 |
|---|---|
| 有現成可下載的 DSV4.1-EXL3 image 嗎？ | **有兩顆**，見 §2（皆已取得 digest，匿名可拉） |
| sfxnz 那顆 image 有發佈嗎？ | **沒有**。任何 registry 都查無；只有 `docker build` 配方 |
| 2× GB10（TP=2）能跑 EXL3 嗎？ | **只有 2.0bpw 級 pack 可以**；3.5bpw 級被證明不可行（§3） |
| 為何本輪不採用？ | 免 build 的成熟 image 只有 ~26 tok/s（Mia 2.9bpw）；要 42–50 tok/s 就得用 sfxnz stack＝要 build。兩者無法同時成立（§4、§5） |
| 2-Spark 多模態建議 | 維持 `deepseek-vision`（論壇多位生產使用者同結論，§5） |

## 2. 可下載 image（實測，2026-09-29）

匿名 registry probe（`auth.docker.io` / `ghcr.io` anonymous token + manifest fetch）：

| Image | Manifest digest | 定位 |
|---|---|---|
| `ghcr.io/miaai-lab/deepseek-v4.1-flash-exl3-2x-dgx-sparks:latest` | `sha256:2f0cf3adc0f989c1d446be274df864eb799630175f604c3b22b71b7205971dce` | **專為 2×GB10 / TP2 / CX7 / `sm_121a`**；EXL3 **2.9bpw / mul1**、196 GiB、39 shards；DSpark 內建於 checkpoint（無獨立 drafter）；基底 `vllm/vllm-openai:deepseekv41-flash-0909`；API `:8888` |
| `littlecedar/dgx-spark-dsv41:exl3a` | `sha256:71e23ff986f4ab58353bfd0c71062d6d256c290edca55bf7773a779f5076128d` | **TP3/TP4/TP6 reference lane**（`tonyd2wild/vllm-dsv41:exl3a` 的 retag，label `kai.exl3a=cuda-exl3-6a1ffc34`）；arm64；`ENTRYPOINT ["vllm","serve"]`；**不含** Engram-on-disk reader |
| *(旁證)* `ghcr.io/miaai-lab/glm-5.3-flash-2x-dgx-sparks:exl3-instanttensor` | `sha256:447114ee77d14c9b4732ee23978ada2a0ee9027868a231d6fd42700a8b25be1d` | 證明 MiaAI-Lab 確實會發佈 TP2 EXL3 GHCR image（GLM 線） |

同時確認（供對照）：

- sfxnz 配方基底 `vllm/vllm-openai:deepseekv41-flash-0909` 是**官方公開 tag**，arm64 digest
  `sha256:d84a123255b822fc22508635218000187221794f59c0694c33b0650d1e377d58`
  ＝其 Dockerfile `FROM …@sha256:d84a1232…` 逐字相同 → 基底可 digest 釘選。
- sfxnz 衍生 image `dsv41-flash-exl3-sm121:canonical-e14` **未發佈**；
  `sfxnz/*` Docker Hub namespace 為 0 個 repository，README 只文件化 `docker build`。
- 不可用：`ai/deepseek-v4.1-flash`（CNCF **model** manifest，510 GB，非容器）、
  `aidendle94/sparkrun-vllm-dsv41-gb10:production-1.1`（DSV4.1/GB10 但**非 EXL3**，
  b12x/DCP2 補丁集）、`erian214/dsv41-flash-sm120`（sm120，非 GB10）。

## 3. 硬限制：TP=2 在 3.5bpw 線上不可行（VERIFIED）

`littlecedar/sparkrun-recipe-registry` 的 `recipes/ds4/AGENTS.md` §3 以 cluster-RAM 預算證明
（因其 GPU 與 host 共用同一個 unified pool，故唯一無爭議的預算是 cluster 總量），並加了
`NoTP2` guard：

```
all weights (GB) <= TP_nodes × (128 − 18)        # ~110 GB usable/node
TP=2  →  220 GB
V4.1 非 Engram 權重：release 307.5 GB / EXL3(3.5bpw) ~257 GB   →  TP=2 closed
```

因此該 registry **只有 TP3/TP4/TP6 recipe，沒有 TP2**。TP=2 之可行的唯一原因是換成更小的
**2.0bpw** pack：

| pack | routed experts | 每 rank 權重 | TP=2 |
|---|---|---|---|
| MXFP4（官方） | 288.78 GB | 153.8 GB | ✗ |
| EXL3 3.5bpw | 245.4 GB | ~128 GB | ✗ |
| **EXL3 2.0bpw MCG** | **~133.6 GiB** | **~72 GiB** | **✓** |

（~72 GiB/rank 出自 `Kristianaaron/dsv41-flash-exl3-2x-spark` 的實測；該 recipe 另在 14/40
早期層加 K+1 至 ~84 GiB/rank，上限仍 <128 GiB。）

`littlecedar/dgx-spark-dsv41:exl3a` 的另一個必備件：`@littlecedar/mods/mount-dsv41-exl3-patches`
（fail-closed、md5 驗 14 檔、含 `virtual_heads.py` 與把 `hf_overrides` 傳給 DSpark drafter 的
`config_speculative.py`）。**缺它則 Engram 留在 UMA，開機約 25 分鐘後 OOM。**

## 4. Benchmark 對照（同模型、不同線）

| 線 | 節點 | 權重 | 單路 decode tok/s | 併發 agg | 證據等級 |
|---|---|---|---|---|---|
| **MiaAI `2x-dgx-sparks`** | **TP2** | EXL3 2.9bpw/mul1, 196 GiB | **~26** | — | 他人實測（論壇 `say3` 2026-09-14）+ CyberQ 對照值 |
| **sfxnz `viterbi 2.0bpw`** | **TP2** | MCG 357.5 GB | **41.3–44.9**（L.A.I.L 42.6；prose c1 50.4；structured c1 84.2） | prose c2 81.0 / structured c2 156.3 | 他人實測（CyberQ 2026-09-29） |
| `littlecedar exl3a` | TP3 | 3.5bpw | 34.3 | C4 59.1 / C8 77.7 | 實測（registry） |
| `littlecedar exl3a` | TP4 | 3.5bpw | 38.8 | C4 66.3 / C8 88.5 / C16 122.0 | 實測（registry） |
| `littlecedar exl3a` | TP4 + 1M | 3.5bpw | 40.7 | C4 65.4 / C8 84.5 / C16 121.3；needle ✓ 799K | 實測（registry） |
| `littlecedar exl3a` | TP6 | 3.5bpw | 40.0 | C4 78.0 / C8 107.9 / C16 151.1 | 實測（registry） |
| tonyd2wild | TP4 | EXL3 | 73.8（code） | C6 code agg 225.5 | 實測（repo） |

其他已記錄事實：

- **KV 幾乎免費**：V4.1-Flash 全域 KV 890 B/token、只有 4 個 `kv_source_layer_ids` 存 KV；
  1M context ≈ 0.93 GB/sequence。**瓶頸是權重，不是 KV。**
- littlecedar 自家 DBSpark **k-sweep（13 boots，TP=4）**：k∈{1,2,3} 在 C≥4 全部勝過上游預設
  **k=5**（k=1 在 C8 為 107.3，比 k=5 的 84.4 高 **+27%**）；**k=6 非法**（vLLM:
  `num_speculative_tokens` 必須是 `n_predict=5` 的因數）。故其五個 recipe 全部 ship **k=3**。
- GB10 **boot 間離散度 7–25%** → 單次開機數字不可排名；C16 為最可信欄位。
- **開機時間**：Mia 2×Spark ~25 分鐘級（論壇提到 25-min boot）；littlecedar TP4 ~12–13 分鐘
  （8 分鐘讀 460 GB checkpoint）。
- 記憶體：Mia 2×Spark 每 rank 權重 **99.5 GiB**、KV pin 2.5 GiB（774,400 tokens @600K）、
  `MAX_NUM_SEQS=2`、`MAX_NUM_BATCHED_TOKENS=1536`，長 prefill 時 `MemAvailable` 觸底約
  **2.1 GiB**（601k prompt）；性能調校必須在**長 prompt 之後**看 `MemAvailable`，不是開機後。

## 5. 論壇／實地口碑

來源：NVIDIA Developer Forums《DeepSeek v4.1 Flash》討論串
<https://forums.developer.nvidia.com/t/deepseek-v4-1-flash/382725>
（187 篇 / 28.2k views / 56 位使用者，本次抓取 topic JSON 全量過濾）。

| 使用者 | 日期 | 內容 |
|---|---|---|
| `say3` | 09-14 | Mia 2× Spark EXL3 2.9bpw → **「26 tok/s on my dual Spark setup. too slow.」** |
| `0rand` | 09-10 | **「…2-bit, not 4-bit… 2bpw is less so for any production use」**；主張 2-Spark 用 *proper vision exp* 勝過「circumsized 4.1」 |
| `stu.miller` | 09-20 | 跑生產負載（兩個 2-node cluster + tp4）：4.1 的 TP4 recipe **「hacky as f\*\*k」**、別人的 recipe **12 次都開不起來**；另明確說 DS4 Vision-Exp 在 2 sparks 上 **「works great」** |
| `helge` | 09-26 | Mia 2.9bpw 2× Spark：tool-eval-bench 對比原始權重，品質損失 **「within narrow limits」**；但「TP=4 offers a significant speed advantage」 |
| `mxjohnwong` | 09-14 | `dsv41-gb10`（aidendle94）於 4× Spark：**24h 零 crash**、TP4 ~50 tok/s code / ~40 thinking；但 **TTFT 明顯變慢** |
| `josephdrose` | 09-10 | TP4、Engram off disk、DSpark@5、eager → ~60 tps（後續 ~50）；engram 47.2 GiB/box on NVMe |
| `phyo.arkarlwin` / `0rand` | 09-10/11 | 直接結論「2-bit is not for me」 |
| `stu.miller` | 09-10 | TP3 + NVMe Engram offload + seqs=1 + vision on：「Headroom ~3–10 GiB/node. **Tight, real, workable.**」 |

## 6. 生態地圖（供日後追蹤）

- **sfxnz** — TP2 EXL3 的 canonical 配方（自行 build image）。
  - `Snail3D/dsv41-vision-2xspark`：**no image rebuild**，以 bind-mount patch 打開 vision，
    並記錄兩個 upstream bug（`sitecustomize.py` 硬編 `language_model_only=True`；
    `run.sh` 從不轉發 vision env 給 worker rank）。**需 64 GB swapfile**（權重載入峰值
    ~124 GB on 121 GB box）。
  - `Kristianaaron/dsv41-flash-exl3-2x-spark`：2× Spark，sfxnz 權重（`k2-mcg`）+ Mia 2× overlay，
    `UTIL=0.60`、DSpark k=5、KV pin 4 GiB；**K=4 在此 kit 被禁**。
- **MiaAI-Lab** — 唯一對 2× Spark 出 EXL3 且**發佈 GHCR image** 的來源。
  另有 3/4 節點 SGLang 線（`DeepSeek-v4.1-Flash-DGX-Sparks`）與 vLLM GLM EXL3 線。
- **littlecedar / sparkrun** — `sparkrun` CLI + `sparkrun-recipe-registry`（`recipes/ds4` 為
  TP3/TP4/TP6）；image 為 tonyd2wild 的 retag。另有 `aidendle94`、`verdictai` 等社群發佈者。
- **tonyd2wild** — 4-node vLLM TP4 的原始 reference（Engram-on-disk + sm121 patch + 量測）。

## 7. 若日後重啟此 lane：最短路徑

1. **免 build 首選**：`ghcr.io/miaai-lab/deepseek-v4.1-flash-exl3-2x-dgx-sparks:latest`
   （digest `2f0cf3ad…`）。用途：新 profile `deepseekv41flash`（`IMG_SHA256` 直接沿用現有
   registry gate；權重放共享池 `~/docker-stacks/models/`；stack dir 以 image 命名）。
   **預期 ~26 tok/s**，品質已被第三方（`helge`）驗為「損失有限」。
2. **要速度的探針**：驗證 Mia 2× image 能否載入 sfxnz **2.0bpw-mcg-viterbi** pack。
   EXL3 為同族格式，但 **mul1 vs mcg**、per-tensor K-map、以及 `exllamav3 v1.4.5 (e648f1a1)`
   的相容性**未知**。成功即「免 build + 44 tok/s」。**此為最高價值、但未驗證的一步。**
3. 若兩者皆不通，且仍要 sfxnz 的速度，就只能接受自行 build image（＝違反本次約束），
   或改走 `deepseek-vision`。
4. 不論哪條：**Engram 必須留在 NVMe**（`DSV41_ENGRAM_DISK=1` / row store），
   且 `MAX_NUM_SEQS` 上限為 2（`FORCE_UNSAFE_CTX` 可覆寫，但 cp=2 是量測出的上限）。

## 8. 如何重現本查核（不需 GPU、不需 docker）

```bash
# 1) Docker Hub：查 tag / 拉 image config（ENV / Labels / build history）
curl -s 'https://hub.docker.com/v2/repositories/<owner>/<repo>/tags/?page_size=50'
#    取 arm64 digest 後，向 registry-1.docker.io 換 anonymous token 抓 manifest + config blob

# 2) GHCR：anonymous pull token，無 token 代表 repo 不存在或未公開
curl -s 'https://ghcr.io/token?scope=repository:<owner>/<repo>:pull&service=ghcr.io'

# 3) 社群配方 / benchmark
#    https://github.com/littlecedar/sparkrun-recipe-registry  (recipes/README.md, recipes/ds4/AGENTS.md)
#    https://github.com/tonyd2wild/DeepSeek-V4.1-Flash-vLLM-DGX-Spark
#    https://github.com/MiaAI-Lab/DeepSeek-v4.1-Flash-EXL3-2x-DGX-Sparks

# 4) 論壇（discourse JSON，可全量過濾）
curl -s 'https://forums.developer.nvidia.com/t/deepseek-v4-1-flash/382725.json?page=1'
```

## 9. 授權註記

sfxnz 配方 scripts 為 MIT、權重 MIT、`vllm-exl3` 為 **AGPL-3.0**；tonyd2wild patch 為
Apache-2.0 vLLM 衍生（recipe code MIT）；MiaAI-Lab 系列為 AGPL-3.0；littlecedar registry
recipe 為其各自授權。**若未來採用，必須比照 `patches/qwen38flash/` 的 `NOTICE.md`
+ sha256 慣例處理，且不得再散布衍生 image。**
