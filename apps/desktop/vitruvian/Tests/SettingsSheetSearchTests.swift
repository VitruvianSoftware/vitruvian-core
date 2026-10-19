// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import Foundation
import VitruvianCore
import VitruvianServices
import VitruvianToolProtocol
import VitruvianUI

/// An extension's settings sheet as its search and its row of section
/// links read it: which settings a search keeps, under which section, and
/// which section is lit as the sheet scrolls. Plain values; no view is
/// drawn.
enum SettingsSheetSearchTests {
    static func run(_ suite: TestSuite) {
        announceFindsBeeperAnnounce(suite)
        aMatchingSubheadingKeepsItsGroup(suite)
        aCaptionAfterAControlIsItsHelp(suite)
        aSectionAndAMenusOptionsAreSearched(suite)
        caseAndAccentsDoNotMatter(suite)
        vitruvianRowsAreSearchedToo(suite)
        noMatchSaysSo(suite)
        aWebPageIsNotSearchable(suite)
        jumpRowListsEverySection(suite)
        theSectionInViewIsLit(suite)
    }

    static let english = FeatureStrings.externalTools(.enUS)

    /// An extension with an island page, a status, a settings page, a
    /// setting in its manifest, a command and a service.
    static let manifest = ExternalToolManifestTests.file(#"""
        {"protocol": "2", "uses": ["notify"], "contributes": {
          "commands": [{"id": "copyLatest", "title": {"en": "Copy latest deploy"}, "surfaces": ["commandBar"]}],
          "panels": [{"id": "speaker", "title": {"en": "Speaker"}, "placement": "island"},
                     {"id": "settings", "title": {"en": "Speaker"}, "placement": "settings"}],
          "status": {"placement": "island"}},
         "preferences": [{"id": "project", "title": {"en": "Project"}, "type": "string", "default": "web"}]}
        """#)

    /// A page shaped as HomeSpeaker's: sections, sub-headings, a caption
    /// after a control, and help.
    static let homeSpeaker = #"""
        {"blocks": [
          {"type": "heading", "text": "Speaking", "section": true},
          {"type": "toggle", "id": "speak", "title": "Speak", "value": true, "help": "Say things on the home speakers."},
          {"type": "choice", "id": "voice", "title": "Voice", "value": "a",
           "options": [{"value": "a", "title": "Aoede"}, {"value": "b", "title": "Puck"}]},
          {"type": "heading", "text": "Chats", "section": true},
          {"type": "heading", "text": "Slack"},
          {"type": "toggle", "id": "slack", "title": "Read Slack", "value": true},
          {"type": "choice", "id": "slack.when", "title": "Read", "value": "mentions",
           "options": [{"value": "mentions", "title": "Mentions"}, {"value": "all", "title": "All"}]},
          {"type": "heading", "text": "Béeper"},
          {"type": "toggle", "id": "beeper", "title": "Read messages", "value": true},
          {"type": "choice", "id": "beeper.when", "title": "Announce", "value": "every",
           "options": [{"value": "every", "title": "Every message"}, {"value": "direct", "title": "Direct only"}]},
          {"type": "text", "text": "Messages you send yourself are never read.", "style": "caption"},
          {"type": "chips", "id": "beeper.networks", "title": "Networks",
           "options": [{"value": "wa", "title": "WhatsApp", "on": true}, {"value": "sg", "title": "Signal", "on": false}]},
          {"type": "heading", "text": "Quiet hours", "section": true},
          {"type": "toggle", "id": "quiet", "title": "Quiet hours", "value": false, "help": "Nothing is spoken."},
          {"type": "text", "text": "A stray caption after a switch with help of its own.", "style": "caption"}
        ]}
        """#

    /// The detail of the extension of `manifest`, and its sheet's index
    /// with `page` as its settings page.
    static func index(_ page: String?, web: Bool = false,
                      _ check: (ExternalToolDetail, SettingsSheetIndex) -> Void) {
        let bench = ExternalToolStoreTests.Bench()
        defer { bench.close() }
        bench.add(bench.folder(manifest: manifest))
        guard let listed = bench.store.listed.first else { return check(detailless, emptyIndex) }
        let detail = ExternalToolDetail(listed, files: nil, language: .enUS, strings: english,
                                        settings: bench.store.settings(of: listed.id), settingsTitle: "Settings",
                                        showsInIsland: true, showsStatus: true)
        let panel = page.flatMap { ToolPanelScreensTests.content($0) }
        check(detail, SettingsSheetIndex(detail: detail, panel: panel, panelIsWeb: web, strings: english))
    }

    // Stand-ins, never checked as right: a bench that adds nothing fails
    // every test that uses them.
    private static var detailless: ExternalToolDetail {
        let bench = ExternalToolStoreTests.Bench()
        defer { bench.close() }
        bench.add(bench.folder())
        return ExternalToolDetail(bench.store.listed[0], files: nil, language: .enUS, strings: english)
    }

    private static var emptyIndex: SettingsSheetIndex {
        SettingsSheetIndex(detail: detailless, panel: nil, panelIsWeb: false, strings: english)
    }

    static func announceFindsBeeperAnnounce(_ suite: TestSuite) {
        index(homeSpeaker) { _, index in
            let found = index.matches("announce")
            suite.expect(found.map(\.title) == ["Announce"] && found.first?.section == "Chats"
                             && found.first?.anchor == .panelItem(9),
                         "typing announce finds Beeper's Announce, in the section Chats: \(found.map(\.title))")
            suite.expect(found.first.map { Set($0.items) } == [3, 7, 9, 10],
                         "it is drawn with its section's heading, its sub-heading and its caption: "
                             + "\(found.first?.items ?? [])")
            suite.expect(index.matches("annou").map(\.title) == ["Announce"],
                         "part of a word finds it too")
            let kept = index.kept("announce")
            suite.expect(kept.searching && kept.links.map(\.title) == ["Chats"] && kept.panelItems == [3, 7, 9, 10]
                             && !kept.draws(.showsInIsland) && !kept.drawsSection(.vitruvianHeading)
                             && !kept.draws(.commands, title: "Copy latest deploy") && !kept.nothingFound,
                         "while it is typed the sheet draws only that, under its section, and links only that section")
            let cleared = index.kept(" ")
            suite.expect(!cleared.searching && cleared.panelItems == nil && cleared.links.map(\.title) == index.sections
                             && cleared.draws(.showsInIsland) && cleared.draws(.uses, title: "anything"),
                         "clearing the search draws the whole sheet again")
        }
    }

    static func aMatchingSubheadingKeepsItsGroup(_ suite: TestSuite) {
        index(homeSpeaker) { _, index in
            suite.expect(index.matches("beeper").map(\.title) == ["Read messages", "Announce", "Networks"],
                         "a sub-heading that matches keeps every setting under it, and only those: "
                             + "\(index.matches("beeper").map(\.title))")
            suite.expect(index.matches("slack read").map(\.title) == ["Read Slack", "Read"],
                         "every word typed must be found, in the title or the sub-heading: "
                             + "\(index.matches("slack read").map(\.title))")
            suite.expect(index.matches("whatsapp").map(\.title) == ["Networks"],
                         "a chip's title finds its chips")
        }
    }

    static func aSectionAndAMenusOptionsAreSearched(_ suite: TestSuite) {
        index(homeSpeaker) { _, index in
            let chats = ["Read Slack", "Read", "Read messages", "Announce", "Networks"]
            suite.expect(index.matches("chats").map(\.title) == chats
                             && index.kept("chats").links.map(\.title) == ["Chats"],
                         "a section's title that matches keeps the whole section: \(index.matches("chats").map(\.title))")
            suite.expect(index.matches("every message").map(\.title) == ["Announce"]
                             && index.matches("every message").first?.section == "Chats",
                         "an option of a menu finds the menu: every message finds Beeper's Announce, in Chats: "
                             + "\(index.matches("every message").map(\.title))")
            suite.expect(index.matches("vitruvian").map(\.anchor) == [.showsInIsland, .showsStatus, .setting("project")],
                         "Vitruvian's own section is found by its title too")
        }
    }

    static func aCaptionAfterAControlIsItsHelp(_ suite: TestSuite) {
        index(homeSpeaker) { _, index in
            suite.expect(index.matches("yourself").map(\.title) == ["Announce"],
                         "a caption directly after a control with no help is that control's help")
            suite.expect(index.matches("home speakers").map(\.title) == ["Speak"],
                         "a control's own help is searched")
            suite.expect(index.matches("stray").isEmpty,
                         "a caption after a control that has help of its own is not that control's")
        }
    }

    static func caseAndAccentsDoNotMatter(_ suite: TestSuite) {
        index(homeSpeaker) { _, index in
            suite.expect(index.matches("QUIET").map(\.title) == ["Quiet hours"]
                             && index.matches("réad sláck").map(\.title) == ["Read Slack", "Read"],
                         "a search ignores the letters' case and accents, in what is typed and in what it finds")
            suite.expect(index.matches("   ") == index.entries && index.matches("") == index.entries,
                         "a search of no words keeps every setting")
        }
    }

    static func vitruvianRowsAreSearchedToo(_ suite: TestSuite) {
        index(homeSpeaker) { detail, index in
            let found = index.matches("island")
            suite.expect(found.map(\.anchor) == [.showsInIsland, .showsStatus]
                             && found.allSatisfy { $0.section == "Vitruvian" && $0.sectionAnchor == .vitruvianHeading },
                         "typing island finds Show in island, and the status switch, under Vitruvian: "
                             + "\(found.map(\.title))")
            suite.expect(index.matches("project").map(\.anchor) == [.setting("project")],
                         "a setting the manifest declares is found")
            suite.expect(index.matches("latest").map(\.section) == [detail.commandsTitle]
                             && index.matches("alert sound").map(\.section) == [detail.usesTitle],
                         "the commands and what the extension uses are found, each under its section")
        }
    }

    static func noMatchSaysSo(_ suite: TestSuite) {
        index(homeSpeaker) { _, index in
            suite.expect(index.matches("zebra").isEmpty && index.kept("zebra").nothingFound
                             && index.kept("zebra").links.isEmpty && !index.kept("zebra").saysNotSearchable,
                         "a search that finds nothing keeps nothing, and the sheet says so")
        }
        suite.expect(english.noSettingsMatch("zebra") == "No settings match “zebra”"
                         && FeatureStrings.externalTools(.de).noSettingsMatch("zebra") == "Keine Einstellung passt zu „zebra“",
                     "and the sheet says so, with what was typed, in the person's language")
    }

    static func aWebPageIsNotSearchable(_ suite: TestSuite) {
        index(nil, web: true) { detail, index in
            suite.expect(!index.searchable && index.sections.contains(detail.settingsTitle)
                             && index.anchors.contains(.panel)
                             && index.entries.allSatisfy { $0.items.isEmpty },
                         "a settings page that is a web page cannot be searched, and still has its link: "
                             + "\(index.sections)")
            suite.expect(index.matches("island").map(\.anchor) == [.showsInIsland, .showsStatus],
                         "the rest of the sheet still is")
            let kept = index.kept("zebra")
            suite.expect(kept.saysNotSearchable && !kept.nothingFound && kept.links.map(\.anchor) == [.panel],
                         "a search says it cannot look inside the page, keeps the page's link, and does not claim "
                             + "that nothing matches")
            suite.expect(!index.kept("").saysNotSearchable, "with nothing typed it says nothing of it")
        }
        suite.expect(english.pageNotSearchable == "This page can’t be searched.",
                     "the sheet says it cannot search the page")
        index(homeSpeaker) { _, index in
            suite.expect(index.searchable, "a page of blocks can be searched")
        }
    }

    static func jumpRowListsEverySection(_ suite: TestSuite) {
        index(homeSpeaker) { detail, index in
            suite.expect(index.sections == ["Vitruvian", "Speaking", "Chats", "Quiet hours", detail.commandsTitle,
                                            detail.usesTitle]
                             && index.anchors == [.vitruvianHeading, .panelItem(0), .panelItem(3), .panelItem(12),
                                                  .commands, .uses],
                         "the links are Vitruvian's rows, the page's sections in order, the commands and what it "
                             + "uses: \(index.sections)")
        }
        index(#"{"blocks": [{"type": "toggle", "id": "t", "title": "Loud", "value": true}]}"#) { detail, index in
            suite.expect(index.sections == ["Vitruvian", "Settings", detail.commandsTitle, detail.usesTitle]
                             && index.anchors.dropFirst().first == .panel
                             && index.matches("loud").first?.section == "Settings",
                         "a page with no section headings has one link, titled with the sheet's settings title: "
                             + "\(index.sections)")
        }
        index(#"{"blocks": [{"type": "text", "text": "Hello"}, {"type": "heading", "text": "More", "section": true}]}"#) {
            _, index in
            suite.expect(index.sections.prefix(3) == ["Vitruvian", "Settings", "More"],
                         "what a page draws before its first section is under the settings title")
        }
        let dropped = #"{"blocks": [{"type": "map"}, {"type": "heading", "text": "Late", "section": true}]}"#
        index(dropped) { _, index in
            suite.expect(index.anchors.contains(.panelItem(1)),
                         "a section's link is its heading's place in the page, past a block the app leaves out")
        }
    }

    static func theSectionInViewIsLit(_ suite: TestSuite) {
        index(homeSpeaker) { _, index in
            let tops: [SettingsSheetIndex.Anchor: CGFloat] = [.vitruvianHeading: -400, .panelItem(0): -180,
                                                               .panelItem(3): 12, .panelItem(12): 300,
                                                               .commands: 520, .uses: 610]
            suite.expect(index.current(tops: tops, reach: 24, height: 320, chosen: nil) == .panelItem(3),
                         "the lit link is the last section whose heading has reached the top of the region")
            suite.expect(index.current(tops: tops.mapValues { $0 + 400 }, reach: 24, height: 320, chosen: nil)
                             == .vitruvianHeading,
                         "at the top of the sheet the first section is lit")
            let end: [SettingsSheetIndex.Anchor: CGFloat] = [.panelItem(12): -40, .commands: 150, .uses: 240]
            suite.expect(index.current(tops: end, reach: 24, height: 320, chosen: .uses) == .uses
                             && index.current(tops: end, reach: 24, height: 320, chosen: nil) == .panelItem(12),
                         "a short last section that cannot reach the top is lit while its link was just used")
            suite.expect(index.current(tops: tops, reach: 24, height: 320, chosen: .uses) == .panelItem(3),
                         "once that heading is out of view, the lit link follows the scrolling again")
        }
    }
}
