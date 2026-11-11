# Src

## Overview
Component package providing implementation for `apps/web/gods-eye-view/upstream/src`.

## Interface
- `[lib.rs:APP_DIR]`
- `[lib.rs:UPSTREAM_URL]`
- `[lib.rs:UPSTREAM_BRANCH]`
- `[lib.rs:KINDS]`
- `[lib.rs:SERVER_PATHS]`
- `[lib.rs:PRODUCTION_SERVER_PATHS]`
- `[lib.rs:COLUMNS]`
- `[lib.rs:HEADER_MAX_LINES]`
- `[lib.rs:ToolError]`
- `[lib.rs:split_header]`
- `[lib.rs:SplitResult]`
- `[lib.rs:split_header_owned]`
- `[lib.rs:join_header]`
- `[lib.rs:blob_id]`
- `[lib.rs:is_binary]`
- `[lib.rs:Row]`
- `[lib.rs:Changes]`
- `[lib.rs:Upstream]`
- `[lib.rs:Local]`
- `[lib.rs:app_dir]`

## Invariants
- None

## Side Effects
- [lib.rs:413]: `let mut child = cmd.spawn().map_err(|e| ToolError(format!("git spawn: {}", e)...`
- [lib.rs:436]: `pub fn new(url: &str, cache_dir: &Path, fetch: bool) -> Result<Self, ToolErro...`
- [lib.rs:444]: `if !fetch {`
- [main.rs:26]: `[--cache DIR] [--no-fetch] <command> [options]\n\`
- [main.rs:70]: `"--no-fetch" => {`

## Verification
- Run: `bazel test //apps/web/gods-eye-view/upstream/src/...`
