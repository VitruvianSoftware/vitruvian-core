# Couriercore

## Overview
Component package providing implementation for `apps/desktop/courier/app/Sources/CourierCore`.

## Interface
- `[AIProvider.swift:AIRewriteTone]`
- `[AIProvider.swift:AIProviderDisposition]`
- `[AIProvider.swift:AIProvider]`
- `[AIProvider.swift:UnavailableAIProvider]`
- `[AIProvider.swift:AIPreferences]`
- `[AccountsAndBridgesModel.swift:DockTileService]`
- `[AccountsAndBridgesModel.swift:MACDockTileService]`
- `[AccountsAndBridgesModel.swift:RemoveAccountConfirmation]`
- `[AccountsAndBridgesModel.swift:AccountsAndBridgesModel]`
- `[AppIconRenderer.swift:CourierAppIconVariant]`
- `[AppIconRenderer.swift:AppIconApplyError]`
- `[AppIconRenderer.swift:AppIconApplying]`
- `[AppIconRenderer.swift:MACAppIconApplier]`
- `[AppIconRenderer.swift:AppIconRenderer]`
- `[AppModel.swift:PendingMessage]`
- `[AppModel.swift:AppModel]`
- `[AppearancePreferences.swift:ThemeMode]`
- `[AppearancePreferences.swift:CourierThemePreset]`
- `[AppearancePreferences.swift:CourierWallpaperPreset]`
- `[AppearancePreferences.swift:FontSizeScale]`
- Subdirectory: [AI](./AI/README.md)

## Invariants
- [EngineSupervisor.swift:15]: `/// - Any exit the app did not ask for is a crash, whatever its status (a Go ...`
- [ProblemReportModel.swift:10]: `/// strip home directory paths (`/Users/<name>`), phone numbers, tokens, quot...`
- [ProblemReportModel.swift:23]: `"panic", "stack",`
- [ProblemReportModel.swift:32]: `"trace", "debug", "info", "warn", "error", "fatal", "panic",`
- [SettingsSearchModel.swift:332]: `title: "Require Touch ID authentication on launch",`

## Side Effects
- [AccountsAndBridgesModel.swift:242]: `case "whatsapp": return "net.whatsapp.WhatsApp"`
- [AttachmentCarouselModel.swift:7]: `/// Returns true only when `path` is a local filesystem path (never a remote ...`
- [AttachmentCarouselModel.swift:12]: `if lower.hasPrefix("http://") || lower.hasPrefix("https://") || lower.hasPref...`
- [AttachmentDownloader.swift:48]: `!lower.hasPrefix("http://"),`
- [AudioPlayerModel.swift:283]: `if lowered.hasPrefix("http://")`
- [ChatFeatures.swift:184]: `/// The first link in a message, for Open Link (⌘⇧H): a link range's address,...`
- [ChatFeatures.swift:197]: `guard let url = match.url, ["http", "https", "mailto"].contains(url.scheme?.l...`
- [CommandBarModel.swift:18]: `@Published public var query: String = "" {`
- [CommandBarModel.swift:84]: `query = initialQuery`
- [CommandBarModel.swift:95]: `query = initialQuery`

## Verification
- Run: `bazel test //apps/desktop/courier/app/Sources/CourierCore/...`
