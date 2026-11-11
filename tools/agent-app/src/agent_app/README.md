# Agent App

## Overview
Component package providing implementation for `tools/agent-app/src/agent_app`.

## Interface
- `[jq.rs:J]`
- `[jq.rs:Prog]`
- `[jq.rs:Ran]`
- `[jq.rs:run]`
- `[mod.rs:HOLD_LABEL]`
- `[mod.rs:RELEASE_HOLD_LABEL]`
- `[mod.rs:BETA_GATE_LABEL]`
- `[mod.rs:FAST_LANE_LABEL]`
- `[mod.rs:Refusal]`
- `[mod.rs:b64url]`
- `[mod.rs:awk_v]`
- `[mod.rs:Tool]`
- `[mod.rs:landed_candidates]`
- `[mod.rs:find_landed]`
- `[mod.rs:landed_gate]`
- `[mod.rs:arith]`
- `[mod.rs:take_agent]`
- `[mod.rs:need_target]`
- `[mod.rs:has_fast_lane]`
- `[mod.rs:has_body]`

## Invariants
- [tests.rs:54]: `assert!(take_agent(&v(&["--agent"])).is_none());`
- [tests.rs:55]: `assert!(take_agent(&v(&["--agent", ""])).is_none());`
- [tests.rs:62]: `assert!(need_target("pr", "u", b"12").is_ok());`

## Side Effects
- [mod.rs:22]: `//! kept the script's command line, its calls to curl, openssl, gh, git and the`
- [mod.rs:63]: `query($id: ID!) { node(id: $id) { ... on PullRequest {`
- [mod.rs:80]: `query($id: ID!) { node(id: $id) { ... on PullRequest {`

## Verification
- Run: `bazel test //tools/agent-app/src/agent_app/...`
