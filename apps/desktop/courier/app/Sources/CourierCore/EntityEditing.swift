// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation

/// How the composer's formatting ranges follow its text, and what the formatting keys do to them. Every offset and
/// length is in UTF-16 code units, as NSString and NSRange count them.
///
/// The ranges made here are ones the engine takes once `RichTextHTML.sendable` has cleaned them: a block covers whole
/// lines (never its last line break), styles of one kind that touch are one range.
public enum EntityEditing {
    /// Kinds a key puts on or takes off a selection.
    static let inline: Set<TextEntity.Kind> = [.bold, .italic, .strikethrough, .code, .spoiler]

    /// The ranges after `range` of `text` is replaced by `length` new UTF-16 units: later ranges shift, a range the edit
    /// falls inside grows or shrinks, a range wholly replaced goes, and a mention the edit touches goes (it is one unit).
    ///
    /// Typed text at a style's edge stays plain (a key with no selection formats what is typed next); typed text at a
    /// block's edge is part of the line, so the block takes it.
    public static func replacing(_ entities: [TextEntity], range: NSRange, with length: Int) -> [TextEntity] {
        let start = range.location
        let end = range.location + range.length
        let delta = length - range.length
        let isInsertion = range.length == 0
        var result: [TextEntity] = []
        for var entity in entities {
            let first = entity.offset
            let last = entity.offset + entity.length
            if entity.kind == .mention {
                let overlaps = !isInsertion && start < last && end > first
                let inside = start > first && start < last
                if overlaps || inside { continue }
                if end <= first { entity.offset += delta }
                result.append(entity)
                continue
            }
            if end <= first {
                if isInsertion, start == first, entity.kind.isBlock {
                    entity.length += length
                } else {
                    entity.offset += delta
                }
            } else if start >= last {
                if isInsertion, start == last, entity.kind.isBlock { entity.length += length }
            } else if start <= first, end >= last {
                continue // wholly deleted or replaced
            } else if start < first {
                // From before it into it: what is left of it follows the new text.
                entity.offset = start + length
                entity.length = last - end
            } else if end <= last {
                entity.length += delta // inside it
            } else {
                entity.length = start - first // from inside it to after it
            }
            if entity.length > 0 { result.append(entity) }
        }
        return result.sorted(by: TextEntity.precedes)
    }

    /// The formatting keys: an inline kind over a selection it already covers comes off it, otherwise goes on (merged
    /// with touching ranges of that kind); a block kind applies to every line the selection touches, replacing another.
    ///
    /// An inline kind with no selection, and a block on an empty line, change nothing here: the composer keeps them
    /// for what is typed next. Links and mentions have their own commands.
    public static func toggle(_ kind: TextEntity.Kind, in range: NSRange, of text: NSString, entities: [TextEntity])
        -> [TextEntity] {
        if kind.isBlock { return toggleBlock(kind, in: range, of: text, entities: entities) }
        guard inline.contains(kind), range.length > 0, range.location >= 0, range.location + range.length <= text.length
        else { return entities }
        let same = entities.filter { $0.kind == kind }
        if covers(same, from: range.location, to: range.location + range.length) {
            return removing(kind, from: range.location, to: range.location + range.length, in: entities)
        }
        return adding(kind, in: range, of: text, entities: entities)
    }

    /// `kind` on `range`, whatever was there: merged with the ranges of that kind it overlaps or touches. A block
    /// takes the whole lines `range` touches and replaces another block there.
    static func adding(_ kind: TextEntity.Kind, in range: NSRange, of text: NSString, entities: [TextEntity])
        -> [TextEntity] {
        if kind.isBlock {
            let span = lineSpan(of: range, in: text)
            guard span.length > 0 else { return entities }
            return addingBlock(kind, span: span, of: text, entities: entities)
        }
        guard range.length > 0 else { return entities }
        var from = range.location
        var to = range.location + range.length
        var kept: [TextEntity] = []
        for entity in entities {
            if entity.kind == kind, entity.offset <= to, entity.offset + entity.length >= from {
                from = min(from, entity.offset)
                to = max(to, entity.offset + entity.length)
            } else {
                kept.append(entity)
            }
        }
        kept.append(TextEntity(kind: kind, offset: from, length: to - from))
        return kept.sorted(by: TextEntity.precedes)
    }

    /// The whole lines `range` touches, without the line break after the last: from the start of the caret's line to
    /// its end. A selection that ends just after a line break doesn't take the line after it. Empty for an empty line.
    static func lineSpan(of range: NSRange, in text: NSString) -> NSRange {
        let length = text.length
        let location = min(max(range.location, 0), length)
        var lastIndex = range.length > 0 ? min(location + range.length, length) - 1 : location
        if range.length > 0, lastIndex > location, lastIndex < length, text.character(at: lastIndex) == 0x0A {
            lastIndex -= 1
        }
        var start = location
        while start > 0, text.character(at: start - 1) != 0x0A { start -= 1 }
        var end = max(lastIndex, start)
        while end < length, text.character(at: end) != 0x0A { end += 1 }
        return NSRange(location: start, length: end - start)
    }

    /// The ranges after an edit, fitted to the edited `text` as the engine will check them, so nothing is dropped
    /// unseen at send:
    ///   - a block covers whole lines again. One that now starts mid-line (Backspace joined its first line to the
    ///     line before) gives that line up: a joined line keeps the first line's block, or none. One that ends
    ///     mid-line takes the rest of the line, and none ends on a line break. Of two blocks on one line, the first
    ///     stays.
    ///   - a link or mention now over more than one line goes, and so does one on a line a code block took (as does
    ///     a style inside code);
    ///   - styles of one kind that now touch are one range.
    public static func fitted(_ entities: [TextEntity], to text: NSString) -> [TextEntity] {
        let length = text.length
        func isBreak(_ index: Int) -> Bool { text.character(at: index) == 0x0A }
        var blocks: [TextEntity] = []
        var atoms: [TextEntity] = []
        var styles: [TextEntity] = []
        for entity in entities where entity.length > 0 && entity.offset >= 0 && entity.offset + entity.length <= length {
            if entity.kind.isBlock {
                var start = entity.offset
                let originalEnd = entity.offset + entity.length
                if start > 0, !isBreak(start - 1) {
                    while start < originalEnd, !isBreak(start) { start += 1 }
                    start += 1 // the line after this one, if the block reaches it
                }
                guard start < originalEnd else { continue }
                var end = originalEnd
                while end > start, isBreak(end - 1) { end -= 1 }
                while end < length, !isBreak(end) { end += 1 }
                guard end > start else { continue }
                blocks.append(TextEntity(kind: entity.kind, offset: start, length: end - start))
            } else if entity.kind == .code {
                atoms.append(entity)
            } else if entity.kind == .link || entity.kind == .mention {
                let range = NSRange(location: entity.offset, length: entity.length)
                guard text.rangeOfCharacter(from: .newlines, options: [], range: range).location == NSNotFound
                else { continue }
                atoms.append(entity)
            } else {
                styles.append(entity)
            }
        }

        // Blocks: one of a kind that overlap become one; another kind on the same lines gives way to the first.
        var keptBlocks: [TextEntity] = []
        for block in blocks.sorted(by: TextEntity.precedes) {
            if let index = keptBlocks.firstIndex(where: {
                $0.kind == block.kind && $0.offset <= block.offset + block.length && block.offset <= $0.offset + $0.length
            }) {
                let first = min(keptBlocks[index].offset, block.offset)
                let last = max(keptBlocks[index].offset + keptBlocks[index].length, block.offset + block.length)
                keptBlocks[index] = TextEntity(kind: block.kind, offset: first, length: last - first)
                continue
            }
            if keptBlocks.contains(where: { $0.offset < block.offset + block.length && block.offset < $0.offset + $0.length }) {
                continue
            }
            keptBlocks.append(block)
        }

        // Nothing is formatted inside a code block (a line joined to one becomes code): no link, mention or code
        // there, and no style inside code.
        let codeBlocks = keptBlocks.filter { $0.kind == .pre }
        func overlaps(_ a: TextEntity, _ b: TextEntity) -> Bool {
            a.offset < b.offset + b.length && b.offset < a.offset + a.length
        }
        atoms.removeAll { atom in codeBlocks.contains { overlaps(atom, $0) } }
        let code = codeBlocks + atoms.filter { $0.kind == .code }
        styles.removeAll { style in
            code.contains { $0.offset <= style.offset && style.offset + style.length <= $0.offset + $0.length }
        }

        // Styles: one of a kind that overlap or touch become one.
        var keptStyles: [TextEntity] = []
        for kind in TextEntity.Kind.allCases {
            var open: TextEntity?
            for style in styles.filter({ $0.kind == kind }).sorted(by: { $0.offset < $1.offset }) {
                if var current = open, style.offset <= current.offset + current.length {
                    current.length = max(current.offset + current.length, style.offset + style.length) - current.offset
                    open = current
                } else {
                    if let current = open { keptStyles.append(current) }
                    open = style
                }
            }
            if let current = open { keptStyles.append(current) }
        }
        return (keptBlocks + atoms + keptStyles).sorted(by: TextEntity.precedes)
    }

    // MARK: - Blocks

    private static func toggleBlock(_ kind: TextEntity.Kind, in range: NSRange, of text: NSString,
                                    entities: [TextEntity]) -> [TextEntity] {
        let span = lineSpan(of: range, in: text)
        guard span.length > 0 else { return entities }
        let from = span.location
        let to = span.location + span.length
        // Covered: every character of these lines but their breaks is in a block of this kind.
        let blocks = entities.filter { $0.kind == kind }
        var covered = true
        for index in from ..< to where text.character(at: index) != 0x0A {
            if !blocks.contains(where: { $0.offset <= index && index < $0.offset + $0.length }) {
                covered = false
                break
            }
        }
        if covered { return removingBlocks(of: [kind], from: from, to: to, in: entities) }
        return addingBlock(kind, span: span, of: text, entities: entities)
    }

    private static func addingBlock(_ kind: TextEntity.Kind, span: NSRange, of text: NSString, entities: [TextEntity])
        -> [TextEntity] {
        let others = Set(TextEntity.Kind.allCases.filter { $0.isBlock && $0 != kind })
        var result = removingBlocks(of: others, from: span.location, to: span.location + span.length, in: entities)
        var from = span.location
        var to = span.location + span.length
        // Overlapping blocks of the kind, and ones on the line just before or after, become one.
        var kept: [TextEntity] = []
        for entity in result {
            let first = entity.offset
            let last = entity.offset + entity.length
            let touches = entity.kind == kind && (
                (first <= to && last >= from)
                    || (last + 1 == from && last < text.length && text.character(at: last) == 0x0A)
                    || (to + 1 == first && to < text.length && text.character(at: to) == 0x0A))
            if touches {
                from = min(from, first)
                to = max(to, last)
            } else {
                kept.append(entity)
            }
        }
        kept.append(TextEntity(kind: kind, offset: from, length: to - from))
        result = kept
        return result.sorted(by: TextEntity.precedes)
    }

    /// Takes the blocks of `kinds` off the lines from `from` to `to` (a line span). What is left of a block either
    /// side is whole lines, without the line break between.
    private static func removingBlocks(of kinds: Set<TextEntity.Kind>, from: Int, to: Int, in entities: [TextEntity])
        -> [TextEntity] {
        var result: [TextEntity] = []
        for entity in entities {
            let first = entity.offset
            let last = entity.offset + entity.length
            guard kinds.contains(entity.kind), first < to, last > from else {
                result.append(entity)
                continue
            }
            if first < from - 1 {
                result.append(TextEntity(kind: entity.kind, offset: first, length: from - 1 - first))
            }
            if last > to + 1 {
                result.append(TextEntity(kind: entity.kind, offset: to + 1, length: last - to - 1))
            }
        }
        return result.sorted(by: TextEntity.precedes)
    }

    // MARK: - Styles

    /// Whether `ranges` together cover every unit from `from` to `to`.
    private static func covers(_ ranges: [TextEntity], from: Int, to: Int) -> Bool {
        var reached = from
        for entity in ranges.sorted(by: { $0.offset < $1.offset }) {
            if entity.offset > reached { break }
            reached = max(reached, entity.offset + entity.length)
            if reached >= to { return true }
        }
        return reached >= to
    }

    /// Takes `kind` off the units from `from` to `to`; what is left of a range either side stays.
    private static func removing(_ kind: TextEntity.Kind, from: Int, to: Int, in entities: [TextEntity])
        -> [TextEntity] {
        var result: [TextEntity] = []
        for entity in entities {
            let first = entity.offset
            let last = entity.offset + entity.length
            guard entity.kind == kind, first < to, last > from else {
                result.append(entity)
                continue
            }
            if first < from { result.append(TextEntity(kind: kind, offset: first, length: from - first)) }
            if last > to { result.append(TextEntity(kind: kind, offset: to, length: last - to)) }
        }
        return result.sorted(by: TextEntity.precedes)
    }
}
