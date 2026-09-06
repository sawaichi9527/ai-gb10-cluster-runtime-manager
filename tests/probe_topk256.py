"""TopK=256 dispatch gate probe for the DSv4 SM120 backport (design §8.3).

Run inside the target AEON image:

    python3 /tmp/probe_topk256.py

Importing the module IS the load-time try_load / JIT traversal — a failed or absent
instantiation surfaces here before any boot.
"""

from flashinfer.mla._sparse_mla_sm120 import _decode_dsv4_dispatchable

cases = [
    (5, 64, 256, 512, 64, True),   # the failing r2 case — MUST now be dispatchable
    (5, 64, 192, 512, 64, False),  # 192 deliberately absent
    (5, 64, 512, 512, 64, True),   # unchanged control
    (5, 64, 128, 512, 64, True),   # unchanged control
    (5, 8, 256, 512, 64, True),    # full 256 head sweep
    (5, 128, 256, 512, 64, True),
]

res = [(_decode_dsv4_dispatchable(*c[:5]) == c[5]) for c in cases]
assert all(res), res
print("TOPK256_DISPATCH_GATE PASS", res)
