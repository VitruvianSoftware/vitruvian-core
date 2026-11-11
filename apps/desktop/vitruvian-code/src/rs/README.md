# Rs

## Overview
Component package providing implementation for `apps/desktop/vitruvian-code/src/rs`.

## Interface
- `[agy.rs:ChatSettings]`
- `[agy.rs:ChatSettingsOverrides]`
- `[agy.rs:RunningProcessInfo]`
- `[agy.rs:PromptResult]`
- `[agy.rs:StreamUpdate]`
- `[agy.rs:ParsedAgyOutput]`
- `[agy.rs:ModelInfo]`
- `[agy.rs:Conversation]`
- `[agy.rs:ProviderCommand]`
- `[agy.rs:env_compat_from_map]`
- `[agy.rs:env_compat]`
- `[agy.rs:current_environment_map]`
- `[agy.rs:resolve_agy_binary_from_map]`
- `[agy.rs:resolve_agy_binary]`
- `[agy.rs:approval_args]`
- `[agy.rs:build_agy_args]`
- `[agy.rs:friendly_error]`
- `[agy.rs:mentions_unknown_conversation]`
- `[agy.rs:build_provider_args]`
- `[agy.rs:clean_cli_output]`

## Invariants
- None

## Side Effects
- [bot.rs:24]: `//! handlers, media prompt builders, rate-limiting, and Telegram HTTP Bot API.`

## Verification
- Run: `bazel test //apps/desktop/vitruvian-code/src/rs/...`
