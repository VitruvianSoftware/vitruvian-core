# Rust dependency versions

See [Dependency Versioning & the One Version Rule](index.md) for the concepts referenced here.

## How this repo resolves them

Rust crates are managed by `rules_rust`'s crate-universe, generated from the Cargo workspace
(`Cargo.toml` / `Cargo.lock`):

```python
crate.from_cargo(
    name = "crates",
    cargo_lockfile = "//:Cargo.lock",
    manifests = ["//:Cargo.toml"],
)
```

Cargo is a **nesting** resolver: it unifies within a semver-compatible range but allows multiple
*semver-incompatible* versions of a crate to be built into the same graph, with symbols mangled
per version.

## Two apps, different versions

Mostly a non-event. If one crate needs `rand@0.7` and another needs `rand@0.8`, Cargo resolves
and compiles both side by side. A lagging transitive dependency keeps its older major while a
newer consumer gets the newer one — no conflict.

The one gotcha is **type identity**: a `Foo` from `rand@0.7` is a *different type* from a `Foo`
in `rand@0.8`. If a value crosses an API boundary between code compiled against different
versions you'll get a "mismatched types" error that looks impossible until you spot the duplicate
crate. `cargo tree -d` is how you spot it.

## If you truly need to pin or redirect

Use a Cargo `[patch]` to force a single source/version (a fix, a fork, or to collapse a
duplicate):

```toml
# Cargo.toml
[patch.crates-io]
rand = { git = "https://github.com/rust-random/rand", tag = "0.8.5" }
```

Then refresh the lock and re-pin the crate-universe repo.

## Inspect / detect

```bash
# Show duplicated (multiple-version) crates in the graph
cargo tree -d

# Why is a crate present, and via whom?
cargo tree -i <crate>
```
