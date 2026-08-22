#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
COMPOSE_PROJECT="${E2E_COMPOSE_PROJECT_NAME:-outpost-pi-live-e2e-${GITHUB_RUN_ID:-local}-${GITHUB_RUN_ATTEMPT:-$$}-${RANDOM}}"
RUN_STATE="$ROOT/e2e/.run-state/$COMPOSE_PROJECT"
COMPOSE_FILE="$ROOT/e2e/docker-compose.test.yml"
COMPOSE=(docker compose -p "$COMPOSE_PROJECT" -f "$COMPOSE_FILE")
FLUTTER="${FLUTTER:-$ROOT/.tools/flutter/bin/flutter}"
EMULATOR="${EMULATOR_BIN:-/opt/android-sdk/emulator/emulator}"
ADB_BIN="${ADB_BIN:-/opt/android-sdk/platform-tools/adb}"
ANDROID_SERIAL="${E2E_ANDROID_SERIAL:-emulator-5554}"
EMULATOR_PORT=${ANDROID_SERIAL#emulator-}
TEST_SELECTOR="${1:-${E2E_LIVE_TEST_FILE:-integration_test/live_infra_smoke_test.dart}}"
case "$TEST_SELECTOR" in
  state-shapes) TEST_FILE=integration_test/live_state_shapes_test.dart ;;
  grid) TEST_FILE=integration_test/live_grid_test.dart ;;
  *) TEST_FILE="$TEST_SELECTOR" ;;
esac
case "$TEST_FILE" in
  integration_test/*.dart) ;;
  *) printf 'live test selector must be integration_test/*.dart\n' >&2; exit 2 ;;
esac
[[ "$TEST_FILE" != *..* ]] || { printf 'live test selector cannot contain ..\n' >&2; exit 2; }
[[ -f "$ROOT/app/$TEST_FILE" ]] || { printf 'live test file not found: %s\n' "$TEST_FILE" >&2; exit 2; }
EMULATOR_PID=""
TEST_PID=""
GRANT_PID=""
CAPTURED=0

export BUILDX_CONFIG="${BUILDX_CONFIG:-$RUN_STATE/buildx}"
export PUB_CACHE="${PUB_CACHE:-$ROOT/.pub-cache}"
export ANDROID_HOME="${ANDROID_HOME:-/opt/android-sdk}"
export ANDROID_SDK_ROOT="${ANDROID_SDK_ROOT:-$ANDROID_HOME}"
export JAVA_HOME="${JAVA_HOME:-/usr/lib/jvm/java-21-openjdk-amd64}"
export PATH="$ANDROID_HOME/platform-tools:$ANDROID_HOME/emulator:$PATH"
mkdir -p "$BUILDX_CONFIG"
chmod 700 "$RUN_STATE"

# shellcheck source=lib/faults.sh
source "$ROOT/e2e/lib/faults.sh"

published_port() {
  local address
  address=$("${COMPOSE[@]}" port "$1" "$2")
  printf '%s\n' "${address##*:}"
}

capture_diagnostics() {
  local capture_status=0
  if [[ "$CAPTURED" == 1 ]]; then return 0; fi
  CAPTURED=1
  if "$ADB_BIN" -s "$ANDROID_SERIAL" get-state >/dev/null 2>&1; then
    capture_pull "$RUN_STATE" >"$RUN_STATE/capture-path.txt" \
      2>"$RUN_STATE/capture-error.txt" || capture_status=$?
    "$ADB_BIN" -s "$ANDROID_SERIAL" logcat -d -t 500 >"$RUN_STATE/android-logcat.tail" 2>&1 || true
  else
    capture_status=1
  fi
  "${COMPOSE[@]}" logs --no-color pi-host >"$RUN_STATE/pi-host.log" 2>&1 || true
  "${COMPOSE[@]}" logs --no-color relay >"$RUN_STATE/relay.log" 2>&1 || true
  return "$capture_status"
}

cleanup() {
  local status=$?
  trap - EXIT INT TERM
  set +e
  [[ -n "$TEST_PID" ]] && kill "$TEST_PID" >/dev/null 2>&1
  [[ -n "$GRANT_PID" ]] && kill "$GRANT_PID" >/dev/null 2>&1
  capture_diagnostics || true
  if [[ -n "${E2E_LIVE_ARTIFACT_DIR:-}" ]]; then
    mkdir -p "$E2E_LIVE_ARTIFACT_DIR"
    cp -a "$RUN_STATE/." "$E2E_LIVE_ARTIFACT_DIR/" >/dev/null 2>&1 || true
  fi
  app_airplane off >/dev/null 2>&1 || true
  net_clear >/dev/null 2>&1 || true
  if "$ADB_BIN" -s "$ANDROID_SERIAL" get-state >/dev/null 2>&1; then
    "$ADB_BIN" -s "$ANDROID_SERIAL" emu kill >/dev/null 2>&1 || true
  fi
  [[ -n "$EMULATOR_PID" ]] && wait "$EMULATOR_PID" >/dev/null 2>&1
  if [[ "${E2E_KEEP_STACK:-0}" != "1" ]]; then
    "${COMPOSE[@]}" down -v --remove-orphans >/dev/null 2>&1 || true
  else
    printf '%s\n' "live e2e stack retained: project=$COMPOSE_PROJECT"
  fi
  rm -rf "$RUN_STATE"
  exit "$status"
}
trap cleanup EXIT INT TERM

wait_for_device_value() {
  local expected=$1
  local timeout_seconds=$2
  local deadline=$((SECONDS + timeout_seconds))
  while (( SECONDS < deadline )); do
    if [[ "$("$ADB_BIN" -s "$ANDROID_SERIAL" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" == "$expected" ]]; then
      return 0
    fi
    sleep 1
  done
  printf 'emulator did not report sys.boot_completed=%s within %ss\n' "$expected" "$timeout_seconds" >&2
  return 1
}

apply_fault_request() {
  local request=$1 action class value state
  local -a parts=()
  read -r -a parts <<<"$request"
  action=${parts[0]:-}
  case "$action" in
    net_fault)
      (( ${#parts[@]} == 2 || ${#parts[@]} == 3 )) || return 2
      class=${parts[1]}
      [[ "$class" == timeout || "$class" == slicer || "$class" == down ||
         "$class" == latency || "$class" == bandwidth || "$class" == slow_close ]] || return 2
      value=${parts[2]:-1500}
      net_fault "$class" "$value"
      ;;
    net_compound)
      (( ${#parts[@]} >= 3 )) || return 2
      net_compound "${parts[@]:1}"
      ;;
    net_clear|relay_pause|relay_resume|relay_kill|pi_restart|app_background|app_foreground)
      (( ${#parts[@]} == 1 )) || return 2
      "$action"
      ;;
    app_airplane)
      (( ${#parts[@]} == 2 )) || return 2
      state=${parts[1]}
      [[ "$state" == on || "$state" == off ]] || return 2
      app_airplane "$state"
      # adb reverse keeps emulator localhost reachable even in Android airplane
      # mode. Mirror the radio cut at the app-facing proxy so this lane observes
      # the same transport loss a physical device would.
      if [[ "$state" == on ]]; then net_fault down; else net_clear; fi
      ;;
    *)
      printf 'unsupported live fault request: %s\n' "$request" >&2
      return 2
      ;;
  esac
  printf '[live] applied %s\n' "$request" | tee -a "$RUN_STATE/faults-applied.log"
}

drive_faults() {
  local consumed=0 request
  local -a requests=()
  while true; do
    mapfile -t requests < <(
      grep -F 'OUTPOST_LIVE_FAULT_REQUEST ' "$FLUTTER_LOG" 2>/dev/null \
        | sed 's/^.*OUTPOST_LIVE_FAULT_REQUEST //'
    )
    while (( consumed < ${#requests[@]} )); do
      request=${requests[$consumed]}
      consumed=$((consumed + 1))
      apply_fault_request "$request" || return
    done
    if [[ -n "$TEST_PID" ]] && ! kill -0 "$TEST_PID" 2>/dev/null; then
      return 0
    fi
    sleep 0.2
  done
}

cd "$ROOT/pi-extension"
node_modules/.bin/tsc -p ../e2e/tsconfig.pi-host.json

if [[ -n "${OUTPOST_PI_E2E_RELAY_IMAGE:-}" ]]; then
  "${COMPOSE[@]}" build pi-host
  "${COMPOSE[@]}" up -d --no-build --wait --wait-timeout 60
else
  "${COMPOSE[@]}" up -d --build --wait --wait-timeout 60
fi

TOXI_ADMIN_PORT=$(published_port toxiproxy 8474)
TOXI_RELAY_PORT=$(published_port toxiproxy 8666)
PI_HOST_PORT=$(published_port toxiproxy 8667)
export E2E_COMPOSE_PROJECT="$COMPOSE_PROJECT"
export E2E_COMPOSE_FILE="$COMPOSE_FILE"
export E2E_TOXIPROXY_PORT="$TOXI_ADMIN_PORT"
E2E_TOXIPROXY_CLI="$RUN_STATE/toxiproxy-cli"
docker cp "$("${COMPOSE[@]}" ps -q toxiproxy):/toxiproxy-cli" \
  "$E2E_TOXIPROXY_CLI"
chmod 700 "$E2E_TOXIPROXY_CLI"
export E2E_TOXIPROXY_CLI
export E2E_PI_HOST_PORT="$PI_HOST_PORT"
export E2E_ANDROID_SERIAL="$ANDROID_SERIAL"
export ADB_BIN

for proxy in app-relay pi-host; do
  curl --silent --show-error -X DELETE \
    "http://127.0.0.1:${TOXI_ADMIN_PORT}/proxies/$proxy" >/dev/null || true
done
curl --fail --silent --show-error -H 'content-type: application/json' \
  -d '{"name":"app-relay","listen":"0.0.0.0:8666","upstream":"relay:3000","enabled":true}' \
  "http://127.0.0.1:${TOXI_ADMIN_PORT}/proxies" >/dev/null
curl --fail --silent --show-error -H 'content-type: application/json' \
  -d '{"name":"pi-host","listen":"0.0.0.0:8667","upstream":"pi-host:4317","enabled":true}' \
  "http://127.0.0.1:${TOXI_ADMIN_PORT}/proxies" >/dev/null

if "$ADB_BIN" -s "$ANDROID_SERIAL" get-state >/dev/null 2>&1; then
  printf 'refusing to reuse occupied Android serial %s\n' "$ANDROID_SERIAL" >&2
  exit 2
fi
[[ "$EMULATOR_PORT" =~ ^[0-9]+$ ]] || { printf 'E2E_ANDROID_SERIAL must be emulator-<port>\n' >&2; exit 2; }

EMULATOR_LOG="$RUN_STATE/emulator.log"
sg kvm -c "exec '$EMULATOR' -avd outpost34 -port '$EMULATOR_PORT' -no-window -gpu swiftshader_indirect -noaudio -no-boot-anim -camera-back virtualscene -no-snapshot -memory 3072" \
  >"$EMULATOR_LOG" 2>&1 &
EMULATOR_PID=$!
wait_for_device_value 1 180
"$ADB_BIN" -s "$ANDROID_SERIAL" shell settings put global window_animation_scale 0
"$ADB_BIN" -s "$ANDROID_SERIAL" shell settings put global transition_animation_scale 0
"$ADB_BIN" -s "$ANDROID_SERIAL" shell settings put global animator_duration_scale 0

for port in "$TOXI_ADMIN_PORT" "$TOXI_RELAY_PORT" "$PI_HOST_PORT"; do
  "$ADB_BIN" -s "$ANDROID_SERIAL" reverse "tcp:$port" "tcp:$port"
done

cd "$ROOT/app"
"$FLUTTER" build apk --debug --no-pub
"$ADB_BIN" -s "$ANDROID_SERIAL" install -r \
  "$ROOT/app/build/app/outputs/flutter-apk/app-debug.apk" >/dev/null

"$ADB_BIN" -s "$ANDROID_SERIAL" shell pm clear dev.kevoun.outpostpi >/dev/null

grant_loop() {
  while kill -0 "$TEST_PID" 2>/dev/null; do
    "$ADB_BIN" -s "$ANDROID_SERIAL" shell pm grant \
      dev.kevoun.outpostpi android.permission.CAMERA >/dev/null 2>&1 || true
    if "$ADB_BIN" -s "$ANDROID_SERIAL" shell dumpsys package dev.kevoun.outpostpi \
        | grep -q 'android.permission.CAMERA: granted=true'; then
      return
    fi
    if "$ADB_BIN" -s "$ANDROID_SERIAL" shell uiautomator dump /sdcard/ui.xml >/dev/null 2>&1; then
      local bounds coords
      bounds=$("$ADB_BIN" -s "$ANDROID_SERIAL" shell cat /sdcard/ui.xml 2>/dev/null \
        | tr '>' '\n' | grep 'While using the app' \
        | grep -o 'bounds="\[[0-9]*,[0-9]*\]\[[0-9]*,[0-9]*\]"' | head -1 || true)
      if [[ -n "$bounds" ]]; then
        coords=$(printf '%s' "$bounds" | grep -oE '[0-9]+,[0-9]+' | tr ',\n' '  ')
        # shellcheck disable=SC2086
        set -- $coords
        if [[ $# -ge 4 ]]; then
          "$ADB_BIN" -s "$ANDROID_SERIAL" shell input tap \
            $(( ($1 + $3) / 2 )) $(( ($2 + $4) / 2 )) >/dev/null
        fi
      fi
    fi
    sleep 0.5
  done
}

run_device_test() {
  local phase=${1:-} label=${1:-all}
  local -a phase_define=()
  [[ -z "$phase" ]] || phase_define+=(--dart-define="E2E_LIVE_PHASE=$phase")
  FLUTTER_LOG="$RUN_STATE/flutter-live-${label}.log"
  : >"$FLUTTER_LOG"
  set +e
  timeout --signal=TERM "${E2E_LIVE_TIMEOUT_SECONDS:-660}s" "$FLUTTER" test --no-pub \
    "$TEST_FILE" \
    -d "$ANDROID_SERIAL" --tags e2e --no-uninstall \
    --dart-define="E2E_PI_HOST_URL=http://127.0.0.1:${PI_HOST_PORT}" \
    --dart-define="E2E_RELAY_URL=http://127.0.0.1:${TOXI_RELAY_PORT}" \
    "${phase_define[@]}" \
    > >(tee "$FLUTTER_LOG") 2>&1 &
  TEST_PID=$!
  set -e

  grant_loop &
  GRANT_PID=$!
  set +e
  drive_faults
  local driver_status=$?
  if [[ "$driver_status" -ne 0 ]]; then
    kill "$TEST_PID" >/dev/null 2>&1 || true
  fi
  wait "$TEST_PID"
  local flutter_status=$?
  kill "$GRANT_PID" >/dev/null 2>&1 || true
  wait "$GRANT_PID" >/dev/null 2>&1 || true
  GRANT_PID=""
  TEST_PID=""
  set -e

  if [[ "$driver_status" -ne 0 ]]; then return "$driver_status"; fi
  if [[ "$flutter_status" -ne 0 ]]; then
    printf '%s\n' '===== flutter live tail =====' >&2
    tail -120 "$FLUTTER_LOG" >&2 || true
    printf '%s\n' '===== pi-host tail =====' >&2
    "${COMPOSE[@]}" logs --no-color pi-host | tail -120 >&2 || true
    return "$flutter_status"
  fi
}

if [[ "$TEST_FILE" == integration_test/live_golden_test.dart ]]; then
  run_device_test pair-chat
  "$ADB_BIN" -s "$ANDROID_SERIAL" shell am force-stop dev.kevoun.outpostpi
  run_device_test cold-open
  "$ADB_BIN" -s "$ANDROID_SERIAL" shell am force-stop dev.kevoun.outpostpi
  run_device_test reconnect
elif [[ "$TEST_FILE" == integration_test/live_failure_test.dart ]]; then
  run_device_test failure-main
  "$ADB_BIN" -s "$ANDROID_SERIAL" shell am force-stop dev.kevoun.outpostpi
  run_device_test blank-cold
elif [[ "$TEST_FILE" == integration_test/live_grid_test.dart ]]; then
  run_device_test grid-main
  "$ADB_BIN" -s "$ANDROID_SERIAL" shell am force-stop dev.kevoun.outpostpi
  run_device_test grid-cold
else
  run_device_test
fi

CAPTURE_STATUS=0
capture_diagnostics || CAPTURE_STATUS=$?
if [[ "$CAPTURE_STATUS" -ne 0 ]]; then
  printf '%s\n' 'live device debug capture pull failed' >&2
  exit "$CAPTURE_STATUS"
fi

printf 'live device e2e passed: %s + capture\n' "$TEST_FILE"
