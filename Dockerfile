# You can set the Swift version to what you need for your app. Versions can be found here: https://hub.docker.com/_/swift
FROM swift:6.0.3-jammy AS build

# Keep the build CPU baseline compatible with older x86_64 hosts.
ARG SWIFT_TARGET_CPU=x86-64

# For local build, add `--build-arg env=docker`
# In your application, you can use `Environment.custom(name: "docker")` to check if you're in this env
# ARG env

RUN apt-get -qq update && apt-get install -y \
  libssl-dev zlib1g-dev \
  && rm -r /var/lib/apt/lists/*
WORKDIR /app
COPY . .
RUN mkdir -p /build/bin /build/lib
RUN SWIFT_FLAGS="-Xswiftc -target-cpu -Xswiftc ${SWIFT_TARGET_CPU}" \
  && swift build -c release ${SWIFT_FLAGS} \
  && BIN_PATH="$(swift build -c release --show-bin-path ${SWIFT_FLAGS})" \
  && mv "${BIN_PATH}"/* /build/bin/
RUN find /usr/lib/swift/linux -name '*.so*' -exec cp {} /build/lib/ \;

# Production image
FROM ubuntu:22.04

RUN apt-get -qq update && DEBIAN_FRONTEND=noninteractive apt-get install -y \
  libatomic1 libicu70 libxml2 libcurl4 zlib1g libbsd0 tzdata \
  && rm -r /var/lib/apt/lists/*
WORKDIR /app
COPY --from=build /build/bin/Maverick .
COPY --from=build /build/lib/* /usr/lib/

EXPOSE 8080
ENTRYPOINT ["./Maverick", "serve", "-e", "prod", "-b", "0.0.0.0"]
