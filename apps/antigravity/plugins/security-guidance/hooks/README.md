# Hooks

## Overview
Component package providing implementation for `apps/antigravity/plugins/security-guidance/hooks`.

## Interface
- `[rust-hook.sh:script entrypoint]`
- `[security-check.sh:script entrypoint]`
- Subdirectory: [src](./src/README.md)

## Invariants
- None

## Side Effects
- [rust-hook.sh:113]: `find "$cache" -maxdepth 1 -name '.build.*' -mmin +60 -exec rm -rf {} + 2>/dev...`
- [rust-hook.sh:145]: `-mtime "+$gc_days" -exec rm -rf {} + 2>/dev/null`
- [rust-hook.sh:243]: `perl -MPOSIX -e 'POSIX::setsid(); exec @ARGV or exit 1' \`
- [security-check.sh:17]: `exec "$(dirname "$0")/rust-hook.sh" security_check main.rs \`

## Verification
- Run: `bazel test //apps/antigravity/plugins/security-guidance/hooks/...`
