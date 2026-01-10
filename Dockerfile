# You can set the Swift version to what you need for your app. Versions can be found here: https://hub.docker.com/_/swift
FROM swift:6.0.3-jammy AS build

# For local build, add `--build-arg env=docker`
# In your application, you can use `Environment.custom(name: "docker")` to check if you're in this env
# ARG env

RUN apt-get -qq update && apt-get install -y \
  libssl-dev zlib1g-dev \
  && rm -r /var/lib/apt/lists/*
WORKDIR /app
COPY . .
RUN mkdir -p /build/lib && cp -R /usr/lib/swift/linux/*.so* /build/lib
RUN swift build -c release && mv `swift build -c release --show-bin-path` /build/bin

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
