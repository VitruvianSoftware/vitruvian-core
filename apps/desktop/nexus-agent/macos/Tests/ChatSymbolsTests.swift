// Copyright (c) 2026 VitruvianSoftware
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

import AppKit
import XCTest

/// Rules over how the shared chat view is written, checked by reading its
/// source. The Vitruvian app has lints that did this while the view lived
/// there (every SF Symbol it draws exists; nothing names another app's
/// settings); they walk only that app's folder, so the same rules are kept
/// here, beside the code they are about.
final class ChatSymbolsTests: XCTestCase {

    // MARK: - Finding the sources

    /// Where the chat view's sources are on this machine. Bazel runs the
    /// test in a folder of its own, so they come from the target's runfiles
    /// (the `shared_ui_sources` data); under SwiftPM or Xcode the test
    /// file's own path leads to them.
    private func sourcesDirectory() -> String? {
        let relative = "apps/desktop/nexus-agent/macos/Sources/NexusAgentUI"
        var candidates: [String] = []
        let environment = ProcessInfo.processInfo.environment
        if let runfiles = environment["TEST_SRCDIR"] {
            for workspace in [environment["TEST_WORKSPACE"], "_main"].compactMap({ $0 }) {
                candidates.append("\(runfiles)/\(workspace)/\(relative)")
            }
        }
        let here = (#filePath as NSString).deletingLastPathComponent
        candidates.append((here as NSString).deletingLastPathComponent + "/Sources/NexusAgentUI")
        return candidates.first { FileManager.default.fileExists(atPath: $0) }
    }

    private func swiftFiles() -> [(name: String, text: String)] {
        guard let directory = sourcesDirectory() else {
            XCTFail("could not find the NexusAgentUI sources to check")
            return []
        }
        let names = ((try? FileManager.default.subpathsOfDirectory(atPath: directory)) ?? [])
            .filter { $0.hasSuffix(".swift") }
            .sorted()
        let files = names.compactMap { name in
            (try? String(contentsOfFile: directory + "/" + name, encoding: .utf8)).map { (name, $0) }
        }
        // An empty list would let every check below pass without looking.
        XCTAssertFalse(files.isEmpty, "no Swift files found under \(directory)")
        XCTAssertEqual(files.count, names.count, "every source file is readable")
        return files
    }

    func testTheSourcesAreFound() {
        let names = Set(swiftFiles().map(\.name))
        for expected in ["NexusAgentChatStrings.swift", "NexusAgentChatChrome.swift"] {
            XCTAssertTrue(names.contains(expected), "\(expected) is among the sources read: \(names.sorted())")
        }
    }

    // MARK: - Every symbol the view draws exists

    /// What `symbolNames` found in one piece of source: the names written
    /// out, and the lines that name a symbol in a way it cannot read.
    struct SymbolFindings: Equatable {
        var names: Set<String> = []
        var unreadable: [String] = []
    }

    /// The argument labels that take an SF Symbol's name. `icon:` is this
    /// library's own: every view here that takes an `icon` draws it with
    /// `Image(systemName:)`.
    static let symbolLabels = ["systemName:", "systemSymbolName:", "systemImage:", "icon:"]

    /// Every SF Symbol name written in `source`. A name is a string literal
    /// in the argument that follows one of `symbolLabels`; the argument may
    /// choose between several (`copied ? "checkmark" : "doc.on.doc"`), and
    /// each is collected. An argument with no literal is a name passed in
    /// from elsewhere, which is fine as long as it was a literal there; a
    /// literal with an interpolation in it can never be checked, and is
    /// reported.
    static func symbolNames(in source: String) -> SymbolFindings {
        var findings = SymbolFindings()
        for line in source.components(separatedBy: "\n") {
            let code = line.trimmingCharacters(in: .whitespaces)
            if code.hasPrefix("//") { continue }
            for label in symbolLabels {
                var rest = Substring(code)
                while let found = rest.range(of: label) {
                    // `icon:` must be a label of its own, not the tail of another name.
                    let standsAlone = found.lowerBound == rest.startIndex
                        || !(rest[rest.index(before: found.lowerBound)].isLetter
                             || rest[rest.index(before: found.lowerBound)].isNumber)
                    rest = rest[found.upperBound...]
                    guard standsAlone else { continue }
                    for literal in literals(inArgument: rest) {
                        if literal.contains("\\(") {
                            findings.unreadable.append(code)
                        } else {
                            findings.names.insert(literal)
                        }
                    }
                }
            }
        }
        return findings
    }

    /// The string literals in one call argument: from the start of `text`
    /// to the comma or closing bracket that ends the argument.
    private static func literals(inArgument text: Substring) -> [String] {
        var found: [String] = []
        var depth = 0
        var literal: String?
        var escaped = false
        for character in text {
            if var open = literal {
                if escaped {
                    open.append(character)
                    escaped = false
                    literal = open
                } else if character == "\\" {
                    open.append(character)
                    escaped = true
                    literal = open
                } else if character == "\"" {
                    found.append(open)
                    literal = nil
                } else {
                    open.append(character)
                    literal = open
                }
                continue
            }
            switch character {
            case "\"": literal = ""
            case "(", "[", "{": depth += 1
            case ")", "]", "}":
                if depth == 0 { return found }
                depth -= 1
            case ",":
                if depth == 0 { return found }
            default: break
            }
        }
        return found
    }

    func testEverySymbolTheChatDrawsExists() {
        for file in swiftFiles() {
            let findings = Self.symbolNames(in: file.text)
            XCTAssertEqual(findings.unreadable, [], "\(file.name) builds a symbol's name at run time, so it cannot be checked")
            for name in findings.names.sorted() {
                XCTAssertNotNil(NSImage(systemSymbolName: name, accessibilityDescription: nil),
                                "\(file.name) draws the SF Symbol \"\(name)\", which this macOS does not have")
            }
        }
    }

    /// The check above is only worth something if a wrong name fails it.
    func testAMadeUpSymbolIsCaught() {
        let source = """
        Image(systemName: "sparkles")
        // Image(systemName: "in.a.comment")
        Image(systemName: copied ? "checkmark" : "doc.on.doc").help("Copy source")
        Label(title, systemImage: "definitely.not.a.symbol")
        NSImage(systemSymbolName: "folder", accessibilityDescription: "not a symbol")
        ModularButtonView(icon: open ? "clock.fill" : "clock", isActive: open, help: "Recent sessions") {
        environmentRow(label: "Model", value: model, icon: "cube")
        Image(systemName: icon)
        Image(systemName: "chevron.\\(direction)")
        """
        let findings = Self.symbolNames(in: source)
        XCTAssertEqual(findings.names, ["sparkles", "checkmark", "doc.on.doc", "definitely.not.a.symbol", "folder",
                                        "clock.fill", "clock", "cube"])
        XCTAssertEqual(findings.unreadable, ["Image(systemName: \"chevron.\\(direction)\")"])
        XCTAssertNil(NSImage(systemSymbolName: "definitely.not.a.symbol", accessibilityDescription: nil),
                     "a name that is not a symbol's is refused by the system, which is what fails the check")
        XCTAssertNotNil(NSImage(systemSymbolName: "sparkles", accessibilityDescription: nil))
    }

    // MARK: - The view stays free of any one app

    /// What may not appear in the shared chat view, and why.
    static let forbidden: [(text: String, why: String)] = [
        ("import Vitruvian", "imports a module of the Vitruvian app"),
        ("UserDefaults", "reads saved settings; an app hands the view what it needs"),
        ("@AppStorage", "reads saved settings; an app hands the view what it needs"),
        ("vitruvian.", "names a Vitruvian saved-settings key"),
        ("vitruvian-error", "names Vitruvian's URL scheme; the app passes its own in"),
        ("NexusAgentService", "names Vitruvian's service; the view is handed an engine"),
    ]

    static func forbiddenUses(in source: String) -> [String] {
        forbidden.filter { source.contains($0.text) }.map(\.why)
    }

    func testTheChatViewNamesNoApp() {
        for file in swiftFiles() {
            XCTAssertEqual(Self.forbiddenUses(in: file.text), [], "\(file.name)")
        }
    }

    func testANamedAppIsCaught() {
        XCTAssertEqual(Self.forbiddenUses(in: "import SwiftUI\nimport NexusAgentCore\n"), [])
        XCTAssertEqual(Self.forbiddenUses(in: "import VitruvianCore\n").count, 1)
        XCTAssertEqual(Self.forbiddenUses(in: "@AppStorage(\"vitruvian.x\") var x = false").count, 2)
        XCTAssertEqual(Self.forbiddenUses(in: "let service = NexusAgentService.shared").count, 1)
        XCTAssertEqual(Self.forbiddenUses(in: "url.scheme == \"vitruvian-error\"").count, 1)
    }
}
