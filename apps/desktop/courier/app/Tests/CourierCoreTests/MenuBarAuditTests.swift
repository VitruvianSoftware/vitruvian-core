// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import CourierCore
import Foundation
import XCTest

/// The menu bar has no dead or duplicate items.
///
/// SwiftUI builds the menu bar from the app's `Commands` only inside a running app: no test can ask it for the menus.
/// So this reads the commands' source (the files that declare the Courier, File, Edit, View, Chat, Message and Help
/// menus' items, and App.swift's scenes) and checks what the running menus showed going wrong:
/// - every item does something when chosen (it has an action);
/// - no two items share a title, a shortcut, or the shortcut setting they show;
/// - no item repeats one that macOS or SwiftUI already puts in the menu (File ▸ Close and Close All, the Settings
///   scene's own Settings…, Help ▸ Courier Help with no help book behind it);
/// - no item is placed before a standard group the app also replaces, which SwiftUI silently drops (Minimize to Menu
///   Bar never showed).
final class MenuBarAuditTests: XCTestCase {
    /// One menu item as declared: a `Button(…)` in a commands file.
    private struct Item {
        let file: String
        let title: String
        let hasAction: Bool
        let registryID: String?
        let chord: KeyChord?
    }

    private static func sourceDirectory() throws -> URL {
        let protocolDirectory = try XCTUnwrap(ProtocolConformanceTests.protocolDirectory(),
                                              "the test reads the app's source next to the protocol")
        return protocolDirectory.deletingLastPathComponent().appendingPathComponent("app/Sources/Courier")
    }

    private static func source(_ name: String) throws -> String {
        let text = try String(contentsOf: sourceDirectory().appendingPathComponent(name), encoding: .utf8)
        return SwiftSource.strippingComments(text)
    }

    /// The commands: the two `Commands` structs, and the File ▸ Open… item MenuBar.swift declares for them.
    private static func commandSources() throws -> [(file: String, text: String)] {
        let menuBar = try source("MenuBar.swift")
        let openItem = String(menuBar[try XCTUnwrap(menuBar.range(of: "struct FileOpenCommandItem"))
            .lowerBound...])
        return [
            ("InboxCommands.swift", try source("InboxCommands.swift")),
            ("ConversationCommands.swift", try source("ConversationCommands.swift")),
            ("MenuBar.swift", openItem),
        ]
    }

    private static func items() throws -> [Item] {
        try commandSources().flatMap { file, text in
            SwiftSource.buttons(in: text).map { button in
                let modifiers = SwiftSource.modifierChain(in: text, after: button.end)
                let registryID = SwiftSource.firstStringArgument(of: ".registryShortcut(", in: modifiers)
                let literal = SwiftSource.literalShortcut(in: modifiers)
                let chord = literal ?? registryID.flatMap { id in
                    HotkeyRegistry.allDefinitions.first { $0.id == id }?.defaultChords.first
                }
                return Item(file: file, title: button.title, hasAction: button.hasAction, registryID: registryID,
                            chord: chord)
            }
        }
    }

    /// The items macOS and SwiftUI put in the menus themselves, with their keys.
    private static let systemItems: [(title: String, chord: KeyChord)] = [
        ("Close", KeyChord(key: "w", command: true)),
        ("Close All", KeyChord(key: "w", command: true, option: true)),
        ("Minimize", KeyChord(key: "m", command: true)),
        ("Minimize All", KeyChord(key: "m", command: true, option: true)),
        ("Hide Courier", KeyChord(key: "h", command: true)),
        ("Hide Others", KeyChord(key: "h", command: true, option: true)),
        ("Cut", KeyChord(key: "x", command: true)),
        ("Copy", KeyChord(key: "c", command: true)),
        ("Paste", KeyChord(key: "v", command: true)),
        ("Select All", KeyChord(key: "a", command: true)),
        ("Enter Full Screen", KeyChord(key: "f", command: true, control: true)),
    ]

    func testTheAuditReadsTheMenus() throws {
        // A parser that found nothing would pass everything below.
        let items = try Self.items()
        XCTAssertGreaterThan(items.count, 60, "found \(items.count) menu items")
        XCTAssertTrue(items.contains { $0.title == "Archive All Read Chats…" && $0.registryID == "Chat: Archive All Read" })
        XCTAssertTrue(items.contains { $0.title == "Show Calendar" || $0.title == "calendarMenuTitle" })
    }

    func testEveryMenuItemDoesSomething() throws {
        for item in try Self.items() {
            XCTAssertTrue(item.hasAction, "\(item.file): \(item.title) has no action")
        }
    }

    func testNoTwoMenuItemsShareATitle() throws {
        let titled = try Self.items().filter { !$0.title.isEmpty }
        let counts = Dictionary(grouping: titled, by: { $0.title })
        for (title, items) in counts where items.count > 1 {
            XCTFail("\(items.count) menu items are titled \(title) (\(items.map(\.file).joined(separator: ", ")))")
        }
        for item in titled {
            XCTAssertFalse(Self.systemItems.contains { $0.title == item.title },
                           "\(item.file): \(item.title) repeats an item macOS already puts in the menu")
        }
    }

    func testNoTwoMenuItemsShareAShortcut() throws {
        let items = try Self.items()
        let bound = items.compactMap { item in item.registryID.map { ($0, item) } }
        for (id, matches) in Dictionary(grouping: bound, by: { $0.0 }) where matches.count > 1 {
            XCTFail("the shortcut \(id) is shown by \(matches.map { $0.1.title }.joined(separator: " and "))")
        }
        var chords: [(owner: String, chord: KeyChord)] = items.compactMap { item in
            item.chord.map { ("\(item.title) (\(item.file))", $0) }
        }
        let conversation = try Self.source("ConversationCommands.swift")
        chords += SwiftSource.formatShortcuts(in: conversation).map { ("Format ▸ \($0.kind)", $0.chord) }
        for (chord, owners) in Dictionary(grouping: chords, by: { $0.chord }) where owners.count > 1 {
            XCTFail("\(chord.symbols) is the shortcut of \(owners.map { $0.owner }.joined(separator: " and "))")
        }
        for (owner, chord) in chords {
            if let system = Self.systemItems.first(where: { $0.chord == chord }) {
                XCTFail("\(owner) takes \(chord.symbols), which is macOS's \(system.title)")
            }
        }
    }

    func testNoGroupIsPlacedBeforeOneTheAppReplaces() throws {
        for (file, text) in try Self.commandSources() {
            let replaced = Set(SwiftSource.placements(of: "replacing", in: text))
            for placement in SwiftSource.placements(of: "before", in: text) where replaced.contains(placement) {
                XCTFail("\(file): a group placed before .\(placement), which it also replaces, never shows")
            }
        }
    }

    func testStandardItemsTheAppReplacesAreNotAlsoAdded() throws {
        let commands = try Self.commandSources().map { $0.text }.joined(separator: "\n")
        let app = try Self.source("App.swift")
        // The app's own Settings… honours the shortcut setting and the lock; the Settings scene would add a second.
        if SwiftSource.placements(of: "replacing", in: commands).contains("appSettings") {
            let scene = try XCTUnwrap(app.range(of: "Settings {"), "App.swift declares the Settings scene")
            let body = try XCTUnwrap(SwiftSource.matchingClose(in: app, open: app.index(before: scene.upperBound)))
            let modifiers = SwiftSource.modifierChain(in: app, after: app.index(after: body))
            XCTAssertTrue(modifiers.contains(".commandsRemoved()"),
                          "the Settings scene must not add its own Settings… beside the app's")
        }
        // Courier has no help book, so the standard Help ▸ Courier Help says only that help isn't available.
        XCTAssertTrue(SwiftSource.placements(of: "replacing", in: commands).contains("help"),
                      "Help ▸ Courier Help opens nothing: replace the help group")
    }
}

/// Just enough of a Swift reader for the menu audit: strings, comments and brackets.
enum SwiftSource {
    struct Button {
        let title: String
        let hasAction: Bool
        /// Just past the button: its closing parenthesis, or its trailing closure's brace.
        let end: String.Index
    }

    static func strippingComments(_ text: String) -> String {
        var out = ""
        var index = text.startIndex
        var inString = false
        while index < text.endIndex {
            let char = text[index]
            let next = text.index(after: index) < text.endIndex ? text[text.index(after: index)] : nil
            if inString {
                out.append(char)
                if char == "\\", let next {
                    out.append(next)
                    index = text.index(index, offsetBy: 2)
                    continue
                }
                if char == "\"" { inString = false }
            } else if char == "/", next == "/" {
                while index < text.endIndex, text[index] != "\n" { index = text.index(after: index) }
                continue
            } else if char == "/", next == "*" {
                guard let close = text.range(of: "*/", range: index..<text.endIndex) else { break }
                index = close.upperBound
                continue
            } else {
                if char == "\"" { inString = true }
                out.append(char)
            }
            index = text.index(after: index)
        }
        return out
    }

    /// The index of the bracket that closes the one at `open`, skipping string literals.
    static func matchingClose(in text: String, open: String.Index) -> String.Index? {
        let opening = text[open]
        let closing: Character = opening == "(" ? ")" : opening == "{" ? "}" : "]"
        var depth = 0
        var index = open
        var inString = false
        while index < text.endIndex {
            let char = text[index]
            if inString {
                if char == "\\" {
                    index = text.index(after: index)
                } else if char == "\"" {
                    inString = false
                }
            } else if char == "\"" {
                inString = true
            } else if char == opening {
                depth += 1
            } else if char == closing {
                depth -= 1
                if depth == 0 { return index }
            }
            index = text.index(after: index)
        }
        return nil
    }

    static func buttons(in text: String) -> [Button] {
        var found: [Button] = []
        var search = text.startIndex
        while let range = text.range(of: "Button(", range: search..<text.endIndex) {
            search = range.upperBound
            if range.lowerBound > text.startIndex {
                let before = text[text.index(before: range.lowerBound)]
                if before.isLetter || before.isNumber || before == "_" { continue }
            }
            let open = text.index(before: range.upperBound)
            guard let close = matchingClose(in: text, open: open) else { continue }
            let arguments = String(text[text.index(after: open)..<close])
            var end = text.index(after: close)
            var rest = end
            while rest < text.endIndex, text[rest] == " " { rest = text.index(after: rest) }
            let trailingClosure = rest < text.endIndex && text[rest] == "{"
            if trailingClosure, let closureEnd = matchingClose(in: text, open: rest) {
                end = text.index(after: closureEnd)
            }
            // A literal title (`"…"` or `String(localized: "…")`) as it reads; anything else (a computed title)
            // as its expression, up to the first comma.
            let leading = arguments.trimmingCharacters(in: .whitespacesAndNewlines)
            let isLiteral = leading.hasPrefix("\"") || leading.hasPrefix("String(localized: \"")
            let expression = leading.split(separator: ",", maxSplits: 1).first.map(String.init) ?? leading
            let isWholeLiteral = isLiteral && !expression.contains("+") && !expression.contains("?")
            let title = isWholeLiteral ? (firstStringLiteral(in: arguments) ?? "") : expression
            found.append(Button(title: title, hasAction: trailingClosure || arguments.contains("action:"), end: end))
            search = end
        }
        return found
    }

    /// The modifiers chained after `index`: the rest of that line and every following line that starts with a dot
    /// (blank lines skipped).
    static func modifierChain(in text: String, after index: String.Index) -> String {
        var lines = text[index...].split(separator: "\n", omittingEmptySubsequences: false)
        guard !lines.isEmpty else { return "" }
        var chain = String(lines.removeFirst())
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue } // a comment's line, emptied by strippingComments
            guard trimmed.hasPrefix(".") else { break }
            chain += "\n" + line
        }
        return chain
    }

    static func firstStringLiteral(in text: String) -> String? {
        guard let start = text.firstIndex(of: "\"") else { return nil }
        var index = text.index(after: start)
        var literal = ""
        while index < text.endIndex, text[index] != "\"" {
            if text[index] == "\\" { index = text.index(after: index) }
            if index < text.endIndex { literal.append(text[index]) }
            index = text.index(after: index)
        }
        return literal
    }

    static func firstStringArgument(of call: String, in text: String) -> String? {
        guard let range = text.range(of: call) else { return nil }
        let rest = text[range.upperBound...]
        guard rest.first == "\"" else { return nil } // a constant such as HotkeyID.zoomIn
        return firstStringLiteral(in: String(rest))
    }

    /// `.keyboardShortcut("k", modifiers: …)` with a literal key, as a chord.
    static func literalShortcut(in text: String) -> KeyChord? {
        guard let range = text.range(of: ".keyboardShortcut(\"") else { return nil }
        return chord(from: String(text[text.index(before: range.upperBound)...]))
    }

    private static func chord(from call: String) -> KeyChord? {
        guard let key = firstStringLiteral(in: call),
              let close = call.firstIndex(of: ")").map({ call[...$0] }) else { return nil }
        let modifiers = close.range(of: "modifiers:").map { String(close[$0.upperBound...]) } ?? ".command"
        return KeyChord(key: key, command: modifiers.contains(".command"), shift: modifiers.contains(".shift"),
                        option: modifiers.contains(".option"), control: modifiers.contains(".control"))
    }

    /// The Format submenu's keys: `case .kind: content.keyboardShortcut(…)`.
    static func formatShortcuts(in text: String) -> [(kind: String, chord: KeyChord)] {
        text.split(separator: "\n").compactMap { line in
            guard let caseRange = line.range(of: "case ."),
                  let colon = line[caseRange.upperBound...].firstIndex(of: ":"),
                  let call = line.range(of: "content.keyboardShortcut(") else { return nil }
            let kind = String(line[caseRange.upperBound..<colon])
            return chord(from: String(line[line.index(before: call.upperBound)...])).map { (kind, $0) }
        }
    }

    /// The standard groups named by `CommandGroup(<label>: .x)`.
    static func placements(of label: String, in text: String) -> [String] {
        var found: [String] = []
        var search = text.startIndex
        let marker = "CommandGroup(\(label): ."
        while let range = text.range(of: marker, range: search..<text.endIndex) {
            let name = text[range.upperBound...].prefix { $0.isLetter || $0.isNumber }
            found.append(String(name))
            search = range.upperBound
        }
        return found
    }
}
