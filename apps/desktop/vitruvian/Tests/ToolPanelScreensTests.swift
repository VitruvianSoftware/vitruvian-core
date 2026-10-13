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
            .heading("Aujourd’hui"),
            .text("Three deploys", style: .secondary, lines: 2),
            .row(Row(id: "latest", title: "web 1.42.0", subtitle: "main", symbol: "checkmark.circle", trailing: "9:12"),
                 tappable: true),
            .row(Row(id: "", title: "a row that cannot be tapped", subtitle: nil, symbol: nil, trailing: nil), tappable: false),
            .button(id: "again", title: "Redéployer", style: .prominent, enabled: false),
            .toggle(id: "notify", title: "Tell me", isOn: true, enabled: true),
            .field(id: "project", title: "Project", value: "acme/web", placeholder: "owner/name", kind: .secret),
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
            .field(id: "name", title: nil, value: "", placeholder: "", kind: .text),
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
                     "the Tools area has a tile for each tool's island page, and none for a tool without one")
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
