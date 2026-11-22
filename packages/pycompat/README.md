# pycompat

## What it gives you

Python-compatible Rust helpers for monorepo CLI tools ported from Python, split into two crates:

- [`vitruvian-pycompat/`](./vitruvian-pycompat/README.md): standard-library-only Python 3.12 helpers — `argparse`, `json`, `pystr`, `pyerr`, `http` (keeps tokens off curl's command line), and `unicode_tables`.
- [`vitruvian-pyjson/`](./vitruvian-pyjson/README.md): `serde_json`-backed JSON parser and Python-compatible formatter (`json.load` / `json.dumps` / `print(...)` semantics, preserving object key insertion order and last-wins duplicate keys).

## When to use it

- Pick `vitruvian-pycompat` when porting a Python CLI or script that needs byte-identical output/exit codes or must build with plain `rustc` outside Bazel (zero external crates).
- Pick `vitruvian-pyjson` when a Bazel-built tool parses JSON manifests and needs CPython-compatible formatting with insertion-ordered keys and duplicate-key override semantics.

## When not to use it

- General-purpose Rust CLIs or services with no Python parity requirement; deserialize into typed structs with `serde` and `serde_json` directly instead.

## Example

See the example in each crate: [vitruvian-pycompat](./vitruvian-pycompat/README.md#example) and [vitruvian-pyjson](./vitruvian-pyjson/README.md#example).

## Depend on it

- Standard-library-only helpers: `//packages/pycompat/vitruvian-pycompat:vitruvian_pycompat`
- Serde-backed Python JSON formatter: `//packages/pycompat/vitruvian-pyjson:vitruvian_pyjson`

## Constraints

- `vitruvian-pycompat` must stay standard-library-only (zero external crates) because CI workflows and `package-desktop` also build consumers with plain `rustc` via `vitruvian-pycompat/rustc-build.sh`.
- `vitruvian-pyjson` depends on `@crates//:serde` and `@crates//:serde_json` and is built through Bazel only.
