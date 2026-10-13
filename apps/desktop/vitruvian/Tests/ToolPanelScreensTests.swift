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
    }

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
}
