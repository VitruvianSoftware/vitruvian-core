# dupcheck

Detects code added in a change that already exists in `packages/`, and tracks the private helper families outside shared packages. Reads exclusively from `git` objects rather than the working tree so results are reproducible.

## Usage

### Mode 1: Diff check (`--diff`)

Compare code added in `<base>...<head>` against all source files under `packages/` at `<head>`:

```sh
bazel run //tools/dupcheck -- --diff origin/main...HEAD
bazel run //tools/dupcheck -- --diff origin/main...HEAD --strict
bazel run //tools/dupcheck -- --diff origin/main...HEAD --allow 'apps/example/**'
```

- **Eligible files**: tracked source files ending in `.rs`, `.swift`, `.kt`, `.go`, `.ts`, `.tsx`, `.js`, `.mjs`, `.py`, `.sh`, excluding paths containing `third_party/`, `node_modules/`, `/testdata/`, `/generated/`, `/vendor/`, `Localizations/`, or ending in `_pb.go`, `.pb.go`, `.d.ts`.
- **Normalization**: trims whitespace per line, drops empty lines and lines shorter than 4 characters, and drops lines starting with `//`, `#`, `*`, `/*`, `import `, `use `, `package `, `}`, `{`, `)`, or `@`, while preserving original 1-based line numbers.
- **Matching**: hashes every 12-consecutive-meaningful-line block across `packages/` at `<head>`, then flags blocks in changed files outside `packages/` where **all 12** meaningful lines in the block were added in `<base>...<head>` (so small edits next to or inside an existing copy are not flagged). Overlapping and adjacent matching blocks are merged into one finding per `(file, package)` pair, listing every matched package file (comma-separated) and pointing to `vitruvian.dev/bazel-target` from the package's `catalog-info.yaml` (or the package path if absent).
- **Known limit**: a copy split across two separate files under `packages/` is not reported, because each 12-meaningful-line window must reside within a single package file.
- **Exit status**: exits `0` by default (warning mode). With `--strict`, exits `1` when findings are present.

### Mode 2: Helper families tracker (`--families`)

Reproduces the shared-package rollout table across the 10 tracked Rust helper families (`json`, `argparse`, `unicode_tables`, `pystr`, `http`, `jq`, `pyjson`, `pyerr`, `gostd`, `goexec`):

```sh
bazel run //tools/dupcheck -- --families
bazel run //tools/dupcheck -- --families --ref aaf841f83379bf1f75d7b12b39e897441e3336ac
```

Default `--ref` is `origin/main`. Excludes shared helper package copies (`packages/rust/`, `packages/pycompat/`, `packages/jq/`, `packages/gocompat/`) and one-line `pub use vitruvian_*` re-exports, cuts each file at the first top-level `#[cfg(test)]`, and prints a Markdown table of copies, code lines, and lines shared across at least two copies.

## Allow list

Deliberate copies that should stay ignored in `--diff` mode live in `tools/dupcheck/allow.txt` (one glob pattern per line, `#` comments). `tools/dupcheck/allow.txt` is read exclusively from `<head>` in git (never from the working tree); if it is absent at `<head>`, no file-based allow list is applied. Additional globs can be passed per invocation with repeatable `--allow <path-glob>` flags. Allowed paths are excluded both as changed candidate files and from the `packages/` reference index. Segment wildcards `*` match within a single path component and `**` matches zero or more path segments.

## Running in CI

CI checkout must fetch full git history (`fetch-depth: 0`) so `git` can compute the merge-base for `<base>...<head>` ranges and resolve historical tree objects.

## Testing and linting

```sh
bazel test //tools/dupcheck/...
bazel run //tools/format
bazel run //tools/license:check
bazel build --config=lint --output_groups=+rules_lint_human //tools/dupcheck/...
```
