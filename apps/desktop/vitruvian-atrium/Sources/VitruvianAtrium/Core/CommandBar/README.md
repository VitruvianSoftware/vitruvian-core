# Commandbar

## Overview
Component package providing implementation for `apps/desktop/vitruvian-atrium/Sources/VitruvianAtrium/Core/CommandBar`.

## Interface
- Internal implementation components

## Invariants
- None

## Side Effects
- [CommandBarSupport.swift:45]: `query: String,`
- [CommandBarSupport.swift:49]: `return query.trimmingCharacters(in: .whitespaces).isEmpty`
- [CommandBarSupport.swift:148]: `/// A deliberate preference, such as an alias or learned query choice,`

## Verification
- Run: `bazel test //apps/desktop/vitruvian-atrium/Sources/VitruvianAtrium/Core/CommandBar/...`
