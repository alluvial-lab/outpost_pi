#!/usr/bin/env bash
# Run interactive pi under an explicit hot-reload restart handshake.
#
# A hot-reload request writes .restart-marker-<PID> before sending SIGTERM. Pi's
# graceful shutdown exits with code 0; a restart marker authorizes relaunch.
# Normal /quit (also exit 0) and crashes stop the loop.
#
# pi MUST run in the foreground (it's a TUI app — backgrounding it disconnects
# the terminal and pi exits immediately). The marker is checked via glob after
# pi exits; the PID in the filename is for the extension's tracking, the wrapper
# just checks for presence of any recent marker.

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
  # Run pi in the FOREGROUND so it gets the terminal (TUI requires it).
  # Backgrounding pi (+ wait) breaks the TUI — pi exits immediately.
  set +e
  pi "${PI_ARGS[@]}"
  exit_code=$?
  set -e

  echo "[pi-restart-loop] pi exited with code $exit_code at $(date -u +%FT%TZ)"

  # Check for a restart marker (PID-scoped filename, globbed by the wrapper).
  # Only a graceful exit (0) + a marker authorizes relaunch.
  if [ "$exit_code" -eq 0 ]; then
    marker=""
    for f in "$REMOTE_DIR"/.restart-marker-*; do
      # glob didn't match (no marker) → literal pattern string
      [ -e "$f" ] || continue
      [ -L "$f" ] && continue  # reject symlinks
      marker="$f"
      break
    done
    if [ -n "$marker" ]; then
      rm -f -- "$marker"
      echo "[pi-restart-loop] restart marker consumed ($marker) → relaunching in 1s"
      sleep 1
      continue
    fi
    echo "[pi-restart-loop] graceful exit without restart marker → stopping loop"
    break
  fi

  echo "[pi-restart-loop] non-zero exit ($exit_code) → stopping loop (crash safety)"
  break
done
