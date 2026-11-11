# Src

## Overview
Component package providing implementation for `catalog/src`.

## Interface
- `[argparse.rs:Kind]`
- `[argparse.rs:Opt]`
- `[argparse.rs:Parser]`
- `[argparse.rs:Values]`
- `[argparse.rs:Exit]`
- `[argparse.rs:py_int]`
- `[argparse.rs:help_width]`
- `[argparse.rs:wrap]`
- `[base64.rs:encode]`
- `[base64.rs:b64decode_validate]`
- `[bump.rs:OK]`
- `[bump.rs:REFUSED]`
- `[bump.rs:NOT_READY]`
- `[bump.rs:NOT_LISTED]`
- `[bump.rs:UNAVAILABLE]`
- `[bump.rs:CATALOG]`
- `[bump.rs:SCHEMA]`
- `[bump.rs:SOURCES]`
- `[bump.rs:APP_INFO]`
- `[bump.rs:HOME_REPO]`
- Subdirectory: [bin](./bin/README.md)
- Subdirectory: [crypto](./crypto/README.md)

## Invariants
- [catalogue.rs:181]: `assert!(out.ends_with("public_key: \"KEY\"\ntools: []\n"));`
- [check_downloads.rs:361]: `assert!(probs.iter().any(|p| p.contains("not later than main's")));`
- [macho.rs:253]: `assert!(macho_slices(short).is_err());`
- [macho.rs:256]: `assert!(macho_slices(&bad).is_err());`
- [plist.rs:270]: `assert!(load(b"<plist><dict><key>x</dict></plist>").is_err());`
- [pyerr.rs:291]: `assert!(decode_utf8_py(b"\xed\xa0\x80", false).is_err());`
- [pystr.rs:265]: `assert!(is_space('\u{1c}'));`
- [pystr.rs:266]: `assert!(!is_space('\u{200b}'));`
- [signing.rs:126]: `assert!(verify(message, &made, &b64_hex(public)));`
- [signing.rs:136]: `assert!(verify(data, &signature, &b64_hex(public)));`

## Side Effects
- [bump.rs:212]: `fn fetch(&self, asset: &Value) -> Res<Option<Vec<u8>>>;`
- [bump.rs:225]: `fn fetch(&self, asset: &Value) -> Res<Option<Vec<u8>>> {`
- [bump.rs:252]: `fn fetch(&self, asset: &Value) -> Res<Option<Vec<u8>>> {`
- [check_downloads.rs:33]: `use crate::{http, py, pypath, rules};`
- [check_downloads.rs:39]: `/// What fetches a download: `fetch(url, size)`.`
- [check_downloads.rs:40]: `pub type Fetch<'a> = dyn Fn(&Value, &Value) -> Res<Option<Vec<u8>>> + 'a;`
- [http.rs:21]: `//! HTTP for the catalog's tools: `urllib.request.urlopen(url).read(n)` as`
- [http.rs:24]: `//! The client speaks plain http:// itself (with urllib's redirects) and`
- [http.rs:25]: `//! reads file:// from disk; https:// goes through `curl`, since the`
- [lib.rs:32]: `pub mod http;`

## Verification
- Run: `bazel test //catalog/src/...`
