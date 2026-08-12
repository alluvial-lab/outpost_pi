#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
COMPOSE_PROJECT="${E2E_COMPOSE_PROJECT_NAME:-outpost-pi-pairing-e2e-${GITHUB_RUN_ID:-local}-${GITHUB_RUN_ATTEMPT:-$$}-${RANDOM}}"
RUN_STATE="$ROOT/e2e/.run-state/$COMPOSE_PROJECT"
COMPOSE_FILE="$ROOT/e2e/docker-compose.test.yml"
COMPOSE=(docker compose -p "$COMPOSE_PROJECT" -f "$COMPOSE_FILE")

# Docker buildx writes activity state even for the tiny host adapter image.
# Keep every run's state private so concurrent local/CI runs cannot collide.
export BUILDX_CONFIG="${BUILDX_CONFIG:-$RUN_STATE/buildx}"
mkdir -p "$BUILDX_CONFIG"
chmod 700 "$RUN_STATE"

cleanup() {
  status=$?
  if [[ "${E2E_KEEP_STACK:-0}" != "1" ]]; then
    "${COMPOSE[@]}" down -v --remove-orphans >/dev/null 2>&1 || true
  else
    printf '%s\n' "pairing e2e stack retained: project=$COMPOSE_PROJECT"
  fi
  rm -rf "$RUN_STATE"
  exit "$status"
}
trap cleanup EXIT INT TERM

published_port() {
  local address
  address=$("${COMPOSE[@]}" port "$1" "$2")
  printf '%s\n' "${address##*:}"
}

cd "$ROOT/pi-extension"
node_modules/.bin/tsc -p ../e2e/tsconfig.pi-host.json

if [[ -n "${OUTPOST_PI_E2E_RELAY_IMAGE:-}" ]]; then
  # An explicit image opts out of rebuilding relay source, while the host
  # adapter still rebuilds from this checkout.
  "${COMPOSE[@]}" build pi-host
  "${COMPOSE[@]}" up -d --no-build --wait
else
  # The regression gate defaults to the repository's current relay source.
  "${COMPOSE[@]}" up -d --build --wait
fi

TOXI_ADMIN_PORT=$(published_port toxiproxy 8474)
TOXI_RELAY_PORT=$(published_port toxiproxy 8666)
PI_HOST_PORT=$(published_port toxiproxy 8667)

# Delete-then-create makes rerunning initialization safe when an operator keeps
# a stack or retries the runner against an existing project. Pi-host also uses
# the stable Toxiproxy container as its host-port front door because Docker may
# reassign a dynamically published port when the host process restarts.
for proxy in app-relay pi-host; do
  curl --silent --show-error -X DELETE \
    "http://127.0.0.1:${TOXI_ADMIN_PORT}/proxies/$proxy" >/dev/null || true
done
curl --fail --silent --show-error \
  -H 'content-type: application/json' \
  -d '{"name":"app-relay","listen":"0.0.0.0:8666","upstream":"relay:3000","enabled":true}' \
  "http://127.0.0.1:${TOXI_ADMIN_PORT}/proxies" >/dev/null
curl --fail --silent --show-error \
  -H 'content-type: application/json' \
  -d '{"name":"pi-host","listen":"0.0.0.0:8667","upstream":"pi-host:4317","enabled":true}' \
  "http://127.0.0.1:${TOXI_ADMIN_PORT}/proxies" >/dev/null

if [[ "${E2E_INFRA_ONLY:-0}" == "1" ]]; then
  curl --fail --silent "http://127.0.0.1:${PI_HOST_PORT}/status" >/dev/null
  printf '%s\n' "pairing e2e infrastructure healthy"
  exit 0
fi

CANARY_FILE="$RUN_STATE/redaction-canaries.jsonl"
FLUTTER_LOG="$RUN_STATE/flutter-test.log"
PI_HOST_LOG="$RUN_STATE/pi-host.log"
RELAY_LOG="$RUN_STATE/relay.log"
: > "$CANARY_FILE"
chmod 600 "$CANARY_FILE"

cd "$ROOT/app"
export PUB_CACHE="${PUB_CACHE:-$ROOT/.pub-cache}"
FLUTTER="${FLUTTER:-$ROOT/.tools/flutter/bin/flutter}"
set +e
"$FLUTTER" test --no-pub --concurrency=1 test/e2e/ \
  --dart-define="E2E_PI_HOST_URL=http://127.0.0.1:${PI_HOST_PORT}" \
  --dart-define="E2E_RELAY_URL=http://127.0.0.1:${TOXI_RELAY_PORT}" \
  --dart-define="E2E_TOXIPROXY_URL=http://127.0.0.1:${TOXI_ADMIN_PORT}" \
  --dart-define="E2E_COMPOSE_PROJECT=$COMPOSE_PROJECT" \
  --dart-define="E2E_COMPOSE_FILE=$COMPOSE_FILE" \
  --dart-define="E2E_REDACTION_CANARY_FILE=$CANARY_FILE" \
  2>&1 | tee "$FLUTTER_LOG"
FLUTTER_STATUS=${PIPESTATUS[0]}
set -e

# Capture service diagnostics without echoing them. The checker reports only a
# canary label plus a one-way fingerprint if a sensitive value leaked.
"${COMPOSE[@]}" logs --no-color pi-host > "$PI_HOST_LOG" 2>&1
"${COMPOSE[@]}" logs --no-color relay > "$RELAY_LOG" 2>&1
set +e
node "$ROOT/e2e/check-redaction.mjs" \
  "$CANARY_FILE" "$FLUTTER_LOG" "$PI_HOST_LOG" "$RELAY_LOG"
REDACTION_STATUS=$?
set -e

if [[ "$FLUTTER_STATUS" -ne 0 ]]; then
  # Surface the relay auth-handshake sequence on failure so CI can diagnose
  # flaky pairing timeouts WITHOUT a local repro (the relay log is already a
  # check-redaction input, so this structural grep is redaction-safe; it goes
  # to stderr, which the tee'd FLUTTER_LOG does not capture). The key question:
  # did the app's relay WS auth complete? `authenticated ... room=main` => yes
  # (stall is post-auth); `phase=auth handshake step failed` => the app's auth
  # missed the relay's 5s HANDSHAKE_STEP_TIMEOUT.
  echo "===== relay auth-handshake diagnostics (flutter failed) =====" >&2
  grep -E "handshake step failed|auth failed|duplicate auth|phase=|authenticated" \
    "$RELAY_LOG" | tail -200 >&2 || true
  echo "===== relay disconnect/order diagnostics (tail) =====" >&2
  tail -60 "$RELAY_LOG" >&2 || true
  exit "$FLUTTER_STATUS"
fi
if [[ "$REDACTION_STATUS" -ne 0 ]]; then
  exit "$REDACTION_STATUS"
fi
