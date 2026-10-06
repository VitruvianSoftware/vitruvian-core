// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI
import VitruvianCore
import VitruvianDesign
import VitruvianServices

package struct WindowMaximizerExclusionsList: View {
    @ObservedObject private var l10n = L10n.shared
    @State private var apps: [String] = Self.savedApps

    private var text: WindowMaximizerExclusionStrings {
        FeatureStrings.windowMaximizerExclusions(l10n.language)
    }

    package var body: some View {
        AppBundleList(title: text.listTitle,
                      caption: text.caption,
                      addTitle: text.addButton,
                      removeLabel: text.removeButton,
                      bundleIDs: apps,
                      // Games often live outside the Applications folders,
                      // so the picker offers running apps and browsing too.
                      reachesEveryApp: true,
                      onAdd: { save(apps + [$0]) },
                      onRemove: { bundleID in save(apps.filter { $0 != bundleID }) })
    }

    private static var savedApps: [String] {
        Defaults.sanitizedBundleIdentifierList(
            UserDefaults.standard[Preferences.windowMaximizeExcludedApps])
    }

    private func save(_ bundleIDs: [String]) {
        let sanitized = Defaults.sanitizedBundleIdentifierList(bundleIDs)
        UserDefaults.standard[Preferences.windowMaximizeExcludedApps] = sanitized
        apps = sanitized
    }
}
