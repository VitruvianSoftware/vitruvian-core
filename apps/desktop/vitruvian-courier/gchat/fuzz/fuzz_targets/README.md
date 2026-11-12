# Fuzz Targets

## Overview
Component package providing implementation for `apps/desktop/vitruvian-courier/gchat/fuzz/fuzz_targets`.

## Interface
- Internal implementation components

## Invariants
- [fuzz_chunk_parser.rs:21]: `assert!(`
- [fuzz_chunk_parser.rs:31]: `assert!(fuzz_chunk_parser_once(&buf));`
- [fuzz_cookies.rs:15]: `assert!(`
- [fuzz_cookies.rs:25]: `assert!(fuzz_cookies_once(&buf));`
- [fuzz_fmt_annotations.rs:17]: `assert!(`
- [fuzz_fmt_annotations.rs:27]: `assert!(fuzz_fmt_annotations_once(&buf));`
- [fuzz_pblite_event.rs:20]: `assert!(`
- [fuzz_pblite_event.rs:30]: `assert!(fuzz_pblite_event_once(&buf));`

## Side Effects
- None

## Verification
- Run: `bazel test //apps/desktop/vitruvian-courier/gchat/fuzz/fuzz_targets/...`
