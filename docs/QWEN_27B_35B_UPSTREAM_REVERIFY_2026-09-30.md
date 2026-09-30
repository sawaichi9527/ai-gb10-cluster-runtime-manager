# 27B / 35B 上游再查核（2026-09-30）

> 觸發：使用者要求確認 cluster 運行的 **27b** 與 **35b**（cluster TP2 與單機 TP1 皆同）
> 的 docker image 與 HuggingFace 模型來源「自 2026-09-19 之後」是否有更新。
> **結果：兩 lane 的 image 與四個模型來源全部無更新；現行 pin 即為最新。**
> 本次只做唯讀查核（registry tags/digest、HF commit、node0 `docker inspect` + 本機快照），
> **未變更任何 runtime/profile/設定**（唯一變更是本紀錄文件）。

## 一、查證基準（現行 pin）

| lane | image | 模型（body / drafter） |
|---|---|---|
| `27b` | `ghcr.io/aeon-7/aeon-vllm-ultimate:2026-09-18-v0.29.0-omni` | body `qwen3.8-27b-aeon-ultimate-uncensored-nvfp4-mixed` + drafter `qwen3.8-27b-dflash2` |
| `35b` | 同上（兩 lane 共用同一顆 image） | body `qwen3.6-35b-a3b-heretic-nvfp4` + drafter `qwen3.6-35b-a3b-dflash` |

兩 lane 於 **2026-09-19** 完成部署與實測（見 README「已部署服務」）；本查核以該日為基準。

## 二、Docker image — 無更新

- 現行 pin `2026-09-18-v0.29.0-omni` digest ＝
  **`sha256:cc91c51559d66854718fd9a8db6423e605ba76fb338bb55902caccb62aa9c677`**
  （**node0 實機 `docker image inspect .RepoDigests` 同值**）。
- registry 的**所有** `2026-09*` dated tag 僅 4 個：
  `2026-09-07-reasoning-eos`、`2026-09-11-v0.29.0-omni`、**`2026-09-18-v0.29.0-omni`**、`2026-09-18-v0.29.0-omni-dflash2`。
- **`2026-09-19` 之後無任何 dated tag**（`2026-10*` 亦無）→ 無新 image、無重新推送。
- `latest` → `sha256:cc91c515…`（**與本 repo pin 同 digest**）；
  `2026-09-18-v0.29.0-omni-dflash2` 亦為同 digest（同一 manifest，非另一次 build）。
- 旁註：`edge` rolling tag 指向另一 dev digest `ac63ec51…`，**非日期發佈 tag、profile 不跟隨**，不列入更新。

## 三、HF 模型來源 — 無更新

| lane 角色 | 本機目錄 | HF 來源 | 最後 commit | 日期 | 9/19 後更新 |
|---|---|---|---|---|---|
| 27B body | `qwen3.8-27b-aeon-ultimate-uncensored-nvfp4-mixed` | `AEON-7/Qwen3.8-27B-AEON-ULTIMATE-UNCENSORED-NVFP4-MIXED` | `282e6775` | 2026-09-18 | ❌ |
| 27B drafter | `qwen3.8-27b-dflash2` | `z-lab/Qwen3.8-27B-DFlash2`（git clone，HEAD `50307d4c` = 上游 HEAD） | `50307d4c` | 2026-08-19 | ❌ |
| 35B body | `qwen3.6-35b-a3b-heretic-nvfp4` | `AEON-7/Qwen3.6-35B-A3B-heretic-NVFP4` | `a4837491` | 2026-07-15 | ❌ |
| 35B drafter | `qwen3.6-35b-a3b-dflash` | `AEON-7/AEON-DFlash-Qwen3.6-35B-A3B` | `7f5324ae` | 2026-06-28 | ❌ |

**佐證細節**

- 本機快照時間與 HF 一致、且都停在 9/19 之前：27B body 檔案 `2026-09-18`、27B drafter README
  `2026-08-30`、35B body `2026-07-30`、35B drafter README `2026-09-10`。
- 27B drafter 是 **git clone**：本機 `git rev-parse HEAD` ＝ `50307d4c4cde6860d4eee73e2547cd786fe8e8a4`
  ＝ `z-lab/Qwen3.8-27B-DFlash2` 上游 HEAD（**無落後**）。
- 27B body（`NVFP4-MIXED`）的 `f8b6e4c4`（09-18）本身即「**Pin Spark image to
  2026-09-18-v0.29.0-omni**；ModelOpt/DFlash2 baked in」→ 9/19 部署時 image 與模型是**配套釘同版**，之後未動。
- 上游基底（非本 repo 直接來源，一併確認）：`Qwen/Qwen3.8-27B`（08-14）、`Qwen/Qwen3.6-35B-A3B`（04-24）、
  `tvall43/Qwen3.6-35B-A3B-heretic`（04-16）、`incoai/Qwen3.8-27B-DFlash2` mirror（09-17）、
  `AEON-7/Ornith-1.0-35B-AEON-Ultimate-Uncensored-NVFP4`（07-15）—— **全部 ≤ 9/17，無一在 9/19 之後**。

## 四、結論

| 面向 | 結果 |
|---|---|
| image `ghcr.io/aeon-7/aeon-vllm-ultimate` | 最新 dated tag 仍 `2026-09-18-v0.29.0-omni`（＝現行 pin，digest 不變） |
| 27B body / drafter | 09-18 / 08-19，**無更新** |
| 35B body / drafter | 07-15 / 06-28，**無更新** |

**淨結果**：`27b` 與 `35b` 現行 image／模型來源皆為**當下最新且正確**，**無需任何變更**。
下次檢討時點沿用「定期檢討追蹤」：每當 `patches/` 上游或 image 更新，或每次 27b/35b 重大變更時。
