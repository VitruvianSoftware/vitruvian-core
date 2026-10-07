// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware
//
// Adapted from the standalone Nexus Agent app (apps/desktop/nexus-agent,
// MIT, Copyright (c) 2026 VitruvianSoftware): the geometry of its
// Spotlight-style Quick Prompt, its session list and its reply formatting,
// pulled out of the views so they can be tested.

import CoreGraphics
import Foundation

/// What the Quick Prompt panel is showing.
package enum NexusAgentQuickPromptMode: Equatable, Sendable {
    /// The input pill on its own.
    case compact
    /// The pill with the recent-sessions drawer open under it.
    case sessions
    /// The streaming conversation.
    case chat
}

/// Every size and position of the Quick Prompt panel, in one place.
package enum NexusAgentQuickPromptLayout {
    package static let width: CGFloat = 680
    package static let compactHeight: CGFloat = 72
    package static let sessionsHeight: CGFloat = 340
    package static let chatHeight: CGFloat = 500
    package static let cornerRadius: CGFloat = 22
    /// Gap above the pill, as a share of the screen height (Spotlight's spot).
    package static let topInsetFraction: CGFloat = 0.18
    package static let chatMinimumSize = CGSize(width: 480, height: 300)
    package static let chatMaximumSize = CGSize(width: 900, height: 800)
    /// The spring the panel resizes with.
    package static let springStiffness: Double = 500
    package static let springDamping: Double = 24

    package static func size(for mode: NexusAgentQuickPromptMode) -> CGSize {
        switch mode {
        case .compact: return CGSize(width: width, height: compactHeight)
        case .sessions: return CGSize(width: width, height: sessionsHeight)
        case .chat: return CGSize(width: width, height: chatHeight)
        }
    }

    /// Only the conversation can be resized by the user.
    package static func isResizable(_ mode: NexusAgentQuickPromptMode) -> Bool { mode == .chat }

    /// Where the panel opens: centred, its top edge in the upper third.
    package static func initialFrame(for mode: NexusAgentQuickPromptMode, screen: CGRect) -> CGRect {
        let size = size(for: mode)
        let top = screen.maxY - screen.height * topInsetFraction
        return clamp(CGRect(x: screen.midX - size.width / 2, y: top - size.height,
                            width: size.width, height: size.height), to: screen)
    }

    /// The frame after switching to `mode`: the top edge and centre stay
    /// where the user left them, so the panel grows and shrinks downward.
    package static func frame(for mode: NexusAgentQuickPromptMode, from current: CGRect,
                              screen: CGRect) -> CGRect {
        let size = size(for: mode)
        return clamp(CGRect(x: current.midX - size.width / 2, y: current.maxY - size.height,
                            width: size.width, height: size.height), to: screen)
    }

    private static func clamp(_ frame: CGRect, to screen: CGRect) -> CGRect {
        var result = frame
        result.origin.x = max(screen.minX, min(result.minX, screen.maxX - result.width))
        result.origin.y = max(screen.minY, min(result.minY, screen.maxY - result.height))
        return result
    }
}

/// One past agy conversation, as the sessions drawer lists it.
package struct NexusAgentSessionSummary: Identifiable, Equatable, Sendable {
    package let id: String
    package let title: String
    package let preview: String
    package let steps: Int
    package let modified: Date?

    package init(id: String, title: String, preview: String = "", steps: Int, modified: Date?) {
        self.id = id
        self.title = title
        self.preview = preview
        self.steps = steps
        self.modified = modified
    }

    /// The SQL the drawer runs against agy's `conversation_summaries.db`.
    package static let query = """
    SELECT conversation_id, title, preview, step_count, last_modified_time, workspace_uris \
    FROM conversation_summaries WHERE nesting_depth = 0 AND killed = 0 \
    ORDER BY last_modified_time DESC LIMIT 200;
    """

    /// Rows from `sqlite3 -json`, keeping the top-level conversations for
    /// `directory` and those with no recorded folder, newest first.
    /// An empty `directory` keeps all workspaces.
    package static func parse(_ data: Data, directory: String) -> [NexusAgentSessionSummary] {
        guard let rows = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }
        let trimmedDir = directory.trimmingCharacters(in: .whitespacesAndNewlines)
        let wanted = trimmedDir.isEmpty ? nil : normalizePath(trimmedDir)
        let dates = ISO8601DateFormatter()
        dates.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plainDates = ISO8601DateFormatter()
        return rows.compactMap { row in
            guard let id = row["conversation_id"] as? String, !id.isEmpty else { return nil }
            if let wanted,
               let text = row["workspace_uris"] as? String, let raw = text.data(using: .utf8),
               let folders = try? JSONSerialization.jsonObject(with: raw) as? [String],
               !folders.isEmpty {
                let normalizedFolders = folders.map(normalizePath)
                if !normalizedFolders.contains(where: { folderMatches($0, target: wanted) }) {
                    return nil
                }
            }
            let preview = (row["preview"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let title = [row["title"] as? String, preview]
                .compactMap { $0?.split(separator: "\n").first.map(String.init) }
                .first { !$0.trimmingCharacters(in: .whitespaces).isEmpty } ?? ""
            let stamp = row["last_modified_time"] as? String ?? ""
            return NexusAgentSessionSummary(id: id, title: String(title.prefix(100)),
                                            preview: preview,
                                            steps: (row["step_count"] as? NSNumber)?.intValue ?? 0,
                                            modified: dates.date(from: stamp) ?? plainDates.date(from: stamp))
        }
    }

    /// Converts a filesystem path to Claude Code's project directory slug by
    /// replacing every non-alphanumeric character with `-`.
    package static func projectSlug(for path: String) -> String {
        let chars = path.map { char -> Character in
            if char.isASCII && (char.isLetter || char.isNumber) {
                return char
            } else {
                return "-"
            }
        }
        return String(chars)
    }

    /// Discovers and parses Claude Code session JSONL files in `~/.claude/projects/`.
    /// When `directory` is provided (and not home), checks `~/.claude/projects/<slug>`.
    /// Otherwise scans all project directories under `~/.claude/projects/`.
    package static func parseClaudeSessions(home: String, directory: String) -> [NexusAgentSessionSummary] {
        let fileManager = FileManager.default
        let claudeProjectsDir = (home as NSString).appendingPathComponent(".claude/projects")
        guard fileManager.fileExists(atPath: claudeProjectsDir) else { return [] }

        var targetDirs: [String] = []
        let trimmedDir = directory.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedDir.isEmpty && trimmedDir != home {
            let slug = projectSlug(for: normalizePath(trimmedDir))
            let specificDir = (claudeProjectsDir as NSString).appendingPathComponent(slug)
            if fileManager.fileExists(atPath: specificDir) {
                targetDirs.append(specificDir)
            }
        }
        if targetDirs.isEmpty {
            if let subdirs = try? fileManager.contentsOfDirectory(atPath: claudeProjectsDir) {
                targetDirs = subdirs.map { (claudeProjectsDir as NSString).appendingPathComponent($0) }
            }
        }

        var candidateFiles: [(path: String, modDate: Date)] = []
        for dir in targetDirs {
            guard let files = try? fileManager.contentsOfDirectory(atPath: dir) else { continue }
            for file in files where file.hasSuffix(".jsonl") {
                let fullPath = (dir as NSString).appendingPathComponent(file)
                let attrs = try? fileManager.attributesOfItem(atPath: fullPath)
                let modDate = (attrs?[.modificationDate] as? Date) ?? Date.distantPast
                candidateFiles.append((path: fullPath, modDate: modDate))
            }
        }

        candidateFiles.sort { $0.modDate > $1.modDate }
        let topCandidates = candidateFiles.prefix(100)

        var summaries: [NexusAgentSessionSummary] = []
        for candidate in topCandidates {
            let fileURL = URL(fileURLWithPath: candidate.path)
            let sessionID = fileURL.deletingPathExtension().lastPathComponent

            guard let content = try? String(contentsOfFile: candidate.path, encoding: .utf8) else { continue }
            let lines = content.components(separatedBy: "\n").prefix(60)

            var title = ""
            var preview = ""
            var steps = 0

            for line in lines {
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty,
                      let data = trimmed.data(using: .utf8),
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let type = json["type"] as? String else { continue }

                if type == "ai-title", let aiTitle = json["aiTitle"] as? String, !aiTitle.isEmpty {
                    if title.isEmpty { title = aiTitle }
                } else if type == "queue-operation", let op = json["operation"] as? String, op == "enqueue",
                          let opContent = json["content"] as? String, !opContent.isEmpty {
                    if preview.isEmpty { preview = opContent }
                } else if type == "user" {
                    steps += 1
                    if preview.isEmpty {
                        if let msg = json["message"] as? [String: Any] {
                            if let text = msg["content"] as? String, !text.isEmpty {
                                preview = extractUserPrompt(text)
                            } else if let blocks = msg["content"] as? [[String: Any]] {
                                let texts = blocks.compactMap { $0["text"] as? String }
                                if !texts.isEmpty { preview = extractUserPrompt(texts.joined(separator: "\n")) }
                            }
                        } else if let text = json["content"] as? String, !text.isEmpty {
                            preview = extractUserPrompt(text)
                        }
                    }
                } else if type == "assistant" {
                    steps += 1
                }
            }

            if title.isEmpty {
                let firstLine = preview.split(separator: "\n").first.map(String.init) ?? ""
                let trimmedFirstLine = firstLine.trimmingCharacters(in: .whitespaces)
                if !trimmedFirstLine.isEmpty {
                    title = String(trimmedFirstLine.prefix(100))
                } else {
                    title = "Untitled Claude Session"
                }
            }

            summaries.append(NexusAgentSessionSummary(
                id: sessionID,
                title: title,
                preview: preview,
                steps: steps,
                modified: candidate.modDate == Date.distantPast ? nil : candidate.modDate
            ))
        }

        summaries.sort { ($0.modified ?? Date.distantPast) > ($1.modified ?? Date.distantPast) }
        return summaries
    }

    package static func extractUserPrompt(_ raw: String) -> String {
        if let start = raw.range(of: "<USER_REQUEST>"),
           let end = raw.range(of: "</USER_REQUEST>", range: start.upperBound..<raw.endIndex) {
            return String(raw[start.upperBound..<end.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func normalizePath(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("file://") {
            if let url = URL(string: trimmed) {
                let path = url.standardizedFileURL.path
                return (path.hasSuffix("/") && path.count > 1) ? String(path.dropLast()) : path
            }
            let stripped = String(trimmed.dropFirst("file://".count))
            let path = URL(fileURLWithPath: stripped).standardizedFileURL.path
            return (path.hasSuffix("/") && path.count > 1) ? String(path.dropLast()) : path
        }
        let path = URL(fileURLWithPath: trimmed).standardizedFileURL.path
        return (path.hasSuffix("/") && path.count > 1) ? String(path.dropLast()) : path
    }

    private static func folderMatches(_ folderPath: String, target targetPath: String) -> Bool {
        folderPath == targetPath
            || folderPath.hasPrefix(targetPath + "/")
            || targetPath.hasPrefix(folderPath + "/")
    }

    /// Sessions whose title holds every word of `filter`, ignoring case.
    package static func filter(_ sessions: [NexusAgentSessionSummary], by filter: String) -> [NexusAgentSessionSummary] {
        let words = filter.lowercased().split(whereSeparator: \.isWhitespace)
        guard !words.isEmpty else { return sessions }
        return sessions.filter { session in
            let title = session.title.lowercased()
            return words.allSatisfy { title.contains($0) }
        }
    }
}

/// A reply split into prose and fenced code, the way the chat draws it.
package enum NexusAgentReplyBlock: Equatable, Sendable {
    /// Markdown prose, drawn with inline formatting.
    case text(String)
    /// A fenced code block; `language` is the word after the fence, if any.
    case code(language: String?, body: String)

    /// Splits on ``` fences. An unclosed fence (a reply still streaming)
    /// is code up to the end.
    package static func parse(_ reply: String) -> [NexusAgentReplyBlock] {
        var blocks: [NexusAgentReplyBlock] = []
        var prose: [String] = []
        var code: [String]?
        var language: String?
        func flushProse() {
            let text = prose.joined(separator: "\n").trimmingCharacters(in: .newlines)
            if !text.isEmpty { blocks.append(.text(text)) }
            prose = []
        }
        for line in reply.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") {
                if let open = code {
                    blocks.append(.code(language: language, body: open.joined(separator: "\n")))
                    code = nil
                    language = nil
                } else {
                    flushProse()
                    let tag = trimmed.dropFirst(3).trimmingCharacters(in: .whitespaces)
                    language = tag.isEmpty ? nil : tag
                    code = []
                }
            } else if code != nil {
                code?.append(line)
            } else {
                prose.append(line)
            }
        }
        if let open = code { blocks.append(.code(language: language, body: open.joined(separator: "\n"))) }
        flushProse()
        return blocks
    }
}

/// Structured Markdown block elements parsed from prose.
package enum NexusAgentMarkdownBlock: Equatable, Sendable {
    case heading(level: Int, text: String)
    case bulletItem(text: String)
    case numberedItem(number: String, text: String)
    case blockquote(text: String)
    case divider
    case paragraph(text: String)

    /// Parses a markdown text string into structured blocks.
    package static func parse(_ text: String) -> [NexusAgentMarkdownBlock] {
        var blocks: [NexusAgentMarkdownBlock] = []
        var paragraphLines: [String] = []
        var quoteLines: [String] = []

        func flushQuote() {
            guard !quoteLines.isEmpty else { return }
            let joined = quoteLines.joined(separator: "\n").trimmingCharacters(in: .newlines)
            if !joined.isEmpty {
                blocks.append(.blockquote(text: joined))
            }
            quoteLines = []
        }

        func flushParagraph() {
            guard !paragraphLines.isEmpty else { return }
            let joined = paragraphLines.joined(separator: "\n").trimmingCharacters(in: .newlines)
            if !joined.isEmpty {
                blocks.append(.paragraph(text: joined))
            }
            paragraphLines = []
        }

        func flushAll() {
            flushQuote()
            flushParagraph()
        }

        for line in text.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                flushAll()
            } else if isDivider(trimmed) {
                flushAll()
                blocks.append(.divider)
            } else if let (level, headingText) = parseHeading(trimmed) {
                flushAll()
                blocks.append(.heading(level: level, text: headingText))
            } else if let bullet = parseBullet(trimmed) {
                flushAll()
                blocks.append(.bulletItem(text: bullet))
            } else if let (num, itemText) = parseNumbered(trimmed) {
                flushAll()
                blocks.append(.numberedItem(number: num, text: itemText))
            } else if isBlockquote(trimmed) {
                flushParagraph()
                quoteLines.append(blockquoteContent(trimmed))
            } else {
                flushQuote()
                paragraphLines.append(trimmed)
            }
        }
        flushAll()
        return blocks
    }

    private static func isDivider(_ trimmed: String) -> Bool {
        let stripped = trimmed.filter { !$0.isWhitespace }
        guard stripped.count >= 3 else { return false }
        return stripped.allSatisfy { $0 == "-" }
            || stripped.allSatisfy { $0 == "*" }
            || stripped.allSatisfy { $0 == "_" }
    }

    private static func parseHeading(_ trimmed: String) -> (level: Int, text: String)? {
        guard trimmed.hasPrefix("#") else { return nil }
        var level = 0
        var index = trimmed.startIndex
        while index < trimmed.endIndex && trimmed[index] == "#" {
            level += 1
            index = trimmed.index(after: index)
        }
        guard level >= 1 && level <= 6, index < trimmed.endIndex, trimmed[index] == " " || trimmed[index] == "\t" else {
            return nil
        }
        let headingText = String(trimmed[index...]).trimmingCharacters(in: .whitespaces)
        return (level, headingText)
    }

    private static func parseBullet(_ trimmed: String) -> String? {
        if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") || trimmed.hasPrefix("+ ") {
            return String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
        }
        return nil
    }

    private static func parseNumbered(_ trimmed: String) -> (number: String, text: String)? {
        var digits = ""
        var index = trimmed.startIndex
        while index < trimmed.endIndex && trimmed[index].isNumber {
            digits.append(trimmed[index])
            index = trimmed.index(after: index)
        }
        guard !digits.isEmpty, index < trimmed.endIndex else { return nil }
        let delimiter = trimmed[index]
        guard delimiter == "." || delimiter == ")" else { return nil }
        index = trimmed.index(after: index)
        guard index < trimmed.endIndex, trimmed[index] == " " || trimmed[index] == "\t" else { return nil }
        while index < trimmed.endIndex && (trimmed[index] == " " || trimmed[index] == "\t") {
            index = trimmed.index(after: index)
        }
        let itemText = String(trimmed[index...]).trimmingCharacters(in: .whitespaces)
        return (digits, itemText)
    }

    private static func isBlockquote(_ trimmed: String) -> Bool {
        trimmed.hasPrefix("> ") || trimmed == ">"
    }

    private static func blockquoteContent(_ trimmed: String) -> String {
        if trimmed.hasPrefix("> ") {
            return String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
        } else if trimmed == ">" {
            return ""
        }
        return trimmed
    }
}

