# NOTICE — patches/qwen38flash/

Vendored, **byte-identical** copies of runtime patch scripts from:

- Upstream: `MiaAI-Lab/Qwen3.8-Flash-Next-Dual-DGX-Sparks`
  (<https://github.com/MiaAI-Lab/Qwen3.8-Flash-Next-Dual-DGX-Sparks>)
- Commit: `d2f54b78c0d2f9d74ac61aa56200e3c40fac3f22`
- Upstream license: **GNU AGPL-3.0** (`LICENSE`, sha256
  `e0eedba615d5cd1b986afb6c5b3a4b1ae33713e7e9dc74d19daec5e3221f9d2e`)

These files are applied **inside the container** at launch time by the
`CMD_WRAPPER` in `cluster-profiles.d/qwen38flash.conf` (the image's own vLLM
sources are patched in place; the image is never rebuilt). They are read-only
inputs to the lane.

## Vendored files (sha256)

| file | sha256 | notes |
|---|---|---|
| `patch_ple_layer.py` | `6cb1bb9d8a4700e23c9b3114e1f3d360456669d598c7481c739ecf03d82bb964` | PLE NVFP4/mixed dispatch; `ple_layer_patched.py.orig` → `ple_layer_patched.py` |
| `patch_modelopt_mxfp8.py` | `adf72c590969a8a690fdca83e0cb2428df0dc7c7debdd2cb1983013492d9f285` | MXFP8 kernel fallback; `modelopt_patched.py.orig` → `modelopt_patched.py` |
| `patch_modelopt_fp8_block_moe.py` | `20b5d81b097f6135a0403d91cdea25e90180f7b7d0aa2fe8d9ba3fe3d4c83acf` | stacks on `modelopt_patched.py` in place (adds the `FP8_BLOCK_SCALES` routed-expert branch) |
| `patch_qsa_fp8_kv.py` | `61b7fc7cb64b9ef0d6dc702966385331a27464616cdc3ade22c5d85057a30956` | **SPDX: AGPL-3.0-or-later, (C) 2026 MiaAI Lab**; FP8-e4m3 KV cache for QSA |
| `patch_checkpoint_config.py` | `d727134c3af8db66ee2979fc64049da7895aa0e97408895903d54c52bbdc479b` | MTP layer-index alias → `config_patched.json` / `hf_quant_config_patched.json` |
| `detect_ple_dtype.py` | `03bccc515c7b65ac7570c378347e9cd9db242ebb8d600b2dd90d2e37a646be83` | recovers `text_config.ple_embedding_dtype` from a checkpoint |
| `patch_mtp_draft_vocab.py` | `d5a85baaab238917d70448feb57761e61826f4e515bbc098167515d601bb6ea5` | reduced-vocabulary MTP drafter; `mtp_patched.py.orig` → `mtp_patched.py` |
| `draft_vocab_en_code_47k.txt` | `20e36b6e8eae2598019298959a578ef8adc2948bbed7189e43a8da9b9d84a0b1` | 47,149 token ids (one per line); mounted at `/etc/vllm-draft-vocab.txt` |

## Provenance / credit

* The FP8-KV approach in `patch_qsa_fp8_kv.py` is credited by upstream to
  `lancelind/qwen3.8-Flash-DGX` (Apache-2.0); that file was reimplemented by
  MiaAI Lab against the image's own sources and is licensed AGPL-3.0-or-later.
* All other files are upstream MiaAI-Lab work under the repository's AGPL-3.0
  license. Keep this NOTICE with any redistribution.

## Not vendored (generated)

`config_patched.json` and `hf_quant_config_patched.json` are **generated** from
the local checkpoint by `prepare.sh` and are gitignored — do not commit them.
