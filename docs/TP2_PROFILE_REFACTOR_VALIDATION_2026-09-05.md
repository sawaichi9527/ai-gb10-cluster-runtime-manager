# TP2 Profile Refactor — Validation Record (2026-09-05)

Scope: the data-driven TP2 cluster-profile registry refactor (`cluster-profiles.d/`),
driven by `[REDACTED:entropy:56].md`. This document records the static checks and the
**full live 27B/35B regression** that closed the refactor, plus the lazy-sudo behavioral
change that shipped alongside it.

## Objective

Make TP2 launch data-driven before the DeepSeek-V4-Flash-0731 image work: move profile
data out of `scripts/tp2-common.sh::set_profile()` into `cluster-profiles.d/*.conf`,
make the image **profile-scoped**, and ensure rank0/rank1 consume one authoritative argv —
while **preserving 27B/35B effective launch behavior** as the regression controls.

## What changed

| area | before | after |
|---|---|---|
| Profile data | hard-coded `set_profile()` + 2nd copy in `tp2-up` | `cluster-profiles.d/*.conf` loaded once by `tp2-common.sh` |
| Image | cluster-global `IMG` in `tp2.env` | per-profile `IMG` (conf) wins when set |
| Rank1 argv | hard-coded second copy | rank0 builds argv; rank1 receives shell-escaped array (no eval) |
| DeepSeek | `runtimes.d/deepseek.conf` single-node placeholder | retired; `cluster-profiles.d/deepseek.conf` = only (cluster) placeholder |
| sudo | `sdk()`/`tp2-down`/`tp2-status` assumed a tty password read | lazy `sudo_pass()` (reuse exported `SUDO_PASS`, else interactive-only, error w/o tty) |
| inspect | n/a | `gb10 inspect <profile>` emits sanitized resolved-profile report |

Behavioral change (distinct, ships in the same commit): **lazy sudo**. `tp2-common.sh`
now exposes `sudo_pass()` (private `_sudo_pass`). If `SUDO_PASS` is already exported it is
reused with no prompt; otherwise it only prompts on a tty and errors instead of hanging on a
non-tty read. `sdk()`, `tp2-down`, `tp2-status` and the `tp2-up` heredoc all route through it.
Credentials are never echoed to stdout/logs.

## Static checks (Node0, feature branch)

| check | result |
|---|---|
| `bash -n` on `bin/gb10`, `bin/gb10-single`, `scripts/tp2-common.sh`, `tp2-up`, `tp2-down`, `tp2-status`, `tp2-smoke`, `tp2-load` | pass (8 files) |
| `gb10 list` | 27b, 35b + placeholders; no sudo prompt |
| `gb10 inspect 27b` / `inspect 35b` | correct resolved args, **no** erroneous `(placeholder)` tag |
| `gb10 inspect deepseek` | safe placeholder report |
| `gb10 use deepseek` | exit=1, stderr `ERROR: profile 'deepseek' not deployed yet (placeholder)` (safe-fail) |
| `runtimes.d/deepseek.conf` | `git rm` (staged `D`); `gb10-single list` no longer shows `deepseek` |
| stray untracked files (`.b64.common`, `.b64.up`, `tp2.env.bak-*`) | removed |

Fixes caught pre-ship: (1) `inspect_profile` used
`${PROFILE_PLACEHOLDER:+ (placeholder)}` so non-empty `"false"` also showed `(placeholder)`
→ now `[[ "${PROFILE_PLACEHOLDER}" == "true" ]]`; (2) `free_singles()` used `${SCRIPT_DIR}/gb10-single`
(repo-relative `scripts/`, wrong) → now `${REPO_DIR}/bin/gb10-single`.

## Live regression — 27B

Profile: `cluster-profiles.d/27b.conf`. BODY=`qwen3.8-27b-aeon-ultimate-uncensored-nvfp4`,
DRAF=`qwen3.8-27b-dflash2`, MAXLEN=262144, NSPEC=7, IMAGE=omni, KV=fp8_e4m3.

Command: `gb10 use 27b` (detached `/tmp/use27b.log`).

| check | value |
|---|---|
| containers | both nodes TP2 Up |
| NCCL | `world_size=2` |
| KV | 85.73 GiB |
| health | READY |
| `/v1/models` | `max_model_len=262144` |
| smoke | HTTP 200 `HELLO-TP2-OK` |

Teardown: `gb10 stop` → both nodes' containers removed, health down.

## Live regression — 35B

Profile: `cluster-profiles.d/35b.conf`. BODY=`qwen3.6-35b-a3b-heretic-nvfp4`,
DRAF=`qwen3.6-35b-a3b-dflash`, MAXLEN=131072, NSPEC=11, IMAGE=omni, KV=fp8_e4m3.

Command: `gb10 use 35b` (detached `/tmp/use35b.log`, READY `2026-09-05 00:15:39`).

| check | value |
|---|---|
| containers | both nodes TP2 Up |
| NCCL | `world_size=2` |
| KV | 79.76 GiB |
| health | READY |
| `/v1/models` | `max_model_len=131072` |
| smoke | HTTP 200 `HELLO-TP2-OK` |

Teardown: `gb10 stop` → both nodes removed, health down, `/v1/models` no models.

## DeepSeek safe-fail (final)

`gb10 use deepseek` → exit=1 with a clear placeholder message. `gb10 inspect deepseek`
reports placeholder state. Nothing deploys and no missing stack is touched.

## Credential / secrets check

- `/tmp/use27b.log` and `/tmp/use35b.log`: no `VLLM_API_KEY` / `SUDO_PASS` / `sk-` / `Bearer` markers.
- `tp2.env` remains gitignored.
- `gb10 status` / `inspect` output redacts auth.

## Conclusion

The data-driven TP2 profile registry is complete and regression-verified on both live
profiles; DeepSeek is held as a safe cluster placeholder pending its own image/model
bring-up (separate follow-up).

## Artifacts

- Final Node0 file SHA-256s: `scripts/tp2-common.sh`=`38b6a505…`,
  `scripts/tp2-up`=`312baed3…`, `scripts/tp2-down`=`a104c01f…`,
  `scripts/tp2-status`=`feecdafb…`, `bin/gb10`=`7acb3ed4…`,
  `cluster-profiles.d/27b.conf`=`0fa8d217…`, `35b.conf`=`d0915fcc…`,
  `deepseek.conf`=`1b411354…`.
- Branch: `feature/tp2-profile-registry`.