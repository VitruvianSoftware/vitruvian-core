# Commandbar

## Overview
Component package providing implementation for `apps/desktop/vitruvian-atrium/Sources/VitruvianAtrium/UI/CommandBar`.

## Interface
- Internal implementation components

## Invariants
- None

## Side Effects
- [CommandBarView.swift:208]: `.onChange(of: service.query) { _, query in`
- [CommandBarView.swift:209]: `if !query.isEmpty { CommandBarDroplet.shared.typed(keyCode: nil, presentation...`
- [CommandBarView.swift:267]: `TextField(fieldPlaceholder, text: $service.query)`

## Verification
- Run: `bazel test //apps/desktop/vitruvian-atrium/Sources/VitruvianAtrium/UI/CommandBar/...`
