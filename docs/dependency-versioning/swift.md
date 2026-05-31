# Swift dependency versions

See [Dependency Versioning & the One Version Rule](index.md) for the concepts referenced here.

## How this repo resolves them

Swift code is built with `rules_swift`. External Swift package dependencies are resolved to a
single version per package (Swift Package Manager-style resolution, pinned into the Bazel build),
so for third-party packages this behaves as a **one-version / flat** model — one resolved version
per package across the build graph. (Apple SDK frameworks are provided by the toolchain/SDK, not
versioned as third-party packages.)

## Two apps, different versions

For a shared package graph you get one resolved version per package. Two apps requiring
incompatible versions of the same Swift package don't get separate copies — resolution settles on
one, and the other must adapt. A lagging transitive package constraint pins the resolution.

## If you truly need different versions

Swift's multi-version story is limited, so the practical answer is isolation:

- **Separate package graphs / targets** — keep the divergent app's external packages in their own
  resolved set so it doesn't share the contested package with the rest of the repo.
- Failing that, **converge** — align both apps on a version that satisfies them, which is usually
  feasible given Swift packages' relatively coarse dependency trees.

If both versions must coexist in one linked binary, there is no clean mechanism; split into
separate binaries/processes.

## Inspect / detect

```bash
# Which path pulls a package into a target?
bazel query "somepath(//app, @<swift_pkg_repo>//...)"

# Resolved external repos / versions
bazel mod graph
```
