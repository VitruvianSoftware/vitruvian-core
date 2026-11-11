# Src

## Overview
Component package providing implementation for `tools/merge-queue-stats/src`.

## Interface
- `[argparse.rs:Kind]`
- `[argparse.rs:Opt]`
- `[argparse.rs:Parser]`
- `[argparse.rs:Values]`
- `[argparse.rs:Exit]`
- `[argparse.rs:help_width]`
- `[argparse.rs:wrap]`
- `[http.rs:Error]`
- `[http.rs:Request]`
- `[http.rs:send]`
- `[json.rs:Value]`
- `[json.rs:dedup]`
- `[json.rs:JsonError]`
- `[json.rs:loads]`
- `[json.rs:dumps]`
- `[lib.rs:DEFAULT_API]`
- `[lib.rs:QUERY]`
- `[lib.rs:Fail]`
- `[lib.rs:fetch_pulls]`
- `[lib.rs:fetch_runs]`

## Invariants
- [http.rs:375]: `assert!(matches!(get("ftp://x"), Err(Error::Value(_))));`
- [http.rs:378]: `Err(Error::Url(m)) => assert!(m.starts_with("<urlopen error [Errno "), "{}", m),`
- [http.rs:379]: `other => panic!("{:?}", other),`
- [pystr.rs:270]: `assert!(is_space('\u{1c}'));`
- [pystr.rs:271]: `assert!(!is_space('\u{200b}'));`
- [stats.rs:449]: `let Value::Arr(runs) = runs else { panic!() };`
- [stats.rs:459]: `assert!(out.contains("| PRs merged through the queue | 1 (0.1/day) |"));`
- [stats.rs:460]: `assert!(out.contains("median 10.0 min, p90 10.0 min"));`

## Side Effects
- [http.rs:22]: `//! request, a JSON body or none, the response body back. `http://` URLs (a`
- [http.rs:24]: `//! socket; `https://` goes through curl, since the standard library has no`
- [http.rs:25]: `//! TLS. Errors read as urllib's do: `HTTP Error 404: Not Found` for a status`
- [lib.rs:26]: `pub mod http;`
- [lib.rs:43]: `pub const QUERY: &str = "`
- [lib.rs:44]: `query($q: String!, $after: String) {`

## Verification
- Run: `bazel test //tools/merge-queue-stats/src/...`
