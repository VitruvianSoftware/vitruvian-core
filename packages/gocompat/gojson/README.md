# vitruvian-gojson

## What it gives you

A `serde_json`-backed Go `encoding/json` compatibility crate (matching the Go toolchain pinned in `go.mod`) providing:

- **Marshaling (`marshal`, `marshal_string`, `marshal_indent`, `marshal_indent_string`)**: HTML-safe escaping of `<`, `>`, `&`, `U+2028`, and `U+2029`, two-space `MarshalIndent(v, "", "  ")` formatting, and Go's unsupported-value errors for `NaN`, `+Inf`, and `-Inf`.
- **Streaming boundaries and UTF-8 decoding (`value_len`, `go_string`)**: Go's `json.Decoder` value-length detection (`MAX_DEPTH = 10000`, `"unexpected EOF"`, and Go's exact syntax error text) and byte-by-byte invalid UTF-8 replacement (`string(b)`).
- **Parsing and typed decoding (`parse`, `GoValue`, `Dec`, `decode_string_map`)**: iterative AST parsing preserving exact number literals, byte-by-byte invalid UTF-8 and lone surrogate replacement with `U+FFFD`, exact-then-`unicode.SimpleFold` field matching, Go backing-array slice reuse on duplicate keys, and Go's exact `json: cannot unmarshal ...` error messages.

## When to use it

- Porting Go CLI or pipeline tools that serialize manifests/logs or decode JSON configs and must match Go's `encoding/json` output and error messages byte for byte.

## When not to use it

- Standard-library-only Rust tools that cannot link `serde` / `serde_json`; use [`//packages/gocompat:vitruvian_gocompat`](../README.md) (`goexec`, `gostd`, `unicode`) instead.
- General-purpose Rust services with no Go `encoding/json` parity requirement; use `serde` and `serde_json` directly.

## Example

```rust
use vitruvian_gojson::{marshal_indent, parse, Dec};

let raw = br#"{"Schema": "bad", "name": "demo"}"#;
let v = parse(raw)?;
let (mut schema, mut name) = (0i64, String::new());
let mut d = Dec::new();
d.object(&v, "Unit", "main.Unit", &["schema", "name"], |d, key, val| match key {
    "schema" => d.int(val, &mut schema),
    _ => d.string(val, &mut name),
});
// d.finish() -> Err("json: cannot unmarshal string into Go struct field Unit.schema of type int")
let out = marshal_indent(&name)?;
```

## Depend on it

`//packages/gocompat/gojson:vitruvian_gojson`

## Constraints

- Depends on `//packages/gocompat:vitruvian_gocompat`, `@crates//:serde`, and `@crates//:serde_json` (built through Bazel, unlike `vitruvian_gocompat` which has zero third-party crate dependencies).
- Floating-point values (`f32`/`f64`) are rejected during marshaling: no current caller marshals one, and adding float support is a deliberate change to this crate. Finite floats return `vitruvian_gojson: floats are not supported (no caller needs them; add support here if one does)`; non-finite values return Go's exact messages (`json: unsupported value: NaN`, `json: unsupported value: +Inf`, `json: unsupported value: -Inf`) rather than `null`.
- Parity fixtures track the Go toolchain version pinned in `go.mod`.
