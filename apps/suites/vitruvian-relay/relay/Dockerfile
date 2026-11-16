# syntax=docker/dockerfile:1
#
# Copyright (c) 2026 VitruvianSoftware
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

# The Vitruvian Relay server (apps/suites/vitruvian-relay/relay). Built by
# .github/workflows/vitruvian-relay-image.yaml from the repo root:
#
#   docker buildx build -f apps/suites/vitruvian-relay/relay/Dockerfile \
#     --build-context mcpauth=packages/rust/vitruvian-mcp-auth \
#     apps/suites/vitruvian-relay
#
# The context is the relay WORKSPACE (apps/suites/vitruvian-relay), not this
# folder, because the relay is a member of that workspace and its Cargo.lock
# lives there. The shared token checker comes in as a second, named context
# (`mcpauth`), because relay/Cargo.toml path-depends on
# ../../../../packages/rust/vitruvian-mcp-auth. The layout under /src mirrors
# the repo, so that path resolves unchanged. vitruvian-mcp-auth has no lock of
# its own: the workspace's lock covers it.
#
# Every workspace member's manifest and sources are copied, because cargo loads
# the whole workspace even for `-p vitruvian-relay`; only the relay, the
# protocol crate and vitruvian-mcp-auth are compiled. spike/ is a separate
# workspace and is not copied.

FROM rust:1.98.1-slim-bookworm AS build
COPY --from=mcpauth Cargo.toml /src/packages/rust/vitruvian-mcp-auth/
COPY --from=mcpauth src /src/packages/rust/vitruvian-mcp-auth/src
WORKDIR /src/apps/suites/vitruvian-relay
COPY Cargo.toml Cargo.lock ./
COPY relay/Cargo.toml relay/
COPY relay/src relay/src
COPY protocol/Cargo.toml protocol/
COPY protocol/src protocol/src
COPY connector/Cargo.toml connector/
COPY connector/src connector/src
COPY connector/scripts/Cargo.toml connector/scripts/
COPY connector/scripts/src connector/scripts/src
RUN cargo build --release --locked -p vitruvian-relay --bin vitruvian-relay && \
    install -m 0755 target/release/vitruvian-relay /vitruvian-relay

FROM gcr.io/distroless/cc-debian12:nonroot AS runtime
WORKDIR /app
# DATA_DIR is the chart's persistent volume (devices.json); the chart sets it
# too, so this default only matters for a bare `docker run`.
ENV PORT=3000 \
    DATA_DIR=/data \
    HOME=/tmp
COPY --from=build --chmod=0755 /vitruvian-relay /app/vitruvian-relay
USER 10001:10001
EXPOSE 3000
CMD ["/app/vitruvian-relay"]

ARG GIT_REVISION=unknown
LABEL org.opencontainers.image.title="vitruvian-relay" \
      org.opencontainers.image.description="Vitruvian Relay: OAuth-protected MCP endpoint for AI apps and the WebSocket the Mac connector dials" \
      org.opencontainers.image.source="https://github.com/VitruvianSoftware/vitruvian-core" \
      org.opencontainers.image.licenses="MIT" \
      org.opencontainers.image.revision="${GIT_REVISION}"
