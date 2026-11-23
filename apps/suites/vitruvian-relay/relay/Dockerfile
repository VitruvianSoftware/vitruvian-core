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
#     --build-context mcpauth=packages/mcp-auth \
#     apps/suites/vitruvian-relay
#
# The context is the relay WORKSPACE (apps/suites/vitruvian-relay), not this
# folder, because the relay is a member of that workspace and its Cargo.lock
# lives there. The shared token checker comes in as a second, named context
# (`mcpauth`), because relay/Cargo.toml path-depends on
# ../../../../packages/mcp-auth. The layout under /src mirrors
# the repo, so that path resolves unchanged. vitruvian-mcp-auth has no lock of
# its own: the workspace's lock covers it.
#
# Every workspace member's manifest is copied because cargo loads the whole
# workspace even for `-p vitruvian-relay`. Connector crates stay dummy stubs
# (dev-dep only, never compiled into the relay binary); third-party crates are
# prebuilt against manifests+stubs before copying real relay/protocol/mcpauth
# sources, on $BUILDPLATFORM with cross-compilation rather than QEMU.

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

COPY --from=mcpauth Cargo.toml /src/packages/mcp-auth/
RUN mkdir -p /src/packages/mcp-auth/src && \
    printf '// stub for dependency prebuild\n' > /src/packages/mcp-auth/src/lib.rs
WORKDIR /src/apps/suites/vitruvian-relay
COPY Cargo.toml Cargo.lock ./
COPY relay/Cargo.toml relay/
COPY protocol/Cargo.toml protocol/
COPY connector/Cargo.toml connector/
COPY connector/scripts/Cargo.toml connector/scripts/
RUN set -eu; \
    . /tmp/cross.env; \
    mkdir -p relay/src protocol/src connector/src connector/scripts/src && \
    printf '// stub for dependency prebuild\n' > relay/src/lib.rs && \
    printf 'fn main() { std::process::exit(97); }\n' > relay/src/main.rs && \
    printf '// stub for dependency prebuild\n' > protocol/src/lib.rs && \
    printf '// stub for workspace member\n' > connector/src/lib.rs && \
    printf 'fn main() { std::process::exit(97); }\n' > connector/src/main.rs && \
    printf '// stub for workspace member\n' > connector/scripts/src/lib.rs && \
    printf 'fn main() { std::process::exit(97); }\n' > connector/scripts/src/main.rs && \
    cargo build --release --locked --target "$RUST_TARGET" -p vitruvian-relay --bin vitruvian-relay

COPY --from=mcpauth src /src/packages/mcp-auth/src
COPY relay/src relay/src
# The schema is compiled in (include_str! in relay/src/store.rs).
COPY relay/migrations relay/migrations
COPY protocol/src protocol/src
RUN set -eu; \
    . /tmp/cross.env; \
    find /src/packages/mcp-auth/src relay/src protocol/src -type f -name '*.rs' -exec touch {} + && \
    rm -rf target/"$RUST_TARGET"/release/vitruvian-relay* \
           target/"$RUST_TARGET"/release/deps/*vitruvian_relay* \
           target/"$RUST_TARGET"/release/deps/*vitruvian_mcp_auth* \
           target/"$RUST_TARGET"/release/.fingerprint/vitruvian-relay-* \
           target/"$RUST_TARGET"/release/.fingerprint/vitruvian-mcp-auth-* && \
    cargo build --release --locked --target "$RUST_TARGET" -p vitruvian-relay --bin vitruvian-relay && \
    install -m 0755 target/"$RUST_TARGET"/release/vitruvian-relay /vitruvian-relay && \
    got="$(od -An -tx1 -j18 -N2 /vitruvian-relay | tr -d ' \n')"; \
    if [ "$got" != "$ELF_EM" ]; then \
      echo "unexpected ELF e_machine=$got expected=$ELF_EM (TARGETARCH=$TARGETARCH)" >&2; \
      exit 1; \
    fi

FROM gcr.io/distroless/cc-debian12:nonroot AS runtime
WORKDIR /app
# DATABASE_URL (Postgres) is required and has no default: the chart sets it.
# The relay keeps devices and calls in Postgres and writes nothing to disk.
ENV PORT=3000 \
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
