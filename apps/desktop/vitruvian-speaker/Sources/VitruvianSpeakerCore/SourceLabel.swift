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

import Foundation

/// Whether an agent's announcement starts by saying where it came from:
/// "Claude: …", or "Claude, Courier: …" when another session of the same
/// app has spoken lately. Off unless chosen, so an older file speaks as it did.
public enum AnnounceSourceLabel: String, Codable, CaseIterable, Sendable {
    case off
    case app
    case appAndSession = "app_and_session"

    public var label: String {
        switch self {
        case .off: return "Off"
        case .app: return "App name"
        case .appAndSession: return "App and session name"
        }
    }
}

/// The session an agent's announcement came from: an id that tells two
/// sessions of one app apart, and a short name to say for it.
public struct SessionOrigin: Equatable, Sendable {
    public let id: String
    public let name: String?

    public init(id: String, name: String?) {
        self.id = id
        self.name = name.flatMap(SourceLabel.shortName)
    }

    /// `--session <id>` and `--session-name <name>` on `--announce`.
    public static let idFlag = "--session"
    public static let nameFlag = "--session-name"

    public var arguments: [String] {
        [Self.idFlag, id] + (name.map { [Self.nameFlag, $0] } ?? [])
    }

    /// A Claude Code session: the hook's `session_id`, named by the title
    /// the app gave it (the last one in its transcript), else its folder.
    public static func claudeCode(sessionID: String, transcriptPath: String?, cwd: String?) -> SessionOrigin? {
        guard !sessionID.isEmpty else { return nil }
        let title = transcriptPath.flatMap { SourceLabel.claudeTitle(transcript: URL(fileURLWithPath: $0)) }
        return SessionOrigin(id: sessionID, name: title ?? SourceLabel.folderName(cwd))
    }

    /// An Antigravity conversation, by the id in its transcript's path
    /// (`<brain>/<conversation>/.system_generated/logs/transcript.jsonl`),
    /// named by the folder it works in.
    public static func antigravity(transcriptPath: String, cwd: String?) -> SessionOrigin? {
        let logs = URL(fileURLWithPath: transcriptPath).deletingLastPathComponent()
        guard logs.lastPathComponent == "logs" else { return nil }
        let id = logs.deletingLastPathComponent().deletingLastPathComponent().lastPathComponent
        guard !id.isEmpty else { return nil }
        return SessionOrigin(id: id, name: SourceLabel.folderName(cwd))
    }

    /// The session a `--say` runs in, from the variables each agent sets
    /// for its commands; nil for a person's own `--say`.
    public static func fromEnvironment(
        _ environment: [String: String], agent: CodingAgent?,
        claudeProjects: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/projects")
    ) -> SessionOrigin? {
        let cwd = environment["PWD"]
        switch agent {
        case .claudeCode:
            guard let id = environment["CLAUDE_CODE_SESSION_ID"], !id.isEmpty else { return nil }
            return claudeCode(sessionID: id, transcriptPath: SourceLabel.claudeTranscript(id, in: claudeProjects)?.path, cwd: cwd)
        case .antigravity:
            guard let id = environment["ANTIGRAVITY_CONVERSATION_ID"], !id.isEmpty else { return nil }
            return SessionOrigin(id: id, name: SourceLabel.folderName(cwd))
        case .opencode, nil:
            // OpenCode sets no session variable for its commands; its hook
            // passes the session itself.
            return nil
        }
    }
}

/// The words an agent's announcement starts with, under `announce_source`.
public enum SourceLabel {
    /// How recently another session must have spoken for its name to matter.
    public static let busyWindow: TimeInterval = 30 * 60
    /// What the setting does, under it in Settings and the extension.
    public static let settingHelp = "Who it's from starts each agent announcement with the app: \"Claude:\". With the session name too, it says \"Claude, Courier:\" when another session of the same app has spoken in the last half hour."

    /// The most words said for a session.
    public static let maxWords = 3

    /// The app as one spoken word.
    public static func spokenName(_ agent: CodingAgent) -> String {
        switch agent {
        case .claudeCode: return "Claude"
        case .antigravity: return "Antigravity"
        case .opencode: return "OpenCode"
        }
    }

    /// "Claude: ", "Claude, Courier: ", or nil when off. The session's name
    /// is said only when another session of the same app spoke within
    /// `busyWindow`, by `history`: with one session it is just noise.
    public static func lead(
        _ mode: AnnounceSourceLabel, agent: CodingAgent, session: SessionOrigin?,
        history: [BroadcastLogItem], now: Date = Date()
    ) -> String? {
        let app = spokenName(agent)
        switch mode {
        case .off:
            return nil
        case .app:
            return "\(app): "
        case .appAndSession:
            guard let session, let name = session.name,
                  othersBusy(agent: agent, session: session.id, history: history, now: now) else { return "\(app): " }
            return "\(app), \(name): "
        }
    }

    static func othersBusy(agent: CodingAgent, session: String, history: [BroadcastLogItem], now: Date) -> Bool {
        history.contains {
            $0.source == agent.displayName && $0.session != nil && $0.session != session
                && now.timeIntervalSince($0.timestamp) <= busyWindow
        }
    }

    /// At most `maxWords` words for a title or folder: the part after a
    /// "project: " or "project - " prefix (the app names most sessions
    /// "vitruvian-core: Courier"), no brackets, dashes read as spaces.
    public static func shortName(_ raw: String) -> String? {
        var s = raw
        for separator in [": ", " - ", " — "] {
            if let r = s.range(of: separator, options: .backwards), !s[r.upperBound...].trimmingCharacters(in: .whitespaces).isEmpty {
                s = String(s[r.upperBound...])
                break
            }
        }
        s = s.replacingOccurrences(of: "\\([^)]*\\)|\\[[^\\]]*\\]", with: " ", options: .regularExpression)
        s = s.replacingOccurrences(of: "[-_/]+", with: " ", options: .regularExpression)
        s = s.replacingOccurrences(of: "[^\\p{L}\\p{N} ]", with: "", options: .regularExpression)
        let words = s.split(separator: " ").prefix(maxWords)
        return words.isEmpty ? nil : words.joined(separator: " ")
    }

    /// The working folder's name; nil for the home folder or none, which
    /// say nothing about the session.
    public static func folderName(_ path: String?) -> String? {
        guard let path, !path.isEmpty else { return nil }
        let url = URL(fileURLWithPath: path).standardizedFileURL
        guard url.path != FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL.path, url.path != "/" else { return nil }
        return url.lastPathComponent
    }

    /// `~/.claude/projects/<folder>/<id>.jsonl`.
    static func claudeTranscript(_ id: String, in projects: URL) -> URL? {
        guard !id.contains("/"),
              let folders = try? FileManager.default.contentsOfDirectory(at: projects, includingPropertiesForKeys: nil) else { return nil }
        return folders.lazy.map { $0.appendingPathComponent("\(id).jsonl") }
            .first { FileManager.default.fileExists(atPath: $0.path) }
    }

    /// The bytes read from a transcript's end for its title: the app writes
    /// the title again as the session goes on.
    static let titleTailBytes = 1 << 20

    /// The latest title in a Claude Code transcript: a `custom-title` (set
    /// by the person or the desktop app) or an `ai-title` line.
    static func claudeTitle(transcript: URL) -> String? {
        guard let tail = AntigravityHook.readTailWithTruncation(of: transcript, bytes: titleTailBytes) else { return nil }
        var title: String?
        for line in tail.text.split(separator: "\n") where line.contains("-title\"") {
            guard let data = line.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let type = obj["type"] as? String, type == "custom-title" || type == "ai-title" else { continue }
            let value = (obj["customTitle"] ?? obj["aiTitle"] ?? obj["title"]) as? String
            if let value, !value.trimmingCharacters(in: .whitespaces).isEmpty { title = value }
        }
        return title
    }
}
