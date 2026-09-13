import re
p = "/usr/local/lib/python3.12/dist-packages/vllm/model_executor/layers/quantization/modelopt.py"
src = open(p, encoding="utf-8").read()
lines = src.splitlines()
for i in range(955, min(1090, len(lines))):
    print(f"{i+1:5d} {lines[i]}")