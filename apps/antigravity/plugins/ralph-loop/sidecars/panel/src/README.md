# Src

## Overview
Component package providing implementation for `apps/antigravity/plugins/ralph-loop/sidecars/panel/src`.

## Interface
- `[lib.rs:MIN_ITERATIONS]`
- `[lib.rs:MAX_ITERATIONS_LIMIT]`
- `[lib.rs:DEFAULT_MAX_ITERATIONS]`
- `[lib.rs:check_promise_matched]`
- `[lib.rs:create_loop_state]`
- `[lib.rs:update_loop_iteration]`
- `[lib.rs:evaluate_stop_event]`
- `[lib.rs:summarise_loops]`
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

## Invariants
- [lib.rs:311]: `assert!(check_promise_matched(`
- [lib.rs:315]: `assert!(!check_promise_matched(`
- [lib.rs:319]: `assert!(check_promise_matched("Status: SHIP_IT_NOW", "SHIP_IT_NOW"));`

## Side Effects
- None

## Verification
- Run: `bazel test //apps/antigravity/plugins/ralph-loop/sidecars/panel/src/...`
