# Autoquit

## Overview
Component package providing implementation for `apps/desktop/vitruvian/Sources/Vitruvian/Services/AutoQuit`.

## Interface
- Internal implementation components

## Invariants
- None

## Side Effects
- [AutoQuitSupport.swift:105]: `/// browsers) answers a role query on its application element by`
- [AutoQuitSupport.swift:309]: `/// even if it retains a title (#2696). A failed query proves nothing, and`

## Verification
- Run: `bazel test //apps/desktop/vitruvian/Sources/Vitruvian/Services/AutoQuit/...`
