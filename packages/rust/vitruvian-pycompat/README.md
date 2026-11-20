# vitruvian-pycompat

## What it gives you

A standard-library-only Rust crate reproducing Python 3.12 behavior where Rust's standard library differs—covering `pystr` (whitespace, decimal digits, `repr()`, float formatting, round-to-even), `json` (`json.loads` and `json.dumps` defaults), `argparse` (optionals parser with Python help/usage/errors), and `unicode_tables` (Unicode 15.0.0 character classes).

## When to use it

- Porting a Python CLI or monorepo script to Rust when output, exit codes, and edge-case parsing must stay byte-identical to the Python original under parity tests.
- Building standard-library-only Rust tools that must compile with plain `rustc` outside Bazel.

## When not to use it

- General-purpose Rust CLIs or services with no Python parity requirement; use a general-purpose CLI crate (none is in the repo yet; follow AGENTS.md's "Reuse before writing") and `serde_json` from `@crates` instead.
- Preserving JSON object key insertion order and duplicate-key overwrite semantics via `serde_json`; use [`//packages/rust/vitruvian-pyjson`](../vitruvian-pyjson/README.md) instead.

## Example

From `tools/merge-queue-stats/src/lib.rs:25-398`:

```rust
pub use vitruvian_pycompat::argparse;
// …
use argparse::{Kind, Opt, Parser};
// …
fn parser(prog: String) -> Parser {
    Parser {
        prog,
        description: Some("How is main's merge queue doing over a window of days?".into()),
        opts: vec![
            Opt::help(),
            Opt {
                strings: vec!["--since"],
                dest: "since",
                kind: Kind::Value,
                help: Some("UTC date or datetime, e.g. 2026-10-05".into()),
                required: true,
            },
            // …
        ],
    }
}
// …
    let values = match p.parse(&argv[1.min(argv.len())..], &convert) {
        Ok(v) => v,
        Err(exit) => {
            print!("{}", exit.stdout);
            eprint!("{}", exit.stderr);
            return exit.code;
        }
    };
```

## Depend on it

`//packages/rust/vitruvian-pycompat:vitruvian_pycompat`

## Constraints

- Standard library only (zero external crates), because tools using it also build with plain `rustc` outside Bazel via `rustc-build.sh` (verified by `//packages/rust/vitruvian-pycompat:rustc_build_test`).
- Before changing behavior, run the tests of every dependent tool:
  `bazel test $(bazel query 'rdeps(//..., //packages/rust/vitruvian-pycompat)' --output=label 2>/dev/null | grep _test)`
