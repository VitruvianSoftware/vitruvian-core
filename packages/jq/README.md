# vitruvian-jq

## What it gives you

Standard-library-only Rust crate reproducing jq 1.8 behavior for ported CLI tools without shelling out to `jq`: an order-preserving JSON `Value` and `decNumber`-accurate `Number`, streaming JSON parser with jq 1.8 parse-error messages and `<stdin>:N` line numbers, jq total ordering (`compare`, `jq_eq`, `sort`, `sort_by`, `group_by`, `unique`, `unique_by`), output formatters (`pretty`, `compact`, `raw`, `pretty_sorted`, `compact_sorted`, `tostring`, `interpolate`, `uri_encode`), jq 1.8 index/iterate error text and 30-byte truncation (`dump_trunc`), filter combinators (`one`, `each`, `or_empty`, `alt`, `first`, `any`), and stream runner exit-status rules (`5` only when a parse error occurs or the last input value errors, plus `-e`).

## When to use it

Pick `vitruvian_jq` when replacing shell `jq` invocations in Rust CLI tools that require jq 1.8 parity (key order, `decNumber` formatting, sorting/grouping semantics, error wording, or stream exit status) or must compile with plain `rustc` outside Bazel.

## When not to use it

Do not use this package for general-purpose typed JSON serialization/deserialization without jq compatibility requirements (use `serde` and `serde_json` directly), or when Python `json` parity is needed (use `//packages/pycompat`). This crate provides jq runtime primitives, not a general jq query language compiler.

## Example

```rust
use vitruvian_jq::{one, run, RunOptions};

let out = run(br#"{"status":"unlocked"}"#, RunOptions::raw(), |v| {
    one(v.index("status"))
});
assert_eq!(out.stdout_string(), "unlocked\n");
assert_eq!(out.status, 0);
```

## Depend on it

Add `//packages/jq:vitruvian_jq` to your target's `deps` in `BUILD` (or build with plain `rustc` via `packages/pycompat/vitruvian-pycompat/rustc-build.sh`), then import `vitruvian_jq`.

## Constraints

- Standard library only (zero third-party crates), because CI tools and standalone ports compile via plain `rustc` outside Bazel.
- Targets jq 1.8.2 semantics exclusively (`Cannot index <type> with string ("k")`, 30-byte truncation, `decNumber` number printing/ordering, exit status `5` only when the last input value or parser errors).
- **Deliberate exception for credential-handling tools (`Value::iterate_redacted`, `cannot_iterate_redacted`):** jq 1.8.2 prints `Cannot iterate over <kind> (<truncated value>)` (for example, `Cannot iterate over string ("postgres://user:SECRET-M...")`). Because a bare-string response from a credential endpoint can contain a username, password, token, or key, the redacted helpers emit `Cannot iterate over <kind>` without quoting the value while preserving jq's exit code (`5`) and stream behaviour. Default `Value::iterate` and `cannot_iterate` stay jq 1.8.2 faithful for non-secret tools.
