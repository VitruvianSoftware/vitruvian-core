// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import AppKit
import SwiftUI
import VitruvianCore
import VitruvianServices
import VitruvianToolProtocol
import VitruvianUI

/// The detail of an extension whose lists scroll, drawn at its tallest:
/// every line of the extension's own words at its limit, an update, a
/// status with Start Again, its files, its log open, and the search field
/// and row of links over the scrolling region (taller for an extension with
/// a Settings panel). It still fits a 13-inch display, about 800 points
/// under the menu bar and above the Dock.
enum ExternalToolDetailHeightTests {
    static func run(_ suite: TestSuite) {
        theTallestDetailFitsA13InchDisplay(suite)
    }

    static let english = FeatureStrings.externalTools(.enUS)
    /// What is left of a 13-inch display, 900 points high, under the menu
    /// bar and above the Dock.
    static let room: CGFloat = 800

    /// The tallest detail, with a Settings panel or without, and its height
    /// as drawn.
    static func tallest(settingsPanel: Bool, _ suite: TestSuite) -> (detail: ExternalToolDetail, height: CGFloat)? {
        let long = String(repeating: "Wordy words ", count: 40)
        let commands = ExternalToolManifestTests.list(32) {
            #"{"id": "\#($0 == 0 ? "copyLatest" : "c\($0)")", "title": {"en": "\#(long)"}, "surfaces": ["commandBar"]}"#
        }
        // A setting's title is drawn on one line of 60 characters at most.
        let title = String(repeating: "Wordy ", count: 10)
        let preferences = ExternalToolManifestTests.list(16) {
            #"{"id": "p\#($0)", "title": {"en": "\#(title)"}, "type": "boolean", "default": false}"#
        }
        let settings = settingsPanel ? #", {"id": "settings", "title": {"en": "Speaker"}, "placement": "settings"}"# : ""
        let bench = ExternalToolStoreTests.Bench()
        defer { bench.close() }
        let added = bench.add(bench.folder(manifest: ExternalToolManifestTests.file(#"""
            {"name": {"en": "\#(long)"}, "publisher": "\#(long)", "description": {"en": "\#(long)"}, "protocol": "2",
             "uses": ["notify", "open", "clipboard.read", "clipboard.write", "keystrokes", "processes", "storage"],
             "contributes": {"commands": \#(commands),
               "panels": [{"id": "speaker", "title": {"en": "Speaker"}, "placement": "island"}\#(settings)],
               "status": {"placement": "island"}},
             "preferences": \#(preferences)}
            """#)))
        guard case .success = added else {
            suite.expect(false, "the extension is added: \(added)")
            return nil
        }
        // Crashed three times: the app has given up, and offers Start Again.
        for wait in [0.0, 1.0, 2.0] {
            bench.clock.advance(by: wait)
            bench.registry.run(ExternalToolTests.copy)
            guard !bench.runs.isEmpty else {
                suite.expect(false, "the extension's program starts")
                return nil
            }
            bench.current.ends(1)
        }
        guard let listed = bench.store.listed.first else {
            suite.expect(false, "the extension is added")
            return nil
        }
        let detail = ExternalToolDetail(listed, files: bench.store.folder(of: listed.id), language: .enUS,
                                        strings: english, settings: bench.store.settings(of: listed.id),
                                        settingsTitle: "Settings", updateAvailable: true, showsInIsland: true,
                                        showsStatus: true)
        suite.expect((detail.settingsPanel != nil) == settingsPanel && detail.listsScroll
                         && detail.row.status == .stopped(canStartAgain: true)
                         && detail.row.updateText != nil && detail.updateNow != nil && detail.files != nil
                         && detail.summary != nil,
                     "the tallest detail scrolls its lists, and has Start Again, an update and its files")
        let view = ExternalToolDetailView(
            detail: detail, log: (1...200).map { "line \($0)" }.joined(separator: "\n"),
            removal: ToolRemovalContent(name: detail.row.name, strings: english, cancel: "Cancel"), text: english,
            startAgain: {}, saveSetting: { _, _ in true }, setShowsInIsland: { _ in }, setShowsStatus: { _ in },
            panel: { _, _ in }, openWindow: { _ in }, reveal: {}, openShortcuts: {}, update: {}, updateNow: {},
            remove: { _ in }, close: {}, logExpanded: true)
        return (detail, NSHostingView(rootView: view).fittingSize.height)
    }

    static func theTallestDetailFitsA13InchDisplay(_ suite: TestSuite) {
        guard let page = tallest(settingsPanel: true, suite), let plain = tallest(settingsPanel: false, suite) else {
            return
        }
        suite.expect(page.height > ToolAgreementContent.pageListsHeight && page.height < room,
                     "the tallest detail of an extension with a Settings panel is under \(Int(room)) points: "
                         + "\(Int(page.height)), with a scrolling region of \(Int(page.detail.listsHeight))")
        suite.expect(page.detail.listsHeight == ToolAgreementContent.pageListsHeight
                         && ToolAgreementContent.pageListsHeight > ToolAgreementContent.listsHeight,
                     "its scrolling region is taller than the agreement sheet's")
        suite.expect(plain.detail.listsHeight == ToolAgreementContent.listsHeight && plain.height < room,
                     "the tallest detail with no Settings panel keeps the region of 200 points, and is under "
                         + "\(Int(room)): \(Int(plain.height))")
        suite.expect(abs((page.height - page.detail.listsHeight) - (plain.height - plain.detail.listsHeight)) <= 1,
                     "around its region it is drawn as the one with a Settings panel is, search field and row of "
                         + "links included: \(Int(plain.height - plain.detail.listsHeight)) and "
                         + "\(Int(page.height - page.detail.listsHeight)) points")
    }
}
