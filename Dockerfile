# Dockerfile for DHBW Roomfinder API
FROM ghcr.io/gleam-lang/gleam:v1.19.0-erlang-alpine AS builder

WORKDIR /build

# Copy manifest & config to cache dependencies layer
COPY gleam.toml manifest.toml ./
RUN gleam deps download

# Copy source and tests
COPY src ./src
COPY test ./test

# Verify formatting and tests pass before build
RUN gleam format --check src test
RUN gleam test

# Build production Erlang release
RUN gleam export erlang-shipment

# --- Production Runner Stage ---
# Must match Erlang OTP release
FROM docker.io/library/erlang:28-alpine

WORKDIR /app

# Copy production shipment artifact
COPY --from=builder /build/build/erlang-shipment ./

ENV PORT=8000
EXPOSE 8000

# Fix entrypoint script permissions
RUN chmod +x /app/entrypoint.sh

# Start server
ENTRYPOINT ["/bin/sh", "/app/entrypoint.sh", "run"]
