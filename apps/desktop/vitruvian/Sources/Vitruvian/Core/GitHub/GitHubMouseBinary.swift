// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import Foundation

/// Where the GravaStar mouse command lives on this Mac. It is built from
/// `//packages/peripherals:gravastar-mouse`; the app carries its own copy in
/// `Contents/Helpers`, and the package's README installs one in `~/.local/bin`.
package enum GitHubMouseBinary {
    package static let name = "gravastar-mouse"

    /// The copy inside the app bundle at `bundlePath` (the BUILD file's
    /// `additional_contents`).
    package static func bundled(in bundlePath: String) -> String {
        (bundlePath as NSString).appendingPathComponent("Contents/Helpers/\(name)")
    }

    /// Install locations an app launched from Finder does not have on its
    /// PATH, in the order they are tried.
    package static func searchDirectories(home: String) -> [String] {
        [(home as NSString).appendingPathComponent(".local/bin"), "/opt/homebrew/bin", "/usr/local/bin",
         (home as NSString).appendingPathComponent("bin")]
    }

    /// The configured path first (`~` expanded), then the app's own copy,
    /// which always takes the arguments this version sends, then each
    /// absolute PATH entry, then the usual install locations. Nil when none
    /// is executable, so the mouse is simply left alone.
    package static func locate(configured: String, bundled: String?, environment: [String: String], home: String,
                               isExecutable: (String) -> Bool) -> String? {
        let trimmed = configured.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            let explicit = expandingTilde(trimmed, home: home)
            if isExecutable(explicit) { return explicit }
        }
        if let bundled, isExecutable(bundled) { return bundled }
        // A relative PATH entry would resolve against the app's working
        // directory, so only absolute ones count.
        let path = (environment["PATH"] ?? "").split(separator: ":").map(String.init).filter { $0.hasPrefix("/") }
        var seen = Set<String>()
        return (path + searchDirectories(home: home))
            .filter { seen.insert($0).inserted }
            .map { ($0 as NSString).appendingPathComponent(name) }
            .first(where: isExecutable)
    }

    /// The `mcpServers` entry that runs `binary` as an MCP server
    /// (`gravastar-mouse mcp`), in the JSON shape MCP clients read.
    package static func mcpConfig(binary: String) -> String {
        let config: [String: Any] = ["mcpServers": [name: ["command": binary, "args": ["mcp"]] as [String: Any]]]
        guard let data = try? JSONSerialization.data(
            withJSONObject: config, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]) else { return "" }
        return String(decoding: data, as: UTF8.self)
    }

    private static func expandingTilde(_ path: String, home: String) -> String {
        if path == "~" { return home }
        if path.hasPrefix("~/") { return (home as NSString).appendingPathComponent(String(path.dropFirst(2))) }
        return path
    }
}
