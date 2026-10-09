// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import Foundation

/// Where the GravaStar mouse command lives on this Mac. It is built from
/// `//packages/peripherals:gravastar-mouse`, and its README installs it in
/// `~/.local/bin`.
package enum GitHubMouseBinary {
    package static let name = "gravastar-mouse"

    /// Install locations an app launched from Finder does not have on its
    /// PATH, in the order they are tried.
    package static func searchDirectories(home: String) -> [String] {
        [(home as NSString).appendingPathComponent(".local/bin"), "/opt/homebrew/bin", "/usr/local/bin",
         (home as NSString).appendingPathComponent("bin")]
    }

    /// The configured path first (`~` expanded), then each absolute PATH
    /// entry, then the usual install locations. Nil when none is executable,
    /// so the mouse is simply left alone.
    package static func locate(configured: String, environment: [String: String], home: String,
                               isExecutable: (String) -> Bool) -> String? {
        let trimmed = configured.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            let explicit = expandingTilde(trimmed, home: home)
            if isExecutable(explicit) { return explicit }
        }
        // A relative PATH entry would resolve against the app's working
        // directory, so only absolute ones count.
        let path = (environment["PATH"] ?? "").split(separator: ":").map(String.init).filter { $0.hasPrefix("/") }
        var seen = Set<String>()
        return (path + searchDirectories(home: home))
            .filter { seen.insert($0).inserted }
            .map { ($0 as NSString).appendingPathComponent(name) }
            .first(where: isExecutable)
    }

    private static func expandingTilde(_ path: String, home: String) -> String {
        if path == "~" { return home }
        if path.hasPrefix("~/") { return (home as NSString).appendingPathComponent(String(path.dropFirst(2))) }
        return path
    }
}
