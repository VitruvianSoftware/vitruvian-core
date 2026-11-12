# Commands

## Overview
Component package providing implementation for `apps/suites/vitruvian-tabs/cli/rs/src/commands`.

## Interface
- `[auth.rs:build_gsm_store_neon_key_command]`
- `[auth.rs:persist_verified_neon_api_key]`
- `[auth.rs:run_auth_command]`
- `[config.rs:format_ascii_table]`
- `[config.rs:format_config_list]`
- `[config.rs:run_config_command_at]`
- `[config.rs:run_config_command]`
- `[db.rs:get_db_env]`
- `[db.rs:api_dir]`
- `[db.rs:DbActionPlan]`
- `[db.rs:plan_db_command]`
- `[db.rs:run_db_command]`
- `[ext.rs:ToolSpawnError]`
- `[ext.rs:ToolRunResult]`
- `[ext.rs:ToolRunner]`
- `[ext.rs:StdToolRunner]`
- `[ext.rs:run_tool]`
- `[ext.rs:run_tool_with]`
- `[ext.rs:run_tool_capture]`
- `[ext.rs:run_tool_capture_with]`

## Invariants
- None

## Side Effects
- [db.rs:27]: `/// Build environment map for Prisma/DB commands, injecting `DATABASE_URL` from`
- [db.rs:104]: `"prisma".to_string(),`
- [db.rs:109]: `"prisma".to_string(),`
- [workos.rs:69]: `callbacks.push("http://localhost:8080/api/v1/auth/callback".to_string());`
- [workos.rs:150]: `"Failed to fetch Cloud Run services. Make sure gcloud is configured.".to_stri...`
- [workos.rs:154]: `"Failed to fetch Cloud Run services. Make sure gcloud is configured.".to_stri...`

## Verification
- Run: `bazel test //apps/suites/vitruvian-tabs/cli/rs/src/commands/...`
