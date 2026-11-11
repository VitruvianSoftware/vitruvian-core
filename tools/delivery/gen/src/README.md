# Src

## Overview
Component package providing implementation for `tools/delivery/gen/src`.

## Interface
- `[actionpins.rs:Pins]`
- `[actionpins.rs:parse_pin_line]`
- `[app.rs:BazelRunner]`
- `[app.rs:exec_bazel]`
- `[app.rs:discover]`
- `[app.rs:write_atomic]`
- `[app.rs:PinSource]`
- `[app.rs:write_apps]`
- `[app.rs:resolve_workspace]`
- `[app.rs:bazel_binary]`
- `[app.rs:Flags]`
- `[app.rs:parse_flags]`
- `[app.rs:main_with_args]`
- `[gojson.rs:J]`
- `[gojson.rs:check_valid]`
- `[gojson.rs:parse]`
- `[gojson.rs:kind_word]`
- `[gojson.rs:fold_name]`
- `[gostd.rs:Value]`
- `[gostd.rs:decode_rune]`

## Invariants
- [actionpins.rs:235]: `/// MustLoadDefault, with the panic turned into the message Go panicked`
- [actionpins.rs:285]: `assert!(parse_pin_line("uses: a/b@v4").is_err());`
- [actionpins.rs:294]: `assert!(Pins::load(p.to_str().unwrap())`
- [app.rs:304]: `// panic in its function and re-panics it: the runtime then marks`
- [app.rs:307]: `.map_err(|m| GenError::Panic(format!("{} [recovered, repanicked]", m)))?;`
- [app.rs:339]: `panic => panic,`
- [render.rs:40]: `/// with the way a Go panic does.`
- [render.rs:44]: `Panic(String),`
- [render.rs:50]: `GenError::Msg(s) | GenError::Panic(s) => s,`
- [tests.rs:72]: `panic!("cannot find tools/delivery/gen/testdata");`

## Side Effects
- [app.rs:21]: `//! The command: flags, discovery through `bazel query`, and writing (and`
- [app.rs:67]: `"exec: {}: cannot run executable found relative to current directory",`
- [app.rs:75]: `"exec: {}: executable file not found in $PATH",`
- [main.rs:31]: `.spawn(move || delivery_gen::app::main_with_args(&argv0, &rest))`
- [main.rs:32]: `.expect("spawn")`
- [render.rs:423]: `b.push_str("          fetch-depth: 0\n");`
- [render.rs:461]: `b.push_str("      # firmware-only change does not re-fetch it.\n");`
- [tests.rs:229]: `let fake = |query: &'static str| {`
- [tests.rs:233]: `"query" => Ok(query.as_bytes().to_vec()),`

## Verification
- Run: `bazel test //tools/delivery/gen/src/...`
