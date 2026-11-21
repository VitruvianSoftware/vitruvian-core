// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation

/// Typed markdown becomes real formatting, as in Beeper: when the closing marker of `**bold**`, `_italic_`, `*italic*`,
/// `~~strike~~` or `` `code` `` is typed (or the text with such markers is pasted, or comes back as a saved draft), the
/// markers are taken out and the words keep the style as a formatting range (`TextEntity`). The ranges are what is
/// sent: the engine turns them into each chat network's own formatting, and a network with none gets the plain words
/// with no markers. Text inside code never converts.
public enum MarkdownConverter {
    /// What a conversion made of the text.
    public struct Result: Equatable, Sendable {
        public var text: String
        public var entities: [TextEntity]
        /// The markers that were taken out, in the old text.
        public var removed: [NSRange]

        /// Where a position in the old text is in the new one.
        public func map(_ position: Int) -> Int {
            position - removed.reduce(0) { $0 + ($1.location + $1.length <= position ? $1.length : 0) }
        }
    }

    /// Converts the spans whose closing marker ends inside `inserted` (what was just typed or pasted). Nil when none do.
    public static func convert(text: String, entities: [TextEntity], inserted: NSRange) -> Result? {
        let end = inserted.location + inserted.length
        return convert(text: text, entities: entities) { span in
            let closeEnd = span.close.location + span.close.length
            return closeEnd > inserted.location && closeEnd <= end
        }
    }

    /// Converts every span in `text`: a draft coming back, or a whole message put in the box. Nil when none.
    public static func convertAll(text: String, entities: [TextEntity] = []) -> Result? {
        convert(text: text, entities: entities) { _ in true }
    }

    private static func convert(text: String, entities: [TextEntity], where wanted: (MarkdownSpan) -> Bool) -> Result? {
        let string = text as NSString
        let code = entities.filter { $0.kind == .code || $0.kind == .pre }
        let parsed = MarkdownSpans.parse(text).filter(wanted)
        guard !parsed.isEmpty else { return nil }
        // An address and a mention are one word: `https://x.com/_a_` and `@_john_` keep their characters.
        let guarded = protectedRanges(in: text, entities: entities)
        let chosen = parsed.filter { span in
            // Text inside code is just text, and so is a span that runs into code that is already there.
            !code.contains { touches($0, span.whole) } && !guarded.contains { NSIntersectionRange($0, span.whole).length > 0 }
        }
        guard !chosen.isEmpty else { return nil }

        // What is taken out: every marker, and for a fence round a block, the line break after the opening fence and
        // before the closing one, which belong to the fence.
        var removed: [NSRange] = []
        var styled: [(kind: TextEntity.Kind, content: NSRange)] = []
        for span in chosen {
            var content = span.content
            var kind: TextEntity.Kind
            switch span.kind {
            case .bold: kind = .bold
            case .italic: kind = .italic
            case .strikethrough: kind = .strikethrough
            case .code: kind = .code
            }
            removed.append(span.open)
            removed.append(span.close)
            if span.kind == .code, span.open.length >= 3 {
                let body = string.substring(with: content)
                if body.contains("\n") {
                    kind = .pre
                    if body.hasPrefix("\n") {
                        removed.append(NSRange(location: content.location, length: 1))
                        content = NSRange(location: content.location + 1, length: content.length - 1)
                    }
                    if body.hasSuffix("\n"), content.length > 0 {
                        removed.append(NSRange(location: content.location + content.length - 1, length: 1))
                        content = NSRange(location: content.location, length: content.length - 1)
                    }
                }
            }
            if content.length > 0 { styled.append((kind, content)) }
        }
        removed.sort { $0.location < $1.location }

        var newText = string as String
        var newEntities = entities
        for marker in removed.reversed() {
            newText = (newText as NSString).replacingCharacters(in: marker, with: "")
            newEntities = EntityEditing.replacing(newEntities, range: marker, with: 0)
        }
        let result = Result(text: newText, entities: newEntities, removed: removed)
        var ranged = result
        let updated = newText as NSString
        for (kind, content) in styled {
            let start = result.map(content.location)
            let stop = result.map(content.location + content.length)
            guard stop > start else { continue }
            ranged.entities = EntityEditing.adding(kind, in: NSRange(location: start, length: stop - start), of: updated,
                                                   entities: ranged.entities)
        }
        ranged.entities = EntityEditing.fitted(ranged.entities, to: updated)
        return ranged
    }

    private static let linkDetector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
    private static let addressWord = try? NSRegularExpression(pattern: #"(?i)(?:https?://|www\.)\S+"#)
    private static let mentionWord = try? NSRegularExpression(pattern: #"(?<![\p{L}\p{N}_])@\S+"#)

    /// Addresses (as macOS finds them, and any `http(s)://` or `www.` word), `@mention` words, and links and mentions
    /// already made: no markdown inside them converts.
    private static func protectedRanges(in text: String, entities: [TextEntity]) -> [NSRange] {
        let whole = NSRange(location: 0, length: (text as NSString).length)
        var ranges = entities.filter { $0.kind == .link || $0.kind == .mention }.map(\.range)
        ranges += linkDetector?.matches(in: text, options: [], range: whole).map(\.range) ?? []
        ranges += addressWord?.matches(in: text, options: [], range: whole).map(\.range) ?? []
        ranges += mentionWord?.matches(in: text, options: [], range: whole).map(\.range) ?? []
        return ranges
    }

    private static func touches(_ entity: TextEntity, _ range: NSRange) -> Bool {
        entity.offset < range.location + range.length && entity.offset + entity.length > range.location
    }

    // MARK: Back to markdown

    /// The text with its bold, italic, strike and code ranges written as markers again: what the engine keeps of a
    /// draft (it keeps text only), so the styles come back from `convertAll` when the draft is opened. Other kinds
    /// (links, mentions, quotes, lists, spoilers) have no marker here and are plain in a saved draft, as before.
    public static func markdown(text: String, entities: [TextEntity]) -> String {
        let string = text as NSString
        let kinds: [TextEntity.Kind: String] = [.bold: "**", .italic: "_", .strikethrough: "~~"]
        var inserts: [(position: Int, group: Int, size: Int, index: Int, marker: String)] = []
        // Characters that are left as typed but would read back as markers (after Undo kept `**x**` as it was typed)
        // get a backslash, and so does every backslash, so `unescaped` can undo exactly what is done here.
        var escaped: Set<Int> = []
        for span in MarkdownSpans.parse(text) {
            for marker in [span.open, span.close] {
                for position in marker.location ..< marker.location + marker.length { escaped.insert(position) }
            }
        }
        // A backslash the person typed is doubled; and the mark it was protecting is escaped again, or doubling the
        // backslash would let the mark mean something.
        for position in 0 ..< string.length where string.character(at: position) == 0x5C {
            escaped.insert(position)
            if position + 1 < string.length, isASCIIPunctuation(string.character(at: position + 1)) {
                escaped.insert(position + 1)
            }
        }
        for position in escaped { inserts.append((position, 2, 0, position, "\\")) }
        for (index, entity) in entities.enumerated() {
            guard entity.offset >= 0, entity.length > 0, entity.offset + entity.length <= string.length else { continue }
            var start = entity.offset
            var stop = entity.offset + entity.length
            // A marker needs words hugging it on the inside.
            while start < stop, isBlank(string.character(at: start)) { start += 1 }
            while stop > start, isBlank(string.character(at: stop - 1)) { stop -= 1 }
            guard stop > start else { continue }
            let open: String
            let close: String
            if let marker = kinds[entity.kind] {
                open = marker
                close = marker
            } else if entity.kind == .code {
                let body = string.substring(with: NSRange(location: start, length: stop - start))
                var longest = 0
                var run = 0
                for scalar in body.unicodeScalars {
                    run = scalar == "`" ? run + 1 : 0
                    longest = max(longest, run)
                }
                let fence = String(repeating: "`", count: longest + 1)
                open = fence
                close = fence
            } else {
                continue
            }
            // At one place, ranges that end close first (the inner one first), then ranges that start open (the outer first).
            inserts.append((start, 1, -(stop - start), index, open))
            inserts.append((stop, 0, stop - start, index, close))
        }
        guard !inserts.isEmpty else { return text }
        inserts.sort { a, b in
            (a.position, a.group, a.size, a.index) < (b.position, b.group, b.size, b.index)
        }
        var out = ""
        var cursor = 0
        for insert in inserts {
            out += string.substring(with: NSRange(location: cursor, length: insert.position - cursor))
            out += insert.marker
            cursor = insert.position
        }
        out += string.substring(from: cursor)
        return out
    }

    /// A draft the engine kept, as the box opens it: markers turned back into styles, escapes taken out.
    public static func restoredDraft(_ kept: String) -> (text: String, entities: [TextEntity]) {
        let converted = convertAll(text: kept)
        return unescaped(text: converted?.text ?? kept, entities: converted?.entities ?? [])
    }

    /// A kept draft as the person sees it in the box, for the inbox's "Draft:" line: no markers for styles (they are
    /// styles in the box) and no backslash escapes.
    public static func visibleDraft(_ kept: String) -> String {
        restoredDraft(kept).text
    }

    /// Takes out the backslashes `markdown` put in: one before an ASCII punctuation mark goes. The ranges follow.
    public static func unescaped(text: String, entities: [TextEntity]) -> (text: String, entities: [TextEntity]) {
        let units = Array(text.utf16)
        var removed: [Int] = []
        var index = 0
        while index < units.count {
            if units[index] == 0x5C, index + 1 < units.count, isASCIIPunctuation(units[index + 1]) {
                removed.append(index)
                index += 2
            } else {
                index += 1
            }
        }
        guard !removed.isEmpty else { return (text, entities) }
        var out = text as NSString
        var ranges = entities
        for position in removed.reversed() {
            let marker = NSRange(location: position, length: 1)
            out = out.replacingCharacters(in: marker, with: "") as NSString
            ranges = EntityEditing.replacing(ranges, range: marker, with: 0)
        }
        return (out as String, ranges)
    }

    private static func isASCIIPunctuation(_ unit: unichar) -> Bool {
        (0x21...0x2F).contains(unit) || (0x3A...0x40).contains(unit) || (0x5B...0x60).contains(unit) || (0x7B...0x7E).contains(unit)
    }

    private static func isBlank(_ unit: unichar) -> Bool {
        unit == 0x20 || unit == 0x09 || unit == 0x0A || unit == 0x0D || unit == 0xA0
    }
}
