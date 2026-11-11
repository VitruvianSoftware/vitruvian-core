# Hooks

## Overview
Component package providing implementation for `apps/antigravity/plugins/gh-watch/hooks`.

## Interface
- `[note-pr-create.sh:script entrypoint]`
- `[rust-hook.sh:script entrypoint]`
- Subdirectory: [src](./src/README.md)

## Invariants
- None

## Side Effects
- [note-pr-create.sh:24]: `exec "$(dirname "$0")/rust-hook.sh" note_pr_create main.rs \`
- [rust-hook.sh:113]: `find "$cache" -maxdepth 1 -name '.build.*' -mmin +60 -exec rm -rf {} + 2>/dev...`
- [rust-hook.sh:145]: `-mtime "+$gc_days" -exec rm -rf {} + 2>/dev/null`
- [rust-hook.sh:243]: `perl -MPOSIX -e 'POSIX::setsid(); exec @ARGV or exit 1' \`

## Verification
- Run: `bazel test //apps/antigravity/plugins/gh-watch/hooks/...`
