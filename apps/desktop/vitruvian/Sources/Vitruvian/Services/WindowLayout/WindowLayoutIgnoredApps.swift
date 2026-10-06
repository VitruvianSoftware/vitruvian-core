// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Combine
import Foundation
import VitruvianCore
import VitruvianDesign

/// Apps that temporarily turn off every Window Layout input while focused.
@MainActor
package final class WindowLayoutIgnoredApps: ObservableObject {
    package static let shared = WindowLayoutIgnoredApps()

    @Published package private(set) var apps: [String] = []

    private init() {
        reload()
    }

    package func reload() {
        let defaults = UserDefaults.standard
        let raw = defaults[Preferences.windowLayoutIgnoredApps]
        let sanitized = Defaults.sanitizedBundleIdentifierList(raw)
        if raw != sanitized {
            defaults[Preferences.windowLayoutIgnoredApps] = sanitized
        }
        apps = sanitized
    }

    package func add(_ bundleID: String) {
        let updated = Defaults.sanitizedBundleIdentifierList(apps + [bundleID])
        guard updated != apps else { return }
        UserDefaults.standard[Preferences.windowLayoutIgnoredApps] = updated
        apps = updated
    }

    package func remove(_ bundleID: String) {
        guard apps.contains(bundleID) else { return }
        UserDefaults.standard[Preferences.windowLayoutIgnoredApps] = apps.filter { $0 != bundleID }
        reload()
    }

    package func contains(bundleID: String?, executablePath: @autoclosure () -> String?) -> Bool {
        Self.matches(bundleID: bundleID, executablePath: executablePath(), apps: apps)
    }

    nonisolated package static func contains(_ bundleID: String?, in apps: [String]) -> Bool {
        guard let bundleID else { return false }
        return apps.contains(bundleID)
    }

    nonisolated package static func matches(bundleID: String?, executablePath: String?, apps: [String]) -> Bool {
        contains(MouseAppExceptionSupport.identity(bundleID: bundleID,
                                                   executablePath: executablePath),
                 in: apps)
    }
}
