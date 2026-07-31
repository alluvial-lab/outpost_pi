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

stat_mode() {
  stat -c '%a' "$1" 2>/dev/null || stat -f '%Lp' "$1"
}

stat_uid() {
  stat -c '%u' "$1" 2>/dev/null || stat -f '%u' "$1"
}

validate_dir() {
  local mode owner
  [ ! -L "$REMOTE_DIR" ] && [ -d "$REMOTE_DIR" ] || return 1
  mode="$(stat_mode "$REMOTE_DIR")"
  owner="$(stat_uid "$REMOTE_DIR")"
  [ "$mode" = "700" ] && [ "$owner" = "$(id -u)" ]
}

validate_file() {
  local path="$1" mode owner
  [ ! -L "$path" ] && [ -f "$path" ] || return 1
  mode="$(stat_mode "$path")"
  owner="$(stat_uid "$path")"
  [ "$mode" = "600" ] && [ "$owner" = "$(id -u)" ]
}

ensure_dir() {
  if [ -L "$REMOTE_DIR" ]; then
    echo "[hot-reload] refusing symlink state directory: $REMOTE_DIR" >&2
    return 1
  fi
  mkdir -p "$REMOTE_DIR"
  if ! validate_dir; then
    echo "[hot-reload] state directory must be owner-only (0700): $REMOTE_DIR" >&2
    return 1
  fi
}

cmd_on() {
  ensure_dir
  if [ -e "$TOGGLE" ] || [ -L "$TOGGLE" ]; then
    validate_file "$TOGGLE" || {
      echo "[hot-reload] toggle exists but is not an owner-only regular file: $TOGGLE" >&2
      return 1
    }
  else
    (umask 077; printf '' > "$TOGGLE")
  fi
  chmod 600 "$TOGGLE"
  echo "[hot-reload] enabled (toggle on) — $TOGGLE"
}

cmd_off() {
  if [ -e "$REMOTE_DIR" ] || [ -L "$REMOTE_DIR" ]; then
    ensure_dir
  fi
  rm -f -- "$TOGGLE"
  # Disable is also a cleanup boundary: no request or wrapper marker should
  # survive into a later enable cycle or a different process occupying a PID.
  rm -f -- \
    "$REMOTE_DIR"/.hot-reload-armed-* \
    "$REMOTE_DIR"/.runtime-self-* \
    "$REMOTE_DIR"/.claimed-* \
    "$REMOTE_DIR"/.restart-marker-* \
    "$REMOTE_DIR"/.restart-pending-*
  echo "[hot-reload] disabled (toggle off) — pending runtime state removed"
}

cmd_arm() {
  local pid identity nonce armed
  ensure_dir
  if ! validate_file "$TOGGLE"; then
    echo "[hot-reload] toggle is off — run 'hot-reload.sh on' first" >&2
    return 1
  fi
  pid="$(ps -o ppid= -p $$ | tr -d '[:space:]')"
  if [ -z "$pid" ] || ! [[ "$pid" =~ ^[0-9]+$ ]]; then
    echo "[hot-reload] could not discover the pi parent PID" >&2
    return 1
  fi
  identity="$REMOTE_DIR/.runtime-self-$pid"
  if ! validate_file "$identity"; then
    echo "[hot-reload] no secure runtime identity for pid=$pid — is pi running?" >&2
    return 1
  fi
  nonce="$(python3 - "$identity" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as stream:
    identity = json.load(stream)
if identity.get("pid") != int(sys.argv[1].rsplit("-", 1)[-1]):
    raise SystemExit("runtime identity PID mismatch")
nonce = identity.get("nonce")
if not isinstance(nonce, str) or not nonce:
    raise SystemExit("runtime identity has no nonce")
print(nonce)
PY
)"
  armed="$REMOTE_DIR/.hot-reload-armed-$pid"
  if ! python3 - "$armed" "$nonce" <<'PY'
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
  then
    echo "[hot-reload] already armed for pid=$pid" >&2
    return 1
  fi
  echo "[hot-reload] armed for pid=$pid — restart at next agent_settled"
}

cmd_status() {
  local toggle_state="off"
  [ -f "$TOGGLE" ] && [ ! -L "$TOGGLE" ] && toggle_state="on"
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
