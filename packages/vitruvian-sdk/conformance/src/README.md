# Src

## Overview
Component package providing implementation for `packages/vitruvian-sdk/conformance/src`.

## Interface
- `[cli.rs:Options]`
- `[cli.rs:ParseOutcome]`
- `[cli.rs:parse_args]`
- `[cli.rs:resolve_folder]`
- `[cli.rs:check_to]`
- `[cli.rs:check]`
- `[cli.rs:main_with_args]`
- `[json.rs:Value]`
- `[json.rs:normalize_int]`
- `[json.rs:py_eq]`
- `[json.rs:loads_bytes]`
- `[json.rs:loads]`
- `[protocol.rs:MAX_LINE_BYTES]`
- `[protocol.rs:FIRST_ANSWER_SECONDS]`
- `[protocol.rs:ANSWER_SECONDS]`
- `[protocol.rs:EXIT_SECONDS]`
- `[protocol.rs:MAX_TREE_BYTES]`
- `[protocol.rs:MAX_BLOCKS]`
- `[protocol.rs:NEEDS_ID]`
- `[protocol.rs:VERSIONS]`

## Invariants
- [lib.rs:59]: `assert!(json::py_eq(&a, &b));`
- [lib.rs:124]: `assert!(check_params(&req).is_ok());`
- [lib.rs:144]: `assert!(kind_of(&missing_id_err).is_err());`

## Side Effects
- [cli.rs:174]: `.and_then(|r| r.get("exec"))`
- [cli.rs:179]: `"missing runtime.exec in manifest",`
- [cli.rs:191]: `let link = Link::spawn(&command, temp.path())?;`
- [session.rs:98]: `pub fn spawn(command: &[String], folder: &Path) -> io::Result<Self> {`
- [session.rs:107]: `.spawn()?;`
- [session.rs:112]: `let reader = thread::spawn(move || {`

## Verification
- Run: `bazel test //packages/vitruvian-sdk/conformance/src/...`
