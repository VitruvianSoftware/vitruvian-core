# Src

## Overview
Component package providing implementation for `apps/antigravity/plugins/savvy-fleet/sidecars/panel/src`.

## Interface
- `[lib.rs:PHASES]`
- `[lib.rs:TierInfo]`
- `[lib.rs:TIERS]`
- `[lib.rs:SPECIALIST_DEFAULTS]`
- `[lib.rs:blank_flow]`
- `[lib.rs:normalize_text]`
- `[lib.rs:infer_tier]`
- `[lib.rs:merge_flow_progress]`
- `[lib.rs:estimate_run_cost]`
- `[lib.rs:extract_subagents_from_transcript]`
- `[lib.rs:summarise_fleet_state]`
- `[openui.rs:escape_html]`
- `[openui.rs:escape_html_str]`
- `[openui.rs:openui_literal]`
- `[openui.rs:openui_f64]`
- `[openui.rs:resolve_data_path]`
- `[openui.rs:ParsedOpenUI]`
- `[openui.rs:parse_openui_lang]`
- `[openui.rs:RenderOptions]`
- `[openui.rs:render_node_to_html]`

## Invariants
- None

## Side Effects
- [openui.rs:413]: `if name == "Query" {`

## Verification
- Run: `bazel test //apps/antigravity/plugins/savvy-fleet/sidecars/panel/src/...`
