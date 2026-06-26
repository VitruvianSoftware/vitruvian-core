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

**2b. Publish stays in the mirror, re-triggered by a monorepo-pushed tag.** Each mirror release workflow today is **two jobs**: a `release-please` job (authors the version/changelog — the drift source) and a publish job gated on `release_created`. The migration **splits** them rather than relocating the publish:

- The **`release-please` job is removed** from the mirror and recreated in the monorepo (2a).
- The **publish job stays in the mirror**, re-triggered by `on: push: tags: ['v*']` instead of `needs: release-please` / `if: release_created`. It keeps using the mirror's **existing** tokens — nothing moves. Per app, unchanged in substance: GoReleaser (devx, homelab; `RELEASE_AUTOMATION_TOKEN`), `npm publish` (mcp-slack; `NPM_RELEASE_TOKEN`), build-macos→package→DMG+release-upload+Homebrew-cask (nexus; `RELEASE_AUTOMATION_TOKEN`).
- On a monorepo release, a monorepo job uses the **`vitruvian-copybara-sync` App** to push the semver tag `vX.Y.Z` to the mirror. Because the tag is pushed with the **App token (not `GITHUB_TOKEN`)** it *triggers* the mirror's publish-on-tag run (same mechanism as today's copybara export and the Dependabot auto-merge fan-out). The tag also satisfies `go install github.com/VitruvianSoftware/<app>@vX.Y.Z` and Homebrew.
- **`devx` `bridge-agent.yml` (GHCR) and `deploy-docs.yml` (gh-pages)** are push-triggered *publishes* using the mirror's `GITHUB_TOKEN` — they don't author source, so they **stay in the mirror** unchanged.

**No secret migration:** the publish tokens stay in the mirrors where they already are; the monorepo only needs the existing sync App to push the tag. This removes the one human-gated step and is *more* aligned with how Google's mirrors run publish CI on the GitHub side.

**Loop-safety:** the monorepo pushes only a **tag** to the mirror, never a source commit (source still flows one-way via the copybara export). A tag is not authoritative source, so no new drift is introduced.

## Phase 3 — Strip the mirrors (cleanup, after 1 + 2 per app)

Delete from each app's **monorepo subtree** (the export then removes it from the mirror):

- `ci.yml` (devx, homelab, mcp-slack) — redundant with monorepo Bazel + the Phase-1 Go lint.
- `license-check.yml` (nexus) — the monorepo has a whole-repo license-check job.
- `build.yml` (nexus) — the monorepo Bazel builds the Swift (`swift_library`/`macos_application`) and the node bridge (`js_*`).
- `dependabot.yml` (devx, homelab, mcp-slack, nexus — these live in the subtrees and export) — Dependabot now runs only in the monorepo.

**Convert (not delete)** the release workflow in each subtree: drop its `release-please` job; leave the publish job, re-triggered by `on: push: tags` (2b).

**Keep** in each subtree (still exported to the mirror):
- **`cla.yml`** — the CLA gate on contributor PRs; runs in the mirror's own trusted context with only `GITHUB_TOKEN`, does not author source.
- the **publish-on-tag** release workflow (2b), and devx's **`bridge-agent.yml`** / **`deploy-docs.yml`** — all publishes, never source authors.

**Net mirror state:** a read-only reflection of `<app>/`, plus `cla.yml`, plus publish workflows that react to monorepo-pushed tags / exported commits. No redundant CI, no Dependabot, no source-authoring automation.

## Risks & open items

- **No secret migration** — publish stays in the mirror with its existing tokens; the monorepo only pushes the tag via the existing sync App. (This replaces the earlier "move secrets to the monorepo" gate.)
- **Double-release window** — for each app the cutover must be atomic: the same change that adds the app to the monorepo release-please must convert the mirror workflow to publish-on-tag, so the mirror stops opening its own release PRs. Sequence carefully; verify the mirror's old release-please no longer runs after the export lands.
- **App-token-triggers-workflow** — the monorepo's tag push MUST use the sync App token (not `GITHUB_TOKEN`), or the mirror's `on: push: tags` run won't fire. Verified mechanism (copybara export + Dependabot fan-out already rely on it).
- **First real release per app** — full E2E validates only on a real release; do **devx first as the canary**, watch the mirror `vX.Y.Z` tag + GH release land and `go install …@vX.Y.Z` resolve before cutting the others.
- **mcp-slack release-please** already migrated to `googleapis/*@v5` (#316); reuse its config when moving it to the monorepo.

## Sequencing

`Phase 1 (gaps)` → `Phase 2a (release-please in monorepo)` → `Phase 2b (publish, devx canary first)` → `Phase 3 (strip, per app)`. Each app cuts over independently after 1 + 2a; **strip an app's mirror CI only once its monorepo-driven release is proven** by a real release.

## Testing / verification per phase

- **P1:** golangci-lint green in monorepo CI over devx+homelab; Dependabot npm PRs appear for mcp-slack/nexus.
- **P2:** per app, cut a real release → verify the mirror gets the `vX.Y.Z` tag + GH release (+ Homebrew/npm), and `go install …@vX.Y.Z` / `npm i` / `brew install` resolve.
- **P3:** per app, after a strip, confirm the mirror shows no CI/Dependabot runs and the next export is still green, while monorepo CI still builds+tests+lints the app.
