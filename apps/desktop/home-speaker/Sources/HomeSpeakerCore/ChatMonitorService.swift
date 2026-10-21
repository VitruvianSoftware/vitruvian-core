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
    public enum Source: String { case slack = "Slack", googleChat = "Google Chat", beeper = "Beeper" }
    public var source: Source
    public var id: String
    public var timestamp: Date
    public var senderId: String
    public var senderName: String
    public var channel: String
    public var text: String
    /// The network a Beeper message came over ("WhatsApp"); nil otherwise.
    public var network: String?

    public init(source: Source, id: String, timestamp: Date, senderId: String, senderName: String, channel: String, text: String,
                network: String? = nil) {
        self.source = source
        self.id = id
        self.timestamp = timestamp
        self.senderId = senderId
        self.senderName = senderName
        self.channel = channel
        self.text = text
        self.network = network
    }

    /// "Slack message from alice in general: hi"; a Beeper message by its
    /// network: "WhatsApp message from Alice: hi".
    public var spokenLine: String {
        let who = senderName.isEmpty ? "someone" : senderName
        let place = channel.isEmpty ? "" : " in \(channel)"
        let name = network.flatMap { $0.isEmpty ? nil : $0 } ?? source.rawValue
        return "\(name) message from \(who)\(place): \(text)"
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

    /// Own user id, used to mute messages the user sent themselves, and
    /// the workspace the token reads (`team_id`, and its name), which
    /// Beeper's copy of the same workspace is skipped by.
    public func identity() async throws -> (userId: String, name: String, teamId: String?, team: String?) {
        let json = try await call("auth.test", query: [:])
        guard (json["ok"] as? Bool) == true, let id = json["user_id"] as? String else {
            throw ChatMonitorError.slack((json["error"] as? String) ?? "auth.test failed")
        }
        return (id, (json["user"] as? String) ?? "", json["team_id"] as? String, json["team"] as? String)
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
    case beeper(String)
    case beeperTokenMissing
    case beeperNotRunning
    case beeperTokenRefused
    case beeperSlowDown
    case beeperTooMany

    public var errorDescription: String? {
        switch self {
        case .slack(let m): return "Slack: \(m)"
        case .googleChat(let m): return "Google Chat: \(m)"
        case .gws(let m): return "gws: \(m)"
        case .slackTokenMissing: return "Slack monitoring is on but no Slack token is saved."
        case .googleChatScopeMissing: return "Google Chat via the API needs its own Google permission — grant it under Chats."
        case .gwsNotInstalled: return "Google Chat via gws needs the gws CLI installed and signed in."
        case .noGoogleChatSource: return "Google Chat is on but no way to read it: grant Chat permission, or install and sign in to the gws CLI."
        case .beeper(let m): return "Beeper: \(m)"
        case .beeperTokenMissing: return "Beeper monitoring is on but no Beeper token is saved."
        case .beeperNotRunning:
            return "Beeper: Beeper Desktop isn't running, or its Desktop API is off (Beeper Settings › Integrations)."
        case .beeperTokenRefused:
            return "Beeper: the saved token was refused. Create a new one in Beeper Desktop under Settings › Integrations › Approved connections."
        case .beeperSlowDown: return "Beeper: asked to slow down; skipping the next poll."
        case .beeperTooMany:
            return "Beeper: too many messages at once; some may be missed. Mute busy chats in Beeper."
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

    /// What stops a switched-on source from running, Slack first, then
    /// Google Chat, then Beeper: the rules `start()` applies, as a pure
    /// function, so the app and the Vitruvian tool's Settings say the same
    /// thing. Empty when every source that is on can run, and when every
    /// source is off. Beeper Desktop not running is not one: the monitor
    /// starts anyway and reads it once it is.
    nonisolated public static func setupProblems(
        config: ChatMonitorConfig, hasSlackToken: Bool, hasChatScopes: Bool, gwsInstalled: Bool, hasBeeperToken: Bool
    ) -> [ChatMonitorError] {
        var problems: [ChatMonitorError] = []
        if config.slackEnabled, !hasSlackToken { problems.append(.slackTokenMissing) }
        if config.googleChatEnabled,
           case .none(let why) = chooseChatSource(
               preference: config.googleChatSource, hasChatScopes: hasChatScopes, gwsInstalled: gwsInstalled) {
            problems.append(why)
        }
        if config.beeperEnabled, !hasBeeperToken { problems.append(.beeperTokenMissing) }
        return problems
    }

    /// "Reading Beeper: WhatsApp, Signal · Slack skipped (read directly)",
    /// from what the monitor reported; nil before it has read the accounts.
    nonisolated public static func beeperReadingLine(networks: [String]?, skipped: [String]?) -> String? {
        guard let networks else { return nil }
        let reading = networks.isEmpty ? "Reading Beeper: no networks" : "Reading Beeper: " + networks.joined(separator: ", ")
        let skipped = skipped ?? []
        guard !skipped.isEmpty else { return reading }
        return reading + " · " + skipped.joined(separator: ", ") + " skipped (read directly)"
    }
}

// MARK: - Service

/// What `ConfigManager` needs of the chat monitor to follow an edit made
/// outside the app. A protocol so a test can record the calls.
@MainActor
public protocol ChatMonitorControlling: AnyObject {
    var isRunning: Bool { get }
    func start()
    func stop()
}

/// What to do with the chat monitor when its settings change on disk.
public enum ChatMonitorReconciliation: Equatable, Sendable {
    case none, start, stop, restart

    /// Unchanged settings leave the monitor alone, whatever its state: a
    /// monitor stopped by signing out must not come back because the phone
    /// picked another speaker. Otherwise: every source off stops it; a
    /// source on starts it, or restarts it so the new settings take hold.
    ///
    /// Beeper's muted networks are left out of the comparison: each poll
    /// reads them, and a restart would drop what arrived meanwhile.
    public static func decide(old: ChatMonitorConfig, new: ChatMonitorConfig, isRunning: Bool) -> Self {
        var oldRest = old
        var newRest = new
        oldRest.beeperMutedNetworks = []
        newRest.beeperMutedNetworks = []
        guard oldRest != newRest else { return .none }
        guard new.anySourceEnabled else { return isRunning ? .stop : .none }
        return isRunning ? .restart : .start
    }
}

/// Polls Slack, Google Chat and Beeper from inside the app and announces
/// new messages. Nothing runs until the user switches a source on.
@MainActor
public class ChatMonitorService: ObservableObject, ChatMonitorControlling {
    /// The app's monitor, which tells other processes what it is doing
    /// through `~/.gemini/speaker_monitor_status.json`.
    public static let shared = ChatMonitorService(statusFile: ChatMonitorStatusFile(url: ChatMonitorStatusFile.defaultURL()))

    @Published public var isRunning: Bool = false
    @Published public var lastPollTime: Date?
    @Published public var lastError: String?

    /// Problems found at start() -- a source switched on that cannot run.
    /// Kept apart from per-poll errors because they do not go away on their
    /// own: a clean Google Chat poll says nothing about a Slack token that
    /// was never saved.
    private var startProblems: [String] = []
    @Published public var slackUser: String?
    /// Which Google Chat reader is active while running ("api" / "gws").
    @Published public var googleChatVia: String?
    /// The Beeper networks read and the ones left to HomeSpeaker's own
    /// readers ("Slack (acme)"), once Beeper has listed its accounts.
    @Published public var beeperNetworks: [String]?
    @Published public var beeperSkippedNetworks: [String]?
    /// Every Beeper network once, read, skipped or muted, as the status
    /// file carries it; nil while the monitor is not running or Beeper has
    /// not listed its accounts.
    @Published public var beeperNetworkStates: [BeeperNetworkState]?

    private let configManager: ConfigManager
    private let secrets: SecretStore
    private let announcer: Announcer
    /// The Google sign-in Chat is read with, and the session its Chat
    /// requests go through. The engine's own, for an engine that is not the
    /// app's: the monitor reads Chat as whoever that engine is signed in as.
    private let auth: GoogleAuth
    private let chatSession: URLSession
    /// Slack's requests; Beeper's, with its own short timeout; and where
    /// Beeper is (nil: `BeeperClient.baseURL(environment:)`, at start).
    private let slackSession: URLSession
    private let beeperSession: URLSession
    private let beeperBaseURL: URL?
    /// The clock the Beeper window is measured by. A test's own.
    var now: () -> Date = Date.init
    /// False in a test that polls by hand: `start()` sets up the sources
    /// and starts no loop.
    var runsLoop = true
    /// Where the running state is written for other processes; nil writes
    /// nothing, which is what a test's monitor gets unless it asks.
    private let statusFile: ChatMonitorStatusFile?
    /// What went wrong while running, as `ChatMonitorStatus.lastError`
    /// carries it: the last poll's errors and its failed announcements.
    private var runtimeErrors: [String] = []
    private var loop: Task<Void, Never>?

    private var slack: SlackClient?
    private var slackOwnId: String?
    private var slackAfter: TimeInterval = Date().timeIntervalSince1970
    private var chat: (any ChatSource)?
    private var chatOwnId: String?
    private var chatAfter = Date()
    private var seen: Set<String> = []

    private var beeper: BeeperClient?
    /// Beeper's accounts by id; nil until listed.
    private var beeperAccounts: [String: BeeperAccount]?
    /// The accounts as last listed, in Beeper's order, each with the label
    /// it is skipped under ("Slack (acme)"), or nil when it is not left to
    /// HomeSpeaker's own reader. Mutes are applied to it as each status is
    /// written, so one saved between polls shows without a restart.
    private var beeperListing: [(account: BeeperAccount, skipped: String?)]?
    /// When the monitor started: no Beeper message from before is spoken.
    private var beeperStart = Date()
    private var beeperLastPollStart: Date?
    /// Messages already handled, with their time, kept while they are in
    /// the look-back window. Never emptied wholesale: that would speak the
    /// window again.
    private var beeperSeen: [String: Date] = [:]
    private var beeperSkipsNextPoll = false
    /// Unknown account ids that already made the accounts be listed again.
    private var beeperAccountsAskedFor: Set<String> = []
    /// Counts starts and stops: a poll begun under another run writes
    /// nothing of Beeper's, nor who Slack says we are, when it resumes.
    private var beeperRun = 0
    /// The workspace the Slack token reads, from `auth.test`.
    private var slackTeamId: String?
    private var slackTeamName: String?

    public init(
        configManager: ConfigManager? = nil, secrets: SecretStore = .shared,
        home: GoogleHomeClient = .shared, announcer: Announcer? = nil,
        statusFile: ChatMonitorStatusFile? = nil,
        auth: GoogleAuth = .shared, chatSession: URLSession = .shared,
        slackSession: URLSession = .shared, beeperSession: URLSession? = nil, beeperBaseURL: URL? = nil
    ) {
        self.configManager = configManager ?? .shared
        self.secrets = secrets
        self.announcer = announcer ?? Announcer(home: home, geminiKey: { secrets.load().geminiApiKey })
        self.statusFile = statusFile
        self.auth = auth
        self.chatSession = chatSession
        self.slackSession = slackSession
        self.beeperSession = beeperSession ?? BeeperClient.makeSession()
        self.beeperBaseURL = beeperBaseURL
    }

    /// What the status file says right now.
    public var statusSnapshot: ChatMonitorStatus {
        ChatMonitorStatus(
            isRunning: isRunning, lastPollDate: lastPollTime,
            lastError: isRunning ? Self.combinedError(setup: [], poll: runtimeErrors) : nil,
            slackIdentity: slackUser, activeGoogleChatBackend: googleChatVia,
            beeperNetworks: isRunning ? beeperNetworks : nil, beeperSkippedNetworks: isRunning ? beeperSkippedNetworks : nil,
            beeperNetworkStates: isRunning ? beeperNetworkStates : nil)
    }

    /// Writes `statusSnapshot`, if this monitor has a file. A failed write
    /// is not the monitor's failure: the next change writes again.
    private func publishStatus() {
        applyBeeperListing()
        guard let statusFile else { return }
        try? statusFile.write(statusSnapshot)
    }

    /// Launch-time entry point: starts only when the user previously opted in.
    public func startIfConfigured() {
        if configManager.config.effectiveChatMonitor.anySourceEnabled { start() }
    }

    public func start() {
        guard !isRunning else { return }
        let cfg = configManager.config.effectiveChatMonitor
        guard cfg.anySourceEnabled else {
            lastError = "Every source is off. Turn on Slack, Google Chat or Beeper to start monitoring."
            publishStatus()
            return
        }
        let s = secrets.load()
        let slackToken = s.slackToken.flatMap { $0.isEmpty ? nil : $0 }
        let beeperToken = s.beeperToken.flatMap { $0.isEmpty ? nil : $0 }
        let hasScopes = s.hasChatAccess
        // Only looked for with Google Chat on, as before.
        let gwsPath = cfg.googleChatEnabled ? GwsChatClient.locate() : nil
        var problems = Self.setupProblems(
            config: cfg, hasSlackToken: slackToken != nil, hasChatScopes: hasScopes, gwsInstalled: gwsPath != nil,
            hasBeeperToken: beeperToken != nil)

        slack = nil
        if cfg.slackEnabled, let slackToken {
            slack = SlackClient(token: slackToken, session: slackSession)
        }
        // Who Slack said we were is only true of the token it said it for.
        slackUser = nil
        slackOwnId = nil
        slackTeamId = nil
        slackTeamName = nil
        beeper = nil
        beeperAccounts = nil
        beeperListing = nil
        beeperNetworks = nil
        beeperSkippedNetworks = nil
        beeperNetworkStates = nil
        beeperLastPollStart = nil
        beeperSeen = [:]
        beeperSkipsNextPoll = false
        beeperAccountsAskedFor = []
        beeperRun += 1
        if cfg.beeperEnabled, let beeperToken {
            switch beeperBaseURL.map({ Result<URL, ChatMonitorError>.success($0) })
                ?? BeeperClient.baseURL(environment: ProcessInfo.processInfo.environment) {
            case .success(let url):
                beeper = BeeperClient(token: beeperToken, baseURL: url, session: beeperSession)
            case .failure(let why):
                problems.append(why)
            }
        }
        runtimeErrors = []
        chat = nil
        googleChatVia = nil
        if cfg.googleChatEnabled {
            switch Self.chooseChatSource(preference: cfg.googleChatSource, hasChatScopes: hasScopes, gwsInstalled: gwsPath != nil) {
            case .api:
                chat = GoogleChatClient(auth: auth, session: chatSession)
                googleChatVia = "api"
            case .gws:
                chat = GwsChatClient(executable: gwsPath ?? "gws", account: cfg.gwsAccount)
                googleChatVia = "gws"
            case .none:
                break // in `problems` already
            }
            // Own-message muting needs the Google user id, which only an API
            // sign-in provides; via gws alone it stays unknown.
            chatOwnId = (s.googleChat?.userId ?? s.google?.userId).map { "users/\($0)" }
        }
        startProblems = problems.map { $0.localizedDescription }
        lastError = Self.combinedError(setup: startProblems, poll: [])
        guard slack != nil || chat != nil || beeper != nil else {
            publishStatus()
            return
        }

        slackAfter = Date().timeIntervalSince1970
        chatAfter = Date()
        beeperStart = now()
        seen.removeAll()
        isRunning = true
        publishStatus()
        guard runsLoop else { return }
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
        beeperRun += 1
        isRunning = false
        runtimeErrors = []
        beeperNetworkStates = nil
        publishStatus()
    }

    /// Re-launches the poller so a changed toggle or interval takes effect.
    /// No-op while stopped: the next `start()` reads the config.
    public func restartIfRunning() {
        guard isRunning else { return }
        stop()
        start()
    }

    private func runLoop() async {
        while !Task.isCancelled {
            await pollOnce()
            let seconds = configManager.config.effectiveChatMonitor.clampedPollInterval
            try? await Task.sleep(for: .seconds(seconds))
        }
    }

    /// Who the Slack token is, and which workspace it reads. Asked before
    /// each poll until Slack has answered; until then every Slack account
    /// in Beeper is skipped while Slack is on. Once it answers, Beeper's
    /// accounts are listed again so the page says what is skipped.
    func readSlackIdentity() async {
        let run = beeperRun
        guard let slack, let ident = try? await slack.identity(), run == beeperRun else { return }
        slackOwnId = ident.userId
        slackUser = ident.name
        slackTeamId = ident.teamId
        slackTeamName = ident.team
        beeperAccounts = nil
        publishStatus()
    }

    /// One poll of every source, then the new messages spoken. A poll cut
    /// off by `stop()` or a restart (saving a token restarts the monitor)
    /// ends where it is: its run is over, so it records no error -- above
    /// all not the "cancelled" its requests end in -- reads no further
    /// source, speaks nothing and writes nothing over the new run's state.
    func pollOnce() async {
        let run = beeperRun
        /// Still this poll's run, and not cancelled.
        func current() -> Bool { run == beeperRun && !Task.isCancelled }
        /// Whether a caught error should end the poll in silence.
        func ended(by error: Error) -> Bool { !current() || Self.isCancellation(error) }

        if slack != nil, slackOwnId == nil {
            await readSlackIdentity()
            guard current() else { return }
        }
        let monitorConfig = configManager.config.effectiveChatMonitor
        let mute = monitorConfig.muteOwnMessages
        var fresh: [IncomingMessage] = []
        var errors: [String] = []

        if let slack {
            do {
                let msgs = try await slack.messages(after: slackAfter)
                guard current() else { return }
                if let newest = msgs.last { slackAfter = newest.timestamp.timeIntervalSince1970 }
                fresh += msgs.filter { !(mute && $0.senderId == slackOwnId) }
            } catch {
                if ended(by: error) { return }
                errors.append(error.localizedDescription)
            }
        }
        if let chat {
            do {
                var newest = chatAfter
                for space in try await chat.spaces() {
                    guard current() else { return }
                    let msgs = try await chat.messages(in: space, after: chatAfter)
                    guard current() else { return }
                    if let last = msgs.last, last.timestamp > newest { newest = last.timestamp }
                    fresh += msgs.filter { !(mute && $0.senderId == chatOwnId) }
                }
                chatAfter = newest
            } catch {
                if ended(by: error) { return }
                errors.append(error.localizedDescription)
            }
        }
        if let beeper {
            if beeperSkipsNextPoll {
                beeperSkipsNextPoll = false
            } else {
                do {
                    let polled = try await pollBeeper(beeper, config: monitorConfig, run: run)
                    guard current() else { return }
                    fresh += polled.messages
                    if polled.truncated { errors.append(ChatMonitorError.beeperTooMany.localizedDescription) }
                } catch {
                    if ended(by: error) { return }
                    if (error as? ChatMonitorError) == .beeperSlowDown { beeperSkipsNextPoll = true }
                    errors.append(error.localizedDescription)
                }
            }
        }

        guard current() else { return }
        lastPollTime = Date()
        lastError = Self.combinedError(setup: startProblems, poll: errors)
        runtimeErrors = errors

        let config = configManager.config
        // Home only with no speaker picked: wait for one, as before.
        guard config.enabled, config.effectiveSpeakLocal || config.effectiveSpeakPhone || !config.effectiveSpeakHome || config.defaultDevice != nil else {
            publishStatus()
            return
        }
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
            // Stopped or restarted while speaking: the rest is not this
            // run's to speak, nor its failures to record.
            guard current() else { return }
            let failures = outcome.failureMessages
            if !failures.isEmpty {
                errors.append(contentsOf: failures)
                lastError = Self.combinedError(setup: startProblems, poll: errors)
                runtimeErrors = errors
            }
        }
        if seen.count > 500 { seen.removeAll() }
        publishStatus()
    }

    /// A request ended by cancelling it, not by anything going wrong.
    nonisolated static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        if let error = error as? URLError, error.code == .cancelled { return true }
        return false
    }

    // MARK: Beeper

    /// A poll begun under an earlier run of the monitor.
    private struct BeeperRunEnded: Error {}

    private func stillRun(_ run: Int) throws {
        if run != beeperRun { throw BeeperRunEnded() }
    }

    /// One poll of Beeper: every page of messages after the window's start
    /// (up to `BeeperClient.maxPages`), less the ones handled already, the
    /// accounts HomeSpeaker reads itself, and anything not to be spoken.
    /// Each is handled once, spoken or not. `truncated`: the window held
    /// more than the pages read.
    private func pollBeeper(
        _ beeper: BeeperClient, config: ChatMonitorConfig, run: Int
    ) async throws -> (messages: [IncomingMessage], truncated: Bool) {
        let pollStart = now()
        if beeperAccounts == nil { try await readBeeperAccounts(beeper, config: config, run: run) }
        // To the millisecond, as it is sent: the window pruned by is the
        // window asked for.
        let from = max(beeperStart, (beeperLastPollStart ?? beeperStart).addingTimeInterval(-BeeperClient.lookBack))
        let after = Date(timeIntervalSince1970: (from.timeIntervalSince1970 * 1000).rounded(.down) / 1000)
        // What counts against the poll's budget: a message not handled yet
        // that would be spoken, or whose account is not known yet. A copy
        // of what is known now, so Beeper's reading never waits on this.
        let known = beeperAccounts ?? [:]
        let handled = beeperSeen
        let start = beeperStart
        let knownOwnIDs = Set(known.values.compactMap(\.userID))
        let team = slackTeamId
        let user = slackOwnId
        let found = try await beeper.allMessages(after: after, othersOnly: config.muteOwnMessages) { message, chat in
            guard handled[message.key] == nil, message.timestamp > start else { return false }
            guard let account = known[message.accountID] else { return true }
            return !BeeperClient.isSkipped(account, config: config, nativeSlackTeam: team, nativeSlackUser: user)
                && !BeeperClient.isMuted(account, config: config)
                && BeeperClient.shouldAnnounce(message, chat: chat, ownUserIDs: knownOwnIDs, mode: config.beeperAnnounce,
                                               muteOwn: config.muteOwnMessages)
        }
        try stillRun(run)
        beeperLastPollStart = pollStart
        // An account Beeper has added since: list them again, once for
        // each id it did not know. An id never listed is classified by its
        // own shape and, failing that, its chat's network: display-only in
        // Beeper's words, but it errs towards skipping.
        let unknown = Set(found.messages.map(\.accountID)).filter {
            !$0.isEmpty && beeperAccounts?[$0] == nil && !beeperAccountsAskedFor.contains($0)
        }
        if !unknown.isEmpty {
            beeperAccountsAskedFor.formUnion(unknown)
            try? await readBeeperAccounts(beeper, config: config, run: run)
            try stillRun(run)
        }
        // Out of the window now: such a message is never asked for again.
        beeperSeen = beeperSeen.filter { $0.value > after }

        let accounts = beeperAccounts ?? [:]
        let ownIDs = Set(accounts.values.compactMap(\.userID))
        var out: [IncomingMessage] = []
        for message in found.messages where message.timestamp > beeperStart && beeperSeen[message.key] == nil {
            beeperSeen[message.key] = message.timestamp
            let chat = found.chats[message.chatID]
            let account = accounts[message.accountID]
                ?? BeeperAccount(accountID: message.accountID, network: chat?.network ?? "")
            guard !BeeperClient.isSkipped(account, config: config, nativeSlackTeam: slackTeamId, nativeSlackUser: slackOwnId),
                  !BeeperClient.isMuted(account, config: config),
                  BeeperClient.shouldAnnounce(message, chat: chat, ownUserIDs: ownIDs, mode: config.beeperAnnounce,
                                              muteOwn: config.muteOwnMessages),
                  let text = BeeperClient.spokenText(message) else { continue }
            out.append(BeeperClient.incoming(message, chat: chat, account: accounts[message.accountID], text: text))
        }
        return (out, found.truncated)
    }

    /// Lists Beeper's accounts and says which networks are read, which
    /// are left to HomeSpeaker's own Slack or Google Chat reader, and
    /// which are muted.
    private func readBeeperAccounts(_ beeper: BeeperClient, config: ChatMonitorConfig, run: Int) async throws {
        let list = try await beeper.accounts()
        try stillRun(run)
        beeperAccounts = Dictionary(list.map { ($0.accountID, $0) }, uniquingKeysWith: { first, _ in first })
        beeperListing = list.map { account in
            guard BeeperClient.isSkipped(account, config: config, nativeSlackTeam: slackTeamId, nativeSlackUser: slackOwnId) else {
                return (account, nil)
            }
            var label = Self.beeperName(account)
            if case .slack(let team) = BeeperClient.classify(account), let team, team == slackTeamId,
               let teamName = slackTeamName, !teamName.isEmpty {
                label = "\(label) (\(teamName))"
            }
            return (account, label)
        }
        publishStatus()
    }

    /// A Beeper account's network, for people.
    nonisolated private static func beeperName(_ account: BeeperAccount) -> String {
        account.network.isEmpty ? account.accountID : account.network
    }

    /// The networks read, skipped and muted, from the accounts as last
    /// listed and the mutes saved now. Nothing before Beeper has listed
    /// them, or once the monitor has stopped.
    private func applyBeeperListing() {
        guard isRunning, let listing = beeperListing else { return }
        let lists = Self.beeperLists(listing, config: configManager.config.effectiveChatMonitor)
        if beeperNetworks != lists.reading { beeperNetworks = lists.reading }
        if beeperSkippedNetworks != lists.skipped { beeperSkippedNetworks = lists.skipped }
        if beeperNetworkStates != lists.states { beeperNetworkStates = lists.states }
    }

    /// Display names read and skipped, as before (a muted network is not
    /// read), and one state per network key, sorted by name. Two accounts
    /// on one network are one state: read or muted if either is not
    /// skipped, since a mute is by network.
    nonisolated static func beeperLists(
        _ listing: [(account: BeeperAccount, skipped: String?)], config: ChatMonitorConfig
    ) -> (reading: [String], skipped: [String], states: [BeeperNetworkState]) {
        var reading: [String] = []
        var skipped: [String] = []
        var states: [BeeperNetworkState] = []
        for (account, skippedLabel) in listing {
            let name = beeperName(account)
            let key = BeeperClient.networkKey(account)
            let state: BeeperNetworkState.State
            if let skippedLabel {
                if !skipped.contains(skippedLabel) { skipped.append(skippedLabel) }
                state = .skipped
            } else if BeeperClient.isMuted(account, config: config) {
                state = .muted
            } else {
                if !reading.contains(name) { reading.append(name) }
                state = .reading
            }
            if let at = states.firstIndex(where: { $0.key == key }) {
                if states[at].state == .skipped, state != .skipped { states[at].state = state }
            } else {
                states.append(BeeperNetworkState(key: key, name: name, state: state))
            }
        }
        states.sort {
            let order = $0.name.localizedCaseInsensitiveCompare($1.name)
            return order == .orderedSame ? $0.key < $1.key : order == .orderedAscending
        }
        return (reading.sorted(), skipped.sorted(), states)
    }
}
