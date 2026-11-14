# Tool Conformance

## Overview
Component package providing implementation for `apps/mobile/vitruvian-remote/macmenu/scripts/src/tool_conformance`.

## Interface
- `[lib.rs:TABS]`
- `[lib.rs:SECTIONS]`
- `[lib.rs:SECONDS]`
- `[lib.rs:words]`
- `[lib.rs:says]`
- `[lib.rs:block]`
- `[lib.rs:section_headings]`
- `[lib.rs:Driver]`
- `[lib.rs:end_to_end_active]`
- `[lib.rs:end_to_end_coexistence]`
- `[lib.rs:run]`

## Invariants
- None

## Side Effects
- [lib.rs:256]: `.and_then(|r| r.get("exec"))`
- [lib.rs:258]: `.ok_or("missing runtime.exec")?;`
- [lib.rs:268]: `let link = Link::spawn(&[program.to_string_lossy().into_owned()], &data)`

## Verification
- Run: `bazel test //apps/mobile/vitruvian-remote/macmenu/scripts/src/tool_conformance/...`
