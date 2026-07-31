#!/usr/bin/env bash
# Manage process-scoped extension hot reload.
#
# The extension publishes .runtime-self-<PID> on session_start. `arm` follows
# the shell's parent PID to that runtime identity, then creates a nonce-bound
# .hot-reload-armed-<PID>. The extension consumes it at agent_settled and writes
# .restart-marker before graceful SIGTERM.

set -euo pipefail
umask 077

REMOTE_DIR="${OUTPOST_PI_HOME:-$HOME/.pi/remote}"
TOGGLE="$REMOTE_DIR/.hot-reload-enabled"

ensure_dir() {
  mkdir -p "$REMOTE_DIR"
}

cmd_on() {
  ensure_dir
  if [ ! -e "$TOGGLE" ]; then
    (umask 077; printf '' > "$TOGGLE")
  fi
  chmod 600 "$TOGGLE"
  echo "[hot-reload] enabled (toggle on) — $TOGGLE"
}

cmd_off() {
  rm -f -- "$TOGGLE"
  # Disable is also a cleanup boundary: no request or wrapper marker should
  # survive into a later enable cycle or a different process occupying a PID.
  rm -f -- \
    "$REMOTE_DIR"/.hot-reload-armed-* \
    "$REMOTE_DIR"/.runtime-self-* \
    "$REMOTE_DIR"/.claimed-* \
    "$REMOTE_DIR"/.restart-marker
  echo "[hot-reload] disabled (toggle off) — pending runtime state removed"
}

cmd_arm() {
  local pid identity nonce armed
  if [ ! -f "$TOGGLE" ]; then
    echo "[hot-reload] toggle is off — run 'hot-reload.sh on' first" >&2
    return 1
  fi
  ensure_dir
  pid="$(ps -o ppid= -p $$ | tr -d '[:space:]')"
  if [ -z "$pid" ] || ! [[ "$pid" =~ ^[0-9]+$ ]]; then
    echo "[hot-reload] could not discover the pi parent PID" >&2
    return 1
  fi
  identity="$REMOTE_DIR/.runtime-self-$pid"
  if [ ! -f "$identity" ]; then
    echo "[hot-reload] no runtime identity for pid=$pid — is pi running?" >&2
    return 1
  fi
  nonce="$(python3 - "$identity" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as stream:
    identity = json.load(stream)
nonce = identity.get("nonce")
if not isinstance(nonce, str) or not nonce:
    raise SystemExit("runtime identity has no nonce")
print(nonce)
PY
)"
  armed="$REMOTE_DIR/.hot-reload-armed-$pid"
  python3 - "$armed" "$nonce" <<'PY'
import json
import os
import sys
import time

path, nonce = sys.argv[1:]
fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
try:
    payload = json.dumps({"nonce": nonce, "ts": int(time.time() * 1000)})
    os.write(fd, payload.encode("utf-8"))
finally:
    os.close(fd)
PY
  echo "[hot-reload] armed for pid=$pid — restart at next agent_settled"
}

cmd_status() {
  local toggle_state="off"
  [ -f "$TOGGLE" ] && toggle_state="on"
  echo "[hot-reload] toggle: $toggle_state"
  echo "[hot-reload]   toggle: $TOGGLE"
  echo "[hot-reload]   runtime identities: $REMOTE_DIR/.runtime-self-*"
  echo "[hot-reload]   armed requests: $REMOTE_DIR/.hot-reload-armed-*"
  if [ "$toggle_state" = "on" ]; then
    echo "[hot-reload] → enabled; arm from the Pi shell or /outpost-pi hot-reload arm"
  else
    echo "[hot-reload] → disabled"
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
