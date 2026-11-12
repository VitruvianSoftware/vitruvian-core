# Services

## Overview
Component package providing implementation for `apps/desktop/vitruvian-atrium/Sources/VitruvianAtrium/Services`.

## Interface
- `[DockTileResolver.swift:DockTileResolver]`
- `[SelectedTextReader.swift:SelectedTextReader]`
- Subdirectory: [AgentUsage](./AgentUsage/README.md)
- Subdirectory: [AppUpdates](./AppUpdates/README.md)
- Subdirectory: [Audio](./Audio/README.md)
- Subdirectory: [AutoQuit](./AutoQuit/README.md)
- Subdirectory: [Bluetooth](./Bluetooth/README.md)
- Subdirectory: [Cleaner](./Cleaner/README.md)
- Subdirectory: [CleaningMode](./CleaningMode/README.md)
- Subdirectory: [Clipboard](./Clipboard/README.md)
- Subdirectory: [CommandBar](./CommandBar/README.md)
- Subdirectory: [DiskImageInstaller](./DiskImageInstaller/README.md)
- Subdirectory: [Display](./Display/README.md)
- Subdirectory: [DockClick](./DockClick/README.md)
- Subdirectory: [DockPreview](./DockPreview/README.md)
- Subdirectory: [FanControl](./FanControl/README.md)
- Subdirectory: [Feedback](./Feedback/README.md)
- Subdirectory: [Finder](./Finder/README.md)
- Subdirectory: [FocusFollowsMouse](./FocusFollowsMouse/README.md)
- Subdirectory: [Homebrew](./Homebrew/README.md)
- Subdirectory: [KeyboardDebounce](./KeyboardDebounce/README.md)
- Subdirectory: [KillProcess](./KillProcess/README.md)
- Subdirectory: [ManagedDownloads](./ManagedDownloads/README.md)
- Subdirectory: [Media](./Media/README.md)
- Subdirectory: [MenuBar](./MenuBar/README.md)
- Subdirectory: [MenuPanel](./MenuPanel/README.md)
- Subdirectory: [Metrics](./Metrics/README.md)
- Subdirectory: [MiddleClick](./MiddleClick/README.md)
- Subdirectory: [MouseAcceleration](./MouseAcceleration/README.md)
- Subdirectory: [MouseButtons](./MouseButtons/README.md)
- Subdirectory: [MouseClickDebounce](./MouseClickDebounce/README.md)
- Subdirectory: [MouseExceptions](./MouseExceptions/README.md)
- Subdirectory: [MouseNavigation](./MouseNavigation/README.md)
- Subdirectory: [Notch](./Notch/README.md)
- Subdirectory: [Platform](./Platform/README.md)
- Subdirectory: [PortManager](./PortManager/README.md)
- Subdirectory: [QuickTools](./QuickTools/README.md)
- Subdirectory: [QuitProtection](./QuitProtection/README.md)
- Subdirectory: [RadialMenu](./RadialMenu/README.md)
- Subdirectory: [Recorder](./Recorder/README.md)
- Subdirectory: [Settings](./Settings/README.md)
- Subdirectory: [Shelf](./Shelf/README.md)
- Subdirectory: [Snippets](./Snippets/README.md)
- Subdirectory: [SpacesOrder](./SpacesOrder/README.md)
- Subdirectory: [SuperKey](./SuperKey/README.md)
- Subdirectory: [Switcher](./Switcher/README.md)
- Subdirectory: [SystemMonitor](./SystemMonitor/README.md)
- Subdirectory: [Uninstall](./Uninstall/README.md)
- Subdirectory: [Update](./Update/README.md)
- Subdirectory: [Wallpaper](./Wallpaper/README.md)
- Subdirectory: [WindowLayout](./WindowLayout/README.md)

## Invariants
- [GeneralPasteboardAccess.swift:105]: `precondition(Thread.isMainThread)`
- [GeneralPasteboardAccess.swift:113]: `precondition(Thread.isMainThread)`
- [InstalledApps.swift:151]: `/// treats as installed) - this used to require the app sit directly in`
- [KeepAwakeManager.swift:36]: `package var assert: @MainActor (_ type: String, _ name: String) -> IOPMAssert...`
- [KeepAwakeManager.swift:66]: `assert: @escaping @MainActor (String, String) -> IOPMAssertionID?,`
- [KeepAwakeManager.swift:87]: `self.assert = assert`
- [ScrollWheelTarget.swift:22]: `precondition(Thread.isMainThread)`

## Side Effects
- [DetachedProcess.swift:24]: `/// Returns the child pid, or throws the spawn errno.`
- [DetachedProcess.swift:26]: `package static func spawn(_ executablePath: String, _ arguments: [String]) th...`
- [DetachedProcess.swift:71]: `/// disposition survives exec) instead of handing the decision back.`
- [FeatureRuntime.swift:127]: `guard (try? DetachedProcess.spawn(`
- [SelectedTextReader.swift:92]: `/// role query switches a Chromium app's renderers into full accessibility`
- [SelfUninstall.swift:463]: `// URLSession writes these on our behalf whenever the app talks to the`
- [ShellSupport.swift:94]: `/// other administrative tools retain their bounded subprocess behavior.`
- [WindowMaximizer.swift:298]: `/// An application element answers a role query by switching a Chromium app's`

## Verification
- Run: `bazel test //apps/desktop/vitruvian-atrium/Sources/VitruvianAtrium/Services/...`
