# Src

## Overview
Component package providing implementation for `apps/antigravity/plugins/live-context/hooks/src`.

## Interface
- `[json.rs:Value]`
- `[json.rs:Map]`
- `[json.rs:obj]`
- `[json.rs:Error]`
- `[json.rs:parse]`
- `[json.rs:parse_object]`
- `[lib.rs:DEFAULT_RESPONSE_CONTRACT]`
- `[lib.rs:DEFAULT_REPO]`
- `[lib.rs:SNAPSHOT_MAX_AGE_MS]`
- `[lib.rs:GITHUB_UNKNOWN]`
- `[lib.rs:GIT_UNKNOWN]`
- `[lib.rs:resolve_state_dir]`
- `[lib.rs:format_live_git_summary]`
- `[lib.rs:build_ephemeral_context_payload]`
- `[lib.rs:Runner]`
- `[lib.rs:run_command]`
- `[lib.rs:probe_git]`
- `[lib.rs:probe_github]`
- `[lib.rs:snapshot_updated_ms]`
- `[lib.rs:snapshot_is_fresh]`
- Subdirectory: [bin](./bin/README.md)

## Invariants
- None

## Side Effects
- [lib.rs:41]: `pub const GITHUB_UNKNOWN: &str = "GitHub state unavailable this turn (gh quer...`
- [lib.rs:286]: `"LIVE {repo} state, fetched just now — this SUPERSEDES any PR/issue status st...`
- [lib.rs:377]: `let mut child = cmd.spawn().ok()?;`

## Verification
- Run: `bazel test //apps/antigravity/plugins/live-context/hooks/src/...`
