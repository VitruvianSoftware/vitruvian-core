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

# The Vitruvian Relay P0 spike server. Built by .github/workflows/vitruvian-relay-spike-image.yaml
# with this folder as the context and vitruvian-slack-mcp's crate as a second, named
# context (`--build-context slackmcp=apps/mcp/vitruvian-slack-mcp/rs`), because the spike
# reuses vitruvian-slack-mcp's token verifier through a Cargo path dependency
# (../../../mcp/vitruvian-slack-mcp/rs). The layout under /src mirrors apps/ so that path
# resolves unchanged.

FROM rust:1.85-slim-bookworm AS build
WORKDIR /src/suites/vitruvian-relay/spike
COPY --from=slackmcp Cargo.toml Cargo.lock /src/mcp/vitruvian-slack-mcp/rs/
COPY --from=slackmcp src /src/mcp/vitruvian-slack-mcp/rs/src
COPY Cargo.toml Cargo.lock ./
COPY src ./src
RUN cargo build --release --locked --bin vitruvian-relay-spike && \
    install -m 0755 target/release/vitruvian-relay-spike /vitruvian-relay-spike

FROM gcr.io/distroless/cc-debian12:nonroot AS runtime
WORKDIR /app
ENV PORT=3000 \
    HOME=/tmp
COPY --from=build --chmod=0755 /vitruvian-relay-spike /app/vitruvian-relay-spike
USER 10001:10001
EXPOSE 3000
CMD ["/app/vitruvian-relay-spike"]

ARG GIT_REVISION=unknown
LABEL org.opencontainers.image.title="vitruvian-relay-spike" \
      org.opencontainers.image.description="Vitruvian Relay P0 spike: OAuth-protected MCP endpoint and WebSocket echo" \
      org.opencontainers.image.source="https://github.com/VitruvianSoftware/vitruvian-core" \
      org.opencontainers.image.licenses="MIT" \
      org.opencontainers.image.revision="${GIT_REVISION}"
