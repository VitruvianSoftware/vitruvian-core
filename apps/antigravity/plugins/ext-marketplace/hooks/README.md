# Hooks

## Overview
Component package providing implementation for `apps/antigravity/plugins/ext-marketplace/hooks`.

## Interface
- `[note-plugin-cmd.sh:script entrypoint]`
- `[rust-hook.sh:script entrypoint]`
- Subdirectory: [src](./src/README.md)

## Invariants
- None

## Side Effects
- [note-plugin-cmd.sh:15]: `exec "$(dirname "$0")/rust-hook.sh" note_plugin_cmd main.rs \`
- [rust-hook.sh:113]: `find "$cache" -maxdepth 1 -name '.build.*' -mmin +60 -exec rm -rf {} + 2>/dev...`
- [rust-hook.sh:145]: `-mtime "+$gc_days" -exec rm -rf {} + 2>/dev/null`
- [rust-hook.sh:243]: `perl -MPOSIX -e 'POSIX::setsid(); exec @ARGV or exit 1' \`

## Verification
- Run: `bazel test //apps/antigravity/plugins/ext-marketplace/hooks/...`
