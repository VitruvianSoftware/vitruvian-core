# JavaScript / TypeScript dependency versions

See [Dependency Versioning & the One Version Rule](index.md) for the concepts referenced here.

## How this repo resolves them

JS/TS dependencies come from `aspect_rules_js`, which translates a single `pnpm-lock.yaml` into
the `@npm` hub:

```python
npm.npm_translate_lock(
    name = "npm",
    pnpm_lock = "//:pnpm-lock.yaml",
)
```

Projects are pnpm workspace members (listed in `pnpm-workspace.yaml`), each with its own
`package.json`. This is a **nesting** resolver: pnpm stores every version in a content-
addressable store and symlinks each project's `node_modules` to exactly the versions that
project declared.

## Declaring a version once: the catalog

`pnpm-lock.yaml` is the single *resolution* hub — one resolved version of each package recorded
for the whole workspace. But each project still *declares* its own ranges in its `package.json`,
and nothing stops the same dependency from being declared at different ranges in different
projects. That accidental drift is its own hazard: it spawns a redundant dependency-bot PR per
project, hides dependencies that are no longer used anywhere, and once let a `react` 18→19 bump
land in one project while another stayed on 18 — an unsupported pairing that only surfaced in
production.

The **catalog** is the *declaration* hub. Versions meant to be uniform across the repo are
declared once in `pnpm-workspace.yaml`, and each project references the entry instead of
repeating a range:

```yaml
# pnpm-workspace.yaml
catalog:
  jest: ^29.7.0
  '@swc/core': ^1.13.0
  '@swc/jest': ^0.2.39
```

```json
// any workspace package.json
{
  "devDependencies": {
    "jest": "catalog:",
    "@swc/core": "catalog:"
  }
}
```

A bump becomes one edit in the catalog rather than one per `package.json`, the versions cannot
silently diverge, and pnpm fails fast if a `catalog:` reference has no catalog entry. This is the
JS arm of the One Version Rule applied to *declaration* — the same role `bazel_dep`,
`[workspace.dependencies]`, `go.work`, and the single `pip` lock play in their ecosystems (see
[index.md](index.md#where-each-ecosystem-declares-its-versions)).

**What belongs in the catalog:** dependencies that should move in lockstep — shared test/build
tooling (`jest`, `@swc/*`), linters, a framework together with its types (`react` + `react-dom`
+ `@types/react`), anything where a split is a latent bug. **What doesn't:** a dependency only
one project uses (a catalog entry buys nothing), or one where divergence is *intentional* — for
that, see the next section.

**Standalone-built apps cannot use the catalog.** `catalog:` only resolves when `pnpm install`
can see the monorepo `pnpm-workspace.yaml`. A workspace that builds on its own — `oauth-user-inspector`,
whose `Dockerfile` runs `pnpm install` against just its own `package.json`, and which is also
Copybara-mirrored to a standalone repo with no monorepo root — has no catalog at build time, so a
`catalog:` reference there fails with `ERR_PNPM_CATALOG_ENTRY_NOT_FOUND_FOR_SPEC`. These workspaces
must declare concrete versions and are listed in `CATALOG_EXEMPT` in
`tools/conformance/check.sh`; for them the conformance gate inverts — a concrete version is correct
and a `catalog:` reference is the failure.

**Enforced, not just encouraged.** Like Bazel's one-version rule, the catalog is a guardrail, not
a convention you can quietly bypass. The required `conformance-check` gate
(`bazel run //tools/conformance:check`) fails the build when a cataloged dependency is declared
as a literal range in any workspace, or when a catalog entry is used by no workspace (dead
config). It also lists, as non-failing advisories, dependencies that already drift across
workspaces — your worklist for what to migrate into the catalog next.

## Two apps, different versions

This is the easy case — it just works. If `app-a/package.json` pins `lodash@4` and
`app-b/package.json` pins `lodash@5`, pnpm keeps both, and `rules_js` builds each project against
its own resolved tree. A diamond where a transitive dependency lags is also a non-event: the
laggard keeps its old version nested while the newer consumer gets the new one.

That freedom is for *intentional* divergence — and it reads better as a decision than as drift.
Make it explicit with a **named catalog** so the supported versions live in one place instead of
being inferred from scattered ranges:

```yaml
# pnpm-workspace.yaml
catalogs:
  react18:
    react: ^18.2.0
    react-dom: ^18.2.0
  react19:
    react: ^19.2.7
    react-dom: ^19.2.7
```

```json
// a legacy app, pinned on purpose
{ "dependencies": { "react": "catalog:react18", "react-dom": "catalog:react18" } }
```

Each app still gets the version it needs (pnpm nests them); the difference is that the two
supported lines are named and visible, not an accident waiting to be "fixed" by an automated bump.

The only other real failure mode is a *singleton* that must be unique across a boundary (e.g. two
copies of a framework whose objects are passed between projects). That's a design issue, not a
resolver one.

## If you truly need to force convergence

Sometimes you want the *opposite* — pin everyone to one version (a security fix, or to collapse a
duplicated singleton). Use a pnpm override at the workspace root:

```json
// package.json (workspace root)
{
  "pnpm": {
    "overrides": {
      "lodash": "4.17.21"
    }
  }
}
```

## Inspect / detect

```bash
# Who depends on a package, and which versions are installed?
pnpm why <package>

# List duplicated versions across the workspace
pnpm list --depth Infinity <package>
```
