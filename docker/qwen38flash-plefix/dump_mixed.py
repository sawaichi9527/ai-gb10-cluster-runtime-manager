p = "/usr/local/lib/python3.12/dist-packages/vllm/model_executor/layers/quantization/modelopt.py"
lines = open(p, encoding="utf-8").read().splitlines()
mp = {i + 1: ln for i, ln in enumerate(lines)}
lo, hi = 2143, 2360
for j in range(lo, hi + 1):
    print(f"{j}: {mp[j]}")