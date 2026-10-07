#!/usr/bin/env bash
# Run interactive pi under explicit restart handshakes.
#
# A hot-reload request writes .restart-marker-<PID> before sending SIGTERM. Pi's
# graceful shutdown exits with code 0; a restart marker authorizes relaunch with
# --continue. Mobile /new exits 42; that authorizes exactly one relaunch without
# --continue, after which later hot reloads resume with --continue. Normal /quit
# (exit 0 without a marker) and all other non-zero exits stop the loop.
#
# Fresh start: `--fresh-first` (or PI_RESTART_FRESH=1) drops `--continue` on the
# FIRST iteration only, then resumes the normal hot-reload --continue cadence.
# Use it when the stored latest session predates skill/package wiring changes —
# pi's --continue resumes the STORED system message, so wiring changes only
# reach a FRESH session (upstream pi-core behavior; see
# pi-extension/docs/daemon.md).
#
# Every lifecycle event is appended to
# $OUTPOST_PI_HOME/logs/pi-restart-loop-<roomId>.log (roomId = the same
# per-folder identity the cwd lock uses) in addition to stdout, so a relaunch
# that dies without a trace on the terminal survives in the log. A
# marker/fresh-authorized relaunch that exits within
# $OUTPOST_PI_RELAUNCH_FAST_WINDOW seconds (default 5) gets a
# RELAUNCH-FAILED-FAST record with the evidence needed to diagnose it.
#
# pi MUST run in the foreground (it's a TUI app — backgrounding it disconnects
# the terminal and pi exits immediately). A foreground exec shim records the pi
# child PID; after exit, the wrapper checks only that child's owner-only regular
# marker. Foreign or malformed markers are never consumed.

set -euo pipefail

# Ensure pi is on PATH (tmux/systemd contexts may not source ~/.bashrc).
export PATH="$HOME/.local/bin:$PATH"

# First positional arg is pi's cwd ONLY when it names an existing directory;
# everything else (e.g. `--continue` alone) passes through to pi. The old
# `CWD="${1:-$(pwd)}"` form always consumed $1 because the comparison matched
# itself — `--continue` became a bogus cwd and broke `cd`.
CWD="$(pwd)"
if [ "${1:-}" != "" ] && [ -d "$1" ]; then CWD="$1"; shift; fi
PI_ARGS=("$@")
# Fresh-start opt-in: env form for tmux/systemd launch lines, argv form for
# interactive use. Intercepted BEFORE pi sees it — it is a wrapper flag, not a
# pi flag (left in place it would be a bogus prompt/flag for pi).
fresh_first=0
if [ "${PI_RESTART_FRESH:-0}" = "1" ]; then fresh_first=1; fi
filtered_args=()
for arg in ${PI_ARGS[@]+"${PI_ARGS[@]}"}; do
  if [ "$arg" = "--fresh-first" ]; then
    fresh_first=1
  else
    filtered_args+=("$arg")
  fi
done
PI_ARGS=(${filtered_args[@]+"${filtered_args[@]}"})
REMOTE_DIR="${OUTPOST_PI_HOME:-$HOME/.pi/remote}"
LOG_DIR="$REMOTE_DIR/logs"
# Same derivation as the extension's roomIdForCwd / cwd-lock id: first 12
# base64url chars of sha256(realpath(cwd)) — cross-references naturally with
# ~/.pi/remote/locks/<roomId>.sock.
room_id() {
  local real
  real="$(cd -- "$CWD" && pwd -P)" || real="$CWD"
  printf '%s' "$real" | openssl dgst -sha256 -binary | base64 | tr '+/' '-_' | cut -c1-12
}
LOG_FILE="$LOG_DIR/pi-restart-loop-$(room_id).log"
LOG_MAX_BYTES=$((1024 * 1024))
RELAUNCH_FAST_WINDOW="${OUTPOST_PI_RELAUNCH_FAST_WINDOW:-5}"
CHILD_PID_FILE="$(mktemp "${TMPDIR:-/tmp}/outpost-pi-child.XXXXXX")"
trap 'rm -f -- "$CHILD_PID_FILE"' EXIT
# Must match pi-extension/src/daemon/rpc_child.ts EXIT_FRESH_SESSION.
EXIT_FRESH_SESSION=42
# This is the extension's safety gate: only this wrapper and the daemon
# supervisor are allowed to turn a mobile /new request into process exit.
export OUTPOST_PI_UNDER_RESTART_WRAPPER=1
# fresh_first seeds fresh_launch: the FIRST iteration runs without --continue.
fresh_launch="$fresh_first"

# Append one timestamped line to the persistent per-folder log (best-effort:
# log trouble must never take the wrapper down). Rotation keeps a single .1
# generation past the 1 MiB cap.
log_only() {
  if ! mkdir -m 700 -p "$LOG_DIR" 2>/dev/null; then return 0; fi
  if [ -f "$LOG_FILE" ]; then
    local size
    size="$(wc -c <"$LOG_FILE" 2>/dev/null || echo 0)"
    if [ "$size" -gt "$LOG_MAX_BYTES" ]; then
      mv -f -- "$LOG_FILE" "$LOG_FILE.1" 2>/dev/null || true
    fi
  fi
  printf '%s %s\n' "$(date -u +%FT%TZ)" "$*" >>"$LOG_FILE" 2>/dev/null || true
}

# Lifecycle line: stdout (tmux pane) AND the persistent log — the log is what
# survives a dying PTY, which is the failure mode this exists for.
log() {
  echo "[pi-restart-loop] $*"
  log_only "$*"
}

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

log "cwd=$CWD args=${PI_ARGS[*]:-} fresh-first=$fresh_first log=$LOG_FILE"

cd -- "$CWD"

# True for the run immediately following a relaunch authorization (marker
# consumed / fresh-session exit / fresh-first start) — the run whose
# instant death is the silent-failure mode this log exists to expose.
run_was_relaunch=0
[ "$fresh_first" -eq 1 ] && run_was_relaunch=1

while true; do
  # Run pi in the FOREGROUND so it gets the terminal (TUI requires it).
  # Backgrounding pi (+ wait) breaks the TUI — pi exits immediately.
  : > "$CHILD_PID_FILE"
  launch_epoch="$(date +%s)"
  set +e
  if [ "$fresh_launch" -eq 1 ]; then
    fresh_launch=0
    run_pi_foreground "$CHILD_PID_FILE" "${PI_ARGS[@]}"
  else
    run_pi_foreground "$CHILD_PID_FILE" --continue "${PI_ARGS[@]}"
  fi
  exit_code=$?
  set -e
  elapsed=$(( $(date +%s) - launch_epoch ))
  was_relaunch="$run_was_relaunch"
  run_was_relaunch=0

  child_pid="$(tr -d '[:space:]' < "$CHILD_PID_FILE")"
  if ! [[ "$child_pid" =~ ^[0-9]+$ ]]; then
    log "could not determine exited pi child PID → stopping loop"
    break
  fi
  log "pi pid=$child_pid exited with code $exit_code at $(date -u +%FT%TZ) after ${elapsed}s"

  if [ "$exit_code" -eq "$EXIT_FRESH_SESSION" ]; then
    fresh_launch=1
    run_was_relaunch=1
    log "fresh-session exit ($EXIT_FRESH_SESSION) → relaunching once without --continue in 1s"
    sleep 1
    continue
  fi

  # Only a graceful exit (0) plus this exact child's validated marker authorizes
  # relaunch. Foreign PID markers remain untouched for their owning wrappers.
  if [ "$exit_code" -eq 0 ]; then
    marker="$REMOTE_DIR/.restart-marker-$child_pid"
    if [ -e "$marker" ] || [ -L "$marker" ]; then
      if ! validate_marker "$marker"; then
        log "refusing invalid restart marker for pid=$child_pid: $marker"
        log "stopping loop (invalid marker)"
        break
      fi
      rm -f -- "$marker"
      run_was_relaunch=1
      log "restart marker consumed ($marker) → relaunching in 1s"
      sleep 1
      continue
    fi
    if [ "$was_relaunch" -eq 1 ] && [ "$elapsed" -le "$RELAUNCH_FAST_WINDOW" ]; then
      log "RELAUNCH-FAILED-FAST: pi quit gracefully ${elapsed}s after a relaunch (exit $exit_code, no marker) — cwd=$CWD pi=$(command -v pi || echo '?') child_pid=$child_pid; if unexpected, check the pi version/env and try a manual 'pi --continue' in this cwd"
    fi
    log "graceful exit without restart marker for pid=$child_pid → stopping loop"
    break
  fi

  if [ "$was_relaunch" -eq 1 ] && [ "$elapsed" -le "$RELAUNCH_FAST_WINDOW" ]; then
    log "RELAUNCH-FAILED-FAST: pi died ${elapsed}s after a relaunch (exit $exit_code) — cwd=$CWD pi=$(command -v pi || echo '?') child_pid=$child_pid; if unexpected, check the pi version/env and try a manual 'pi --continue' in this cwd"
  fi
  log "non-zero exit ($exit_code) → stopping loop (crash safety)"
  break
done
