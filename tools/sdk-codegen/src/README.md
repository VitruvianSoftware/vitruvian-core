# Src

## Overview
Component package providing implementation for `tools/sdk-codegen/src`.

## Interface
- `[argparse.rs:Options]`
- `[argparse.rs:Parsed]`
- `[argparse.rs:width_from]`
- `[argparse.rs:help]`
- `[argparse.rs:parse]`
- `[cli.rs:is_generated]`
- `[cli.rs:generate]`
- `[cli.rs:committed]`
- `[cli.rs:check]`
- `[cli.rs:write]`
- `[cli.rs:normpath]`
- `[cli.rs:traceback]`
- `[cli.rs:run]`
- `[difflib.rs:unified_diff]`
- `[fsio.rs:join]`
- `[fsio.rs:dirname]`
- `[fsio.rs:os_error]`
- `[fsio.rs:decode_utf8]`
- `[fsio.rs:read_text]`
- `[fsio.rs:makedirs]`
- Subdirectory: [emitters](./emitters/README.md)

## Invariants
- [argparse.rs:454]: `other => panic!("{other:?}"),`
- [argparse.rs:469]: `assert!(matches!(run(&["-hx"]), Parsed::Help(_)));`
- [argparse.rs:470]: `assert!(matches!(run(&["--he"]), Parsed::Help(_)));`
- [cli.rs:315]: `assert!(is_generated("kits/python/x/generated/messages.py"));`
- [cli.rs:316]: `assert!(is_generated("go/toolkit/protocol_gen.go"));`
- [cli.rs:317]: `assert!(!is_generated("kits/generated"));`
- [difflib.rs:290]: `assert!(unified_diff(&a, &a, "a", "b", 1).is_empty());`
- [fsio.rs:254]: `assert!(read_text(dir.to_str().unwrap())`
- [pyerr.rs:188]: `assert!(contains(&text, "x").unwrap());`
- [pyerr.rs:199]: `assert!(hashable(&list).is_err());`

## Side Effects
- None

## Verification
- Run: `bazel test //tools/sdk-codegen/src/...`
