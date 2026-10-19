// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import Foundation
import VitruvianCore
import VitruvianServices
import VitruvianToolProtocol
import VitruvianUI

/// A page as the app draws it, checked as the plain value the view draws:
/// the person's language, the line limits, the defaults, a picture found
/// in the tool's folder, a link the app may open, and a later block's
/// fallback. No test draws a view.
enum ToolPanelScreensTests {
    static func run(_ suite: TestSuite) {
        everyKind(suite)
        defaultsAndLimits(suite)
        linksAndPictures(suite)
        laterKinds(suite)
        detail(suite)
        islandSwitch(suite)
        islandTiles(suite)
        availableIslandSections(suite)
        islandQuickActions(suite)
        aChoiceIsAMenu(suite)
        aChipsBlockIsChips(suite)
        chipsSendTheSetThatIsOn(suite)
        twoQuickChipTapsKeepTheFirst(suite)
        aDisabledChipSaysWhy(suite)
        helpShowsUnderItsControl(suite)
        sectionHeadingsAreListed(suite)
    }

    static let id = ExternalToolTests.id

    /// The design's example tool, of protocol 2, with a panel in each place
    /// and two windows.
    static let drawing = ExternalToolManifestTests.file(#"""
        {"protocol": "2", "uses": ["notify"], "contributes": {
          "commands": [{"id": "copyLatest", "title": {"en": "Copy latest deploy"}}],
          "panels": [
            {"id": "deploys", "title": {"en": "Deploys"}, "placement": "island"},
            {"id": "settings", "title": {"en": "Deploys"}, "placement": "settings"},
            {"id": "log", "title": {"en": "Deploy log", "fr": "Journal"}, "placement": "window", "icon": "doc.text"},
            {"id": "dashboard", "title": {"en": "Dashboard"}, "placement": "window", "kind": "web", "entry": "ui/d.html"}]}}
        """#)

    static func content(_ page: String, language: String = "en", folder: URL? = nil,
                        size: BlockTreeContent.Size = .standard) -> BlockTreeContent? {
        guard case .success(let tree) = ToolPanelTree.read(ToolPanelTests.json(page)) else { return nil }
        return BlockTreeContent(tree: tree, language: language, folder: folder, size: size)
    }

    static func everyKind(_ suite: TestSuite) {
        let drawn = content(#"""
            {"blocks": [
              {"type": "heading", "text": {"en": "Today", "fr": "Aujourd’hui"}},
              {"type": "text", "text": "Three deploys", "style": "secondary", "lines": 2},
              {"type": "row", "id": "latest", "title": "web 1.42.0", "subtitle": "main", "icon": "checkmark.circle", "trailing": "9:12"},
              {"type": "row", "title": "a row that cannot be tapped"},
              {"type": "button", "id": "again", "title": {"en": "Deploy again", "fr": "Redéployer"}, "style": "prominent", "enabled": false},
              {"type": "toggle", "id": "notify", "title": "Tell me", "value": true},
              {"type": "field", "id": "project", "title": "Project", "value": "acme/web", "placeholder": "owner/name", "kind": "secret"},
              {"type": "list", "id": "deploys", "rows": [{"id": "api", "title": "api 3.8.1", "subtitle": "failed"}]},
              {"type": "progress", "value": 0.5, "label": "worker"},
              {"type": "divider"},
              {"type": "spacer", "size": 12}
            ]}
            """#, language: "fr")
        let kinds = drawn?.items.map(\.kind) ?? []
        suite.expect(kinds.count == 11 && drawn?.items.map(\.id) == Array(0..<11),
                     "every block is drawn, in the page's order")
        typealias Row = BlockTreeContent.Row
        suite.expect(kinds == [
            .heading("Aujourd’hui", section: false),
            .text("Three deploys", style: .secondary, lines: 2),
            .row(Row(id: "latest", title: "web 1.42.0", subtitle: "main", symbol: "checkmark.circle", trailing: "9:12"),
                 tappable: true),
            .row(Row(id: "", title: "a row that cannot be tapped", subtitle: nil, symbol: nil, trailing: nil), tappable: false),
            .button(id: "again", title: "Redéployer", style: .prominent, enabled: false),
            .toggle(id: "notify", title: "Tell me", isOn: true, enabled: true, help: nil),
            .field(id: "project", title: "Project", value: "acme/web", placeholder: "owner/name", kind: .secret,
                   help: nil),
            .list(id: "deploys", rows: [Row(id: "api", title: "api 3.8.1", subtitle: "failed", symbol: nil, trailing: nil)]),
            .progress(value: 0.5, label: "worker"),
            .divider,
            .spacer(12),
        ], "each block is drawn as its kind, in the person's language, with what it says; a row with an id can be tapped")
    }

    static func defaultsAndLimits(_ suite: TestSuite) {
        let long = String(repeating: "x", count: BlockTreeContent.maxCharacters + 50)
        let drawn = content(#"""
            {"blocks": [
              {"type": "text", "text": "\#(long)"},
              {"type": "button", "id": "go", "title": "Go"},
              {"type": "field", "id": "name"},
              {"type": "progress"},
              {"type": "spacer"}
            ]}
            """#)
        let kinds = drawn?.items.map(\.kind) ?? []
        if case .text(let text, let style, let lines)? = kinds.first {
            suite.expect(text.count == BlockTreeContent.maxCharacters && text.hasSuffix("…") && style == .body
                             && lines == BlockTreeContent.textLines && BlockTreeContent.textLines == 4,
                         "text is cut to 2,000 characters, and takes four lines of body text unless it says")
        } else {
            suite.expect(false, "a text block is drawn as text")
        }
        suite.expect(kinds.dropFirst() == [
            .button(id: "go", title: "Go", style: .plain, enabled: true),
            .field(id: "name", title: nil, value: "", placeholder: "", kind: .text, help: nil),
            .progress(value: nil, label: nil),
            .spacer(BlockTreeContent.spacerSize),
        ], "a field left out is the protocol's default: a plain button that can be pressed, an empty text field, "
            + "progress under way, eight points of room")
        suite.expect(BlockTreeContent.headingLines == 2 && BlockTreeContent.toggleLines == 2
                         && BlockTreeContent.imageHeight(.island) == 40 && BlockTreeContent.imageHeight(.standard) == 64,
                     "a heading and a switch take two lines; a picture is 40 points high in the island, 64 elsewhere")
    }

    static func linksAndPictures(_ suite: TestSuite) {
        ToolPanelTests.folder { root in
            try? FileManager.default.createDirectory(at: root.appendingPathComponent("ui"), withIntermediateDirectories: true)
            FileManager.default.createFile(atPath: root.appendingPathComponent("ui/logo.png").path, contents: Data([1]))
            let drawn = content(#"""
                {"blocks": [
                  {"type": "link", "title": "Dashboard", "url": "https://example.com/deploys"},
                  {"type": "link", "title": "Write", "url": "mailto:ops@example.com"},
                  {"type": "link", "title": "Run this", "url": "javascript:alert(1)"},
                  {"type": "link", "title": "A file", "url": "file:///etc/hosts"},
                  {"type": "image", "source": "ui/logo.png", "alt": "Logo"},
                  {"type": "image", "source": "../elsewhere.png", "alt": "Elsewhere", "height": 20}
                ]}
                """#, folder: root, size: .island)
            let kinds = drawn?.items.map(\.kind) ?? []
            suite.expect(Array(kinds.prefix(4)) == [
                .link(title: "Dashboard", url: URL(string: "https://example.com/deploys")),
                .link(title: "Write", url: URL(string: "mailto:ops@example.com")),
                .link(title: "Run this", url: nil),
                .link(title: "A file", url: nil),
            ], "a link opens only a web or mail address; any other is drawn as plain words")
            let logo = root.appendingPathComponent("ui/logo.png").resolvingSymlinksInPath().standardizedFileURL
            suite.expect(Array(kinds.suffix(2)) == [
                .image(.file(logo), alt: "Logo", height: 40),
                .image(nil, alt: "Elsewhere", height: 20),
            ], "a picture is found in the tool's folder; one outside it is not, and its alt text stands in")
        }
        let nowhere = content(#"{"blocks": [{"type": "image", "source": "ui/logo.png"}]}"#)
        suite.expect(nowhere?.items.map(\.kind) == [.image(nil, alt: nil, height: 64)],
                     "with no folder to look in, a picture is not drawn")
    }

    static func laterKinds(_ suite: TestSuite) {
        let drawn = content(#"""
            {"blocks": [{"type": "chart", "fallback": {"en": "Five deploys", "de": "Fünf Deployments"}},
                        {"type": "map"},
                        {"type": "divider"}]}
            """#, language: "de")
        suite.expect(drawn?.items.map(\.kind) == [.fallback("Fünf Deployments"), .divider]
                         && drawn?.items.map(\.id) == [0, 2],
                     "a block of a later kind is drawn as its fallback in the person's language, or left out")
    }

    static func detail(_ suite: TestSuite) {
        let english = FeatureStrings.externalTools(.enUS)
        let bench = ExternalToolStoreTests.Bench()
        defer { bench.close() }
        bench.add(bench.folder(manifest: drawing))
        guard let listed = bench.store.listed.first else { return suite.expect(false, "the tool is added") }
        let detail = ExternalToolDetail(listed, files: nil, language: .fr, strings: english, settingsTitle: "Settings",
                                        showsInIsland: bench.store.showsInIsland(id))
        suite.expect(detail.settingsPanel == "settings" && detail.showsInIsland == true
                         && detail.showInIslandTitle == "Show in the Dynamic Island",
                     "a tool with a Settings panel has it drawn in its detail, under the switch for its island page")
        suite.expect(detail.windows == [ExternalToolDetail.Window(id: "log", title: "Journal", symbol: "doc.text"),
                                        ExternalToolDetail.Window(id: "dashboard", title: "Dashboard",
                                                                  symbol: "shippingbox")],
                     "its windows are listed in the person's language, each to be opened with the app's word Open")
        suite.expect(detail.listsScroll && detail.listRows == 1 + 2 + 1 + 1,
                     "with a Settings panel of any height the lists scroll, so the buttons stay in view")

        bench.store.setOn(id, false)
        if let off = bench.store.listed.first {
            let quiet = ExternalToolDetail(off, files: nil, language: .enUS, strings: english)
            suite.expect(quiet.settingsPanel == nil && quiet.windows.isEmpty && quiet.showsInIsland == true,
                         "a tool that is switched off draws no panel and opens no window; its island switch stays")
        }

        let plain = ExternalToolStoreTests.Bench()
        defer { plain.close() }
        plain.add(plain.folder())
        if let listed = plain.store.listed.first {
            let old = ExternalToolDetail(listed, files: nil, language: .enUS, strings: english)
            suite.expect(old.settingsPanel == nil && old.windows.isEmpty && old.showsInIsland == nil && !old.listsScroll,
                         "a tool of protocol 1 has a detail as before: no panel, no window, no island switch")
        }
    }

    static func islandSwitch(_ suite: TestSuite) {
        let bench = ExternalToolStoreTests.Bench()
        defer { bench.close() }
        bench.add(bench.folder(manifest: drawing))
        suite.expect(bench.store.showsInIsland(id) && bench.records.first?.showsInIsland == nil,
                     "a tool's island page is listed until the person says otherwise, and nothing is written for it")
        let island = ToolPanelHost.Key(tool: id, panel: "deploys")
        bench.panels.open(island, in: .island)
        bench.current.greets()
        let revision = bench.registry.revision
        bench.store.setShowsInIsland(id, false)
        suite.expect(!bench.store.showsInIsland(id) && bench.records.first?.showsInIsland == false
                         && bench.panels.shown[island] == nil && bench.registry.revision > revision,
                     "turned off, it is remembered, its open island page closes, and the lists are drawn again")
        let relaunched = bench.relaunched()
        relaunched.store.restore()
        suite.expect(!relaunched.store.showsInIsland(id), "the next launch remembers it")
        bench.add(bench.folder(manifest: drawing))
        suite.expect(!bench.store.showsInIsland(id), "an update keeps it")
        bench.store.setShowsInIsland(id, true)
        suite.expect(bench.store.showsInIsland(id) && bench.records.first?.showsInIsland == nil,
                     "turned on again, the record is as it was before")
    }

    static func islandTiles(_ suite: TestSuite) {
        let bench = ExternalToolStoreTests.Bench()
        defer { bench.close() }
        bench.add(bench.folder(manifest: drawing))
        bench.add(bench.folder("other", manifest: ExternalToolManifestTests.file(#"{"id": "com.acme.other"}"#)))
        func tiles() -> [ToolIslandEntry] { ToolIslandEntry.all(store: bench.store, host: bench.panels, language: .fr) }
        let island = ToolPanelHost.Key(tool: id, panel: "deploys")
        suite.expect(tiles() == [ToolIslandEntry(key: island, title: "Deploys", symbol: "shippingbox", badge: nil)]
                         && bench.store.islandPanels() == [island],
                     "the island lists a section for each tool's island page, and none for a tool without one")
        bench.panels.badge(id, UIBadgeParams(count: 3))
        suite.expect(tiles().first?.count == "3" && tiles().first?.dot == false, "the tile carries the tool's count")
        bench.panels.badge(id, UIBadgeParams(count: 120))
        suite.expect(tiles().first?.count == "99+", "a count over 99 is drawn as 99+")
        bench.panels.badge(id, UIBadgeParams(dot: true))
        suite.expect(tiles().first?.count == nil && tiles().first?.dot == true, "or a dot")
        bench.store.setShowsInIsland(id, false)
        suite.expect(tiles().isEmpty, "a page the person turned off has no tile")
        bench.store.setShowsInIsland(id, true)
        bench.store.setOn(id, false)
        suite.expect(tiles().isEmpty, "a tool that is switched off has no tile")
    }
}

extension ToolPanelScreensTests {
    /// What the island's editor offers: every island page there is, the
    /// ones the person turned off too, and none for a tool without one.
    static func availableIslandSections(_ suite: TestSuite) {
        let bench = ExternalToolStoreTests.Bench()
        defer { bench.close() }
        bench.add(bench.folder(manifest: drawing))
        bench.add(bench.folder("other", manifest: ExternalToolManifestTests.file(#"{"id": "com.acme.other"}"#)))
        let island = ToolPanelHost.Key(tool: id, panel: "deploys")
        func available() -> [ToolIslandEntry] {
            ToolIslandEntry.available(store: bench.store, host: bench.panels, language: .fr)
        }
        suite.expect(bench.store.availableIslandPanels() == [island] && bench.store.islandPanels() == [island],
                     "a tool's island page is available and listed; a tool without one has neither")
        bench.store.setShowsInIsland(id, false)
        suite.expect(bench.store.availableIslandPanels() == [island] && bench.store.islandPanels().isEmpty,
                     "a page the person turned off is still available to show again, though not listed")
        bench.panels.badge(id, UIBadgeParams(count: 120))
        suite.expect(available() == [ToolIslandEntry(key: island, title: "Deploys", symbol: "shippingbox",
                                                     badge: .count(120))]
                         && available().first?.count == "99+" && ToolIslandEntry.all(store: bench.store, host: bench.panels,
                                                                                      language: .fr).isEmpty,
                     "the editor's entry has the page's title, symbol and badge, whether or not it is shown")
        bench.panels.badge(id, UIBadgeParams(dot: true))
        suite.expect(available().first?.dot == true && available().first?.count == nil, "or its dot")
        bench.store.setOn(id, false)
        suite.expect(bench.store.availableIslandPanels().isEmpty && available().isEmpty,
                     "a tool that is switched off has no page to offer")
    }

    /// A quick-access button for a tool's island page, read from the
    /// tools added: the page's title and symbol, shown while the island
    /// lists the page.
    static func islandQuickActions(_ suite: TestSuite) {
        let bench = ExternalToolStoreTests.Bench()
        defer { bench.close() }
        bench.add(bench.folder(manifest: drawing))
        bench.add(bench.folder("other", manifest: ExternalToolManifestTests.file(#"{"id": "com.acme.other"}"#)))
        let action = NotchQuickAction.extensionPanel(id)
        func lookup() -> NotchExtensionActions { NotchExtensionActions.live(language: .fr, store: bench.store) }
        suite.expect(lookup().actions == [action] && lookup().title(action) == "Deploys" && lookup().symbol(action) == "shippingbox"
                         && lookup().isAvailable(action),
                     "a tool's island page is offered as a button with its page's title and symbol; a tool without one is not")
        bench.store.setShowsInIsland(id, false)
        suite.expect(lookup().actions == [action] && !lookup().isAvailable(action),
                     "hidden, the page is still there to choose, and the island leaves its button out")
        bench.store.setOn(id, false)
        suite.expect(lookup().actions.isEmpty && !lookup().isAvailable(action) && lookup().title(action) == id.rawValue,
                     "switched off, the tool offers no button, and a saved one names its tool")
    }

    static func aChoiceIsAMenu(_ suite: TestSuite) {
        typealias Choice = ExternalToolSetting.Choice
        let page = #"""
            {"blocks": [
              {"type": "choice", "id": "light", "title": {"en": "Mouse when green", "de": "Maus bei Grün"},
               "value": "breathe green", "fallback": "Mouse when green: Pulsing green",
               "options": [{"value": "green", "title": "Green"},
                           {"value": "breathe green", "title": {"en": "Pulsing green", "de": "Pulsierendes Grün"}}]},
              {"type": "choice", "id": "idle", "value": "typed by hand", "enabled": false,
               "options": [{"value": "restore", "title": "Restore my lighting"}, {"value": "off", "title": "Turn the light off"}]}
            ]}
            """#
        let kinds = content(page, language: "de")?.items.map(\.kind) ?? []
        suite.expect(kinds.first == .choice(id: "light", title: "Maus bei Grün", selected: "breathe green",
                                            options: [Choice(value: "green", title: "Green", isStored: false),
                                                      Choice(value: "breathe green", title: "Pulsierendes Grün", isStored: false)],
                                            enabled: true, help: nil),
                     "a choice block is a menu with its options in order, in the person's language, its selected "
                         + "value, and never its fallback")
        suite.expect(kinds.last == .choice(id: "idle", title: nil, selected: "typed by hand",
                                           options: [Choice(value: "typed by hand", title: "typed by hand", isStored: true),
                                                     Choice(value: "restore", title: "Restore my lighting", isStored: false),
                                                     Choice(value: "off", title: "Turn the light off", isStored: false)],
                                           enabled: false, help: nil),
                     "a value that is no option's is an extra first row, as written; a choice that is not enabled "
                         + "is drawn dimmed; one with no title has none")
        let long = content(#"""
            {"blocks": [{"type": "choice", "id": "p", "value": "a",
                         "options": [{"value": "a", "title": "\#(String(repeating: "x", count: 500))"}]}]}
            """#)?.items.first?.kind
        if case .choice(_, _, _, let options, _, _)? = long {
            suite.expect(options.first?.title.count == ToolOwnWords.limit && options.first?.title.hasSuffix("…") == true,
                         "an option's title is drawn as one line, cut where it is too long")
        } else {
            suite.expect(false, "a choice with a long title is still a menu")
        }
    }

    /// HomeSpeaker's networks as chips: one muted, one it cannot mute.
    static let networks = #"""
        {"blocks": [
          {"type": "chips", "id": "muted", "title": {"en": "Read aloud", "de": "Vorlesen"},
           "help": {"en": "Tap a network to mute it.", "de": "Tippe auf ein Netz, um es stummzuschalten."},
           "fallback": "Muted: WhatsApp",
           "options": [{"value": "whatsapp", "title": "WhatsApp", "on": true},
                       {"value": "signal", "title": "Signal", "on": false},
                       {"value": "slack", "title": "Slack", "on": false, "enabled": false,
                        "reason": {"en": "Slack has its own switch.", "de": "Slack hat einen eigenen Schalter."}},
                       {"value": "imessage", "title": {"en": "Messages", "de": "Nachrichten"}, "on": true}]},
          {"type": "chips", "id": "rooms", "enabled": false,
           "options": [{"value": "kitchen", "title": "Kitchen", "on": true}]}
        ]}
        """#

    static func aChipsBlockIsChips(_ suite: TestSuite) {
        func chip(_ value: String, _ title: String, on: Bool, enabled: Bool = true, reason: String? = nil)
            -> BlockTreeContent.Chip {
            BlockTreeContent.Chip(value: value, title: title, on: on, enabled: enabled, reason: reason)
        }
        let kinds = content(networks, language: "de")?.items.map(\.kind) ?? []
        suite.expect(kinds.first == .chips(id: "muted", title: "Vorlesen",
                                           options: [chip("whatsapp", "WhatsApp", on: true),
                                                     chip("signal", "Signal", on: false),
                                                     chip("slack", "Slack", on: false, enabled: false,
                                                          reason: "Slack hat einen eigenen Schalter."),
                                                     chip("imessage", "Nachrichten", on: true)],
                                           enabled: true, help: "Tippe auf ein Netz, um es stummzuschalten."),
                     "a chips block is chips, never its fallback: its title, each option on or off in order, in the "
                         + "person's language, and its help")
        suite.expect(kinds.last == .chips(id: "rooms", title: nil, options: [chip("kitchen", "Kitchen", on: true)],
                                          enabled: false, help: nil),
                     "chips that are not enabled are drawn dimmed; with no title they have none")
        let long = content(#"""
            {"blocks": [{"type": "chips", "id": "c",
                         "options": [{"value": "a", "title": "\#(String(repeating: "x", count: 500))", "on": false}]}]}
            """#)?.items.first?.kind
        if case .chips(_, _, let options, _, _)? = long {
            suite.expect(options.first?.title.count == ToolOwnWords.limit && options.first?.title.hasSuffix("…") == true,
                         "a chip's title is one line, cut where it is too long")
        } else {
            suite.expect(false, "chips with a long title are still chips")
        }
    }

    static func chipsSendTheSetThatIsOn(_ suite: TestSuite) {
        guard case .chips(let id, _, let options, let enabled, _)? = content(networks)?.items.first?.kind else {
            suite.expect(false, "a chips block is chips")
            return
        }
        var sent: [(String, UIEventKind, JSONValue?)] = []
        let act: (String, UIEventKind, JSONValue?) -> Void = { sent.append(($0, $1, $2)) }
        BlockTreeContent.turnChip("signal", of: id, options: options, enabled: enabled, act: act)
        suite.expect(sent.count == 1 && sent.first?.0 == "muted" && sent.first?.1 == .change
                         && sent.first?.2 == .array([.string("whatsapp"), .string("signal"), .string("imessage")]),
                     "turning a chip on sends change with every value then on, in the options' order")
        sent = []
        BlockTreeContent.turnChip("whatsapp", of: id, options: options, enabled: enabled, act: act)
        suite.expect(sent.count == 1 && sent.first?.2 == .array([.string("imessage")]),
                     "turning a chip off sends the set without it")
        sent = []
        let one = [BlockTreeContent.Chip(value: "a", title: "A", on: true, enabled: true, reason: nil)]
        BlockTreeContent.turnChip("a", of: "c", options: one, enabled: true, act: act)
        suite.expect(sent.count == 1 && sent.first?.2 == .array([]),
                     "turning the last chip off sends an empty set")
        sent = []
        BlockTreeContent.turnChip("a", of: "c", options: one, enabled: false, act: act)
        BlockTreeContent.turnChip("nowhere", of: id, options: options, enabled: true, act: act)
        suite.expect(sent.isEmpty, "chips that are not enabled, or a value that is no chip's, send nothing")
    }

    /// Two chips tapped before the tool sends the page again: the second
    /// tap starts from the first, not from the page as last drawn.
    static func twoQuickChipTapsKeepTheFirst(_ suite: TestSuite) {
        func chip(_ value: String, on: Bool) -> BlockTreeContent.Chip {
            BlockTreeContent.Chip(value: value, title: value.uppercased(), on: on, enabled: true, reason: nil)
        }
        let none = [chip("a", on: false), chip("b", on: false), chip("c", on: false)]
        var picks = BlockTreeContent.ChipPicks()
        let first = picks.turn("a", of: "k", options: none, enabled: true)
        let second = picks.turn("b", of: "k", options: none, enabled: true)
        suite.expect(first == .array([.string("a")]) && second == .array([.string("a"), .string("b")]),
                     "two taps before the page returns send [a] then [a, b], not [a] then [b]: "
                         + "\(String(describing: first)), \(String(describing: second))")
        let caught = [chip("a", on: true), chip("b", on: true), chip("c", on: false)]
        suite.expect(picks.turn("a", of: "k", options: caught, enabled: true) == .array([.string("b")]),
                     "once the page shows the pick, a tap starts from the page")
        let refused = [chip("a", on: false), chip("b", on: false), chip("c", on: true)]
        suite.expect(picks.turn("b", of: "k", options: refused, enabled: true) == .array([.string("b"), .string("c")]),
                     "a page that shows another set for the block is followed: the tool had the last word")
        var others = BlockTreeContent.ChipPicks()
        _ = others.turn("a", of: "k", options: none, enabled: true)
        suite.expect(others.turn("a", of: "j", options: none, enabled: true) == .array([.string("a")])
                         && others.turn("z", of: "k", options: none, enabled: true) == nil,
                     "a pick is kept for its own chips block only, and a value that is no chip's sends nothing")
    }

    static func aDisabledChipSaysWhy(_ suite: TestSuite) {
        guard case .chips(let id, _, let options, let enabled, _)? = content(networks)?.items.first?.kind else {
            suite.expect(false, "a chips block is chips")
            return
        }
        let slack = options.first { $0.value == "slack" }
        suite.expect(slack?.enabled == false && slack?.reason == "Slack has its own switch.",
                     "a chip that cannot be turned is dimmed and says why")
        let quiet = content(#"""
            {"blocks": [{"type": "chips", "id": "c",
                         "options": [{"value": "a", "title": "A", "on": false, "reason": "Never shown"}]}]}
            """#)?.items.first?.kind
        if case .chips(_, _, let options, _, _)? = quiet {
            suite.expect(options.first?.reason == nil, "a chip that can be turned shows no reason")
        } else {
            suite.expect(false, "chips with a reason are still chips")
        }
        var sent = 0
        BlockTreeContent.turnChip("slack", of: id, options: options, enabled: enabled, act: { _, _, _ in sent += 1 })
        suite.expect(sent == 0, "tapping a chip that cannot be turned does nothing")
    }

    static func helpShowsUnderItsControl(_ suite: TestSuite) {
        let kinds = content(#"""
            {"blocks": [
              {"type": "toggle", "id": "t", "title": "Announce", "value": true,
               "help": {"en": "Read new messages aloud.", "fr": "Lire les nouveaux messages."}},
              {"type": "choice", "id": "c", "title": "Room", "value": "all", "help": "Where it is said.",
               "options": [{"value": "all", "title": "All"}]},
              {"type": "field", "id": "f", "title": "Name", "help": "What it is called."},
              {"type": "chips", "id": "k", "help": "Pick any.", "options": [{"value": "a", "title": "A", "on": false}]},
              {"type": "toggle", "id": "plain", "title": "No help", "value": false}
            ]}
            """#, language: "fr")?.items.map(\.kind) ?? []
        suite.expect(kinds == [
            .toggle(id: "t", title: "Announce", isOn: true, enabled: true, help: "Lire les nouveaux messages."),
            .choice(id: "c", title: "Room", selected: "all",
                    options: [ExternalToolSetting.Choice(value: "all", title: "All", isStored: false)],
                    enabled: true, help: "Where it is said."),
            .field(id: "f", title: "Name", value: "", placeholder: "", kind: .text, help: "What it is called."),
            .chips(id: "k", title: nil,
                   options: [BlockTreeContent.Chip(value: "a", title: "A", on: false, enabled: true, reason: nil)],
                   enabled: true, help: "Pick any."),
            .toggle(id: "plain", title: "No help", isOn: false, enabled: true, help: nil),
        ], "a switch, a menu, a field and chips each carry their help in the person's language, drawn under the "
            + "control; one without help has none")
        suite.expect(BlockTreeContent.helpLines == 2, "help takes two lines at most")
    }

    static func sectionHeadingsAreListed(_ suite: TestSuite) {
        let drawn = content(#"""
            {"blocks": [
              {"type": "heading", "text": {"en": "Speakers", "fr": "Enceintes"}, "section": true},
              {"type": "toggle", "id": "t", "title": "Announce", "value": true},
              {"type": "heading", "text": "Quiet hours"},
              {"type": "map"},
              {"type": "heading", "text": "Chats", "section": true},
              {"type": "heading", "text": "Not a section", "section": false}
            ]}
            """#, language: "fr")
        let kinds = drawn?.items.map(\.kind) ?? []
        suite.expect(kinds.first == .heading("Enceintes", section: true)
                         && kinds.dropFirst(2).first == .heading("Quiet hours", section: false)
                         && kinds.last == .heading("Not a section", section: false),
                     "a heading that starts a section says so; a heading without it, or with false, is a sub-heading")
        let sections = drawn?.sections ?? []
        suite.expect(sections.map(\.title) == ["Enceintes", "Chats"] && sections.map(\.index) == [0, 4],
                     "the page lists its sections in order, each with its item's place in the page, past a block "
                         + "it leaves out: \(sections)")
        suite.expect(content(#"{"blocks": [{"type": "heading", "text": "Today"}]}"#)?.sections.isEmpty == true,
                     "a page with no section headings lists none")
    }
}
