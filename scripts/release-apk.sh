#!/usr/bin/env bash
# Build + verify + name a release APK. NEVER upload from a battery-touched
# app/build directly — the e2e lane rebuilds app-debug.apk for the emulator
# ABI only (x86_64), which once shipped as v0.8.0 and crashed every arm64
# phone (2026-08-25 incident). This script owns release builds.
#
# Usage: scripts/release-apk.sh [--upload-draft <tag>]
#   --upload-draft <tag>  additionally creates a DRAFT PRE-RELEASE with the
#                         named APK attached (operator UATs, then publishes).
#                         Tag convention: v<version>-rc.<n> for candidates.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT/app"
export PATH="$ROOT/.tools/flutter/bin:$PATH"
export JAVA_HOME="${JAVA_HOME:-/usr/lib/jvm/java-21-openjdk-amd64}"
export ANDROID_HOME="${ANDROID_HOME:-/opt/android-sdk}"
export GRADLE_OPTS="${GRADLE_OPTS:--Djava.io.tmpdir=/home/agent/.gradle-tmp}"

AAPT2=$(ls "$ANDROID_HOME"/build-tools/*/aapt2 | sort | tail -1)

echo "== building full-ABI debug APK =="
flutter build apk --debug

SRC=build/app/outputs/flutter-apk/app-debug.apk
VERSION=$("$AAPT2" dump badging "$SRC" | grep -m1 "versionName" | sed -E "s/.*versionName='([^']+)'.*/\1/")
CODE=$("$AAPT2" dump badging "$SRC" | grep -m1 "versionCode" | sed -E "s/.*versionCode='([^']+)'.*/\1/")

echo "== verifying native libraries (the v0.8.0 incident guard) =="
# badging lists ABI DIRECTORIES (plugins pad every dir); libflutter.so per-ABI
# is what actually loads. Fail unless the phone ABI is really there.
for ABI in arm64-v8a armeabi-v7a; do
  if ! unzip -l "$SRC" | grep -q "lib/$ABI/libflutter.so"; then
    echo "FATAL: libflutter.so missing from lib/$ABI — this build cannot run on $ABI phones" >&2
    exit 1
  fi
done
echo "ok: libflutter.so present in arm64-v8a and armeabi-v7a"

OUT="$ROOT/outpost-${VERSION}-${CODE}.apk"
cp "$SRC" "$OUT"
sha256sum "$OUT"
echo "release artifact: $OUT"

if [[ "${1:-}" == "--upload-draft" ]]; then
  TAG="${2:?--upload-draft requires a tag}"
  echo "== creating draft prerelease $TAG =="
  gh release create "$TAG" -R alluvial-lab/outpost_pi \
    --draft --prerelease \
    --title "$TAG candidate" \
    --notes "Candidate build. UAT: download the APK below, install, verify; publish on pass." \
    "$OUT"
  echo "draft created — operator UAT gate; publish when green"
fi
