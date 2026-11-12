# Clipboard

## Overview
Component package providing implementation for `apps/desktop/vitruvian-atrium/Sources/VitruvianAtrium/Services/Clipboard`.

## Interface
- Internal implementation components

## Invariants
- None

## Side Effects
- [ClipboardAutoClearService.swift:30]: `/// letting ticks pile up would spawn a thread each time.`

## Verification
- Run: `bazel test //apps/desktop/vitruvian-atrium/Sources/VitruvianAtrium/Services/Clipboard/...`
