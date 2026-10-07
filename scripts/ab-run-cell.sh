#!/usr/bin/env bash
# =====================================================================
# ab-run-cell.sh <cell> <label> [profile]
#
# One A/B cell end-to-end: apply the single knob, reboot the lane, gate it
# (compose-verify + smoke), run the full bench, then run the warm
# prefix-cache probe. Everything lands in /tmp/ab-<label>.txt so the cell
# can be diffed against the baseline file.
#
# Usage:
#   scripts/ab-run-cell.sh <cell> <label> <profile>      # all three required
#
#   scripts/ab-run-cell.sh V0 V0 deepseek-vision-tune     # vision baseline
#   scripts/ab-run-cell.sh V1 V1 deepseek-vision-tune     # one knob
#   AB_REF=V0 scripts/ab-run-cell.sh V1 V1 deepseek-vision-tune
#   SKIP_BOOT=1 scripts/ab-run-cell.sh V1 V1 deepseek-vision-tune
#
# profile is REQUIRED, not defaulted: an earlier version defaulted it to
# deepseek-tune, so a two-argument call silently tore down the vision lane
# and booted the mainline experiment lane instead — measured the wrong model
# for half an hour before it was caught.
#
# Environment:
#   AB_REF        baseline label for the delta table. Defaults per lane:
#                 E0 for the mainline lane, V0 for deepseek-vision-tune, so
#                 a vision cell can never pick up a mainline reference file.
#   SKIP_BOOT=1   re-run the bench against the already-running stack (no
#                 knob re-apply, no reboot) — for a re-measure.
#   SKIP_PROBE=1  skip the warm prefix-cache probe.
#
# Rebooting tears down whatever cluster profile is live: the lanes are
# exclusive by design, so this IS the disruption the campaign budgeted for.
# =====================================================================
set -Eeuo pipefail

CELL="${1:?usage: ab-run-cell.sh <cell> <label> <profile>}"
LABEL="${2:?usage: ab-run-cell.sh <cell> <label> <profile>}"
PROFILE="${3:?usage: ab-run-cell.sh <cell> <label> <profile>  (no default, see header)}"
cd "$(dirname "$0")/.." || exit 1

if [[ -z "${AB_REF:-}" ]]; then
  if [[ "$PROFILE" == *vision* ]]; then AB_REF=V0; else AB_REF=E0; fi
fi
export AB_REF

CONF="cluster-profiles.d/${PROFILE}.conf"
BASE="${CONF}.base"
[[ -f "$CONF" ]] || { echo "ab-run-cell: no such profile conf: $CONF" >&2; exit 1; }
[[ -f "$BASE" ]] || { echo "ab-run-cell: missing baseline copy: $BASE" >&2; exit 1; }

log(){ echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }

fail(){
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] FAIL (${CELL}): $*" >&2
  echo "--- cluster-node0 log tail ---" >&2
  docker logs --tail 40 cluster-node0 >&2 2>&1 || true
  echo "--- end log tail ---" >&2
  exit 1
}

# gb10 wait only surrenders after its own 2400 s health timeout, so a boot that
# dies in second 2 still burns 40 minutes of wall clock before the driver
# notices. V2 did exactly that. Watch OUR container instead: StartedAt is
# compared against this cell's start time so the previous stack's teardown
# (docker stop leaves a transient "Exited" before the rm) is not mistaken for
# our boot dying.
wait_or_fail(){
  local prof="$1" wlog wpid rc=0 start status started
  start=$(date -u +%Y-%m-%dT%H:%M:%S)
  wlog=$(mktemp)
  bin/gb10 wait "$prof" >"$wlog" 2>&1 &
  wpid=$!
  while kill -0 "$wpid" 2>/dev/null; do
    status=$(docker ps -a --filter name=cluster-node0 --format '{{.Status}}' | head -1 || true)
    started=$(docker inspect -f '{{.State.StartedAt}}' cluster-node0 2>/dev/null || true)
    started=${started%%.*}
    if [[ "$status" == Exited* && -n "$started" && "$started" > "$start" ]]; then
      sleep 20
      status=$(docker ps -a --filter name=cluster-node0 --format '{{.Status}}' | head -1 || true)
      if [[ "$status" == Exited* ]]; then
        kill "$wpid" 2>/dev/null || true
        wait "$wpid" 2>/dev/null || true
        tail -40 "$wlog" >&2 || true
        rm -f "$wlog"
        fail "boot failed: cluster-node0 ${status} (gb10 wait would still hang until its 2400 s timeout)"
      fi
    fi
    sleep 15
  done
  wait "$wpid" || rc=$?
  tail -30 "$wlog" || true
  rm -f "$wlog"
  [[ "$rc" == "0" ]] || fail "gb10 wait exited rc=${rc}"
}

log "cell=${CELL} label=${LABEL} profile=${PROFILE} ref=${AB_REF}"

if [[ "${SKIP_BOOT:-0}" != "1" ]]; then
  log "apply cell"
  AB_CONF="$CONF" AB_BASE="$BASE" scripts/ab-setcell.sh "$CELL" | tail -6

  log "reboot lane (exclusive: tears down the other cluster profile first)"
  bin/gb10 use "$PROFILE" 2>&1 | tail -20
  wait_or_fail "$PROFILE"

  log "compose-verify both ranks"
  scripts/cluster-compose-verify "$PROFILE" 2>&1 | tail -30

  log "smoke"
  bin/gb10 smoke 2>&1 | tail -20
fi

log "bench -> /tmp/ab-${LABEL}.txt (reference ${AB_REF})"
LABEL="$LABEL" scripts/bench-ab-deepseek.sh "$LABEL" "$PROFILE"

if [[ "${SKIP_PROBE:-0}" != "1" ]]; then
  log "warm prefix-cache probe"
  LABEL="$LABEL" scripts/bench-prefix-hit.sh
fi

log "CELL DONE ${CELL} (${LABEL})"
