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
/// under the menu bar and above the Dock, in every language, with the links
/// of an extension with as many sections as HomeSpeaker, which wrap onto a
/// second row so that every one is in view.
enum ExternalToolDetailHeightTests {
    static func run(_ suite: TestSuite) {
        theTallestDetailFitsA13InchDisplay(suite)
        everyLinkIsInView(suite)
    }

    static let english = FeatureStrings.externalTools(.enUS)
    /// The width the detail's lists are drawn in: the sheet's 480 points
    /// less its margins.
    static let listsWidth: CGFloat = 480 - 22 * 2

    /// HomeSpeaker's eight links in `language`: Vitruvian's own rows, its
    /// five sections, its commands and what it uses.
    static func homeSpeakerLinks(_ language: AppLanguage) -> [(title: String, anchor: SettingsSheetIndex.Anchor)] {
        let text = FeatureStrings.externalTools(language)
        let titles = [text.vitruvianSection, "General", "Speakers", "Chats", "AI Agents", "Google Cloud",
                      text.commandsTitle, text.usesTitle]
        return titles.enumerated().map { (title: $1, anchor: .panelItem($0)) }
    }

    /// Where the drawn links were placed, as the row reports it.
    private final class Seen {
        var frames: [CGRect] = []
    }

    /// `links` drawn at the lists' width in a window: how tall the row is,
    /// and each link's frame from the row's left edge.
    static func drawn(_ links: [(title: String, anchor: SettingsSheetIndex.Anchor)], width: CGFloat = listsWidth)
        -> (height: CGFloat, frames: [CGRect]) {
        _ = NSApplication.shared
        let seen = Seen()
        let row = SettingsSheetLinks(links: links, current: links.first?.anchor, focus: nil, jump: { _ in },
                                     placed: { seen.frames = $0 })
            .frame(width: width, alignment: .topLeading)
        let view = NSHostingView(rootView: row)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: 200), styleMask: [.borderless],
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = view
        window.orderFrontRegardless()
        view.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        defer {
            window.orderOut(nil)
            window.contentView = nil
            window.close()
        }
        return (view.fittingSize.height, seen.frames)
    }

    /// What is left of a 13-inch display, 900 points high, under the menu
    /// bar and above the Dock.
    static let room: CGFloat = 800

    /// The tallest detail, with a Settings panel or without, and its height
    /// as drawn.
    static func tallest(settingsPanel: Bool, language: AppLanguage = .enUS,
                        _ suite: TestSuite) -> (detail: ExternalToolDetail, height: CGFloat)? {
        let text = FeatureStrings.externalTools(language)
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
        let detail = ExternalToolDetail(listed, files: bench.store.folder(of: listed.id), language: language,
                                        strings: text, settings: bench.store.settings(of: listed.id),
                                        settingsTitle: "Settings", updateAvailable: true, showsInIsland: true,
                                        showsStatus: true)
        suite.expect((detail.settingsPanel != nil) == settingsPanel && detail.listsScroll
                         && detail.row.status == .stopped(canStartAgain: true)
                         && detail.row.updateText != nil && detail.updateNow != nil && detail.files != nil
                         && detail.summary != nil,
                     "the tallest detail scrolls its lists, and has Start Again, an update and its files")
        let view = ExternalToolDetailView(
            detail: detail, log: (1...200).map { "line \($0)" }.joined(separator: "\n"),
            removal: ToolRemovalContent(name: detail.row.name, strings: text, cancel: "Cancel"), text: text,
            startAgain: {}, saveSetting: { _, _ in true }, setShowsInIsland: { _ in }, setShowsStatus: { _ in },
            panel: { _, _ in }, openWindow: { _ in }, reveal: {}, openShortcuts: {}, update: {}, updateNow: {},
            remove: { _ in }, close: {}, logExpanded: true)
        return (detail, NSHostingView(rootView: view).fittingSize.height)
    }

    static func theTallestDetailFitsA13InchDisplay(_ suite: TestSuite) {
        for language in AppLanguage.allCases {
            guard let page = tallest(settingsPanel: true, language: language, suite),
                  let plain = tallest(settingsPanel: false, language: language, suite) else { return }
            let name = language.rawValue
            // The sheet drawn has a link for each of its four parts; one with
            // HomeSpeaker's eight wraps them onto more rows.
            let text = FeatureStrings.externalTools(language)
            let own = SettingsSheetIndex(detail: page.detail, panel: nil, panelIsWeb: false, strings: text).kept("").links
            let more = drawn(homeSpeakerLinks(language)).height - drawn(own).height
            // Both draw the same around their region, search field and row of
            // links included; the one with a Settings panel gives its region
            // the room that is left, at least its least.
            let around = plain.height - plain.detail.listsHeight
            let region = page.height - around
            suite.expect(page.detail.fillsHeight && page.height <= ToolAgreementContent.detailHeight + 0.5
                             && region >= ToolAgreementContent.pageListsHeight - 0.5,
                         "\(name): the tallest detail of an extension with a Settings panel is at most "
                             + "\(Int(ToolAgreementContent.detailHeight)) points, \(Int(page.height)), with a region of "
                             + "\(Int(region)), at least \(Int(ToolAgreementContent.pageListsHeight))")
            suite.expect(around + more + ToolAgreementContent.pageListsHeight < room,
                         "\(name): with HomeSpeaker's links its region keeps its least and the detail is under "
                             + "\(Int(room)) points: \(Int(around + more + ToolAgreementContent.pageListsHeight)) "
                             + "(\(Int(more)) for the links' extra rows)")
            suite.expect(!plain.detail.fillsHeight && plain.detail.listsHeight == ToolAgreementContent.listsHeight
                             && plain.height + more < room,
                         "\(name): the tallest detail with no Settings panel keeps the region of 200 points, and is "
                             + "under \(Int(room)) with as many links: \(Int(plain.height + more))")
        }
        // The rule the sheet's column follows.
        let budget = ExternalToolDetail.columnBudget(room: nil)
        suite.expect(budget == ToolAgreementContent.detailHeight - ExternalToolDetail.margins
                         && ExternalToolDetail.columnBudget(room: 600) == 600 - ToolAgreementContent.sheetMargin
                             - ExternalToolDetail.margins,
                     "the column may be as tall as a 13-inch display has room for, or the window less the sheet's "
                         + "margin when that is less")
        suite.expect(SheetColumn.fill(ideal: 900, least: 250, rest: 300, budget: 746) == 446
                         && SheetColumn.fill(ideal: 320, least: 250, rest: 300, budget: 746) == 320
                         && SheetColumn.fill(ideal: 900, least: 250, rest: 300, budget: 500) == 250,
                     "the region takes what is left, up to all it holds, and never less than its least")
        suite.expect(ToolAgreementContent.pageListsHeight > ToolAgreementContent.listsHeight,
                     "the scrolling region of a detail with a Settings panel is taller than the agreement sheet's")
    }

    /// No link is hidden past the sheet's edge: they wrap onto rows.
    static func everyLinkIsInView(_ suite: TestSuite) {
        for language in AppLanguage.allCases {
            let links = homeSpeakerLinks(language)
            let row = drawn(links)
            let outside = row.frames.filter { $0.minX < -0.5 || $0.maxX > listsWidth + 0.5 }
            suite.expect(row.frames.count == links.count && outside.isEmpty,
                         "\(language.rawValue): HomeSpeaker's \(links.count) links all lie within the sheet's "
                             + "\(Int(listsWidth)) points: \(row.frames.count) drawn, "
                             + "\(outside.map { Int($0.maxX) }) past the edge")
            // Drawn with all the room they want, each is as wide as it is here.
            let whole = drawn(links, width: 2000).frames.map(\.width)
            let cut = zip(row.frames.map(\.width), whole).filter { $0 < $1 - 0.5 }
            suite.expect(whole.count == links.count && cut.isEmpty,
                         "\(language.rawValue): no link is cut short to fit: \(cut.map { "\(Int($0)) of \(Int($1))" })")
        }
    }
}
