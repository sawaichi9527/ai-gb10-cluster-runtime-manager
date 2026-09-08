# ADR-2026-09-01：TP2 27B（DFlash2）刻意關閉 prefix caching + 新版 image 檢查指引

> 決策紀錄（Architecture Decision Record），避免日後被當作「無意遺漏」而誤開。
> **決策**：TP2 27B 組合（DFlash2 n=7 / `fp8_e4m3` KV / `TRITON_ATTN` / `2026-08-24-v0.27.1-omni`）維持 `--no-enable-prefix-caching`（`scripts/tp2-common.sh` L125）。
>
> 對照：單節點 27B（`docker-compose.27b.yml`）用 **MTP k=3** + `--enable-prefix-caching` —— **兩者 drafter 不同，屬不同 decision class，非不一致**。

## 1. 現況（2026-09-01 實地確認）

| 面向 | 單節點 27B | TP2 27B（運行中） |
|---|---|---|
| spec decoding | **MTP** k=3 | **DFlash2** k=7 (block 8) |
| prefix caching | `--enable-prefix-caching` | `--no-enable-prefix-caching` |
| image | omni | `ghcr.io/aeon-7/aeon-vllm-ultimate:2026-08-24-v0.27.1-omni` |
| 位置 | `docker-compose.27b.yml` | `scripts/tp2-common.sh` L125 |

- 兩者皆跑 **v0.27.1-era** build。TP2 關閉 APC 之原因過去**無文件**，本 ADR 補上。

## 2. 為何維持關閉（v0.27.1 世代 + DFlash2 + hybrid GDN 的實證）

Qwen3.8-27B 為 hybrid GDN（48 linear + 16 full attention），`mamba_cache_mode=align`。DFlash/MTP 對 prefix-cache 有已知相容性問題（vLLM issue #54360 / #53670 / #54027 / #53504，PR #50457）：

1. **hash unit 隨 spec depth 改變**（v0.27.1 實測 #54360）：K=0 → 1568、K=3(MTP) → 1600、K=7(DFlash2) → 1648 tokens。重複長 prompt 命中率：無 spec 69.4% → **DFlash2 K=7 僅 43.3%**（且每 hit 掉一整個 1648-token block）。
2. **每一 hit 至少損失最後一整個 hash block**（EAGLE last-block drop，#53670）→ prefix-reuse 工作負載 c=8 吞吐 **-30~40%**（327→206 tok/s）。disable drop 後回到 322（-1.6%）。
3. **有 KV 損壞 / 靜默失效風險**（#50457：#42971 共用 prefix block 寫入、#41884 IndexError；#53505 附 KV connector 時 hybrid Mamba align 損壞）。官方 workaround 即 `--no-enable-prefix-caching`。
4. **YaRN 超長場景可完全歸零**（#54027：DFlash2 K=7 + YaRN 1.04M prompt，byte-identical 重送 hits=0）。

**工作負載判斷**：實際併發 3~4（低）、256K 長 context、`tp2-load` 用唯一短 prompt（不吃 prefix cache）。開啟 APC 的增益被 ~43% 上限 + 每 hit 噴 1648 tokens 抵銷，卻承擔吞吐退化 + KV 損壞風險；記憶體已緊（~6 GiB RAM free）。

→ **維持 `--no-enable-prefix-caching` 為正確防禦性選擇。勿改。**

## 3. 新版 image release 之檢查指引（何時可重新評估開啟）

當 aeon-7 釋出**新版 `aeon-vllm-ultimate` image**（升級 vLLM 基底），先比對 release note / 上游 vLLM changelog 是否**已合入**下列修復，**全部到位**才值得做 A/B 實測重新評估 APC：

| vLLM 上游 | 修復「DFlash/MT + hybrid GDN + APC」哪一項 |
|---|---|
| **#53479** | Mamba align 於每個 boundary 落地 + 捨棄 speculative one-block back-off（消除 1648-token 損失主因） |
| **#52244** | 還原 hybrid GDN 於 MTP spec-decode 的 prefix-cache hits |
| **#50457** | 讓 DFlash（全部/混 sliding）drafter 可在 APC 下正確運行（修 #42971 共用 prefix block 寫入 / #41884 IndexError / mixed-drafter hits=0） |
| **#50897** | successor-aware 保留最後一個 EAGLE/MTP block（正確性路徑） |
| **#53420/#53426** | tiered K=0 時 skip draft（K=0 consumer 不需讀 draft-layer KV） |
| **#53504 workaround** | `--prefix-cache-retention-interval <block_size>`（first-repeat miss 之 config 級 workaround） |

**A/B 驗證門（cluster 環境，皆採共用 `:1234` + bearer）**：
1. 記錄目前 `vllm:prefix_cache_hits_total`（關閉下應為 0）。
2. 臨時改 `scripts/tp2-common.sh` L125 為 `--enable-prefix-caching`，`gb10 use 27b` 重啟，送**byte-identical 長 prompt** 兩次。
3. 檢查 `gb10 status` KV / `/metrics` `prefix_cache_hits_total` 是否 >0 且重複 prompt TTFT 下降；**並確認無 KV 損壞 / crash**（併發 8 下）。
4. 若 hits 卡 0 或僅 ~43%（1648 損失仍存）或出現損壞 → 維持關閉。

## 4. 紀錄位置

- 本 ADR：本文件（`docs/ADR_..._prefix_caching_dflash2.md`）
- 同步副本：maintenance 倉 `handoff.md` §20
- `scripts/tp2-common.sh` L125 與 `docs/TP2_DEPLOYMENT_2026-08-30.md` 目前無理由說明——於下次改 flag 時一併補 `# ADR-2026-09-01: DFlash2 下刻意關閉`。
