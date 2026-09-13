import json, glob

base = "/usr/local/lib/python3.12/dist-packages/vllm/model_executor/layers/quantization/modelopt.py"
lines = open(base, encoding="utf-8").read().splitlines()
mp = {i + 1: ln for i, ln in enumerate(lines)}

p = glob.glob("/model/hf_quant_config.json")
d = json.load(open(p[0]))
q = d.get("quantization", d)
print("top-level keys:", list(d.keys()))
print("quant_algo:", q.get("quant_algo"))
ql = q.get("quantized_layers", {})
print("quantized_layers count:", len(ql))
print("--- first 12 keys ---")
for i, k in enumerate(list(ql.keys())[:12]):
    print(f"  {i}: {k} => {ql[k].get('quant_algo')}")
print("--- PLE-related keys ---")
for k, v in ql.items():
    if "ple" in k.lower():
        print(f"  {k} => {v}")
print("--- attach ModelOptMixedPrecisionConfig lazily not imported; resolve candidate via direct map ---")
# Strategy: mimic _resolve_quant_algo's first candidate (exact) then prefix-dot parents.
target = "model.language_model.layers.1.ple.ple_embedding.ngram_embedding"
parts = target.split(".")
cands = [".".join(parts[:i]) for i in range(1, len(parts) + 1)]
print("candidate chain:")
for c in cands:
    if c in ql:
        print(f"  EXACT {c} => {ql[c].get('quant_algo')}")
    else:
        print(f"  none  {c}")