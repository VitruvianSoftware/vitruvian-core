# Src

## Overview
Component package providing implementation for `tools/pipeline-status/src`.

## Interface
- `[batch.rs:MAX_PUSHES]`
- `[batch.rs:Push]`
- `[batch.rs:Resolved]`
- `[batch.rs:Outcome]`
- `[batch.rs:parse_activity]`
- `[batch.rs:parse_range]`
- `[batch.rs:check_runs_response]`
- `[batch.rs:resolve]`
- `[cli.rs:run]`
- `[evaluate.rs:Evaluation]`
- `[evaluate.rs:EMPTY_RETURN_STATUS]`
- `[evaluate.rs:evaluate_runs_json]`
- `[evaluate.rs:list_failed]`
- `[evaluate.rs:list_in_flight]`
- `[evaluate.rs:restrict_to_push]`
- `[evaluate.rs:parse_utc]`
- `[evaluate.rs:DEFAULT_SETTLE_SECS]`
- `[evaluate.rs:parse_settle]`
- `[evaluate.rs:settle_secs_from_env]`
- `[evaluate.rs:runs_query]`
- Subdirectory: [bin](./bin/README.md)

## Invariants
- [batch.rs:300]: `Outcome::Waiting(w) => panic!("expected a verdict, got waiting: {w}"),`
- [batch.rs:339]: `assert!(`
- [batch.rs:355]: `Outcome::Waiting(w) => assert!(w.contains("not in the"), "{w}"),`
- [cli.rs:227]: `assert!(is_pr_number(yes), "{yes}");`
- [cli.rs:230]: `assert!(!is_pr_number(no), "{no}");`
- [jq.rs:375]: `_ => panic!("no value in {text}"),`
- [jq.rs:421]: `assert!(matches!(items[0], Input::Value(_, 1)));`
- [jq.rs:422]: `assert!(matches!(items[1], Input::ParseError(_)));`

## Side Effects
- [batch.rs:365]: `let bad_activity = || Err("HTTP 502".to_string());`
- [batch.rs:385]: `let bad_range = |_: &str, _: &str| Err("HTTP 500".to_string());`
- [batch.rs:389]: `let bad_runs = |_: &str| Err("HTTP 503".to_string());`
- [cli.rs:81]: `sh::run_quiet("git", &["fetch", "origin", "main", "-q"]);`
- [evaluate.rs:292]: `/// The runs query: server-side narrowed to pushes on `branch`, so a tip commit`

## Verification
- Run: `bazel test //tools/pipeline-status/src/...`
