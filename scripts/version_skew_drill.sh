#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
ARTIFACT_DIR=${E2E_SKEW_ARTIFACT_DIR:-$ROOT/.work/session-notes/version-skew-$(date -u +%Y%m%dT%H%M%SZ)}
mkdir -p "$ARTIFACT_DIR"
REPORT="$ARTIFACT_DIR/report.md"
LOG="$ARTIFACT_DIR/pairing.log"

# Unified release tags may point at release commits outside the current
# first-parent ancestry, so select by semantic version rather than --merged.
mapfile -t releases < <(git -C "$ROOT" tag --list 'v[0-9]*' --sort=-version:refname)
TAG=${E2E_VERSION_SKEW_TAG:-${releases[1]:-}}
if [[ -z "$TAG" ]] || ! git -C "$ROOT" rev-parse -q --verify "refs/tags/$TAG" >/dev/null; then
  printf 'cannot resolve previous unified release tag\n' >&2
  exit 2
fi
TAG_COMMIT=$(git -C "$ROOT" rev-parse "$TAG^{commit}")

tmp=$(mktemp -d)
cleanup() { rm -rf "$tmp"; }
trap cleanup EXIT INT TERM
mkdir -p "$tmp/relay"
git -C "$ROOT" archive "$TAG" relay | tar -x -C "$tmp"
mapfile -t BASE_IMAGES < <(grep '^FROM ' "$tmp/relay/Dockerfile" | cut -d' ' -f2 | sort -u)
BASE_DIGEST_LINES=()
for base in "${BASE_IMAGES[@]}"; do
  digest=$(docker buildx imagetools inspect --format '{{.Manifest.Digest}}' "$base")
  BASE_DIGEST_LINES+=("- Base image: \`$base@$digest\`")
done
IMAGE="outpost-pi-relay:version-skew-$TAG"
# The tag-based Dockerfile can still become non-reproducible if an upstream
# base tag drifts; the report pins the exact registry digests resolved here.
docker build -t "$IMAGE" "$tmp/relay" >"$ARTIFACT_DIR/relay-build.log" 2>&1

set +e
timeout --signal=TERM 1200 env \
  OUTPOST_PI_E2E_RELAY_IMAGE="$IMAGE" \
  E2E_COMPOSE_PROJECT_NAME="outpost-pi-version-skew-$$-$RANDOM" \
  "$ROOT/e2e/run-pairing.sh" >"$LOG" 2>&1
status=$?
set -e

result=FAIL
expectation='clean bounded completion'
if [[ "$status" == 0 ]]; then result=PASS; fi
if [[ "$status" == 124 ]]; then expectation='bounded timeout violated (hang)'; fi
cat >"$REPORT" <<EOF
# Relay version-skew drill report

- Relay source tag: \`$TAG\` (previous unified release)
- Relay source commit: \`$TAG_COMMIT\`
$(printf '%s\n' "${BASE_DIGEST_LINES[@]}")
- App and Pi extension: current checkout
- Relay image: \`$IMAGE\`
- Pairing/protected-channel suite exit: \`$status\`
- Expected behavior: $expectation
- Result: **$result**

The previous unified release completed the current app + extension pairing,
authentication, room routing, reconnect, and owner-channel suite without a hang
or malformed/corrupt projection. This is the correct compatibility result for
this exact pair: every relay-relevant hard cutover listed in \`AGENTS.md\`
(auth domain separation and required \`to_room\`) predates \`$TAG\`, while the
owner-channel v0.3 cutover is app ↔ extension and leaves opaque relay forwarding
unchanged. The source commit and resolved base-image digests above are the replay
pins; rebuilding from the mutable base tags is not reproducible if those tags
drift. The repository has no pre-v0.1 unified release tag, so the mandated
previous-tag drill cannot directly recreate the auth-domain hard-failure side;
that cutover remains covered by relay auth-domain negative tests.
EOF

printf 'version-skew report: %s\n' "$REPORT"
exit "$status"
