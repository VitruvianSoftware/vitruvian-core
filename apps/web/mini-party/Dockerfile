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

# Mini Party rooms server: the socket.io relay behind online play, without the
# web client (GitHub Pages serves that). Runs on the homelab cluster at
# mini-games-rooms.vitruviansoftware.dev; see gitops/argocd/platform/mini-party.
#
# Built from the repository root so pnpm installs from the monorepo lockfile:
#   docker build -f apps/web/mini-party/Dockerfile .

# Bundle server.ts (and server/) into one ES module. Dependencies stay
# external and come from the prod-deps stage.
FROM --platform=$BUILDPLATFORM node:26-bookworm-slim AS build
WORKDIR /workspace
RUN npm install -g corepack && corepack enable && corepack prepare pnpm@10.20.0 --activate
COPY package.json pnpm-lock.yaml pnpm-workspace.yaml .npmrc ./
COPY apps/web/mini-party/package.json ./apps/web/mini-party/
RUN pnpm install --frozen-lockfile --filter=mini-party
COPY apps/web/mini-party/ ./apps/web/mini-party/
RUN pnpm --filter=mini-party run build:server

# Only the runtime dependencies (express, socket.io): pure JavaScript, so the
# build platform's install works on both architectures.
FROM --platform=$BUILDPLATFORM node:26-bookworm-slim AS prod-deps
WORKDIR /workspace
RUN npm install -g corepack && corepack enable && corepack prepare pnpm@10.20.0 --activate
COPY package.json pnpm-lock.yaml pnpm-workspace.yaml .npmrc ./
COPY apps/web/mini-party/package.json ./apps/web/mini-party/
RUN pnpm deploy --legacy --prod --frozen-lockfile --filter=mini-party /prod

FROM node:26-bookworm-slim AS runtime
WORKDIR /app
ENV NODE_ENV=production \
    PORT=8080
COPY --from=prod-deps --chown=1001:1001 /prod/node_modules ./node_modules
COPY --from=prod-deps --chown=1001:1001 /prod/package.json ./package.json
COPY --from=build --chown=1001:1001 /workspace/apps/web/mini-party/dist-server/server.mjs ./server.mjs
USER 1001:1001
EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=5s --start-period=5s --retries=3 \
    CMD ["node", "-e", "fetch('http://127.0.0.1:8080/healthz').then(r => process.exit(r.ok ? 0 : 1)).catch(() => process.exit(1))"]
CMD ["node", "server.mjs"]

ARG GIT_REVISION=unknown
LABEL org.opencontainers.image.source="https://github.com/VitruvianSoftware/vitruvian-core" \
      org.opencontainers.image.revision="${GIT_REVISION}" \
      org.opencontainers.image.description="Mini Party rooms server"
