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

public enum BroadcastError: LocalizedError, Equatable {
    /// Suppressed by quiet hours; `until` is the configured end time ("07:00").
    case quietHours(until: String)
    case noCredentials
    case noSpeaker
    case http(Int)
    case mcp(String)

    public var errorDescription: String? {
        switch self {
        case .quietHours(let until): return "Quiet hours active until \(until)."
        case .noCredentials: return "Not signed in to Google Home."
        case .noSpeaker: return "No speaker selected."
        case .http(let code): return "Google Home returned HTTP \(code)."
        case .mcp(let message): return "Google Home error: \(message)"
        }
    }
}

public struct HomeStructure: Identifiable, Equatable, Hashable {
    public let id: String
    public let name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

/// Talks to Google's hosted Home MCP endpoint over plain HTTPS JSON-RPC.
public actor GoogleHomeClient {
    public static let shared = GoogleHomeClient()

    public static let mcpEndpointString = "https://home.googleapis.com/mcp"
    private let mcpEndpoint = URL(string: GoogleHomeClient.mcpEndpointString)!
    private let auth: GoogleAuth
    private let session: URLSession

    public init(auth: GoogleAuth = .shared, session: URLSession = .shared) {
        self.auth = auth
        self.session = session
    }

    // MARK: Speech

    public static func cleanForSpeech(_ text: String, length: SpeechLength = .headline) -> String {
        var s = text
        // Remove code blocks and inline code
        s = s.replacingOccurrences(of: "```[\\s\\S]*?```", with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: "`([^`]+)`", with: "$1", options: .regularExpression)
        // Remove URLs
        s = s.replacingOccurrences(of: "https?://\\S+", with: "", options: .regularExpression)
        // Remove markdown links [title](url) -> title
        s = s.replacingOccurrences(of: "\\[([^\\]]+)\\]\\([^)]+\\)", with: "$1", options: .regularExpression)
        // Remove bold, italics, strikethrough, headers
        s = s.replacingOccurrences(of: "\\*\\*([^*]+)\\*\\*", with: "$1", options: .regularExpression)
        s = s.replacingOccurrences(of: "\\*([^*]+)\\*", with: "$1", options: .regularExpression)
        s = s.replacingOccurrences(of: "__([^_]+)__", with: "$1", options: .regularExpression)
        s = s.replacingOccurrences(of: "~~([^~]+)~~", with: "$1", options: .regularExpression)
        s = s.replacingOccurrences(of: "(?m)^\\s*#+\\s*", with: "", options: .regularExpression)
        // Remove bullets, numbered lists, blockquotes
        s = s.replacingOccurrences(of: "(?m)^\\s*[-*•>]\\s*", with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: "(?m)^\\s*\\d+\\.\\s+", with: "", options: .regularExpression)
        // Clean up Problem/Fix/Next tags
        s = s.replacingOccurrences(of: "\\b(Problem|Fix|Next):\\s*", with: "$1: ", options: .regularExpression)
        // Collapse whitespace
        s = s.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)

        // Split sentences
        let pattern = "(?<=[.!?])\\s+"
        if let regex = try? NSRegularExpression(pattern: pattern) {
            let range = NSRange(s.startIndex..., in: s)
            let matches = regex.matches(in: s, range: range)
            var sentences: [String] = []
            var lastIdx = s.startIndex
            for match in matches {
                if let r = Range(match.range, in: s) {
                    sentences.append(String(s[lastIdx..<r.lowerBound]))
                    lastIdx = r.upperBound
                }
            }
            if lastIdx < s.endIndex {
                sentences.append(String(s[lastIdx...]))
            }
            sentences = sentences.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }

            if !sentences.isEmpty {
                let cap = length.maxCharacters
                var spoken = sentences[0]
                var used = 1
                for next in sentences.dropFirst() {
                    if let limit = length.maxSentences, used >= limit { break }
                    guard spoken.count + 1 + next.count <= cap else { break }
                    spoken += " " + next
                    used += 1
                }
                return truncate(spoken, to: cap)
            }
        }
        return truncate(s, to: length.maxCharacters)
    }

    /// Cuts at a word boundary so the speaker never reads half a word.
    private static func truncate(_ s: String, to cap: Int) -> String {
        guard s.count > cap else { return s }
        let head = String(s.prefix(cap - 3))
        if let space = head.lastIndex(of: " "), head.distance(from: head.startIndex, to: space) > cap / 2 {
            return String(head[..<space]) + "..."
        }
        return head + "..."
    }

    /// True when the broadcast must be dropped: quiet hours are active in
    /// `config` and the caller did not `force` it. Manual Quick Announce
    /// passes `force: true`; automated callers leave it false.
    public static func isSuppressedByQuietHours(config: SpeakerConfig?, force: Bool, at date: Date = Date()) -> Bool {
        guard !force, let config else { return false }
        return config.isInQuietHours(at: date)
    }

    // MARK: Broadcast

    /// Speaks `text` on `target`. Throws `BroadcastError.quietHours` before any
    /// credential or network I/O when suppressed. Pass `config: nil` to skip
    /// the quiet-hours check entirely. Returns false only when the text
    /// cleans down to nothing.
    public func broadcast(
        text: String,
        target: SpeakerDevice,
        structureId: String,
        config: SpeakerConfig? = nil,
        force: Bool = false,
        at date: Date = Date()
    ) async throws -> Bool {
        if Self.isSuppressedByQuietHours(config: config, force: force, at: date) {
            throw BroadcastError.quietHours(until: config?.quietHoursEnd ?? "")
        }
        let spoken = Self.cleanForSpeech(text, length: config?.effectiveSpeechLength ?? .summary)
        guard !spoken.isEmpty else { return false }
        guard !structureId.isEmpty else { throw BroadcastError.noSpeaker }

        let arguments: [String: Any] = [
            "structureId": structureId,
            "homeActionRequests": [[
                "id": target.id,
                "type": target.type,
                "command": "AssistantBroadcast.Broadcast",
                "parameters": ["msg": spoken],
            ]],
        ]
        _ = try await callTool("run_home_actions", arguments: arguments)
        return true
    }

    // MARK: Discovery

    public func listHomes() async throws -> [HomeStructure] {
        let payload = try await callTool("list_homes", arguments: [:])
        return Self.parseStructures(payload)
    }

    /// Every resource in `structureId` that can be broadcast to, keyed by a
    /// config alias ("kitchen_home"). Rooms are resolved to names.
    public func discoverBroadcastTargets(structureId: String) async throws -> [String: SpeakerDevice] {
        var resources: [[String: Any]] = []
        var pageToken: String?
        repeat {
            var args: [String: Any] = ["structureId": structureId, "view": "VIEW_SUMMARY", "pageSize": 200]
            if let pageToken { args["pageToken"] = pageToken }
            let payload = try await callTool("list_home_resources", arguments: args)
            resources += (payload["resources"] as? [[String: Any]]) ?? []
            pageToken = payload["nextPageToken"] as? String
        } while pageToken != nil && resources.count < 2000
        return Self.parseBroadcastTargets(resources: resources)
    }

    public static func parseStructures(_ payload: [String: Any]) -> [HomeStructure] {
        ((payload["structures"] as? [[String: Any]]) ?? []).compactMap { s in
            guard let id = s["structureId"] as? String, !id.isEmpty else { return nil }
            return HomeStructure(id: id, name: (s["displayName"] as? String) ?? "Home")
        }
    }

    /// Pure: turns a `list_home_resources` result into broadcast targets.
    /// A resource qualifies when it advertises the `AssistantBroadcast`
    /// trait (possibly component-prefixed, "SpeakerDevice/AssistantBroadcast").
    /// The structure itself qualifies too and becomes the "all" target.
    public static func parseBroadcastTargets(resources: [[String: Any]]) -> [String: SpeakerDevice] {
        var roomNames: [String: String] = [:]
        for r in resources where (r["type"] as? String) == "Room" {
            if let id = r["id"] as? String, let name = r["displayName"] as? String { roomNames[id] = name }
        }

        var targets: [String: SpeakerDevice] = [:]
        for r in resources {
            guard let id = r["id"] as? String,
                  let type = r["type"] as? String,
                  let traits = r["supportedTraits"] as? [String],
                  traits.contains(where: { $0 == "AssistantBroadcast" || $0.hasSuffix("/AssistantBroadcast") })
            else { continue }
            let name = (r["displayName"] as? String) ?? type
            if type == "Structure" {
                targets["all"] = SpeakerDevice(id: id, type: type, name: "Whole Home (All Speakers)", room: "All")
                continue
            }
            let parents = (r["parentIds"] as? [String]) ?? []
            let room = parents.compactMap { roomNames[$0] }.first
            var alias = SpeakerDevice.alias(for: name)
            var n = 2
            while targets[alias] != nil && targets[alias]?.id != id {
                alias = "\(SpeakerDevice.alias(for: name))_\(n)"
                n += 1
            }
            targets[alias] = SpeakerDevice(id: id, type: type, name: name, room: room)
        }
        return targets
    }

    // MARK: JSON-RPC

    /// Unwraps an MCP `tools/call` response into the tool's own payload.
    /// Servers return either `result.structuredContent` or a single text
    /// content block holding JSON; both are handled. A top-level or in-result
    /// error becomes `BroadcastError.mcp`.
    public static func extractToolPayload(_ envelope: [String: Any]) throws -> [String: Any] {
        if let err = envelope["error"] as? [String: Any] {
            throw BroadcastError.mcp((err["message"] as? String) ?? "unknown error")
        }
        guard let result = envelope["result"] as? [String: Any] else { return [:] }
        if let structured = result["structuredContent"] as? [String: Any] { return structured }
        let contents = (result["content"] as? [[String: Any]]) ?? []
        let text = contents.compactMap { $0["text"] as? String }.joined()
        if (result["isError"] as? Bool) == true {
            throw BroadcastError.mcp(text.isEmpty ? "tool reported an error" : text)
        }
        if let data = text.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            return json
        }
        return result
    }

    private func callTool(_ name: String, arguments: [String: Any]) async throws -> [String: Any] {
        let token: String
        do {
            token = try await auth.validAccessToken()
        } catch GoogleAuthError.notSignedIn {
            throw BroadcastError.noCredentials
        }
        let (status, envelope) = try await post(name: name, arguments: arguments, token: token)
        if status == 401 {
            let fresh = try await auth.validAccessToken(forceRefresh: true)
            let (retryStatus, retryEnvelope) = try await post(name: name, arguments: arguments, token: fresh)
            guard retryStatus == 200 else { throw BroadcastError.http(retryStatus) }
            return try Self.extractToolPayload(retryEnvelope)
        }
        guard status == 200 else { throw BroadcastError.http(status) }
        return try Self.extractToolPayload(envelope)
    }

    private func post(name: String, arguments: [String: Any], token: String) async throws -> (Int, [String: Any]) {
        var req = URLRequest(url: mcpEndpoint)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "jsonrpc": "2.0",
            "id": Int(Date().timeIntervalSince1970 * 1000),
            "method": "tools/call",
            "params": ["name": name, "arguments": arguments],
        ] as [String: Any])
        let (data, response) = try await session.data(for: req)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let envelope = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
        return (status, envelope)
    }
}
