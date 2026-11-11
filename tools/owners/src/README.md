# Src

## Overview
Component package providing implementation for `tools/owners/src`.

## Interface
- `[engine.rs:OwnersNode]`
- `[engine.rs:Engine]`
- `[engine.rs:IGNORED_DIRS]`
- `[engine.rs:REQUIRED_SUBTREES]`
- `[engine.rs:is_ignored]`
- `[flags.rs:Flags]`
- `[flags.rs:FlagError]`
- `[flags.rs:usage]`
- `[flags.rs:parse]`
- `[gostr.rs:is_space]`
- `[gostr.rs:trim_space]`
- `[gostr.rs:fields]`
- `[gostr.rs:quote]`
- `[gostr.rs:clean]`
- `[gostr.rs:join]`
- `[gostr.rs:dir]`
- `[gostr.rs:getwd]`
- `[gostr.rs:abs]`
- `[gostr.rs:errno_text]`
- `[gostr.rs:path_error]`

## Invariants
- [engine.rs:375]: `assert!(c.contains("* @VitruvianSoftware/platform-team"));`
- [engine.rs:376]: `assert!(c.contains("/devx/ @VitruvianSoftware/devx-team @VitruvianSoftware/pl...`
- [engine.rs:377]: `assert!(c.contains("/devx/*.md @VitruvianSoftware/docs-team"));`
- [flags.rs:173]: `assert!(!p(&["-check=false"]).unwrap().check);`
- [flags.rs:174]: `assert!(!p(&["pos", "-check"]).unwrap().check);`
- [flags.rs:175]: `assert!(!p(&["--", "-check"]).unwrap().check);`
- [schema.rs:245]: `assert!(c.options.no_parent_owners);`
- [schema.rs:249]: `assert!(c.options.no_parent_owners);`
- [schema.rs:280]: `assert!(c.options.no_parent_owners);`
- [validate.rs:347]: `assert!(validate_handle(h).is_ok(), "{h}");`

## Side Effects
- [gostr.rs:212]: `/// Go's `os.WriteFile(path, data, 0o644)`, with its error text.`

## Verification
- Run: `bazel test //tools/owners/src/...`
