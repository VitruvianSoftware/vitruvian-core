# Mouseacceleration

## Overview
Component package providing implementation for `apps/desktop/vitruvian-atrium/Sources/VitruvianAtrium/Services/MouseAcceleration`.

## Interface
- Internal implementation components

## Invariants
- None

## Side Effects
- [MouseAccelerationGuard.swift:30]: `"IFS= read -r _; exec \"$1\" \"$2\"",`

## Verification
- Run: `bazel test //apps/desktop/vitruvian-atrium/Sources/VitruvianAtrium/Services/MouseAcceleration/...`
