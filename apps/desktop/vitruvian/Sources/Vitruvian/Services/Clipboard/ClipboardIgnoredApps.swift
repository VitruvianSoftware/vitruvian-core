// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Combine
import Foundation
import VitruvianCore
import VitruvianDesign

/// Apps whose copies never reach the clipboard history (issue #423).
///
/// The pasteboard says what was copied, never who copied it, so the app has to
/// be worked out from who had the screen at the time. The history reads the
/// pasteboard on a timer, which means a copy is only ever noticed some time
/// after it happened, and by then the person may already be in the app they
/// went to paste into. Asking only who is in front at that moment would name
/// the wrong app exactly in the case this list exists for, since the windows
/// that hold passwords usually close themselves the instant something is
/// copied.
///
/// So instead of one guess, every app that came to the front since the last
/// look is kept, and the copy is left out when any of them is on the list. The
/// window is under a second, and leaving out one copy too many is the harmless
/// side of being wrong here. The same window names the app a copy came from,
/// but only when a single app held the front through it.
@MainActor
package final class ClipboardIgnoredApps: ObservableObject {
    package static let shared = ClipboardIgnoredApps()

    @Published package private(set) var apps: [String] = []

    /// The same list as a set, for the question the history asks.
    private var lookup: Set<String> = []
    /// What happened since the history last looked at the pasteboard.
    private var window = ClipboardSourceWindow(ownBundleID: Bundle.main.bundleIdentifier)
    private var activationObserver: NSObjectProtocol?
    /// True while the history itself is running, the only time the observer
    /// lives.
    private var historyIsRunning = false

    private init() {
        reload()
    }

    // MARK: - The list

    package func reload() {
        let defaults = UserDefaults.standard
        let raw = defaults[Preferences.clipboardHistoryIgnoredApps]
        let sanitized = Defaults.sanitizedBundleIdentifierList(raw)
        if raw != sanitized {
            defaults[Preferences.clipboardHistoryIgnoredApps] = sanitized
        }
        apps = sanitized
        lookup = Set(sanitized)
    }

    package func add(_ bundleID: String) {
        let bundleID = bundleID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !bundleID.isEmpty, !apps.contains(bundleID) else { return }
        UserDefaults.standard[Preferences.clipboardHistoryIgnoredApps] = apps + [bundleID]
        reload()
    }

    package func remove(_ bundleID: String) {
        guard apps.contains(bundleID) else { return }
        UserDefaults.standard[Preferences.clipboardHistoryIgnoredApps] = apps.filter { $0 != bundleID }
        reload()
    }

    // MARK: - Watching

    /// Follows the history: the observer is only installed while it runs.
    package func setHistoryRunning(_ running: Bool) {
        guard historyIsRunning != running else { return }
        historyIsRunning = running
        if running {
            guard activationObserver == nil else { return }
            window.candidates = Self.frontmostBundleID().map { [$0] } ?? []
            activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didActivateApplicationNotification,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                // Read here: the notification itself never crosses to the main actor.
                let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                // Delivered on the main queue.
                MainActor.assumeIsolated {
                    guard let app, let bundleID = app.bundleIdentifier else { return }
                    self?.window.candidates.insert(bundleID)
                }
            }
        } else if let activationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(activationObserver)
            self.activationObserver = nil
            window = ClipboardSourceWindow(ownBundleID: window.ownBundleID)
        }
    }

    // MARK: - The question the history asks

    /// Whether a copy noticed right now could have come from a listed app, the
    /// app it came from when only one held the front, and opens the next
    /// window. Called once per pasteboard check, on the main thread, whether
    /// or not anything was actually copied, so the window never stretches
    /// past the check it belongs to. With two apps in the window either could
    /// have copied it, and naming none is better than naming the wrong one.
    /// An app that names itself on the pasteboard is believed over the
    /// guess, and is left out just the same when it is on the list.
    /// Vitruvian's own writes, which never take the front, name no app at
    /// all, and neither does a copy that came from another device. The
    /// history's own panel never takes the front either: a copy made while
    /// it held the keys is Vitruvian's own and comes back as
    /// `fromHistoryPanel`. Closing the panel makes one last check of its own,
    /// so the next copy belongs to the app the user went back to; only when
    /// that check could not run does the first check after it still count
    /// as the panel's.
    package func sourceSinceLastCheck(declared: String?, remote: Bool,
                                      historyPanelIsKey: Bool, historyPanelClosing: Bool)
        -> (excluded: Bool, bundleID: String?, fromHistoryPanel: Bool) {
        guard historyIsRunning else { return (false, nil, false) }
        return window.check(declared: declared, remote: remote, historyPanelIsKey: historyPanelIsKey,
                            historyPanelClosing: historyPanelClosing, skipped: lookup,
                            front: Self.frontmostBundleID())
    }

    private static func frontmostBundleID() -> String? {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier
    }
}

/// The window `ClipboardIgnoredApps` keeps between two pasteboard checks,
/// apart from the workspace that feeds it, so the tests run the decision the
/// history makes.
package struct ClipboardSourceWindow: Equatable {
    /// Every app that held the front since the history last looked at the
    /// pasteboard. Seeded with whoever is in front when the window opens.
    package var candidates: Set<String> = []
    /// Whether the history's own panel held the keys at the last check, so a
    /// copy made in it is still known as one when the check its closing
    /// makes could not run.
    package var historyPanelWasKey = false
    package let ownBundleID: String?

    package init(ownBundleID: String?) {
        self.ownBundleID = ownBundleID
    }

    /// Answers `ClipboardIgnoredApps.sourceSinceLastCheck` for a history
    /// that is running, given the apps it `skipped`, and opens the next
    /// window with `front`, the app in front now.
    package mutating func check(declared: String?, remote: Bool,
                                historyPanelIsKey: Bool, historyPanelClosing: Bool,
                                skipped lookup: Set<String>, front: String?)
        -> (excluded: Bool, bundleID: String?, fromHistoryPanel: Bool) {
        // An empty mark is the convention for a writer that does not know,
        // and nothing longer than 255 bytes is a bundle identifier.
        let trimmed = declared?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let mark = trimmed.isEmpty || trimmed.utf8.count > 255 ? nil : trimmed
        let fromHistoryPanel = mark == nil && (historyPanelWasKey || historyPanelIsKey)
        let guessed = candidates.count == 1 && !fromHistoryPanel ? candidates.first : nil
        let named: String? = mark.map { $0 == ownBundleID ? nil : $0 } ?? guessed
        let source = (excluded: !candidates.isDisjoint(with: lookup) || mark.map { lookup.contains($0) } == true,
                      bundleID: remote ? nil : named,
                      fromHistoryPanel: fromHistoryPanel)
        candidates = front.map { [$0] } ?? []
        historyPanelWasKey = historyPanelIsKey && !historyPanelClosing
        return source
    }
}
