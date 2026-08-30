# AGENTS.md — ai-gb10-cluster

Rules for any agent/maintainer working in this repo.

## Layout / placement

- Checkout this repo on **Node0 only** at **`~/ai-gb10-cluster/`** — under the home
  dir, deliberately **outside `~/docker-stacks/`** so that directory stays purely
  for deployed runtime stacks. This repo *manages* the cluster; it is not a stack
  itself. Node0 orchestrates; the scripts reach Node1 over ssh. **Node1 does not
  have the repo** — only the image, the model dirs
  (`~/docker-stacks/aeon-vllm/models/...`), and sudo docker.
- Model paths inside scripts default to the shared `~/docker-stacks/aeon-vllm/models`
  on the *current* node (Node1 over ssh resolves its own copy of those dirs).

## Cluster facts (don't "fix" these)

- **Two asymmetric nodes, Node0 single-side orchestration.** All scripts run on
  Node0 and reach Node1 via `ssh -i ~/.ssh/id_gb10_cluster eye@10.0.101.102`.
- **No Ray, no LiteLLM.** TP2 uses vLLM's native `mp` backend
  (`--nnodes 2 --node-rank 0|1 --master-addr ... --master-port ...`).
- **RoCE v2 interconnect env is mandatory**: `NCCL_SOCKET_IFNAME`/`GLOO_SOCKET_IFNAME=enp1s0f0np0`,
  `NCCL_IB_HCA=rocep1s0f0:1`, `NCCL_IB_GID_INDEX=3`. Indices are GID[3] = RoCE v2.
- **`--disable-custom-all-reduce` is required** for the cross-node path — do not remove.
- **Image slim must match on both nodes** (`sha256:e62ac10d…` for the verified image).
- **GB10 NVML** reports util/mem = 0%/N/A. Real signals: SignDecoding acceptance,
  KV pool GiB, concurrent throughput, `/health`.
- **MoE 35b**: TP=2 splits globally; MoE experts additionally EP-split across nodes
  (log shows EP rank 0/1). Drafter is `DFlashQwen3ForCausalLM`/`DFlashModel` (upstream now), not MTP.
- **Reasoning models**: small `max_tokens` can hide content inside `reasoning_content`.
  In smoke tests use generous `max_tokens` (>= 500).
- **warm-up**: draft acceptance climbs after the first few generations; measure
  after warm-up for real numbers.

## Conventions

- Keep the per-profile parameter table in `scripts/tp2-common.sh::set_profile`
  and the README in sync. Add new profiles there, not scattered in each script.
- `tp2.env` is gitignored; keep the template `tp2.env.example` the single source
  of default knobs. Never commit real `VLLM_API_KEY` / `SUDO_PASS`.
- Prefer stable interconnect IPs (`10.0.101.x`) over mgmt LAN IPs in scripts.
- Node1 mgmt IP may change (192.168.23.129 → 192.168.23.216); scripts must not
  depend on it.

## Verify before claiming done

- `scripts/tp2-up 27b` then `scripts/tp2-status` then `scripts/tp2-smoke`.
- `scripts/tp2-down` must clean both nodes (repeat no-op is fine).
