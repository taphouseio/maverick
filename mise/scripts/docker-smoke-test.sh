#!/usr/bin/env bash

set -euo pipefail

readonly IMAGE="${1:-maverick:ci}"
readonly CONTAINER_NAME="maverick-smoke-${RANDOM}-$$"
WORK_DIRECTORY="$(mktemp -d)"

# Invoked indirectly by the EXIT trap.
# shellcheck disable=SC2329
cleanup() {
    docker rm --force "$CONTAINER_NAME" >/dev/null 2>&1 || true
    rm -rf "$WORK_DIRECTORY"
}
trap cleanup EXIT

missing_libraries="$({
    docker run --rm \
        --entrypoint /bin/sh \
        "$IMAGE" \
        -c "ldd /app/Maverick | grep 'not found' || true"
})"

if [[ -n "$missing_libraries" ]]; then
    echo "Missing runtime libraries:"
    echo "$missing_libraries"
    exit 1
fi

cat > "$WORK_DIRECTORY/SiteConfig.yml" <<'YAML'
title: Maverick Container Smoke Test
description: Production container verification
url: http://127.0.0.1
metaDescription: Production container verification
batchSize: 5
feedSize: 20
disablePageCaching: true
YAML

docker run --detach \
    --name "$CONTAINER_NAME" \
    --publish 127.0.0.1::8080 \
    --tmpfs /app/Public:rw,mode=1777 \
    --volume "$WORK_DIRECTORY/SiteConfig.yml:/app/SiteConfig.yml:ro" \
    --entrypoint /bin/sh \
    "$IMAGE" \
    -c 'mkdir -p /app/Public/_pages /app/Public/_posts /app/Public/_drafts /app/Public/incoming/posts /app/Public/incoming/media && exec /app/Maverick serve --env production --hostname 0.0.0.0 --port 8080' \
    >/dev/null

host_port="$(docker inspect --format '{{(index (index .NetworkSettings.Ports "8080/tcp") 0).HostPort}}' "$CONTAINER_NAME")"

for _ in {1..30}; do
    if curl --fail --silent "http://127.0.0.1:${host_port}/health" | grep --quiet '^OK$'; then
        echo "Production image passed dependency and startup checks."
        exit 0
    fi

    if [[ "$(docker inspect --format '{{.State.Running}}' "$CONTAINER_NAME")" != "true" ]]; then
        echo "Maverick exited before becoming healthy."
        docker logs "$CONTAINER_NAME"
        exit 1
    fi

    sleep 1
done

echo "Maverick did not become healthy within 30 seconds."
docker logs "$CONTAINER_NAME"
exit 1
