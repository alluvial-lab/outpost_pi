#!/usr/bin/env bash
# Build the site Docker image locally.
#
# Usage:
#   ./build-docker.sh              → tags as :latest
#   ./build-docker.sh v1.2.3       → tags as :v1.2.3 AND :latest
#
# Builds for the host platform and loads into the local Docker daemon (no
# registry push) — the site image is project-local, built from site/ source.
#
# Requirements:
#   docker (buildx bundled with modern Docker).

set -euo pipefail

IMAGE="outpost-pi-site"
VERSION="${1:-}"

# Always resolve paths relative to this script so it can be called from anywhere
cd "$(dirname "$0")"

if [[ -n "$VERSION" ]]; then
  TAGS="--tag $IMAGE:$VERSION --tag $IMAGE:latest"
  echo "→ Building $IMAGE:$VERSION + :latest"
else
  TAGS="--tag $IMAGE:latest"
  echo "→ Building $IMAGE:latest"
fi

# shellcheck disable=SC2086
docker build \
  $TAGS \
  .

echo "✓ Done (local)"
