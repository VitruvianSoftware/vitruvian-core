# vitruvian-gojson

## What it gives you

A `serde_json`-backed Go `encoding/json` compatibility crate providing:

- **Marshaling (`GoFormatter`, `marshal`, `marshal_string`, `marshal_indent`, `marshal_indent_string`, `marshal_indent_with`, `marshal_raw_string`, `go_escape`)**: HTML-safe escaping of `<`, `>`, `&`, `U+2028`, and `U+2029`; Go's exact `float32`/`float64` formatting (`-0`, positional `1e-6 <= |x| < 1e21`, `+` on positive exponents); `MarshalIndent(v, prefix, indent)` with empty containers on one line; and byte-by-byte `\ufffd` escaping for invalid UTF-8 sequences.
- **Validation and streaming (`check_valid`, `value_len`)**: Go's scanner state machine (`MAX_DEPTH = 10000`) producing Go's exact syntax error strings and `json.Decoder` value-length detection.
- **Parsing and typed decoding (`parse`, `GoValue`, `Dec`, `GoSlice`, `decode_string_map`, `go_string`, `fold_eq`)**: iterative AST parsing preserving exact number literals, byte-by-byte invalid UTF-8 and lone surrogate replacement with `U+FFFD`, exact-then-`unicode.SimpleFold` field matching, backing-array slice reuse across duplicate keys, and Go's exact `json: cannot unmarshal ...` error messages.

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
let out = marshal_indent(&name);
```

## Depend on it

`//packages/gocompat/gojson:vitruvian_gojson`

## Constraints

- Depends on `//packages/gocompat:vitruvian_gocompat`, `@crates//:serde`, and `@crates//:serde_json` (built through Bazel, unlike `vitruvian_gocompat` which has zero third-party crate dependencies).
- Non-finite floats (`NaN`, `Infinity`) serialized directly through `serde_json::Serializer` follow `serde_json`'s `null` hook before reaching `GoFormatter::write_f64`/`write_f32`; Go's `json.Marshal` returns an unsupported-value error for non-finite floats.
