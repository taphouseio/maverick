# syntax=docker/dockerfile:1

# ================================
# Build image
# ================================
FROM swift:6.2-noble AS build

ARG TARGETARCH

# Install OS updates
RUN export DEBIAN_FRONTEND=noninteractive DEBCONF_NONINTERACTIVE_SEEN=true \
    && apt-get -q update \
    && apt-get -q dist-upgrade -y \
    && apt-get install -y libjemalloc-dev libssl-dev

# Set up a build area
WORKDIR /build

# First just resolve dependencies.
# This creates a cached layer that can be reused
# as long as your Package.swift/Package.resolved
# files do not change.
COPY ./Package.* ./
RUN --mount=type=cache,id=maverick-swift-build-${TARGETARCH},target=/build/.build \
    swift package resolve \
        $([ -f ./Package.resolved ] && echo "--force-resolved-versions" || true)

# SwiftPM validates declared test-target paths even when building a production
# product, so include tests in the small context without compiling them.
COPY ./Sources ./Sources
COPY ./Tests ./Tests

# Build with the SwiftPM output cached outside the image layer. Copy every
# runtime artifact into /staging during the same mount so it remains available
# after the cache mount is detached.
RUN --mount=type=cache,id=maverick-swift-build-${TARGETARCH},target=/build/.build \
    swift build -c release \
        --static-swift-stdlib \
        -Xlinker -ljemalloc \
    && bin_path="$(swift build --package-path /build -c release --show-bin-path)" \
    && mkdir -p /staging \
    && cp "$bin_path/Maverick" /staging/ \
    && cp "/usr/libexec/swift/linux/swift-backtrace-static" /staging/ \
    && find -L "$bin_path" -regex '.*\.resources$' -exec cp -Ra {} /staging/ \;

# ================================
# Run image
# ================================
FROM ubuntu:24.04

# Make sure all system packages are up to date, and install only essential packages.
RUN export DEBIAN_FRONTEND=noninteractive DEBCONF_NONINTERACTIVE_SEEN=true \
    && apt-get -q update \
    && apt-get -q dist-upgrade -y \
    && apt-get -q install -y \
      libjemalloc2 \
      ca-certificates \
      tzdata \
      libcurl4 \
      libxml2 \
    && rm -r /var/lib/apt/lists/*

# Create a vapor user and group with /app as its home directory
RUN useradd --user-group --create-home --system --skel /dev/null --home-dir /app vapor

# Switch to the new home directory
WORKDIR /app

# Copy built executable and any staged resources from builder
COPY --from=build --chown=vapor:vapor /staging /app

# Provide configuration needed by the built-in crash reporter and some sensible default behaviors.
ENV SWIFT_BACKTRACE=enable=yes,sanitize=yes,threads=all,images=all,interactive=no,swift-backtrace=./swift-backtrace-static

# Ensure all further commands run as the vapor user
USER vapor:vapor

# Let Docker bind to port 8080
EXPOSE 8080

# Start the Vapor service when the image is run, default to listening on 8080 in production environment
ENTRYPOINT ["./Maverick"]
CMD ["serve", "--env", "production", "--hostname", "0.0.0.0", "--port", "8080"]
