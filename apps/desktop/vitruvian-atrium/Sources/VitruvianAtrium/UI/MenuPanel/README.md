# Menupanel

## Overview
Component package providing implementation for `apps/desktop/vitruvian/Sources/Vitruvian/UI/MenuPanel`.

## Interface
- `[ClipboardClearRecentConfirmation.swift:ClipboardClearRecentConfirmation]`

## Invariants
- None

## Side Effects
- [PanelClipboardView.swift:14]: `@State private var query = ""`
- [PanelClipboardView.swift:43]: `history.filteredEntries(matching: query)`
- [PanelClipboardView.swift:47]: `query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty`
- [PanelHomebrewView.swift:16]: `@State private var query = ""`
- [PanelHomebrewView.swift:55]: `.onChange(of: query) { _, _ in resetContextSelection() }`
- [PanelHomebrewView.swift:190]: `PanelHomebrewSearchField(text: $query,`
- [PanelPortManagerView.swift:92]: `TextField(strings.filter, text: $service.query)`

## Verification
- Run: `bazel test //apps/desktop/vitruvian/Sources/Vitruvian/UI/MenuPanel/...`
