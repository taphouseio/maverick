#!/usr/bin/env bash

# Build the production image locally with Apple's container tool.
set -euo pipefail

readonly CONTAINER_IMAGE="${CONTAINER:-ghcr.io/jsorge/maverick}"
# Apple Container's local BuildKit worker is native arm64 on Apple Silicon.
# Set CONTAINER_PLATFORM explicitly when using a builder that supports another
# architecture (the release workflow builds linux/amd64 in GitHub Actions).
readonly PLATFORM="${CONTAINER_PLATFORM:-linux/arm64}"
readonly PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

if ! command -v container >/dev/null 2>&1; then
    echo "Apple's container tool is not installed. Install it with:"
    echo "  brew install container"
    exit 1
fi

# A fresh install may not have a Linux kernel configured yet. Install the
# recommended kernel if the service cannot start non-interactively.
if ! container system status >/dev/null 2>&1; then
    echo "Starting Apple's container system service..."
    if ! container system start </dev/null >/dev/null 2>&1; then
        container system kernel set --recommended
        container system start
    fi
fi

VERSION="${1:-}"
if [[ -z "$VERSION" ]]; then
    VERSION="$(git -C "$PROJECT_ROOT" describe --tags --abbrev=0 2>/dev/null || true)"
    VERSION="${VERSION#v}"
    VERSION="${VERSION:-dev}"
else
    # Accept either the workflow's `1.0.0` form or a convenient `v1.0.0`.
    VERSION="${VERSION#v}"
fi

cd "$PROJECT_ROOT"

echo "==> Building ${CONTAINER_IMAGE}:${VERSION} and ${CONTAINER_IMAGE}:latest..."
echo "    Platform: ${PLATFORM}"

container build \
    --platform "$PLATFORM" \
    --no-cache \
    --tag "${CONTAINER_IMAGE}:${VERSION}" \
    --tag "${CONTAINER_IMAGE}:latest" \
    .

echo "==> Local container build complete!"
