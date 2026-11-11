# Quicktools

## Overview
Component package providing implementation for `apps/desktop/vitruvian/Sources/Vitruvian/Core/QuickTools`.

## Interface
- Internal implementation components

## Invariants
- None

## Side Effects
- [QuickToolsSupport.swift:254]: `/// http and https on purpose: a scanned code must never be able to launch`
- [QuickToolsSupport.swift:262]: `scheme == "http" || scheme == "https",`
- [ScreenshotSharingSupport.swift:126]: `components.query == nil,`

## Verification
- Run: `bazel test //apps/desktop/vitruvian/Sources/Vitruvian/Core/QuickTools/...`
