import math
p = "/usr/local/lib/python3.12/dist-packages/vllm/model_executor/layers/quantization/modelopt.py"
lines = open(p, encoding="utf-8").read().splitlines()
mp = {}
for i, ln in enumerate(lines):
    mp[i + 1] = ln
# print class definitions and any 'mixed' references
keys = [n for n in mp if "class " in mp[n]]
for n in keys[:200]:
    print(f"== {mp[n]}")
print("---- 'mixed' occurrences ----")
for n in mp:
    if "mixed" in mp[n].lower():
        print(f"{n:5d} {mp[n]}")
print("---- _extract_modelopt_quant_algo ----")
for n in mp:
    if "_extract_modelopt_quant_algo" in mp[n]:
        lo, hi = n, min(n + 40, len(mp))
        for j in range(lo, hi + 1):
            print(f"{j:5d} {mp[j]}")