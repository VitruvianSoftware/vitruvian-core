// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation

/// One piece of markdown typed into the message box: `code`, **bold**, _italic_ (or *italic*) and ~~strike~~.
///
/// The message box shows these as you type: the words take on the look (a code chip, bold, slanted, struck through)
/// and the marker characters around them are drawn faint. The text itself is never changed, so what is sent is exactly
/// what was typed. Ranges are UTF-16 offsets into the text, as `NSTextView` counts.
public struct MarkdownSpan: Equatable, Sendable {
    public enum Kind: Sendable {
        case code
        case bold
        case italic
        case strikethrough
    }

    public var kind: Kind
    /// The opening marker (`**`, `_`, a run of backticks, `~~`).
    public var open: NSRange
    /// The words between the markers, which carry the look.
    public var content: NSRange
    /// The closing marker.
    public var close: NSRange

    public init(kind: Kind, open: NSRange, content: NSRange, close: NSRange) {
        self.kind = kind
        self.open = open
        self.content = content
        self.close = close
    }

    /// Both markers and everything between them.
    public var whole: NSRange {
        NSRange(location: open.location, length: close.location + close.length - open.location)
    }
}

/// Finds the markdown spans in a draft. It is deliberately cautious, so a word is never styled by accident:
///
/// - A marker needs text hugging it on the inside (`** bold **` and `2 * 3 * 4` do nothing).
/// - `_` only counts at the edge of a word, so `snake_case_name` stays plain.
/// - A span never reaches across a line break, except a fence of three or more backticks.
/// - Code is not looked into: `**x**` inside backticks is just code.
/// - A backslash keeps the next punctuation mark as itself (`\*not italic\*`).
public enum MarkdownSpans {
    /// Longer drafts are not styled: the scan is cheap, but a paste of a whole file is not a message being formatted.
    public static let maximumLength = 20_000

    public static func parse(_ text: String) -> [MarkdownSpan] {
        let units = Array(text.utf16)
        guard units.count >= 2, units.count <= maximumLength else { return [] }
        var scanner = Scanner(units: units)
        scanner.scan(0, units.count)
        return scanner.spans
    }

    private struct Scanner {
        let units: [UInt16]
        var spans: [MarkdownSpan] = []

        private static let backslash = UInt16(UInt8(ascii: "\\"))
        private static let backtick = UInt16(UInt8(ascii: "`"))
        private static let star = UInt16(UInt8(ascii: "*"))
        private static let underscore = UInt16(UInt8(ascii: "_"))
        private static let tilde = UInt16(UInt8(ascii: "~"))
        private static let newline = UInt16(UInt8(ascii: "\n"))

        init(units: [UInt16]) {
            self.units = units
        }

        mutating func scan(_ low: Int, _ high: Int) {
            var i = low
            while i < high {
                let unit = units[i]
                if unit == Self.backslash, i + 1 < high, isPunctuation(units[i + 1]) {
                    i += 2
                    continue
                }
                if unit == Self.backtick {
                    let run = runLength(of: unit, at: i, before: high)
                    if let close = backtickClose(after: i + run, before: high, run: run), close > i + run {
                        spans.append(MarkdownSpan(
                            kind: .code,
                            open: NSRange(location: i, length: run),
                            content: NSRange(location: i + run, length: close - (i + run)),
                            close: NSRange(location: close, length: run)
                        ))
                        i = close + run
                    } else {
                        i += run
                    }
                    continue
                }
                if unit == Self.star || unit == Self.underscore || unit == Self.tilde {
                    let run = runLength(of: unit, at: i, before: high)
                    let want: Int
                    switch unit {
                    case Self.tilde: want = run >= 2 ? 2 : 0
                    case Self.star: want = run >= 2 ? 2 : 1
                    default: want = run == 1 ? 1 : 0 // `__init__` is a name, not emphasis
                    }
                    if want > 0, canOpen(unit, at: i, want: want, before: high),
                       let close = findClose(unit, want: want, from: i + want, before: high) {
                        let kind: MarkdownSpan.Kind = unit == Self.tilde ? .strikethrough : (want == 2 ? .bold : .italic)
                        spans.append(MarkdownSpan(
                            kind: kind,
                            open: NSRange(location: i, length: want),
                            content: NSRange(location: i + want, length: close - (i + want)),
                            close: NSRange(location: close, length: want)
                        ))
                        scan(i + want, close)
                        i = close + want
                    } else {
                        i += max(run, 1)
                    }
                    continue
                }
                i += 1
            }
        }

        private func runLength(of unit: UInt16, at start: Int, before high: Int) -> Int {
            var end = start
            while end < high, units[end] == unit { end += 1 }
            return end - start
        }

        /// Where the next run of exactly `run` backticks starts. Short runs stop at the end of the line.
        private func backtickClose(after start: Int, before high: Int, run: Int) -> Int? {
            var j = start
            while j < high {
                let unit = units[j]
                if unit == Self.newline, run < 3 { return nil }
                if unit == Self.backtick {
                    let length = runLength(of: unit, at: j, before: high)
                    if length == run { return j }
                    j += length
                } else {
                    j += 1
                }
            }
            return nil
        }

        private func canOpen(_ marker: UInt16, at i: Int, want: Int, before high: Int) -> Bool {
            let next = i + want
            guard next < high, !isWhitespace(units[next]) else { return false }
            if marker == Self.underscore, i > 0, isWordCharacter(units[i - 1]) { return false }
            return true
        }

        /// The start of the marker that closes a span opened with `want` of `marker`, searching from `start`.
        private func findClose(_ marker: UInt16, want: Int, from start: Int, before high: Int) -> Int? {
            var j = start
            while j < high {
                let unit = units[j]
                if unit == Self.newline { return nil }
                if unit == Self.backslash, j + 1 < high {
                    j += 2
                    continue
                }
                if unit == Self.backtick {
                    // Code inside is skipped whole: a marker in it closes nothing.
                    let run = runLength(of: unit, at: j, before: high)
                    if let close = backtickClose(after: j + run, before: high, run: run) {
                        j = close + run
                    } else {
                        j += run
                    }
                    continue
                }
                if unit == marker {
                    let run = runLength(of: unit, at: j, before: high)
                    // A single marker only closes on a lone one: `**` inside `*a **b** c*` belongs to the bold.
                    let position: Int? = want == 1 ? (run == 1 ? j : nil) : (run >= want ? j + run - want : nil)
                    if let position, position > start, isValidClose(marker, at: position, want: want, before: high) {
                        return position
                    }
                    j += run
                    continue
                }
                j += 1
            }
            return nil
        }

        private func isValidClose(_ marker: UInt16, at position: Int, want: Int, before high: Int) -> Bool {
            guard !isWhitespace(units[position - 1]) else { return false }
            if marker == Self.underscore {
                let after = position + want
                if after < high, isWordCharacter(units[after]) { return false }
            }
            return true
        }

        private func isWhitespace(_ unit: UInt16) -> Bool {
            unit == 0x20 || unit == 0x09 || unit == 0x0A || unit == 0x0D || unit == 0xA0
        }

        private func isPunctuation(_ unit: UInt16) -> Bool {
            guard unit < 0x80, let scalar = Unicode.Scalar(unit) else { return false }
            return !CharacterSet.alphanumerics.contains(scalar) && !CharacterSet.whitespacesAndNewlines.contains(scalar)
                && scalar.value > 0x20
        }

        private func isWordCharacter(_ unit: UInt16) -> Bool {
            // Letters and digits in any script. The halves of a surrogate pair (emoji, mostly) are not word characters.
            guard let scalar = Unicode.Scalar(unit) else { return false }
            return CharacterSet.alphanumerics.contains(scalar)
        }
    }
}
