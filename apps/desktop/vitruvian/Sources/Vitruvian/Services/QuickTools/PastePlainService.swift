// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import ApplicationServices
import VitruvianCore
import VitruvianDesign

/// Pastes the clipboard as plain text on a global shortcut: strips fonts,
/// colors and links, pastes, and quietly puts the original rich content back
/// so later normal pastes keep their formatting. Requires Accessibility for
/// the synthesized ⌘V.
@MainActor
package final class PastePlainService: ObservableObject {
    package static let shared = PastePlainService(environment: .live)

    /// What the service reaches outside itself. The app's is the saved
    /// preferences, hotkey 10, Accessibility, the clipboard lane, the front
    /// app's menus and the paste helper. A test passes doubles, so it
    /// registers no key, asks macOS nothing and touches no clipboard.
    package struct Environment {
        /// Where the hub's switch, this feature's own switch and its
        /// shortcut are saved.
        package var defaults: UserDefaults
        package var hotkey: ToolHotkey
        /// Whether Accessibility is granted at this instant.
        package var isTrusted: () -> Bool
        package var beep: () -> Void
        /// The system's Accessibility prompt and the app's guide.
        package var requestAccessibility: () -> Void
        /// Reads the clipboard on its lane.
        package var clipboard: ClipboardWatcher
        package var menu: FrontAppMenu
        /// The paste helper: the text, what to do just before Command-V
        /// goes down, and what to do once it is up.
        package var paste: (_ text: String, _ willPost: @escaping () -> Void, _ didPost: @escaping () -> Void) -> Void

        package init(defaults: UserDefaults, hotkey: ToolHotkey, isTrusted: @escaping () -> Bool,
                     beep: @escaping () -> Void, requestAccessibility: @escaping () -> Void,
                     clipboard: ClipboardWatcher, menu: FrontAppMenu,
                     paste: @escaping (String, @escaping () -> Void, @escaping () -> Void) -> Void) {
            self.defaults = defaults
            self.hotkey = hotkey
            self.isTrusted = isTrusted
            self.beep = beep
            self.requestAccessibility = requestAccessibility
            self.clipboard = clipboard
            self.menu = menu
            self.paste = paste
        }

        @MainActor package static let live = Environment(
            defaults: .standard,
            hotkey: QuickToolHotkey(id: 10),
            isTrusted: { AXIsProcessTrusted() },
            beep: { NSSound.beep() },
            requestAccessibility: { Permissions.shared.requestAccessibility() },
            clipboard: ClipboardWatcher(environment: .live),
            menu: FrontAppMenu(environment: .live),
            paste: { text, willPost, didPost in
                _ = TransientPaste.shared.paste(text, willPostShortcut: willPost, didPostShortcut: didPost)
            })
    }

    @Published package private(set) var shortcutRegistrationFailed = false

    private let environment: Environment

    /// The permission prompt fires at most once per launch, so a shortcut
    /// mashed without Accessibility nags once instead of five times.
    private var promptedForAccessibility = false

    package init(environment: Environment) {
        self.environment = environment
        environment.hotkey.onPress = { [weak self] in self?.performPastePlain() }
    }

    /// The saved shortcut, or the default when none is saved or it cannot
    /// be read.
    private var savedShortcut: GlobalShortcut {
        GlobalShortcut(storageValue: environment.defaults[Preferences.pastePlainShortcut]) ?? .pastePlainDefault
    }

    package func syncWithPreferences() {
        let enabled = AppFeature.pastePlain.isAvailable(in: environment.defaults)
            && environment.defaults[Preferences.pastePlainEnabled]
        shortcutRegistrationFailed = !environment.hotkey.sync(enabled: enabled, shortcut: savedShortcut,
                                                              storageKey: DefaultsKey.pastePlainShortcut)
    }

    package func suspend() {
        environment.hotkey.unregister()
    }

    package func performPastePlain() {
        // Without Accessibility the synthesized ⌘V can never be posted: say so
        // (system prompt once, a beep after) instead of silently swallowing the
        // shortcut, which reads as "the feature does nothing" (issue #186).
        guard environment.isTrusted() else {
            if promptedForAccessibility {
                environment.beep()
            } else {
                promptedForAccessibility = true
                environment.requestAccessibility()
            }
            return
        }
        environment.clipboard.readPlainText { [weak self] plain in
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
        if environment.menu.pressItem(matching: [QuickToolsSupport.matchStyleEquivalent]) { return }

        var releaseHotkey = false
        environment.paste(
            plain,
            { [weak self] in
                guard let self else { return }
                releaseHotkey = self.savedShortcut.isStandardPasteCommand
                if releaseHotkey { self.environment.hotkey.unregister() }
            },
            { [weak self] in
                if releaseHotkey { self?.syncWithPreferences() }
            })
    }
}
