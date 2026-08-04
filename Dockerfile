# Multi-stage build for llmfit (with embedded web dashboard)
# rustc >= 1.95 required: sysinfo 0.39.x bumped its MSRV to 1.95.
# Pin the Debian release to match the runtime stage (bookworm). The default
# rust:1.95-slim base tracks trixie (glibc 2.39), which links the binary
# against symbols the bookworm runtime (glibc 2.36) does not provide, so the
# binary fails to start with "GLIBC_2.39 not found". Keep both stages on the
# same release so the linked glibc is always available at runtime.

# Stage 1: Build llmfit-web assets (embedded into the Rust binary at compile time)
FROM node:22-bookworm-slim AS web
WORKDIR /web
COPY llmfit-web/package.json llmfit-web/package-lock.json ./
RUN npm ci
COPY llmfit-web/ ./
RUN npm run build

# Stage 2: Build the Rust binary
FROM rust:1.95-slim-bookworm AS builder

RUN apt-get update && apt-get install -y \
    pkg-config \
    libssl-dev \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /build

COPY Cargo.toml Cargo.lock ./
COPY llmfit-core/ ./llmfit-core/
COPY llmfit-tui/ ./llmfit-tui/
COPY llmfit-desktop/ ./llmfit-desktop/
COPY --from=web /web/dist ./llmfit-web/dist

RUN cargo build --release -p llmfit

# Stage 3: Runtime image
FROM debian:bookworm-slim

RUN apt-get update && apt-get install -y \
    pciutils \
    lshw \
    && rm -rf /var/lib/apt/lists/*

COPY --from=builder /build/target/release/llmfit /usr/local/bin/llmfit

RUN useradd -m -u 1000 llmfit && \
    chown -R llmfit:llmfit /usr/local/bin/llmfit

USER llmfit

ENTRYPOINT ["/usr/local/bin/llmfit"]
CMD ["serve", "--host", "0.0.0.0", "--port", "8787"]