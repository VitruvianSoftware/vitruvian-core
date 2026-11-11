# Src

## Overview
Component package providing implementation for `tools/agent-roster/src`.

## Interface
- `[lib.rs:GENERATED_COMMENT]`
- `[lib.rs:TABLE_MARKER]`
- `[lib.rs:OUTPUT_DIRS]`
- `[lib.rs:CORE_SOURCE]`
- `[lib.rs:CORE_COPIES]`
- `[lib.rs:PRICES_SOURCE]`
- `[lib.rs:PRICES_COPIES]`
- `[lib.rs:add_core_copies]`
- `[lib.rs:add_prices_copies]`
- `[lib.rs:REQUIRED_HARNESSES]`
- `[lib.rs:SKILL_OUTPUTS]`
- `[lib.rs:TierRow]`
- `[lib.rs:AgentRow]`
- `[lib.rs:HarnessModel]`
- `[lib.rs:TierSpec]`
- `[lib.rs:Roster]`
- `[lib.rs:Mode]`
- `[lib.rs:DiffReport]`
- `[lib.rs:parse_tiers]`
- `[lib.rs:parse_agents]`

## Invariants
- None

## Side Effects
- None

## Verification
- Run: `bazel test //tools/agent-roster/src/...`
