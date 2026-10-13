// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import Foundation
import VitruvianCore
import VitruvianToolProtocol

/// A page a tool sends, as the app reads it: within its limits, with a
/// block of a later kind kept for its fallback; and what a web panel may
/// load. Files are made under the temporary folder, in a folder the test
/// makes and removes.
enum ToolPanelTests {
    static func run(_ suite: TestSuite) {
        pages(suite)
        theLimit(suite)
        laterKinds(suite)
        webPages(suite)
        pictures(suite)
    }

    static func json(_ text: String) -> JSONValue {
        (try? JSONDecoder().decode(JSONValue.self, from: Data(text.utf8))) ?? .null
    }

    static func pages(_ suite: TestSuite) {
        let read = ToolPanelTree.read(json(#"""
            {"blocks": [{"type": "heading", "text": {"en": "Today", "fr": "Aujourd’hui"}},
                        {"type": "button", "id": "again", "title": "Deploy again", "style": "prominent"},
                        {"type": "list", "id": "deploys", "rows": [{"id": "web", "title": "web 1.42.0"}]}]}
            """#))
        guard case .success(let tree) = read else { return suite.expect(false, "a page is read: \(read)") }
        suite.expect(tree.blocks.map(\.type) == ["heading", "button", "list"] && tree.blocks[1].id == "again",
                     "a page is its blocks, in order, each with its kind and its id")
        if case .heading(let heading) = tree.blocks[0].content {
            suite.expect(heading.text.text(for: "fr") == "Aujourd’hui" && heading.text.text(for: "de") == "Today",
                         "text in languages is found for a language, as a manifest's is")
        }
        suite.expect(ToolPanelTree.read(json(#"{"blocks": [{"type": "button", "title": "Go"}]}"#))
                         == .failure(.notWellFormed("blocks[0].id")),
                     "a button with no id refuses the page, and says where")
        suite.expect(ToolPanelTree.read(json(#"{"blocks": [{"type": "text", "style": "caption"}]}"#))
                         == .failure(.notWellFormed("blocks[0].text")),
                     "a block of a kind the app knows, with a field missing, refuses the page")
        suite.expect(ToolPanelTree.read(json(#"{"blocks": [{"type": "progress", "value": 1.5}]}"#))
                         == .failure(.notWellFormed("blocks[0].value")),
                     "a value past its bounds refuses the page")
        suite.expect(ToolPanelTree.read(json(#"{"blocks": {"type": "divider"}}"#)) == .failure(.notWellFormed("blocks"))
                         && ToolPanelTree.read(json("[]")) == .failure(.notWellFormed("the page")),
                     "something that is not a page is refused")
        let most = (0..<UILimits.maxBlocks).map { _ in #"{"type": "divider"}"# }.joined(separator: ",")
        suite.expect((try? ToolPanelTree.read(json(#"{"blocks": [\#(most)]}"#)).get().blocks.count) == UILimits.maxBlocks
                         && ToolPanelTree.read(json(#"{"blocks": [\#(most), {"type": "divider"}]}"#))
                         == .failure(.notWellFormed("blocks")),
                     "a page holds 200 blocks, and one more refuses it")
    }

    /// The 256 KB are counted as the app writes the page again: compact,
    /// with slashes as they are.
    static func theLimit(_ suite: TestSuite) {
        func page(_ length: Int) -> JSONValue {
            .object(["blocks": .array([.object(["type": .string("text"),
                                                "text": .string(String(repeating: "a/", count: length / 2))])])])
        }
        let frame = (try? JSONEncoder().encode(page(0)).count) ?? 0
        let fits = page(UILimits.maxTreeBytes - frame)
        let over = page(UILimits.maxTreeBytes - frame + 2)
        suite.expect(UILimits.maxTreeBytes == 262_144 && (try? ToolPanelTree.read(fits).get()) != nil,
                     "a page of exactly 262,144 bytes is drawn")
        suite.expect(ToolPanelTree.read(over) == .failure(.tooLarge(bytes: UILimits.maxTreeBytes + 2)),
                     "a page over 262,144 bytes is refused, and the reason says how large it was")
    }

    static func laterKinds(_ suite: TestSuite) {
        let read = try? ToolPanelTree.read(json(#"""
            {"blocks": [{"type": "chart", "id": "week", "fallback": "Five deploys this week", "points": [1, 2]},
                        {"type": "map"},
                        {"type": "divider"}]}
            """#)).get()
        suite.expect(read?.blocks.map(\.type) == ["chart", "map", "divider"],
                     "a block of a kind the app does not know is kept, by its name, and the page is drawn")
        suite.expect(read?.blocks[0].content == .unknown("chart") && read?.blocks[0].fallback == .plain("Five deploys this week")
                         && read?.blocks[1].fallback == nil,
                     "it carries its fallback when it has one, to be drawn in its place")
    }

    /// A folder for one test, under the temporary folder, removed after.
    static func folder(_ build: (URL) throws -> Void) rethrows {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("vitruvian-panel-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try build(root)
    }

    static func webPages(_ suite: TestSuite) {
        folder { root in
            let tool = root.appendingPathComponent("tool", isDirectory: true)
            let twin = root.appendingPathComponent("tool-other", isDirectory: true)
            for made in [tool.appendingPathComponent("ui"), twin] {
                try? FileManager.default.createDirectory(at: made, withIntermediateDirectories: true)
            }
            for file in [tool.appendingPathComponent("ui/page.html"), twin.appendingPathComponent("page.html"),
                         root.appendingPathComponent("secret.html")] {
                FileManager.default.createFile(atPath: file.path, contents: Data("<p>".utf8))
            }
            try? FileManager.default.createSymbolicLink(at: tool.appendingPathComponent("ui/out.html"),
                                                        withDestinationURL: root.appendingPathComponent("secret.html"))
            try? FileManager.default.createSymbolicLink(at: tool.appendingPathComponent("ui/in.html"),
                                                        withDestinationURL: tool.appendingPathComponent("ui/page.html"))
            let page = tool.appendingPathComponent("ui/page.html")
            suite.expect(ToolWebPolicy.allows(page, in: tool)
                             && ToolWebPolicy.allows(URL(fileURLWithPath: tool.path + "/ui/page.html#top"), in: tool)
                             && ToolWebPolicy.allows(tool.appendingPathComponent("ui/in.html"), in: tool)
                             && ToolWebPolicy.allows(URL(string: "about:blank")!, in: tool),
                         "a web panel may go to a file of its tool's folder, through a link that stays inside too")
            let refused: [URL] = [
                root.appendingPathComponent("secret.html"),
                URL(fileURLWithPath: tool.path + "/../secret.html"),
                twin.appendingPathComponent("page.html"),
                tool.appendingPathComponent("ui/out.html"),
                tool,
                URL(string: "https://example.com/")!,
                URL(string: "http://localhost:8080/page.html")!,
                URL(string: "data:text/html,<p>hi")!,
                URL(string: "javascript:alert(1)")!,
            ]
            let wrongly = refused.filter { ToolWebPolicy.allows($0, in: tool) }
            suite.expect(wrongly.isEmpty,
                         "a web panel may go nowhere else: not above its folder, not into one whose name starts "
                             + "the same, not through a link out, not to the network (\(wrongly))")
            suite.expect(ToolWebPolicy.entry("ui/page.html", in: tool) == page.resolvingSymlinksInPath().standardizedFileURL
                             && ToolWebPolicy.entry("ui/out.html", in: tool) == nil
                             && ToolWebPolicy.entry("ui/missing.html", in: tool) == nil
                             && ToolWebPolicy.entry("ui", in: tool) == nil
                             && ToolWebPolicy.entry("../secret.html", in: tool) == nil,
                         "a panel's page is a file inside the folder, with every link followed; anything else is none")
        }
    }

    static func pictures(_ suite: TestSuite) {
        folder { root in
            let tool = root.appendingPathComponent("tool", isDirectory: true)
            try? FileManager.default.createDirectory(at: tool.appendingPathComponent("ui"), withIntermediateDirectories: true)
            FileManager.default.createFile(atPath: tool.appendingPathComponent("ui/logo.png").path, contents: Data([1]))
            FileManager.default.createFile(atPath: root.appendingPathComponent("other.png").path, contents: Data([1]))
            let png = Data([0x89, 0x50, 0x4E, 0x47])
            suite.expect(ToolPanelImage.resolve("ui/logo.png", in: tool)
                             == .file(tool.appendingPathComponent("ui/logo.png").resolvingSymlinksInPath().standardizedFileURL)
                             && ToolPanelImage.resolve("data:image/png;base64," + png.base64EncodedString(), in: tool)
                             == .bytes(png),
                         "a picture is a file of the tool's folder, or its own bytes in a data: address")
            suite.expect(ToolPanelImage.resolve("../other.png", in: tool) == nil
                             && ToolPanelImage.resolve("/etc/hosts", in: tool) == nil
                             && ToolPanelImage.resolve("ui/missing.png", in: tool) == nil
                             && ToolPanelImage.resolve("data:image/svg+xml;base64,PHN2Zz4=", in: tool) == nil
                             && ToolPanelImage.resolve("https://example.com/a.png", in: tool) == nil,
                         "anything else draws no picture: outside the folder, missing, not a PNG or JPEG, or remote")
        }
    }
}
