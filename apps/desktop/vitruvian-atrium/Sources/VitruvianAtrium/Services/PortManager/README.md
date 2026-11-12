# Portmanager

## Overview
Component package providing implementation for `apps/desktop/vitruvian-atrium/Sources/VitruvianAtrium/Services/PortManager`.

## Interface
- Internal implementation components

## Invariants
- None

## Side Effects
- [PortManagerService.swift:47]: `@Published package var query = ""`
- [PortManagerService.swift:72]: `let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()`
- [PortManagerSupport.swift:35]: `components.scheme = "http"`

## Verification
- Run: `bazel test //apps/desktop/vitruvian-atrium/Sources/VitruvianAtrium/Services/PortManager/...`
