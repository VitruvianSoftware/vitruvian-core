// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import AppKit
import VitruvianCore
import VitruvianDesign

/// Puts the app's own tools in the registry: one tool per hub feature, and a
/// handler for each built-in command. This is the only place that knows
/// which service call a built-in command runs.
@MainActor
package enum BuiltinTools {
    /// Called once from `main.swift`, before anything can present. Safe to
    /// call again: a tool already there is left alone.
    package static func install(into registry: ToolRegistry = .shared) {
        for feature in AppFeature.allCases {
            guard let id = ToolID(feature.rawValue), registry.tool(id) == nil else { continue }
            let commands = BuiltinCommand.allCases.filter { $0.feature == feature }.map { command in
                CommandDescriptor(id: command.id, title: feature.rawValue, symbol: feature.symbolName,
                                  surfaces: [.radial, .quickPanel])
            }
            guard let tool = ToolDescriptor(id: id, name: feature.rawValue, symbol: feature.symbolName,
                                            commands: commands) else { continue }
            try? registry.register(tool)
            try? registry.setName(titleProvider(for: feature), for: id)
            for command in BuiltinCommand.allCases where command.feature == feature {
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
