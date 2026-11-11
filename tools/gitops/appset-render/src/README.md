# Src

## Overview
Component package providing implementation for `tools/gitops/appset-render/src`.

## Interface
- `[gofmt.rs:ItemArg]`
- `[gofmt.rs:Arg]`
- `[gofmt.rs:sprintf]`
- `[gofmt.rs:errorf]`
- `[gostr.rs:RUNE_ERROR]`
- `[gostr.rs:decode_rune]`
- `[gostr.rs:decode_last_rune]`
- `[gostr.rs:is_letter]`
- `[gostr.rs:is_digit]`
- `[gostr.rs:is_print]`
- `[gostr.rs:is_unicode_space]`
- `[gostr.rs:trim_space]`
- `[gostr.rs:push_rune]`
- `[gostr.rs:quote]`
- `[gostr.rs:quote_to_ascii]`
- `[gostr.rs:quote_rune]`
- `[gostr.rs:can_backquote]`
- `[gostr.rs:unquote_char]`
- `[gostr.rs:unquote]`
- `[lib.rs:SPRIG_NAMES]`

## Invariants
- [gostr.rs:462]: `assert!(can_backquote(b"a\tb"));`
- [gostr.rs:463]: `assert!(!can_backquote(b"a`b"));`
- [gostr.rs:470]: `assert!(unquote(b"\"\\q\"").is_err());`

## Side Effects
- [main.rs:30]: `.spawn(move || appset_render::run(&argv, &mut std::io::stdout(), &mut std::io...`
- [main.rs:31]: `.expect("spawn parser thread")`

## Verification
- Run: `bazel test //tools/gitops/appset-render/src/...`
