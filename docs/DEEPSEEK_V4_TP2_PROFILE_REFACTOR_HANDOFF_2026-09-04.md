# DeepSeek V4 TP2 Profile Refactor Handoff — 2026-09-04

## 目的

本文件交給負責 remote maintain DGX Spark GB10 cluster 的 OpenCode / agent 執行。

本次任務 **不是直接部署 DeepSeek-V4-Flash-0731，也不是先 patch vLLM image**。
本次只做 TP2 control-plane 的結構整理，讓現有 Qwen 27B / 35B 與未來 DeepSeek V4 可以用不同 image、不同 vLLM args、不同 speculative-decoding policy，而不把 model-specific `if/case` 持續塞進 `scripts/tp2-common.sh` / `scripts/tp2-up`。

完成後仍必須維持現有操作入口：

```bash
gb10 use 27b
gb10 use 35b
# future
gb10 use deepseek
```

## 現況基準（不要破壞）

Repo：`sawaichi9527/ai-gb10-cluster-runtime-manager`

Topology：

```text
Node0 spark-25d5
  mgmt 192.168.23.215
  interconnect 10.0.101.101
  TP2 rank0 + OpenAI API :1234
  repo only lives here

Node1 spark-8095
  mgmt 192.168.23.216
  interconnect 10.0.101.102
  TP2 rank1 headless
  no repo checkout required
```

Control policy：

- `bin/gb10` = 2-node TP2 cluster manager.
- `bin/gb10-single` = single-node runtime manager.
- Node0 orchestrates Node1 over SSH.
- TP2 and single-node exclusive runtimes are mutually exclusive.
- All LLM endpoints stay on OpenAI-compatible port `1234` and share `VLLM_API_KEY`.
- `tp2.env` remains gitignored and stores host/network/secrets/site-specific values.
- Node1 must continue to require only image + model dirs + Docker; it must not require this repo.
- RoCE/NCCL settings and `--disable-custom-all-reduce` are load-bearing and must not be removed as part of this refactor.
- Existing 27B and 35B profiles are deployed/verified behavior. Refactor must preserve their effective launch arguments unless explicitly documented otherwise.

## 為何現在需要重構

目前 single-node 已經 data-driven：

```text
runtimes.d/*.conf
  -> gb10-single generic loader
```

但 TP2 profile 仍 code-driven：

```text
bin/gb10
  -> scripts/tp2-up
  -> scripts/tp2-common.sh::set_profile()
       -> hard-coded 27b/35b model paths and knobs
```

同時 `tp2.env` 只有 cluster-global `IMG`，而 `build_vllm_args()` 目前把 Qwen-specific 設定寫死，例如：

- `--attention-backend TRITON_ATTN`
- `--kv-cache-dtype fp8_e4m3`
- `--speculative-config ... method=dflash ...`
- `--reasoning-parser qwen3`
- `--tool-call-parser qwen3_coder`
- `FULL_AND_PIECEWISE`

DeepSeek V4 不會和 Qwen 共用完全相同的 image / parser / speculative / backend policy，所以不能只在 `set_profile()` 再加一個 `deepseek)` case。

## 目標架構

新增 TP2 cluster profile registry：

```text
cluster-profiles.d/
  27b.conf
  35b.conf
  deepseek.conf     # initially placeholder / disabled until model+image ready
```

責任分層：

```text
Image layer
  AEON / derived image / DeepSeek patches

Cluster profile layer
  model path
  per-profile image
  vLLM model-specific args
  speculative policy
  max context / concurrency / GMU

TP2 orchestration layer
  rank0/rank1
  SSH
  Docker
  RoCE/NCCL
  API port/auth
  health/start/stop
```

**TP2 orchestration layer不得知道 Qwen 或 DeepSeek 的特殊語義。**

## 建議 cluster profile schema

可依 shell implementation 調整名稱，但語義需維持。建議至少支援：

```bash
PROFILE_ID="27b"
DISPLAY_NAME="Qwen3.8 27B"
PLACEHOLDER="false"

IMAGE="ghcr.io/aeon-7/aeon-vllm-ultimate:2026-08-24-v0.27.1-omni"
BODY_REL="qwen3.8-27b-aeon-ultimate-uncensored-nvfp4"
DRAF_REL="qwen3.8-27b-dflash2"

MAXLEN="262144"
NUMSEQ="8"
BATCHED="16384"
GMU="0.85"

# Prefer a profile-owned array/function rather than a single unsafe string.
# It must be possible for rank0 and rank1 to consume exactly the same
# model-specific arguments.
```

35B must preserve current effective values:

```text
body   qwen3.6-35b-a3b-heretic-nvfp4
draft  qwen3.6-35b-a3b-dflash
maxlen 131072
numseq 16
batched 16384
GMU    0.80
NSPEC  11
```

27B must preserve current effective values:

```text
body   qwen3.8-27b-aeon-ultimate-uncensored-nvfp4
draft  qwen3.8-27b-dflash2
maxlen 262144
numseq 8
batched 16384
GMU    0.85
NSPEC  7
```

## DeepSeek placeholder profile

Create `cluster-profiles.d/deepseek.conf`, but keep it non-runnable until model + derived image are actually present and verified.

Target identity for later deployment:

```text
Model family:
  NVIDIA DeepSeek-V4-Flash-0731 NVFP4

Base image:
  ghcr.io/aeon-7/aeon-vllm-ultimate:2026-08-24-v0.27.1-omni

Planned derived image lineage:
  2026-09-04-v0.27.1-omni-ds4flash0731-r1
  later: ...-r2
```

Do **not** invent a final registry/repository name if it is not yet configured on the hosts.
Do **not** silently fall back to the global AEON image for the DeepSeek profile.
A placeholder profile must fail safely with `not deployed yet` and must not start containers.

Initial planned DeepSeek r1 policy (documentation only; do not assume supported until image bring-up):

```text
TP                2
EP                off
weights           NVFP4 routed experts
KV                FP8 baseline
DSpark            off for r1 control
CUDA graph        PIECEWISE baseline
linear backend    DeepGEMM path expected
MoE backend       FlashInfer CUTLASS / auto expected
context           start 64K; validate before scaling
API               OpenAI compatible :1234
```

r2 is expected to add DSpark and longer-context tuning after r1 correctness is proven.

## Required implementation changes

### 1. Add `cluster-profiles.d/`

Move the 27B/35B **profile data** out of `set_profile()` into separate conf files.
Keep profile discovery deterministic and sorted.

### 2. Make image per-profile

`tp2.env` may retain a default/fallback image for backward compatibility, but a profile must be able to override it.

Desired behavior:

```text
27b      -> AEON omni
35b      -> AEON omni
deepseek -> DeepSeek-derived AEON image (when deployed)
```

The resolved image must be **byte-identical / same digest on both nodes** before TP2 launch.

### 3. Separate cluster-global args from model-specific args

Cluster-global examples:

```text
--tensor-parallel-size 2
--nnodes 2
--node-rank
--master-addr / --master-port
--disable-custom-all-reduce
host / port / headless
API key
```

Model-specific examples:

```text
quantization
KV dtype
attention backend
linear/MoE backend
speculative config
reasoning parser
tool-call parser
CUDA graph mode
prefix-caching policy
max model len
max num seqs
max batched tokens
GMU
```

Do not encode DeepSeek-specific branches in the generic TP2 engine.

### 4. Remove duplicated rank1 model arguments

Current `scripts/tp2-up` hard-codes a second copy of many vLLM options for Node1 while Node0 uses `build_vllm_args()`.
Refactor so rank0 and rank1 are generated from the **same resolved profile data**.
Only rank-specific fields may differ:

```text
rank0: --port, API server
rank1: --headless
node rank / host IP / NIC settings
```

This is an important acceptance criterion: no two independently maintained copies of model-specific args.

### 5. Keep `gb10` thin

`bin/gb10` should discover/list profiles from `cluster-profiles.d` rather than hard-code a second independent profile list if practical.

At minimum, `gb10 list/use/start/restart` must use one authoritative profile registry.

### 6. DeepSeek is cluster-only

Current `runtimes.d/deepseek.conf` is a historical single-node placeholder.
DeepSeek-V4-Flash-0731 target requires TP2 and should not appear as a runnable `gb10-single` runtime.

Preferred cleanup:

- remove `runtimes.d/deepseek.conf`, or
- if removal would complicate compatibility, clearly mark it deprecated and ensure `gb10-single` never presents it as a future deployable single-node target.

Update README / AGENTS accordingly.

## Do NOT do in this task

Do not mix these into the structural refactor:

- do not build `...ds4flash0731-r1` yet;
- do not patch vLLM Python source yet;
- do not import old AEON DeepSeek PR#4 wholesale;
- do not enable DSpark;
- do not switch Qwen 27B/35B KV/backend/spec-decoding settings;
- do not re-enable 27B prefix caching (existing ADR remains authoritative);
- do not move repo onto Node1;
- do not change port 1234 or shared API-key policy;
- do not replace direct SSH orchestration with Ray/Slurm/Kubernetes;
- do not change RoCE/NCCL values merely for cleanup.

## Backward compatibility requirements

After refactor, with the same existing `tp2.env` and model directories:

```bash
gb10 list
gb10 use 27b
gb10 status
gb10 smoke
gb10 stop

gb10 use 35b
gb10 status
gb10 smoke
gb10 stop
```

must continue to work with the same endpoint semantics and effective vLLM model settings as before.

`gb10 use deepseek` must return a clear placeholder/not-deployed message until the DeepSeek profile is explicitly promoted.

## Static validation before touching live cluster

Required at minimum:

```bash
bash -n bin/gb10
bash -n bin/gb10-single
bash -n scripts/tp2-common.sh
bash -n scripts/tp2-up
bash -n scripts/tp2-down
bash -n scripts/tp2-status
bash -n scripts/tp2-smoke
bash -n scripts/tp2-load
```

Add a dry-run/profile-inspection path if useful so an operator can verify resolved values without starting Docker. Example desired capability (name may differ):

```bash
gb10 inspect 27b
gb10 inspect 35b
gb10 inspect deepseek
```

It should print sanitized resolved profile values and must never print API keys or sudo passwords.

## Live validation order

Do not validate DeepSeek yet. Validate the refactor against existing known-good profiles first.

1. `gb10 use 27b`
2. `/health` PASS
3. `/v1/models` PASS with auth
4. `gb10 smoke` PASS
5. confirm Node1 rank1 is headless and same image as Node0
6. `gb10 stop`
7. repeat for 35B
8. switch 27B -> 35B -> 27B once to verify exclusivity/state handling
9. `gb10 use deepseek` must fail safely as placeholder

Record actual validation results in a new dated doc or append a clearly labeled Results section here.

## Git / delivery policy

- Work in a feature branch.
- Keep the structural refactor separate from future DeepSeek image/patch commits.
- Prefer small commits with one responsibility.
- Do not commit `tp2.env`, API keys, passwords, private SSH material, model blobs, Docker logs, or generated caches.
- Update `README.md` and `AGENTS.md` in the same PR if behavior/registry layout changes.
- Do not claim `deepseek` deployed until both-node image/model presence and a real generation have been verified.

Suggested commit sequence:

```text
refactor: add data-driven TP2 cluster profile registry
refactor: generate rank0/rank1 args from one profile source
refactor: make TP2 image profile-scoped
chore: retire single-node deepseek placeholder
docs: update cluster profile architecture and DeepSeek placeholder
```

## Definition of Done for this refactor

The task is complete only when all of the following are true:

- `cluster-profiles.d/27b.conf` and `35b.conf` are authoritative.
- `deepseek.conf` exists in the cluster registry as safe placeholder.
- per-profile image selection exists.
- model-specific args are profile-owned.
- rank0/rank1 no longer maintain duplicated model-specific launch arguments.
- existing 27B and 35B real serves pass smoke tests.
- TP2/single-node mutual exclusion is unchanged.
- endpoint remains `:1234/v1`.
- Node1 still needs no repo checkout.
- secrets remain outside git.
- README and AGENTS match deployed reality.
- DeepSeek image patching/deployment remains a separate follow-up task.

## Follow-up after this refactor

Only after this refactor is merged and 27B/35B are revalidated should the next task begin:

```text
AEON 2026-08-24-v0.27.1-omni
  + minimal DeepSeek-V4-Flash-0731 / GB10 patch delta
  -> 2026-09-04-v0.27.1-omni-ds4flash0731-r1
  -> TP2 r1 bring-up
  -> correctness / RDMA / 64K -> 128K -> longer-context validation
  -> r2 DSpark
```

The image patch inventory must be based on verified DGX Spark / GB10 implementations and compared against what AEON 0.27.1 already carries. Do not rebuild the old community patch stack blindly.
