// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation

/// A message's text and its formatting ranges, as the composer makes them and the engine takes them: plain text, with
/// ranges in UTF-16 code units. Typed characters are never formatting: there is no Markdown.
public struct RichText: Equatable, Sendable {
    public var text: String
    /// In `TextEntity.precedes` order.
    public var entities: [TextEntity]

    public init(text: String, entities: [TextEntity] = []) {
        self.text = text
        self.entities = entities
    }
}

/// Reads a message's Matrix HTML (`formatted_body`, org.matrix.custom.html) back into text and ranges.
///
/// It is a small hand-written reader, not `NSAttributedString(html:)`, which loads WebKit and must run on the main
/// thread. What it reads:
///   - the tags the engine writes (engine/internal/richtext Render): strong, em, del, code, pre, blockquote, ul, ol
///     (with `start`), li, a (an http, https or mailto link, or a matrix.to link to a user: a mention), span
///     data-mx-spoiler and br; and b, i, s and strike, which other apps write for the same styles;
///   - h1 to h6 as bold lines, and p as paragraphs a blank line apart;
///   - mx-reply (another app's quote of the message replied to) is dropped, and so are script and style;
///   - any other tag keeps its text; character references (&amp;, &#39;, &#x1F600;) are decoded.
///
/// The layout follows Render: a block (code block, quote, list) takes whole lines, the line breaks either side of it
/// are its own, and a `<br>` straight after a block stands for the break after it. Two lists of one kind with only
/// empty lines between them (Render's list across an empty line, the second `<ol>` numbered on) read as one.
///
/// The ranges that come back are ones the engine takes (richtext.Check): a link or mention on one line, links,
/// mentions and code never overlapping, blocks on whole lines and never two on a line, no style inside code, at most
/// 1,000 ranges. So a message read here can be edited and sent again as it is.
public enum RichTextHTML {
    /// The most ranges one message may carry (richtext.MaxEntities).
    public static let maxEntities = 1000

    /// Matrix HTML back to text and ranges. Never fails: HTML that holds no text (or none at all) gives
    /// `RichText(text: fallback, entities: [])`, and broken HTML reads as what it says.
    public static func parse(html: String, fallback: String) -> RichText {
        let plain = RichText(text: fallback, entities: [])
        guard !html.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return plain }
        var reader = Reader(html)
        reader.read()
        guard !reader.out.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return plain }
        return RichText(text: reader.out, entities: Self.sendable(reader.entities, in: reader.out))
    }

    // MARK: - Ranges the engine takes

    private static let styles: Set<TextEntity.Kind> = [.bold, .italic, .strikethrough, .spoiler]
    private static let atoms: Set<TextEntity.Kind> = [.link, .mention, .code]

    /// The ranges, cleaned up as richtext.Check and Render would have them: styles of one kind that touch are one,
    /// and what Check refuses, or Render drops, is left out.
    static func sendable(_ raw: [TextEntity], in text: String) -> [TextEntity] {
        let units = Array(text.utf16)
        var entities = raw.filter { $0.offset >= 0 && $0.length > 0 && $0.offset + $0.length <= units.count }

        // Styles of one kind that overlap or touch become one range.
        var merged: [TextEntity] = entities.filter { !styles.contains($0.kind) }
        for kind in TextEntity.Kind.allCases where styles.contains(kind) {
            var current: TextEntity?
            for entity in entities.filter({ $0.kind == kind }).sorted(by: { $0.offset < $1.offset }) {
                if var open = current, entity.offset <= open.offset + open.length {
                    open.length = max(open.offset + open.length, entity.offset + entity.length) - open.offset
                    current = open
                } else {
                    if let open = current { merged.append(open) }
                    current = entity
                }
            }
            if let open = current { merged.append(open) }
        }
        // The checks below compare ranges pairwise; past a few thousand tags, the rest can't be kept anyway.
        entities = Array(merged.sorted(by: TextEntity.precedes).prefix(4 * maxEntities))

        // Line numbers, to place blocks and keep links and mentions on one line.
        var lineAt = [Int](repeating: 0, count: units.count + 1)
        var line = 0
        for (index, unit) in units.enumerated() {
            lineAt[index] = line
            if unit == 0x0A { line += 1 }
        }
        lineAt[units.count] = line
        func lines(_ entity: TextEntity) -> ClosedRange<Int> {
            lineAt[entity.offset] ... lineAt[entity.offset + entity.length - 1]
        }
        func within(_ entity: TextEntity, _ outer: TextEntity) -> Bool {
            outer.offset <= entity.offset && entity.offset + entity.length <= outer.offset + outer.length
        }
        func overlaps(_ a: TextEntity, _ b: TextEntity) -> Bool {
            a.offset < b.offset + b.length && b.offset < a.offset + a.length
        }

        // Blocks: whole lines, never two on one line (the outer one of two nested stays).
        var blocks: [TextEntity] = []
        for entity in entities where entity.kind.isBlock {
            let end = entity.offset + entity.length
            let startsLine = entity.offset == 0 || units[entity.offset - 1] == 0x0A
            let endsLine = end == units.count || units[end] == 0x0A || units[end - 1] == 0x0A
            guard startsLine, endsLine, !blocks.contains(where: { lines($0).overlaps(lines(entity)) }) else { continue }
            blocks.append(entity)
        }
        let codeBlocks = blocks.filter { $0.kind == .pre }

        // Links, mentions and code: never inside a code block, never overlapping one another; links and mentions on
        // one line, with an address or user the engine takes.
        var kept: [TextEntity] = []
        for entity in entities where atoms.contains(entity.kind) {
            guard !codeBlocks.contains(where: { lines($0).overlaps(lines(entity)) }),
                  !kept.contains(where: { overlaps($0, entity) }) else { continue }
            switch entity.kind {
            case .link:
                guard lines(entity).count == 1, let url = entity.url, isSafeURL(url) else { continue }
            case .mention:
                guard lines(entity).count == 1, let user = entity.userID, isMatrixUser(user) else { continue }
            default:
                break
            }
            kept.append(entity)
        }
        let code = kept.filter { $0.kind == .code } + codeBlocks

        // Styles, except inside code: nothing styles code.
        let styled = entities.filter { style in styles.contains(style.kind) && !code.contains { within(style, $0) } }
        return Array((blocks + kept + styled).sorted(by: TextEntity.precedes).prefix(maxEntities))
    }

    /// An http or https address with a host, or a mailto address, with no space or control character
    /// (richtext.safeURL).
    static func isSafeURL(_ address: String) -> Bool {
        guard !address.unicodeScalars.contains(where: {
            CharacterSet.whitespacesAndNewlines.contains($0) || CharacterSet.controlCharacters.contains($0)
        }) else { return false }
        let lower = address.lowercased()
        for scheme in ["http://", "https://"] where lower.hasPrefix(scheme) {
            let rest = address.dropFirst(scheme.count)
            let host = rest.prefix { $0 != "/" && $0 != "?" && $0 != "#" }
            let name = host.split(separator: "@").last.map(String.init) ?? ""
            return !name.isEmpty && name != ":"
        }
        return lower.hasPrefix("mailto:") && address.count > "mailto:".count
    }

    /// "@room", or a Matrix user ID: "@", a localpart, ":", a server name, at most 255 bytes, no space or control
    /// character (richtext.matrixUser).
    static func isMatrixUser(_ user: String) -> Bool {
        if user == "@room" { return true }
        guard user.hasPrefix("@"), user.utf8.count <= 255,
              !user.unicodeScalars.contains(where: {
                  CharacterSet.whitespacesAndNewlines.contains($0) || CharacterSet.controlCharacters.contains($0)
              }),
              let colon = user.firstIndex(of: ":") else { return false }
        let local = user[user.index(after: user.startIndex) ..< colon]
        let server = user[user.index(after: colon)...]
        return !local.isEmpty && !server.isEmpty
    }
}

// MARK: - The reader

/// One pass over the HTML: tags and text, never failing. `out` is the text so far, and `entities` the ranges of
/// elements already closed.
private struct Reader {
    private let input: [Unicode.Scalar]
    /// Where the last ">", "\"" and "'" are: a tag or a quoted value that starts after the last one can't close,
    /// which is known at once rather than by reading to the end (so many "<" never cost the square of the length).
    private let lastClose: [Unicode.Scalar: Int]
    private var index = 0
    /// A tag read up to here never closed: every "<" before this is text. Without it, many such tags, each read to
    /// the cap again from the next "<", would cost the square of the length.
    private var textUntil = 0
    private(set) var out = ""
    private(set) var entities: [TextEntity] = []
    /// out's length in UTF-16 code units.
    private var length = 0
    /// Line breaks owed after a block or a paragraph, written before what comes next (and never at the end).
    private var owed = 0
    private var open: [Element] = []
    /// Inside an element whose content is dropped (mx-reply, script, style): its name and how deep.
    private var skipping: (name: String, depth: Int)?
    /// The last list closed, for one that carries it on after empty lines.
    private var lastList: (entity: Int, kind: TextEntity.Kind, end: Int, next: Int)?

    private struct Element {
        let name: String
        var kind: TextEntity.Kind?
        var url: String?
        var userID: String?
        /// Where its first text went; nil until it has some.
        var start: Int?
        var isBlock = false
        var isParagraph = false
        /// A list: its items so far, and the number its first item has.
        var items = 0
        var first = 1
        /// A list that carries on the entity at this index.
        var carriesOn: Int?
    }

    /// The longest tag read as one, in Unicode scalars (a long link's address fits).
    static let maxTagScalars = 4096
    /// The most elements open at once; tags deeper than this keep only their text.
    static let maxDepth = 100

    private static let voids: Set<String> = [
        "br", "img", "hr", "meta", "link", "input", "wbr", "area", "base", "col", "embed", "source", "track", "param",
    ]
    private static let dropped: Set<String> = ["mx-reply", "script", "style", "head", "title", "template"]
    private static let headings: Set<String> = ["h1", "h2", "h3", "h4", "h5", "h6"]

    init(_ html: String) {
        input = Array(html.unicodeScalars)
        var last: [Unicode.Scalar: Int] = [:]
        for (position, scalar) in input.enumerated() where scalar == ">" || scalar == "\"" || scalar == "'" {
            last[scalar] = position
        }
        lastClose = last
    }

    /// How many open elements are a `pre`.
    private var preDepth = 0
    private var inPre: Bool { preDepth > 0 }
    /// The open elements that already have text: always the first ones, since text starts every element open.
    private var started = 0

    mutating func read() {
        var text = ""
        while index < input.count {
            let scalar = input[index]
            if scalar == "<", let tag = readMarkup() {
                if !text.isEmpty {
                    handleText(text, next: tag)
                    text = ""
                }
                handle(tag)
            } else {
                text.unicodeScalars.append(scalar)
                index += 1
            }
        }
        if !text.isEmpty { handleText(text, next: nil) }
        while !open.isEmpty { close(at: open.count - 1) }
    }

    // MARK: Tokens

    private enum Markup {
        case start(name: String, attributes: [String: String], selfClosing: Bool)
        case end(name: String)
        case ignored
    }

    /// The tag, comment or declaration at `index` (a "<"), moving past it; nil, and nothing moved, when the "<" is
    /// just text.
    private mutating func readMarkup() -> Markup? {
        let begin = index
        var at = index + 1
        guard at < input.count, begin >= textUntil, begin < lastClose[">", default: -1] else { return nil }
        // A tag longer than this is text: so a "<" whose tag never closes costs at most this much reading, however
        // many there are.
        let limit = min(input.count, begin + Self.maxTagScalars)
        if input[at] == "!" || input[at] == "?" {
            if input[at] == "!", at + 2 < input.count, input[at + 1] == "-", input[at + 2] == "-" {
                // A comment, to its "-->" or to the end.
                var scan = at + 3
                while scan < input.count {
                    if input[scan] == ">", scan >= at + 5, input[scan - 1] == "-", input[scan - 2] == "-" { break }
                    scan += 1
                }
                index = min(scan + 1, input.count)
                return .ignored
            }
            guard let close = input[at ..< limit].firstIndex(of: ">") else { return nil }
            index = close + 1
            return .ignored
        }
        var isEnd = false
        if input[at] == "/" {
            isEnd = true
            at += 1
        }
        guard at < limit, Self.isLetter(input[at]) else { return nil }
        var name = ""
        while at < limit, !Self.isSpace(input[at]), input[at] != "/", input[at] != ">" {
            name.unicodeScalars.append(input[at])
            at += 1
        }
        var attributes: [String: String] = [:]
        var selfClosing = false
        while true {
            while at < limit, Self.isSpace(input[at]) { at += 1 }
            guard at < limit else {
                index = begin
                textUntil = at
                return nil // never closed: the "<" is text
            }
            if input[at] == ">" {
                at += 1
                break
            }
            if input[at] == "/" {
                selfClosing = true
                at += 1
                continue
            }
            var key = ""
            while at < limit, !Self.isSpace(input[at]), input[at] != "=", input[at] != ">", input[at] != "/" {
                key.unicodeScalars.append(input[at])
                at += 1
            }
            while at < limit, Self.isSpace(input[at]) { at += 1 }
            var value = ""
            if at < limit, input[at] == "=" {
                at += 1
                while at < limit, Self.isSpace(input[at]) { at += 1 }
                if at < limit, input[at] == "\"" || input[at] == "'" {
                    let quote = input[at]
                    guard at < lastClose[quote, default: -1] else {
                        index = begin
                        textUntil = at
                        return nil
                    }
                    at += 1
                    while at < limit, input[at] != quote {
                        value.unicodeScalars.append(input[at])
                        at += 1
                    }
                    guard at < limit else {
                        index = begin
                        textUntil = at
                        return nil
                    }
                    at += 1
                } else {
                    while at < limit, !Self.isSpace(input[at]), input[at] != ">" {
                        value.unicodeScalars.append(input[at])
                        at += 1
                    }
                }
            }
            if !key.isEmpty { attributes[key.lowercased()] = Self.decode(value) }
        }
        index = at
        let lower = name.lowercased()
        return isEnd ? .end(name: lower) : .start(name: lower, attributes: attributes, selfClosing: selfClosing)
    }

    private static func isLetter(_ scalar: Unicode.Scalar) -> Bool {
        ("a" ... "z").contains(scalar) || ("A" ... "Z").contains(scalar)
    }

    private static func isSpace(_ scalar: Unicode.Scalar) -> Bool {
        scalar == " " || scalar == "\t" || scalar == "\n" || scalar == "\r" || scalar == "\u{0C}"
    }

    // MARK: Text

    private mutating func handleText(_ raw: String, next: Markup?) {
        guard skipping == nil else { return }
        let text = Self.decode(raw)
        if inPre {
            append(text)
            return
        }
        // Whitespace with a line break between tags is the HTML's own layout, not the message's: nothing where a
        // line breaks anyway, a space between words.
        if text.contains("\n"), text.unicodeScalars.allSatisfy(Self.isSpace) {
            if length == 0 || owed > 0 || out.hasSuffix("\n") || Self.breaksLine(next) || topIsList { return }
            append(" ")
            return
        }
        if topIsList, text.unicodeScalars.allSatisfy(Self.isSpace) { return }
        append(text)
    }

    /// Whether the innermost open element is a list (text there, outside an item, is layout).
    private var topIsList: Bool {
        guard let top = open.last else { return false }
        return top.name == "ul" || top.name == "ol"
    }

    private static func breaksLine(_ markup: Markup?) -> Bool {
        switch markup {
        case let .start(name, _, _), let .end(name):
            ["br", "p", "pre", "blockquote", "ul", "ol", "li", "div", "table", "tr"].contains(name)
                || headings.contains(name)
        default:
            false
        }
    }

    private mutating func append(_ text: String) {
        guard !text.isEmpty else { return }
        payOwed()
        for position in started ..< open.count {
            open[position].start = length
        }
        started = open.count
        appendRaw(text)
    }

    private mutating func appendRaw(_ text: String) {
        out += text
        length += text.utf16.count
    }

    /// Writes the line breaks owed, so what comes next starts where it should.
    private mutating func payOwed() {
        if owed > 0 { ensureLineBreaks(owed) }
        owed = 0
    }

    /// At least `count` line breaks end the text (none at its very start).
    private mutating func ensureLineBreaks(_ count: Int) {
        guard length > 0 else { return }
        var have = 0
        for unit in out.utf16.reversed() {
            guard unit == 0x0A, have < count else { break }
            have += 1
        }
        if have < count { appendRaw(String(repeating: "\n", count: count - have)) }
    }

    // MARK: Tags

    private mutating func handle(_ markup: Markup) {
        if let skip = skipping {
            switch markup {
            case let .start(name, _, selfClosing) where name == skip.name && !selfClosing:
                skipping = (name, skip.depth + 1)
            case let .end(name) where name == skip.name:
                skipping = skip.depth > 1 ? (name, skip.depth - 1) : nil
            default:
                break
            }
            return
        }
        switch markup {
        case .ignored:
            break
        case let .start(name, attributes, selfClosing):
            start(name, attributes: attributes, selfClosing: selfClosing)
        case let .end(name):
            if let position = open.lastIndex(where: { $0.name == name }) { close(at: position) }
        }
    }

    private mutating func start(_ name: String, attributes: [String: String], selfClosing: Bool) {
        if Self.dropped.contains(name) {
            if !selfClosing { skipping = (name, 1) }
            return
        }
        if name == "br" {
            if inPre {
                append("\n")
            } else if owed > 0 {
                payOwed() // a <br> straight after a block is the break after it
            } else {
                appendRaw("\n")
            }
            return
        }
        guard !Self.voids.contains(name), !selfClosing, open.count < Self.maxDepth else { return }

        var element = Element(name: name)
        switch name {
        case "strong", "b": element.kind = .bold
        case "em", "i": element.kind = .italic
        case "del", "s", "strike": element.kind = .strikethrough
        case "code": element.kind = inPre ? nil : .code
        case "span": element.kind = attributes["data-mx-spoiler"] != nil ? .spoiler : nil
        case "a": link(attributes["href"] ?? "", into: &element)
        case "pre": element.kind = .pre; element.isBlock = true
        case "blockquote": element.kind = .blockquote; element.isBlock = true
        case "ul": element.kind = .bulletList; element.isBlock = true
        case "ol":
            element.kind = .orderedList
            element.isBlock = true
            // The network's number, kept to a sane range: the next list's number is worked out from it.
            let start = Int(attributes["start"]?.trimmingCharacters(in: .whitespaces) ?? "") ?? 1
            element.first = min(max(start, 0), 1_000_000)
        case "p":
            // A paragraph in a list item is the item's line, not a paragraph of its own.
            element.isBlock = true
            element.isParagraph = !open.contains { $0.name == "li" }
        case _ where Self.headings.contains(name): element.kind = .bold; element.isBlock = true
        case "li":
            if let list = open.lastIndex(where: { $0.name == "ul" || $0.name == "ol" }) {
                if open[list].items > 0 {
                    owed = 0
                    ensureLineBreaks(1)
                }
                open[list].items += 1
            }
        default:
            break
        }

        if element.isBlock {
            payOwed()
            ensureLineBreaks(element.isParagraph ? 2 : 1)
            if let kind = element.kind, kind == .bulletList || kind == .orderedList, let last = lastList,
               last.kind == kind, kind == .bulletList || element.first == last.next, last.end < length,
               out.utf16.suffix(length - last.end).allSatisfy({ $0 == 0x0A }) {
                element.carriesOn = last.entity
                element.first = last.next
            }
        }
        if name == "pre" { preDepth += 1 }
        open.append(element)
    }

    /// An `<a>`: a mention when it links to a user on matrix.to, else a link to its address.
    private func link(_ href: String, into element: inout Element) {
        let prefix = "https://matrix.to/#/"
        if href.lowercased().hasPrefix(prefix) {
            let target = String(href.dropFirst(prefix.count).prefix { $0 != "?" })
            let user = target.removingPercentEncoding ?? target
            if user.hasPrefix("@") {
                element.kind = .mention
                element.userID = user
                return
            }
        }
        element.kind = .link
        element.url = href
    }

    /// Closes the element at `position`, and any still open inside it.
    private mutating func close(at position: Int) {
        while open.count > position {
            let element = open.removeLast()
            started = min(started, open.count)
            if element.name == "pre" { preDepth -= 1 }
            if let kind = element.kind, let start = element.start, length > start {
                let isList = kind == .bulletList || kind == .orderedList
                if isList, let carried = element.carriesOn, carried < entities.count {
                    entities[carried].length = length - entities[carried].offset
                    lastList = (carried, kind, length, element.first &+ element.items)
                } else {
                    entities.append(TextEntity(kind: kind, offset: start, length: length - start, url: element.url,
                                               userID: element.userID))
                    if isList { lastList = (entities.count - 1, kind, length, element.first &+ element.items) }
                }
            }
            if element.isBlock { owed = max(owed, element.isParagraph ? 2 : 1) }
        }
    }

    // MARK: Character references

    private static let named: [String: String] = [
        "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": "\u{00A0}",
    ]

    /// Decodes &name; and &#n; / &#xn;. One it can't read stays as it is; a number that isn't a character is U+FFFD.
    static func decode(_ text: String) -> String {
        guard text.contains("&") else { return text }
        let scalars = Array(text.unicodeScalars)
        var result = String.UnicodeScalarView()
        var at = 0
        while at < scalars.count {
            guard scalars[at] == "&", let semicolon = scalars[(at + 1)...].prefix(12).firstIndex(of: ";") else {
                result.append(scalars[at])
                at += 1
                continue
            }
            let body = String(String.UnicodeScalarView(scalars[(at + 1) ..< semicolon]))
            var decoded: String?
            if body.hasPrefix("#x") || body.hasPrefix("#X") {
                decoded = character(UInt32(body.dropFirst(2), radix: 16), digits: body.count - 2)
            } else if body.hasPrefix("#") {
                decoded = character(UInt32(body.dropFirst(1), radix: 10), digits: body.count - 1)
            } else {
                decoded = named[body]
            }
            if let decoded {
                result.append(contentsOf: decoded.unicodeScalars)
                at = semicolon + 1
            } else {
                result.append(scalars[at])
                at += 1
            }
        }
        return String(result)
    }

    private static func character(_ number: UInt32?, digits: Int) -> String? {
        guard digits > 0 else { return nil }
        guard let number, number != 0, let scalar = Unicode.Scalar(number) else { return "\u{FFFD}" }
        return String(scalar)
    }
}
