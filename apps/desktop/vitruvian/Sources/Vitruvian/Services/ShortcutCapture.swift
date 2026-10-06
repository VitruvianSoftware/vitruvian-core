// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Foundation
import VitruvianCore
import VitruvianDesign

/// Keeps the app's own global shortcuts quiet while the user is recording a
/// new one. Without this, typing a combination the app already answers to
/// fires that feature instead of landing in the field, so the one shortcut a
/// user most wants to change is the one they cannot type.
///
/// The state is a plain flag rather than a counter on purpose. Two fields can
/// never listen at once (only one view holds the keyboard), and if the two
/// ever disagreed, the safe outcome is shortcuts coming back on early, never
/// shortcuts left dead. `end` is therefore idempotent and every exit from
/// recording calls it: a capture, Escape, losing focus, the window closing,
/// the view going away and the app losing front.
@MainActor
package enum ShortcutCapture {
    package private(set) static var isCapturing = false

    /// Releases every global key the app holds. Main thread only, like the
    /// services it drives.
    package static func begin() {
        guard !isCapturing else { return }
        isCapturing = true
        // A flag inside the routing, not a teardown: rebuilding the tap per
        // recording would churn the system keyboard path (issue #275).
        AppSwitcher.shared.setCapturingShortcut(true)
        HotkeyManager.shared.setEnabled(false)
        ShelfService.shared.suspendShortcut()
        ClipboardHistoryService.shared.suspendShortcut()
        SoundOutputSwitcher.shared.suspendShortcut()
        WindowLayoutService.shared.suspendShortcuts()
        QuickToolHotkey.unregisterAll()
    }

    /// Gives every key back. Safe to call when nothing was suspended, and safe
    /// to call twice; the features re-read their own preferences, so a feature
    /// switched off in the meantime simply stays off.
    package static func end() {
        guard isCapturing else { return }
        isCapturing = false
        AppSwitcher.shared.setCapturingShortcut(false)
        FeatureRuntime.shared.sync(GlobalShortcutRole.featuresToSilenceWhileRecording)
    }
}

/// What a listening shortcut field holds: the app's own global keys stepped
/// aside, and the recording tap ahead of the app's menu, without which Command
/// Q never reaches the field and quits Vitruvian instead (issue #1193).
/// Settings' shortcut fields and the Command Bar's capture card both listen
/// through this one pair, and leaving gives every key back.
@MainActor
package struct ShortcutListening {
    package typealias KeyHandler = (Int64, GlobalShortcutModifiers, CGEventFlags) -> Void

    private let suspendKeys: () -> Void
    private let startTap: (@escaping KeyHandler) -> Bool
    private let stopTap: () -> Void
    private let restoreKeys: () -> Void

    // Spelled out because a memberwise initializer never leaves its module.
    package init(suspendKeys: @escaping () -> Void,
                 startTap: @escaping (@escaping KeyHandler) -> Bool,
                 stopTap: @escaping () -> Void,
                 restoreKeys: @escaping () -> Void) {
        self.suspendKeys = suspendKeys
        self.startTap = startTap
        self.stopTap = stopTap
        self.restoreKeys = restoreKeys
    }

    /// `ShortcutCapture` and `ShortcutRecordingTap`.
    package static var live: ShortcutListening {
        ShortcutListening(suspendKeys: { ShortcutCapture.begin() },
                          startTap: { ShortcutRecordingTap.begin($0) },
                          stopTap: { ShortcutRecordingTap.end() },
                          restoreKeys: { ShortcutCapture.end() })
    }

    /// Takes every key, then starts the tap. Answers whether the tap could
    /// start; without Accessibility it cannot, and the field's own events
    /// still record as before.
    @discardableResult
    package func begin(_ handler: @escaping KeyHandler) -> Bool {
        suspendKeys()
        return startTap(handler)
    }

    /// Stops the tap, then gives every key back. Safe to call twice, and when
    /// the tap never started.
    package func end() {
        stopTap()
        restoreKeys()
    }
}
