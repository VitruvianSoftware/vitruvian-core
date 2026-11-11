# Src

## Overview
Component package providing implementation for `apps/antigravity/plugins/hookify/hooks/src`.

## Interface
- `[json.rs:Value]`
- `[json.rs:Map]`
- `[json.rs:obj]`
- `[json.rs:Error]`
- `[json.rs:parse]`
- `[json.rs:parse_object]`
- `[lib.rs:SUPPORTED_OPERATORS]`
- `[lib.rs:SUPPORTED_ACTIONS]`
- `[lib.rs:ALLOW]`
- `[lib.rs:parse_hookify_markdown]`
- `[lib.rs:serialize_hookify_markdown]`
- `[lib.rs:extract_field_from_payload]`
- `[lib.rs:evaluate_condition]`
- `[lib.rs:evaluate_condition_checked]`
- `[lib.rs:RuleEvalResult]`
- `[lib.rs:evaluate_rule]`
- `[lib.rs:PreToolEvalSummary]`
- `[lib.rs:evaluate_pre_tool_use]`
- `[lib.rs:StopEvalSummary]`
- `[lib.rs:evaluate_stop]`

## Invariants
- None

## Side Effects
- [main.rs:21]: `.spawn(move || handle_hookify_payload(&payload, app_dir.as_deref()))`

## Verification
- Run: `bazel test //apps/antigravity/plugins/hookify/hooks/src/...`
