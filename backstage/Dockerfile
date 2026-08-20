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

FROM node:22-bookworm-slim AS build

RUN apt-get update && apt-get install -y --no-install-recommends     python3     g++     build-essential     git     && rm -rf /var/lib/apt/lists/*

WORKDIR /app
RUN corepack enable && corepack prepare pnpm@10.20.0 --activate

COPY pnpm-workspace.yaml package.json pnpm-lock.yaml ./
COPY backstage/package.json ./backstage/
COPY backstage/packages/app/package.json ./backstage/packages/app/
COPY backstage/packages/backend/package.json ./backstage/packages/backend/

RUN pnpm install --frozen-lockfile

COPY backstage/ ./backstage/

WORKDIR /app/backstage/packages/app
RUN npx backstage-cli package build

WORKDIR /app/backstage/packages/backend
RUN touch yarn.lock && npx backstage-cli package build --skip-build-dependencies

FROM node:22-bookworm-slim AS runtime

# mkdocs + mkdocs-techdocs-core power TechDocs' `generator.runIn: local`. Without
# them the generator defaults to `docker`, which cannot spawn a container from
# inside this pod, so every /docs/... page failed to build.
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    python3 \
    python3-pip \
    && pip3 install --break-system-packages --no-cache-dir mkdocs-techdocs-core==1.6.1 \
    && rm -rf /var/lib/apt/lists/*

# aspect CLI, statically-linked (musl) so it needs no libc/dynamic deps beyond
# what's already here. Pinned to 2026.26.25 -- the exact version the app
# initializer engine (tools/initializer, ADR-026) was developed and proven
# against in P0/P0.5/P1.1. The scaffolder action (Task 3) shells out to this
# binary as `aspect render-app`; a version drift here would let the stamped
# output silently diverge from what was validated upstream.
#
# TARGETARCH is populated by buildx for the multi-arch build (linux/amd64 +
# linux/arm64, see .github/workflows/backstage-image.yaml); sha256 is pinned
# per-arch from the release's published checksums so a compromised or
# swapped release asset fails the build instead of landing silently.
ARG TARGETARCH
ARG ASPECT_CLI_VERSION=2026.26.25
RUN set -eu; \
    case "$TARGETARCH" in \
      amd64) ASPECT_ARCH=x86_64-unknown-linux-musl; \
             ASPECT_SHA256=9430d40f0390382a637be8dde7791a17f66f98c7d00c7f53d57b2e99f55f2136 ;; \
      arm64) ASPECT_ARCH=aarch64-unknown-linux-musl; \
             ASPECT_SHA256=ffdb238922abc9045c066d472700c5de82b40a71a46de0c9c4e58461575ef53e ;; \
      *) echo "unsupported TARGETARCH: $TARGETARCH" >&2; exit 1 ;; \
    esac; \
    curl -fsSL -o /usr/local/bin/aspect \
      "https://github.com/aspect-build/aspect-cli/releases/download/v${ASPECT_CLI_VERSION}/aspect-cli-${ASPECT_ARCH}"; \
    echo "${ASPECT_SHA256}  /usr/local/bin/aspect" | sha256sum -c -; \
    chmod +x /usr/local/bin/aspect
RUN aspect --version

WORKDIR /app

ENV NODE_ENV=production \
    PORT=7007

RUN corepack enable && corepack prepare pnpm@10.20.0 --activate

COPY --from=build /app/pnpm-lock.yaml /app/package.json /app/pnpm-workspace.yaml ./
COPY --from=build /app/backstage/package.json ./backstage/
COPY --from=build /app/backstage/packages/backend/package.json ./backstage/packages/backend/
COPY --from=build /app/backstage/packages/app/package.json ./backstage/packages/app/

RUN pnpm install --prod --frozen-lockfile

COPY --from=build /app/backstage/packages/app/dist ./backstage/packages/app/dist
COPY --from=build /app/backstage/packages/backend/dist ./backstage/packages/backend/dist
COPY --from=build /app/backstage/app-config.yaml ./app-config.yaml

RUN cd /app/backstage/packages/backend && tar xzf dist/bundle.tar.gz && rm dist/bundle.tar.gz dist/skeleton.tar.gz

RUN ln -s /app/backstage/packages /app/packages && \
    mkdir -p /app/node_modules/@vitruviansoftware && \
    ln -s /app/backstage/packages/app /app/node_modules/@vitruviansoftware/backstage-app && \
    ln -s /app/backstage/packages/app /app/node_modules/app

RUN groupadd -r -g 1001 nodejs && useradd -r -u 1001 -g nodejs nodejs
RUN chown -R nodejs:nodejs /app

# useradd -r skips home-dir creation, but $HOME still resolves to
# /home/nodejs -- and `aspect` writes its axl cache to $HOME/.cache/aspect on
# every invocation (confirmed by running it as this user: it fails with
# "Permission denied (os error 13)" against a nonexistent, unwritable
# /home/nodejs). This is exactly the path the scaffolder action (Task 3) runs
# `aspect render-app` on at request time, as this same non-root user.
RUN mkdir -p /home/nodejs && chown nodejs:nodejs /home/nodejs
USER nodejs

EXPOSE 7007
CMD ["node", "packages/backend/dist/index.cjs.js", "--config", "app-config.yaml"]
