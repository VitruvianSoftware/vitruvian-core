# Src

## Overview
Component package providing implementation for `tools/pipeline/gen/src`.

## Interface
- `[actionpins.rs:Pins]`
- `[actionpins.rs:parse_pin_line]`
- `[actionpins.rs:load]`
- `[actionpins.rs:find_default_path]`
- `[actionpins.rs:load_default]`
- `[dag.rs:Dag]`
- `[dag.rs:build_dag]`
- `[flags.rs:Flags]`
- `[flags.rs:FlagError]`
- `[flags.rs:usage]`
- `[flags.rs:parse]`
- `[gojson.rs:Json]`
- `[gojson.rs:check_valid]`
- `[gojson.rs:parse_valid]`
- `[gojson.rs:parse]`
- `[gojson.rs:fold_name]`
- `[gostr.rs:trim_space]`
- `[gostr.rs:decode_rune]`
- `[gostr.rs:quote_bytes]`
- `[gostr.rs:quote]`

## Invariants
- [actionpins.rs:232]: `/// Go's `MustLoadDefault`, with the panic text as the error (the caller`
- [flags.rs:200]: `assert!(!p(&["-check=false"]).unwrap().check);`
- [flags.rs:201]: `assert!(!p(&["pos", "-check"]).unwrap().check);`
- [flags.rs:216]: `assert!(u.starts_with("Usage of g:\n  -check\n    \tVerify"));`
- [lib.rs:82]: `/// What the Go runtime printed for an unrecovered panic; exit 2.`
- [lib.rs:83]: `fn panic(&mut self, m: &str) -> i32 {`
- [lib.rs:86]: `"panic: {m}\n\ngoroutine 1 [running]:\nmain.main()\n"`
- [render.rs:64]: `Panic(String),`
- [render.rs:102]: `load_pins().map_err(|e| RenderError::Panic(format!("{e} [recovered, repanicke...`
- [render.rs:103]: `let pin = |action: &str| pins.lookup(action).map_err(RenderError::Panic);`

## Side Effects
- [gostr.rs:265]: `/// Go's `os.WriteFile(path, data, 0o644)`, with its error text.`
- [render.rs:149]: `// query below is allowed 15 (see --timeout-sec), plus checkout and setup.`
- [render.rs:168]: `b.push_str("          fetch-depth: 0\n\n");`
- [render.rs:350]: `b.push_str("      - name: Fetch the dependency map kept under a git ref\n");`

## Verification
- Run: `bazel test //tools/pipeline/gen/src/...`
