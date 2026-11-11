# Pyast

## Overview
Component package providing implementation for `tools/lint-naming/src/pyast`.

## Interface
- `[lexer.rs:Kind]`
- `[lexer.rs:Token]`
- `[lexer.rs:Warn]`
- `[lexer.rs:Lexed]`
- `[lexer.rs:tokenize]`
- `[mod.rs:SyntaxWarning]`
- `[mod.rs:KeywordInfo]`
- `[mod.rs:CallInfo]`
- `[mod.rs:Parsed]`
- `[mod.rs:parse]`
- `[mod.rs:failure_point]`
- `[parser.rs:K]`
- `[parser.rs:Node]`
- `[parser.rs:is_keyword]`
- `[parser.rs:Parser]`
- `[parser.rs:valid_target]`
- `[strings.rs:LiteralValue]`
- `[strings.rs:decode_literal]`

## Invariants
- [mod.rs:294]: `assert!(calls(bad).is_none(), "{:?}", bad);`
- [mod.rs:312]: `assert!(calls(good).is_some(), "{:?}", good);`
- [mod.rs:319]: `assert!(p.calls.is_none());`
- [parser.rs:75]: `"False", "None", "True", "and", "as", "assert", "async", "await", "break", "c...`
- [parser.rs:393]: `"assert" => {`
- [parser.rs:399]: `return Ok(other("Assert", kids));`

## Side Effects
- [lexer.rs:167]: `Some(fs) => !matches!(fs.frames.last(), Some(Frame::Field { .. })),`
- [lexer.rs:352]: `if let Some(Frame::Field { level }) = fs.frames.last() {`
- [lexer.rs:357]: `fs.frames.pop();`

## Verification
- Run: `bazel test //tools/lint-naming/src/pyast/...`
