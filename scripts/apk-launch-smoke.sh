#!/usr/bin/env bash
# Launch smoke for a built APK — the no-start guard.
# History: point builds with full toolchain swaps (AGP/Kotlin/Flutter majors)
# have shipped first candidates that crashed at launch while passing every
# compile/test gate. This script installs the APK on the e2e emulator and
# proves the app reaches a resumed, rendered first frame with no FATAL.
#
# Usage: scripts/apk-launch-smoke.sh <apk-path> [device]
# Requires: e2e emulator running (adb device visible) — see e2e/ for boot.
set -euo pipefail
APK="$1"; DEV="${2:-emulator-5554}"
ADB="$ANDROID_HOME/platform-tools/adb -s $DEV"

[ -f "$APK" ] || { echo "FATAL: apk not found: $APK" >&2; exit 2; }
$ADB get-state >/dev/null 2>&1 || { echo "FATAL: device $DEV not connected" >&2; exit 2; }

echo "== install =="
$ADB install -r "$APK" | tail -1
$ADB logcat -c
# am start -W times out spuriously on headless emulators; rely on state below.
$ADB shell am start -W -n dev.kevoun.outpostpi/.MainActivity >/dev/null 2>&1 || true
sleep 8

echo "== assertions =="
PID="$($ADB shell pidof dev.kevoun.outpostpi | tr -d '\r' || true)"
[ -n "$PID" ] || { echo "FAIL: process not alive (no-start)"; $ADB logcat -d | grep -E "FATAL|AndroidRuntime" | head -10; exit 1; }
echo "ok: process alive (pid $PID)"
$ADB shell dumpsys activity activities 2>/dev/null | grep -q "topResumedActivity=ActivityRecord{.*dev.kevoun.outpostpi" \
  || { echo "FAIL: MainActivity not resumed"; exit 1; }
echo "ok: MainActivity resumed"
FATALS="$($ADB logcat -d 2>/dev/null | grep -c 'FATAL EXCEPTION' || true)"
[ "$FATALS" = "0" ] || { echo "FAIL: $FATALS FATAL EXCEPTION(s)"; $ADB logcat -d | grep -A8 'FATAL EXCEPTION' | head -20; exit 1; }
echo "ok: zero FATAL exceptions"
SCR="$($ADB exec-out screencap -p 2>/dev/null | wc -c)"
[ "$SCR" -gt 30000 ] || { echo "FAIL: screenshot too small ($SCR bytes) — likely unrendered surface"; exit 1; }
echo "ok: rendered surface (${SCR} bytes)"
echo "LAUNCH SMOKE: PASS"
