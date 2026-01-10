# Needs packages pkg-config & libressl via homebrew on mac
# Needs libssl-dev & pkg-config on Linux

CONTAINER ?= ghcr.io/jsorge/maverick
TAG       := $$(git describe --tags)
IMG       := ${CONTAINER}:${TAG}
LATEST    := ${CONTAINER}:latest

# Development: download the dev site (jsorge.net) into _dev/
.PHONY: dev
dev:
	./tools/update_dev.sh

# Development: run Maverick locally against _dev/ site (no Docker)
.PHONY: run
run:
	cd _dev && swift run --package-path .. Maverick serve -b 127.0.0.1

# Development: run Maverick in Docker against _dev/ site (builds local Dockerfile)
.PHONY: docker-dev
docker-dev:
	cp tools/docker-compose_local.yml _dev/.tools/docker-compose_local.yml
	cd _dev/.tools && docker-compose -f docker-compose_local.yml up --build

# Development: stop Docker dev containers
.PHONY: docker-dev-down
docker-dev-down:
	cd _dev/.tools && docker-compose -f docker-compose_local.yml down

# Production: build Docker image
.PHONY: docker-build
docker-build:
	@docker build -t ${IMG} .
	@docker tag ${IMG} ${LATEST}

# Production: push Docker image to registry
.PHONY: docker-push
docker-push:
	docker push ${CONTAINER}
