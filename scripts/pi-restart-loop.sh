#!/usr/bin/env bash
# pi-restart-loop.sh — run interactive pi under a restart loop so a
# graceful SIGTERM (from the agent itself, or from `kill -TERM $(pgrep -x pi)`)
# causes pi to shut down cleanly and relaunch with a fresh ESM cache.
#
# WHY: pi's `/reload` does NOT re-import a `type: module` (ESM) extension.
# jiti's async path uses nativeImport = (id) => import(id), which hits
# Node's ESM cache — immutable at runtime. A full process restart is the
# only way to clear it. This wrapper makes that restart cheap: the tmux
# session persists, pi --continue resumes the conversation, and the relay
# reconnects in ~2s.
#
# EXIT CODES (set by pi or the agent):
#   0   — normal quit (/quit, Ctrl+D). The loop STOPS.
#   42  — restart requested (agent-triggered extension reload). The loop RELAUNCHES.
#   *   — any other exit (crash, SIGKILL). The loop STOPS (don't auto-restart crashes).
#
# USAGE:
#   tmux new -d -s outpost "cd /home/agent/projects/outpost_pi && ./scripts/pi-restart-loop.sh"
#   tmux attach -t outpost
#
# To trigger a restart from within pi (e.g. after rebuilding dist/):
#   kill -TERM $(pgrep -x pi)     # graceful: session_shutdown → working=false → exit 0
#   # OR, for an explicit restart code:
#   kill -USR1 $(pgrep -x pi)    # (if wired) → exit 42 → relaunch
#
# Currently SIGTERM is the trigger: pi's signal handler exits 0 (graceful).
# To distinguish "restart" from "quit", use USR1 (exit 42) vs TERM/quit (exit 0).
# For now, the loop treats exit 0 from a signal as "relaunch" only when
# RESTART_ON_EXIT_ZERO=1 is set; otherwise exit 0 stops the loop.

set -euo pipefail

CWD="${1:-$(pwd)}"
# Shift off the cwd argument if provided so remaining args pass to pi.
if [ "${1:-}" = "$CWD" ]; then shift; fi

PI_ARGS=("--continue" "$@")

# Whether to relaunch when pi exits 0 (normal quit). Default: no (stop).
# Set RESTART_ON_EXIT_ZERO=1 to relaunch on any clean exit (signal or /quit).
RESTART_ON_EXIT_ZERO="${RESTART_ON_EXIT_ZERO:-0}"

echo "[pi-restart-loop] cwd=$CWD args=${PI_ARGS[*]}"
echo "[pi-restart-loop] RESTART_ON_EXIT_ZERO=$RESTART_ON_EXIT_ZERO"

cd "$CWD"

while true; do
  # Run pi. If it exits non-zero from a crash, capture the code.
  set +e
  pi "${PI_ARGS[@]}"
  exit_code=$?
  set -e

  echo "[pi-restart-loop] pi exited with code $exit_code at $(date -u +%FT%TZ)"

  # Exit 42 = explicit restart request → always relaunch.
  if [ "$exit_code" -eq 42 ]; then
    echo "[pi-restart-loop] restart requested (exit 42) → relaunching in 1s..."
    sleep 1
    continue
  fi

  # Exit 0 = graceful quit.
  if [ "$exit_code" -eq 0 ]; then
    if [ "$RESTART_ON_EXIT_ZERO" = "1" ]; then
      echo "[pi-restart-loop] graceful exit 0, RESTART_ON_EXIT_ZERO=1 → relaunching in 1s..."
      sleep 1
      continue
    fi
    echo "[pi-restart-loop] graceful exit 0 → stopping loop."
    break
  fi

  # Any other exit code = crash or signal. Do NOT auto-restart (avoid loops).
  echo "[pi-restart-loop] non-zero exit ($exit_code) → stopping loop (crash safety)."
  echo "[pi-restart-loop] to retry manually: re-run this script."
  break
done
