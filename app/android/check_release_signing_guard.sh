#!/usr/bin/env bash
set -euo pipefail

android_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
cd "$android_dir"

guard_tmp=$(mktemp -d)
key_properties_backup=""
release_output="$guard_tmp/release-output"
restore_local_signing() {
  if [[ -n "$key_properties_backup" && -e "$key_properties_backup" ]]; then
    mv "$key_properties_backup" key.properties
  fi
  rm -rf "$guard_tmp"
}
trap restore_local_signing EXIT

# Exercise fresh-clone behavior even on the operator VM, where ignored local
# signing configuration normally exists. Always restore it on exit.
if [[ -e key.properties || -L key.properties ]]; then
  key_properties_backup="$guard_tmp/key.properties"
  mv key.properties "$key_properties_backup"
fi

# A fresh clone must be able to configure Gradle for contributor and debug work.
./gradlew help "$@"

# --dry-run constructs the real release task graph without compiling or emitting
# an artifact. The graph-aware signing guard must reject it before execution.
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
