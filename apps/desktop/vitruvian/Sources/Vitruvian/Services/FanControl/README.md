# Fancontrol

## Overview
Component package providing implementation for `apps/desktop/vitruvian/Sources/Vitruvian/Services/FanControl`.

## Interface
- Internal implementation components

## Invariants
- [FanControlService.swift:260]: `/// macOS may require approval again even when registration succeeds.`

## Side Effects
- None

## Verification
- Run: `bazel test //apps/desktop/vitruvian/Sources/Vitruvian/Services/FanControl/...`
