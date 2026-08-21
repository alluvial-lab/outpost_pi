#!/usr/bin/env bash
# Sourceable fault controls for the live Android device E2E lane.
#
# Required environment is exported by e2e/run-live.sh. The helpers deliberately
# target only the unique Compose project for the current run.

_fault_require() {
  local name=$1
  if [[ -z "${!name:-}" ]]; then
    printf 'fault helper requires %s\n' "$name" >&2
    return 2
  fi
}

_fault_compose() {
  _fault_require E2E_COMPOSE_PROJECT || return
  _fault_require E2E_COMPOSE_FILE || return
  docker compose -p "$E2E_COMPOSE_PROJECT" -f "$E2E_COMPOSE_FILE" "$@"
}

_fault_adb() {
  _fault_require E2E_ANDROID_SERIAL || return
  "${ADB_BIN:-adb}" -s "$E2E_ANDROID_SERIAL" "$@"
}

_toxi_cli() {
  _fault_require E2E_TOXIPROXY_PORT || return
  if [[ -n "${E2E_TOXIPROXY_CLI:-}" ]]; then
    "$E2E_TOXIPROXY_CLI" \
      --host "http://127.0.0.1:${E2E_TOXIPROXY_PORT}" "$@"
    return
  fi
  docker run --rm --network host --entrypoint /toxiproxy-cli \
    ghcr.io/shopify/toxiproxy:2.12.0 \
    --host "http://127.0.0.1:${E2E_TOXIPROXY_PORT}" "$@"
}

# Remove every live-lane toxic and restore the app-relay proxy if it was down.
net_clear() {
  _toxi_cli toxic remove --toxicName live-timeout app-relay >/dev/null 2>&1 || true
  _toxi_cli toxic remove --toxicName live-slicer app-relay >/dev/null 2>&1 || true
  if ! curl --fail --silent --show-error \
      "http://127.0.0.1:${E2E_TOXIPROXY_PORT}/proxies/app-relay" \
      | grep -q '"enabled":true'; then
    _toxi_cli toggle app-relay >/dev/null
  fi
}

# Apply a timeout, slicer, or hard-down fault to the app-facing relay proxy.
net_fault() {
  local class=${1:-}
  local ms=${2:-1500}
  [[ "$ms" =~ ^[0-9]+$ ]] || { printf 'net_fault duration must be milliseconds\n' >&2; return 2; }
  net_clear
  case "$class" in
    timeout)
      _toxi_cli toxic add --toxicName live-timeout --type timeout \
        --attribute "timeout=$ms" app-relay >/dev/null
      ;;
    slicer)
      _toxi_cli toxic add --toxicName live-slicer --type slicer \
        --attribute average_size=1 --attribute size_variation=0 \
        --attribute "delay=$((ms * 1000))" app-relay >/dev/null
      ;;
    down)
      _toxi_cli toggle app-relay >/dev/null
      ;;
    *)
      printf 'usage: net_fault <timeout|slicer|down> [ms]\n' >&2
      return 2
      ;;
  esac
}

relay_pause() {
  _fault_compose pause relay >/dev/null
}

relay_resume() {
  _fault_compose unpause relay >/dev/null
}

# Preserve machine identity and owner-channel state: this models a production
# Pi process restart, unlike the reset-by-default isolation endpoint behavior.
pi_restart() {
  _fault_require E2E_PI_HOST_PORT || return
  curl --fail --silent --show-error -X POST \
    "http://127.0.0.1:${E2E_PI_HOST_PORT}/__restart?preserve=1" >/dev/null
}

app_background() {
  _fault_adb shell input keyevent KEYCODE_HOME >/dev/null
}

app_foreground() {
  _fault_adb shell am start -W -n \
    dev.kevoun.outpostpi/.MainActivity >/dev/null
}

app_airplane() {
  local state=${1:-}
  local enabled
  case "$state" in
    on) enabled=1 ;;
    off) enabled=0 ;;
    *) printf 'usage: app_airplane <on|off>\n' >&2; return 2 ;;
  esac
  _fault_adb shell cmd connectivity airplane-mode \
    "$([[ "$enabled" == 1 ]] && printf enable || printf disable)" >/dev/null
  # A device-private acknowledgement lets the instrumentation process prove
  # the adb action completed without adding a production platform channel.
  _fault_adb shell \
    "run-as dev.kevoun.outpostpi sh -c 'mkdir -p app_flutter && printf %s $state > app_flutter/.outpost_live_airplane'"
}

# Copy the private debug ring from the debuggable APK without printing content.
capture_pull() {
  local destination=${1:-.}
  local stamp path
  mkdir -p "$destination"
  stamp=$(date -u +%Y%m%dT%H%M%SZ)
  path="$destination/outpost_pi_debug-${stamp}.jsonl"
  if ! _fault_adb exec-out run-as dev.kevoun.outpostpi \
      cat app_flutter/outpost_pi_debug.jsonl >"$path" 2>/dev/null \
      || [[ ! -s "$path" ]]; then
    rm -f "$path"
    printf 'debug capture is not available on the device\n' >&2
    return 1
  fi
  chmod 600 "$path"
  printf '%s\n' "$stamp" >"$path.timestamp"
  chmod 600 "$path.timestamp"
  printf '%s\n' "$path"
}
