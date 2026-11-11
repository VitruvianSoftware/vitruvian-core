# Src

## Overview
Component package providing implementation for `apps/antigravity/plugins/hookify/sidecars/panel/src`.

## Interface
- `[lib.rs:summarise_hookify_state]`
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
- `[openui.rs:openui_str]`
- `[openui.rs:call]`
- `[openui.rs:list]`
- `[openui.rs:to_openui_lang]`

## Invariants
- [lib.rs:155]: `assert!(blocked.reason.contains("--force-with-lease"));`
- [lib.rs:182]: `assert!(!res.continue_flag);`
- [lib.rs:183]: `assert!(res.stop_reason.contains("Commit your work"));`

## Side Effects
- None

## Verification
- Run: `bazel test //apps/antigravity/plugins/hookify/sidecars/panel/src/...`
