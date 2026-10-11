# syntax=docker/dockerfile:1.7
# Build with: docker build --build-arg RELEASE=<version> --build-arg C2_SHA256=<sha256> -t hak5c2:<version> .
FROM alpine:3.24 AS fetch

ARG RELEASE=latest
ARG TARGET=amd64_linux
ARG C2_SHA256=""

RUN apk add --no-cache ca-certificates curl unzip busybox-static \
    && mkdir -p /runtime/app \
    && chown 65532:65532 /runtime/app
ARG URL=https://downloads.hak5.org/api/devices/cloudc2/firmwares/${RELEASE}

RUN set -eu; \
    curl --fail --location --retry 5 --connect-timeout 20 --max-time 600 -o /tmp/cloudc2.zip "$URL"; \
    if [ -n "$C2_SHA256" ]; then echo "$C2_SHA256  /tmp/cloudc2.zip" | sha256sum -c -; fi; \
    mkdir /extract; unzip -q /tmp/cloudc2.zip -d /extract; \
    bin="$(find /extract -type f -name "c2-*_${TARGET}" -print -quit)"; \
    test -n "$bin"; install -m 0755 "$bin" /c2

FROM golang:1.27.2-alpine3.24 AS wrapper
WORKDIR /src
COPY entrypoint.go ./entrypoint.go
RUN CGO_ENABLED=0 GOOS=linux go build -trimpath -buildvcs=false -ldflags='-s -w' -o /entrypoint ./entrypoint.go

FROM gcr.io/distroless/static-debian12:nonroot

# Create the application directory with nonroot ownership.
COPY --from=fetch --chown=65532:65532 /runtime/app /app
WORKDIR /app

# BusyBox selects its mv applet from the executable's filename.
COPY --from=fetch /bin/busybox.static /usr/local/bin/mv
ENV PATH="/usr/local/bin:/usr/bin:/bin"

COPY --from=fetch --chown=65532:65532 /c2 /app/c2
COPY --from=wrapper --chown=65532:65532 /entrypoint /app/entrypoint

USER 65532:65532
EXPOSE 8080 2022
ENTRYPOINT ["/app/entrypoint"]
