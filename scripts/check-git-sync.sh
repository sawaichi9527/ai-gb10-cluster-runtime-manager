#!/usr/bin/env bash
# =====================================================================
# check-git-sync.sh — preflight drift guard for deploy commands.
#
# Compares HEAD against the current branch's upstream (@{upstream}) and
# refuses (--block) or warns (--warn) when the checkout has drifted.
# Invoked as a subprocess from bin/gb10, bin/gb10-single and
# scripts/cluster-* so it cannot pollute the caller's functions or env.
# Read-only: never fetches, never writes anything.
#
#   scripts/check-git-sync.sh --block   # exit 1 when behind/diverged
#   scripts/check-git-sync.sh --warn    # print warning, always exit 0
#
# Read-only: never fetches, never writes anything.
# =====================================================================
set -Eeuo pipefail

MODE="${1:---warn}"
case "$MODE" in
  --block|--warn) ;;
  *) echo "ERROR: usage: check-git-sync.sh [--block|--warn]" >&2; exit 2 ;;
esac

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Not a git repo, or git unavailable -> nothing to guard (portable).
[[ -d "${REPO_DIR}/.git" ]] || exit 0
command -v git >/dev/null 2>&1 || { echo "WARN: git unavailable -- skipping sync check" >&2; exit 0; }

# Upstream resolution: @{upstream} fails quietly when the branch is
# untracked or the remote is gone; in that case there is nothing to
# compare against, so pass.
HEAD_SHA="$(git -C "${REPO_DIR}" rev-parse HEAD 2>/dev/null)" || exit 0
UPSTREAM="$(git -C "${REPO_DIR}" rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' 2>/dev/null)" || exit 0
UP_SHA="$(git -C "${REPO_DIR}" rev-parse "${UPSTREAM}" 2>/dev/null)" || exit 0

AHEAD="$(git -C "${REPO_DIR}" rev-list --count "${UPSTREAM}..HEAD" 2>/dev/null || echo 0)"
BEHIND="$(git -C "${REPO_DIR}" rev-list --count "HEAD..${UPSTREAM}" 2>/dev/null || echo 0)"

# Tracked-file dirty state only (untracked files are scratch/state).
DIRTY=""
[[ -n "$(git -C "${REPO_DIR}" status --porcelain --untracked-files=no 2>/dev/null)" ]] && DIRTY="1"

print_warn(){
  echo "WARN: repo is out of sync with ${UPSTREAM}"
  echo "      HEAD        ${HEAD_SHA:0:7}  (${AHEAD} ahead, ${BEHIND} behind)"
  echo "      ${UPSTREAM} ${UP_SHA:0:7}"
  [[ -n "$DIRTY" ]] && echo "      working tree has uncommitted changes to tracked files"
  echo "      fix: git -C ${REPO_DIR} fetch origin && git -C ${REPO_DIR} pull"
}

if (( BEHIND > 0 )); then
  # behind or diverged — the dangerous state for a deploy.
  if [[ "$MODE" == "--block" ]]; then
    echo "ERROR: refusing to deploy -- checkout is behind ${UPSTREAM}" >&2
    print_warn >&2
    exit 1
  fi
  print_warn
elif (( AHEAD > 0 )); then
  # ahead only: warn but never refuse (node0 is the primary dev site and
  # may legitimately deploy locally-committed work).
  print_warn
else
  [[ -n "$DIRTY" ]] && print_warn
fi
exit 0