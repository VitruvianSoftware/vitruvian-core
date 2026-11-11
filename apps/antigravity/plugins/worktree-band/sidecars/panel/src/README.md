# Src

## Overview
Component package providing implementation for `apps/antigravity/plugins/worktree-band/sidecars/panel/src`.

## Interface
- `[lib.rs:fmt_size]`
- `[lib.rs:count_checks]`
- `[lib.rs:is_removable]`
- `[lib.rs:judge_cleanup]`
- `[lib.rs:total_cache_kb]`
- `[lib.rs:summarise_worktrees]`
- `[openui.rs:escape_html]`
- `[openui.rs:escape_html_str]`
- `[openui.rs:openui_literal]`
- `[openui.rs:openui_f64]`
- `[openui.rs:resolve_data_path]`
- `[openui.rs:ParsedOpenUI]`
- `[openui.rs:parse_openui_lang]`
- `[openui.rs:RenderOptions]`
- `[openui.rs:render_node_to_html]`
- `[openui.rs:render_openui_fragment]`
- `[openui.rs:compile_to_html]`
- `[openui.rs:to_openui_lang]`

## Invariants
- [lib.rs:350]: `assert!(is_removable(`
- [lib.rs:355]: `assert!(is_removable(`
- [lib.rs:360]: `assert!(!is_removable(shared[0], home, &shared));`

## Side Effects
- [openui.rs:414]: `if name == "Query" {`

## Verification
- Run: `bazel test //apps/antigravity/plugins/worktree-band/sidecars/panel/src/...`
