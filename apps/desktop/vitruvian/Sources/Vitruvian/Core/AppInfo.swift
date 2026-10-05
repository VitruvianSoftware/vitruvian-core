// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Static identity of the app, shared by UI, notifications and tooling.
package enum AppInfo {
    package static let name = "Vitruvian"
    /// Vitruvian is a fork of Vorssaint, whose notice stays (GPL-3.0 §5).
    package static let copyright = "© 2026 Vorssaint, VitruvianSoftware"
    /// Public home of the source, which the GPL obliges us to offer with every
    /// distributed build: the planned public mirror of apps/desktop/vitruvian.
    /// It has to exist before the first release (see UPSTREAM.md).
    package static let repositoryURL = URL(string: "https://github.com/VitruvianSoftware/vitruvian")!
    package static let websiteURL = repositoryURL
    /// Upstream's donation, Discord and X channels belong to upstream. The fork
    /// has none yet, so the Support page and the post-update support prompt are
    /// hidden and these links fall back to the repository.
    package static let hasCommunityChannels = false
    package static let coffeeURL = repositoryURL
    package static let discordURL = repositoryURL
    package static let socialURL = repositoryURL

    /// The bundle version. The fallback only applies to the bare binary
    /// (e.g. `--selftest`), never the shipped app, which reads its Info.plist.
    package static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }

    /// True for the local "Vitruvian (Developer)" build (bundle id ends in `.dev`).
    /// It is never published and never auto-updates; all work is tested here first.
    package static var isDeveloperBuild: Bool {
        (Bundle.main.bundleIdentifier ?? "").hasSuffix(".dev")
    }

    /// True when the current version is a pre-release (e.g. 3.3.4-beta.1 or 3.3.4-rc.1).
    package static var isBeta: Bool {
        if isDeveloperBuild && UserDefaults.standard.bool(forKey: DefaultsKey.simulateBetaUI) {
            return true
        }
        return isPrerelease(version)
    }

    /// Whether a version names a pre-release (e.g. 3.3.4-beta.1 or 3.3.4-rc.1).
    package static func isPrerelease(_ version: String) -> Bool {
        let v = version.lowercased()
        return v.contains("-beta") || v.contains("-rc") || v.contains("-alpha")
    }

    /// The git commit a Developer build was compiled from, e.g. "ed2ebba · 2026-06-15 21:30"
    /// (or with a "-dirty" suffix on the SHA for uncommitted changes). build.sh stamps
    /// this into the Developer bundle only, so you can confirm at a glance that the
    /// running dev app matches the source you are about to change. nil in the official app.
    package static var buildCommit: String? {
        Bundle.main.object(forInfoDictionaryKey: "VitruvianBuildCommit") as? String
    }
}
