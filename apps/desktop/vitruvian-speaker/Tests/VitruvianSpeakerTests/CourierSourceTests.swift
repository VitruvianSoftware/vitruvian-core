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

// Courier as a second chat source beside Beeper: the same API on its own
// port with its own token. Nothing here reaches the network, and never the
// real Beeper Desktop (23373) or Courier (23390) on this Mac: every request
// goes to a stand-in answering in this process, at made-up loopback ports,
// and the stand-in fails any request to either real port, anywhere but this
// Mac, or with any method but GET. Each test uses made-up tokens of its own,
// which the stand-in keys its answers on. Every fixture is fake.

// MARK: - Fixtures (fake)

private let start = Date(timeIntervalSince1970: 1_800_000_000)
private let beeperBase = URL(string: "http://localhost:47981")!
private let courierBase = URL(string: "http://localhost:47982")!

private func stamp(_ seconds: TimeInterval) -> String {
    ISO8601DateFormatter.fractional.string(from: start.addingTimeInterval(seconds))
}

/// One app's accounts: WhatsApp and Signal, under ids of the app's own.
private func accounts(_ prefix: String) -> String {
    """
    [
      {"accountID": "\(prefix)-whatsapp_FAKE", "bridge": {"type": "whatsapp"}, "network": "WhatsApp",
       "user": {"id": "@\(prefix)-me-wa:fake.test"}},
      {"accountID": "\(prefix)-signal_FAKE", "bridge": {"type": "signal"}, "network": "Signal",
       "user": {"id": "@\(prefix)-me-sig:fake.test"}}
    ]
    """
}

/// A direct message, as either app serves one: `prefix` makes its ids and
/// its chat's id the app's own, as they are in life.
private func dm(_ id: String, _ prefix: String, network: String = "whatsapp", from: String, at: TimeInterval,
                text: String) -> String {
    """
    {"id": "\(prefix)-\(id)", "chatID": "\(prefix)-\(network)-dm-\(from.lowercased())",
     "accountID": "\(prefix)-\(network)_FAKE", "senderID": "@\(prefix)-\(from.lowercased()):fake.test",
     "senderName": "\(from)", "timestamp": "\(stamp(at))", "type": "TEXT", "text": "\(text)",
     "isSender": false, "isHidden": false, "isDeleted": false, "mentions": []}
    """
}

private func search(_ items: [String], _ prefix: String) -> String {
    let chats = ["whatsapp", "signal"].flatMap { network in
        ["Alice", "Bob", "Carol"].map { who in
            let id = "\(prefix)-\(network)-dm-\(who.lowercased())"
            let name = network == "whatsapp" ? "WhatsApp" : "Signal"
            return #""\#(id)": {"id": "\#(id)", "type": "single", "title": "\#(who)", "network": "\#(name)"}"#
        }
    }.joined(separator: ",")
    return #"{"items": ["# + items.joined(separator: ",") + #"], "hasMore": false, "chats": {"# + chats + "}}"
}

// MARK: - The stand-in

/// Beeper and Courier, answering in this process, by token. A token's
/// searches take the next answer each poll (the last one repeats).
private final class StandInApps: URLProtocol {
    struct Request: Equatable {
        let method: String
        let host: String
        let port: Int?
        let path: String
        let bearer: String?
    }

    enum Answer {
        case body(String)
        case status(Int, String)
        case refused
    }

    final class App: @unchecked Sendable {
        private let lock = NSLock()
        private let accountsBody: String
        private var searches: [Answer]
        private var seen: [Request] = []

        init(accounts: String, searches: [Answer]) {
            accountsBody = accounts
            self.searches = searches
        }

        var requests: [Request] { lock.withLock { seen } }

        func answer(_ request: Request) -> Answer {
            lock.withLock {
                seen.append(request)
                switch request.path {
                case "/v1/accounts": return .body(accountsBody)
                case "/v1/messages/search":
                    guard let first = searches.first else { return .status(500, "{}") }
                    if searches.count > 1 { searches.removeFirst() }
                    return first
                default: return .status(404, #"{"message":"not found"}"#)
                }
            }
        }
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var apps: [String: App] = [:]
    nonisolated(unsafe) private static var strays: [Request] = []

    static func register(_ app: App, token: String) { lock.withLock { apps[token] = app } }
    static var badRequests: [Request] { lock.withLock { strays } }

    static var session: URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StandInApps.self]
        return URLSession(configuration: configuration)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        let url = request.url!
        let bearer = request.value(forHTTPHeaderField: "Authorization").flatMap {
            $0.hasPrefix("Bearer ") ? String($0.dropFirst("Bearer ".count)) : nil
        }
        let seen = Request(method: request.httpMethod ?? "GET", host: url.host ?? "", port: url.port, path: url.path,
                           bearer: bearer)
        // HomeSpeaker's own Slack reader: who the token is, and nothing new.
        if url.host == "slack.com" {
            switch url.path {
            case "/api/auth.test": finish(200, #"{"ok":true,"user_id":"UME1","user":"me","team_id":"TNATIVE","team":"acme"}"#)
            default: finish(200, #"{"ok":true,"messages":{"matches":[]}}"#)
            }
            return
        }
        let app = Self.lock.withLock { bearer.flatMap { Self.apps[$0] } }
        let rulesKept = seen.method == "GET" && ChatAppClient.isLoopback(url) && url.port != 23373 && url.port != 23390
        guard rulesKept, let app else {
            Self.lock.withLock { Self.strays.append(seen) }
            finish(418, "{}")
            return
        }
        switch app.answer(seen) {
        case .body(let body): finish(200, body)
        case .status(let code, let body): finish(code, body)
        case .refused: client?.urlProtocol(self, didFailWithError: URLError(.cannotConnectToHost))
        }
    }

    private func finish(_ status: Int, _ body: String) {
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1",
                                       headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
}

/// This Mac's speech, made silent.
private struct QuietLocal: LocalSpeaking {
    func speak(_ text: String, voiceID: String) async throws {}
}

/// A made-up token, unique to the test. // gitleaks:allow (made-up test token)
private func fakeToken(_ app: String) -> String { "fake-\(app)-test-token-\(UUID().uuidString)" } // gitleaks:allow (made-up test token)

// MARK: - A monitor on a scratch engine

@MainActor
private struct Rig {
    let root: URL
    let engine: HomeSpeakerEngine
    let monitor: ChatMonitorService
    let beeperToken: String
    let courierToken: String
    let statusURL: URL

    init(_ monitorConfig: ChatMonitorConfig, beeper: StandInApps.App?, courier: StandInApps.App?,
         courierToken: Bool = true, slackToken: String? = nil) throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("homespeaker-courier-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let profile = HomeSpeakerProfile.extension(
            dataFolder: root.appendingPathComponent("data"), toolFolder: nil,
            messagePrefix: "test.\(UUID().uuidString).homespeaker")
        for url in [profile.settingsURL, profile.historyURL, profile.secretsURL, profile.monitorStatusURL] {
            try #require(url.path.hasPrefix(root.path + "/"), "\(url.path) is outside the scratch folder")
        }
        engine = HomeSpeakerEngine(profile: profile, session: StandInApps.session, local: QuietLocal())
        var config = SpeakerConfig(enabled: true, quietHoursEnabled: false, chatMonitor: monitorConfig)
        config.speakHome = false
        config.speakLocal = true
        engine.config.config = config
        beeperToken = fakeToken("beeper")
        self.courierToken = fakeToken("courier")
        try engine.secrets.save(Secrets(slackToken: slackToken, beeperToken: beeperToken,
                                        courierToken: courierToken ? self.courierToken : nil))
        if let beeper { StandInApps.register(beeper, token: beeperToken) }
        if let courier { StandInApps.register(courier, token: self.courierToken) }
        statusURL = profile.monitorStatusURL
        monitor = ChatMonitorService(
            configManager: engine.config, secrets: engine.secrets, home: engine.home, announcer: engine.announcer,
            statusFile: ChatMonitorStatusFile(url: profile.monitorStatusURL), auth: engine.auth,
            chatSession: StandInApps.session, slackSession: StandInApps.session,
            beeperSession: StandInApps.session, beeperBaseURL: beeperBase,
            courierSession: StandInApps.session, courierBaseURL: courierBase)
        monitor.runsLoop = false
        monitor.now = { start }
    }

    func poll(at seconds: TimeInterval) async {
        let when = start.addingTimeInterval(seconds)
        monitor.now = { when }
        await monitor.pollOnce()
    }

    /// What was spoken, oldest first, with the app it came through.
    var spoken: [(source: String, text: String)] {
        engine.history.load().reversed().map { ($0.source, $0.text) }
    }

    var spokenTexts: [String] { spoken.map(\.text) }

    func finish() {
        monitor.stop()
        try? FileManager.default.removeItem(at: root)
    }
}

// MARK: - Courier on its own

@MainActor
@Suite struct CourierMonitorTests {
    @Test func courierIsReadAtItsOwnAddressWithItsOwnToken() async throws {
        let courier = StandInApps.App(accounts: accounts("co"), searches: [.body(search([
            dm("1", "co", from: "Alice", at: 10, text: "Dinner at seven"),
            dm("2", "co", network: "signal", from: "Bob", at: 11, text: "Running late"),
        ], "co"))])
        let rig = try Rig(ChatMonitorConfig(courierEnabled: true), beeper: nil, courier: courier)
        defer { rig.finish() }
        rig.monitor.start()
        try #require(rig.monitor.isRunning, "\(rig.monitor.lastError ?? "")")
        await rig.poll(at: 30)

        #expect(rig.spoken.map(\.source) == ["Courier", "Courier"])
        #expect(rig.spokenTexts == ["WhatsApp message from Alice: Dinner at seven", "Signal message from Bob: Running late"])
        #expect(!courier.requests.isEmpty)
        #expect(courier.requests.allSatisfy {
            $0.method == "GET" && $0.bearer == rig.courierToken && $0.port == courierBase.port && $0.host == "localhost"
        }, "\(courier.requests)")
        #expect(StandInApps.badRequests.filter { $0.bearer == rig.courierToken || $0.bearer == rig.beeperToken }.isEmpty)
        // Its networks, in the status file, apart from Beeper's.
        let status = try #require(ChatMonitorStatusFile(url: rig.statusURL).read())
        #expect(status.courierNetworks == ["Signal", "WhatsApp"])
        #expect(status.beeperNetworks == nil)
        #expect(rig.monitor.networks(for: .courier) == ["Signal", "WhatsApp"])
        #expect(ChatMonitorService.readingLine(.courier, networks: status.courierNetworks, skipped: status.courierSkippedNetworks)
                == "Reading Courier: Signal, WhatsApp")
    }

    @Test func courierIsOffUntilATokenIsSaved() async throws {
        #expect(!ChatMonitorConfig().courierEnabled)
        let old = try JSONDecoder().decode(ChatMonitorConfig.self, from: Data(#"{"beeper_enabled": true}"#.utf8))
        #expect(!old.courierEnabled && old.courierMutedNetworks.isEmpty && old.courierAddress.isEmpty)
        #expect(ChatMonitorService.setupProblems(
            config: ChatMonitorConfig(courierEnabled: true), hasSlackToken: false, hasChatScopes: false, gwsInstalled: false,
            hasBeeperToken: false, hasCourierToken: false) == [.chatAppTokenMissing(.courier)])

        // Switched on in the file with no token: nothing is read, and it says why.
        let courier = StandInApps.App(accounts: accounts("co"), searches: [.body(search([], "co"))])
        let rig = try Rig(ChatMonitorConfig(courierEnabled: true), beeper: nil, courier: courier, courierToken: false)
        defer { rig.finish() }
        rig.monitor.start()
        #expect(!rig.monitor.isRunning)
        #expect(rig.monitor.lastError == "Courier monitoring is on but no Courier token is saved.")
        #expect(courier.requests.isEmpty)
    }

    @Test func courierErrorsNameCourier() async throws {
        let courier = StandInApps.App(accounts: accounts("co"), searches: [.status(401, "{}")])
        let rig = try Rig(ChatMonitorConfig(courierEnabled: true), beeper: nil, courier: courier)
        defer { rig.finish() }
        rig.monitor.start()
        await rig.poll(at: 30)
        let error = try #require(rig.monitor.lastError)
        #expect(error.hasPrefix("Courier: the saved token was refused."), "\(error)")
        #expect(error.contains("New connection"))
        #expect(!error.contains("Beeper"))
        #expect(ChatAppClient.mapped(URLError(.cannotConnectToHost), app: .courier).localizedDescription
                == "Courier: Courier isn't running, or its API is off (Courier Settings › Integrations).")
        #expect(ChatMonitorError.chatAppTooMany(.courier).localizedDescription.hasSuffix("Mute busy chats in Courier."))
    }

    @Test func eachAppHasItsOwnNetworkSwitches() async throws {
        let beeper = StandInApps.App(accounts: accounts("be"), searches: [.body(search([
            dm("1", "be", from: "Alice", at: 10, text: "via beeper"),
        ], "be"))])
        let courier = StandInApps.App(accounts: accounts("co"), searches: [.body(search([
            dm("1", "co", from: "Bob", at: 11, text: "via courier"),
            dm("2", "co", network: "signal", from: "Carol", at: 12, text: "signal via courier"),
        ], "co"))])
        // WhatsApp off in Courier's list only.
        let rig = try Rig(ChatMonitorConfig(beeperEnabled: true, courierEnabled: true, courierMutedNetworks: ["whatsapp"]),
                          beeper: beeper, courier: courier)
        defer { rig.finish() }
        rig.monitor.start()
        await rig.poll(at: 30)
        #expect(rig.spokenTexts == ["WhatsApp message from Alice: via beeper", "Signal message from Carol: signal via courier"])
        let status = try #require(ChatMonitorStatusFile(url: rig.statusURL).read())
        #expect(status.courierNetworkStates?.first { $0.key == "whatsapp" }?.state == .muted)
        #expect(status.beeperNetworkStates?.first { $0.key == "whatsapp" }?.state == .reading)

        // The switch saves into Courier's list and leaves Beeper's alone.
        #expect(rig.engine.config.setNetwork("signal", of: .courier, reading: false))
        #expect(rig.engine.config.config.effectiveChatMonitor.courierMutedNetworks == ["whatsapp", "signal"])
        #expect(rig.engine.config.config.effectiveChatMonitor.beeperMutedNetworks == [])
        // And, like Beeper's, never restarts the monitor.
        #expect(ChatMonitorReconciliation.decide(
            old: ChatMonitorConfig(courierEnabled: true), new: ChatMonitorConfig(courierEnabled: true, courierMutedNetworks: ["x"]),
            isRunning: true) == .none)
    }
}

// MARK: - Courier's Slack

/// Courier's accounts as it serves them: opaque ids that say nothing of a
/// Slack workspace, the network's name as the bridge's type.
private let courierSlackAccounts = """
[
  {"accountID": "login-1", "bridge": {"id": "slack", "type": "slack", "provider": "local"}, "network": "Slack",
   "user": {"id": "@me:courier.local", "isSelf": true}, "status": "CONNECTED"},
  {"accountID": "login-2", "bridge": {"id": "whatsapp", "type": "whatsapp", "provider": "local"}, "network": "WhatsApp",
   "user": {"id": "@me:courier.local", "isSelf": true}, "status": "CONNECTED"}
]
"""

private func courierSlackSearch() -> String {
    """
    {"items": [
      {"id": "$e1", "chatID": "!slack-dm", "accountID": "login-1", "senderID": "@slack_dee:courier.local",
       "senderName": "Dee", "timestamp": "\(stamp(10))", "type": "TEXT", "text": "from another workspace",
       "isSender": false, "isHidden": false, "isDeleted": false, "mentions": []},
      {"id": "$e2", "chatID": "!wa-dm", "accountID": "login-2", "senderID": "@whatsapp_al:courier.local",
       "senderName": "Alice", "timestamp": "\(stamp(11))", "type": "TEXT", "text": "hello",
       "isSender": false, "isHidden": false, "isDeleted": false, "mentions": []}
    ],
    "chats": {
      "!slack-dm": {"id": "!slack-dm", "accountID": "login-1", "network": "Slack", "title": "Dee", "type": "single"},
      "!wa-dm": {"id": "!wa-dm", "accountID": "login-2", "network": "WhatsApp", "title": "Alice", "type": "single"}
    },
    "hasMore": false}
    """
}

@MainActor
@Suite struct CourierSlackTests {
    /// HomeSpeaker's own Slack reader on: Courier cannot say which
    /// workspace its Slack is, so it is left to that reader, and shows as
    /// such, until the person switches it on in Courier's list.
    @Test func courierSlackIsLeftToHomeSpeakerUntilSwitchedOn() async throws {
        for readAnyway in [false, true] {
            let courier = StandInApps.App(accounts: courierSlackAccounts, searches: [.body(courierSlackSearch())])
            let rig = try Rig(
                ChatMonitorConfig(slackEnabled: true, courierEnabled: true, courierReadAnyway: readAnyway ? ["slack"] : []),
                beeper: nil, courier: courier, slackToken: "fake-slack-token") // gitleaks:allow (made-up test token)
            defer { rig.finish() }
            rig.monitor.start()
            await rig.monitor.readSlackIdentity()
            await rig.poll(at: 30)
            let status = try #require(ChatMonitorStatusFile(url: rig.statusURL).read())
            if readAnyway {
                #expect(rig.spokenTexts == ["Slack message from Dee: from another workspace", "WhatsApp message from Alice: hello"])
                #expect(status.courierNetworkStates?.first { $0.key == "slack" }?.state == .reading)
            } else {
                #expect(rig.spokenTexts == ["WhatsApp message from Alice: hello"])
                #expect(status.courierNetworkStates?.first { $0.key == "slack" }?.state == .skipped)
                #expect(status.courierSkippedNetworks == ["Slack"])
            }
        }
    }

    /// Beeper has no such switch: its Slack accounts name their workspace.
    @Test func onlyCourierReadsAnyway() {
        let account = BeeperAccount(accountID: "login-1", bridgeType: "slack", network: "Slack")
        var config = ChatMonitorConfig(slackEnabled: true, courierReadAnyway: ["slack"])
        #expect(ChatAppClient.isSkipped(account, config: config, nativeSlackTeam: "TNATIVE", app: .beeper))
        #expect(!ChatAppClient.isSkipped(account, config: config, nativeSlackTeam: "TNATIVE", app: .courier))
        config.setReadAnyway("slack", false)
        #expect(ChatAppClient.isSkipped(account, config: config, nativeSlackTeam: "TNATIVE", app: .courier))
        // A change restarts the monitor, so the accounts are sorted again.
        #expect(ChatMonitorReconciliation.decide(
            old: ChatMonitorConfig(courierEnabled: true), new: ChatMonitorConfig(courierEnabled: true, courierReadAnyway: ["slack"]),
            isRunning: true) == .restart)
    }
}

// MARK: - Both on

@MainActor
@Suite struct BothChatAppsTests {
    /// The cutover: Beeper and Courier both bridge the same WhatsApp, so
    /// each passes on every message, under ids of its own and a time a
    /// moment apart. Each is spoken once; messages only one has are spoken.
    @Test func aMessageBothPassOnIsSpokenOnce() async throws {
        let beeper = StandInApps.App(accounts: accounts("be"), searches: [.body(search([
            dm("1", "be", from: "Alice", at: 10, text: "Dinner at seven"),
            dm("2", "be", from: "Alice", at: 20, text: "ok"),
            dm("3", "be", from: "Alice", at: 25, text: "ok"),
            dm("4", "be", network: "signal", from: "Bob", at: 30, text: "only in beeper"),
        ], "be"))])
        let courier = StandInApps.App(accounts: accounts("co"), searches: [.body(search([
            dm("a", "co", from: "Alice", at: 10.4, text: "Dinner  at seven"),
            dm("b", "co", from: "Alice", at: 20.2, text: "OK"),
            dm("c", "co", from: "Alice", at: 25.3, text: "ok"),
            dm("d", "co", from: "Carol", at: 31, text: "only in courier"),
        ], "co"))])
        let rig = try Rig(ChatMonitorConfig(beeperEnabled: true, courierEnabled: true), beeper: beeper, courier: courier)
        defer { rig.finish() }
        rig.monitor.start()
        await rig.poll(at: 40)

        #expect(rig.spokenTexts == [
            "WhatsApp message from Alice: Dinner at seven",
            "WhatsApp message from Alice: ok",
            "WhatsApp message from Alice: ok",
            "Signal message from Bob: only in beeper",
            "WhatsApp message from Carol: only in courier",
        ])
    }

    /// One app passes a message on a poll before the other: the late copy
    /// is still not spoken.
    @Test func aCopyThatArrivesAPollLaterIsNotSpoken() async throws {
        let beeper = StandInApps.App(accounts: accounts("be"), searches: [.body(search([
            dm("1", "be", from: "Alice", at: 10, text: "Dinner at seven"),
        ], "be"))])
        let courier = StandInApps.App(accounts: accounts("co"), searches: [
            .body(search([], "co")),
            .body(search([dm("a", "co", from: "Alice", at: 11, text: "Dinner at seven")], "co")),
        ])
        let rig = try Rig(ChatMonitorConfig(beeperEnabled: true, courierEnabled: true), beeper: beeper, courier: courier)
        defer { rig.finish() }
        rig.monitor.start()
        await rig.poll(at: 15)
        await rig.poll(at: 30)
        #expect(rig.spoken.map(\.source) == ["Beeper"])
        #expect(rig.spokenTexts == ["WhatsApp message from Alice: Dinner at seven"])
    }

    /// One app down, the other still read; an error names the app it is about.
    @Test func oneAppDownLeavesTheOtherRead() async throws {
        let beeper = StandInApps.App(accounts: accounts("be"), searches: [.refused])
        let courier = StandInApps.App(accounts: accounts("co"), searches: [.body(search([
            dm("a", "co", from: "Alice", at: 10, text: "still here"),
        ], "co"))])
        let rig = try Rig(ChatMonitorConfig(beeperEnabled: true, courierEnabled: true), beeper: beeper, courier: courier)
        defer { rig.finish() }
        rig.monitor.start()
        await rig.poll(at: 30)
        #expect(rig.spokenTexts == ["WhatsApp message from Alice: still here"])
        let error = try #require(rig.monitor.lastError)
        #expect(error.hasPrefix("Beeper:") && !error.contains("Courier"), "\(error)")
    }
}

// MARK: - The rules, by themselves

@Suite struct ChatAppEchoTests {
    private func message(_ source: IncomingMessage.Source, _ text: String, from: String = "Alice", network: String? = "WhatsApp",
                         at seconds: TimeInterval) -> IncomingMessage {
        IncomingMessage(source: source, id: "\(source.rawValue)/\(UUID().uuidString)", timestamp: start.addingTimeInterval(seconds),
                        senderId: "", senderName: from, channel: "", text: text, network: network)
    }

    @Test func onlyTheOtherAppsCopyWithinTheWindowIsAnEcho() {
        var echoes = ChatAppEchoes()
        let heard: [(IncomingMessage, Bool)] = [
            (message(.beeper, "hi", at: 0), false),
            // The same app twice is two messages.
            (message(.beeper, "hi", at: 1), false),
            // The other app's copies: one each, spacing and case aside.
            (message(.courier, "Hi ", at: 2), true),
            (message(.courier, "hi", at: 3), true),
            (message(.courier, "hi", at: 4), false),
            // Another sender, network or words is another message.
            (message(.courier, "hi", from: "Bob", at: 5), false),
            (message(.courier, "hi", network: "Signal", at: 6), false),
            (message(.courier, "hello", at: 7), false),
            // Outside the window is another message.
            (message(.beeper, "later", at: 100), false),
            (message(.courier, "later", at: 100 + ChatAppEchoes.window + 1), false),
            // Slack and Google Chat are never touched.
            (message(.slack, "hi", network: nil, at: 0), false),
            (message(.slack, "hi", network: nil, at: 0), false),
        ]
        for (m, expected) in heard {
            let echo = echoes.isEcho(m)
            #expect(echo == expected, "\(m.source.rawValue) \(m.senderName) \(m.text)")
        }
    }

    @Test func forgottenMessagesNoLongerAnswer() {
        var echoes = ChatAppEchoes()
        let first = echoes.isEcho(message(.beeper, "hi", at: 0))
        echoes.forget(before: start.addingTimeInterval(1))
        let copy = echoes.isEcho(message(.courier, "hi", at: 2))
        #expect(!first && !copy)
    }

    @Test func settingsRoundTripUnderTheirSnakeCaseKeys() throws {
        let config = ChatMonitorConfig(beeperAddress: "http://localhost:5000", courierEnabled: true, courierAnnounce: .all,
                                       courierMutedNetworks: ["signal"], courierAddress: "http://127.0.0.1:5001")
        let json = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(config)) as? [String: Any])
        #expect(json["courier_enabled"] as? Bool == true)
        #expect(json["courier_announce"] as? String == "all")
        #expect(json["courier_muted_networks"] as? [String] == ["signal"])
        #expect(json["courier_address"] as? String == "http://127.0.0.1:5001")
        #expect(json["beeper_address"] as? String == "http://localhost:5000")
        #expect(try JSONDecoder().decode(ChatMonitorConfig.self, from: JSONEncoder().encode(config)) == config)
        #expect(config.anySourceEnabled && ChatMonitorConfig(courierEnabled: true).anySourceEnabled)
    }

    @Test func theTokenIsKeptBesideBeepers() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("homespeaker-courier-secrets-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = SecretStore(fileURL: dir.appendingPathComponent("secrets.json"))
        try store.save(Secrets(beeperToken: "fake-beeper")) // gitleaks:allow (made-up test token)
        try store.update { $0[keyPath: Secrets.tokenKey(.courier)] = "fake-courier" } // gitleaks:allow (made-up test token)
        #expect(store.load().token(for: .courier) == "fake-courier")
        #expect(store.load().token(for: .beeper) == "fake-beeper")
        try Data(#"{"beeperToken":"x"}"#.utf8).write(to: store.fileURL)
        #expect(store.load().courierToken == nil)
        try store.update { $0.courierToken = "" }
        #expect(store.load().token(for: .courier) == nil)
    }

    @Test func theAddressIsCouriersOwnAndStaysOnThisMac() {
        #expect(ChatAppClient.baseURL(for: .courier, environment: [:]) == .success(URL(string: "http://localhost:23390")!))
        #expect(ChatAppClient.baseURL(for: .courier, configured: "http://localhost:5001", environment: [:])
                == .success(URL(string: "http://localhost:5001")!))
        // The test variable wins over Settings, and Beeper's is not Courier's.
        #expect(ChatAppClient.baseURL(for: .courier, configured: "http://localhost:5001",
                                      environment: ["HOMESPEAKER_COURIER_URL": "http://localhost:9"])
                == .success(URL(string: "http://localhost:9")!))
        #expect(ChatAppClient.baseURL(for: .courier, environment: ["HOMESPEAKER_BEEPER_URL": "http://localhost:9"])
                == .success(ChatApp.courier.defaultBaseURL))
        for bad in ["http://example.com:23390", "https://localhost:23390", "localhost:23390", "http://192.168.1.10:23390"] {
            guard case .failure(let why) = ChatAppClient.baseURL(for: .courier, configured: bad, environment: [:]) else {
                Issue.record("\(bad) was taken")
                continue
            }
            #expect(why.localizedDescription.hasPrefix("Courier: "))
            #expect(ChatAppClient.addressProblem(bad, app: .courier) != nil)
        }
        #expect(ChatAppClient.addressProblem("", app: .courier) == nil)
        #expect(ChatAppClient.addressProblem(" http://localhost:5001 ", app: .courier) == nil)
    }

    /// Every test run names a Courier on this Mac that nothing listens on
    /// (the Bazel test targets' env), so a test that forgets its stand-in
    /// can never reach the real Courier.
    @Test func testRunsNeverPointAtTheRealCourier() throws {
        let url = try ChatAppClient.baseURL(for: .courier, environment: ProcessInfo.processInfo.environment).get()
        #expect(url.port != 23390, "run the tests through Bazel, whose env sets HOMESPEAKER_COURIER_URL")
    }
}
