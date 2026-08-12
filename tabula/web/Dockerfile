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
# Stage 1: Install dependencies
FROM node:22-alpine AS deps
WORKDIR /app
RUN corepack enable

# Copy workspace config and lockfile
COPY package.json pnpm-workspace.yaml pnpm-lock.yaml ./
# Copy package.json files for all relevant workspaces
COPY tabula/web/package.json tabula/web/package.json
COPY tabula/shared/package.json tabula/shared/package.json
COPY packages/design-system/package.json packages/design-system/package.json

# Install only production + build deps for the web workspace
RUN pnpm install --frozen-lockfile

# Stage 2: Build
FROM node:22-alpine AS builder
WORKDIR /app
RUN corepack enable

COPY --from=deps /app/node_modules ./node_modules
COPY --from=deps /app/tabula/web/node_modules ./tabula/web/node_modules
COPY --from=deps /app/tabula/shared/node_modules ./tabula/shared/node_modules
COPY --from=deps /app/packages/design-system/node_modules ./packages/design-system/node_modules

# Copy source for all needed workspaces
COPY tabula/shared/ tabula/shared/
COPY packages/design-system/ packages/design-system/
COPY tabula/web/ tabula/web/
COPY package.json pnpm-workspace.yaml ./

# Build-time env var (baked into the JS bundle by Next.js)
ARG NEXT_PUBLIC_API_URL
ENV NEXT_PUBLIC_API_URL=$NEXT_PUBLIC_API_URL

WORKDIR /app/tabula/web
RUN npx next build

# Stage 3: Production runner
FROM node:22-alpine AS runner
WORKDIR /app

ENV NODE_ENV=production
ENV PORT=8080
ENV HOSTNAME=0.0.0.0

# Copy standalone output
COPY --from=builder /app/tabula/web/.next/standalone ./
COPY --from=builder /app/tabula/web/.next/static ./tabula/web/.next/static
COPY --from=builder /app/tabula/web/public ./tabula/web/public

EXPOSE 8080

# The standalone output creates server.js at the workspace root within the standalone dir
# Next.js standalone mode preserves the monorepo directory structure
CMD ["node", "tabula/web/server.js"]
