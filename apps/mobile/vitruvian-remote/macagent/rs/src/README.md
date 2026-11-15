# Src

## Overview
Component package providing implementation for `apps/mobile/vitruvian-remote/macagent/rs/src`.

## Interface
- `[antigravity.rs:AGY_IDLE_STATUS]`
- `[antigravity.rs:AGY_SESSIONS_MAX]`
- `[antigravity.rs:AGY_PROMPT_MAX_BYTES]`
- `[antigravity.rs:AGY_RESUME_TIMEOUT]`
- `[antigravity.rs:AGY_SQLITE_TIMEOUT]`
- `[antigravity.rs:AGY_ROW_COLUMNS]`
- `[antigravity.rs:AgyStreamFn]`
- `[antigravity.rs:real_agy_stream]`
- `[antigravity.rs:is_valid_agy_id]`
- `[antigravity.rs:agy_dir]`
- `[antigravity.rs:default_agy_summaries]`
- `[antigravity.rs:AgyRow]`
- `[antigravity.rs:AgySession]`
- `[antigravity.rs:AgySessionsReply]`
- `[antigravity.rs:query_summaries]`
- `[antigravity.rs:parse_agy_rows]`
- `[antigravity.rs:sql_bool]`
- `[antigravity.rs:agy_workspaces]`
- `[antigravity.rs:agy_time]`
- `[antigravity.rs:agy_state]`

## Invariants
- [exec.rs:471]: `assert!(trunc, "expected truncated=true");`
- [exec.rs:472]: `assert!(`
- [exec.rs:479]: `assert!(!got.contains('\u{FFFD}'), "split UTF-8 rune: {:?}", got);`
- [mcp.rs:443]: `assert!(`
- [mcp.rs:450]: `assert!(logged.contains("act mcp: sms.list"), "logged: {}", logged);`
- [mcp.rs:451]: `assert!(`
- [notify.rs:310]: `assert!(!n.configured());`
- [notify.rs:311]: `assert!(n`
- [notify.rs:318]: `assert!(`
- [pair.rs:420]: `assert!(s.paired());`

## Side Effects
- [antigravity.rs:30]: `use crate::exec::get_exec_dir;`
- [antigravity.rs:155]: `pub fn query_summaries(db: &Path, query: &str) -> Result<Vec<AgyRow>, String> {`
- [antigravity.rs:156]: `if !db.exists() {`
- [exec.rs:21]: `//! Act-tier execution (`POST /v1/exec`), clipboard (`GET/POST /v1/clipboard`),`
- [exec.rs:208]: `let mut child = match cmd.spawn() {`
- [exec.rs:226]: `let out_handle = thread::spawn(move || {`
- [speaker.rs:56]: `/// Returned with HTTP 409 when a sign-in, grant-chat, or disconnect-chat job...`
- [hook.rs:142]: `if let Some(out) = permission_hook_output(stdin, "http://127.0.0.1:9949", &to...`
- [http_util.rs:21]: `//! Zero-dependency (std-only) HTTP/1.1 + SSE server, client, and test harness.`
- [http_util.rs:463]: `/// Serves a single HTTP connection.`

## Verification
- Run: `bazel test //apps/mobile/vitruvian-remote/macagent/rs/src/...`
