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
//
// Shared by the standalone Vitruvian Code app and the Code feature of the
// Vitruvian desktop app. Written for Vitruvian and released under MIT by its
// copyright holder on 2026-10-09 (apps/desktop/vitruvian-atrium/UPSTREAM.md).

import Foundation

/// A line diff between the text a tool replaced and the text it wrote, shared by
/// tool-step cards and diff review.
public enum VitruvianCodeLineDiff: Sendable {
    public struct Line: Equatable, Sendable {
        public enum Kind: Equatable, Sendable { case context, removed, added }
        public let kind: Kind
        public let text: String

        public init(_ kind: Kind, _ text: String) {
            self.kind = kind
            self.text = text
        }

        /// The line as a unified diff writes it.
        public var unified: String {
            switch kind {
            case .context: return "  " + text
            case .removed: return "- " + text
            case .added: return "+ " + text
            }
        }
    }

    /// Past this many lines on both sides the middle is not searched for
    /// common lines; it is shown as removed and then added.
    static let searchLimit = 400

    /// Maximum diff lines drawn inside a single tool-step card before truncating.
    public static let maxDisplayedLines = 200

    /// Splits diff text into lines, normalizing CRLF and ignoring a single trailing newline.
    public static func splitLines(_ text: String?) -> [String] {
        guard let text, !text.isEmpty else { return [] }
        var lines = text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        // A final newline ends the last line; it does not start another.
        if lines.count > 1, lines.last == "" { lines.removeLast() }
        return lines
    }

    /// Computes line diff entries capped at `limit` lines, returning the hidden remainder count.
    public static func cappedLines(
        old: String?,
        new: String?,
        limit: Int = maxDisplayedLines
    ) -> (lines: [Line], truncatedCount: Int) {
        let all = lines(old: old, new: new)
        let effectiveLimit = max(1, limit)
        guard all.count > effectiveLimit else {
            return (all, 0)
        }
        return (Array(all.prefix(effectiveLimit)), all.count - effectiveLimit)
    }

    /// The lines from `old` to `new`. A nil or empty `old` (a new file) is
    /// every line added. Common leading and trailing lines are context; the
    /// middle is matched line by line on its longest common subsequence.
    public static func lines(old: String?, new: String?) -> [Line] {
        let oldLines = splitLines(old)
        let newLines = splitLines(new)
        var prefix = 0
        while prefix < oldLines.count, prefix < newLines.count, oldLines[prefix] == newLines[prefix] {
            prefix += 1
        }
        var suffix = 0
        while suffix < oldLines.count - prefix, suffix < newLines.count - prefix,
            oldLines[oldLines.count - 1 - suffix] == newLines[newLines.count - 1 - suffix]
        {
            suffix += 1
        }
        let oldMiddle = Array(oldLines[prefix..<(oldLines.count - suffix)])
        let newMiddle = Array(newLines[prefix..<(newLines.count - suffix)])

        var result = oldLines[0..<prefix].map { Line(.context, $0) }
        result += middle(oldMiddle, newMiddle)
        result += oldLines[(oldLines.count - suffix)...].map { Line(.context, $0) }
        return result
    }

    private static func middle(_ old: [String], _ new: [String]) -> [Line] {
        if old.isEmpty { return new.map { Line(.added, $0) } }
        if new.isEmpty { return old.map { Line(.removed, $0) } }
        guard old.count <= searchLimit, new.count <= searchLimit else {
            return old.map { Line(.removed, $0) } + new.map { Line(.added, $0) }
        }
        // lengths[i][j]: the longest common subsequence of old[i...] and new[j...].
        var lengths = Array(repeating: Array(repeating: 0, count: new.count + 1), count: old.count + 1)
        for i in stride(from: old.count - 1, through: 0, by: -1) {
            for j in stride(from: new.count - 1, through: 0, by: -1) {
                lengths[i][j] = old[i] == new[j] ? lengths[i + 1][j + 1] + 1 : max(lengths[i + 1][j], lengths[i][j + 1])
            }
        }
        var result: [Line] = []
        var i = 0
        var j = 0
        while i < old.count, j < new.count {
            if old[i] == new[j] {
                result.append(Line(.context, old[i]))
                i += 1
                j += 1
            } else if lengths[i + 1][j] >= lengths[i][j + 1] {
                result.append(Line(.removed, old[i]))
                i += 1
            } else {
                result.append(Line(.added, new[j]))
                j += 1
            }
        }
        result += old[i...].map { Line(.removed, $0) }
        result += new[j...].map { Line(.added, $0) }
        return result
    }
}
