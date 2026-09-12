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
# receives this subtree). That constraint is what dictates the `catalog:`
# handling below.

# NODE_VERSION defaults to the repo canonical (the .nvmrc major) and CI passes
# it explicitly from .nvmrc. //tools/conformance:check compares this default
# against .nvmrc's major, so it cannot silently drift.
ARG NODE_VERSION=22

# Pinned to the repo canonical (root package.json `packageManager`). This is
# NOT cosmetic: `corepack enable` alone resolves whatever pnpm is newest at
# build time, so the first build of this file fetched pnpm 11.20.0 while the
# monorepo builds everything else with 10.20.0 — a different package manager
# major than the one CI tests with, chosen by the calendar. It failed the build
# outright (pnpm 11 turns ERR_PNPM_IGNORED_BUILDS into an error), which was the
# lucky outcome; the unlucky one is a silent resolution difference between the
# image and the tree the tests ran against.
#
# //tools/conformance:check already warns about exactly this — "Dockerfile runs
# pnpm but its dir has no package.json with a packageManager pin". Pinned here
# rather than by adding `packageManager` to mcp-slack/package.json, because that
# file is the npm-published manifest and a corepack pin in it changes the
# mirror's release path.
ARG PNPM_VERSION=10.20.0

# --- Build stage: compile src/**/*.ts -> dist/ with tsc -------------------
FROM node:${NODE_VERSION}-slim AS build
ARG PNPM_VERSION
WORKDIR /app
RUN corepack enable && corepack prepare "pnpm@${PNPM_VERSION}" --activate
COPY package.json ./
COPY tsconfig.json ./
COPY src/ ./src/
# Standalone-context catalog neutralization, same mechanism and same reason as
# oauth-user-inspector/Dockerfile:51 — the Docker context is this directory
# alone, with no monorepo pnpm-workspace.yaml, so pnpm cannot resolve the
# `catalog:` protocol. Today `jest` is the only such reference and it is a
# devDependency the image never runs, so the concrete version is immaterial;
# only that the spec parses.
#
# THE GUARD IS THE POINT, not the rewrite. #1498 adds mcp-slack to
# CATALOG_EXEMPT and pins jest literally, which would make this `sed` a no-op —
# and a no-op that reads like a control is the exact failure this build has now
# hit three times (an inert PrometheusRule, an unwired imagePullPolicy, a
# `required` behind a default). So rather than leave a blind rewrite that
# silently stops mattering, fail the build if ANY catalog reference survives.
# That also covers the case the `sed` alone would miss: a named `catalog:group`
# reference, which would otherwise reach pnpm and fail with an error about the
# protocol rather than about this line.
RUN sed -i 's/"catalog:[^"]*"/"^30.4.2"/g' package.json; \
    if grep -q '"catalog:' package.json; then \
      echo "unresolved catalog: reference remains in package.json" >&2; \
      exit 1; \
    fi
RUN pnpm install --no-frozen-lockfile
RUN pnpm build

# Prune to production deps HERE, so the runtime stage can copy the tree instead
# of rebuilding it — which is what lets pnpm stay out of the runtime image
# entirely. It has to run AFTER `pnpm build`, because the compile needs the
# devDependencies this removes.
#
# `--prod` is load-bearing and not a tidiness flag: the install above resolves
# every dependency (2 prod, 8 dev), so copying that tree unpruned would move
# jest and the rest of the toolchain into the runtime layer of an
# internet-facing pod — trading a known advisory set for a larger one nothing
# has scanned.
RUN pnpm prune --prod

# --- Runtime stage: production deps + compiled output only ----------------
FROM node:${NODE_VERSION}-slim AS runtime
WORKDIR /app

# PORT is the chart's contract (deployment.yaml containerPort: 3000), defaulted
# here so the image is correct when run outside Kubernetes too. The chart still
# sets it explicitly rather than inheriting — two statements of the same number
# is deliberate: this one keeps the image self-describing, that one keeps the
# manifest readable.
ENV NODE_ENV=production \
    PORT=3000 \
    MCP_TRANSPORT=http \
    HOME=/tmp

# NO PACKAGE MANAGER IN THE RUNTIME STAGE. This stage used to run `corepack
# enable && corepack prepare pnpm@... --activate` and then `pnpm install
# --prod`, which left pnpm resident in the shipped image for the sake of one
# install. The file already refuses `curl` on exactly these grounds twelve
# lines from the entrypoint (see the HEALTHCHECK note below) — and pnpm is the
# stronger case, since it does network fetch AND executes lifecycle scripts.
#
# Measured on the image this replaced, at digest sha256:63912eee (Aegis, #1503):
# 42 of 58 npm advisory instances came from the corepack pnpm payload under
# /tmp/.cache, and 10 more from the base image's own bundled npm. Copying the
# already-pruned tree from the build stage deletes the 42 from the artifact
# rather than arguing they are unreachable — the pod's emptyDir over /tmp does
# shadow them at runtime, but every scanner and compliance report still reads
# the image.
#
# package.json comes from the build stage rather than the context because
# `"type": "module"` is what makes `node dist/index.js` resolve as ESM at all;
# dropping it with pnpm would CrashLoop on module resolution. The build stage's
# copy is already catalog-neutralized, so the sed and its guard live there once
# instead of being repeated here.
#
# ARCHITECTURE: this copy is only safe because neither stage pins
# `--platform=$BUILDPLATFORM` — both build natively per-platform under buildx,
# so node_modules is produced for the target architecture. If a future change
# pins the build stage to the build platform for speed, this COPY silently
# ships the wrong architecture's binaries and breaks the mixed-arch cluster
# this image is multi-platform for.
COPY --from=build /app/package.json ./
COPY --from=build /app/node_modules ./node_modules
COPY --from=build /app/dist ./dist

# The pod overrides USER with `runAsUser: 10001` (deploy/chart deployment.yaml),
# a UID that exists in no image layer. Everything the process reads must
# therefore be world-readable, or it CrashLoops on a MODULE_NOT_FOUND that
# reads like a build fault rather than a permission one. `a+rX` grants read on
# files and traverse on directories without making anything executable that
# was not already.
#
# USER is set to the same numeric UID so the image's own default matches the
# pod's, rather than relying on the manifest to correct it. Numeric and not a
# named user: `runAsNonRoot` is evaluated by the kubelet against a UID, and a
# name it cannot resolve fails the pod rather than the check.
RUN chmod -R a+rX /app
USER 10001:10001

# Documentation only — Kubernetes routes by containerPort, not by EXPOSE.
EXPOSE 3000

# No HEALTHCHECK: Kubernetes ignores it and drives /health through the pod's
# liveness/readiness probes instead. Adding one would mean shipping `curl` in
# the runtime layer of an internet-facing pod that holds a Slack bot token,
# which is attack surface bought for nothing.
#
# `node dist/index.js` directly, with no shell wrapper: readOnlyRootFilesystem
# is on and /tmp is the only writable path, so anything that wants to write
# beside the entrypoint fails at start.
CMD ["node", "dist/index.js"]

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
