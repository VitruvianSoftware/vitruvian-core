# Switcher

## Overview
Component package providing implementation for `apps/desktop/vitruvian-atrium/Sources/VitruvianAtrium/Services/Switcher`.

## Interface
- Internal implementation components

## Invariants
- [WindowEnumerator.swift:19]: `/// Window titles require Screen Recording on modern macOS; Vitruvian Atrium's own`

## Side Effects
- [SpaceWindowBridge.swift:50]: `/// Keep an unavailable query distinct from an explicit ordered-out answer.`
- [SpaceWindowBridge.swift:77]: `/// window. Empty for leftover surfaces, and when the query is unavailable.`
- [SpaceWindowBridge.swift:83]: `/// query is unavailable or failed for this window; callers deciding whether`
- [WindowEnumerator.swift:297]: `/// The same decision with the preference and the desktop query passed in.`
- [WindowEnumerator.swift:298]: `/// The query runs only for a window when previews keep to the current desktop.`
- [WindowEnumerator.swift:443]: `// process can own its real windows. Query both sides of that mapping.`
- [WindowUseOrder.swift:88]: `// A WindowServer query must not erase focus recorded while it ran.`

## Verification
- Run: `bazel test //apps/desktop/vitruvian-atrium/Sources/VitruvianAtrium/Services/Switcher/...`
