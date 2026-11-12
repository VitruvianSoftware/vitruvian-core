# Generate Sources

## Overview
Component package providing implementation for `apps/desktop/vitruvian-atrium/bazel/src/generate_sources`.

## Interface
- `[lib.rs:Config]`
- `[lib.rs:default_app_dir]`
- `[lib.rs:parse_args]`
- `[lib.rs:extract_feature_strings_scopes]`
- `[lib.rs:extract_factory_names_from_scope]`
- `[lib.rs:collect_factories]`
- `[lib.rs:render_localization_catalog]`
- `[lib.rs:generate]`
- `[lib.rs:run_cli]`

## Invariants
- [lib.rs:133]: `// Require `\s+``
- [lib.rs:143]: `// Require `func``
- [lib.rs:150]: `// Require `\s+``

## Side Effects
- None

## Verification
- Run: `bazel test //apps/desktop/vitruvian-atrium/bazel/src/generate_sources/...`
