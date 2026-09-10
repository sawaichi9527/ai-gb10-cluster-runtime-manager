# src/ — vendored reference sources

Sources pinned beside this repo. `runtimes.d/*.conf` reference deployment
targets; `src/` holds upstream source checked in for provenance/pinning.

## minimax-h3/

MiniMax H3 (FL2VA) reference implementation, used by the single-node **video**
runtime (`gb10-single use/start node1 minimaxh3`; `MODE=exclusive`,
`GROUP=video`, deployed on Node1 via compose under `~/docker-stacks/minimax-h3/`).

Upstream layout:

- `Dockerfile`, `compose.yaml`, `Makefile`
- `start-fp8.sh`, `launch-download.sh`, `verify-h3-download.py`, `fp8-quant.json`
- `scripts/`, `patches/`, `tests/`, `docs/`
- `CHANGELOG.md`, `CITATION.cff`, `CONTRIBUTING.md`, `README.md`, `SECURITY.md`
- Licensing: `LICENSE`, `MODEL-LICENSE.md`, `NOTICE`

Active deployment configuration / stack pin: `runtimes.d/minimaxh3.conf` and
Node1 `~/docker-stacks/minimax-h3/`.
