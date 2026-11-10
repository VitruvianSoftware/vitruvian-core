// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation

/// Cleans and formats Markdown output returned by AI providers for summaries, translations, and composer drafts.
public enum AIOutputFormatter {
    /// Strips a single wrapping triple-backtick code fence (` ``` ` or ` ```markdown `) if the entire text is fenced.
    public static func stripCodeFence(_ raw: String) -> String {
        let normalized = raw
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let trimmed = normalized.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("```"), trimmed.hasSuffix("```"), trimmed.count >= 6 else {
            return trimmed
        }

        if let firstNewline = trimmed.firstIndex(of: "\n") {
            let openingFenceLine = trimmed[trimmed.index(trimmed.startIndex, offsetBy: 3) ..< firstNewline]
            // Opening line after ``` must only be an optional language tag (no backticks).
            guard !openingFenceLine.contains("`") else {
                return trimmed
            }
            let afterOpening = trimmed.index(after: firstNewline)
            let closingFenceStart = trimmed.index(trimmed.endIndex, offsetBy: -3)
            guard afterOpening <= closingFenceStart else {
                return ""
            }
            var body = String(trimmed[afterOpening ..< closingFenceStart])
            // If the closing ``` was preceded by horizontal whitespace on its own line, trim that trailing whitespace.
            while let last = body.last, last == " " || last == "\t" {
                body.removeLast()
            }
            if body.hasSuffix("\n") {
                body.removeLast()
            }
            // Ensure there isn't an intermediate closing/opening ``` fence inside the body.
            let innerLines = body.split(separator: "\n", omittingEmptySubsequences: false)
            let hasInnerFence = innerLines.contains { line in
                line.trimmingCharacters(in: .whitespaces).hasPrefix("```")
            }
            guard !hasInnerFence else {
                return trimmed
            }
            return body.trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            let start = trimmed.index(trimmed.startIndex, offsetBy: 3)
            let end = trimmed.index(trimmed.endIndex, offsetBy: -3)
            guard start <= end else { return "" }
            let inner = String(trimmed[start ..< end])
            guard !inner.contains("`") else { return trimmed }
            return inner.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    /// Strips a wrapping code fence, normalizes `"* item"` / `"- item"` / `"+ item"` bullets to `"• item"`,
    /// and removes stray blank lines between bullet items.
    public static func cleanMarkdown(_ raw: String) -> String {
        let unfenced = stripCodeFence(raw)
        guard !unfenced.isEmpty else { return "" }

        let rawLines = unfenced.components(separatedBy: "\n")
        struct ProcessedLine {
            let text: String
            let isBullet: Bool
            let isBlank: Bool
        }

        var processed: [ProcessedLine] = []
        processed.reserveCapacity(rawLines.count)

        for line in rawLines {
            let trimmedRight = line.replacingOccurrences(
                of: #"[ \t]+$"#,
                with: "",
                options: .regularExpression
            )
            let trimmed = trimmedRight.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                processed.append(ProcessedLine(text: "", isBullet: false, isBlank: true))
                continue
            }
            if let bulletRest = Self.extractBulletContent(from: trimmed) {
                processed.append(ProcessedLine(text: "• " + bulletRest, isBullet: true, isBlank: false))
                continue
            }
            let headingStripped = Self.stripHeadingPrefix(from: trimmedRight)
            processed.append(ProcessedLine(text: headingStripped, isBullet: false, isBlank: false))
        }

        // Remove leading/trailing blank lines, collapse multiple blank lines, and drop stray blank lines between bullets.
        var outputLines: [String] = []
        outputLines.reserveCapacity(processed.count)

        for idx in processed.indices {
            let current = processed[idx]
            if current.isBlank {
                guard let lastNonBlank = processed[..<idx].last(where: { !$0.isBlank }),
                      let nextNonBlank = processed[(idx + 1)...].first(where: { !$0.isBlank })
                else {
                    continue
                }
                // Drop stray blank lines between bullet items so bullets render as tight "•" lines.
                if lastNonBlank.isBullet && nextNonBlank.isBullet {
                    continue
                }
                if outputLines.last != "" {
                    outputLines.append("")
                }
            } else {
                outputLines.append(current.text)
            }
        }

        return outputLines.joined(separator: "\n")
    }

    /// Renders AI Markdown output as an `AttributedString` using `.inlineOnlyPreservingWhitespace`
    /// after normalizing code fences and `"•"` bullet lines.
    public static func attributed(_ raw: String) -> AttributedString {
        let cleaned = cleanMarkdown(raw)
        guard !cleaned.isEmpty else { return AttributedString() }
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace
        )
        if let parsed = try? AttributedString(markdown: cleaned, options: options) {
            return parsed
        }
        return AttributedString(cleaned)
    }

    /// Cleans AI draft output into plain text with Markdown markers removed for insertion into the composer.
    public static func plainText(_ raw: String) -> String {
        let cleaned = cleanMarkdown(raw)
        guard !cleaned.isEmpty else { return "" }

        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace
        )
        let lines = cleaned.components(separatedBy: "\n")
        var plainLines: [String] = []
        plainLines.reserveCapacity(lines.count)

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") {
                continue
            }
            let unquoted = Self.stripBlockquotePrefix(from: line)
            let inlineStripped: String
            if let parsed = try? AttributedString(markdown: unquoted, options: options) {
                inlineStripped = String(parsed.characters)
            } else {
                inlineStripped = unquoted
            }
            plainLines.append(Self.stripResidualMarkdownMarkers(from: inlineStripped))
        }

        return plainLines
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Private Helpers

    private static func extractBulletContent(from trimmedLine: String) -> String? {
        for prefix in ["* ", "*\t", "- ", "-\t", "+ ", "+\t", "• ", "•\t"] {
            if trimmedLine.hasPrefix(prefix) {
                let rest = trimmedLine.dropFirst(prefix.count).trimmingCharacters(in: .whitespaces)
                return rest.isEmpty ? nil : rest
            }
        }
        return nil
    }

    private static func stripHeadingPrefix(from line: String) -> String {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        var hashCount = 0
        for ch in trimmed {
            if ch == "#" {
                hashCount += 1
            } else {
                break
            }
        }
        guard (1 ... 6).contains(hashCount) else { return line }
        let afterHashes = trimmed.dropFirst(hashCount)
        guard let first = afterHashes.first, first == " " || first == "\t" else {
            return line
        }
        return String(afterHashes.drop(while: { $0 == " " || $0 == "\t" }))
    }

    private static func stripBlockquotePrefix(from line: String) -> String {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix(">") else { return line }
        let after = trimmed.dropFirst()
        if after.first == " " || after.first == "\t" {
            return String(after.dropFirst())
        }
        return String(after)
    }

    private static func stripResidualMarkdownMarkers(from text: String) -> String {
        var result = text
        // Convert any unparsed [label](url) links to label
        result = result.replacingOccurrences(
            of: #"\[([^\]]+)\]\([^)]+\)"#,
            with: "$1",
            options: .regularExpression
        )
        // Strip any remaining paired **bold**, __bold__, ~~strike~~, or `code` markers
        result = result.replacingOccurrences(
            of: #"(\*\*|__|~~)(.+?)\1"#,
            with: "$2",
            options: .regularExpression
        )
        result = result.replacingOccurrences(
            of: #"`([^`]+)`"#,
            with: "$1",
            options: .regularExpression
        )
        return result
    }
}
