# Src

## Overview
Component package providing implementation for `packages/design-system-android/tools/src`.

## Interface
- `[argparse.rs:Kind]`
- `[argparse.rs:Opt]`
- `[argparse.rs:Parser]`
- `[argparse.rs:Values]`
- `[argparse.rs:Exit]`
- `[argparse.rs:help_width]`
- `[argparse.rs:wrap]`
- `[fsio.rs:pathlib_str]`
- `[fsio.rs:read_text]`
- `[fsio.rs:write_text]`
- `[gen_unicode_tables.rs:render_unicode_tables]`
- `[lib.rs:PROG]`
- `[lib.rs:parser]`
- `[lib.rs:generate]`
- `[lib.rs:run]`
- `[pyerr.rs:Exc]`
- `[pyerr.rs:os_error]`
- `[pyerr.rs:decode_utf8]`
- `[pyerr.rs:encode_error]`
- `[pyjson.rs:MAX_DEPTH]`

## Invariants
- [lib.rs:122]: `assert!(text.starts_with("// header\n\n// GENERATED FILE - DO NOT EDIT.\n"));`
- [lib.rs:127]: `assert!(text.ends_with("public const val GLASS_BLUR_RADIUS: Float = 16f\n"));`
- [lib.rs:154]: `assert!(exit.stderr.ends_with(`
- [pyerr.rs:198]: `assert!(t.starts_with("Traceback (most recent call last):\n"));`
- [pyerr.rs:199]: `assert!(t.ends_with("\nKeyError: 'space'\n"));`
- [pyerr.rs:200]: `assert!(Exc::new("ValueError", "")`
- [pyjson.rs:425]: `assert!(loads(&ps(&deep)).is_ok());`
- [pyjson.rs:471]: `assert!(same(&ours, &theirs), "{}", doc);`
- [tokens_are_current.rs:286]: `assert!(status.success());`
- [value.rs:362]: `assert!(list.index(&Value::Int(BigInt::small(-1))).is_ok());`

## Side Effects
- [main.rs:34]: `.spawn(move || gen_tokens::run(&args))`
- [main.rs:35]: `.expect("spawn the generator")`
- [pyjson.rs:423]: `.spawn(|| {`

## Verification
- Run: `bazel test //packages/design-system-android/tools/src/...`
