#!/usr/bin/env bash
# hot-reload.sh — manage the outpost-pi extension hot-reload toggle.
#
# The extension hot-reloads dist/ via a process restart: at turn_end, if the
# toggle is enabled AND a restart is requested (sentinel), the extension sends
# SIGTERM to pi. The restart-loop wrapper (pi-restart-loop.sh) relaunches
# pi --continue with a fresh ESM cache, loading the new dist/.
#
# Two state files in ~/.pi/remote/ (or $OUTPOST_PI_HOME):
#   .hot-reload-enabled  — persistent toggle (presence = on)
#   .restart-pending     — transient trigger (consumed at turn_end)
#
# Usage:
#   hot-reload.sh on       Enable the hot-reload toggle (persistent)
#   hot-reload.sh off      Disable the toggle (sentinels are ignored)
#   hot-reload.sh arm      Request a restart at the next turn_end (touch sentinel)
#   hot-reload.sh status   Show current state
#   hot-reload.sh on+arm   Enable + arm in one step (convenient after a dist/ rebuild)

set -euo pipefail

REMOTE_DIR="${OUTPOST_PI_HOME:-$HOME/.pi/remote}"
TOGGLE="$REMOTE_DIR/.hot-reload-enabled"
SENTINEL="$REMOTE_DIR/.restart-pending"

cmd_on() {
  mkdir -p "$REMOTE_DIR"
  touch "$TOGGLE"
  echo "[hot-reload] enabled (toggle on) — $TOGGLE"
}

cmd_off() {
  rm -f "$TOGGLE"
  echo "[hot-reload] disabled (toggle off) — $TOGGLE removed"
}

cmd_arm() {
  if [ ! -f "$TOGGLE" ]; then
    echo "[hot-reload] WARNING: toggle is off — sentinel will be ignored." >&2
    echo "[hot-reload] Run 'hot-reload.sh on' first, or 'hot-reload.sh on+arm'." >&2
  fi
  mkdir -p "$REMOTE_DIR"
  touch "$SENTINEL"
  echo "[hot-reload] armed — restart will fire at the next turn_end — $SENTINEL"
}

cmd_status() {
  local toggle_state="off"
  local sentinel_state="absent"
  [ -f "$TOGGLE" ] && toggle_state="on"
  [ -f "$SENTINEL" ] && sentinel_state="present"
  echo "[hot-reload] toggle: $toggle_state  sentinel: $sentinel_state"
  echo "[hot-reload]   toggle:  $TOGGLE"
  echo "[hot-reload]   sentinel: $SENTINEL"
  if [ "$toggle_state" = "on" ] && [ "$sentinel_state" = "present" ]; then
    echo "[hot-reload] → restart will fire at the next turn_end"
  elif [ "$toggle_state" = "on" ]; then
    echo "[hot-reload] → enabled but no restart requested (run 'arm' after rebuilding dist/)"
  else
    echo "[hot-reload] → disabled (sentinels ignored)"
  fi
}

case "${1:-status}" in
  on)       cmd_on ;;
  off)      cmd_off ;;
  arm)      cmd_arm ;;
  status)   cmd_status ;;
  on+arm)   cmd_on; cmd_arm ;;
  *)
    echo "Usage: $0 {on|off|arm|status|on+arm}" >&2
    exit 1
    ;;
esac
