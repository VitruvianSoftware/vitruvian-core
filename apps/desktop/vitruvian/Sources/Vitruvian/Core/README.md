# Core

## Overview
Component package providing implementation for `apps/desktop/vitruvian/Sources/Vitruvian/Core`.

## Interface
- Internal implementation components
- Subdirectory: [AgentUsage](./AgentUsage/README.md)
- Subdirectory: [AppUpdates](./AppUpdates/README.md)
- Subdirectory: [Audio](./Audio/README.md)
- Subdirectory: [Cleaner](./Cleaner/README.md)
- Subdirectory: [CommandBar](./CommandBar/README.md)
- Subdirectory: [Display](./Display/README.md)
- Subdirectory: [DockPreview](./DockPreview/README.md)
- Subdirectory: [FocusFollowsMouse](./FocusFollowsMouse/README.md)
- Subdirectory: [Homebrew](./Homebrew/README.md)
- Subdirectory: [Localizations](./Localizations/README.md)
- Subdirectory: [Media](./Media/README.md)
- Subdirectory: [MenuBar](./MenuBar/README.md)
- Subdirectory: [Metrics](./Metrics/README.md)
- Subdirectory: [MouseButtons](./MouseButtons/README.md)
- Subdirectory: [MouseExceptions](./MouseExceptions/README.md)
- Subdirectory: [Notch](./Notch/README.md)
- Subdirectory: [Platform](./Platform/README.md)
- Subdirectory: [QuickTools](./QuickTools/README.md)
- Subdirectory: [RadialMenu](./RadialMenu/README.md)
- Subdirectory: [Recorder](./Recorder/README.md)
- Subdirectory: [Settings](./Settings/README.md)
- Subdirectory: [Shelf](./Shelf/README.md)
- Subdirectory: [SuperKey](./SuperKey/README.md)
- Subdirectory: [Switcher](./Switcher/README.md)
- Subdirectory: [Update](./Update/README.md)
- Subdirectory: [WindowLayout](./WindowLayout/README.md)

## Invariants
- [KillProcessStrings.swift:94]: `killFailedMessage: "The process may have already exited or require additional...`
- [NotchMusicExtrasStrings.swift:82]: `automationExplanation: "Some music apps require permission for their playback...`
- [QuitProtectionStrings.swift:89]: `extraModifier: "Require extra modifier",`

## Side Effects
- [ExternalToolStrings.swift:208]: `package func noSettingsMatch(_ query: String) -> String {`
- [ExternalToolStrings.swift:209]: `String(format: noSettingsMatchFormat, locale: Locale.current, query)`
- [RadialMenuStrings.swift:222]: `fetchFaviconButton: "Fetch Website Icon",`
- [URLCleaning.swift:34]: `// both because it matches the raw query with regex.`
- [URLCleaning.swift:167]: `(scheme == "http" || scheme == "https"),`
- [URLCleaning.swift:174]: `// re-encode existing escapes when a query also contains literal Unicode.`

## Verification
- Run: `bazel test //apps/desktop/vitruvian/Sources/Vitruvian/Core/...`
