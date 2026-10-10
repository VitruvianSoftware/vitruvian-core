// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import VitruvianCore
import VitruvianDesign

/// Pastes the clipboard as plain text on a global shortcut: strips fonts,
/// colors and links, pastes, and quietly puts the original rich content back
/// so later normal pastes keep their formatting. Requires Accessibility for
/// the synthesized ⌘V.
@MainActor
package final class PastePlainService: ObservableObject {
    @Published package private(set) var shortcutRegistrationFailed = false

    private let services: ToolServices

    /// The permission prompt fires at most once per launch, so a shortcut
    /// mashed without Accessibility nags once instead of five times.
    private var promptedForAccessibility = false

    package init(services: ToolServices) {
        self.services = services
    }

    /// Takes the shortcut. The tool host calls this each time it finds the
    /// tool installed and switched on, with or without Accessibility, so a
    /// second call only asks for the key it already holds. It is also how
    /// the key comes back after a shortcut recording let every key go, and
    /// how a newly recorded combination is taken.
    package func start() {
        services.hotkey.bind(.pastePlain,
                             onPress: { [weak self] in self?.pastePlainText() },
                             onRegistered: { [weak self] given in self?.shortcutRegistrationFailed = !given })
    }

    package func stop() {
        services.hotkey.unbind(.pastePlain)
        shortcutRegistrationFailed = false
    }

    package func canRun(_ command: CommandID) -> Bool {
        command == Self.paste
    }

    package func run(_ command: CommandID) {
        guard command == Self.paste else { return }
        pastePlainText()
    }

    /// One press of the shortcut, or one run of the command bar's row.
    private func pastePlainText() {
        // Without Accessibility the synthesized ⌘V can never be posted: say so
        // (system prompt once, a beep after) instead of silently swallowing the
        // shortcut, which reads as "the feature does nothing" (issue #186).
        // Asked before anything is read.
        if let refusal = services.keystrokes.refusal {
            guard case .notGranted = refusal else { return }
            if promptedForAccessibility {
                services.notify.beep()
            } else {
                promptedForAccessibility = true
                services.keystrokes.requestGrant()
            }
            return
        }
        services.clipboard.readPlainText { [weak self] plain in
            guard let plain, !plain.isEmpty else { return }
            self?.pastePlain(plain)
        }
    }

    private func pastePlain(_ plain: String) {
        // An app that ships its own matching-style paste does this better
        // than any synthesized ⌘V: the destination decides the typing
        // attributes (a stripped string pasted normally can leave the
        // insertion point stuck with the styling of what it landed in,
        // issue #349), the pasteboard keeps the original formatting for
        // later pastes, and held modifier keys don't matter to a menu
        // press. The strip-and-restore dance below stays as the fallback
        // for every app without that command.
        if case .success(true) = services.keystrokes.pressFrontAppMenuItem(
            matching: [QuickToolsSupport.matchStyleEquivalent]) { return }

        // The paste types ⌘V. When ⌘V is this tool's own shortcut, the paste
        // lets go of it while it types and takes it again after.
        services.keystrokes.paste(plain)
    }
}

extension PastePlainService: BundledTool {
    /// Pastes the clipboard as plain text, once. The shortcut runs it, and
    /// so does the command bar's row. It asks for no surface: the row is the
    /// bar's own, and the shortcut is a `GlobalShortcutRole`.
    package static let paste: CommandID = {
        guard let id = ToolID(AppFeature.pastePlain.rawValue),
              let command = CommandID(tool: id, name: "paste")
        else { preconditionFailure("Paste as plain text's command is not valid") }
        return command
    }()

    package static let manifest: ToolManifest = {
        let feature = AppFeature.pastePlain
        guard let command = CommandDescriptor(id: paste, title: feature.rawValue, symbol: feature.symbolName,
                                              surfaces: []),
              let tool = ToolDescriptor(id: paste.tool, name: feature.rawValue, symbol: feature.symbolName,
                                        commands: [command]),
              let shortcut = CapabilityRequest(.hotkey, reason: "Pastes as plain text when you press its shortcut."),
              // It starts without Accessibility: the shortcut is taken at
              // once, and the first press asks.
              let keys = CapabilityRequest(
                  .keystrokes,
                  reason: "Presses Paste and Match Style in the app in front, or types the paste for you.",
                  startsWithoutGrant: true),
              let read = CapabilityRequest(.clipboardRead, reason: "Reads what you copied, to paste its text."),
              let say = CapabilityRequest(.notify, reason: "Beeps when it cannot paste."),
              let manifest = ToolManifest(
                  tool: tool, group: feature.group, capabilities: [shortcut, keys, read, say],
                  preferences: [
                      PreferenceDeclaration(key: DefaultsKey.pastePlainEnabled, default: .bool(false)),
                      PreferenceDeclaration(key: DefaultsKey.pastePlainShortcut,
                                            default: .string(GlobalShortcut.pastePlainDefault.storageValue)),
                  ],
                  activation: [.onLaunch, .onCommand], enabledBy: DefaultsKey.pastePlainEnabled)
        else { preconditionFailure("Paste as plain text's manifest is not valid") }
        return manifest
    }()
}
