# Src

## Overview
Component package providing implementation for `apps/desktop/vitruvian-code/src`.

## Interface
- `[bot_lib.rs:BotAction]`
- `[bot_lib.rs:BotOptions]`
- `[bot_lib.rs:usage_text]`
- `[bot_lib.rs:parse_args]`
- `[bot_lib.rs:pid_file_path]`
- `[bot_lib.rs:log_file_path]`
- `[bot_lib.rs:read_pid]`
- `[bot_lib.rs:is_pid_alive]`
- `[bot_lib.rs:is_running]`
- `[bot_lib.rs:last_n_lines]`
- `[bot_lib.rs:run_bot]`
- Subdirectory: [rs](./rs/README.md)

## Invariants
- [bot_lib.rs:317]: `assert!(out.contains("Usage: ./bot.sh {start|stop|restart|status|logs}"));`
- [bot_lib.rs:321]: `assert!(start_opts.dry_run);`
- [bot_lib.rs:342]: `assert!(status_out.contains("❌ Bot is not running"));`

## Side Effects
- [bot_lib.rs:161]: `.spawn()`

## Verification
- Run: `bazel test //apps/desktop/vitruvian-code/src/...`
