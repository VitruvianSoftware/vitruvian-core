# `//tools/packages-index`

Generates and drift-checks the package index table in [`packages/README.md`](../../packages/README.md) from every `catalog-info.yaml` under `packages/`.

## Usage

```sh
# Check that packages/README.md matches packages/**/catalog-info.yaml (default):
bazel run //tools/packages-index -- --check

# Regenerate the table between the marker comments in packages/README.md:
bazel run //tools/packages-index -- --write

# Run unit tests:
bazel test //tools/packages-index/...
```

Pass `--root <dir>` when running the binary outside `bazel run` (otherwise `BUILD_WORKSPACE_DIRECTORY` is used).

## How it works

- Walks `packages/` at any depth for `catalog-info.yaml` files (skipping dot-directories, `bazel-*`, `node_modules`, `testdata`, `vendor`, and `target`).
- Parses each file as multi-document YAML with `gopkg.in/yaml.v3`, keeping only documents where `kind: Component` and `spec.type: library`.
- Links each package to its `README.md` (following `backstage.io/techdocs-ref: dir:...` when it points inside `packages/` to an existing `README.md`, as in `packages/pulumi/catalog-info.yaml`, and falling back to the directory containing `catalog-info.yaml`).
- Filters `metadata.tags` to the language tags (`rust`, `swift`, `go`, `typescript`, `kotlin`, `javascript`, `python`, `cpp`), formats `vitruvian.dev/bazel-target` as inline code, sorts entries by `metadata.name`, and replaces only the content between `<!-- BEGIN GENERATED: packages index -->` and `<!-- END GENERATED -->` so the hand-written header stays untouched.

## Drift check

`//tools/conformance:check` runs `//tools/packages-index -- --root <repo> --check` in its `PKGINDEX` group, mirroring how `//tools/owners` is checked. Putting the drift check in `//tools/conformance:check` avoids maintaining a hand-edited Bazel `data` list across package boundaries (each subfolder under `packages/` has its own `BUILD` file, which `glob()` cannot cross) while gating PRs and the merge queue through the existing `Conformance Check` workflow.

## Testing and linting

```sh
bazel test //tools/packages-index/...
bazel run //tools/conformance:check
bazel run //tools/format
bazel run //tools/license:check
bazel build --config=lint --output_groups=rules_lint_human //tools/packages-index/...
```
