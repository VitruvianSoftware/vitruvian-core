// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import AppKit
import VitruvianCore
import VitruvianDesign

/// Puts the app's own tools in the registry: one tool per hub feature, and a
/// handler for each command. This is the only place that knows which service
/// call a built-in command runs. A feature that has become a tool is
/// registered from its manifest, and its commands run through the tool host.
@MainActor
package enum BuiltinTools {
    /// Called once from `main.swift`, before anything can present. Safe to
    /// call again: a tool already there is left alone.
    ///
    /// `tools` are the features that have become tools. `host` is asked for
    /// only when one of their commands is run or asked whether it can run,
    /// never here: installing builds no host, no broker and no tool.
    package static func install(into registry: ToolRegistry = .shared,
                                tools: [any BundledTool.Type] = BundledTools.all,
                                host: @escaping @MainActor () -> ToolHost = { .shared }) {
        var manifests: [ToolID: ToolManifest] = [:]
        for type in tools { manifests[type.manifest.id] = type.manifest }
        // A built-in command asks for the panel only when a tile runs it:
        // the others have no tile today, and listing them would put new
        // tiles in front of everyone.
        let tiled = Set(QuickLauncherItem.allCases.compactMap(\.command))
        for feature in AppFeature.allCases {
            guard let id = ToolID(feature.rawValue), registry.tool(id) == nil else { continue }
            // A feature that has become a tool says what it is in its
            // manifest, and its commands run through the tool host. Its
            // commands are the manifest's alone: it has no `BuiltinCommand`.
            if let manifest = manifests[id] {
                try? registry.register(manifest.tool)
                try? registry.setName(titleProvider(for: feature), for: id)
                for command in manifest.tool.commands {
                    try? registry.setHandler(.init(title: titleProvider(for: feature),
                                                   isRunnable: { host().canRun(command.id) },
                                                   run: { host().run(command.id) }),
                                             for: command.id)
                }
                continue
            }
            let own = BuiltinCommand.allCases.filter { $0.feature == feature }
            let commands = own.compactMap { command in
                CommandDescriptor(id: command.id, title: feature.rawValue, symbol: feature.symbolName,
                                  surfaces: tiled.contains(command) ? [.radial, .quickPanel] : [.radial])
            }
            guard commands.count == own.count,
                  let tool = ToolDescriptor(id: id, name: feature.rawValue, symbol: feature.symbolName,
                                            commands: commands) else {
                assertionFailure("the built-in tool \(feature.rawValue) could not be described")
                continue
            }
            try? registry.register(tool)
            try? registry.setName(titleProvider(for: feature), for: id)
            for command in own {
                try? registry.setHandler(handler(for: command), for: command.id)
            }
        }
    }

    /// A built-in command is titled after its feature, as the radial menu
    /// and the Quick panel title it today.
    private static func titleProvider(for feature: AppFeature) -> @MainActor (AppLanguage) -> String {
        { language in feature.hubTitle(Strings.localized(language), hub: FeatureStrings.hub(language)) }
    }

    private static func openSettings(at page: SettingsPage) {
        SettingsRouter.shared.page = page
        appShell()?.openSettingsWindow()
    }

    /// Exhaustive on purpose: a new `BuiltinCommand` does not compile until
    /// it says what it runs.
    private static func handler(for command: BuiltinCommand) -> ToolRegistry.Handler {
        let title = titleProvider(for: command.feature)
        switch command {
        case .screenshotCapture:
            return .init(title: title, run: { ScreenshotService.shared.capture() })
        case .screenRecorderToggle:
            return .init(title: title, run: { ScreenRecorderService.shared.toggle() })
        case .colorPickerPick:
            return .init(title: title, run: { ColorSamplerService.shared.pick() })
        case .screenOCRCapture:
            return .init(title: title, run: { ScreenTextService.shared.capture() })
        case .micMuteToggle:
            return .init(title: title, run: { MicMuteService.shared.toggle() })
        case .clipboardHistoryShow:
            return .init(title: title, run: { ClipboardHistoryService.shared.showHistoryWindow() })
        case .quickLauncherShow:
            return .init(title: title, run: { QuickLauncherService.shared.show() })
        case .cameraPreviewShow:
            return .init(title: title, run: { CameraPreviewService.shared.show() })
        case .scratchpadShow:
            return .init(title: title, run: { ScratchpadService.shared.show() })
        case .shelfSummon:
            // Hub availability and Shelf's own switch are separate: a saved
            // slice stays dormant while Shelf is off and returns with it.
            return .init(title: title,
                         isRunnable: { UserDefaults.standard[Preferences.shelfEnabled] },
                         run: { ShelfService.shared.summon() })
        case .cleanerOpen:
            return .init(title: title, run: { openSettings(at: .cleaner) })
        case .uninstallerOpen:
            return .init(title: title, run: { openSettings(at: .uninstaller) })
        case .appUpdatesCheck:
            return .init(title: title, run: {
                AppUpdatesService.shared.check()
                openSettings(at: .appUpdates)
            })
        case .cleaningModeActivate:
            return .init(title: title, run: { CleaningModeManager.shared.activate() })
        case .keepAwakeToggle:
            return .init(title: title, run: { KeepAwakeManager.shared.toggle() })
        }
    }
}
