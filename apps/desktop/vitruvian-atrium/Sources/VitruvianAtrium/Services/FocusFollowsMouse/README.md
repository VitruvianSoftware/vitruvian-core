# Focusfollowsmouse

## Overview
Component package providing implementation for `apps/desktop/vitruvian-atrium/Sources/VitruvianAtrium/Services/FocusFollowsMouse`.

## Interface
- Internal implementation components

## Invariants
- None

## Side Effects
- [FocusFollowsMouseService.swift:137]: `/// again when the window query answers, because the query takes long`
- [FocusFollowsMouseService.swift:249]: `/// receives just the ID and never needs a system-wide Accessibility query.`
- [FocusFollowsMouseService.swift:257]: `// changes after the ownership lookup. Never fall back to a global query.`

## Verification
- Run: `bazel test //apps/desktop/vitruvian-atrium/Sources/VitruvianAtrium/Services/FocusFollowsMouse/...`
