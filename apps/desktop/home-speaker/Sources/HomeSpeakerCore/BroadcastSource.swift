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

/// Who asked `HomeSpeaker --say` to speak: a person, or a coding agent.
/// An agent's announcement is spoken only while that agent's switch is on
/// (`SpeakerConfig.announces`), under the master switch.
///
/// The `speaker-broadcast` command both agents are told to run (the
/// `home-speaker-broadcast` instruction line) calls `--say` with no way to
/// say who it is for. So the source is, in order:
/// 1. `--source <name>` before `--say`, when the caller says;
/// 2. otherwise the agent whose shell the command runs in, from the
///    variables each agent sets for the commands it runs: Claude Code sets
///    `CLAUDECODE=1`, Antigravity sets `ANTIGRAVITY_AGENT=1`, OpenCode sets
///    `OPENCODE=1`, and each sets `AI_AGENT` to its own name (OpenCode uses
///    `AI_AGENT ||= "opencode"`, so it does not overwrite an outer agent's
///    `AI_AGENT`). They are inherited, so an agent started by another
///    carries both; `AI_AGENT` tells them apart when overwritten;
/// 3. otherwise a person (`user`).
public enum BroadcastSource: String, CaseIterable, Equatable, Sendable {
    case user
    case claudeCode = "claude-code"
    case antigravity
    case opencode

    /// `--source <name>`: given before `--say`, whose text is the rest of
    /// the line.
    public static let flag = "--source"

    /// The agent whose switch holds this source; nil for a person.
    public var agent: CodingAgent? {
        switch self {
        case .user: return nil
        case .claudeCode: return .claudeCode
        case .antigravity: return .antigravity
        case .opencode: return .opencode
        }
    }

    /// The source an agent's own hook speaks as.
    public static func from(_ agent: CodingAgent) -> BroadcastSource {
        switch agent {
        case .claudeCode: return .claudeCode
        case .antigravity: return .antigravity
        case .opencode: return .opencode
        }
    }

    /// What Recent Broadcasts names it by.
    public var historyLabel: String {
        agent?.displayName ?? "Say"
    }

    /// The name given to `--source`, in any case: `claude-code` (or
    /// `claude`, `claudecode`), `antigravity` (or `agy`), `opencode` (or
    /// `open-code`, `open_code`), `user`.
    public init?(name: String) {
        switch name.lowercased().trimmingCharacters(in: .whitespaces) {
        case "user", "say", "person": self = .user
        case "claude-code", "claude", "claudecode", "claude_code": self = .claudeCode
        case "antigravity", "agy": self = .antigravity
        case "opencode", "open-code", "open_code": self = .opencode
        default: return nil
        }
    }

    /// The agent whose shell `environment` is, or a person when none.
    public static func inferred(from environment: [String: String]) -> BroadcastSource {
        let present = [
            (BroadcastSource.claudeCode, "CLAUDECODE"),
            (.antigravity, "ANTIGRAVITY_AGENT"),
            (.opencode, "OPENCODE"),
        ].filter { environment[$0.1] == "1" }.map(\.0)
        switch present.count {
        case 0: return .user
        case 1: return present[0]
        default:
            // Multiple inherited: pick the flagged agent named by `AI_AGENT`
            // when it matches one of `present`, else the first in priority order.
            return aiAgentMatch(environment["AI_AGENT", default: ""], among: present) ?? present[0]
        }
    }

    private static func aiAgentMatch(_ raw: String, among present: [BroadcastSource]) -> BroadcastSource? {
        let name = raw.lowercased()
        let matched: BroadcastSource?
        if name.hasPrefix("claude") {
            matched = .claudeCode
        } else if name.contains("antigravity") || name.hasPrefix("agy") || name.contains("gemini") {
            matched = .antigravity
        } else if name.contains("opencode") || name.contains("open-code") || name.contains("open_code") {
            matched = .opencode
        } else {
            matched = nil
        }
        return matched.flatMap { present.contains($0) ? $0 : nil }
    }

    /// The source of a `--say` line: `--source` before `--say` when given,
    /// else what `environment` says. A `--source` with no name, or one this
    /// version does not know, is the caller's mistake.
    public static func resolve(
        arguments: [String], environment: [String: String]
    ) -> Result<BroadcastSource, UsageError> {
        let end = arguments.firstIndex(of: "--say") ?? arguments.endIndex
        let head = arguments[..<end]
        guard let i = head.firstIndex(of: flag) else { return .success(inferred(from: environment)) }
        let next = head.index(after: i)
        guard next < head.endIndex else {
            return .failure(.init("\(flag) needs a name: \(names)"))
        }
        guard let source = BroadcastSource(name: head[next]) else {
            return .failure(.init("unknown \(flag) \(head[next]): use \(names)"))
        }
        return .success(source)
    }

    static var names: String { allCases.map(\.rawValue).joined(separator: ", ") }
}
