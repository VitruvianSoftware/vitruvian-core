# Src

## Overview
Component package providing implementation for `apps/antigravity/plugins/receipts-report/sidecars/panel/src`.

## Interface
- `[lib.rs:project_from_path]`
- `[lib.rs:parse_transcript_jsonl]`
- `[lib.rs:aggregate_project_receipts]`
- `[lib.rs:detect_token_hotspots]`
- `[lib.rs:format_csv_receipt]`
- `[lib.rs:render_html_receipt]`
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
- [lib.rs:487]: `assert!(parsed["estimatedTokens"].as_i64().unwrap() > 0);`

## Side Effects
- None

## Verification
- Run: `bazel test //apps/antigravity/plugins/receipts-report/sidecars/panel/src/...`
