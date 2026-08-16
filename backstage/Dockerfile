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

RUN apt-get update && apt-get install -y --no-install-recommends     curl     python3     && rm -rf /var/lib/apt/lists/*

WORKDIR /app

ENV NODE_ENV=production     PORT=7007

RUN corepack enable && corepack prepare pnpm@10.20.0 --activate

COPY --from=build /app/pnpm-lock.yaml /app/package.json /app/pnpm-workspace.yaml ./
COPY --from=build /app/backstage/packages/backend/package.json ./backstage/packages/backend/
COPY --from=build /app/backstage/packages/app/package.json ./backstage/packages/app/

RUN pnpm install --prod --frozen-lockfile

COPY --from=build /app/backstage/packages/backend/dist/bundle.tar.gz ./
RUN tar xzf bundle.tar.gz && rm bundle.tar.gz

COPY --from=build /app/backstage/app-config.yaml ./app-config.yaml

RUN groupadd -r -g 1001 nodejs && useradd -r -u 1001 -g nodejs nodejs
RUN chown -R nodejs:nodejs /app
USER nodejs

EXPOSE 7007
CMD ["node", "packages/backend/dist/index.cjs", "--config", "app-config.yaml"]
