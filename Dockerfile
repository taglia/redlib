# Both bases are multi-platform indexes; update the tag and digest together.
FROM rust:1.99.1-trixie@sha256:931c2c0531a8b143e044f0f3914dfe802f15bb3d1955f0b657e9359327ac2ffc AS builder
RUN apt-get update && apt-get install -y --no-install-recommends \
    cmake perl pkg-config libclang-dev git && rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY Cargo.toml Cargo.lock build.rs ./
COPY src ./src
COPY templates ./templates
COPY static ./static
COPY rustfmt.toml ./
ARG SOURCE_COMMIT=unknown
ENV GIT_HASH=${SOURCE_COMMIT}
RUN cargo build --release --locked --bin redlib

FROM debian:trixie-slim@sha256:62bd423aeee912639ca8ee681c2b762cb3e25137e0a92b20be455898a9f034ad AS runtime
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates wget libgcc-s1 libstdc++6 \
    && rm -rf /var/lib/apt/lists/* \
    && groupadd --gid 10001 redlib \
    && useradd --uid 10001 --gid redlib --no-create-home --home-dir /nonexistent --shell /usr/sbin/nologin redlib
COPY --from=builder /app/target/release/redlib /usr/local/bin/redlib
ARG SOURCE_COMMIT=unknown
LABEL org.opencontainers.image.title="Redlib" \
      org.opencontainers.image.source="https://github.com/taglia/redlib" \
      org.opencontainers.image.revision="${SOURCE_COMMIT}" \
      org.opencontainers.image.licenses="AGPL-3.0-only"
USER 10001:10001
EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=3s --start-period=30s --retries=3 CMD wget --spider -q http://127.0.0.1:8080/settings || exit 1
CMD ["redlib"]
