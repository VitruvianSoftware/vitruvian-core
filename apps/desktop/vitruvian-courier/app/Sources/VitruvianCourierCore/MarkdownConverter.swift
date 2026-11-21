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
        // An address and a mention are one word: the markers of `https://x.com/_a_` and `@_john_` are inside it, so
        // they stay. A span that only ends in an address (`**see https://x.com**`) has its markers outside, and converts.
        let guarded = protectedRanges(in: text, entities: entities)
        let chosen = parsed.filter { span in
            // Text inside code is just text, and so is a span that runs into code that is already there.
            !code.contains { touches($0, span.whole) }
                && !guarded.contains { word in
                    NSIntersectionRange(word, span.open).length > 0 || NSIntersectionRange(word, span.close).length > 0
                }
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

        // In one pass, not a copy of the whole text (and every range) per marker: a draft of a few thousand characters
        // is read back like this on every keystroke.
        let (newText, newEntities) = removingAll(removed, from: string, entities: entities)
        let result = Result(text: newText, entities: newEntities, removed: removed)
        var ranged = result
        let updated = newText as NSString
        // `result.map`, by binary search: `removed` is in order and doesn't overlap, so the ends are in order too.
        var removedBefore: [Int] = [0] // units in removed[0 ..< i]
        removedBefore.reserveCapacity(removed.count + 1)
        for marker in removed { removedBefore.append(removedBefore[removedBefore.count - 1] + marker.length) }
        func map(_ position: Int) -> Int {
            var low = 0
            var high = removed.count
            while low < high {
                let mid = (low + high) / 2
                if removed[mid].location + removed[mid].length <= position { low = mid + 1 } else { high = mid }
            }
            return position - removedBefore[low]
        }
        var added: [TextEntity] = []
        for (kind, content) in styled {
            let start = map(content.location)
            let stop = map(content.location + content.length)
            guard stop > start else { continue }
            if kind.isBlock {
                ranged.entities = EntityEditing.adding(kind, in: NSRange(location: start, length: stop - start), of: updated,
                                                       entities: ranged.entities)
            } else {
                added.append(TextEntity(kind: kind, offset: start, length: stop - start))
            }
        }
        ranged.entities = merging(added, into: ranged.entities)
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
        var words = linkDetector?.matches(in: text, options: [], range: whole).map(\.range) ?? []
        words += addressWord?.matches(in: text, options: [], range: whole).map(\.range) ?? []
        words += mentionWord?.matches(in: text, options: [], range: whole).map(\.range) ?? []
        // What ends the word is not part of it: the closing marker of a span that ends in an address, and the
        // punctuation after it ("see https://x.com.").
        let string = text as NSString
        let trailing: Set<unichar> = Set("*_~`.,;:!?)]}'\"".utf16)
        for word in words {
            var end = word.location + word.length
            while end > word.location + 1, trailing.contains(string.character(at: end - 1)) { end -= 1 }
            ranges.append(NSRange(location: word.location, length: end - word.location))
        }
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
        let written = render(text: text, entities: entities)
        let styled = entities.filter { [.bold, .italic, .strikethrough, .code, .pre].contains($0.kind) }.sorted(by: TextEntity.precedes)
        guard !styled.isEmpty else { return written }
        // Saving must never change what comes back. Where the markers would not read back as these very ranges (a
        // marker the address guard keeps out of an address, say), the words are kept and the styles dropped, which
        // does read back the same every time.
        let back = restoredDraft(written)
        // (A style's edge spaces stay outside its markers, so what reads back is the range without them.)
        let string = text as NSString
        let expected: [TextEntity] = styled.compactMap { entity in
            guard entity.offset >= 0, entity.length > 0, entity.offset + entity.length <= string.length else { return nil }
            guard entity.kind != .pre else { return entity }
            var start = entity.offset
            var stop = entity.offset + entity.length
            while start < stop, isBlank(string.character(at: start)) { start += 1 }
            while stop > start, isBlank(string.character(at: stop - 1)) { stop -= 1 }
            guard stop > start else { return nil }
            return TextEntity(kind: entity.kind, offset: start, length: stop - start)
        }
        return back.text == text && back.entities == expected ? written : render(text: text, entities: [])
    }

    private static func render(text: String, entities: [TextEntity]) -> String {
        let string = text as NSString
        let kinds: [TextEntity.Kind: String] = [.bold: "**", .italic: "_", .strikethrough: "~~"]
        var inserts: [(position: Int, group: Int, size: Int, index: Int, marker: String)] = []
        // Characters that are left as typed but would read back as markers (after Undo kept `**x**` as it was typed)
        // get a backslash. Escaping only some of a draft's marker characters can change which of the rest pair up, so
        // where any could read back as a marker, all of them (outside code) are escaped: then none can.
        var escaped: Set<Int> = []
        let hasStyles = entities.contains { [.bold, .italic, .strikethrough, .code, .pre].contains($0.kind) }
        // Which units are inside code, marked once: not every code range checked again for every character.
        var inCode = [Bool](repeating: false, count: string.length)
        for entity in entities where entity.kind == .code || entity.kind == .pre {
            let from = max(0, entity.offset)
            let to = min(string.length, entity.offset + entity.length)
            if from < to { for position in from ..< to { inCode[position] = true } }
        }
        if hasStyles || !MarkdownSpans.parse(text).isEmpty {
            for position in 0 ..< string.length where isMarkerCharacter(string.character(at: position)) {
                if !inCode[position] { escaped.insert(position) }
            }
        }
        // Inside code, the markers of what would be a span are escaped, as before (the code itself is not read).
        for span in MarkdownSpans.parse(text) {
            for marker in [span.open, span.close] {
                for position in marker.location ..< marker.location + marker.length { escaped.insert(position) }
            }
        }
        // A backslash the person typed is doubled; and the mark it was protecting is escaped again, or doubling the
        // backslash would let the mark mean something.
        for position in 0 ..< string.length where string.character(at: position) == 0x5C {
            escaped.insert(position)
            if position + 1 < string.length, isMarkerCharacter(string.character(at: position + 1)) {
                escaped.insert(position + 1)
            }
        }
        for position in escaped { inserts.append((position, 2, 0, position, "\\")) }
        for (index, entity) in entities.enumerated() {
            if entity.kind == .pre {
                guard entity.offset >= 0, entity.length > 0, entity.offset + entity.length <= string.length,
                      entity.offset == 0 || string.character(at: entity.offset - 1) == 0x0A,
                      entity.offset + entity.length == string.length || string.character(at: entity.offset + entity.length) == 0x0A
                else { continue }
                let body = string.substring(with: entity.range)
                let fence = String(repeating: "`", count: max(3, longestRun(of: "`", in: body) + 1))
                inserts.append((entity.offset, 1, -entity.length, index, fence + "\n"))
                inserts.append((entity.offset + entity.length, 0, entity.length, index, "\n" + fence))
                continue
            }
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
                let fence = String(repeating: "`", count: longestRun(of: "`", in: body) + 1)
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

    /// Takes out the backslashes `markdown` put in: the first of a doubled backslash, and one before `*`, `_`, `~` or a
    /// backtick. Every other backslash is left alone (an older draft's `C:\Users\(x)` keeps its own). The ranges follow.
    public static func unescaped(text: String, entities: [TextEntity]) -> (text: String, entities: [TextEntity]) {
        let units = Array(text.utf16)
        var removed: [Int] = []
        var index = 0
        while index < units.count {
            if units[index] == 0x5C, index + 1 < units.count, isMarkerCharacter(units[index + 1]) || units[index + 1] == 0x5C {
                removed.append(index)
                index += 2
            } else {
                index += 1
            }
        }
        guard !removed.isEmpty else { return (text, entities) }
        return removingAll(removed.map { NSRange(location: $0, length: 1) }, from: text as NSString, entities: entities)
    }

    /// `string` without `removed` (in order, not overlapping), and the ranges as `EntityEditing.replacing` leaves them
    /// after each removal in turn: a position moves back by what is removed before it, a range wholly removed goes,
    /// and a mention any removal touches goes. One pass over the text, a binary search per range.
    static func removingAll(_ removed: [NSRange], from string: NSString, entities: [TextEntity])
        -> (text: String, entities: [TextEntity]) {
        guard !removed.isEmpty else { return (string as String, entities) }
        var out = ""
        out.reserveCapacity(string.length)
        var cursor = 0
        var before: [Int] = [] // units removed before removed[i]
        before.reserveCapacity(removed.count)
        var total = 0
        for marker in removed {
            out += string.substring(with: NSRange(location: cursor, length: marker.location - cursor))
            cursor = marker.location + marker.length
            before.append(total)
            total += marker.length
        }
        out += string.substring(from: cursor)
        // The last removal that starts before `position`.
        func last(before position: Int) -> Int? {
            var low = 0
            var high = removed.count
            while low < high {
                let mid = (low + high) / 2
                if removed[mid].location < position { low = mid + 1 } else { high = mid }
            }
            return low == 0 ? nil : low - 1
        }
        func map(_ position: Int) -> Int {
            guard let i = last(before: position) else { return position }
            return position - before[i] - min(removed[i].length, position - removed[i].location)
        }
        var result: [TextEntity] = []
        for var entity in entities {
            let first = entity.offset
            let stop = entity.offset + entity.length
            if entity.kind == .mention {
                // Touched by a removal: the last one starting before its end reaches into it.
                if let i = last(before: stop), removed[i].location + removed[i].length > first { continue }
                entity.offset = map(first)
                result.append(entity)
                continue
            }
            let start = map(first)
            let end = map(stop)
            guard end > start else { continue }
            entity.offset = start
            entity.length = end - start
            result.append(entity)
        }
        return (out, result.sorted(by: TextEntity.precedes))
    }

    /// `EntityEditing.adding` of each inline range in `added`, at once: a kind's ranges that overlap or touch, new or
    /// already there, become one. Onto fitted ranges and fitted after, as `convert` does, it gives what adding them
    /// one at a time gives (a test holds it to that), without a scan and sort of every range per new one.
    static func merging(_ added: [TextEntity], into entities: [TextEntity]) -> [TextEntity] {
        guard !added.isEmpty else { return entities }
        let kinds = Set(added.map(\.kind))
        var kept = entities.filter { !kinds.contains($0.kind) }
        for kind in kinds {
            let ranges = (entities + added).filter { $0.kind == kind }.sorted { $0.offset < $1.offset }
            var open: TextEntity?
            for range in ranges {
                if var current = open, range.offset <= current.offset + current.length {
                    current.length = max(current.offset + current.length, range.offset + range.length) - current.offset
                    open = current
                } else {
                    if let current = open { kept.append(current) }
                    open = range
                }
            }
            if let current = open { kept.append(current) }
        }
        return kept.sorted(by: TextEntity.precedes)
    }

    /// `*`, `_`, `~` and the backtick: the characters a draft escapes.
    private static func isMarkerCharacter(_ unit: unichar) -> Bool {
        unit == 0x2A || unit == 0x5F || unit == 0x7E || unit == 0x60
    }

    private static func longestRun(of character: Character, in text: String) -> Int {
        var longest = 0
        var run = 0
        for each in text {
            run = each == character ? run + 1 : 0
            longest = max(longest, run)
        }
        return longest
    }

    private static func isBlank(_ unit: unichar) -> Bool {
        unit == 0x20 || unit == 0x09 || unit == 0x0A || unit == 0x0D || unit == 0xA0
    }
}
