#!/usr/bin/env bash
# Build the dormant rp-s3 Docker image locally; this script does not deploy it.
# Version is read from Cargo.toml — bump `version = "..."` there before running.
#
# Usage:
#   ./build-docker.sh
#
# Always tags `:v<cargo-version>` and `:latest`. Builds for the host platform
# and loads into the local Docker daemon (no registry push or deployment) — the
# image is project-local, built from rp-s3/ source.
#
# Requirements:
#   docker (buildx bundled with modern Docker).
set -euo pipefail

IMAGE="outpost-pi-rp-s3"

# Always resolve paths relative to this script so it can be called from anywhere
cd "$(dirname "$0")"

# Extract the [package] version from Cargo.toml.
VERSION=$(awk '
  /^\[package\]/ { in_pkg = 1; next }
  /^\[/          { in_pkg = 0 }
  in_pkg && /^version[[:space:]]*=/ {
    gsub(/[" ]/, "")
    sub(/^version=/, "")
    print
    exit
  }
' Cargo.toml)

if [[ -z "$VERSION" ]]; then
  echo "✗ Could not extract version from Cargo.toml" >&2
  exit 1
fi

TAG="v$VERSION"

echo "→ Building $IMAGE:$TAG + :latest"

docker build \
  --tag "$IMAGE:$TAG" \
  --tag "$IMAGE:latest" \
  .

echo "✓ Built $IMAGE:$TAG and $IMAGE:latest (local; dormant server not deployed)"
