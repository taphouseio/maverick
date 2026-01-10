#!/usr/bin/env bash
set -e

CONTAINER="${CONTAINER:-ghcr.io/jsorge/maverick}"
VERSION="${1:-}"

if [[ -n "$VERSION" ]]; then
    echo "==> Building ${CONTAINER}:${VERSION}..."
    docker build -t "${CONTAINER}:${VERSION}" -t "${CONTAINER}:latest" .
else
    # Fall back to git tag
    TAG=$(git describe --tags 2>/dev/null || echo "dev")
    echo "==> Building ${CONTAINER}:${TAG}..."
    docker build -t "${CONTAINER}:${TAG}" -t "${CONTAINER}:latest" .
fi

echo "==> Build complete!"
