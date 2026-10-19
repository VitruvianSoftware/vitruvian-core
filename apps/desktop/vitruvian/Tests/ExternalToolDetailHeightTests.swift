// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import AppKit
import SwiftUI
import VitruvianCore
import VitruvianServices
import VitruvianToolProtocol
import VitruvianUI

/// The detail of an extension with a Settings panel, drawn at its tallest:
/// every line of the extension's own words at its limit, an update, a
/// status with Start Again, its files, its log open, and the search field
/// and row of links over a taller scrolling region. It still fits a
/// 13-inch display, about 800 points under the menu bar and above the Dock.
enum ExternalToolDetailHeightTests {
    static func run(_ suite: TestSuite) {
        theTallestDetailFitsA13InchDisplay(suite)
    }

    static let english = FeatureStrings.externalTools(.enUS)
    /// What is left of a 13-inch display, 900 points high, under the menu
    /// bar and above the Dock.
    static let room: CGFloat = 800

    static func theTallestDetailFitsA13InchDisplay(_ suite: TestSuite) {
        let long = String(repeating: "Wordy words ", count: 40)
        let commands = ExternalToolManifestTests.list(32) {
            #"{"id": "\#($0 == 0 ? "copyLatest" : "c\($0)")", "title": {"en": "\#(long)"}, "surfaces": ["commandBar"]}"#
        }
        // A setting's title is drawn on one line of 60 characters at most.
        let title = String(repeating: "Wordy ", count: 10)
        let preferences = ExternalToolManifestTests.list(16) {
            #"{"id": "p\#($0)", "title": {"en": "\#(title)"}, "type": "boolean", "default": false}"#
        }
        let bench = ExternalToolStoreTests.Bench()
        defer { bench.close() }
        let added = bench.add(bench.folder(manifest: ExternalToolManifestTests.file(#"""
            {"name": {"en": "\#(long)"}, "publisher": "\#(long)", "description": {"en": "\#(long)"}, "protocol": "2",
             "uses": ["notify", "open", "clipboard.read", "clipboard.write", "keystrokes", "processes", "storage"],
             "contributes": {"commands": \#(commands),
               "panels": [{"id": "speaker", "title": {"en": "Speaker"}, "placement": "island"},
                          {"id": "settings", "title": {"en": "Speaker"}, "placement": "settings"}],
               "status": {"placement": "island"}},
             "preferences": \#(preferences)}
            """#)))
        guard case .success = added else { return suite.expect(false, "the extension is added: \(added)") }
        // Crashed three times: the app has given up, and offers Start Again.
        for wait in [0.0, 1.0, 2.0] {
            bench.clock.advance(by: wait)
            bench.registry.run(ExternalToolTests.copy)
            guard !bench.runs.isEmpty else { return suite.expect(false, "the extension's program starts") }
            bench.current.ends(1)
        }
        guard let listed = bench.store.listed.first else { return suite.expect(false, "the extension is added") }
        let detail = ExternalToolDetail(listed, files: bench.store.folder(of: listed.id), language: .enUS,
                                        strings: english, settings: bench.store.settings(of: listed.id),
                                        settingsTitle: "Settings", updateAvailable: true, showsInIsland: true,
                                        showsStatus: true)
        suite.expect(detail.settingsPanel == "settings" && detail.row.status == .stopped(canStartAgain: true)
                         && detail.row.updateText != nil && detail.updateNow != nil && detail.files != nil
                         && detail.summary != nil,
                     "the tallest detail has a Settings panel, Start Again, an update and its files")
        let view = ExternalToolDetailView(
            detail: detail, log: (1...200).map { "line \($0)" }.joined(separator: "\n"),
            removal: ToolRemovalContent(name: detail.row.name, strings: english, cancel: "Cancel"), text: english,
            startAgain: {}, saveSetting: { _, _ in true }, setShowsInIsland: { _ in }, setShowsStatus: { _ in },
            panel: { _, _ in }, openWindow: { _ in }, reveal: {}, openShortcuts: {}, update: {}, updateNow: {},
            remove: { _ in }, close: {}, logExpanded: true)
        let host = NSHostingView(rootView: view)
        let height = host.fittingSize.height
        suite.expect(height > ToolAgreementContent.pageListsHeight && height < room,
                     "the tallest detail of an extension with a Settings panel is under \(Int(room)) points: "
                         + "\(Int(height)), with a scrolling region of \(Int(detail.listsHeight))")
        suite.expect(detail.listsHeight == ToolAgreementContent.pageListsHeight
                         && ToolAgreementContent.pageListsHeight > ToolAgreementContent.listsHeight,
                     "its scrolling region is taller than the agreement sheet's")
    }
}
