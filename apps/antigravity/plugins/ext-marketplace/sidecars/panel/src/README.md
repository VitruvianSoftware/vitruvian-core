# Src

## Overview
Component package providing implementation for `apps/antigravity/plugins/ext-marketplace/sidecars/panel/src`.

## Interface
- `[lib.rs:marketplace_catalog]`
- `[lib.rs:inspect_plugin_dir_meta]`
- `[lib.rs:apply_plugin_toggle_to_config]`
- `[lib.rs:merge_installed_with_catalog]`
- `[lib.rs:summarise_marketplace]`
- `[openui.rs:OPENUI_LANG_VERSION]`
- `[openui.rs:ParsedOpenUI]`
- `[openui.rs:RenderOpts]`
- `[openui.rs:escape_html]`
- `[openui.rs:escape_html_opt]`
- `[openui.rs:resolve_data_path]`
- `[openui.rs:parse_openui_lang]`
- `[openui.rs:render_node_to_html]`
- `[openui.rs:render_openui_fragment]`
- `[openui.rs:compile_to_html]`
- `[openui.rs:openui_literal]`
- `[openui.rs:openui_str]`
- `[openui.rs:openui_f64]`
- `[openui.rs:call]`
- `[openui.rs:list]`

## Invariants
- None

## Side Effects
- None

## Verification
- Run: `bazel test //apps/antigravity/plugins/ext-marketplace/sidecars/panel/src/...`
