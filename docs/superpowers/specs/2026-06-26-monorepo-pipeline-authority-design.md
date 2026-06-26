# Monorepo as the pipeline authority (mirrors = reflections + publish endpoints)

**Status:** design / approved-shape, pending spec review
**Date:** 2026-06-26
**Follows:** the one-way Copybara migration (#76–#83) and the CI/CD hygiene sweep (#200)

## Context & goal

Each app (`devx`, `homelab`, `mcp-slack`, `nexus-agent`, `oauth-user-inspector`) is exported one-way from the monorepo to a public `VitruvianSoftware/<app>` mirror. But the **mirrors still run their own CI (build/test/lint), Dependabot, and release-please**. That:

- **Re-tests code the monorepo already builds and tests** via Bazel `//...` (devx: 74 `go_test`; homelab: 4 `go_test`; oauth-user-inspector: 2 `jest_test`; mcp-slack: 5 `ts_project`; nexus-agent: 3 `swift_library`/`macos_application` + `js_*`).
- **Reintroduces the two-writable-copies drift** the one-way migration eliminated: mirror-side automation (Dependabot, release-please) **authors source commits in the mirror**. Concrete instance found 2026-06-26: the nexus mirror's Dependabot bumped `release-please-action` v4→v5 while the monorepo source stayed v4 — the next export would have reverted it.

**Goal:** make the **monorepo the single authority** for builds, checks, tests, packaging, verification, and dependency management. Mirrors become **pure export reflections** + the **publish endpoint** for released artifacts, with the CLA gate as the only contributor-facing automation that stays.

## Principle (what Google does)

On Google's OSS mirrors the invariant is: **the mirror never authors authoritative source changes.** All source mutation — including version bumps and changelogs — originates in the source of truth and flows out one-way; the GitHub side is a reflection plus a publish endpoint. `release-please`/`Dependabot` *running in the mirror* violate this (they author commits the mirror then owns), so they move to the monorepo. **tabula already works this way** — `tabula-release.yml` runs release-please in the monorepo over `tabula/*` components — so this is extending an existing, proven pattern, not inventing one.

## End-state ownership

| Concern | Today | End state |
|---|---|---|
| Build + test (all apps) | mirror CI (redundant) **and** monorepo Bazel | **monorepo** Bazel `//...` |
| Go lint (`golangci-lint`) | mirror only | **monorepo** CI job *(NEW — the real gap)* |
| TS / JS / Swift build | mirror **and** monorepo Bazel | **monorepo** Bazel |
| Dependency updates | mirror Dependabot **and** monorepo Dependabot | **monorepo** Dependabot only |
| Version bump + changelog (release-please) | mirror | **monorepo** (per-app components, like tabula) |
| Publish artifact (GH release / Homebrew / npm / GHCR / pages) | mirror | **monorepo-driven**, targeting the mirror repo / registry |
| `go install …@vX.Y.Z` tag on the mirror | mirror (release-please) | **monorepo** release pushes the tag to the mirror |
| CLA gate on contributor PRs | mirror | **mirror** (unchanged) |

## Phase 1 — Close the coverage gaps (prerequisite, low-risk)

Must land **before** anything is stripped, so the monorepo genuinely covers what the mirrors do today.

1. **Go lint.** Add a `golangci-lint` job to the monorepo `ci.yaml` that runs `golangci-lint run` over each Go app module (`devx`, `homelab`) with `GOWORK=off`, pinned to **`v2.12.1`** (the version `devx/ci.yml` already uses — homelab is currently on `latest`, so this also fixes that drift). (`aspect_rules_lint` 2.5.2 ships no golangci-lint aspect — its aspects are eslint/ruff/clippy/ktlint/pmd/clang-tidy/ty/shellcheck — so this is a CI job, not a Bazel aspect.) Path-aware (run only when `devx/**` / `homelab/**` / shared Go files change) to keep it cheap; on `merge_group`/`push` it runs as the floor.
2. **Dependabot npm.** Add `package-ecosystem: npm` entries for `/mcp-slack` and `/nexus-agent` (and `/oauth-user-inspector` if it carries a `package.json`) to the monorepo `.github/dependabot.yml`, mirroring the existing gomod entries' grouping/labels/commit-prefix.
3. **(minor) nexus node.** No new work: Bazel already builds the nexus node bridge (`js_binary`/`js_library`), which subsumes the mirror's only unique check (`node --check`, syntax). Decision: rely on the Bazel js build; do not port `node --check`.

**Verification:** monorepo CI runs golangci-lint green over devx+homelab; Dependabot opens npm PRs for mcp-slack/nexus on the next cycle.

## Phase 2 — Move releases to the monorepo (the substantive piece)

Author version/changelog/tag in the monorepo; publish the artifact outward to the mirror/registry. Source never lands on the mirror out-of-band — only release tags/assets.

**2a. release-please in the monorepo.** Extend the tabula pattern: a monorepo workflow runs release-please with `devx`, `homelab`, `mcp-slack`, `nexus-agent` as components. The version-bump + changelog PR opens in the **monorepo**; on merge it creates a namespaced tag (e.g. `devx-vX.Y.Z`). The per-app `release-please-config.json` / `.release-please-manifest.json` move from the mirror subtrees into the monorepo's release-please config.

**2b. Publish step (monorepo → mirror / registry), per artifact type:**

- **Go (`devx`, `homelab`).** A monorepo workflow runs **GoReleaser** on the release: builds the cross-platform binaries and publishes the GitHub **Release to the MIRROR repo** (`release.github.owner/name = VitruvianSoftware/<app>`, token with mirror write). GoReleaser is given the semver from release-please; creating the `vX.Y.Z` release **creates the `vX.Y.Z` tag on the mirror** (satisfying `go install github.com/VitruvianSoftware/<app>@vX.Y.Z`) and updates the Homebrew tap formula.
- **npm (`mcp-slack`).** A monorepo workflow runs `npm publish` to the npm registry on the release (NPM token in the monorepo). The package is built by the monorepo (`ts_project`).
- **`nexus-agent`.** release-please cuts the version (stamping `macos/Sources/NexusAgent/Version.swift` via `extra-files`); the monorepo publishes the GitHub Release (binary/zip) to the nexus mirror + the Homebrew cask.
- **`devx` bridge-agent (GHCR image).** Move the docker build+push into the monorepo (Bazel `rules_oci` build + push to `ghcr.io/vitruviansoftware/devx-bridge-agent`), driven on push to main — it's a publish, not source.
- **`devx` deploy-docs (gh-pages).** Build the docs in the monorepo and deploy to the devx mirror's `gh-pages` via the App token. (Recommendation; alternative is hosting docs from the monorepo's own pages.)

**Secrets prerequisite (gates 2b):** the publish tokens currently live in the mirrors (`NPM_RELEASE_TOKEN`, `RELEASE_AUTOMATION_TOKEN`, Homebrew-tap write). They must be added as **monorepo** Actions secrets, or minted via the `vitruvian-copybara-sync` GitHub App where its scope allows. Verify each scope before cutting over.

**Loop-safety:** the publish pushes **tags/releases/artifacts** to the mirror, never **source commits** (source flows only via the copybara export). A tag/asset is not authoritative source, so no new drift is introduced.

## Phase 3 — Strip the mirrors (cleanup, after 1 + 2 per app)

Delete from each app's **monorepo subtree** (the export then removes it from the mirror):

- `ci.yml` (devx, homelab, mcp-slack) — redundant with monorepo Bazel + the Phase-1 Go lint.
- `license-check.yml` (nexus) — the monorepo has a whole-repo license-check job.
- `build.yml` (nexus) — the monorepo Bazel builds the Swift (`swift_library`/`macos_application`) and the node bridge (`js_*`).
- `release-please.yml` / `release.yml` (all) — moved to the monorepo in Phase 2.
- `dependabot.yml` (devx, homelab, mcp-slack, nexus — these live in the subtrees and export) — Dependabot now runs only in the monorepo.
- `bridge-agent.yml`, `deploy-docs.yml` (devx) — moved to the monorepo in Phase 2.

**Keep** in each subtree (still exported to the mirror): **`cla.yml`** — the CLA gate that runs on contributor PRs to the mirror before they're imported. It runs in the mirror's own trusted context with only the mirror's `GITHUB_TOKEN`, posts status/signatures, and does not author source.

**Net mirror state:** a read-only reflection of `<app>/`, plus `cla.yml`, plus release tags/assets pushed by the monorepo. No CI, no Dependabot, no source-authoring automation.

## Risks & open items

- **Secrets migration (2b)** — publish tokens must move to the monorepo; verify scopes. **Gating.**
- **Homebrew tap** — confirm GoReleaser `brews:` + tap-repo write work when GoReleaser runs from the monorepo targeting the mirror.
- **First real release per app** — the monorepo-driven release can't be fully validated until a real release is cut; do **devx first as the canary**, watch the mirror `vX.Y.Z` tag + GH release land and `go install …@vX.Y.Z` resolve before cutting the others.
- **mcp-slack release-please** already migrated to `googleapis/*@v5` (#316); reuse its config when moving it to the monorepo.

## Sequencing

`Phase 1 (gaps)` → `Phase 2a (release-please in monorepo)` → `Phase 2b (publish, devx canary first)` → `Phase 3 (strip, per app)`. Each app cuts over independently after 1 + 2a; **strip an app's mirror CI only once its monorepo-driven release is proven** by a real release.

## Testing / verification per phase

- **P1:** golangci-lint green in monorepo CI over devx+homelab; Dependabot npm PRs appear for mcp-slack/nexus.
- **P2:** per app, cut a real release → verify the mirror gets the `vX.Y.Z` tag + GH release (+ Homebrew/npm), and `go install …@vX.Y.Z` / `npm i` / `brew install` resolve.
- **P3:** per app, after a strip, confirm the mirror shows no CI/Dependabot runs and the next export is still green, while monorepo CI still builds+tests+lints the app.
