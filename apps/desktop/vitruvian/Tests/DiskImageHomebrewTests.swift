// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import VitruvianServices

/// The installer's Homebrew rule over temporary folders. No disk image is
/// mounted and no app is installed or opened.
enum DiskImageHomebrewTests {
    static func run(_ suite: TestSuite) {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("vitru-dmg-homebrew-\(UUID())", isDirectory: true)
        defer { try? fm.removeItem(at: root) }
        do {
            let library = root.appendingPathComponent("Library", isDirectory: true)
            let cache = library.appendingPathComponent("Caches/Homebrew", isDirectory: true)
            let cached = cache.appendingPathComponent("downloads/example.dmg")
            let manual = root.appendingPathComponent("Downloads/manual.dmg")
            let sibling = library.appendingPathComponent("Caches/Homebrew-backup/example.dmg")
            for url in [cached, manual, sibling] {
                try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try Data([0]).write(to: url)
            }
            let linked = root.appendingPathComponent("cache-link", isDirectory: true)
            try fm.createSymbolicLink(at: linked, withDestinationURL: cache)
            func homebrew(_ url: URL) -> Bool {
                DiskImageInstallerSupport.isHomebrewImage(url, libraryURL: library)
            }
            suite.expect(homebrew(cached) && homebrew(linked.appendingPathComponent("downloads/example.dmg")),
                         "cached Homebrew images and symlinks into that cache are excluded")
            suite.expect(!homebrew(manual) && !homebrew(sibling),
                         "manual downloads and similarly named sibling folders are retained")
        } catch {
            suite.expect(false, "disk image fixture failed: \(error)")
        }
    }
}
