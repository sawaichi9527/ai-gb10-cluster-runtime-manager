p = "/usr/local/lib/python3.12/dist-packages/vllm/models/qwen3_8_flash_next/nvidia/ple_layer.py"
lines = open(p, encoding="utf-8").read().splitlines()
mp = {i + 1: ln for i, ln in enumerate(lines)}
print("total lines:", len(lines))
for n in mp:
    if "_get_ple_embedding_quant_method" in mp[n]:
        print(f"== selector at line {n} ==")
        lo, hi = n, min(n + 45, len(mp))
        for j in range(lo, hi + 1):
            print(f"{j:5d} {mp[j]}")