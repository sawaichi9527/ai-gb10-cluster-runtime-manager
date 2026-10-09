# `_backup/` — archived recipes (NOT loaded, NOT deployed)

The loader (`cluster-common.sh: list_cluster_profiles`) only scans
`cluster-profiles.d/*.conf` at the top level, so nothing in this
directory is a live profile.

## `deepseek-vision-anemll.conf`

Byte-identical copy of the `deepseek-vision` production recipe **as it
was until 2026-10-09** (SHA256 `0df27c387a380e40cb9549c20147956047429db801c76337cc2664f5869eaafe`):

- image `ghcr.io/anemll/dspark-vllm-gx10:0.1.1`
  (digest `sha256:a83948492cf13df455170fb42885f5ef4db54fefe0feff0f841ecbff464ac9d8`)
- official checkpoint `models/deepseek-v4-flash-vision-exp`
- startup wrapper applying 17 vendored MiaAI hotfixes from
  `patches/dspark-vision/` (MIT, `NOTICE.md`) — kept in-repo as part of
  this backup solution
- `SYNC_DIRS` stages `patches/dspark-vision` to
  `${HOME}/docker-stacks/anemll-dspark-vllm-gx10-miaFlaver/patches` on
  both nodes at boot

Superseded by the promoted eugr-b12x recipe after the succession A/B
(`docs/DEEPSEEK_VISION_B12X_RECIPE_AB_2026-10-09.md`): decode parity,
prefill +9..14%, acceptance +1pp, correctness gates PASS.

### Restore (rollback to the Anemll recipe)

```sh
# 1. put the recipe back (and the A/B lane base, if you also archived it)
cp cluster-profiles.d/_backup/deepseek-vision-anemll.conf \
   cluster-profiles.d/deepseek-vision.conf
# 2. confirm the pinned Anemll image still exists on both nodes
#    (docker images ghcr.io/anemll/dspark-vllm-gx10) — if it was pruned,
#    re-pull on node0 and byte-transfer to node1 over CX7 first, then
#    verify IMG_SHA256.
# 3. confirm models/deepseek-v4-flash-vision-exp exists on both nodes.
# 4. boot: gb10 use deepseek-vision
```

`patches/dspark-vision/` must stay in the repo while this backup exists
— it is the recipe's runtime dependency.

### Model retention (user decision 2026-10-09)

The **old official model** `~/docker-stacks/models/deepseek-v4-flash-vision-exp`
is **deliberately left in place on BOTH nodes** (node0 + node1) pending a
later user decision — do NOT clean it up as stale residue of this promotion.
It is this backup recipe's model dependency (restore step 3).
