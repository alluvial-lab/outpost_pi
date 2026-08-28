#!/usr/bin/env bash
# Build, verify, and name APKs for the operator sideload loop. NEVER upload
# from a battery-touched app/build directly: the e2e lane rebuilds
# app-debug.apk for x86_64 and once shipped an APK that crashed on arm64 phones
# (the v0.8.0 incident). This script owns every distributable APK build.
#
# Usage: scripts/release-apk.sh [--slim] [--upload-draft <tag>]
#   --slim               additionally build the signed arm64 release APK.
#   --upload-draft <tag>  create or update a draft prerelease with every built
#                         APK. Tag convention: v<version>-rc.<n> for candidates.
set -euo pipefail
umask 022  # callers materialize key.properties under 177; a leaked umask
           # breaks flutter's .dart_tool (dirs need +x) with misleading EACCES

SLIM=false
UPLOAD_TAG=""
while (($#)); do
  case "$1" in
    --slim)
      SLIM=true
      shift
      ;;
    --upload-draft)
      [[ $# -ge 2 ]] || { echo "FATAL: --upload-draft requires a tag" >&2; exit 2; }
      UPLOAD_TAG=$2
      shift 2
      ;;
    --help|-h)
      printf '%s\n' \
        'Usage: scripts/release-apk.sh [--slim] [--upload-draft <tag>]' \
        '  --slim               build the signed arm64 release APK after debug' \
        '  --upload-draft <tag>  create or update the candidate draft release'
      exit 0
      ;;
    *)
      echo "FATAL: unknown argument: $1" >&2
      exit 2
      ;;
  esac
done

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT/app"
export PATH="$ROOT/.tools/flutter/bin:$PATH"
export PUB_CACHE="${PUB_CACHE:-$ROOT/.pub-cache}"
export JAVA_HOME="${JAVA_HOME:-/usr/lib/jvm/java-21-openjdk-amd64}"
export ANDROID_HOME="${ANDROID_HOME:-/opt/android-sdk}"
export GRADLE_OPTS="${GRADLE_OPTS:--Djava.io.tmpdir=/home/agent/.gradle-tmp}"
mkdir -p /home/agent/.gradle-tmp

AAPT2=$(printf '%s\n' "$ANDROID_HOME"/build-tools/*/aapt2 | sort -V | tail -1)
APKSIGNER="$(dirname "$AAPT2")/apksigner"
[[ -x "$AAPT2" ]] || { echo "FATAL: aapt2 not found under $ANDROID_HOME/build-tools" >&2; exit 1; }
[[ -x "$APKSIGNER" ]] || { echo "FATAL: apksigner not found beside $AAPT2" >&2; exit 1; }

badging_field() {
  local apk=$1 field=$2 badging line
  badging=$("$AAPT2" dump badging "$apk")
  line=$(grep -m1 '^package:' <<<"$badging")
  sed -nE "s/.*[[:space:]]${field}='([^']+)'.*/\\1/p" <<<"$line"
}

require_archive_entry() {
  local apk=$1 entry=$2
  if [[ "$(unzip -Z1 "$apk" "$entry" 2>/dev/null || true)" != "$entry" ]]; then
    echo "FATAL: $entry missing from $apk" >&2
    exit 1
  fi
}

human_size() {
  numfmt --to=iec-i --suffix=B "$(stat -c%s "$1")"
}

echo "== building full-ABI debug APK =="
flutter build apk --debug

DEBUG_SRC=build/app/outputs/flutter-apk/app-debug.apk
PACKAGE=$(badging_field "$DEBUG_SRC" name)
VERSION=$(badging_field "$DEBUG_SRC" versionName)
CODE=$(badging_field "$DEBUG_SRC" versionCode)
[[ "$PACKAGE" == "dev.kevoun.outpostpi" ]] || {
  echo "FATAL: unexpected package in debug APK: $PACKAGE" >&2
  exit 1
}

echo "== verifying debug native libraries (the v0.8.0 incident guard) =="
# Badging can list ABI directories padded by plugins. libflutter.so per ABI is
# the executable runtime invariant that determines whether the phone can start.
for ABI in arm64-v8a armeabi-v7a; do
  require_archive_entry "$DEBUG_SRC" "lib/$ABI/libflutter.so"
done
echo "ok: debug libflutter.so present in arm64-v8a and armeabi-v7a"

DEBUG_OUT="$ROOT/outpost-${VERSION}-${CODE}.apk"
cp "$DEBUG_SRC" "$DEBUG_OUT"
ASSETS=("$DEBUG_OUT")
SLIM_OUT=""

if $SLIM; then
  KEYSTORE_ENV="${OUTPOST_PI_KEYSTORE_ENV:-$HOME/.config/outpost-pi/keystore.env}"
  KEY_PROPERTIES="$ROOT/app/android/key.properties"
  [[ -r "$KEYSTORE_ENV" ]] || {
    echo "FATAL: release keystore environment missing: $KEYSTORE_ENV" >&2
    echo "Release builds never fall back to debug signing." >&2
    exit 1
  }
  [[ "$(stat -c '%a' "$KEYSTORE_ENV")" == "600" ]] || {
    echo "FATAL: $KEYSTORE_ENV must have mode 0600" >&2
    exit 1
  }
  [[ -r "$KEY_PROPERTIES" ]] || {
    echo "FATAL: android/key.properties is missing; release signing is not configured" >&2
    echo "Release builds never fall back to debug signing." >&2
    exit 1
  }

  set -a
  # shellcheck disable=SC1090
  . "$KEYSTORE_ENV"
  set +a
  : "${OUTPOST_PI_UPLOAD_KEYSTORE:?keystore env is missing OUTPOST_PI_UPLOAD_KEYSTORE}"
  : "${OUTPOST_PI_UPLOAD_KEYSTORE_PASSWORD:?keystore env is missing OUTPOST_PI_UPLOAD_KEYSTORE_PASSWORD}"
  : "${OUTPOST_PI_UPLOAD_KEY_ALIAS:?keystore env is missing OUTPOST_PI_UPLOAD_KEY_ALIAS}"
  [[ -f "$OUTPOST_PI_UPLOAD_KEYSTORE" ]] || {
    echo "FATAL: configured upload keystore is missing: $OUTPOST_PI_UPLOAD_KEYSTORE" >&2
    exit 1
  }
  [[ "$(stat -c '%a' "$OUTPOST_PI_UPLOAD_KEYSTORE")" == "600" ]] || {
    echo "FATAL: $OUTPOST_PI_UPLOAD_KEYSTORE must have mode 0600" >&2
    exit 1
  }

  echo "== building signed arm64 release APK (R8 + resource shrinking) =="
  flutter build apk --release --target-platform android-arm64

  SLIM_SRC=build/app/outputs/flutter-apk/app-release.apk
  SLIM_PACKAGE=$(badging_field "$SLIM_SRC" name)
  SLIM_VERSION=$(badging_field "$SLIM_SRC" versionName)
  SLIM_CODE=$(badging_field "$SLIM_SRC" versionCode)
  [[ "$SLIM_PACKAGE" == "$PACKAGE" && "$SLIM_VERSION" == "$VERSION" && "$SLIM_CODE" == "$CODE" ]] || {
    echo "FATAL: slim APK package/version does not match debug APK" >&2
    exit 1
  }

  SLIM_BADGING=$("$AAPT2" dump badging "$SLIM_SRC")
  NATIVE_CODE=$(grep -m1 '^native-code:' <<<"$SLIM_BADGING" || true)
  [[ "$NATIVE_CODE" == "native-code: 'arm64-v8a'" ]] || {
    echo "FATAL: slim APK must advertise only arm64-v8a; got: ${NATIVE_CODE:-<none>}" >&2
    exit 1
  }

  mapfile -t FLUTTER_LIBS < <(unzip -Z1 "$SLIM_SRC" 'lib/*/libflutter.so' 2>/dev/null || true)
  if [[ ${#FLUTTER_LIBS[@]} -ne 1 || "${FLUTTER_LIBS[0]:-}" != "lib/arm64-v8a/libflutter.so" ]]; then
    printf 'FATAL: slim APK has unexpected libflutter.so entries: %s\n' "${FLUTTER_LIBS[*]:-<none>}" >&2
    exit 1
  fi
  require_archive_entry "$SLIM_SRC" AndroidManifest.xml
  require_archive_entry "$SLIM_SRC" classes.dex
  require_archive_entry "$SLIM_SRC" assets/flutter_assets/NOTICES.Z

  APK_CERT=$("$APKSIGNER" verify --print-certs "$SLIM_SRC" |
    sed -nE 's/^Signer #1 certificate SHA-256 digest: //p' | tr '[:upper:]' '[:lower:]')
  KEYSTORE_CERT=$(keytool -list -v \
    -keystore "$OUTPOST_PI_UPLOAD_KEYSTORE" \
    -storepass "$OUTPOST_PI_UPLOAD_KEYSTORE_PASSWORD" \
    -alias "$OUTPOST_PI_UPLOAD_KEY_ALIAS" 2>/dev/null |
    sed -nE 's/^[[:space:]]*SHA256: //p' | tr -d ':' | tr '[:upper:]' '[:lower:]')
  [[ -n "$APK_CERT" && "$APK_CERT" == "$KEYSTORE_CERT" ]] || {
    echo "FATAL: slim APK signer does not match the configured upload keystore" >&2
    exit 1
  }
  echo "ok: package/version match; arm64-v8a only; libflutter.so present; signer verified"

  SLIM_OUT="$ROOT/outpost-${VERSION}-${CODE}-arm64.apk"
  cp "$SLIM_SRC" "$SLIM_OUT"
  ASSETS+=("$SLIM_OUT")
fi

echo "== artifact sizes =="
printf 'debug-fat: %s (%s bytes)  %s\n' "$(human_size "$DEBUG_OUT")" "$(stat -c%s "$DEBUG_OUT")" "$DEBUG_OUT"
if [[ -n "$SLIM_OUT" ]]; then
  printf 'slim-arm64: %s (%s bytes)  %s\n' "$(human_size "$SLIM_OUT")" "$(stat -c%s "$SLIM_OUT")" "$SLIM_OUT"
fi
sha256sum "${ASSETS[@]}"

if [[ -n "$UPLOAD_TAG" ]]; then
  NOTES_FILE=$(mktemp)
  trap 'rm -f "$NOTES_FILE"' EXIT
  {
    echo "Candidate build. UAT the debug-fat APK first; publish on pass."
    echo
    echo "Artifacts:"
    echo "- debug-fat: $(human_size "$DEBUG_OUT")"
    if [[ -n "$SLIM_OUT" ]]; then
      echo "- slim-arm64 (Pixel/modern Android): $(human_size "$SLIM_OUT")"
    fi
  } >"$NOTES_FILE"

  if gh release view "$UPLOAD_TAG" -R alluvial-lab/outpost_pi >/dev/null 2>&1; then
    IS_DRAFT=$(gh release view "$UPLOAD_TAG" -R alluvial-lab/outpost_pi --json isDraft --jq .isDraft)
    [[ "$IS_DRAFT" == "true" ]] || {
      echo "FATAL: $UPLOAD_TAG already exists and is not a draft" >&2
      exit 1
    }
    echo "== updating draft prerelease $UPLOAD_TAG =="
    UPLOAD_ASSETS=("${ASSETS[@]}")
    if $SLIM; then
      EXISTING_ASSET_NAMES=$(gh release view "$UPLOAD_TAG" -R alluvial-lab/outpost_pi \
        --json assets --jq '.assets[].name')
      if grep -Fxq "$(basename "$DEBUG_OUT")" <<<"$EXISTING_ASSET_NAMES"; then
        # Preserve the exact debug candidate the operator already UATed. The
        # second pass builds debug again only to re-establish identity/ABI
        # evidence before creating the signed slim artifact.
        UPLOAD_ASSETS=("$SLIM_OUT")
      fi
    fi
    gh release upload "$UPLOAD_TAG" -R alluvial-lab/outpost_pi --clobber "${UPLOAD_ASSETS[@]}"
    gh release edit "$UPLOAD_TAG" -R alluvial-lab/outpost_pi \
      --title "$UPLOAD_TAG candidate" \
      --notes-file "$NOTES_FILE" \
      --prerelease
  else
    echo "== creating draft prerelease $UPLOAD_TAG =="
    gh release create "$UPLOAD_TAG" -R alluvial-lab/outpost_pi \
      --draft --prerelease \
      --title "$UPLOAD_TAG candidate" \
      --notes-file "$NOTES_FILE" \
      "${ASSETS[@]}"
  fi
  echo "draft ready — operator UAT gate; publishing promotes every attached artifact"
fi
