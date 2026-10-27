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
#
# Container image for the mcp-slack HTTP transport, consumed by
# deploy/chart (gitops/argocd/applications/mcp-slack.yaml -> image.digest).
#
# THIS IMAGE IS BUILT FROM SOURCE, NEVER FROM THE npm PACKAGE, and that is a
# correctness requirement rather than a preference: `npm i
# @vitruviansoftware/mcp-slack` resolves to 1.0.3 (2026-05-07) and SUCCEEDS —
# a build three months stale that predates the HTTP transport, the OIDC auth
# layer and the channel allow-list entirely. Every release since failed in the
# mirror's release.yml, so the registry never moved while the tags did. An
# image built from that package would start, pass its probes, and be the wrong
# program.
#
# The build context is THIS directory, so `docker build mcp-slack/` works in
# the monorepo and in the one-way standalone mirror alike (the mirror only ever
# receives this subtree). That is why the server keeps its own Cargo.lock in
# rs/ rather than using the repo's root one.
#
# The server is Rust. The build stage compiles it with `cargo build --locked`,
# so the image holds exactly the crate versions in rs/Cargo.lock, the ones
# Bazel builds and tests (@mcp_slack_crates) and nothing re-resolved here.
# The runtime is distroless: glibc, the CA bundle the HTTPS client trusts for
# Slack and the issuer, and the binary. No shell, no package manager, no Node.

# --- Build stage --------------------------------------------------------------
FROM rust:1.85-slim-bookworm AS build
WORKDIR /src
COPY rs/Cargo.toml rs/Cargo.lock ./
COPY rs/src ./src
RUN cargo build --release --locked --bin mcp-slack && \
    install -m 0755 target/release/mcp-slack /mcp-slack

# --- Runtime stage --------------------------------------------------------------
# cc-debian12 matches the build stage's bookworm glibc and ships
# /etc/ssl/certs/ca-certificates.crt, which the client loads as its trust store.
FROM gcr.io/distroless/cc-debian12:nonroot AS runtime
WORKDIR /app

# PORT is the chart's contract (deployment.yaml containerPort: 3000), defaulted
# here so the image is correct when run outside Kubernetes too. The chart still
# sets it explicitly rather than inheriting — two statements of the same number
# is deliberate: this one keeps the image self-describing, that one keeps the
# manifest readable.
ENV PORT=3000 \
    MCP_TRANSPORT=http \
    HOME=/tmp

COPY --from=build --chmod=0755 /mcp-slack /app/mcp-slack

# The pod overrides USER with `runAsUser: 10001` (deploy/chart deployment.yaml),
# a UID that exists in no image layer. Everything the process reads must
# therefore be world-readable: the binary is copied 0755, and the CA bundle
# is world-readable in the base image.
#
# USER is set to the same numeric UID so the image's own default matches the
# pod's, rather than relying on the manifest to correct it. Numeric and not a
# named user: `runAsNonRoot` is evaluated by the kubelet against a UID, and a
# name it cannot resolve fails the pod rather than the check.
USER 10001:10001

# Documentation only — Kubernetes routes by containerPort, not by EXPOSE.
EXPOSE 3000

# No HEALTHCHECK: Kubernetes ignores it and drives /health through the pod's
# liveness/readiness probes instead. Adding one would mean shipping `curl` in
# the runtime layer of an internet-facing pod that holds a Slack bot token,
# which is attack surface bought for nothing.
CMD ["/app/mcp-slack"]

# Provenance. `org.opencontainers.image.revision` is the ONLY reliable
# digest -> commit tie available here: no AR or GHCR repository in this org
# sets immutable tags, so a `:<sha>` tag can be repointed at different bits
# later and proves nothing about what is running. Passed as a build arg and
# declared here rather than left to the builder — nothing injects these
# automatically, and an absent label looks identical to a correct one until
# someone tries to use it.
#
# LAST, deliberately: a LABEL layer is metadata-only, so putting it at the end
# keeps a revision change from invalidating the dependency and compile layers
# above it on every commit.
ARG GIT_REVISION=unknown
LABEL org.opencontainers.image.title="mcp-slack" \
      org.opencontainers.image.description="Slack MCP server (HTTP transport, OIDC-authenticated)" \
      org.opencontainers.image.source="https://github.com/VitruvianSoftware/vitruvian-core" \
      org.opencontainers.image.licenses="MIT" \
      org.opencontainers.image.revision="${GIT_REVISION}"
