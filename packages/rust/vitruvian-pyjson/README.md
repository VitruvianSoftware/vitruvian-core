# vitruvian-pyjson

## What it gives you

A `serde_json`-backed JSON parser and Python-compatible formatter (`Py`, `loads`, `load_file`) that reproduces CPython 3's `print(json.load(...)[...])` output—including `True`/`None`, `1e+20`, `['a', 1]`, insertion-ordered object keys, and last-wins duplicate-key resolution.

## When to use it

- Porting bash/Python tools that read `package.json` or JSON manifests with `python3 -c 'print(json.load(...))'` and require exact output parity.

## When not to use it

- Standard-library-only Rust tools that cannot link `serde` / `serde_json` or build with plain `rustc`; use [`//packages/rust/vitruvian-pycompat`](../vitruvian-pycompat/README.md) (`vitruvian_pycompat::json`) instead.
- Normal Rust services that deserialize into typed structs; use `serde` and `serde_json` directly.

## Example

From `tools/npm-trusted-publisher/src/manifest.rs:23-74`:

```rust
use crate::pyjson::{self, Py};
// …
pub fn load_dict(mf: &str) -> Result<Py, String> {
    let bytes = std::fs::read(mf).map_err(|e| os_error(&e, mf))?;
    let text =
        String::from_utf8(bytes).map_err(|e| format!("UnicodeDecodeError: {}: {}", mf, e))?;
    let d =
        pyjson::loads(&text).map_err(|e| format!("json.decoder.JSONDecodeError: {}: {}", mf, e))?;
    if !d.is_dict() {
        return Err(format!(
            "AttributeError: '{}' object has no attribute 'get'",
            type_name(&d)
        ));
    }
    Ok(d)
}
```

## Depend on it

`//packages/rust/vitruvian-pyjson:vitruvian_pyjson`

## Constraints

- Depends on `@crates//:serde` and `@crates//:serde_json` (cannot be built with plain `rustc` without Cargo/Bazel).
- Known CPython parity gaps are documented at the top of `src/lib.rs` (for example `NaN`/`Infinity` literals, integers past 64 bits, and nesting deeper than 128 levels).
