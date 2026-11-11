# Toolkit

## Overview
Component package providing implementation for `packages/vitruvian-sdk/go/toolkit`.

## Interface
- `[app.go:App]`
- `[app.go:Language]`
- `[app.go:DataFolder]`
- `[app.go:Supports]`
- `[app.go:Send]`
- `[app.go:SetRunnable]`
- `[app.go:Log]`
- `[app.go:Notify]`
- `[app.go:HUD]`
- `[app.go:Beep]`
- `[app.go:ShowNotice]`
- `[app.go:Open]`
- `[app.go:URL]`
- `[app.go:Clipboard]`
- `[app.go:ReadText]`
- `[app.go:WriteText]`
- `[app.go:Keystrokes]`
- `[app.go:Paste]`
- `[app.go:PressMenuItem]`
- `[app.go:Processes]`
- Subdirectory: [ui](./ui/README.md)

## Invariants
- None

## Side Effects
- None

## Verification
- Run: `bazel test //packages/vitruvian-sdk/go/toolkit/...`
