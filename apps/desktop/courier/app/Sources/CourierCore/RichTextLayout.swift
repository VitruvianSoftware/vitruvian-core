// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation

/// A message's text cut up the way a bubble draws it (01 §5's MessageText): blocks of whole lines (paragraphs, a
/// quote, a list, a code block), and each line in runs of one style. The view only turns runs into styled text.
public enum RichTextLayout {
    /// Lines of one kind, one after another.
    public struct Block: Equatable, Sendable {
        public enum Kind: Equatable, Sendable {
            case paragraph, quote, bulletList, orderedList, code
        }

        public let kind: Kind
        public let lines: [[Run]]
    }

    /// Text of one style. A link's or a mention's text is one run of its own.
    public struct Run: Equatable, Sendable {
        public var text: String
        public var bold = false
        public var italic = false
        public var strikethrough = false
        public var code = false
        public var spoiler = false
        /// A link's address (http, https or mailto).
        public var link: URL?
        /// A mention: a member's Matrix ID, or "@room".
        public var mention: String?

        public init(text: String, bold: Bool = false, italic: Bool = false, strikethrough: Bool = false,
                    code: Bool = false, spoiler: Bool = false, link: URL? = nil, mention: String? = nil) {
            self.text = text
            self.bold = bold
            self.italic = italic
            self.strikethrough = strikethrough
            self.code = code
            self.spoiler = spoiler
            self.link = link
            self.mention = mention
        }

        /// The same look: two runs that are can be one.
        func sameStyle(as other: Run) -> Bool {
            bold == other.bold && italic == other.italic && strikethrough == other.strikethrough && code == other.code
                && spoiler == other.spoiler && link == other.link && mention == other.mention
        }
    }

    /// The blocks of `rich`, in order. A list's lines are its items; an ordered list counts from 1 (the protocol
    /// keeps no start number, so `<ol start=N>` from another app reads from 1). A code block's lines are plain runs.
    public static func blocks(of rich: RichText) -> [Block] {
        let text = rich.text as NSString
        guard text.length > 0 else { return [] }
        var lines: [NSRange] = []
        var start = 0
        for index in 0 ..< text.length where text.character(at: index) == 0x0A {
            lines.append(NSRange(location: start, length: index - start))
            start = index + 1
        }
        lines.append(NSRange(location: start, length: text.length - start))

        let blockRanges = rich.entities.filter(\.kind.isBlock)
        let inline = rich.entities.filter { !$0.kind.isBlock }
        var blocks: [Block] = []
        var currentKind: Block.Kind?
        var currentEntity: TextEntity?
        var currentLines: [[Run]] = []

        func flush() {
            if let kind = currentKind, !currentLines.isEmpty { blocks.append(Block(kind: kind, lines: currentLines)) }
            currentLines = []
        }

        for line in lines {
            // A block covers whole lines; the first one that holds the line's start is its block.
            let block = blockRanges.first { entity in
                entity.offset <= line.location && line.location + line.length <= entity.offset + entity.length
                    && (line.length > 0 || entity.offset < line.location)
            }
            let kind = block.map { kind(of: $0.kind) } ?? .paragraph
            if kind != currentKind || block != currentEntity {
                flush()
                currentKind = kind
                currentEntity = block
            }
            let runs = kind == .code ? [Run(text: text.substring(with: line))] : runs(of: line, in: text, entities: inline)
            currentLines.append(runs)
        }
        flush()
        return blocks
    }

    private static func kind(of entity: TextEntity.Kind) -> Block.Kind {
        switch entity {
        case .blockquote: .quote
        case .bulletList: .bulletList
        case .orderedList: .orderedList
        default: .code
        }
    }

    /// One line's runs: cut wherever a range starts or ends.
    static func runs(of line: NSRange, in text: NSString, entities: [TextEntity]) -> [Run] {
        let lineEnd = line.location + line.length
        let onLine = entities.filter { $0.offset < lineEnd && $0.offset + $0.length > line.location }
        var cuts: Set<Int> = [line.location, lineEnd]
        for entity in onLine {
            cuts.insert(max(entity.offset, line.location))
            cuts.insert(min(entity.offset + entity.length, lineEnd))
        }
        let points = cuts.sorted()
        var runs: [Run] = []
        for (from, to) in zip(points, points.dropFirst()) where to > from {
            var run = Run(text: text.substring(with: NSRange(location: from, length: to - from)))
            for entity in onLine where entity.offset <= from && to <= entity.offset + entity.length {
                switch entity.kind {
                case .bold: run.bold = true
                case .italic: run.italic = true
                case .strikethrough: run.strikethrough = true
                case .code: run.code = true
                case .spoiler: run.spoiler = true
                case .link: run.link = entity.url.flatMap(URL.init(string:))
                case .mention: run.mention = entity.userID ?? ""
                default: break
                }
            }
            if let last = runs.last, last.sameStyle(as: run), run.link == nil, run.mention == nil {
                runs[runs.count - 1].text += run.text
            } else {
                runs.append(run)
            }
        }
        return runs
    }

    /// What VoiceOver reads: the text, with each hidden spoiler read as "Spoiler" until it is shown.
    public static func spoken(_ rich: RichText, revealed: Bool) -> String {
        guard !revealed else { return rich.text }
        let text = rich.text as NSString
        var result = ""
        var at = 0
        for spoiler in rich.entities.filter({ $0.kind == .spoiler }).sorted(by: { $0.offset < $1.offset })
            where spoiler.offset >= at && spoiler.offset + spoiler.length <= text.length {
            result += text.substring(with: NSRange(location: at, length: spoiler.offset - at))
            result += String(localized: "Spoiler")
            at = spoiler.offset + spoiler.length
        }
        return result + text.substring(from: at)
    }
}
