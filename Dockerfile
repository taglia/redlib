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
RUN cargo build --release --locked --bin redlib --bin redlib-healthcheck

# No shell, package manager, mount/login utilities, or general-purpose downloader.
FROM gcr.io/distroless/cc-debian13:nonroot@sha256:3ee00291cf386ec52a552e6a858d555debd74776eb4bfa53fa3df2cd6677515e AS runtime
COPY --from=builder /app/target/release/redlib /usr/local/bin/redlib
COPY --from=builder /app/target/release/redlib-healthcheck /usr/local/bin/redlib-healthcheck
ARG SOURCE_COMMIT=unknown
LABEL org.opencontainers.image.title="Redlib" \
      org.opencontainers.image.source="https://github.com/taglia/redlib" \
      org.opencontainers.image.revision="${SOURCE_COMMIT}" \
      org.opencontainers.image.licenses="AGPL-3.0-only"
USER 10001:10001
EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=7s --start-period=120s --retries=3 CMD ["/usr/local/bin/redlib-healthcheck"]
ENTRYPOINT ["/usr/local/bin/redlib"]
