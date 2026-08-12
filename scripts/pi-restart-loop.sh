#!/usr/bin/env bash
# Run interactive pi under explicit restart handshakes.
#
# A hot-reload request writes .restart-marker-<PID> before sending SIGTERM. Pi's
# graceful shutdown exits with code 0; a restart marker authorizes relaunch with
# --continue. Mobile /new exits 42; that authorizes exactly one relaunch without
# --continue, after which later hot reloads resume with --continue. Normal /quit
# (exit 0 without a marker) and all other non-zero exits stop the loop.
#
# pi MUST run in the foreground (it's a TUI app — backgrounding it disconnects
# the terminal and pi exits immediately). A foreground exec shim records the pi
# child PID; after exit, the wrapper checks only that child's owner-only regular
# marker. Foreign or malformed markers are never consumed.

set -euo pipefail

# Ensure pi is on PATH (tmux/systemd contexts may not source ~/.bashrc).
export PATH="$HOME/.local/bin:$PATH"

CWD="${1:-$(pwd)}"
if [ "${1:-}" = "$CWD" ]; then shift; fi
PI_ARGS=("$@")
REMOTE_DIR="${OUTPOST_PI_HOME:-$HOME/.pi/remote}"
CHILD_PID_FILE="$(mktemp "${TMPDIR:-/tmp}/outpost-pi-child.XXXXXX")"
trap 'rm -f -- "$CHILD_PID_FILE"' EXIT
# Must match pi-extension/src/daemon/rpc_child.ts EXIT_FRESH_SESSION.
EXIT_FRESH_SESSION=42
# This is the extension's safety gate: only this wrapper and the daemon
# supervisor are allowed to turn a mobile /new request into process exit.
export OUTPOST_PI_UNDER_RESTART_WRAPPER=1
fresh_launch=0

stat_mode() {
  stat -c '%a' "$1" 2>/dev/null || stat -f '%Lp' "$1"
}

stat_uid() {
  stat -c '%u' "$1" 2>/dev/null || stat -f '%u' "$1"
}

validate_marker() {
  local path="$1" mode owner
  [ ! -L "$path" ] && [ -f "$path" ] || return 1
  mode="$(stat_mode "$path")"
  owner="$(stat_uid "$path")"
  [ "$mode" = "600" ] && [ "$owner" = "$(id -u)" ]
}

run_pi_foreground() {
  local pid_file="$1"
  shift
  # The shim stays in the foreground and execs pi, so its recorded PID is the
  # exact pi process PID without breaking TUI terminal ownership.
  "$BASH" -c 'set -e; pid_file="$1"; shift; printf "%s\n" "$$" > "$pid_file"; exec pi "$@"' \
    outpost-pi-child "$pid_file" "$@"
}

echo "[pi-restart-loop] cwd=$CWD args=${PI_ARGS[*]}"

cd "$CWD"

while true; do
  # Run pi in the FOREGROUND so it gets the terminal (TUI requires it).
  # Backgrounding pi (+ wait) breaks the TUI — pi exits immediately.
  : > "$CHILD_PID_FILE"
  set +e
  if [ "$fresh_launch" -eq 1 ]; then
    fresh_launch=0
    run_pi_foreground "$CHILD_PID_FILE" "${PI_ARGS[@]}"
  else
    run_pi_foreground "$CHILD_PID_FILE" --continue "${PI_ARGS[@]}"
  fi
  exit_code=$?
  set -e

  child_pid="$(tr -d '[:space:]' < "$CHILD_PID_FILE")"
  if ! [[ "$child_pid" =~ ^[0-9]+$ ]]; then
    echo "[pi-restart-loop] could not determine exited pi child PID → stopping loop" >&2
    break
  fi
  echo "[pi-restart-loop] pi pid=$child_pid exited with code $exit_code at $(date -u +%FT%TZ)"

  if [ "$exit_code" -eq "$EXIT_FRESH_SESSION" ]; then
    fresh_launch=1
    echo "[pi-restart-loop] fresh-session exit ($EXIT_FRESH_SESSION) → relaunching once without --continue in 1s"
    sleep 1
    continue
  fi

  # Only a graceful exit (0) plus this exact child's validated marker authorizes
  # relaunch. Foreign PID markers remain untouched for their owning wrappers.
  if [ "$exit_code" -eq 0 ]; then
    marker="$REMOTE_DIR/.restart-marker-$child_pid"
    if [ -e "$marker" ] || [ -L "$marker" ]; then
      if ! validate_marker "$marker"; then
        echo "[pi-restart-loop] refusing invalid restart marker for pid=$child_pid: $marker" >&2
        break
      fi
      rm -f -- "$marker"
      echo "[pi-restart-loop] restart marker consumed ($marker) → relaunching in 1s"
      sleep 1
      continue
    fi
    echo "[pi-restart-loop] graceful exit without restart marker for pid=$child_pid → stopping loop"
    break
  fi

  echo "[pi-restart-loop] non-zero exit ($exit_code) → stopping loop (crash safety)"
  break
done
