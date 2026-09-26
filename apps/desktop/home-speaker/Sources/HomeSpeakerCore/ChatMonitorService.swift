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

/// One incoming chat message, normalised across sources.
public struct IncomingMessage: Equatable {
    public enum Source: String { case slack = "Slack", googleChat = "Google Chat" }
    public var source: Source
    public var id: String
    public var timestamp: Date
    public var senderId: String
    public var senderName: String
    public var channel: String
    public var text: String

    public init(source: Source, id: String, timestamp: Date, senderId: String, senderName: String, channel: String, text: String) {
        self.source = source
        self.id = id
        self.timestamp = timestamp
        self.senderId = senderId
        self.senderName = senderName
        self.channel = channel
        self.text = text
    }

    /// "Slack message from alice in general: hi"
    public var spokenLine: String {
        let who = senderName.isEmpty ? "someone" : senderName
        let place = channel.isEmpty ? "" : " in \(channel)"
        return "\(source.rawValue) message from \(who)\(place): \(text)"
    }
}

// MARK: - Slack

public struct SlackClient {
    public static let apiBase = URL(string: "https://slack.com/api/")!
    let token: String
    let session: URLSession

    public init(token: String, session: URLSession = .shared) {
        self.token = token
        self.session = session
    }

    /// Slack's own markup: <@U123> mentions, <#C123|name> channels,
    /// <https://…|label> links.
    public static func cleanMarkup(_ text: String) -> String {
        var s = text
        s = s.replacingOccurrences(of: "<https?://[^|>]+\\|([^>]+)>", with: "$1", options: .regularExpression)
        s = s.replacingOccurrences(of: "<https?://[^>]+>", with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: "<@[A-Z0-9]+>", with: "someone", options: .regularExpression)
        s = s.replacingOccurrences(of: "<#[A-Z0-9]+\\|([^>]+)>", with: "$1", options: .regularExpression)
        s = s.replacingOccurrences(of: "<#[A-Z0-9]+>", with: "a channel", options: .regularExpression)
        s = s.replacingOccurrences(of: "&amp;", with: "&").replacingOccurrences(of: "&lt;", with: "<").replacingOccurrences(of: "&gt;", with: ">")
        return s.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).trimmingCharacters(in: .whitespaces)
    }

    /// Pure: parses a `search.messages` response into messages newer than
    /// `after` (Slack `ts` seconds), oldest first.
    public static func parseSearch(_ json: [String: Any], after: TimeInterval) -> [IncomingMessage] {
        guard (json["ok"] as? Bool) == true,
              let matches = (json["messages"] as? [String: Any])?["matches"] as? [[String: Any]] else { return [] }
        return matches.compactMap { m -> IncomingMessage? in
            guard let tsText = m["ts"] as? String, let ts = TimeInterval(tsText), ts > after else { return nil }
            let channel = (m["channel"] as? [String: Any])?["name"] as? String ?? ""
            return IncomingMessage(
                source: .slack, id: "\(channel)/\(tsText)", timestamp: Date(timeIntervalSince1970: ts),
                senderId: (m["user"] as? String) ?? "", senderName: (m["username"] as? String) ?? "",
                channel: channel, text: cleanMarkup((m["text"] as? String) ?? ""))
        }.sorted { $0.timestamp < $1.timestamp }
    }

    /// Own user id, used to mute messages the user sent themselves.
    public func identity() async throws -> (userId: String, name: String) {
        let json = try await call("auth.test", query: [:])
        guard (json["ok"] as? Bool) == true, let id = json["user_id"] as? String else {
            throw ChatMonitorError.slack((json["error"] as? String) ?? "auth.test failed")
        }
        return (id, (json["user"] as? String) ?? "")
    }

    public func messages(after: TimeInterval) async throws -> [IncomingMessage] {
        // `after:` is date-granular; the ts filter in parseSearch trims the rest.
        let day = DateFormatter()
        day.dateFormat = "yyyy-MM-dd"
        day.timeZone = TimeZone(identifier: "UTC")
        let since = day.string(from: Date(timeIntervalSince1970: after).addingTimeInterval(-86_400))
        let json = try await call("search.messages", query: [
            "query": "after:\(since)", "sort": "timestamp", "sort_dir": "desc", "count": "20",
        ])
        guard (json["ok"] as? Bool) == true else {
            throw ChatMonitorError.slack((json["error"] as? String) ?? "search failed")
        }
        return Self.parseSearch(json, after: after)
    }

    private func call(_ method: String, query: [String: String]) async throws -> [String: Any] {
        var comps = URLComponents(url: Self.apiBase.appendingPathComponent(method), resolvingAgainstBaseURL: false)!
        comps.queryItems = query.isEmpty ? nil : query.map { URLQueryItem(name: $0.key, value: $0.value) }
        var req = URLRequest(url: comps.url!)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, _) = try await session.data(for: req)
        return (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }
}

// MARK: - Google Chat

/// A way of reading Google Chat. Two implementations: the Chat REST API with
/// the app's own login, and the `gws` CLI for users who already have it.
public protocol ChatSource: Sendable {
    func spaces() async throws -> [GoogleChatClient.Space]
    func messages(in space: GoogleChatClient.Space, after: Date) async throws -> [IncomingMessage]
}

public struct GoogleChatClient: ChatSource {
    public static let apiBase = URL(string: "https://chat.googleapis.com/v1/")!
    let auth: GoogleAuth
    let session: URLSession

    public init(auth: GoogleAuth = .shared, session: URLSession = .shared) {
        self.auth = auth
        self.session = session
    }

    public struct Space: Equatable {
        public var name: String       // "spaces/AAAA"
        public var displayName: String
    }

    public static func parseSpaces(_ json: [String: Any]) -> [Space] {
        ((json["spaces"] as? [[String: Any]]) ?? []).compactMap { s in
            guard let name = s["name"] as? String else { return nil }
            let display = (s["displayName"] as? String).flatMap { $0.isEmpty ? nil : $0 }
                ?? ((s["spaceType"] as? String) == "DIRECT_MESSAGE" ? "a direct message" : "a space")
            return Space(name: name, displayName: display)
        }
    }

    /// Pure: parses `spaces.messages.list` into messages newer than `after`.
    public static func parseMessages(_ json: [String: Any], space: Space, after: Date) -> [IncomingMessage] {
        ((json["messages"] as? [[String: Any]]) ?? []).compactMap { m in
            guard let name = m["name"] as? String,
                  let createText = m["createTime"] as? String,
                  let created = ISO8601DateFormatter.fractional.date(from: createText) ?? ISO8601DateFormatter().date(from: createText),
                  created > after else { return nil }
            let sender = (m["sender"] as? [String: Any]) ?? [:]
            let text = (m["text"] as? String) ?? (m["formattedText"] as? String) ?? ""
            return IncomingMessage(
                source: .googleChat, id: name, timestamp: created,
                senderId: (sender["name"] as? String) ?? "", senderName: (sender["displayName"] as? String) ?? "",
                channel: space.displayName,
                text: text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).trimmingCharacters(in: .whitespaces))
        }.sorted { $0.timestamp < $1.timestamp }
    }

    public func spaces() async throws -> [Space] {
        Self.parseSpaces(try await get("spaces", query: ["pageSize": "100"]))
    }

    public func messages(in space: Space, after: Date) async throws -> [IncomingMessage] {
        let stamp = ISO8601DateFormatter.fractional.string(from: after)
        let json = try await get("\(space.name)/messages", query: [
            "filter": "createTime > \"\(stamp)\"", "orderBy": "createTime ASC", "pageSize": "20",
        ])
        return Self.parseMessages(json, space: space, after: after)
    }

    private func get(_ path: String, query: [String: String]) async throws -> [String: Any] {
        var comps = URLComponents(url: Self.apiBase.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        comps.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        var req = URLRequest(url: comps.url!)
        req.setValue("Bearer \(try await auth.validAccessToken(purpose: .chat))", forHTTPHeaderField: "Authorization")
        let (data, response) = try await session.data(for: req)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let json = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
        guard status == 200 else {
            let msg = ((json["error"] as? [String: Any])?["message"] as? String) ?? "HTTP \(status)"
            throw ChatMonitorError.googleChat(msg)
        }
        return json
    }
}

// MARK: - Google Chat via the gws CLI

/// Reads Google Chat through the Google Workspace CLI (`gws`) that the user
/// already has installed and signed in — a fallback that needs no extra
/// permission on the app's own login. Output shapes are the Chat API's, so
/// the same parsers apply.
public struct GwsChatClient: ChatSource {
    public let executable: String
    public let account: String

    /// Where `gws` is looked for. GUI apps get a minimal PATH, so the usual
    /// user and Homebrew locations are checked explicitly.
    public static func locate(environment: [String: String] = ProcessInfo.processInfo.environment) -> String? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        var dirs = ["\(home)/bin", "\(home)/.local/bin", "/opt/homebrew/bin", "/usr/local/bin"]
        dirs += (environment["PATH"] ?? "").split(separator: ":").map(String.init)
        for d in dirs {
            let candidate = "\(d)/gws"
            if FileManager.default.isExecutableFile(atPath: candidate) { return candidate }
        }
        return nil
    }

    public init(executable: String, account: String = "") {
        self.executable = executable
        self.account = account
    }

    /// `--page-all` prints one JSON object per line; each carries a `spaces`
    /// array. Blank or unparseable lines are skipped.
    public static func parseNDJSONSpaces(_ text: String) -> [GoogleChatClient.Space] {
        text.split(separator: "\n").flatMap { line -> [GoogleChatClient.Space] in
            guard let data = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [] }
            return GoogleChatClient.parseSpaces(json)
        }
    }

    public func spaces() async throws -> [GoogleChatClient.Space] {
        let out = try await run(["chat", "spaces", "list", "--page-all", "--page-limit", "5"])
        return Self.parseNDJSONSpaces(out)
    }

    public func messages(in space: GoogleChatClient.Space, after: Date) async throws -> [IncomingMessage] {
        let stamp = ISO8601DateFormatter.fractional.string(from: after)
        let params: [String: Any] = [
            "parent": space.name,
            "filter": "createTime > \"\(stamp)\"",
            "orderBy": "createTime ASC",
            "pageSize": 20,
        ]
        let paramsText = String(decoding: try JSONSerialization.data(withJSONObject: params), as: UTF8.self)
        let out = try await run(["chat", "spaces", "messages", "list", "--params", paramsText])
        guard let data = out.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ChatMonitorError.gws("unexpected output from gws")
        }
        return GoogleChatClient.parseMessages(json, space: space, after: after)
    }

    private func run(_ arguments: [String], timeout: TimeInterval = 30) async throws -> String {
        var args = arguments
        if !account.isEmpty { args += ["--account", account] }
        let exe = executable
        return try await withCheckedThrowingContinuation { cont in
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: exe)
            proc.arguments = args
            let out = Pipe(), err = Pipe()
            proc.standardOutput = out
            proc.standardError = err
            proc.terminationHandler = { p in
                let text = String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                let errText = String(decoding: err.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                if p.terminationStatus == 0 {
                    cont.resume(returning: text)
                } else {
                    let line = errText.split(separator: "\n").last.map(String.init) ?? "exit \(p.terminationStatus)"
                    cont.resume(throwing: ChatMonitorError.gws(line))
                }
            }
            do {
                try proc.run()
                DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                    if proc.isRunning { proc.terminate() }
                }
            } catch {
                cont.resume(throwing: ChatMonitorError.gws(error.localizedDescription))
            }
        }
    }
}

public enum ChatMonitorError: LocalizedError, Equatable {
    case slack(String)
    case googleChat(String)
    case gws(String)
    case slackTokenMissing
    case googleChatScopeMissing
    case gwsNotInstalled
    case noGoogleChatSource

    public var errorDescription: String? {
        switch self {
        case .slack(let m): return "Slack: \(m)"
        case .googleChat(let m): return "Google Chat: \(m)"
        case .gws(let m): return "gws: \(m)"
        case .slackTokenMissing: return "Slack monitoring is on but no Slack token is saved."
        case .googleChatScopeMissing: return "Google Chat via the API needs its own Google permission — grant it under Chat & Slack."
        case .gwsNotInstalled: return "Google Chat via gws needs the gws CLI installed and signed in."
        case .noGoogleChatSource: return "Google Chat is on but no way to read it: grant Chat permission, or install and sign in to the gws CLI."
        }
    }
}

extension ChatMonitorService {
    /// Which reader to use for Google Chat, given the preference and what is
    /// actually available. Pure, so the decision is testable.
    public enum ChatSourceChoice: Equatable { case api, gws, none(ChatMonitorError) }

    nonisolated public static func chooseChatSource(
        preference: ChatMonitorConfig.GoogleChatSource, hasChatScopes: Bool, gwsInstalled: Bool
    ) -> ChatSourceChoice {
        switch preference {
        case .api: return hasChatScopes ? .api : .none(.googleChatScopeMissing)
        case .gws: return gwsInstalled ? .gws : .none(.gwsNotInstalled)
        case .auto:
            if hasChatScopes { return .api }
            if gwsInstalled { return .gws }
            return .none(.noGoogleChatSource)
        }
    }
}

// MARK: - Service

/// Polls Slack and Google Chat from inside the app and announces new
/// messages. Nothing runs until the user switches a source on.
@MainActor
public class ChatMonitorService: ObservableObject {
    public static let shared = ChatMonitorService()

    @Published public var isRunning: Bool = false
    @Published public var lastPollTime: Date?
    @Published public var lastError: String?

    /// Problems found at start() -- a source switched on that cannot run.
    /// Kept apart from per-poll errors because they do not go away on their
    /// own: a clean Google Chat poll says nothing about a Slack token that
    /// was never saved.
    private var setupProblems: [String] = []
    @Published public var slackUser: String?
    /// Which Google Chat reader is active while running ("api" / "gws").
    @Published public var googleChatVia: String?

    private let configManager: ConfigManager
    private let secrets: SecretStore
    private let announcer: Announcer
    private var loop: Task<Void, Never>?

    private var slack: SlackClient?
    private var slackOwnId: String?
    private var slackAfter: TimeInterval = Date().timeIntervalSince1970
    private var chat: (any ChatSource)?
    private var chatOwnId: String?
    private var chatAfter = Date()
    private var seen: Set<String> = []

    public init(
        configManager: ConfigManager? = nil, secrets: SecretStore = .shared,
        home: GoogleHomeClient = .shared, announcer: Announcer? = nil
    ) {
        self.configManager = configManager ?? .shared
        self.secrets = secrets
        self.announcer = announcer ?? Announcer(home: home)
    }

    /// Launch-time entry point: starts only when the user previously opted in.
    public func startIfConfigured() {
        if configManager.config.effectiveChatMonitor.anySourceEnabled { start() }
    }

    public func start() {
        guard !isRunning else { return }
        let cfg = configManager.config.effectiveChatMonitor
        guard cfg.anySourceEnabled else {
            lastError = "Both sources are off. Turn on Slack or Google Chat to start monitoring."
            return
        }
        let s = secrets.load()
        var problems: [String] = []

        slack = nil
        if cfg.slackEnabled {
            if let token = s.slackToken, !token.isEmpty {
                slack = SlackClient(token: token)
            } else {
                problems.append(ChatMonitorError.slackTokenMissing.localizedDescription)
            }
        }
        chat = nil
        googleChatVia = nil
        if cfg.googleChatEnabled {
            let hasScopes = s.hasChatAccess
            let gwsPath = GwsChatClient.locate()
            switch Self.chooseChatSource(preference: cfg.googleChatSource, hasChatScopes: hasScopes, gwsInstalled: gwsPath != nil) {
            case .api:
                chat = GoogleChatClient()
                googleChatVia = "api"
            case .gws:
                chat = GwsChatClient(executable: gwsPath ?? "gws", account: cfg.gwsAccount)
                googleChatVia = "gws"
            case .none(let why):
                problems.append(why.localizedDescription)
            }
            // Own-message muting needs the Google user id, which only an API
            // sign-in provides; via gws alone it stays unknown.
            chatOwnId = (s.googleChat?.userId ?? s.google?.userId).map { "users/\($0)" }
        }
        setupProblems = problems
        lastError = Self.combinedError(setup: problems, poll: [])
        guard slack != nil || chat != nil else { return }

        slackAfter = Date().timeIntervalSince1970
        chatAfter = Date()
        seen.removeAll()
        isRunning = true
        loop = Task { [weak self] in
            await self?.runLoop()
        }
    }

    /// What the UI shows. Setup problems first: they are the ones a person
    /// has to fix, and a poll that succeeded must never clear them. It did,
    /// once -- the "no Slack token" warning lasted one poll interval after
    /// launch and then vanished, so Slack was skipped for days with nothing
    /// on screen saying so.
    nonisolated static func combinedError(setup: [String], poll: [String]) -> String? {
        let all = setup + poll
        return all.isEmpty ? nil : all.joined(separator: " ")
    }

    public func stop() {
        loop?.cancel()
        loop = nil
        isRunning = false
    }

    /// Re-launches the poller so a changed toggle or interval takes effect.
    /// No-op while stopped: the next `start()` reads the config.
    public func restartIfRunning() {
        guard isRunning else { return }
        stop()
        start()
    }

    private func runLoop() async {
        if let slack {
            if let ident = try? await slack.identity() {
                slackOwnId = ident.userId
                slackUser = ident.name
            }
        }
        while !Task.isCancelled {
            await pollOnce()
            let seconds = configManager.config.effectiveChatMonitor.clampedPollInterval
            try? await Task.sleep(for: .seconds(seconds))
        }
    }

    func pollOnce() async {
        let mute = configManager.config.effectiveChatMonitor.muteOwnMessages
        var fresh: [IncomingMessage] = []
        var errors: [String] = []

        if let slack {
            do {
                let msgs = try await slack.messages(after: slackAfter)
                if let newest = msgs.last { slackAfter = newest.timestamp.timeIntervalSince1970 }
                fresh += msgs.filter { !(mute && $0.senderId == slackOwnId) }
            } catch { errors.append(error.localizedDescription) }
        }
        if let chat {
            do {
                var newest = chatAfter
                for space in try await chat.spaces() {
                    let msgs = try await chat.messages(in: space, after: chatAfter)
                    if let last = msgs.last, last.timestamp > newest { newest = last.timestamp }
                    fresh += msgs.filter { !(mute && $0.senderId == chatOwnId) }
                }
                chatAfter = newest
            } catch { errors.append(error.localizedDescription) }
        }

        lastPollTime = Date()
        lastError = Self.combinedError(setup: setupProblems, poll: errors)

        let config = configManager.config
        guard config.enabled else { return }
        // Home only with no speaker picked: wait for one, as before.
        if !config.effectiveSpeakLocal && config.effectiveSpeakHome && config.defaultDevice == nil { return }
        for m in fresh.sorted(by: { $0.timestamp < $1.timestamp }) where !seen.contains(m.id) {
            seen.insert(m.id)
            let line = m.spokenLine
            // One at a time: the Mac finishes one message before the next.
            let outcome = await announcer.announce(line, config: config, force: false)
            if outcome.anySpoke {
                configManager.addLogItem(BroadcastLogItem(
                    text: line, targetName: outcome.spokenLabel(homeName: config.defaultDevice?.name ?? "Home speakers"),
                    source: m.source.rawValue))
            }
            let failures = outcome.failureMessages
            if !failures.isEmpty {
                errors.append(contentsOf: failures)
                lastError = Self.combinedError(setup: setupProblems, poll: errors)
            }
        }
        if seen.count > 500 { seen.removeAll() }
    }
}
