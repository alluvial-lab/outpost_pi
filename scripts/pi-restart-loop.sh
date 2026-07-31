#!/usr/bin/env bash
# Run interactive pi under an explicit hot-reload restart handshake.
#
# A hot-reload request writes .restart-marker-<PID> before sending SIGTERM. Pi's
# graceful shutdown exits with code 0; only a marker matching the exact child PID
# authorizes relaunch. Normal /quit (also exit 0) and crashes stop the loop.
# The PID-scoped marker prevents multi-pi wrappers from consuming each other's
# restart intent.

set -euo pipefail

# Ensure pi is on PATH (tmux/systemd contexts may not source ~/.bashrc).
export PATH="$HOME/.local/bin:$PATH"

CWD="${1:-$(pwd)}"
if [ "${1:-}" = "$CWD" ]; then shift; fi
PI_ARGS=("--continue" "$@")
REMOTE_DIR="${OUTPOST_PI_HOME:-$HOME/.pi/remote}"

echo "[pi-restart-loop] cwd=$CWD args=${PI_ARGS[*]}"

cd "$CWD"

while true; do
  # Launch pi as a backgrounded child so we can capture its PID, then wait for it.
  pi "${PI_ARGS[@]}" &
  child_pid=$!
  wait "$child_pid"
  exit_code=$?

  # PID-scoped marker — only this exact child's marker authorizes relaunch.
  marker="$REMOTE_DIR/.restart-marker-$child_pid"

  echo "[pi-restart-loop] pi (pid=$child_pid) exited with code $exit_code at $(date -u +%FT%TZ)"

  if [ "$exit_code" -eq 0 ] && [ -f "$marker" ] && [ ! -L "$marker" ]; then
    rm -f -- "$marker"
    echo "[pi-restart-loop] restart marker for pid=$child_pid consumed → relaunching in 1s"
    sleep 1
    continue
  fi

  if [ "$exit_code" -eq 0 ]; then
    echo "[pi-restart-loop] graceful exit without restart marker → stopping loop"
  else
    echo "[pi-restart-loop] non-zero exit ($exit_code) → stopping loop (crash safety)"
  fi
  break
done
