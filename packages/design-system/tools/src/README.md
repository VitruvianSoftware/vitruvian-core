# Src

## Overview
Component package providing implementation for `packages/design-system/tools/src`.

## Interface
- `[lib.rs:JsonValue]`
- `[lib.rs:parse_json]`
- `[lib.rs:find_pkg_dir]`
- `[lib.rs:check_no_remote_font_import]`
- `[lib.rs:check_all_font_face_urls_exist_on_disk]`
- `[lib.rs:check_color_ramps_match_between_json_css_and_ts]`
- `[lib.rs:check_fibonacci_spacing_and_zero_radius]`
- `[lib.rs:check_index_exports_complete_component_surface]`
- `[lib.rs:check_dark_light_theme_parity]`
- `[lib.rs:check_tailwind_theme_sync]`
- `[lib.rs:run_all_checks]`

## Invariants
- None

## Side Effects
- None

## Verification
- Run: `bazel test //packages/design-system/tools/src/...`
