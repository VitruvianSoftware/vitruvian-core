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
# Self-contained container build for the standalone repo + the monorepo deploy
# pipeline. The Node major is NOT hardcoded: it comes from the NODE_VERSION build
# arg below, which defaults to the repo canonical (the .nvmrc major) and is passed
# explicitly from .nvmrc by the deploy workflow — so the image always tracks the
# repo's single canonical Node. pnpm via corepack. The build context is this app
# directory; deps are resolved from package.json. In the monorepo the pinned
# versions live in the root pnpm-lock.yaml (used by CI/tests); here we resolve
# fresh so `docker build oauth-user-inspector/` works in both the monorepo and
# the one-way standalone mirror.

# NODE_VERSION defaults to the repo canonical (.nvmrc major); CI overrides it via
# --build-arg sourced from .nvmrc. //tools/conformance:check enforces that this
# default equals canonical, so it cannot silently drift.
ARG NODE_VERSION=22

# --- Build stage: compile the Vite/React frontend (-> dist) + the TS server (-> dist-server)
FROM node:${NODE_VERSION}-slim AS build
WORKDIR /app
RUN corepack enable
COPY package.json ./
COPY tsconfig.json ./
COPY frontend/ ./frontend/
COPY server/ ./server/
RUN pnpm install --no-frozen-lockfile
RUN pnpm build

# --- Runtime stage: slim image with only production deps + built artifacts
FROM node:${NODE_VERSION}-slim AS runtime
WORKDIR /app
ENV NODE_ENV=production \
    PORT=8080
RUN corepack enable \
    && apt-get update \
    && apt-get install -y --no-install-recommends curl \
    && rm -rf /var/lib/apt/lists/*
COPY package.json ./
RUN pnpm install --prod --no-frozen-lockfile && pnpm store prune
COPY --from=build /app/dist ./dist
COPY --from=build /app/dist-server ./dist-server
COPY start.sh ./
RUN chmod +x start.sh \
    && groupadd -r -g 1001 nodejs \
    && useradd -r -u 1001 -g nodejs nodejs \
    && chown -R nodejs:nodejs /app
USER nodejs
EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=10s --start-period=10s --retries=3 \
    CMD curl -f http://localhost:8080/ || exit 1
CMD ["./start.sh"]
