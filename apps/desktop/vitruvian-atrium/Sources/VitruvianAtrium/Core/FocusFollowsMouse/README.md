# Focusfollowsmouse

## Overview
Component package providing implementation for `apps/desktop/vitruvian-atrium/Sources/VitruvianAtrium/Core/FocusFollowsMouse`.

## Interface
- Internal implementation components

## Invariants
- [FocusFollowsMouseSupport.swift:59]: `// release their captured pointer, so require a known different window.`

## Side Effects
- [FocusFollowsMouseSupport.swift:17]: `/// before any query: entering our Accessibility tree from a worker can`
- [FocusFollowsMouseSupport.swift:24]: `query: (pid_t) -> Result?) -> Result? {`
- [FocusFollowsMouseSupport.swift:47]: `return query(processID)`

## Verification
- Run: `bazel test //apps/desktop/vitruvian-atrium/Sources/VitruvianAtrium/Core/FocusFollowsMouse/...`
