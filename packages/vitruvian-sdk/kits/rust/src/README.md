# Src

## Overview
Component package providing implementation for `packages/vitruvian-sdk/kits/rust/src`.

## Interface
- `[app.rs:StatusOptions]`
- `[app.rs:App]`
- `[app.rs:Notify]`
- `[app.rs:Ui]`
- `[app.rs:Open]`
- `[app.rs:Clipboard]`
- `[app.rs:Keystrokes]`
- `[app.rs:Processes]`
- `[app.rs:Storage]`
- `[error.rs:RefusalCode]`
- `[error.rs:ToolError]`
- `[link.rs:Message]`
- `[link.rs:parse]`
- `[link.rs:Next]`
- `[link.rs:Outgoing]`
- `[link.rs:Link]`
- `[panels.rs:PanelEvent]`
- `[panels.rs:PanelAnswer]`
- `[panels.rs:Opened]`
- `[panels.rs:Acted]`
- Subdirectory: [generated](./generated/) (code written by `//tools/sdk-codegen`; do not edit)

## Invariants
- None

## Side Effects
- [link.rs:164]: `thread::spawn(move || read(input, sender));`

## Verification
- Run: `bazel test //packages/vitruvian-sdk/kits/rust/src/...`
