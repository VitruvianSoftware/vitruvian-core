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
        let chosen = MarkdownSpans.parse(text).filter { span in
            guard wanted(span) else { return false }
            // Text inside code is just text, and so is a span that runs into code that is already there.
            return !code.contains { touches($0, span.whole) }
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

    private static func isBlank(_ unit: unichar) -> Bool {
        unit == 0x20 || unit == 0x09 || unit == 0x0A || unit == 0x0D || unit == 0xA0
    }
}
