# Src

## Overview
Component package providing implementation for `tools/sync-downloads/src`.

## Interface
- `[argparse.rs:Kind]`
- `[argparse.rs:Opt]`
- `[argparse.rs:Parser]`
- `[argparse.rs:Values]`
- `[argparse.rs:Exit]`
- `[argparse.rs:help_width]`
- `[argparse.rs:wrap]`
- `[difflib.rs:unified_diff]`
- `[fetch.rs:ATTEMPTS]`
- `[fetch.rs:backoff]`
- `[fetch.rs:CurlError]`
- `[fetch.rs:Transport]`
- `[fetch.rs:System]`
- `[fetch.rs:fetch_json]`
- `[fetch.rs:fetch_json_with]`
- `[fetch.rs:reason]`
- `[json.rs:Value]`
- `[json.rs:dedup]`
- `[json.rs:JsonError]`
- `[json.rs:loads]`

## Invariants
- [difflib.rs:344]: `assert!(d.contains("@@ -1,5 +1,5 @@\n 0\n-1\n+x\n"));`
- [difflib.rs:345]: `assert!(d.ends_with("-19\n+y"));`
- [fetch.rs:382]: `assert!(!gave_up);`
- [fetch.rs:413]: `assert!(slept.is_empty());`
- [fetch.rs:436]: `assert!(!gave_up, "{err}");`
- [pyre.rs:91]: `assert!(i == chars.len(), "unsupported pattern {:?}", pattern);`
- [pyre.rs:108]: `assert!(p[*i] == ')', "unbalanced group");`
- [pyre.rs:120]: `assert!(!(*i < p.len() && p[*i] == '?'), "lazy optional group");`
- [pystr.rs:270]: `assert!(is_space('\u{1c}'));`
- [pystr.rs:271]: `assert!(!is_space('\u{200b}'));`

## Side Effects
- [fetch.rs:23]: `//! runs `curl` (headers on stdin, so a token never shows in `ps`); a failure`
- [fetch.rs:27]: `//! fetch is tried up to [`ATTEMPTS`] times. One attempt is one round: `gh`
- [fetch.rs:28]: `//! api`, then curl if gh failed. The round is what is retried, not each`
- [lib.rs:27]: `pub mod fetch;`
- [sync.rs:29]: `use crate::fetch;`
- [sync.rs:147]: `let data = fetch::fetch_json(&format!("repos/{}/releases/latest", repo), toke...`
- [sync.rs:155]: `let refs = fetch::fetch_json(`

## Verification
- Run: `bazel test //tools/sync-downloads/src/...`
