import hashlib, os
from huggingface_hub import list_repo_tree

base = "/home/eye/docker-stacks/minimax-h3/models/MiniMax-H3/FL2VA"
expected = {}
for e in list_repo_tree("MiniMaxAI/MiniMax-H3", "FL2VA", recursive=True):
    if getattr(e, "lfs", None) and e.lfs.get("sha256"):
        expected[e.path] = e.lfs.get("sha256")

local = []
for r, _, fs in os.walk(base):
    for n in fs:
        p = os.path.join(r, n)
        size = os.path.getsize(p)
        rel = "FL2VA/" + os.path.relpath(p, base)
        local.append((size, rel, p))

local.sort(reverse=True)
n = min(3, len(local))
ok = True
for size, rel, p in local[:n]:
    h = hashlib.sha256()
    with open(p, "rb") as fh:
        for blk in iter(lambda: fh.read(1 << 20), b""):
            h.update(blk)
    dig = h.hexdigest()
    match = expected.get(rel) == dig
    ok = ok and match
    print(f"FILE size={size} match={match} expected_present={'yes' if rel in expected else 'NO'}")
print("TOTAL_LOCAL_FILES", len(local))
print("RESULT", "PASS" if ok else "FAIL")