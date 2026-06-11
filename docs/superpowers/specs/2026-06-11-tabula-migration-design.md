# Tabula → vitruvian-core migration design

**Date:** 2026-06-11
**Status:** Approved
**Source:** `BlueCentre/tabula` @ `main` (post PR #43, concurrency-hardened)
**Target:** `vitruvian-core/tabula/` (this repo)

## Goals & constraints

- Migrate the Tabula standalone npm-workspaces monorepo (shared, api, extension, web, cli)
  into vitruvian-core **without git history**.
- **Native Bazel**: every build/test is a Bazel target; no toolchain island. The standard is
  "how Google builds in their monorepo" — no shortcuts, no stopgaps.
- CI/CD remains fully functional in the new home.
- release-please continues, with all artifacts **namespaced `tabula-*`** to avoid collisions.
- Deployment rebuilt in this repo's idiom: Bazel `oci_image` + Pulumi (not buildpacks/Terraform).

## Verified facts the design rests on

1. **Prisma engine-free is GA** on the 6.19 line (`prisma-client` generator + `engineType =
   "client"` + `@prisma/adapter-pg`). Verified empirically offline: generate emits plain TS,
   runtime queries need no Rust engine. Only `prisma migrate deploy` still executes the native
   schema-engine — vendored via `http_file` pinned to the `@prisma/engines-version` hash.
2. **Hermetic DBs**: `rules_itest` (BCR 0.0.56) + real Postgres binaries
   (`theseus-rs/postgresql-binaries`, musl, via `http_archive`) + BCR `redis` module
   (source-built `redis-server`). Loopback networking works on BuildBuddy RBE
   (`network: off` still permits localhost), so API integration tests run on the remote sweep.
3. **Playwright MV3 E2E runs headless**: `channel: 'chromium'` (full Chromium, new headless)
   supports `--load-extension` since Playwright 1.49. xvfb and headed mode are deleted, not
   ported. Browsers pinned hermetically via `rules_playwright` (BCR 0.5.3) with a vendored
   `browsers.json` + integrity map.
4. **Next 16 must build with `--webpack` under Bazel**: Turbopack (default) rejects rules_js's
   symlinked package store (vercel/next.js#91896, rules_js#2739 — open). The official
   `@aspect_rules_js//contrib/nextjs` macros handle the webpack pipeline; App Router support
   requires aspect_rules_js ≥ 3.2.x.
5. **release-please supports subdir config**: `config-file`/`manifest-file` action inputs take
   repo-relative paths; package paths in the config are always repo-root-relative; tag format
   `<component>-v<version>`. Host tags (`devx-v*`, weekly `YYYY.WW`) provably cannot collide.

## Section A — Placement & build mapping

```
vitruvian-core/
  tabula/
    BUILD                          # subtree gazelle directives (ignore/exclude)
    package.json                   # private meta pkg "tabula" (release-please anchor)
    release-please-config.json
    .release-please-manifest.json
    shared/   api/   extension/   web/   cli/
  tools/oci/node_image.bzl         # NEW — sibling of go_image/py3_image
  infrastructure/pulumi/tabula/    # NEW — Cloud Run + AR + secrets + SA (Go)
```

- **npm → pnpm**: `package-lock.json` removed; deps fold into root `pnpm-lock.yaml`;
  `@tabula/shared` referenced as `workspace:*`; `tabula/{shared,api,extension,web,cli}` join
  `pnpm-workspace.yaml`. Node 18/20 → host 22.21.1 (`.nvmrc`).
- **Per-package Bazel targets** (hand-authored BUILD files following the `mcp-slack` pattern:
  per-package `npm_link_all_packages`, co-located tsconfig, `# gazelle:ignore`):

| Package | Build | Test |
|---|---|---|
| shared | `ts_project` (declarations) | — |
| api | prisma-generate `js_run_binary` → `ts_project` → `js_binary` → `node_image` | `jest_test` (node) small + `service_test` integration medium |
| extension | `js_run_binary` running webpack-cli (existing config, `out_dirs=["dist"]`) | `jest_test` (jsdom) small + Playwright `service_test` enormous/e2e |
| web | `nextjs_build` with `args=["--webpack"]`, `NEXT_TELEMETRY_DISABLED=1` | `jest_test` via `next/jest` (jsdom) |
| cli | `ts_project` + `js_binary` (`tabcli`) | `jest_test` if tests exist |

- `aspect_rules_webpack` deliberately **not** used (release lag vs rules_js 3.x;
  `webpack_bundle` is implemented as `js_run_binary` anyway).

### Code changes forced by the no-stopgap bar

- **Prisma engine-free conversion**: schema generator block becomes
  `provider = "prisma-client"`, `engineType = "client"`, `moduleFormat = "cjs"`,
  `output = "../src/generated/prisma"`. `api/src/lib/prisma.ts` instantiates
  `new PrismaClient({ adapter: new PrismaPg({ connectionString }) })`. All imports of Prisma
  types move from `@prisma/client` to the generated client. Generated code is **built, never
  checked in**. `npm_translate_lock` gets
  `lifecycle_hooks_exclude = ["@prisma/client", "@prisma/engines"]`.
- **TS path aliases rewritten to relative imports in `api` and `cli`** — tsc doesn't rewrite
  `paths`, so compiled output only worked via ts-jest/tsx loaders; latent runtime bug.
  `extension`/`web` keep aliases (webpack/Next resolve them for real).
- **MIT license headers** (`addlicense -c "VitruvianSoftware" -l mit`) prepended to all Tabula
  sources (one-time scripted pass) to satisfy the `license-check` CI job.
- **Lint/format adoption**: Tabula's airbnb `.eslintrc.js`, `.prettierrc.js`, husky, and
  lint-staged are deleted. Root flat `eslint.config.mjs` + `prettier.config.cjs` +
  `//tools/format` + repo githooks apply. Resulting format diff and lint debt fixed in-place.
- **tabcli reconciliation**: `dev check/test/lint/build` retired (→ `bazel test`/`coverage`);
  `infra *` (Terraform) retired (→ Pulumi program); `github secrets sync` retired (→ host
  repo_config). Survivors: `auth`, `workos`, `db`, `config`.

## Section B — Hermetic test architecture

Three tiers, all `bazel test` targets:

1. **Unit (`size = "small"`)** — `aspect_rules_jest` `jest_test` per package. Pre-transpiled
   via `ts_project` where practical (Aspect's recommendation; ts-jest is a per-action recompile
   trap); `next/jest` transformer for web. jsdom for extension/web. Runs on the RBE `//...`
   sweep.
2. **API integration (`size = "medium"`)** — `rules_itest` `service_test`: hermetic Postgres 16
   (`initdb`+`postgres` in `$TEST_TMPDIR`, `autoassign_port`, `pg_isready` health check) +
   hermetic `redis-server` + `itest_task` running `prisma migrate deploy` with the vendored
   schema-engine → jest integration suite. Runs on the RBE sweep (loopback allowed).
3. **Extension E2E (`size = "enormous"`, `tags = ["e2e", "no-remote-exec"]`)** — same services
   plus the Fastify `js_binary` as a health-checked `itest_service` (`/health`), seeded via
   `itest_task`; `rules_playwright`-pinned `@playwright//:chromium`;
   `launchPersistentContext` with `channel: 'chromium'` (headless) + `--no-sandbox` +
   `--load-extension=$(rootpath //tabula/extension:dist)`. Playwright `webServer`, xvfb, and
   manual API boot are deleted — Bazel owns orchestration. Ports read from `ASSIGNED_PORTS`.
   Sharding via `shard_count` + `TEST_SHARD_INDEX`; `workers` pinned explicitly.

- E2E env table from the old `extension-e2e.yml` (dummy WorkOS keys, `RATE_LIMIT_MAX=100000`,
  JWT secrets) moves into the `itest_service` definitions.
- **Coverage**: jest `coverageThreshold`s (api 85/85/85/70, extension 80/80/79/65) preserved and
  enforced under `bazel coverage //tabula/...`. The old tabcli pre-push 80%-branch gate retires
  with tabcli; per-package jest thresholds are the single source of truth.
- **Deviation from brainstorm**: no PGlite fake data layer. PGlite is single-connection (breaks
  Fastify-under-load tests; no `migrate deploy` on Prisma 6) while hermetic real Postgres boots
  in seconds in-sandbox with full fidelity. Revisit only if test latency hurts.

## Section C — CI/CD, release, deploy

### CI

- Tabula's `ci.yml`, `api-e2e.yml`, `extension-e2e.yml`, `dev-build.yml`, `docs.yml` are
  **deleted**. Units/integration/builds ride the existing `bazel build`+`test //...` RBE sweep;
  `license-check` and `tidy-check` apply automatically.
- `.bazelrc`: `test --test_tag_filters=-e2e` (default skip) and a `test:e2e` config that runs
  only e2e-tagged targets.
- New `.github/workflows/tabula-e2e.yaml`: ubuntu runner, install Chromium system libs,
  `bazel test --config=e2e //tabula/...` + `bazel coverage //tabula/...`. Path-filtered to
  `tabula/**` + the workflow itself.
- Dropped (host has no equivalent): codecov uploads, PR coverage-comment bot, gh-pages docs
  deploy. Tabula docs move to `docs/tabula/**`.

### Release

- `tabula/release-please-config.json` + `tabula/.release-please-manifest.json`. Packages keyed
  by repo-root-relative paths (`tabula`, `tabula/api`, …) with components `tabula`,
  `tabula-api`, `tabula-extension`, `tabula-cli`, `tabula-web` → tags `tabula-v*`,
  `tabula-api-v*`, etc. Plugins: `node-workspace` with `"merge": false` **before**
  `linked-versions` (lockstep group of all five). `release-search-depth: 5` removed (default
  400). `bootstrap-sha` set to the import commit for the first cycle, then removed.
- New `.github/workflows/tabula-release.yml`: `on: push: branches [main], paths ['tabula/**']`;
  `googleapis/release-please-action@v5` with subdir `config-file`/`manifest-file`;
  `permissions: contents: write, pull-requests: write`. Downstream job: on
  `tabula-extension--release_created`, `bazel build //tabula/extension:chrome_zip` and attach
  to the GitHub release. Known gotcha: if `main` gains required status checks, the release PR
  needs a PAT/App token.

### Deploy

- `tools/oci/node_image.bzl`: `js_image_layer` → `oci_image` on a new
  `gcr.io/distroless/nodejs22-debian12` `oci.pull` base (engine-free Prisma ⇒ no OpenSSL/zlib
  concerns). First `oci_push` target in the repo → Artifact Registry.
- `infrastructure/pulumi/tabula/` (Go, `pulumi_project` macro, registered in
  `infrastructure/gcp-identities.tsv`): Cloud Run service `tabula-api-stg`, Artifact Registry
  repo, Secret Manager secrets (DATABASE_URL, JWT_SECRET, WORKOS_*, UPSTASH_REDIS_URL),
  service account + IAM (public invoker). **Neon + Upstash stay externally provisioned**
  (conn strings in Secret Manager) — matching the host's GCP-only Pulumi posture. The old
  Terraform tree is not imported; its purpose is documented in the runbook.
- New `.github/workflows/tabula-deploy-staging.yaml`: WIF auth →
  `bazel run //tabula/api:image_push` (sha-tagged) → `prisma migrate deploy` (vendored
  schema-engine, staging DATABASE_URL) → `pulumi up` with new image digest. Ordering preserves
  migrate-before-traffic.

## Section D — Sequencing & risks

Phases, each landing green:

1. Host toolchain prep: `aspect_rules_js` 3.0.1→3.2.1; add `aspect_rules_jest`, `rules_itest`,
   `rules_playwright`, `redis`, postgres `http_archive`s, prisma schema-engine `http_file`,
   nodejs22 base image; `.bazelrc` e2e config; `node_image.bzl`. Existing components
   (mcp-slack, nexus-agent, Go/Python) must stay green.
2. Code import + pnpm fold-in + licenses + lint/format adoption + Prisma conversion + alias
   rewrite + BUILD files → `bazel build //tabula/...` green, `//:tidy` clean.
3. Unit tests green.
4. Integration + E2E green (locally via `--config=e2e`).
5. release-please config + workflows.
6. Pulumi + image + deploy workflow.
7. Full verification, PR, then retire `BlueCentre/tabula` (archive; explicit confirmation).

**Risks**: rules_js 3.x bump ripple on existing components (phase 1 isolated for this);
Next-16-under-Bazel fragility (mitigated: `--webpack`, official macro, build/test only);
small-maintainer rulesets `rules_playwright`/`rules_itest` (thin, forkable); Chromium host
system libs are the one non-hermetic layer (documented apt set on the e2e runner; screenshot
tests not byte-reproducible across hosts).
