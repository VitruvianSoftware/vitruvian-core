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
# Multi-stage production container for God's Eye View (geospatial intelligence console).
# Build context is the monorepo root (filtered via Dockerfile.dockerignore) so
# production dependencies install strictly from pnpm-lock.yaml (--frozen-lockfile).
# Runs Node 26 slim with a non-root UID 1001 on port 8080 and native health probe.

# --- Build Stage: Compile web assets to dist/ on $BUILDPLATFORM ---------------
FROM --platform=$BUILDPLATFORM node:26-bookworm-slim AS build

WORKDIR /workspace

RUN npm install -g corepack && corepack enable && corepack prepare pnpm@10.20.0 --activate

COPY package.json pnpm-lock.yaml pnpm-workspace.yaml .npmrc ./
COPY apps/web/gods-eye-view/package.json ./apps/web/gods-eye-view/
RUN pnpm install --frozen-lockfile --filter=gods-eye-view

COPY apps/web/gods-eye-view/ ./apps/web/gods-eye-view/
RUN pnpm --filter=gods-eye-view build

# --- Production Dependencies Stage: Materialize target-arch prod deps ----------
FROM --platform=$BUILDPLATFORM node:26-bookworm-slim AS prod-deps
ARG TARGETARCH

WORKDIR /workspace

RUN npm install -g corepack && corepack enable && corepack prepare pnpm@10.20.0 --activate

COPY package.json pnpm-lock.yaml pnpm-workspace.yaml .npmrc ./
COPY apps/web/gods-eye-view/package.json ./apps/web/gods-eye-view/

RUN set -eu; \
    case "$TARGETARCH" in \
      amd64) PNPM_CPU=x64; ELF_EM=3e00 ;; \
      arm64) PNPM_CPU=arm64; ELF_EM=b700 ;; \
      *) echo "unsupported TARGETARCH: $TARGETARCH" >&2; exit 1 ;; \
    esac; \
    pnpm deploy --legacy --prod --frozen-lockfile \
      --os=linux --cpu="$PNPM_CPU" --libc=glibc \
      --filter=gods-eye-view /prod; \
    checked=0; \
    for f in $(find /prod/node_modules -type f \( -name '*.node' -o -name '*.so' -o -name '*.so.*' -o -perm -111 \)); do \
      magic="$(od -An -tx1 -N4 "$f" | tr -d ' \n')"; \
      if [ "$magic" = "7f454c46" ]; then \
        checked=$((checked + 1)); \
        got="$(od -An -tx1 -j18 -N2 "$f" | tr -d ' \n')"; \
        if [ "$got" != "$ELF_EM" ]; then \
          echo "unexpected ELF e_machine=$got (expected $ELF_EM for TARGETARCH=$TARGETARCH) in $f" >&2; \
          exit 1; \
        fi; \
      fi; \
    done; \
    echo "verified $checked native ELF module(s) in /prod/node_modules for TARGETARCH=$TARGETARCH (e_machine=$ELF_EM)"

# --- Runtime Stage: Zero-RUN multi-arch runtime image ------------------------
FROM node:26-bookworm-slim AS runtime

WORKDIR /app

ENV NODE_ENV=production \
    PORT=8080

COPY --from=prod-deps --chown=1001:1001 /prod/node_modules ./node_modules
COPY --from=build --chown=1001:1001 /workspace/apps/web/gods-eye-view/dist ./dist
COPY --chown=1001:1001 apps/web/gods-eye-view/package.json apps/web/gods-eye-view/server.mjs ./
# Upstream's route handlers, which server.mjs mounts, and the files they read
# at run time: config/ and src/data/local_data/ (CCTV sources, regions).
# Whole trees, so a file an upstream sync adds is already in the image.
COPY --chown=1001:1001 apps/web/gods-eye-view/server/ ./server/
COPY --chown=1001:1001 apps/web/gods-eye-view/src/ ./src/
COPY --chown=1001:1001 apps/web/gods-eye-view/config/ ./config/
COPY --chown=1001:1001 apps/web/gods-eye-view/build/ ./build/
COPY --chown=1001:1001 apps/web/gods-eye-view/scripts/ ./scripts/

# 1001 matches gitops/argocd/platform/gods-eye-view/deployment.yaml (runAsUser: 1001).
USER 1001:1001

EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=10s --start-period=10s --retries=3 \
    CMD ["node", "-e", "fetch('http://127.0.0.1:8080/healthz').then(r => process.exit(r.ok ? 0 : 1)).catch(() => process.exit(1))"]

CMD ["node", "server.mjs"]

# Provenance: tie the published digest back to its source commit. Placed last
# so changing GIT_REVISION on every commit never invalidates build/dep layers.
ARG GIT_REVISION=unknown
LABEL org.opencontainers.image.source="https://github.com/VitruvianSoftware/vitruvian-core" \
      org.opencontainers.image.revision="${GIT_REVISION}"
