# C / C++ dependency versions

See [Dependency Versioning & the One Version Rule](index.md) for the concepts referenced here.

## How this repo resolves them

C/C++ has no package-manager resolver. Each external library is a **separate Bazel repo**,
declared either from the Bazel Central Registry via `bazel_dep` or pinned directly with
`http_archive` in `MODULE.bazel`:

```python
bazel_dep(name = "abseil-cpp", version = "20240116.0")
```

The "version" is simply whatever you declare. bzlmod performs module resolution across
`bazel_dep`s (single version per module name), and `http_archive` repos are whatever URL/commit
you pin.

## Two apps, different versions

You *can* technically have two versions as two distinct repos (e.g. a second `http_archive`
named `foo_v2`). The hard limit is **linking**: pull both into the same `cc_binary` and you get
**One Definition Rule violations** — duplicate symbols at link time, or undefined behavior if
they slip through. So in practice it's one version per linked binary.

Across separate binaries, two versions in two repos is fine.

## If you truly need different versions

- **Separate binaries** — depend on the distinct repos from distinct `cc_binary` targets; never
  in the same link unit.
- **Same binary, both required** — there's no clean answer: build one as a shared library with
  hidden/versioned symbols, or vendor and rename one library's symbols. Usually it's cheaper to
  converge on a single version.

## Inspect / detect

```bash
# Which path pulls a library into a target?
bazel query "somepath(//app:bin, @abseil-cpp//...)"

# All external repos and their resolved versions
bazel mod graph
```
