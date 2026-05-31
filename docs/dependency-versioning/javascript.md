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

## Two apps, different versions

This is the easy case — it just works. If `app-a/package.json` pins `lodash@4` and
`app-b/package.json` pins `lodash@5`, pnpm keeps both, and `rules_js` builds each project against
its own resolved tree. A diamond where a transitive dependency lags is also a non-event: the
laggard keeps its old version nested while the newer consumer gets the new one.

The only real failure mode is a *singleton* that must be unique across a boundary (e.g. two
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
