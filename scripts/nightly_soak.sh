#!/usr/bin/env bash
set -uo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
DURATION=${E2E_NIGHTLY_SOAK_DURATION_SECONDS:-900}
KEEP=${E2E_NIGHTLY_SOAK_KEEP:-14}
HARD_TIMEOUT=${E2E_NIGHTLY_SOAK_HARD_TIMEOUT_SECONDS:-2400}
LANE_WAIT=${E2E_NIGHTLY_LANE_WAIT_SECONDS:-300}
REPORT_ROOT=${E2E_NIGHTLY_SOAK_REPORT_ROOT:-$ROOT/.work/session-notes/nightly-soak}
EXPECTED=${E2E_NIGHTLY_SOAK_EXPECTED_FINDINGS:-$ROOT/e2e/expected-soak-findings.txt}
ADB=${ADB_BIN:-/opt/android-sdk/platform-tools/adb}
SERIAL=${E2E_ANDROID_SERIAL:-emulator-5554}
AVD_NAME=${E2E_ANDROID_AVD:-outpost34}
AVD_DIR=${E2E_ANDROID_AVD_DIR:-$HOME/.android/avd/$AVD_NAME.avd}
LANE_LOCK="$ROOT/e2e/.run-state/locks/${SERIAL}.lock"
MIN_FREE_BYTES=$((10 * 1024 * 1024 * 1024))

if ! [[ "$DURATION" =~ ^[0-9]+$ && "$KEEP" =~ ^[1-9][0-9]*$ && \
        "$HARD_TIMEOUT" =~ ^[1-9][0-9]*$ && "$LANE_WAIT" =~ ^[0-9]+$ ]]; then
  printf 'duration/lane wait must be non-negative; keep/hard timeout must be positive\n' >&2
  exit 2
fi

mkdir -p "$REPORT_ROOT" "$(dirname "$LANE_LOCK")"
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
SOAK_STARTED=0
soak_status=2
reconcile_status=2
hygiene_status=0

finish() {
  local incoming_status=$?
  trap - EXIT INT TERM
  set +e

  if [[ "$SOAK_STARTED" == 1 ]]; then
    {
      printf '\n## Disk hygiene\n\n'
      if "$ADB" -s "$SERIAL" get-state >/dev/null 2>&1; then
        printf -- '- Emulator: **STILL RUNNING** on `%s`; left untouched because ownership is no longer provable\n' "$SERIAL"
        hygiene_status=1
      else
        printf -- '- Emulator: down\n'
        # Release APKs are distributed via GitHub Releases (never retained in
        # the tree — the .work/artifacts experiment caused two 190MB blobs in
        # git history, stripped 2026-08-25). Only build-regenerable state is
        # cleaned here.
        rm -rf "$ROOT/app/build"
        rm -rf "$HOME/.gradle/caches/build-cache-1"
        # The AVD is reset only after this run held the exclusive lane and its
        # owned emulator is confirmed down; a foreign occupied serial is never reset.
        rm -rf "$AVD_DIR/data" "$AVD_DIR/snapshots"
        rm -f "$AVD_DIR"/userdata-qemu.img "$AVD_DIR"/userdata-qemu.img.qcow2 \
          "$AVD_DIR"/cache.img.qcow2 "$AVD_DIR"/encryptionkey.img.qcow2
        printf -- '- Removed: `app/build` (unless retained), Gradle build cache, and `%s` writable userdata\n' "$AVD_NAME"
      fi

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
  fi

  local outcome=success final_status=0
  if (( incoming_status != 0 || soak_status != 0 || reconcile_status != 0 || hygiene_status != 0 )); then
    outcome=failure
    final_status=1
    {
      printf '# Nightly soak alert\n\n'
      printf -- '- Timestamp: `%s`\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
      printf -- '- Soak exit: `%s`\n' "$soak_status"
      printf -- '- Expected-findings reconciliation exit: `%s`\n' "$reconcile_status"
      printf -- '- Disk-hygiene exit: `%s`\n\n' "$hygiene_status"
      printf 'See `summary.md`, `report.md`, and `nightly.log` in `%s`.\n' "$(basename "$RUN_DIR")"
    } >"$ALERT"
    {
      [[ ! -s "$REPORT_ROOT/LATEST_ALERT.md" ]] || printf '\n---\n\n'
      cat "$ALERT"
    } >>"$REPORT_ROOT/LATEST_ALERT.md"
    tail -n 400 "$REPORT_ROOT/LATEST_ALERT.md" >"$REPORT_ROOT/.LATEST_ALERT.tmp"
    mv "$REPORT_ROOT/.LATEST_ALERT.tmp" "$REPORT_ROOT/LATEST_ALERT.md"
  fi

  printf 'timestamp=%s\noutcome=%s\nrun=%s\nsoak_exit=%s\nreconcile_exit=%s\nhygiene_exit=%s\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$outcome" "$(basename "$RUN_DIR")" \
    "$soak_status" "$reconcile_status" "$hygiene_status" \
    >"$REPORT_ROOT/LAST_STATUS"
  printf '%s\n' "$RUN_DIR" >"$REPORT_ROOT/latest-run.txt"
  mapfile -t old_runs < <(find "$REPORT_ROOT" -mindepth 1 -maxdepth 1 -type d -name 'run-*' -printf '%f\n' | sort -r | tail -n +$((KEEP + 1)))
  for old_run in "${old_runs[@]}"; do rm -rf "$REPORT_ROOT/$old_run"; done

  printf 'nightly soak summary: %s\n' "$SUMMARY"
  if (( final_status != 0 )); then
    printf 'nightly soak alert: %s\n' "$ALERT" >&2
  fi
  exit "$final_status"
}
trap finish EXIT INT TERM

printf 'nightly soak seed=%s duration=%ss hard-timeout=%ss\n' \
  "$seed" "$DURATION" "$HARD_TIMEOUT" | tee "$LOG"

lane_deadline=$((SECONDS + LANE_WAIT))
while true; do
  exec {probe_fd}>"$LANE_LOCK"
  lane_free=0
  if flock -n "$probe_fd"; then
    lane_free=1
    flock -u "$probe_fd"
  fi
  exec {probe_fd}>&-
  serial_free=0
  if ! "$ADB" -s "$SERIAL" get-state >/dev/null 2>&1; then serial_free=1; fi
  if (( lane_free == 1 && serial_free == 1 )); then break; fi
  if (( SECONDS >= lane_deadline )); then
    soak_status=75
    reconcile_status=75
    {
      printf '# Nightly soak summary\n\n'
      printf -- '- Outcome: skipped after waiting `%ss` for exclusive Android lane `%s`\n' "$LANE_WAIT" "$SERIAL"
      printf -- '- Existing emulator/resources were left untouched.\n'
    } >"$SUMMARY"
    printf 'nightly lane occupied; skipping without touching %s\n' "$SERIAL" | tee -a "$LOG" >&2
    exit 1
  fi
  sleep 5
done

exec {nightly_lane_fd}>"$LANE_LOCK"
if ! flock --wait "$LANE_WAIT" "$nightly_lane_fd" || \
    "$ADB" -s "$SERIAL" get-state >/dev/null 2>&1; then
  soak_status=75
  reconcile_status=75
  {
    printf '# Nightly soak summary\n\n'
    printf -- '- Outcome: skipped because exclusive Android lane `%s` became occupied before start\n' "$SERIAL"
    printf -- '- Existing emulator/resources were left untouched.\n'
  } >"$SUMMARY"
  exit 1
fi

SOAK_STARTED=1
set +e
timeout --signal=TERM --kill-after=30 "$HARD_TIMEOUT" \
  env E2E_LANE_LOCK_HELD=1 python3 "$ROOT/e2e/live_soak.py" \
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

exit 0
