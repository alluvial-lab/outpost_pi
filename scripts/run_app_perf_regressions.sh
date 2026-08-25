#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
if [[ -n "${FLUTTER_BIN:-}" ]]; then
  FLUTTER=$FLUTTER_BIN
elif command -v flutter >/dev/null 2>&1; then
  FLUTTER=$(command -v flutter)
else
  FLUTTER="$ROOT/.tools/flutter/bin/flutter"
fi
if [[ ! -x "$FLUTTER" ]]; then
  printf 'Flutter executable not found: %s\n' "$FLUTTER" >&2
  exit 2
fi

cd "$ROOT/app"
export OUTPOST_PI_PERF_GATES=1
"$FLUTTER" test --no-pub test/perf/debug_log_benchmark_test.dart --concurrency=2
"$FLUTTER" test --no-pub benchmark/transcript_projection_pipeline_benchmark_test.dart --concurrency=2
"$FLUTTER" test --no-pub test/perf/room_snapshot_consumers_benchmark_test.dart --concurrency=2
