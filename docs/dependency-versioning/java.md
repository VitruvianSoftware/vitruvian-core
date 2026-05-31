# Java dependency versions

See [Dependency Versioning & the One Version Rule](index.md) for the concepts referenced here.

## How this repo resolves them

Java artifacts come from `rules_jvm_external`'s `maven.install` in `MODULE.bazel`, pinned into a
single lock (`maven_install.json`) and exposed as the `@maven` hub:

```python
maven.install(
    artifacts = ["com.google.guava:guava:33.0.0-jre"],
    lock_file = "//:maven_install.json",
)
```

Targets depend on `@maven//:com_google_guava_guava`. This is a **flat** resolver: there is one
classpath, so each coordinate resolves to exactly one version (conflicts are settled by
`rules_jvm_external`'s version-conflict policy and frozen in the lock).

## Two apps, different versions

On a shared classpath you get one winner per coordinate. If two apps need incompatible versions
of the same artifact, conflict resolution picks one and the loser fails at **runtime** with
`NoSuchMethodError` / `ClassNotFoundException`. A lagging transitive dependency that caps a
version drags everything sharing that classpath with it.

## If you truly need different versions

- **Separate closures** — declare a second, named Maven install and point the divergent app's
  targets at it:

  ```python
  maven.install(
      name = "maven_legacy",
      artifacts = ["com.example:lib:1.0"],
      lock_file = "//:maven_legacy_install.json",
  )
  ```
  ```python
  java_binary(name = "legacy", deps = ["@maven_legacy//:com_example_lib"], ...)
  ```
  This works as long as the two versions land in **different** binaries.

- **Same classpath, both versions required** — relocate one with **shading** (a jar with its
  packages renamed) so the two no longer collide. Use `maven.artifact(..., exclusions = [...])`
  to drop a bad transitive and supply your own.

## Inspect / detect

```bash
# Report artifacts with newer versions available
bazel run @maven//:outdated

# See why/where a coordinate resolved (inspect the lock)
grep -i "<group>_<artifact>" maven_install.json
```
