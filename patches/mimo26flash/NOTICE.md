# NOTICE — patches/mimo26flash

Runtime support for the `mimo26flash` cluster lane is **vendored** from the
community recipe and applied at container start as read-only bind mounts over
the image's own vLLM sources (no image rebuild).

- Source: `tonyd2wild/MiMo-V2.6-Flash-DGX-Spark-Recipe`
  <https://github.com/tonyd2wild/MiMo-V2.6-Flash-DGX-Spark-Recipe>
- Commit: `13621bb3cc6fd30a94d53609320599d1f1134686` (2026-09-22)
- License: MIT (see the upstream repository's `LICENSE`)

## What is here

| file | applied over (inside the container) | purpose |
|---|---|---|
| `mimo_v2.py` | `vllm/model_executor/models/mimo_v2.py` | fused fp8 QKV chunk sharding (`ckpt_tp`) + pass `cache_config` so `--kv-cache-dtype fp8` really applies |
| `mimo_v2_omni.py` | `vllm/model_executor/models/mimo_v2_omni.py` | add the `SupportsEagle3` marker (DFlash on the omni class; required even for text-only) |
| `triton_attn_diffkv.py` | `vllm/v1/attention/backends/triton_attn_diffkv.py` | fp8 (e4m3) KV support in the DiffKV attention backend |
| `dflash-config.fixed.json` | `/model/dflash/config.json` (read-only model mount) | repair the release's trailing comma (invalid JSON) |

`diffs/` keeps the upstream unified diffs for the three Python files, for audit.

The upstream recipe's 4th patch (`qwen3_dflash.py`, drafter value-scale) is
**not** vendored: it is opt-in and was measured to give no gain at TP2.

Line endings are normalised to LF (the upstream clone is CRLF on Windows);
these files are mounted into a Linux container, so CRLF must not be
reintroduced.
