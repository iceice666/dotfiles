FROM docker.io/library/rust:1.96.0-bookworm AS builder

ARG REV

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
    && rm -rf /var/lib/apt/lists/*

WORKDIR /src
RUN git init \
    && git remote add origin https://github.com/mozufu/TempestMiku.git \
    && git fetch --depth=1 origin "${REV}" \
    && git checkout --detach FETCH_HEAD

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
