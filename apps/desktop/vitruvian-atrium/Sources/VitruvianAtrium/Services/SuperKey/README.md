# Superkey

## Overview
Component package providing implementation for `apps/desktop/vitruvian/Sources/Vitruvian/Services/SuperKey`.

## Interface
- Internal implementation components

## Invariants
- None

## Side Effects
- [SuperKeyMappingGuard.swift:33]: `"IFS= read -r _; exec \"$1\" \"$2\" \"$3\"",`

## Verification
- Run: `bazel test //apps/desktop/vitruvian/Sources/Vitruvian/Services/SuperKey/...`
