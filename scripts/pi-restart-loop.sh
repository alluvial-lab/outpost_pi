#!/usr/bin/env bash
# Run interactive pi under an explicit hot-reload restart handshake.
#
# A hot-reload request writes .restart-marker before sending SIGTERM. Pi's
# graceful shutdown exits with code 0; only that marker authorizes relaunch.
# Normal /quit (also exit 0) and crashes stop the loop.

set -euo pipefail

CWD="${1:-$(pwd)}"
if [ "${1:-}" = "$CWD" ]; then shift; fi
PI_ARGS=("--continue" "$@")
REMOTE_DIR="${OUTPOST_PI_HOME:-$HOME/.pi/remote}"
MARKER="$REMOTE_DIR/.restart-marker"

echo "[pi-restart-loop] cwd=$CWD args=${PI_ARGS[*]}"
echo "[pi-restart-loop] restart handshake: $MARKER"

cd "$CWD"

while true; do
  set +e
  pi "${PI_ARGS[@]}"
  exit_code=$?
  set -e

  echo "[pi-restart-loop] pi exited with code $exit_code at $(date -u +%FT%TZ)"

  if [ "$exit_code" -eq 0 ] && [ -f "$MARKER" ] && [ ! -L "$MARKER" ]; then
    rm -f -- "$MARKER"
    echo "[pi-restart-loop] restart marker consumed → relaunching in 1s"
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
