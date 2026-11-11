# Uninstall

## Overview
Component package providing implementation for `apps/desktop/vitruvian/Sources/Vitruvian/UI/Uninstall`.

## Interface
- Internal implementation components

## Invariants
- None

## Side Effects
- [AppPickerView.swift:13]: `@State private var query = ""`
- [AppPickerView.swift:51]: `let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)`
- [AppPickerView.swift:63]: `TextField(l10n.s.uninstallerPickerSearch, text: $query)`

## Verification
- Run: `bazel test //apps/desktop/vitruvian/Sources/Vitruvian/UI/Uninstall/...`
