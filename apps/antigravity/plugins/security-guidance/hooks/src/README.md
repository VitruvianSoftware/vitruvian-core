# Src

## Overview
Component package providing implementation for `apps/antigravity/plugins/security-guidance/hooks/src`.

## Interface
- `[json.rs:Value]`
- `[json.rs:Map]`
- `[json.rs:obj]`
- `[json.rs:Error]`
- `[json.rs:parse]`
- `[json.rs:parse_object]`
- `[lib.rs:BuiltinPattern]`
- `[lib.rs:Finding]`
- `[lib.rs:SecurityStore]`
- `[lib.rs:SeverityCounts]`
- `[lib.rs:SecuritySummary]`
- `[lib.rs:has_inline_suppression]`
- `[lib.rs:scan_content_for_patterns]`
- `[lib.rs:scan_diff_for_vulnerabilities]`
- `[lib.rs:filter_suppressed_findings]`
- `[lib.rs:summarise_security_state]`
- `[lib.rs:resolve_app_dir]`
- `[lib.rs:handle_security_hook]`

## Invariants
- None

## Side Effects
- [lib.rs:362]: `let cmd_len = if line[i..].starts_with("curl") {`

## Verification
- Run: `bazel test //apps/antigravity/plugins/security-guidance/hooks/src/...`
