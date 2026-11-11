# Vitruviancode

## Overview
Component package providing implementation for `apps/desktop/vitruvian-code/macos/Sources/VitruvianCode`.

## Interface
- `[App.swift:VitruvianCodeApp]`
- `[App.swift:AppState]`
- `[BackgroundNotifications.swift:BackgroundNotificationManager]`
- `[BotManager.swift:BotManager]`
- `[ChatWindowController.swift:QuickPromptPanel]`
- `[ChatWindowController.swift:QuickPromptWindowController]`
- `[ConfigManager.swift:CLIProvider]`
- `[ConfigManager.swift:ConfigManager]`
- `[ConfigManager.swift:AgyInfo]`
- `[SettingsView.swift:SettingsView]`
- `[SettingsView.swift:TimelineSideToggle]`
- `[SettingsView.swift:ProviderRow]`
- `[SettingsView.swift:HotkeyRecorderView]`
- `[SettingsView.swift:KeyEventCatcher]`
- `[SettingsView.swift:KeyCatcherView]`
- `[SettingsView.swift:AboutTabView]`
- `[StandaloneEngine.swift:StandaloneEngine]`
- `[StandaloneHost.swift:StandaloneHost]`
- `[StatusView.swift:StatusView]`
- `[UpdateChecker.swift:UpdateChecker]`

## Invariants
- None

## Side Effects
- [UpdateChecker.swift:49]: `let (data, response) = try await URLSession.shared.data(for: request)`
- [UpdateChecker.swift:57]: `throw URLError(.badServerResponse, userInfo: [NSLocalizedDescriptionKey: "Ser...`
- [UpdateChecker.swift:96]: `// If assets were still uploading during the initial check, try to fetch them...`

## Verification
- Run: `bazel test //apps/desktop/vitruvian-code/macos/Sources/VitruvianCode/...`
