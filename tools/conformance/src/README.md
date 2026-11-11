# Src

## Overview
Component package providing implementation for `tools/conformance/src`.

## Interface
- `[canonical.rs:canonical_go]`
- `[canonical.rs:canonical_node]`
- `[canonical.rs:canonical_rust]`
- `[canonical.rs:rust_version_from_module]`
- `[canonical.rs:canonical_pnpm]`
- `[canonical.rs:catalog_names]`
- `[canonical.rs:go_major]`
- `[canonical.rs:go_minor]`
- `[canonical.rs:go_patch]`
- `[canonical.rs:go_is_newer]`
- `[discover.rs:FileCache]`
- `[discover.rs:rel]`
- `[emit.rs:GLYPH_OK]`
- `[emit.rs:GLYPH_FAIL]`
- `[emit.rs:GLYPH_PIN]`
- `[emit.rs:GLYPH_WARN]`
- `[emit.rs:Colors]`
- `[emit.rs:RowBuffers]`
- `[emit.rs:print_group]`
- `[emit.rs:print_banner]`
- Subdirectory: [bin](./bin/README.md)
- Subdirectory: [checks](./checks/README.md)

## Invariants
- [discover.rs:272]: `assert!(m.matches("go.mod"));`
- [discover.rs:273]: `assert!(!m.matches("go.mod.bak"));`
- [discover.rs:274]: `assert!(!m.matches("xgo.mod"));`
- [emit.rs:373]: `assert!(!rows.is_empty());`
- [emit.rs:395]: `assert!(buf.get("nonexistent").is_empty());`
- [emit.rs:403]: `assert!(!buf.get("NODE").is_empty());`
- [registry.rs:195]: `assert!(valid_date("2026-10-25"));`
- [registry.rs:196]: `assert!(valid_date("2027-01-12"));`
- [registry.rs:197]: `assert!(valid_date("9999-09-09"));`

## Side Effects
- None

## Verification
- Run: `bazel test //tools/conformance/src/...`
