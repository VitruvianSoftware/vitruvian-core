# Agent Ci Monitor

## Overview
Component package providing implementation for `apps/embedded/esp32-s3/host_companion/src/agent_ci_monitor`.

## Interface
- `[lib.rs:AGENT_STATE_IDLE]`
- `[lib.rs:AGENT_STATE_RUNNING]`
- `[lib.rs:AGENT_STATE_REVIEW]`
- `[lib.rs:AGENT_STATE_ERROR]`
- `[lib.rs:CI_STATUS_UNKNOWN]`
- `[lib.rs:CI_STATUS_PASSING]`
- `[lib.rs:CI_STATUS_FAILING]`
- `[lib.rs:CI_STATUS_PENDING]`
- `[lib.rs:CI_STATUS_NONE]`
- `[lib.rs:detect_agent_error]`
- `[lib.rs:parse_agent_processes]`
- `[lib.rs:determine_agent_state]`
- `[lib.rs:parse_agent_progress]`
- `[lib.rs:parse_git_status]`
- `[lib.rs:parse_gh_pr_checks]`
- `[lib.rs:parse_gh_run_list]`
- `[lib.rs:build_agent_ci_payload]`
- `[lib.rs:serialize_packet]`
- `[lib.rs:get_github_ci_status]`
- `[lib.rs:get_active_agents]`

## Invariants
- None

## Side Effects
- None

## Verification
- Run: `bazel test //apps/embedded/esp32-s3/host_companion/src/agent_ci_monitor/...`
