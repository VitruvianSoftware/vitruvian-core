# Mousenavigation

## Overview
Component package providing implementation for `apps/desktop/vitruvian-atrium/Sources/VitruvianAtrium/Services/MouseNavigation`.

## Interface
- Internal implementation components

## Invariants
- None

## Side Effects
- [MouseNavigationService.swift:254]: `// query reads it here, before another window can take its place;`

## Verification
- Run: `bazel test //apps/desktop/vitruvian-atrium/Sources/VitruvianAtrium/Services/MouseNavigation/...`
