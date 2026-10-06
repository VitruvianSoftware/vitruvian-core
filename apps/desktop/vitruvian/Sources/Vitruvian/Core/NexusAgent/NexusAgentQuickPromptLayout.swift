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
    package let steps: Int
    package let modified: Date?

    package init(id: String, title: String, steps: Int, modified: Date?) {
        self.id = id
        self.title = title
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
    package static func parse(_ data: Data, directory: String) -> [NexusAgentSessionSummary] {
        guard let rows = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }
        let wanted = "file://" + URL(fileURLWithPath: directory).standardizedFileURL.path
        let dates = ISO8601DateFormatter()
        dates.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plainDates = ISO8601DateFormatter()
        return rows.compactMap { row in
            guard let id = row["conversation_id"] as? String, !id.isEmpty else { return nil }
            if let text = row["workspace_uris"] as? String, let raw = text.data(using: .utf8),
               let folders = try? JSONSerialization.jsonObject(with: raw) as? [String],
               !folders.isEmpty, !folders.contains(wanted) {
                return nil
            }
            let title = [row["title"] as? String, row["preview"] as? String]
                .compactMap { $0?.split(separator: "\n").first.map(String.init) }
                .first { !$0.trimmingCharacters(in: .whitespaces).isEmpty } ?? ""
            let stamp = row["last_modified_time"] as? String ?? ""
            return NexusAgentSessionSummary(id: id, title: String(title.prefix(100)),
                                            steps: (row["step_count"] as? NSNumber)?.intValue ?? 0,
                                            modified: dates.date(from: stamp) ?? plainDates.date(from: stamp))
        }
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
