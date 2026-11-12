# Settings

## Overview
Component package providing implementation for `apps/desktop/vitruvian-atrium/Sources/VitruvianAtrium/UI/Settings`.

## Interface
- `[CodexAccountsSettings.swift:CodexAccountsSettings]`
- `[ExtensionSettingsPage.swift:SettingsSheetHeading]`
- `[ExtensionSettingsPage.swift:SettingsSheetNoMatch]`
- `[ExternalToolCatalogueSheet.swift:CatalogueRowView]`
- `[ExternalToolCatalogueSheet.swift:CatalogueSDKLineView]`
- `[ExternalToolsSection.swift:ExternalToolKindBadge]`
- `[ExternalToolsSection.swift:SettingsSheetMark]`
- `[MonitorToken.swift:MonitorTokenOption]`
- `[NotchContentEditor.swift:NotchPaneViewer]`
- `[NotchMascotSettings.swift:NotchMascotSettings]`
- `[NotchMascotSettings.swift:NotchMascotStageModel]`
- `[PastePlainSettingsSection.swift:PastePlainSettingsSection]`
- `[SettingsWindow.swift:SettingsWindow]`

## Invariants
- None

## Side Effects
- [CommandBarAppShortcutsView.swift:17]: `@State private var query = ""`
- [CommandBarAppShortcutsView.swift:46]: `TextField(l10n.s.uninstallerPickerSearch, text: $query)`
- [CommandBarAppShortcutsView.swift:49]: `if !query.isEmpty {`
- [DateVariableBuilder.swift:130]: `// Marked only when the query has actually settled one`
- [DateVariableBuilder.swift:131]: `// way or the other. A query that still matches several`
- [DateVariableBuilder.swift:146]: `// Lazy: a broad query like "america" matches well`
- [ExtensionSettingsPage.swift:20]: `@Binding var query: String`
- [ExtensionSettingsPage.swift:47]: `package init(index: SettingsSheetIndex, query: Binding<String>, height: CGFlo...`
- [ExtensionSettingsPage.swift:52]: `_query = query`
- [HomebrewSettings.swift:15]: `@State private var query = ""`

## Verification
- Run: `bazel test //apps/desktop/vitruvian-atrium/Sources/VitruvianAtrium/UI/Settings/...`
