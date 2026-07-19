#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# Docker buildx writes an activity timestamp even for this tiny adapter image;
# the dev sandbox mounts ~/.docker and /tmp read-only, so use runner-owned
# transient state and remove it in the exit trap.
export BUILDX_CONFIG="${BUILDX_CONFIG:-$ROOT/e2e/.buildx-state}"
mkdir -p "$BUILDX_CONFIG"
COMPOSE=(docker compose -f "$ROOT/e2e/docker-compose.test.yml")

cleanup() {
  status=$?
  if [[ "${E2E_KEEP_STACK:-0}" != "1" ]]; then
    "${COMPOSE[@]}" down -v --remove-orphans >/dev/null 2>&1 || true
  fi
  rm -rf "$BUILDX_CONFIG"
  exit "$status"
}
trap cleanup EXIT INT TERM

free_port() {
  node -e 'const n=require("node:net");const s=n.createServer();s.listen(0,"127.0.0.1",()=>{console.log(s.address().port);s.close()})'
}

# Docker re-allocates an unspecified host port when a restart-policy container
# restarts. Reserve explicit free ports so Pi-host process restart keeps the
# Flutter driver's endpoint stable for the whole run.
export E2E_PI_HOST_HOST_PORT="${E2E_PI_HOST_HOST_PORT:-$(free_port)}"
export E2E_TOXIPROXY_ADMIN_PORT="${E2E_TOXIPROXY_ADMIN_PORT:-$(free_port)}"
export E2E_TOXIPROXY_RELAY_PORT="${E2E_TOXIPROXY_RELAY_PORT:-$(free_port)}"

cd "$ROOT/pi-extension"
node_modules/.bin/tsc -p ../e2e/tsconfig.pi-host.json

"${COMPOSE[@]}" up -d --build --wait

TOXI_ADMIN_PORT=$E2E_TOXIPROXY_ADMIN_PORT
TOXI_RELAY_PORT=$E2E_TOXIPROXY_RELAY_PORT
PI_HOST_PORT=$E2E_PI_HOST_HOST_PORT

curl --fail --silent --show-error \
  -H 'content-type: application/json' \
  -d '{"name":"app-relay","listen":"0.0.0.0:8666","upstream":"relay:3000","enabled":true}' \
  "http://127.0.0.1:${TOXI_ADMIN_PORT}/proxies" >/dev/null

if [[ "${E2E_INFRA_ONLY:-0}" == "1" ]]; then
  curl --fail --silent "http://127.0.0.1:${PI_HOST_PORT}/status" >/dev/null
  printf '%s\n' "pairing e2e infrastructure healthy"
  exit 0
fi

cd "$ROOT/app"
export PUB_CACHE="${PUB_CACHE:-$ROOT/.pub-cache}"
FLUTTER="${FLUTTER:-$ROOT/.tools/flutter/bin/flutter}"
"$FLUTTER" test --no-pub --concurrency=1 test/e2e/ \
  --dart-define="E2E_PI_HOST_URL=http://127.0.0.1:${PI_HOST_PORT}" \
  --dart-define="E2E_RELAY_URL=http://127.0.0.1:${TOXI_RELAY_PORT}" \
  --dart-define="E2E_TOXIPROXY_URL=http://127.0.0.1:${TOXI_ADMIN_PORT}"
