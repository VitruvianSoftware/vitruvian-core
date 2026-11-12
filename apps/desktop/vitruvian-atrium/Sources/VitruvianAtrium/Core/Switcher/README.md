# Switcher

## Overview
Component package providing implementation for `apps/desktop/vitruvian/Sources/Vitruvian/Core/Switcher`.

## Interface
- Internal implementation components

## Invariants
- None

## Side Effects
- [SpaceHopSupport.swift:104]: `/// The windows a window query's answer tags as hidden with their app. A`
- [SwitcherSupport.swift:378]: `package static func topInset(query: String, isPinned: Bool, contentPadding: C...`
- [SwitcherSupport.swift:379]: `guard !query.isEmpty || isPinned else { return 0 }`

## Verification
- Run: `bazel test //apps/desktop/vitruvian/Sources/Vitruvian/Core/Switcher/...`
