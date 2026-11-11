# Killprocess

## Overview
Component package providing implementation for `apps/desktop/vitruvian/Sources/Vitruvian/Services/KillProcess`.

## Interface
- Internal implementation components

## Invariants
- None

## Side Effects
- [KillProcessService.swift:74]: `@Published package var query: String = ""`
- [KillProcessService.swift:129]: `let needle = query.trimmingCharacters(in: .whitespaces).lowercased()`

## Verification
- Run: `bazel test //apps/desktop/vitruvian/Sources/Vitruvian/Services/KillProcess/...`
