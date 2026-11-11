# Src

## Overview
Component package providing implementation for `packages/vitruvian-sdk/verification/src`.

## Interface
- `[conformance_suite.rs:maybe_run_mock_tool]`
- `[conformance_suite.rs:run_all]`
- `[conformance_suite.rs:main_with_args]`
- `[go_template.rs:built_tool]`
- `[go_template.rs:main_with_args]`
- `[guide.rs:EXAMPLES]`
- `[guide.rs:VERBS]`
- `[guide.rs:ALONE]`
- `[guide.rs:FLAGS]`
- `[guide.rs:blocks]`
- `[guide.rs:message_problems]`
- `[guide.rs:excerpt_problems]`
- `[guide.rs:join_swift_line_continuations]`
- `[guide.rs:said_problems]`
- `[guide.rs:kit_problems]`
- `[guide.rs:native_kit_problems]`
- `[guide.rs:templates]`
- `[guide.rs:shell_problems]`
- `[guide.rs:run_in]`
- `[guide.rs:main]`
- Subdirectory: [bin](./bin/README.md)

## Invariants
- [lib.rs:234]: `assert!(schema::matches_pattern(`
- [lib.rs:238]: `assert!(!schema::matches_pattern(`
- [lib.rs:242]: `assert!(schema::matches_pattern(`
- [mirror_workflows.rs:315]: `let text = fs::read_to_string(&path).unwrap_or_else(|e| panic!("{}: {e}", pat...`
- [mirror_workflows.rs:333]: `panic!("release.yml has no step with the id detect");`
- [mirror_workflows.rs:347]: `assert!(status.status.success(), "git {:?} failed", args);`
- [samples.rs:336]: `"require github.com/VitruvianSoftware/vitruvian-sdk/go v",`
- [samples.rs:343]: `"require github.com/VitruvianSoftware/vitruvian-sdk/go v",`

## Side Effects
- [conformance_suite.rs:414]: `.spawn()`
- [mirror_workflows.rs:415]: `s.spawn(move || {`
- [protocol_examples.rs:461]: `.spawn()`
- [protocol_examples.rs:465]: `return vec![format!("reference-tool-2: failed to spawn {prog}: {e}")];`
- [protocol_examples.rs:472]: `thread::spawn(move || {`
- [samples.rs:165]: `.and_then(|r| r.get("exec"))`
- [samples.rs:187]: `let link = match Link::spawn(&command, temp.path()) {`
- [samples.rs:479]: `.and_then(|r| r.get("exec"))`
- [swift_template.rs:85]: `let mut child = match cmd.spawn() {`
- [swift_template.rs:92]: `let out_handle = thread::spawn(move || {`

## Verification
- Run: `bazel test //packages/vitruvian-sdk/verification/src/...`
