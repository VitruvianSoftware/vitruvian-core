# Consistent License Headers + Checks Across All Components — Design

**Status:** approved design (2026-05-26), pending implementation plan.
**Related:** [`docs/copybara-sync.md`](../copybara-sync.md) (sync runbook §9 — standalone-CI conventions).

## Goal

Every vitruvian-core component (and the monorepo's own hand-authored files) carries an **MIT license
header**, enforced by an `addlicense` check **both** in the monorepo CI (shift-left) **and** in each
component's standalone CI. devx already has headers + a check; this brings homelab, nexus-agent, and
mcp-slack to parity and makes the policy uniform repo-wide.

## Why

Standard practice — OSS and closed-source projects carry a license. Today only devx enforces it, so a
missing header in another component is invisible until (if ever) it surfaces downstream. The
components are Copybara-synced, so source files **fan out** to the standalones: headering them in the
monorepo propagates automatically, and the per-standalone checks give each repo its own gate.

## Header policy

- **License:** MIT, copyright holder **`VitruvianSoftware`**, current year — applied with
  **`addlicense`** (so the added header matches `addlicense -check` exactly).
- **Tool version:** pin **`github.com/google/addlicense@v1.2.0`** everywhere (the monorepo
  `license-check` job, every standalone `ci.yml`, and the one-time add-mode run) so add and check
  never diverge. (devx's existing `ci.yml` uses `@latest` resolving to v1.2.0 — pin it to v1.2.0 too,
  for consistency.)

## The ignore list (critical — generated/tool-managed files MUST be ignored)

"Source + config" means **hand-authored** files. A header on a **generated/tool-managed** file gets
wiped when the tool regenerates it, which then fails the check on the next run — so those are ignored,
never headered:

- **Generated — never header (load-bearing):**
  - `**/BUILD`, `**/BUILD.bazel` — gazelle rewrites these headerless; **must** stay ignored.
  - Lockfiles: `pnpm-lock.yaml`, `**/package-lock.json`, `**/Cargo.lock`, `MODULE.bazel.lock`
    (`go.sum`/`go.work.sum` aren't a recognized extension, so addlicense skips them anyway).
  - Other generated: `**/gazelle_python.yaml`, `**/*-baseline.xml` (ktlint),
    `**/.release-please-manifest.json`.
  - Transient build/dep dirs: `bazel-*/**`, `**/node_modules/**`, `**/*.venv/**`, `.git/**`.
- **Policy ignores (devx already uses):** `**/docs/**`, `**/internal/scaffold/templates/**` (scaffold
  templates generate *other* repos — they must not carry our literal header).
- **Header everything else hand-authored:** `.go`/`.ts`/`.swift`/`.sh`/`.js`/`.mjs`/`.cjs`/`.py`/`.bzl`,
  workflow & config YAML, `MODULE.bazel`/`REPO.bazel`, `Gemfile`, `Cargo.toml`, `pyproject.toml`,
  `.rubocop.yml`, `.clippy.toml`, `catalog-info.yaml`, etc. (`addlicense` silently skips extensions it
  doesn't recognize, e.g. `copy.bara.sky`, `.toml`-vs-config nuances handled by addlicense's own table.)

## Where headers get applied

One-time, in the **monorepo**, with `addlicense` add-mode over the whole repo using the ignore list
above. Component source files are synced, so headers **fan out to the standalones** on export. devx is
already compliant (0 changes). Expected scope: ~80–90 hand-authored files (the earlier ~101 "missing"
minus the now-ignored lockfiles/baselines), concentrated in homelab (~32), nexus-agent (~18), the
monorepo-only tooling/CI (~16 `.github` + 8 `tools` + 4 `infrastructure`), and root config files.

## Where the CHECK runs (two layers)

### Layer 1 — monorepo `ci.yaml` (shift-left, whole repo)
Extend the existing `license-check` job from devx-only to the **whole monorepo**: run
`addlicense -check` from the repo root with the full ignore list (B). This catches a missing header on
the monorepo PR, before fan-out. (Keep calling addlicense by full path — `"$(go env GOPATH)/bin/addlicense"` —
since GOPATH/bin isn't on the runner PATH.)

### Layer 2 — each standalone's own CI
Each standalone self-checks (so a header gap is also caught on the standalone, matching devx today).
Standalone checks run against the **standalone's** content — which has **no Bazel `BUILD` files**, so
the `**/BUILD` ignore is dropped there; they keep the per-component ignores:

| Standalone | CI today | Change | Standalone ignore set |
|---|---|---|---|
| devx | has `addlicense -check` | pin tool to v1.2.0 | `docs/**`, `internal/scaffold/templates/**` (existing) |
| homelab | has `ci.yml` (no license step) | **add** an `addlicense -check` step/job | lockfiles; (Go — minimal) |
| mcp-slack | has `ci.yml` (no license step) | **add** an `addlicense -check` step/job | `package-lock.json`, `node_modules/**` |
| nexus-agent | **no `ci.yml`** (only release-please) | **create** a minimal `license-check.yml` | `package-lock.json`, `node_modules/**` |

The new/edited standalone CI files are authored in the **monorepo subtree** (`<comp>/.github/workflows/`)
and fan out via export. **They must themselves carry the MIT header** (they're hand-authored workflow
YAML — addlicense them too, or the monorepo check flags them).

## Fan-out + validation

Headers and the component CI edits fan out via the per-component export. Validate **per component**:
export green → **drift-check green** → the **standalone's own CI green** (the exact gate that caught
the devx dispatch-workflow header gap earlier). Roll out one component at a time to keep blast radius
small.

## Caveats / known interactions

- **gazelle `BUILD` is load-bearing in the ignore list** — never header BUILD files (regeneration
  strips it → check fails). The monorepo invariant "`bazel run //:gazelle` is a no-op on main" still
  holds (root `BUILD` has `# gazelle:exclude infrastructure`).
- The dispatch workflow `sync-to-monorepo.yaml` is **already headered** (earlier fix).
- Standalone checks must include the **standalone-only** files in their scope correctly — e.g.
  mcp-slack/nexus-agent's `package-lock.json` must be ignored (it's a lockfile and standalone-only).
- The monorepo `license-check` is whole-repo; each standalone check is scoped to its own tree. The two
  use **different** ignore lists (monorepo ignores `**/BUILD`; standalones have none).

## Out of scope

- Adding a `LICENSE` file where missing (this is about per-file *headers* + the check; a top-level
  LICENSE file is a separate, smaller follow-up if any repo lacks one).
- Changing the license itself (MIT, VitruvianSoftware — unchanged).
- Re-licensing scaffold templates (intentionally ignored).
