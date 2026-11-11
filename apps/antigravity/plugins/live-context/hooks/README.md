# Hooks

## Overview
Component package providing implementation for `apps/antigravity/plugins/live-context/hooks`.

## Interface
- `[inject-live-context.sh:script entrypoint]`
- `[rust-hook.sh:script entrypoint]`
- `[verify-response-shape.sh:script entrypoint]`
- Subdirectory: [src](./src/README.md)

## Invariants
- None

## Side Effects
- [inject-live-context.sh:13]: `exec "$(dirname "$0")/rust-hook.sh" live_context_hooks bin/inject_live_contex...`
- [rust-hook.sh:113]: `find "$cache" -maxdepth 1 -name '.build.*' -mmin +60 -exec rm -rf {} + 2>/dev...`
- [rust-hook.sh:145]: `-mtime "+$gc_days" -exec rm -rf {} + 2>/dev/null`
- [rust-hook.sh:243]: `perl -MPOSIX -e 'POSIX::setsid(); exec @ARGV or exit 1' \`
- [verify-response-shape.sh:14]: `exec "$(dirname "$0")/rust-hook.sh" live_context_hooks bin/verify_response_sh...`

## Verification
- Run: `bazel test //apps/antigravity/plugins/live-context/hooks/...`
