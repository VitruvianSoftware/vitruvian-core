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
import Testing
@testable import HomeSpeakerCore

// Beeper as a chat source. Nothing here reaches the network, and above all
// never the real Beeper Desktop on this Mac (port 23373): every request goes
// to a stand-in session answering in this process, the base URL each monitor
// is given is a made-up loopback port, and the stand-in fails any request to
// 23373, to anywhere but this Mac, or with any method but GET. Each test
// uses a made-up token of its own, which the stand-in keys its answers on,
// so the tests can run side by side. Every fixture is hand-written fake data.

// MARK: - Fixtures (fake)

/// When every fixture's monitor starts.
private let start = Date(timeIntervalSince1970: 1_800_000_000)

private func stamp(_ secondsAfterStart: TimeInterval) -> String {
    ISO8601DateFormatter.fractional.string(from: start.addingTimeInterval(secondsAfterStart))
}

/// A base URL on this Mac that nothing listens on, and is not Beeper's.
private let standInBase = URL(string: "http://localhost:47999")!

private let accountsBody = """
[
  {"accountID": "local-whatsapp_ba_FAKE", "bridge": {"id": "local-whatsapp", "type": "whatsapp", "provider": "local"},
   "network": "WhatsApp", "user": {"id": "@me-wa:fake.test", "isSelf": true, "fullName": "Me"}},
  {"accountID": "local-signal_FAKE", "network": "Signal", "user": {"id": "@me-signal:fake.test", "isSelf": true}},
  {"accountID": "slackgo.TNATIVE-UME1", "network": "Slack", "user": {"id": "@me-slack1:fake.test"}},
  {"accountID": "slackgo.TOTHER-UME2", "network": "Slack", "user": {"id": "@me-slack2:fake.test"}},
  {"accountID": "gmessages.someone@example.test/0", "bridge": {"type": "gmessages"}, "network": "Google Messages",
   "user": {"id": "@me-sms:fake.test"}},
  {"accountID": "googlechat.FAKE", "bridge": {"type": "googlechat"}, "network": "Google Chat", "user": {"id": "@me-gc:fake.test"}}
]
"""

private func message(_ id: String, chat: String, account: String, from: String = "", at: TimeInterval,
                     type: String = "TEXT", text: String = "", isSender: Bool = false, mentions: [String]? = nil) -> String {
    let mentionsJSON = mentions.map { "[" + $0.map { "\"\($0)\"" }.joined(separator: ",") + "]" } ?? "null"
    return """
    {"id": "\(id)", "chatID": "\(chat)", "accountID": "\(account)", "senderID": "@\(from.lowercased()):fake.test",
     "senderName": "\(from)", "timestamp": "\(stamp(at))", "sortKey": "\(Int(at))", "type": "\(type)", "text": "\(text)",
     "isSender": \(isSender), "isHidden": false, "isDeleted": false, "mentions": \(mentionsJSON)}
    """
}

private let chatsBody = """
{
  "wa-dm": {"id": "wa-dm", "type": "single", "title": "Alice", "network": "WhatsApp", "isMuted": false, "isLowPriority": false},
  "sig-family": {"id": "sig-family", "type": "group", "title": "Family", "network": "Signal", "isMuted": false},
  "slack-native-dm": {"id": "slack-native-dm", "type": "single", "title": "Dee", "network": "Slack"},
  "slack-other-dm": {"id": "slack-other-dm", "type": "single", "title": "Dan", "network": "Slack"},
  "sms-dm": {"id": "sms-dm", "type": "single", "title": "Eve", "network": "Google Messages"},
  "muted-dm": {"id": "muted-dm", "type": "single", "title": "Carol", "network": "WhatsApp", "isMuted": true},
  "gc-dm": {"id": "gc-dm", "type": "single", "title": "Gus", "network": "Google Chat"}
}
"""

/// One of each case the design lists.
private let everyCase = [
    message("m-wa", chat: "wa-dm", account: "local-whatsapp_ba_FAKE", from: "Alice", at: 10, text: "Dinner at seven"),
    message("m-sig-mention", chat: "sig-family", account: "local-signal_FAKE", from: "Bob", at: 11,
            text: "can you call grandma", mentions: ["@me-signal:fake.test"]),
    message("m-sig-plain", chat: "sig-family", account: "local-signal_FAKE", from: "Bob", at: 12, text: "lol"),
    message("m-slack-native", chat: "slack-native-dm", account: "slackgo.TNATIVE-UME1", from: "Dee", at: 13,
            text: "native workspace"),
    message("m-slack-other", chat: "slack-other-dm", account: "slackgo.TOTHER-UME2", from: "Dan", at: 14,
            text: "other workspace"),
    message("m-sms", chat: "sms-dm", account: "gmessages.someone@example.test/0", from: "Eve", at: 15, text: "Running late"),
    message("m-own", chat: "wa-dm", account: "local-whatsapp_ba_FAKE", from: "Me", at: 16, text: "on my way", isSender: true),
    message("m-reaction", chat: "wa-dm", account: "local-whatsapp_ba_FAKE", from: "Alice", at: 17, type: "REACTION", text: "👍"),
    message("m-photo", chat: "wa-dm", account: "local-whatsapp_ba_FAKE", from: "Alice", at: 18, type: "IMAGE"),
    message("m-muted", chat: "muted-dm", account: "local-whatsapp_ba_FAKE", from: "Carol", at: 19, text: "muted hello"),
    message("m-gc", chat: "gc-dm", account: "googlechat.FAKE", from: "Gus", at: 20, text: "google chat dm"),
    message("m-old", chat: "wa-dm", account: "local-whatsapp_ba_FAKE", from: "Alice", at: -60, text: "old news"),
]

private func searchBody(_ items: [String]) -> String {
    #"{"items": ["# + items.joined(separator: ",") + #"], "hasMore": false, "chats": "# + chatsBody + "}"
}

// MARK: - The stand-ins

/// Beeper Desktop, answering in this process, by token.
private final class StandInBeeper: URLProtocol {
    struct Request: Equatable {
        let method: String
        let host: String
        let port: Int?
        let path: String
        let query: [String: String]
        let bearer: String?
    }

    enum Answer {
        case body(String)
        case status(Int, String)
        case refused
    }

    /// What one test's Beeper says. Each search takes the next answer; the
    /// last one repeats.
    final class Scenario: @unchecked Sendable {
        private let lock = NSLock()
        private var accountsAnswers: [Answer]
        private var searchAnswers: [Answer]
        private var seen: [Request] = []

        init(accounts: [Answer] = [.body(accountsBody)], searches: [Answer]) {
            accountsAnswers = accounts
            searchAnswers = searches
        }

        var requests: [Request] { lock.withLock { seen } }
        var searches: [Request] { requests.filter { $0.path == "/v1/messages/search" } }

        func setSearches(_ answers: [Answer]) { lock.withLock { searchAnswers = answers } }

        func answer(_ request: Request) -> Answer {
            lock.withLock {
                seen.append(request)
                func next(_ list: inout [Answer]) -> Answer {
                    guard let first = list.first else { return .status(500, "{}") }
                    if list.count > 1 { list.removeFirst() }
                    return first
                }
                switch request.path {
                case "/v1/accounts": return next(&accountsAnswers)
                case "/v1/messages/search": return next(&searchAnswers)
                default: return .status(404, #"{"message":"not found"}"#)
                }
            }
        }
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var scenarios: [String: Scenario] = [:]
    /// Requests no scenario owned, or that broke a rule: any is a failure.
    nonisolated(unsafe) private static var strays: [Request] = []

    static func register(_ scenario: Scenario, token: String) {
        lock.withLock { scenarios[token] = scenario }
    }

    static var badRequests: [Request] { lock.withLock { strays } }

    static var session: URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StandInBeeper.self]
        return URLSession(configuration: configuration)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        let url = request.url!
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let bearer = request.value(forHTTPHeaderField: "Authorization").flatMap {
            $0.hasPrefix("Bearer ") ? String($0.dropFirst("Bearer ".count)) : nil
        }
        let seen = Request(
            method: request.httpMethod ?? "GET", host: url.host ?? "", port: url.port, path: url.path,
            query: Dictionary(items.map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { _, last in last }),
            bearer: bearer)
        let scenario = Self.lock.withLock { bearer.flatMap { Self.scenarios[$0] } }
        // Beeper is only ever asked with GET, on this Mac, never on its
        // real port; anything else is recorded as a failure and refused.
        let rulesKept = seen.method == "GET" && BeeperClient.isLoopback(url) && url.port != 23373
        guard rulesKept, let scenario else {
            Self.lock.withLock { Self.strays.append(seen) }
            finish(status: 418, body: "{}")
            return
        }
        switch scenario.answer(seen) {
        case .body(let body): finish(status: 200, body: body)
        case .status(let code, let body): finish(status: code, body: body)
        case .refused: client?.urlProtocol(self, didFailWithError: URLError(.cannotConnectToHost))
        }
    }

    private func finish(status: Int, body: String) {
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1",
                                       headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
}

/// Slack, for `auth.test` (the workspace the token reads) and an empty search.
private final class StandInSlack: URLProtocol {
    static var session: URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StandInSlack.self]
        return URLSession(configuration: configuration)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        let url = request.url!
        let body: String
        switch url.path {
        case "/api/auth.test": body = #"{"ok":true,"user_id":"UME1","user":"me","team_id":"TNATIVE","team":"acme"}"#
        case "/api/search.messages": body = #"{"ok":true,"messages":{"matches":[]}}"#
        default: body = #"{"ok":false,"error":"unknown_method"}"#
        }
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1",
                                       headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
}

/// This Mac's speech, made silent, remembering what it was asked to say.
private final class RecordingLocal: LocalSpeaking, @unchecked Sendable {
    private let lock = NSLock()
    private var said: [String] = []
    var spoken: [String] { lock.withLock { said } }
    func speak(_ text: String, voiceID: String) async throws { lock.withLock { said.append(text) } }
}

// MARK: - A monitor on a scratch engine

@MainActor
private struct Rig {
    let root: URL
    let engine: HomeSpeakerEngine
    let monitor: ChatMonitorService
    let beeper: StandInBeeper.Scenario
    let token: String
    /// Everything said on "this Mac", in order.
    let local = RecordingLocal()

    /// A monitor on an engine in a scratch folder, speaking (silently) on
    /// "this Mac", reading Beeper through the stand-in with `token`.
    init(monitorConfig: ChatMonitorConfig, beeperToken: String?, slackToken: String? = nil,
         beeper: StandInBeeper.Scenario) throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("homespeaker-beeper-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let profile = HomeSpeakerProfile.extension(
            dataFolder: root.appendingPathComponent("data"), toolFolder: nil,
            messagePrefix: "test.\(UUID().uuidString).homespeaker")
        for url in [profile.settingsURL, profile.historyURL, profile.secretsURL, profile.monitorStatusURL] {
            try #require(url.path.hasPrefix(root.path + "/"), "\(url.path) is outside the scratch folder")
        }
        // Never the real Beeper: the address the monitor is given is not its port.
        try #require(standInBase.port != 23373 && BeeperClient.isLoopback(standInBase))
        engine = HomeSpeakerEngine(profile: profile, session: StandInSlack.session, local: local)
        var config = SpeakerConfig(enabled: true, quietHoursEnabled: false, chatMonitor: monitorConfig)
        config.speakHome = false
        config.speakLocal = true
        engine.config.config = config
        try engine.secrets.save(Secrets(slackToken: slackToken, beeperToken: beeperToken))
        token = beeperToken ?? ""
        if let beeperToken { StandInBeeper.register(beeper, token: beeperToken) }
        self.beeper = beeper
        monitor = ChatMonitorService(
            configManager: engine.config, secrets: engine.secrets, home: engine.home, announcer: engine.announcer,
            statusFile: ChatMonitorStatusFile(url: profile.monitorStatusURL), auth: engine.auth,
            chatSession: StandInSlack.session, slackSession: StandInSlack.session,
            beeperSession: StandInBeeper.session, beeperBaseURL: standInBase)
        monitor.runsLoop = false
        monitor.now = { [start] in start }
    }

    mutating func startMonitor() async {
        monitor.start()
        await monitor.readSlackIdentity()
    }

    /// One poll, `seconds` after the monitor started.
    mutating func poll(at seconds: TimeInterval) async {
        let when = start.addingTimeInterval(seconds)
        monitor.now = { when }
        await monitor.pollOnce()
    }

    /// What was spoken, as the history keeps it, oldest first.
    var spoken: [String] { engine.history.load().reversed().filter { $0.source == "Beeper" }.map(\.text) }

    func finish() {
        monitor.stop()
        try? FileManager.default.removeItem(at: root)
    }

    /// Every request carried this test's token, went to the stand-in's
    /// address, and was a GET; nothing broke a rule.
    func expectOnlyGoodGETs(sourceLocation: SourceLocation = #_sourceLocation) {
        #expect(beeper.requests.allSatisfy {
            $0.method == "GET" && $0.bearer == token && $0.port == standInBase.port && $0.host == "localhost"
        }, "\(beeper.requests)", sourceLocation: sourceLocation)
        #expect(StandInBeeper.badRequests.filter { $0.bearer == token }.isEmpty,
                "requests that broke a rule: \(StandInBeeper.badRequests)", sourceLocation: sourceLocation)
    }
}

/// A made-up token, unique to the test. // gitleaks:allow (made-up test token)
private func fakeToken() -> String { "fake-beeper-test-token-\(UUID().uuidString)" } // gitleaks:allow (made-up test token)

// MARK: - Pure rules

@Suite struct BeeperRulesTests {
    @Test func classifyGoesByBridgeThenAccountIdThenNetwork() {
        let cases: [(BeeperAccount, BeeperClient.Kind)] = [
            (BeeperAccount(accountID: "slackgo.T01-U02", network: "Slack"), .slack(team: "T01")),
            (BeeperAccount(accountID: "x", bridgeType: "slackgo", network: ""), .slack(team: nil)),
            (BeeperAccount(accountID: "slackgo.T01-U02", bridgeType: "slackgo", network: "Slack"), .slack(team: "T01")),
            (BeeperAccount(accountID: "local-slack_abc", network: ""), .slack(team: nil)),
            (BeeperAccount(accountID: "abc", network: "Slack"), .slack(team: nil)),
            (BeeperAccount(accountID: "googlechat.abc", network: ""), .googleChat),
            (BeeperAccount(accountID: "abc", bridgeType: "googlechat", network: ""), .googleChat),
            (BeeperAccount(accountID: "abc", network: "Google Chat"), .googleChat),
            // Google Messages is texts and RCS, never Google Chat.
            (BeeperAccount(accountID: "gmessages.me@example.test/0", bridgeType: "gmessages", network: "Google Messages"), .other),
            (BeeperAccount(accountID: "gmessages.me@example.test/0", network: "Google Messages"), .other),
            (BeeperAccount(accountID: "local-whatsapp_ba_x", bridgeType: "whatsapp", network: "WhatsApp"), .other),
            (BeeperAccount(accountID: "local-signal_x", network: "Signal"), .other),
            (BeeperAccount(accountID: "matrix", network: "Beeper"), .other),
        ]
        for (account, kind) in cases {
            #expect(BeeperClient.classify(account) == kind, "\(account)")
        }
    }

    @Test func slackTeamComesFromASlackgoAccountIdOnly() {
        #expect(BeeperClient.slackTeam(accountID: "slackgo.T0ABC-U0DEF") == "T0ABC")
        #expect(BeeperClient.slackTeam(accountID: "slackgo.-U0DEF") == nil)
        #expect(BeeperClient.slackTeam(accountID: "slackgo.T0ABC") == nil)
        #expect(BeeperClient.slackTeam(accountID: "gmessages.a-b") == nil)
        #expect(BeeperClient.slackTeam(accountID: "local-slack_T0-U0") == nil)
    }

    /// James's rule: nothing spoken twice. Slack by workspace; a workspace
    /// not known is skipped; Google Chat while its switch is on.
    @Test func theDuplicatesRule() {
        let native = BeeperAccount(accountID: "slackgo.TNATIVE-U1", network: "Slack")
        let other = BeeperAccount(accountID: "slackgo.TOTHER-U2", network: "Slack")
        let noTeam = BeeperAccount(accountID: "local-slack_x", network: "Slack")
        let chat = BeeperAccount(accountID: "googlechat.x", network: "Google Chat")
        let sms = BeeperAccount(accountID: "gmessages.x/0", network: "Google Messages")
        let whatsapp = BeeperAccount(accountID: "local-whatsapp_x", network: "WhatsApp")
        func skipped(_ a: BeeperAccount, slack: Bool, chatOn: Bool, team: String?) -> Bool {
            BeeperClient.isSkipped(a, config: ChatMonitorConfig(slackEnabled: slack, googleChatEnabled: chatOn), nativeSlackTeam: team)
        }
        // Slack on, workspace known: only that workspace.
        #expect(skipped(native, slack: true, chatOn: false, team: "TNATIVE"))
        #expect(!skipped(other, slack: true, chatOn: false, team: "TNATIVE"))
        #expect(skipped(noTeam, slack: true, chatOn: false, team: "TNATIVE"))
        // Slack on, workspace unknown: every Slack account.
        #expect(skipped(native, slack: true, chatOn: false, team: nil))
        #expect(skipped(other, slack: true, chatOn: false, team: nil))
        // Slack off: none.
        #expect(!skipped(native, slack: false, chatOn: false, team: "TNATIVE"))
        #expect(!skipped(other, slack: false, chatOn: false, team: nil))
        // Google Chat by its switch; Google Messages never.
        #expect(skipped(chat, slack: false, chatOn: true, team: nil))
        #expect(!skipped(chat, slack: true, chatOn: false, team: nil))
        #expect(!skipped(sms, slack: true, chatOn: true, team: nil))
        #expect(!skipped(whatsapp, slack: true, chatOn: true, team: nil))
    }

    @Test func whatIsAnnouncedInEachMode() {
        let me: Set<String> = ["@me:fake.test"]
        let dm = BeeperChat(id: "d", isDirect: true)
        let group = BeeperChat(id: "g", isDirect: false, title: "Family")
        func m(type: String = "TEXT", isSender: Bool = false, mentions: [String] = [], hidden: Bool = false, deleted: Bool = false,
               sender: String = "@alice:fake.test") -> BeeperMessage {
            BeeperMessage(id: "1", chatID: "c", accountID: "a", senderID: sender, timestamp: start, type: type, text: "hi",
                          isSender: isSender, isHidden: hidden, isDeleted: deleted, mentions: mentions)
        }
        func says(_ msg: BeeperMessage, _ chat: BeeperChat?, _ mode: ChatMonitorConfig.BeeperAnnounce, muteOwn: Bool = true) -> Bool {
            BeeperClient.shouldAnnounce(msg, chat: chat, ownUserIDs: me, mode: mode, muteOwn: muteOwn)
        }
        #expect(says(m(), dm, .directAndMentions))
        #expect(!says(m(), group, .directAndMentions))
        #expect(says(m(mentions: ["@me:fake.test"]), group, .directAndMentions))
        #expect(says(m(mentions: ["@room"]), group, .directAndMentions))
        #expect(!says(m(mentions: ["@someone-else:fake.test"]), group, .directAndMentions))
        #expect(says(m(), group, .all))
        // An unknown chat is treated as a group.
        #expect(!says(m(), nil, .directAndMentions))
        #expect(!says(m(type: "REACTION"), dm, .all))
        #expect(!says(m(hidden: true), dm, .all))
        #expect(!says(m(deleted: true), dm, .all))
        #expect(!says(m(isSender: true), dm, .all))
        #expect(!says(m(sender: "@me:fake.test"), dm, .all))
        #expect(says(m(isSender: true), dm, .all, muteOwn: false))
        #expect(!says(m(), BeeperChat(id: "d", isDirect: true, isMuted: true), .all))
        #expect(!says(m(), BeeperChat(id: "d", isDirect: true, isLowPriority: true), .all))
    }

    @Test func whatIsSaidOfAMessage() {
        func text(_ type: String, _ body: String) -> String? {
            BeeperClient.spokenText(BeeperMessage(id: "1", chatID: "c", accountID: "a", timestamp: start, type: type, text: body))
        }
        #expect(text("TEXT", "  hello \n there ") == "hello there")
        #expect(text("TEXT", "  ") == nil)
        #expect(text("NOTICE", "server says") == "server says")
        #expect(text("IMAGE", "") == "sent a photo")
        #expect(text("IMAGE", "the view") == "sent a photo: the view")
        #expect(text("VIDEO", "") == "sent a video")
        #expect(text("VOICE", "") == "sent a voice message")
        #expect(text("AUDIO", "") == "sent an audio file")
        #expect(text("FILE", "") == "sent a file")
        #expect(text("STICKER", "") == "sent a sticker")
        #expect(text("LOCATION", "") == "shared a location")
    }

    @Test func theSpokenLineNamesTheNetworkAndTheGroup() {
        let msg = BeeperMessage(id: "1", chatID: "c", accountID: "a", senderName: "Bob", timestamp: start, text: "hi")
        let account = BeeperAccount(accountID: "a", network: "Signal")
        #expect(BeeperClient.incoming(msg, chat: BeeperChat(id: "c", isDirect: false, title: "Family"), account: account, text: "hi")
                .spokenLine == "Signal message from Bob in Family: hi")
        #expect(BeeperClient.incoming(msg, chat: BeeperChat(id: "c", isDirect: true, title: "Bob"), account: account, text: "hi")
                .spokenLine == "Signal message from Bob: hi")
        // No account known: the chat's network; neither: Beeper.
        #expect(BeeperClient.incoming(msg, chat: BeeperChat(id: "c", isDirect: true, network: "Telegram"), account: nil, text: "hi")
                .spokenLine == "Telegram message from Bob: hi")
        #expect(BeeperClient.incoming(msg, chat: nil, account: nil, text: "hi").spokenLine == "Beeper message from Bob: hi")
        // Slack and Google Chat read as before.
        #expect(IncomingMessage(source: .slack, id: "1", timestamp: start, senderId: "", senderName: "alice", channel: "general",
                                text: "hi").spokenLine == "Slack message from alice in general: hi")
    }

    /// The address can be moved for a test, only on this Mac; anything
    /// else reads nothing rather than falling back to the real Beeper.
    @Test func theAddressStaysOnThisMac() {
        #expect(BeeperClient.baseURL(environment: [:]) == .success(URL(string: "http://localhost:23373")!))
        #expect(BeeperClient.baseURL(environment: ["HOMESPEAKER_BEEPER_URL": ""]) == .success(BeeperClient.defaultBaseURL))
        for good in ["http://localhost:5000", "http://127.0.0.1:5000", "http://[::1]:5000"] {
            #expect(BeeperClient.baseURL(environment: ["HOMESPEAKER_BEEPER_URL": good]) == .success(URL(string: good)!), "\(good)")
        }
        for bad in ["http://example.com:23373", "https://localhost:5000", "http://192.168.1.10:23373", "localhost:5000",
                    "http://localhost.example.com"] {
            guard case .failure = BeeperClient.baseURL(environment: ["HOMESPEAKER_BEEPER_URL": bad]) else {
                Issue.record("\(bad) was taken")
                continue
            }
        }
    }

    @Test func accountsReadAsAListOrUnderItems() {
        let list = BeeperClient.parseAccounts(try! JSONSerialization.jsonObject(with: Data(accountsBody.utf8)))
        #expect(list.count == 6)
        #expect(list[0] == BeeperAccount(accountID: "local-whatsapp_ba_FAKE", bridgeType: "whatsapp", network: "WhatsApp",
                                         userID: "@me-wa:fake.test"))
        let wrapped = BeeperClient.parseAccounts(["items": [["accountID": "a", "network": "Signal"], ["network": "no id"]]])
        #expect(wrapped == [BeeperAccount(accountID: "a", network: "Signal")])
        #expect(BeeperClient.parseAccounts("nonsense").isEmpty)
    }

    @Test func aSearchReadsOldestFirstWithItsChats() throws {
        let json = try #require(try JSONSerialization.jsonObject(with: Data(searchBody(everyCase.reversed()).utf8)) as? [String: Any])
        let found = BeeperClient.parseSearch(json)
        #expect(found.messages.count == everyCase.count)
        #expect(found.messages.first?.id == "m-old")
        #expect(found.messages.map(\.timestamp) == found.messages.map(\.timestamp).sorted())
        #expect(found.chats["sig-family"]?.isDirect == false)
        #expect(found.chats["wa-dm"]?.isDirect == true)
        #expect(found.chats["muted-dm"]?.isMuted == true)
        #expect(found.messages.first { $0.id == "m-sig-plain" }?.mentions == [])
    }

    @Test func connectionErrorsSayWhatHappened() {
        #expect(BeeperClient.mapped(URLError(.cannotConnectToHost)) == .beeperNotRunning)
        #expect(BeeperClient.mapped(URLError(.networkConnectionLost)) == .beeperNotRunning)
        #expect(ChatMonitorError.beeperNotRunning.localizedDescription.contains("isn't running"))
        #expect(BeeperClient.mapped(URLError(.timedOut)).localizedDescription.contains("did not answer"))
        #expect(BeeperClient.mapped(URLError(.appTransportSecurityRequiresSecureConnection)).localizedDescription
                .contains("App Transport Security"))
    }

    @Test func beeperOnWithoutATokenIsASetupProblem() {
        let on = ChatMonitorConfig(beeperEnabled: true)
        #expect(ChatMonitorService.setupProblems(config: on, hasSlackToken: false, hasChatScopes: false, gwsInstalled: false,
                                                 hasBeeperToken: false) == [.beeperTokenMissing])
        #expect(ChatMonitorService.setupProblems(config: on, hasSlackToken: false, hasChatScopes: false, gwsInstalled: false,
                                                 hasBeeperToken: true).isEmpty)
        #expect(ChatMonitorService.setupProblems(config: ChatMonitorConfig(), hasSlackToken: false, hasChatScopes: false,
                                                 gwsInstalled: false, hasBeeperToken: false).isEmpty)
    }

    @Test func theReadingLine() {
        #expect(ChatMonitorService.beeperReadingLine(networks: nil, skipped: nil) == nil)
        #expect(ChatMonitorService.beeperReadingLine(networks: ["Signal", "WhatsApp"], skipped: [])
                == "Reading Beeper: Signal, WhatsApp")
        #expect(ChatMonitorService.beeperReadingLine(networks: ["WhatsApp", "Signal"], skipped: ["Slack"])
                == "Reading Beeper: WhatsApp, Signal · Slack skipped (read directly)")
        #expect(ChatMonitorService.beeperReadingLine(networks: [], skipped: nil) == "Reading Beeper: no networks")
    }
}

// MARK: - Settings and the status file

@Suite struct BeeperSettingsTests {
    @Test func olderSettingsReadWithBeeperOff() throws {
        let old = try JSONDecoder().decode(ChatMonitorConfig.self, from: Data(#"{"slack_enabled": true}"#.utf8))
        #expect(!old.beeperEnabled)
        #expect(old.beeperAnnounce == .directAndMentions)
        #expect(old.anySourceEnabled)
        #expect(!ChatMonitorConfig().anySourceEnabled)
        #expect(ChatMonitorConfig(beeperEnabled: true).anySourceEnabled)
    }

    @Test func beeperSettingsRoundTripUnderTheirSnakeCaseKeys() throws {
        let config = ChatMonitorConfig(beeperEnabled: true, beeperAnnounce: .all)
        let json = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(config)) as? [String: Any])
        #expect(json["beeper_enabled"] as? Bool == true)
        #expect(json["beeper_announce"] as? String == "all")
        #expect(try JSONDecoder().decode(ChatMonitorConfig.self, from: JSONEncoder().encode(config)) == config)
    }

    @Test func anAnnounceChoiceFromANewerVersionReadsAsTheDefault() throws {
        let read = try JSONDecoder().decode(
            ChatMonitorConfig.self, from: Data(#"{"beeper_enabled": true, "beeper_announce": "only_vips"}"#.utf8))
        #expect(read.beeperEnabled)
        #expect(read.beeperAnnounce == .directAndMentions)
    }

    @Test func theTokenIsKeptBesideTheOthers() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("homespeaker-beeper-secrets-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = SecretStore(fileURL: dir.appendingPathComponent("secrets.json"))
        try store.save(Secrets(slackToken: "fake-slack")) // gitleaks:allow (made-up test token)
        try store.update { $0.beeperToken = "fake-beeper" } // gitleaks:allow (made-up test token)
        #expect(store.load().beeperToken == "fake-beeper")
        #expect(store.load().slackToken == "fake-slack")
        // An older file, without the key, reads with none.
        try Data(#"{"slackToken":"x"}"#.utf8).write(to: store.fileURL)
        #expect(store.load().beeperToken == nil)
    }

    @Test func theStatusFileCarriesTheNetworksAndOlderFilesRead() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("homespeaker-beeper-status-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = ChatMonitorStatusFile(url: dir.appendingPathComponent(ChatMonitorStatusFile.fileName))
        let status = ChatMonitorStatus(isRunning: true, beeperNetworks: ["Signal", "WhatsApp"],
                                       beeperSkippedNetworks: ["Slack (acme)"], pid: 42)
        try file.write(status)
        #expect(file.read() == status)
        let raw = try String(contentsOf: file.url, encoding: .utf8)
        #expect(raw.contains("\"beeper_networks\"") && raw.contains("\"beeper_skipped_networks\""))
        try Data(#"{"is_running": true, "pid": 7}"#.utf8).write(to: file.url)
        #expect(file.read()?.beeperNetworks == nil)
        #expect(file.read()?.isRunning == true)
    }
}

// MARK: - The monitor reading Beeper

@MainActor
@Suite struct BeeperMonitorTests {
    /// Every case the design lists, in one search: Slack on (its token
    /// reads workspace TNATIVE, "acme"), Google Chat on, Beeper in its
    /// default mode, own messages skipped.
    @Test func everyCaseInOnePoll() async throws {
        let scenario = StandInBeeper.Scenario(searches: [.body(searchBody(everyCase))])
        var rig = try Rig(
            monitorConfig: ChatMonitorConfig(slackEnabled: true, googleChatEnabled: true, googleChatSource: .api,
                                             beeperEnabled: true),
            beeperToken: fakeToken(), slackToken: "fake-slack-token", beeper: scenario) // gitleaks:allow (made-up test token)
        defer { rig.finish() }
        await rig.startMonitor()
        try #require(rig.monitor.isRunning, "\(rig.monitor.lastError ?? "")")
        await rig.poll(at: 30)

        #expect(rig.spoken == [
            "WhatsApp message from Alice: Dinner at seven",
            "Signal message from Bob in Family: can you call grandma",
            "Slack message from Dan: other workspace",
            "Google Messages message from Eve: Running late",
            "WhatsApp message from Alice: sent a photo",
        ])
        #expect(rig.monitor.beeperNetworks == ["Google Messages", "Signal", "Slack", "WhatsApp"])
        #expect(rig.monitor.beeperSkippedNetworks == ["Google Chat", "Slack (acme)"])
        let status = try #require(ChatMonitorStatusFile(url: rig.engine.profile.monitorStatusURL).read())
        #expect(status.beeperSkippedNetworks == ["Google Chat", "Slack (acme)"])

        // Asked as the design says: after the start, 20 at most, muted and
        // low-priority chats left out, other people's only.
        let search = try #require(rig.beeper.searches.first)
        #expect(search.query["dateAfter"] == ISO8601DateFormatter.fractional.string(from: start))
        #expect(search.query["limit"] == "20")
        #expect(search.query["includeMuted"] == "false")
        #expect(search.query["excludeLowPriority"] == "true")
        #expect(search.query["sender"] == "others")
        #expect(rig.beeper.requests.map(\.path) == ["/v1/accounts", "/v1/messages/search"])
        rig.expectOnlyGoodGETs()
    }

    /// Slack on with no token: the workspace is not known, so every Slack
    /// account in Beeper is skipped. Google Chat off: its messages speak.
    @Test func slackOnWithAnUnknownWorkspaceSkipsEverySlack() async throws {
        let scenario = StandInBeeper.Scenario(searches: [.body(searchBody(everyCase))])
        var rig = try Rig(monitorConfig: ChatMonitorConfig(slackEnabled: true, beeperEnabled: true, beeperAnnounce: .all),
                          beeperToken: fakeToken(), beeper: scenario)
        defer { rig.finish() }
        await rig.startMonitor()
        await rig.poll(at: 30)
        #expect(!rig.spoken.contains { $0.hasPrefix("Slack") })
        #expect(rig.spoken.contains("Google Chat message from Gus: google chat dm"))
        // `.all`: the group message without a mention speaks too.
        #expect(rig.spoken.contains("Signal message from Bob in Family: lol"))
        #expect(rig.monitor.beeperSkippedNetworks == ["Slack"])
        rig.expectOnlyGoodGETs()
    }

    /// A message that arrives late, inside the look-back window, is spoken
    /// once; the one spoken before is not spoken again; nothing from before
    /// the monitor started ever is.
    @Test func theLookBackWindowSpeaksALateMessageOnce() async throws {
        let a = message("a", chat: "wa-dm", account: "local-whatsapp_ba_FAKE", from: "Alice", at: 990, text: "first")
        let late = message("late", chat: "wa-dm", account: "local-whatsapp_ba_FAKE", from: "Alice", at: 995, text: "late one")
        let old = message("old", chat: "wa-dm", account: "local-whatsapp_ba_FAKE", from: "Alice", at: -5, text: "before start")
        let scenario = StandInBeeper.Scenario(searches: [
            .body(searchBody([a, old])), .body(searchBody([a, late, old])), .body(searchBody([a, late])),
        ])
        var rig = try Rig(monitorConfig: ChatMonitorConfig(beeperEnabled: true), beeperToken: fakeToken(), beeper: scenario)
        defer { rig.finish() }
        await rig.startMonitor()
        await rig.poll(at: 1000)
        await rig.poll(at: 1060)
        await rig.poll(at: 1120)
        #expect(rig.spoken == ["WhatsApp message from Alice: first", "WhatsApp message from Alice: late one"])
        let after = rig.beeper.searches.map { $0.query["dateAfter"] }
        #expect(after == [
            ISO8601DateFormatter.fractional.string(from: start),
            ISO8601DateFormatter.fractional.string(from: start.addingTimeInterval(1000 - 300)),
            ISO8601DateFormatter.fractional.string(from: start.addingTimeInterval(1060 - 300)),
        ])
        rig.expectOnlyGoodGETs()
    }

    /// The window never empties its memory wholesale: after more than 500
    /// messages (where the monitor's other memory starts again), the ones
    /// still in the window are not spoken again.
    @Test func manyMessagesAreNotSpokenAgain() async throws {
        let many = (0..<520).map {
            message("n\($0)", chat: "wa-dm", account: "local-whatsapp_ba_FAKE", from: "Alice", at: 900 + Double($0) / 10, text: "n\($0)")
        }
        let scenario = StandInBeeper.Scenario(searches: [.body(searchBody(many))])
        var rig = try Rig(monitorConfig: ChatMonitorConfig(beeperEnabled: true), beeperToken: fakeToken(), beeper: scenario)
        defer { rig.finish() }
        await rig.startMonitor()
        await rig.poll(at: 1000)
        #expect(rig.local.spoken.count == 520)
        await rig.poll(at: 1010)
        #expect(rig.local.spoken.count == 520, "\(rig.local.spoken.count - 520) spoken again")
    }

    /// Messages that came while broadcasting was off are not spoken once it
    /// is back on, as with Slack.
    @Test func messagesWhileBroadcastingIsOffAreNotSpokenLater() async throws {
        let wa = message("wa", chat: "wa-dm", account: "local-whatsapp_ba_FAKE", from: "Alice", at: 20, text: "while off")
        let scenario = StandInBeeper.Scenario(searches: [.body(searchBody([wa]))])
        var rig = try Rig(monitorConfig: ChatMonitorConfig(beeperEnabled: true), beeperToken: fakeToken(), beeper: scenario)
        defer { rig.finish() }
        var config = rig.engine.config.config
        config.enabled = false
        rig.engine.config.config = config
        await rig.startMonitor()
        await rig.poll(at: 30)
        config.enabled = true
        rig.engine.config.config = config
        await rig.poll(at: 60)
        #expect(rig.local.spoken.isEmpty)
    }

    /// Beeper not running: the monitor runs anyway, says so, and reads it
    /// at the next poll once it is.
    @Test func beeperNotRunningSaysSoAndRecovers() async throws {
        let wa = message("wa", chat: "wa-dm", account: "local-whatsapp_ba_FAKE", from: "Alice", at: 50, text: "back")
        let scenario = StandInBeeper.Scenario(accounts: [.refused, .body(accountsBody)], searches: [.body(searchBody([wa]))])
        var rig = try Rig(monitorConfig: ChatMonitorConfig(beeperEnabled: true), beeperToken: fakeToken(), beeper: scenario)
        defer { rig.finish() }
        await rig.startMonitor()
        #expect(rig.monitor.isRunning)
        await rig.poll(at: 30)
        #expect(rig.monitor.lastError == ChatMonitorError.beeperNotRunning.localizedDescription)
        #expect(rig.monitor.statusSnapshot.lastError?.contains("Beeper Desktop isn't running") == true)
        await rig.poll(at: 60)
        #expect(rig.monitor.lastError == nil)
        #expect(rig.spoken == ["WhatsApp message from Alice: back"])
        rig.expectOnlyGoodGETs()
    }

    @Test func aRefusedTokenSaysToMakeANewOne() async throws {
        let scenario = StandInBeeper.Scenario(
            accounts: [.status(401, #"{"message":"Unauthorized: Invalid or missing token","code":"unauthorized"}"#)],
            searches: [])
        var rig = try Rig(monitorConfig: ChatMonitorConfig(beeperEnabled: true), beeperToken: fakeToken(), beeper: scenario)
        defer { rig.finish() }
        await rig.startMonitor()
        await rig.poll(at: 30)
        #expect(rig.monitor.lastError?.contains("the saved token was refused") == true)
        #expect(rig.beeper.searches.isEmpty)
        rig.expectOnlyGoodGETs()
    }

    /// 429: the next poll leaves Beeper alone; the one after asks again.
    @Test func askedToSlowDownSkipsOnePoll() async throws {
        let scenario = StandInBeeper.Scenario(searches: [.status(429, "{}"), .body(searchBody([]))])
        var rig = try Rig(monitorConfig: ChatMonitorConfig(beeperEnabled: true), beeperToken: fakeToken(), beeper: scenario)
        defer { rig.finish() }
        await rig.startMonitor()
        await rig.poll(at: 30)
        #expect(rig.monitor.lastError == ChatMonitorError.beeperSlowDown.localizedDescription)
        await rig.poll(at: 60)
        #expect(rig.beeper.searches.count == 1)
        await rig.poll(at: 90)
        #expect(rig.beeper.searches.count == 2)
        #expect(rig.monitor.lastError == nil)
        rig.expectOnlyGoodGETs()
    }

    @Test func anotherErrorSaysBeepersOwnMessage() async throws {
        let scenario = StandInBeeper.Scenario(searches: [.status(500, #"{"message":"database is locked"}"#)])
        var rig = try Rig(monitorConfig: ChatMonitorConfig(beeperEnabled: true), beeperToken: fakeToken(), beeper: scenario)
        defer { rig.finish() }
        await rig.startMonitor()
        await rig.poll(at: 30)
        #expect(rig.monitor.lastError == "Beeper: database is locked")
    }

    /// Beeper on with no token: a setup problem, no monitor, and nothing
    /// asked of Beeper at all.
    @Test func noTokenAsksNothing() async throws {
        let scenario = StandInBeeper.Scenario(searches: [.body(searchBody(everyCase))])
        let token = fakeToken()
        StandInBeeper.register(scenario, token: token)
        var rig = try Rig(monitorConfig: ChatMonitorConfig(beeperEnabled: true), beeperToken: nil, beeper: scenario)
        defer { rig.finish() }
        await rig.startMonitor()
        #expect(!rig.monitor.isRunning)
        #expect(rig.monitor.lastError == ChatMonitorError.beeperTokenMissing.localizedDescription)
        await rig.poll(at: 30)
        #expect(scenario.requests.isEmpty)
    }

    /// Own messages are left out by the search itself, and again by the
    /// monitor; with "Skip messages I sent" off, they are asked for.
    @Test func ownMessagesFollowTheSwitch() async throws {
        let own = message("own", chat: "wa-dm", account: "local-whatsapp_ba_FAKE", from: "Me", at: 20, text: "mine", isSender: true)
        let scenario = StandInBeeper.Scenario(searches: [.body(searchBody([own]))])
        var rig = try Rig(monitorConfig: ChatMonitorConfig(muteOwnMessages: false, beeperEnabled: true),
                          beeperToken: fakeToken(), beeper: scenario)
        defer { rig.finish() }
        await rig.startMonitor()
        await rig.poll(at: 30)
        #expect(rig.beeper.searches.first?.query["sender"] == nil)
        #expect(rig.spoken == ["WhatsApp message from Me: mine"])
    }
}
