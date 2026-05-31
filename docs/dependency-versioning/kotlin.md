# Kotlin dependency versions

See [Dependency Versioning & the One Version Rule](index.md) for the concepts referenced here.

## How this repo resolves them

Kotlin is compiled by `rules_kotlin`, but its third-party JVM dependencies come from the same
`rules_jvm_external` `@maven` hub as the rest of the JVM code, pinned in `maven_install.json`:

```python
kt_jvm_library(
    name = "app",
    srcs = ["App.kt"],
    deps = ["@maven//:com_squareup_okhttp3_okhttp"],
)
```

This is a **flat** resolver: one classpath, one version per coordinate. (Note the Kotlin stdlib
version itself is governed by the `rules_kotlin` toolchain, not Maven.)

## Two apps, different versions

Same as any JVM language: a shared classpath has one winner per coordinate, so incompatible
requirements resolve to one version and the loser fails at runtime
(`NoSuchMethodError`). A lagging transitive dependency pins everyone on that classpath.

## If you truly need different versions

- **Separate closures** — declare a named Maven install and point the divergent target at it:

  ```python
  maven.install(
      name = "maven_legacy",
      artifacts = ["com.squareup.okhttp3:okhttp:3.14.9"],
      lock_file = "//:maven_legacy_install.json",
  )
  ```
  ```python
  kt_jvm_library(name = "legacy", deps = ["@maven_legacy//:com_squareup_okhttp3_okhttp"], ...)
  ```
  Valid as long as the two versions stay in **different** binaries.

- **Same classpath, both required** — relocate one via **shading**, or use
  `maven.artifact(..., exclusions = [...])` to drop a problematic transitive and supply your own.

## Inspect / detect

```bash
bazel run @maven//:outdated
grep -i "<group>_<artifact>" maven_install.json
```
