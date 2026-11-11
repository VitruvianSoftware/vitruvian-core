# Src

## Overview
Component package providing implementation for `apps/antigravity/plugins/live-context/sidecars/panel/src`.

## Interface
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
- [lib.rs:45]: `assert!(text.contains("feat/live-ctx (abc1234)"));`
- [lib.rs:46]: `assert!(text.contains("2 uncommitted files: src/index.ts, README.md"));`
- [lib.rs:47]: `assert!(text.contains("#42 Add live context"));`

## Side Effects
- None

## Verification
- Run: `bazel test //apps/antigravity/plugins/live-context/sidecars/panel/src/...`
