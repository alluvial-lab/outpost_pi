#!/usr/bin/env bash
set -euo pipefail

android_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
cd "$android_dir"

if [[ -e key.properties ]]; then
  echo "error: this regression check requires android/key.properties to be absent" >&2
  exit 2
fi

# A fresh clone must be able to configure Gradle for contributor and debug work.
./gradlew help "$@"

# --dry-run constructs the real release task graph without compiling or emitting
# an artifact. The graph-aware signing guard must reject it before execution.
release_output=$(mktemp)
trap 'rm -f "$release_output"' EXIT
if ./gradlew :app:assembleRelease --dry-run "$@" >"$release_output" 2>&1; then
  cat "$release_output" >&2
  echo "error: no-key assembleRelease unexpectedly passed the signing guard" >&2
  exit 1
fi

expected_error="Release APK/AAB tasks require a complete android/key.properties and an existing release keystore."
if ! grep -Fq "$expected_error" "$release_output"; then
  cat "$release_output" >&2
  echo "error: assembleRelease failed without the explicit release-signing error" >&2
  exit 1
fi

echo "Release signing guard regression check passed."
