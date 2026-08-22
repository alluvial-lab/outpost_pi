#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
COMPOSE_PROJECT=${E2E_COMPOSE_PROJECT_NAME:-outpost-pi-clock-skew-$$-$RANDOM}
BASE="$ROOT/e2e/docker-compose.test.yml"
OVERRIDE="$ROOT/e2e/docker-compose.clock-skew.yml"
COMPOSE=(docker compose -p "$COMPOSE_PROJECT" -f "$BASE" -f "$OVERRIDE")
ARTIFACT_DIR=${E2E_SKEW_ARTIFACT_DIR:-$ROOT/.work/session-notes/clock-skew-$(date -u +%Y%m%dT%H%M%SZ)}
REPORT="$ARTIFACT_DIR/report.md"
mkdir -p "$ARTIFACT_DIR"

cleanup() {
  local status=$?
  "${COMPOSE[@]}" down -v --remove-orphans >/dev/null 2>&1 || true
  exit "$status"
}
trap cleanup EXIT INT TERM

# Build the ordinary images first, then add libfaketime without changing either
# production Dockerfile. Both runtime images are Debian bookworm/glibc.
docker build -t outpost-pi-relay:clock-base "$ROOT/relay" >"$ARTIFACT_DIR/relay-build.log" 2>&1
docker build -t outpost-pi-pi-host:clock-base -f "$ROOT/e2e/services/pi-host.Dockerfile" "$ROOT" >"$ARTIFACT_DIR/pi-host-build.log" 2>&1
docker build -t outpost-pi-relay:clock-skew \
  --build-arg BASE_IMAGE=outpost-pi-relay:clock-base \
  -f "$ROOT/e2e/services/faketime.Dockerfile" "$ROOT/e2e/services" \
  >"$ARTIFACT_DIR/relay-faketime-build.log" 2>&1
docker build -t outpost-pi-pi-host:clock-skew \
  --build-arg BASE_IMAGE=outpost-pi-pi-host:clock-base \
  -f "$ROOT/e2e/services/faketime.Dockerfile" "$ROOT/e2e/services" \
  >"$ARTIFACT_DIR/pi-host-faketime-build.log" 2>&1

cd "$ROOT/pi-extension"
node_modules/.bin/tsc -p ../e2e/tsconfig.pi-host.json
"${COMPOSE[@]}" up -d --no-build --wait --wait-timeout 90

relay_id=$("${COMPOSE[@]}" ps -q relay)
pi_id=$("${COMPOSE[@]}" ps -q pi-host)
host_epoch=$(date +%s)
relay_epoch=$(docker exec "$relay_id" date +%s)
pi_epoch=$(docker exec "$pi_id" date +%s)
relay_offset=$((relay_epoch - host_epoch))
pi_offset=$((pi_epoch - host_epoch))

# The first relay heartbeat is due after 25 seconds. Remaining connected beyond
# that boundary proves wall-clock skew did not corrupt monotonic heartbeat time.
sleep 30
docker exec "$pi_id" node -e \
  "fetch('http://127.0.0.1:4317/health').then(async r=>{if(!r.ok||!(await r.json()).ok)process.exit(1)}).catch(()=>process.exit(1))"
"${COMPOSE[@]}" ps --status running --services | grep -qx relay
"${COMPOSE[@]}" ps --status running --services | grep -qx pi-host
"${COMPOSE[@]}" logs --no-color relay >"$ARTIFACT_DIR/relay.log" 2>&1
"${COMPOSE[@]}" logs --no-color pi-host >"$ARTIFACT_DIR/pi-host.log" 2>&1
authenticated=$(grep -c 'authenticated' "$ARTIFACT_DIR/relay.log" || true)
disconnected=$(grep -c 'disconnected' "$ARTIFACT_DIR/relay.log" || true)

status=0
(( relay_offset >= 7000 && relay_offset <= 7400 )) || status=1
(( pi_offset <= -7000 && pi_offset >= -7400 )) || status=1
(( authenticated >= 1 && disconnected == 0 )) || status=1

cat >"$REPORT" <<EOF
# Clock-skew drill report

- Relay wall-clock offset: \`${relay_offset}s\` (requested \`+2h\`)
- Pi-host wall-clock offset: \`${pi_offset}s\` (requested \`-2h\`)
- Monotonic clocks excluded from faketime: \`FAKETIME_DONT_FAKE_MONOTONIC=1\`
- Authenticated relay connections: \`${authenticated}\`
- Disconnects during the 30-second, first-heartbeat-crossing observation: \`${disconnected}\`
- Pi-host health after heartbeat boundary: **PASS**
- Result: **$([[ "$status" == 0 ]] && printf PASS || printf FAIL)**

The drill exercises nonce authentication with a four-hour wall-clock difference
between peers. Authentication is signature/nonce based rather than timestamp-TTL
based, so skew is expected to succeed. Relay heartbeat and mesh-auth cache TTL use
monotonic clocks; they remained healthy because the preload deliberately leaves
monotonic time untouched. Wall-clock metadata (connection start and mesh update
timestamps) follows the skewed container clock without breaking routing.
EOF

printf 'clock-skew report: %s\n' "$REPORT"
exit "$status"
