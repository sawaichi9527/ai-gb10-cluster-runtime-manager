# NOTICE — patches/qwen38flash/

Vendored, **byte-identical** copies of runtime patch scripts from:

- Upstream: `MiaAI-Lab/Qwen3.8-Flash-Next-Dual-DGX-Sparks`
  (<https://github.com/MiaAI-Lab/Qwen3.8-Flash-Next-Dual-DGX-Sparks>)
- Commit: `cd839d0b62f6c737178a0c2037733420e0524ebf` (2026-09-29; upstream `main`
  HEAD, no later commit). The ten patchers below were re-verified **blob-identical**
  at this commit on 2026-10-21; the only functional addition since `2c86a1d0` is the
  seven language-extended draft vocabularies plus `build_draft_vocab_extend.py`,
  which are now vendored too.
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
| `patch_block_drop.py` | `ff368a20c033c62f2cf113927eeffb74283c12c901e661951a4d1f3b0131e458` | vllm#53388 `disable_eagle_block_drop` backport; patches 6 vLLM files, applied by `CMD_WRAPPER` (fail-closed). Source of the `disable_eagle_block_drop` spec key |
| `patch_determinism.py` | `c8d3e5d86aa04fd4e1de68e98d1e5afb959559f3f58ed3a5e2c6d1a77e63dc42` | Reproducible greedy decoding. **Opt-in**: the container runs it only when `VLLM_QSA_DET_TOPK=1` or `VLLM_MOE_DET_FINALIZE=1`; otherwise it is not applied. Must run after `patch_qsa_fp8_kv.py` (edits `qsa_ops_patched.py` in place) |
| `draft_vocab_es_en_code_65k.txt` | `f5f4517ea57100778ffe8fa96220b32865b0464ec951cf762bbecaed6fa49b90` | Spanish 65,536-row draft head (47k file as floor + es Wikipedia); select with `Q38_DRAFT_VOCAB=es` |
| `draft_vocab_zh_en_code_65k.txt` | `efdf7c2efbaeb23b9ad7271397b2559d016b90656285bbdfdb65d3c9a6ec016b` | Chinese 65,536 rows; upstream TP2 measured +19…+39% (control-normalized) |
| `draft_vocab_ja_en_code_65k.txt` | `9db44500f4015700d2cbafcdb26018cd2e9696243471092a60b2bc0c4f8a5d1f` | Japanese 65,536 rows; +35…+44% |
| `draft_vocab_de_en_code_65k.txt` | `5da38af2279e9e8468ef5908aee9a3cee9091d48dc3e1539966c8281c9d19a96` | German 65,536 rows; +31…+36% (ABBA re-measured) |
| `draft_vocab_pt_en_code_65k.txt` | `79207277245bf1da7b92c8b4b04e7f943873574d1d42910e6c3db79bc2c4db1b` | Portuguese 65,536 rows; +9…+16% |
| `draft_vocab_fr_en_code_65k.txt` | `207c965b33bb2c62baa3ed40a8abf208dce7363b3b2455cf35e845a05ccb1ee6` | French 65,536 rows; +10…+24% |
| `draft_vocab_ru_en_code_65k.txt` | `3cb85dc1d03d4a97b273aee5f8d78f1340f94288db8dc6ffaa2d863ba96fd99a` | Russian 65,536 rows; +53…+77% (largest gap in the 47k file) |
| `build_draft_vocab_extend.py` | `4dd33bcbece3a8220d98496012a6acd5ebd54a8656c308d76be43978f1cb4c11` | Rebuilds a language file from the 47k floor + a language corpus; not run at deploy time |

### Language draft vocabularies (upstream 2026-09-29)

`draft_vocab_<lang>_en_code_65k.txt` = the 47,149-id English+code file **whole as a
floor**, all 400 byte-fallback ids pinned, plus 18,387 ids ranked by frequency over
668 MiB of that language's Wikipedia (65,536 rows, 391–400 KB each). They change
**drafting only** — `compute_logits` still uses the full 248,320-token vocabulary,
and a draft outside the subset is rejected at verification exactly like any other
bad draft. The default stays `draft_vocab_en_code_47k.txt`; `cluster-profiles.d/qwen38flash.conf`
maps `Q38_DRAFT_VOCAB=<lang>` to the matching file and aborts on an unknown value.

## Provenance / credit

* The FP8-KV approach in `patch_qsa_fp8_kv.py` is credited by upstream to
  `lancelind/qwen3.8-Flash-DGX` (Apache-2.0); that file was reimplemented by
  MiaAI Lab against the image's own sources and is licensed AGPL-3.0-or-later.
* All other files are upstream MiaAI-Lab work under the repository's AGPL-3.0
  license. Keep this NOTICE with any redistribution.

## Not vendored (generated)

`config_patched.json` and `hf_quant_config_patched.json` are **generated** from
the local checkpoint by `prepare.sh` and are gitignored — do not commit them.
