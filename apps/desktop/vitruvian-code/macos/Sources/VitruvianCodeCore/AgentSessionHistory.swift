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

/// One past session as the agent itself lists it (`session/list`).
public struct AgentListedSession: Equatable, Sendable {
    public var id: String
    /// The folder the session ran in; empty when the agent did not say.
    public var cwd: String
    public var title: String?
    /// ISO 8601, as the agent sent it.
    public var updatedAt: String?
    public var additionalDirectories: [String]

    public init(id: String, cwd: String = "", title: String? = nil, updatedAt: String? = nil,
                additionalDirectories: [String] = []) {
        self.id = id
        self.cwd = cwd
        self.title = title
        self.updatedAt = updatedAt
        self.additionalDirectories = additionalDirectories
    }
}

/// One page of an agent's session list, and the cursor for the next page when there is one.
public struct AgentSessionPage: Equatable, Sendable {
    public var sessions: [AgentListedSession]
    public var nextCursor: String?

    public init(sessions: [AgentListedSession] = [], nextCursor: String? = nil) {
        self.sessions = sessions
        self.nextCursor = nextCursor
    }
}

/// An open connection that can ask its agent for the agent's own past sessions.
/// Asking never starts a process: only a chat's live connection is asked.
@MainActor
public protocol AgentSessionListing: AnyObject {
    /// Throws `ACPConnectionError.sessionListNotAdvertised` when the agent does not offer it.
    func listSessionPage(cwd: String?, cursor: String?) async throws -> AgentSessionPage
}

/// The chat's "Recent sessions" list, read from the agent where it offers that.
///
/// Each agent owns its own history. When a chat's live connection to the agent
/// is open and advertises `session/list`, the rows (which sessions, their
/// titles, times and folders) come from it, and `session_info_update` keeps an
/// open row current. Otherwise the transcript readers (`Environment.listSessions`)
/// give today's list unchanged. Nothing is stored: every refresh asks again.
///
/// No agent process is ever started just to list. Measured on agy 1.5.16, that
/// took 2 to 12 seconds, 0.9 to 1.5 GB for agy itself, and started every MCP
/// server in the user's agy settings, for a list the transcript readers give
/// at once. T3 Code at `d6e5f2e0` does not list agy sessions over ACP either:
/// `apps/server/src/provider/AntigravityProvider.ts` sets no
/// `acpSessionManagement`, which only registry agents have
/// (`packages/provider-acp-registry/src/server/driver.ts`).
///
/// The request and row rules follow T3 Code's `listAcpRegistrySessions`
/// (`packages/provider-acp-registry/src/server/probe.ts`: `session/list` with
/// `cwd` and `cursor`, entries without an id dropped) and
/// `packages/provider-acp/src/server/runtimeModel.ts` (`session_info_update`:
/// trimmed title and time).
public enum AgentSessionHistory {
    /// Pages followed in one refresh, so an agent that keeps handing out cursors cannot hold the list.
    public static let maxPages = 10
    /// Rows kept, the same number the transcript reader's query takes (`LIMIT 200`).
    public static let maxSessions = 200
    /// Longest title kept, as T3 Code bounds it.
    static let maxTitleLength = 1_024

    /// Every page of the agent's list for `cwd`, following `nextCursor` until it
    /// runs out, repeats, or `maxPages` is reached. A session listed twice keeps
    /// its first entry.
    @MainActor
    public static func fetchAll(from lister: any AgentSessionListing, cwd: String?,
                                maxPages: Int = AgentSessionHistory.maxPages) async throws -> [AgentListedSession] {
        var collected: [AgentListedSession] = []
        var seenIDs = Set<String>()
        var seenCursors = Set<String>()
        var cursor: String?
        for _ in 0..<max(1, maxPages) {
            let page = try await lister.listSessionPage(cwd: cwd, cursor: cursor)
            for session in page.sessions where seenIDs.insert(session.id).inserted {
                collected.append(session)
            }
            guard let next = page.nextCursor?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !next.isEmpty, seenCursors.insert(next).inserted else { break }
            cursor = next
        }
        return collected
    }

    /// The drawer's rows from the agent's list: kept for `directory` by the same
    /// rule as the transcript reader (an empty folder, or home, keeps every
    /// workspace; a session with no folder is always kept), newest first, at
    /// most `maxSessions`. The title, time and folder are the agent's. What
    /// `session/list` does not carry (preview, step count, archived) is taken
    /// from the transcript reader's row for the same session when there is one.
    public static func summaries(listed: [AgentListedSession], directory: String, home: String,
                                 transcriptRows: [VitruvianCodeSessionSummary],
                                 now: Date = Date()) -> [VitruvianCodeSessionSummary] {
        let trimmed = directory.trimmingCharacters(in: .whitespacesAndNewlines)
        let wanted = (trimmed.isEmpty || trimmed == home) ? nil : VitruvianCodeSessionSummary.normalizePath(trimmed)
        var known: [String: VitruvianCodeSessionSummary] = [:]
        for row in transcriptRows where known[row.id] == nil {
            known[row.id] = row
        }
        let rows: [VitruvianCodeSessionSummary] = listed.compactMap { session in
            let id = session.id.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !id.isEmpty else { return nil }
            let rawFolder = session.cwd.trimmingCharacters(in: .whitespacesAndNewlines)
            let folder = rawFolder.isEmpty ? "" : VitruvianCodeSessionSummary.normalizePath(rawFolder)
            if let wanted, !folder.isEmpty, !VitruvianCodeSessionSummary.folderMatches(folder, target: wanted) {
                return nil
            }
            let local = known[id]
            let modified = parseDate(session.updatedAt) ?? local?.modified
            let title = cleanTitle(session.title) ?? local?.title ?? ""
            return VitruvianCodeSessionSummary(
                id: id,
                title: String(title.prefix(100)),
                preview: local?.preview ?? "",
                steps: local?.steps ?? 0,
                modified: modified,
                isArchived: local?.isArchived ?? false,
                workspace: folder.isEmpty ? (local?.workspace ?? "") : folder,
                isLive: VitruvianCodeSessionSummary.isLive(modified: modified, now: now)
            )
        }
        let ordered = rows.enumerated().sorted { lhs, rhs in
            switch (lhs.element.modified, rhs.element.modified) {
            case let (left?, right?) where left != right: return left > right
            case (.some, nil): return true
            case (nil, .some): return false
            default: return lhs.offset < rhs.offset
            }
        }.map(\.element)
        return Array(ordered.prefix(maxSessions))
    }

    /// `rows` with the agent's `session_info_update` for `sessionID` applied: a
    /// new title or time replaces the old one. A session not in the list is left
    /// for the next refresh to bring in.
    public static func applyingSessionInfo(title: String?, updatedAt: String?, sessionID: String,
                                           to rows: [VitruvianCodeSessionSummary],
                                           now: Date = Date()) -> [VitruvianCodeSessionSummary] {
        let newTitle = cleanTitle(title)
        let newDate = parseDate(updatedAt)
        guard newTitle != nil || newDate != nil else { return rows }
        return rows.map { row in
            guard row.id == sessionID else { return row }
            let modified = newDate ?? row.modified
            return VitruvianCodeSessionSummary(
                id: row.id,
                title: newTitle.map { String($0.prefix(100)) } ?? row.title,
                preview: row.preview,
                steps: row.steps,
                modified: modified,
                isArchived: row.isArchived,
                workspace: row.workspace,
                isPinned: row.isPinned,
                isLive: VitruvianCodeSessionSummary.isLive(modified: modified, now: now)
            )
        }
    }

    /// An agent-sent time, with or without fractional seconds.
    public static func parseDate(_ raw: String?) -> Date? {
        guard let text = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: text) ?? ISO8601DateFormatter().date(from: text)
    }

    /// The first line of a title, trimmed and bounded; nil when nothing is left.
    static func cleanTitle(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let firstLine = raw.split(separator: "\n").first.map(String.init) ?? ""
        let trimmed = firstLine.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : String(trimmed.prefix(maxTitleLength))
    }
}

extension ACPConnection: AgentSessionListing {
    public func listSessionPage(cwd: String?, cursor: String?) async throws -> AgentSessionPage {
        let result = try await listSessions(cwd: cwd, cursor: cursor)
        return AgentSessionPage(
            sessions: result.sessions.map {
                AgentListedSession(id: $0.sessionId, cwd: $0.cwd ?? "", title: $0.title,
                                   updatedAt: $0.updatedAt,
                                   additionalDirectories: $0.additionalDirectories ?? [])
            },
            nextCursor: result.nextCursor
        )
    }
}
