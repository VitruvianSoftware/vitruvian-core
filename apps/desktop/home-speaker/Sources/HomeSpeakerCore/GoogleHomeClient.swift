// Copyright (c) 2026 VitruvianSoftware

import Foundation

public enum BroadcastError: LocalizedError, Equatable {
    /// Suppressed by quiet hours; `until` is the configured end time ("07:00").
    case quietHours(until: String)
    case noCredentials

    public var errorDescription: String? {
        switch self {
        case .quietHours(let until): return "Quiet hours active until \(until)."
        case .noCredentials: return "No Google Home credentials found."
        }
    }
}

public actor GoogleHomeClient {
    public static let shared = GoogleHomeClient()

    private let mcpEndpoint = URL(string: "https://home.googleapis.com/mcp")!
    private let tokenEndpoint = URL(string: "https://oauth2.googleapis.com/token")!
    private let tokensPath: URL

    public init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        self.tokensPath = home.appendingPathComponent(".gemini/antigravity/mcp_oauth_tokens.json")
    }

    public static func cleanForSpeech(_ text: String) -> String {
        var s = text
        // Remove code blocks and inline code
        s = s.replacingOccurrences(of: "```[\\s\\S]*?```", with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: "`([^`]+)`", with: "$1", options: .regularExpression)
        // Remove URLs
        s = s.replacingOccurrences(of: "https?://\\S+", with: "", options: .regularExpression)
        // Remove markdown links [title](url) -> title
        s = s.replacingOccurrences(of: "\\[([^\\]]+)\\]\\([^)]+\\)", with: "$1", options: .regularExpression)
        // Remove bold, italics, headers
        s = s.replacingOccurrences(of: "\\*\\*([^*]+)\\*\\*", with: "$1", options: .regularExpression)
        s = s.replacingOccurrences(of: "\\*([^*]+)\\*", with: "$1", options: .regularExpression)
        s = s.replacingOccurrences(of: "^\\s*#+\\s*", with: "", options: .regularExpression)
        // Remove bullets
        s = s.replacingOccurrences(of: "^\\s*[-*•]\\s*", with: "", options: .regularExpression)
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
                var spoken = sentences[0]
                if sentences.count > 1 && (spoken.count + sentences[1].count) < 180 {
                    spoken += " " + sentences[1]
                }
                if spoken.count > 200 {
                    spoken = String(spoken.prefix(197)) + "..."
                }
                return spoken
            }
        }
        return s.count > 200 ? String(s.prefix(197)) + "..." : s
    }

    /// True when the broadcast must be dropped: quiet hours are active in
    /// `config` and the caller did not `force` it. Manual Quick Announce
    /// passes `force: true`; automated callers leave it false.
    public static func isSuppressedByQuietHours(config: SpeakerConfig?, force: Bool, at date: Date = Date()) -> Bool {
        guard !force, let config else { return false }
        return config.isInQuietHours(at: date)
    }

    /// Speaks `text` on `target`. Throws `BroadcastError.quietHours` before any
    /// credential or network I/O when suppressed. Pass `config: nil` to skip
    /// the quiet-hours check entirely.
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

        let spoken = Self.cleanForSpeech(text)
        guard !spoken.isEmpty else { return false }

        guard var token = try await getAccessToken() else {
            throw BroadcastError.noCredentials
        }

        var success = try await executeBroadcast(text: spoken, target: target, structureId: structureId, token: token)
        if !success {
            // Try refreshing token and retry once
            if let refreshed = try await refreshToken() {
                token = refreshed
                success = try await executeBroadcast(text: spoken, target: target, structureId: structureId, token: token)
            }
        }
        return success
    }

    private func executeBroadcast(text: String, target: SpeakerDevice, structureId: String, token: String) async throws -> Bool {
        var req = URLRequest(url: mcpEndpoint)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let reqBody: [String: Any] = [
            "jsonrpc": "2.0",
            "id": Int(Date().timeIntervalSince1970),
            "method": "tools/call",
            "params": [
                "name": "run_home_actions",
                "arguments": [
                    "structureId": structureId,
                    "homeActionRequests": [
                        [
                            "id": target.id,
                            "type": target.type,
                            "command": "AssistantBroadcast.Broadcast",
                            "parameters": ["msg": text]
                        ]
                    ]
                ]
            ]
        ]

        req.httpBody = try JSONSerialization.data(withJSONObject: reqBody)
        let (data, response) = try await URLSession.shared.data(for: req)

        guard let http = response as? HTTPURLResponse else { return false }
        if http.statusCode == 401 {
            return false
        }
        if http.statusCode == 200 {
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               json["error"] == nil {
                return true
            }
        }
        return false
    }

    private func getAccessToken() async throws -> String? {
        guard FileManager.default.fileExists(atPath: tokensPath.path) else { return nil }
        let data = try Data(contentsOf: tokensPath)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let homeData = json["https://home.googleapis.com/mcp"] as? [String: Any],
              let tokenInfo = homeData["token"] as? [String: Any],
              let access = tokenInfo["access_token"] as? String else {
            return nil
        }
        return access
    }

    private func refreshToken() async throws -> String? {
        guard FileManager.default.fileExists(atPath: tokensPath.path) else { return nil }
        let data = try Data(contentsOf: tokensPath)
        guard var json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              var homeData = json["https://home.googleapis.com/mcp"] as? [String: Any],
              var tokenInfo = homeData["token"] as? [String: Any],
              let refresh = tokenInfo["refresh_token"] as? String,
              let clientId = homeData["client_id"] as? String,
              let clientSecret = homeData["client_secret"] as? String else {
            return nil
        }

        var req = URLRequest(url: tokenEndpoint)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let bodyParams = [
            "client_id": clientId,
            "client_secret": clientSecret,
            "refresh_token": refresh,
            "grant_type": "refresh_token"
        ]
        let bodyString = bodyParams.map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")" }.joined(separator: "&")
        req.httpBody = bodyString.data(using: .utf8)

        let (respData, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }

        guard let resJson = try JSONSerialization.jsonObject(with: respData) as? [String: Any],
              let newAccessToken = resJson["access_token"] as? String else {
            return nil
        }

        tokenInfo["access_token"] = newAccessToken
        homeData["token"] = tokenInfo
        json["https://home.googleapis.com/mcp"] = homeData

        let updatedData = try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted])
        try updatedData.write(to: tokensPath, options: .atomic)
        return newAccessToken
    }
}
