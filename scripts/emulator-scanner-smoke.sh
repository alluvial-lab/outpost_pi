#!/usr/bin/env bash
# emulator-scanner-smoke.sh — run the mobile_scanner boundary integration smoke
# against the local Android emulator, handling the runtime CAMERA permission.
#
# Why this exists: `flutter test integration_test` reinstalls the app on every
# run, which clears runtime permission grants. On a headless emulator nobody
# can tap the GrantPermissionsActivity dialog, so the scanner controller never
# reaches isRunning and the smoke times out. We race the app's permission
# request: grant CAMERA as soon as the app process appears (install has
# finished by then), and tap the dialog's "While using the app" button as a
# fallback if the request beats the grant.
#
# Prereqs: emulator booted with -camera-back virtualscene (see
# .work/active/stories/story-ci-android-emulator-test-job.md); ANDROID_HOME
# platform-tools on PATH for adb.
#
# Usage: scripts/emulator-scanner-smoke.sh [serial]   (default emulator-5554)
set -uo pipefail
SERIAL="${1:-emulator-5554}"
PKG="dev.kevoun.outpostpi"
ADB_BIN="$(command -v adb || true)"
[ -z "$ADB_BIN" ] && [ -x "${ANDROID_HOME:-/opt/android-sdk}/platform-tools/adb" ] && ADB_BIN="${ANDROID_HOME:-/opt/android-sdk}/platform-tools/adb"
[ -z "$ADB_BIN" ] && { echo "[smoke] adb not found on PATH or ANDROID_HOME" >&2; exit 2; }
declare -a ADB=("$ADB_BIN" -s "$SERIAL")
cd "$(dirname "$0")/../app"

"${ADB[@]}" wait-for-device
echo "[smoke] starting flutter test (background)"
flutter test integration_test/mobile_scanner_boundary_test.dart -d "$SERIAL" --tags e2e &
TEST_PID=$!

cleanup() { kill "$TEST_PID" 2>/dev/null; }
trap cleanup EXIT

grant_loop() {
  while kill -0 "$TEST_PID" 2>/dev/null; do
    # 1) direct grant — no-op once granted; works only after install
    "${ADB[@]}" shell pm grant "$PKG" android.permission.CAMERA >/dev/null 2>&1
    # 2) dialog fallback — find "While using the app" and tap its center
    if "${ADB[@]}" shell uiautomator dump /sdcard/ui.xml >/dev/null 2>&1; then
      btn=$("${ADB[@]}" shell cat /sdcard/ui.xml 2>/dev/null | tr '>' '\n' | grep 'While using the app' | grep -o 'bounds="\[[0-9]*,[0-9]*\]\[[0-9]*,[0-9]*\]"' | head -1)
      if [ -n "$btn" ]; then
        coords=$(echo "$btn" | grep -oE '[0-9]+,[0-9]+' | sed 's/,/ /g' | tr '\n' ' ')
        set -- $coords
        if [ $# -ge 4 ]; then
          cx=$(( ($1 + $3) / 2)); cy=$(( ($2 + $4) / 2))
          echo "[smoke] tapping permission dialog at ($cx,$cy)"
          "${ADB[@]}" shell input tap "$cx" "$cy"
        fi
      fi
    fi
    sleep 0.5
  done
}

grant_loop &
GRANT_PID=$!
wait "$TEST_PID"; RC=$?
kill "$GRANT_PID" 2>/dev/null
echo "[smoke] flutter test exit: $RC"
exit "$RC"
