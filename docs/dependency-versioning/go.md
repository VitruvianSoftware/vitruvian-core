# Go dependency versions

See [Dependency Versioning & the One Version Rule](index.md) for the concepts referenced here.

## How this repo resolves them

Go dependencies are managed by `rules_go` + Gazelle's `go_deps` extension, fed from the
workspace's `go.work` (and the member `go.mod` files):

```python
go_deps.from_file(go_work = "//:go.work")
```

Go uses **Minimal Version Selection (MVS)**: across every module in `go.work`, for each import
path it selects the *single highest* version anyone requires. So this is effectively a **flat**
resolver within a major version — `go.mod` expresses only minimums, never upper bounds.

## Two apps, different versions

Within one major version you don't get two versions — MVS picks the highest and **everyone is
upgraded to it**, whether or not they asked. If that upgrade is incompatible with one module,
that module breaks (at compile or at runtime). There's deliberately no "max version" knob to
create a deadlock; the trade-off is "highest wins, assume compatibility."

Across **major** versions Go is nesting: `example.com/x` and `example.com/x/v2` are different
import paths, so a v1 consumer and a v2 consumer coexist — provided the library follows semantic
import versioning.

## If you truly need different versions

Two options, depending on the situation:

- **Pin/redirect with `replace`** in `go.mod` when you need a specific build (a fork, or to hold
  a version) — MVS still takes the highest of what's left, so this is for redirection, not for
  running two versions at once.
- **Isolate the app into its own module** kept *out* of `go.work` (this repo already does this
  for the infrastructure Pulumi modules). It then resolves its own `go.mod` independently. The
  cost: an out-of-`go.work` module is no longer part of the shared Gazelle/Bazel graph, so it's
  driven by `go`/its own tooling rather than the monorepo build.

## Inspect / detect

```bash
# Why is this module in the graph, and who requires it?
go mod why -m <module-path>

# Full requirement graph (grep for the contested module)
go mod graph | grep <module-path>
```
