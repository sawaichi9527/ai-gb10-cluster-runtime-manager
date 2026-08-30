# TP2 Cluster Deployment — 2026-08-30 (verified)

Two-node DGX Spark GB10, cross-node vLLM tensor-parallel (TP=2), no Ray.

This document records the **verified** facts that the `scripts/` encode. If a
future change contradicts anything here, update this doc in the same change.

## Environment

| | Node0 | Node1 |
|---|---|---|
| host | spark-25d5 | spark-8095 |
| mgmt LAN | 192.168.23.215 | 192.168.23.129 (→216) |
| interconnect | 10.0.101.101 | 10.0.101.102 |
| role | rank0, API :8000 | rank1, headless |
| OS | Ubuntu 24.04 ARM64 | Ubuntu 24.04 ARM64 |
| interconnect | rocep1s0f0 200GbE, MTU 4096, RoCE v2 GID[3] |
| image | `ghcr.io/aeon-7/aeon-vllm-ultimate:2026-08-24-v0.27.1-omni` (same slim e62ac10d on both) |

Node0→Node1: `ssh -i ~/.ssh/id_gb10_cluster eye@10.0.101.102`.

Repo placement: checkout `gb10-cluster` on **Node0 only** at **`~/gb10-cluster/`**
(deliberately outside `~/docker-stacks/`, which stays purely for runtime stacks).
Node1 does not host the repo — Node0 orchestrates it purely over ssh; Node1 needs
only the image (same slim), the model dirs, and sudo docker.

## Verified launch (both profiles)

Common to every launch:

```bash
docker run -d --name tp2-node0|tp2-node1 \
  --gpus all --ipc=host --shm-size=16g --net=host \
  -e VLLM_HOST_IP=10.0.101.10X \
  -e NCCL_SOCKET_IFNAME=enp1s0f0np0 -e GLOO_SOCKET_IFNAME=enp1s0f0np0 \
  -e NCCL_IB_HCA=rocep1s0f0:1 -e NCCL_IB_GID_INDEX=3 \
  -e PYTORCH_CUDA_ALLOC_CONF=expandable_segments:True \
  --device /dev/infiniband --cap-add IPC_LOCK --ulimit memlock=-1:-1 \
  -v <body>:/model:ro -v <drafter>:/drafter:ro \
  --entrypoint vllm "$IMG" serve /model \
    --served-model-name aeon --host 0.0.0.0 [--port 8000 | --headless] \
    --tensor-parallel-size 2 --nnodes 2 --node-rank {0,1} \
    --master-addr 10.0.101.101 --master-port 29501 \
    --quantization compressed-tensors --kv-cache-dtype fp8_e4m3 \
    --attention-backend TRITON_ATTN \
    --disable-custom-all-reduce \
    --enable-chunked-prefill --no-enable-prefix-caching \
    --compilation-config '{"cudagraph_mode":"FULL_AND_PIECEWISE"}' \
    --speculative-config '{"method":"dflash","model":"/drafter",...}' \
    --reasoning-parser qwen3 --tool-call-parser qwen3_coder --enable-auto-tool-choice \
    --trust-remote-code
```

Node1 adds `--headless --node-rank 1` and omits `--port`/HTTP; Node0 uses `--port 8000`.

### 27B + DFlash2 (default profile)

```
body    qwen3.8-27b-aeon-ultimate-uncensored-nvfp4  (Qwen3_5ForConditionalGeneration)
drafter qwen3.8-27b-dflash2                          (DFlash2DraftModel, block 8, targets [5,19,33,47,61], n=7)
kv      fp8_e4m3   max-model-len 262144  GMU 0.85  num-seqs 8  batched 16384
```

Verified: TP rank 0/1; KV pool 85.68 / 85.52 GiB; max_len 262144;
DFlash2 acceptance 51.4 %; 8-conc ~227–286 comp-tok/s; chat `HELLO-TP2-OK`.

### 35B-A3B + DFlash

```
body    qwen3.6-35b-a3b-heretic-nvfp4  (Qwen3_5MoeForConditionalGeneration, compressed-tensors/nvfp4, 23.35GB)
drafter qwen3.6-35b-a3b-dflash          (DFlashModel v1, block 16, targets [1,6,11,16,22,27,32,37], 6 layers)
kv      fp8_e4m3   max-model-len 131072  GMU 0.80  num-seqs 16  batched 16384  nspec 11
```

Verified: TP rank 0/1 **plus EP rank 0/1** (MoE experts cross-node); V2 Model
Runner; KV pool 79.73 GiB; max_len 131072; chat `HELLO-TP2-OK` (finish stop);
DFlash v1 acceptance 26.6 % → **81.8 % after warm-up** (per-position up to 1.000);
8-conc 402/556/533 comp-tok/s.

## Decisions & facts encoded

- **DFlash/DFlash2 non-causal drafter** ⇒ cannot use NVFP4 KV ⇒ `--kv-cache-dtype fp8_e4m3`
  (27B single-node used `fp8`; cross-node omni uses `fp8_e4m3`).
- **No Ray**: native `mp` backend is sufficient and faster to operate. Do not add Ray.
- DFlash2 on the omni image confirmed working (revises the earlier "leave drafter at MTP" idea).
- 35B chat with tiny `max_tokens` (64) returned `content=None` — Qwen3 MoE thinking
  consumed the budget. Use `max_tokens >= 500` in smoke; treat short-content as a
  budget artifact, not a bug.
- GMU values (0.85 / 0.80) are the smoke-verified baselines; tune only with engine metrics.

## Operational cheatsheet

```bash
gp() { scripts/tp2-up;  }            # 27B default
gp 35b                               # or scripts/tp2-up 35b
scripts/tp2-status | tp2-smoke | tp2-load | tp2-down
```
