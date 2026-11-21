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
# Container image for the vitruvian-slack-mcp HTTP transport, consumed by
# deploy/chart (gitops/argocd/applications/vitruvian-slack-mcp.yaml -> image.digest).
#
# THIS IMAGE IS BUILT FROM SOURCE, NEVER FROM AN npm PACKAGE, and that is a
# correctness requirement rather than a preference: the legacy npm package
# stopped updating before the HTTP transport, the OIDC auth layer and the
# channel allow-list existed. An image built from a stale registry artifact
# would start, pass its probes, and be the wrong program.
#
# The build context is THIS directory, so `docker build apps/mcp/vitruvian-slack-mcp/` works in
# the monorepo and in the one-way standalone mirror alike (the mirror only ever
# receives this subtree). That is why the server keeps its own Cargo.lock in
# rs/ rather than using the repo's root one.
#
# The server is Rust. The build stage compiles it with `cargo build --locked`,
# so the image holds exactly the crate versions in rs/Cargo.lock, the ones
# Bazel builds and tests (@vitruvian_slack_mcp_crates) and nothing re-resolved here.
# The runtime is distroless: glibc, the CA bundle the HTTPS client trusts for
# Slack and the issuer, and the binary. No shell, no package manager, no Node.

# --- Build stage --------------------------------------------------------------
# The shared token-checking crate, vitruvian-mcp-auth. The standalone repo
# carries it at mcp-auth/, so a plain `docker build .` there uses this stage.
# The monorepo keeps it at packages/mcp-auth, outside this
# folder, and its image workflow replaces this stage with
# `--build-context mcpauth=packages/mcp-auth` (a named build
# context overrides a stage of the same name).
FROM scratch AS mcpauth
COPY mcp-auth/Cargo.toml /Cargo.toml
COPY mcp-auth/src /src

# The layout under /src mirrors the monorepo, so rs/Cargo.toml's path to the
# crate (../../../../packages/mcp-auth) resolves unchanged. The
# standalone repo's Cargo.toml says ../mcp-auth instead; the link makes that
# resolve too.
#
# Built on $BUILDPLATFORM with cross-compilation instead of QEMU emulation,
# and split into manifest+stub dependency prebuild -> real source compile so
# source-only changes reuse the compiled third-party crate layer.
FROM --platform=$BUILDPLATFORM rust:1.98.1-slim-bookworm AS build
ARG TARGETARCH
ARG BUILDARCH

RUN set -eu; \
    : > /tmp/cross.env; \
    case "$TARGETARCH" in \
      amd64) RUST_TARGET=x86_64-unknown-linux-gnu; APT_PKGS="gcc-x86-64-linux-gnu libc6-dev-amd64-cross"; TRIPLET=x86_64-linux-gnu; ENV_SLUG=x86_64_unknown_linux_gnu; LINKER_SLUG=X86_64_UNKNOWN_LINUX_GNU; ELF_EM=3e00 ;; \
      arm64) RUST_TARGET=aarch64-unknown-linux-gnu; APT_PKGS="gcc-aarch64-linux-gnu libc6-dev-arm64-cross"; TRIPLET=aarch64-linux-gnu; ENV_SLUG=aarch64_unknown_linux_gnu; LINKER_SLUG=AARCH64_UNKNOWN_LINUX_GNU; ELF_EM=b700 ;; \
      *) echo "unsupported TARGETARCH: $TARGETARCH" >&2; exit 1 ;; \
    esac; \
    echo "RUST_TARGET=$RUST_TARGET" >> /tmp/cross.env; \
    echo "ELF_EM=$ELF_EM" >> /tmp/cross.env; \
    if [ "$TARGETARCH" != "$BUILDARCH" ]; then \
      rustup target add "$RUST_TARGET"; \
      apt-get update && apt-get install -y --no-install-recommends $APT_PKGS && rm -rf /var/lib/apt/lists/*; \
      echo "export CC_${ENV_SLUG}=${TRIPLET}-gcc" >> /tmp/cross.env; \
      echo "export AR_${ENV_SLUG}=${TRIPLET}-ar" >> /tmp/cross.env; \
      echo "export CARGO_TARGET_${LINKER_SLUG}_LINKER=${TRIPLET}-gcc" >> /tmp/cross.env; \
    fi

COPY --from=mcpauth /Cargo.toml /src/packages/mcp-auth/Cargo.toml
RUN mkdir -p /src/apps/mcp/vitruvian-slack-mcp /src/packages/mcp-auth/src && \
    ln -s /src/packages/mcp-auth /src/apps/mcp/vitruvian-slack-mcp/mcp-auth && \
    printf '// stub for dependency prebuild\n' > /src/packages/mcp-auth/src/lib.rs
WORKDIR /src/apps/mcp/vitruvian-slack-mcp/rs
COPY rs/Cargo.toml rs/Cargo.lock ./
RUN set -eu; \
    . /tmp/cross.env; \
    mkdir -p src && \
    printf '// stub for dependency prebuild\n' > src/lib.rs && \
    printf 'fn main() { std::process::exit(97); }\n' > src/main.rs && \
    cargo build --release --locked --target "$RUST_TARGET" --bin vitruvian-slack-mcp

COPY --from=mcpauth /src /src/packages/mcp-auth/src
COPY rs/src ./src
RUN set -eu; \
    . /tmp/cross.env; \
    find /src/packages/mcp-auth/src src -type f -name '*.rs' -exec touch {} + && \
    rm -rf target/"$RUST_TARGET"/release/vitruvian-slack-mcp* \
           target/"$RUST_TARGET"/release/deps/*vitruvian_slack_mcp* \
           target/"$RUST_TARGET"/release/deps/*vitruvian_mcp_auth* \
           target/"$RUST_TARGET"/release/.fingerprint/vitruvian-slack-mcp-* \
           target/"$RUST_TARGET"/release/.fingerprint/vitruvian-mcp-auth-* && \
    cargo build --release --locked --target "$RUST_TARGET" --bin vitruvian-slack-mcp && \
    install -m 0755 target/"$RUST_TARGET"/release/vitruvian-slack-mcp /vitruvian-slack-mcp && \
    got="$(od -An -tx1 -j18 -N2 /vitruvian-slack-mcp | tr -d ' \n')"; \
    if [ "$got" != "$ELF_EM" ]; then \
      echo "unexpected ELF e_machine=$got expected=$ELF_EM (TARGETARCH=$TARGETARCH)" >&2; \
      exit 1; \
    fi

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

COPY --from=build --chmod=0755 /vitruvian-slack-mcp /app/vitruvian-slack-mcp

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
CMD ["/app/vitruvian-slack-mcp"]

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
LABEL org.opencontainers.image.title="vitruvian-slack-mcp" \
      org.opencontainers.image.description="Vitruvian Slack MCP server (HTTP transport, OIDC-authenticated)" \
      org.opencontainers.image.source="https://github.com/VitruvianSoftware/vitruvian-core" \
      org.opencontainers.image.licenses="MIT" \
      org.opencontainers.image.revision="${GIT_REVISION}"
