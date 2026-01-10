#!/usr/bin/env bash
set -e

CONTAINER="${CONTAINER:-ghcr.io/jsorge/maverick}"
VERSION="${1:-}"

if [[ -n "$VERSION" ]]; then
    echo "==> Pushing ${CONTAINER}:${VERSION}..."
    docker push "${CONTAINER}:${VERSION}"
    echo "==> Pushing ${CONTAINER}:latest..."
    docker push "${CONTAINER}:latest"
else
    # Fall back to git tag
    TAG=$(git describe --tags 2>/dev/null || echo "dev")
    echo "==> Pushing ${CONTAINER}:${TAG}..."
    docker push "${CONTAINER}:${TAG}"
    echo "==> Pushing ${CONTAINER}:latest..."
    docker push "${CONTAINER}:latest"
fi

echo "==> Push complete!"
