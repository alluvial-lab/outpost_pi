#!/usr/bin/env bash
set -uo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
DURATION=${E2E_NIGHTLY_SOAK_DURATION_SECONDS:-900}
KEEP=${E2E_NIGHTLY_SOAK_KEEP:-14}
REPORT_ROOT=${E2E_NIGHTLY_SOAK_REPORT_ROOT:-$ROOT/.work/session-notes/nightly-soak}
EXPECTED=${E2E_NIGHTLY_SOAK_EXPECTED_FINDINGS:-$ROOT/e2e/expected-soak-findings.txt}
ADB=${ADB_BIN:-/opt/android-sdk/platform-tools/adb}
SERIAL=${E2E_ANDROID_SERIAL:-emulator-5554}
AVD_NAME=${E2E_ANDROID_AVD:-outpost34}
AVD_DIR=${E2E_ANDROID_AVD_DIR:-$HOME/.android/avd/$AVD_NAME.avd}
MIN_FREE_BYTES=$((10 * 1024 * 1024 * 1024))

if ! [[ "$DURATION" =~ ^[0-9]+$ && "$KEEP" =~ ^[1-9][0-9]*$ ]]; then
  printf 'duration must be a non-negative integer and keep must be positive\n' >&2
  exit 2
fi

mkdir -p "$REPORT_ROOT"
stamp=$(date -u +%Y%m%dT%H%M%SZ)
seed=$(python3 - <<'PY'
import secrets
print(secrets.randbelow(2**31 - 1) + 1)
PY
)
RUN_DIR="$REPORT_ROOT/run-$stamp-$seed"
mkdir -p "$RUN_DIR"
LOG="$RUN_DIR/nightly.log"
SUMMARY="$RUN_DIR/summary.md"
ALERT="$RUN_DIR/ALERT.md"

printf 'nightly soak seed=%s duration=%ss\n' "$seed" "$DURATION" | tee "$LOG"
set +e
python3 "$ROOT/e2e/live_soak.py" \
  --duration "$DURATION" \
  --seed "$seed" \
  --artifacts "$RUN_DIR" 2>&1 | tee -a "$LOG"
soak_status=${PIPESTATUS[0]}
set -e

set +e
python3 "$ROOT/scripts/nightly_soak_report.py" \
  --expected "$EXPECTED" \
  --findings "$RUN_DIR/findings.json" \
  --summary "$SUMMARY" \
  --runner-status "$soak_status"
reconcile_status=$?
set -e

hygiene_status=0
{
  printf '\n## Disk hygiene\n\n'
  if "$ADB" -s "$SERIAL" get-state >/dev/null 2>&1; then
    "$ADB" -s "$SERIAL" emu kill >/dev/null 2>&1 || true
    for _ in $(seq 1 30); do
      "$ADB" -s "$SERIAL" get-state >/dev/null 2>&1 || break
      sleep 1
    done
  fi
  if "$ADB" -s "$SERIAL" get-state >/dev/null 2>&1; then
    printf -- '- Emulator: **STILL RUNNING** on `%s`\n' "$SERIAL"
    hygiene_status=1
  else
    printf -- '- Emulator: down\n'
  fi

  rm -rf "$ROOT/app/build" "$HOME/.gradle/caches/build-cache-1"
  # The AVD is disposable. Removing writable qemu overlays and runtime data is
  # the non-interactive equivalent of the emulator's next-start `-wipe-data`.
  rm -rf "$AVD_DIR/data" "$AVD_DIR/snapshots"
  rm -f "$AVD_DIR"/userdata-qemu.img "$AVD_DIR"/userdata-qemu.img.qcow2 \
    "$AVD_DIR"/cache.img.qcow2 "$AVD_DIR"/encryptionkey.img.qcow2
  printf -- '- Removed: `app/build`, Gradle build cache, and `%s` writable userdata\n' "$AVD_NAME"

  free_bytes=$(df --output=avail -B1 "$ROOT" | tail -1 | tr -d ' ')
  free_human=$(df -h --output=avail "$ROOT" | tail -1 | tr -d ' ')
  printf -- '- Free space after cleanup: `%s`\n' "$free_human"
  if (( free_bytes <= MIN_FREE_BYTES )); then
    printf -- '- Free-space floor: **ALERT** (requires more than 10 GiB)\n'
    hygiene_status=1
  else
    printf -- '- Free-space floor: pass (>10 GiB)\n'
  fi
} >>"$SUMMARY"

if (( reconcile_status != 0 || hygiene_status != 0 )); then
  {
    printf '# Nightly soak alert\n\n'
    printf -- '- Soak exit: `%s`\n' "$soak_status"
    printf -- '- Expected-findings reconciliation exit: `%s`\n' "$reconcile_status"
    printf -- '- Disk-hygiene exit: `%s`\n\n' "$hygiene_status"
    printf 'See `summary.md`, `report.md`, and `nightly.log` in this run directory.\n'
  } >"$ALERT"
  cp "$ALERT" "$REPORT_ROOT/LATEST_ALERT.md"
else
  rm -f "$REPORT_ROOT/LATEST_ALERT.md"
fi

printf '%s\n' "$RUN_DIR" >"$REPORT_ROOT/latest-run.txt"
mapfile -t old_runs < <(find "$REPORT_ROOT" -mindepth 1 -maxdepth 1 -type d -name 'run-*' -printf '%f\n' | sort -r | tail -n +$((KEEP + 1)))
for old_run in "${old_runs[@]}"; do
  rm -rf "$REPORT_ROOT/$old_run"
done

printf 'nightly soak summary: %s\n' "$SUMMARY"
if (( reconcile_status != 0 || hygiene_status != 0 )); then
  printf 'nightly soak alert: %s\n' "$ALERT" >&2
  exit 1
fi
exit 0
