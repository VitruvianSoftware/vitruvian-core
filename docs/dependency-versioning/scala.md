# Scala dependency versions

See [Dependency Versioning & the One Version Rule](index.md) for the concepts referenced here.

## How this repo resolves them

Scala is compiled by `rules_scala`, with third-party JVM dependencies coming from the
`rules_jvm_external` `@maven` hub (pinned in `maven_install.json`), like the rest of the JVM
code. This is a **flat** resolver: one classpath, one version per coordinate.

Scala adds a wrinkle: library artifacts are **cross-built per Scala binary version**, so the
binary version is baked into the coordinate (e.g. `org.typelevel:cats-core_2.13` vs
`..._3`). "Same library, different version" therefore includes "same library, wrong Scala
binary version" — every Scala dependency must match the toolchain's Scala version.

## Two apps, different versions

A shared classpath yields one winner per coordinate; incompatible requirements resolve to one
and the loser fails at runtime. Additionally, mixing artifacts built for different Scala binary
versions on one classpath is its own breakage — keep the `_2.13`/`_3` suffix consistent with the
configured toolchain.

## If you truly need different versions

- **Separate closures** — a named Maven install for the divergent target:

  ```python
  maven.install(
      name = "maven_legacy",
      artifacts = ["org.typelevel:cats-core_2.13:2.9.0"],
      lock_file = "//:maven_legacy_install.json",
  )
  ```
  ```python
  scala_library(name = "legacy", deps = ["@maven_legacy//:org_typelevel_cats_core_2_13"], ...)
  ```
  Valid only across **separate** binaries.

- **Same classpath, both required** — relocate one via **shading**, or use
  `maven.artifact(..., exclusions = [...])` to drop a bad transitive.

## Inspect / detect

```bash
bazel run @maven//:outdated
grep -i "<group>_<artifact>" maven_install.json   # watch the _2.13 / _3 suffix
```
