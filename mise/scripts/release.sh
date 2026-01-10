#!/usr/bin/env bash
set -e

CONTAINER="${CONTAINER:-ghcr.io/jsorge/maverick}"

# Get current version from git tags
CURRENT_VERSION=$(git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//' || echo "none")
echo "Current version: ${CURRENT_VERSION}"

# Prompt for new version
read -p "Enter new version (without 'v' prefix): " VERSION

if [[ -z "$VERSION" ]]; then
    echo "Error: Version is required"
    exit 1
fi

# Confirm
echo ""
echo "This will:"
echo "  1. Create git tag v${VERSION}"
echo "  2. Build Docker image ${CONTAINER}:${VERSION}"
echo "  3. Push ${CONTAINER}:${VERSION} and ${CONTAINER}:latest"
echo "  4. Push git tag to origin"
echo ""
read -p "Continue? [y/N] " CONFIRM

if [[ "$CONFIRM" != "y" && "$CONFIRM" != "Y" ]]; then
    echo "Aborted."
    exit 0
fi

echo ""
echo "==> Creating git tag v${VERSION}..."
git tag -a "v${VERSION}" -m "Release v${VERSION}"

echo "==> Building Docker image..."
docker build -t "${CONTAINER}:${VERSION}" -t "${CONTAINER}:latest" .

echo "==> Pushing ${CONTAINER}:${VERSION}..."
docker push "${CONTAINER}:${VERSION}"

echo "==> Pushing ${CONTAINER}:latest..."
docker push "${CONTAINER}:latest"

echo "==> Pushing git tag..."
git push origin "v${VERSION}"

echo ""
echo "==> Release v${VERSION} complete!"
