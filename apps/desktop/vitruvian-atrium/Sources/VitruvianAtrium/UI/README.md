# Ui

## Overview
Component package providing implementation for `apps/desktop/vitruvian-atrium/Sources/VitruvianAtrium/UI`.

## Interface
- Internal implementation components
- Subdirectory: [AppUpdates](./AppUpdates/README.md)
- Subdirectory: [CameraPreview](./CameraPreview/README.md)
- Subdirectory: [Cleaner](./Cleaner/README.md)
- Subdirectory: [CleaningMode](./CleaningMode/README.md)
- Subdirectory: [CommandBar](./CommandBar/README.md)
- Subdirectory: [Feedback](./Feedback/README.md)
- Subdirectory: [Finder](./Finder/README.md)
- Subdirectory: [KillProcess](./KillProcess/README.md)
- Subdirectory: [Media](./Media/README.md)
- Subdirectory: [MenuPanel](./MenuPanel/README.md)
- Subdirectory: [Notch](./Notch/README.md)
- Subdirectory: [Onboarding](./Onboarding/README.md)
- Subdirectory: [PortManager](./PortManager/README.md)
- Subdirectory: [QuickLauncher](./QuickLauncher/README.md)
- Subdirectory: [RadialMenu](./RadialMenu/README.md)
- Subdirectory: [Recorder](./Recorder/README.md)
- Subdirectory: [Scratchpad](./Scratchpad/README.md)
- Subdirectory: [Screenshot](./Screenshot/README.md)
- Subdirectory: [Settings](./Settings/README.md)
- Subdirectory: [Shelf](./Shelf/README.md)
- Subdirectory: [Switcher](./Switcher/README.md)
- Subdirectory: [ToolPanels](./ToolPanels/README.md)
- Subdirectory: [Uninstall](./Uninstall/README.md)

## Invariants
- None

## Side Effects
- [SnippetLibraryView.swift:35]: `.onChange(of: library.query) { _, _ in`
- [SnippetLibraryView.swift:47]: `TextField(text.librarySearchPlaceholder, text: $library.query)`
- [SnippetLibraryView.swift:51]: `if !library.query.isEmpty {`

## Verification
- Run: `bazel test //apps/desktop/vitruvian-atrium/Sources/VitruvianAtrium/UI/...`
