FROM docker.io/library/rust:1.96.0-bookworm AS builder

ARG SOURCE_ARCHIVE_SHA256
ARG SOURCE_REV

LABEL org.opencontainers.image.revision="${SOURCE_REV}"

RUN apt-get update \
    && apt-get install --yes --no-install-recommends \
        ca-certificates \
        clang \
        cmake \
        curl \
        git \
        libssl-dev \
        pkg-config \
        python3 \
    && rm -rf /var/lib/apt/lists/* \
    && mkdir -p /etc/tempestmiku /run/secrets

COPY source.tar.gz /tmp/source.tar.gz
RUN printf '%s  %s\n' "${SOURCE_ARCHIVE_SHA256}" /tmp/source.tar.gz | sha256sum -c - \
    && mkdir -p /src \
    && tar -xzf /tmp/source.tar.gz --no-same-owner --strip-components=1 -C /src \
    && test -f /src/Cargo.lock \
    && test -f /src/crates/tm-server/Cargo.toml \
    && rm /tmp/source.tar.gz

WORKDIR /src
ENV CARGO_BUILD_JOBS=2
RUN cargo build --locked --release --package tm-server

FROM docker.io/library/debian:bookworm-slim

RUN apt-get update \
    && apt-get install --yes --no-install-recommends \
        ca-certificates \
        libssl3 \
        libstdc++6 \
    && rm -rf /var/lib/apt/lists/*

COPY --from=builder /src/target/release/tm-server /usr/local/bin/tm-server

ENTRYPOINT ["/usr/local/bin/tm-server"]
