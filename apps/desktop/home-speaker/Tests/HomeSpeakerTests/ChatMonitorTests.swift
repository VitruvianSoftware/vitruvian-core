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

// A poll cut off by stop() or a restart (saving a Beeper token restarts the
// monitor). Its Slack request ends in URLError(.cancelled); that must not
// become "cancelled" on screen, and the old poll must not go on to read the
// new run's Beeper and record "Beeper: cancelled" over it.
//
// Nothing here reaches the network: Slack and Beeper are one stand-in
// session answering in this process, and Beeper's address is a made-up
// loopback port, never the real Beeper Desktop's 23373.

private let standInBeeperBase = URL(string: "http://localhost:47998")!

/// Slack answers `auth.test` at once and never answers `search.messages`,
/// so a poll waits there until its task is cancelled. Beeper fails every
/// request. Requests are recorded by bearer token, unique to each test.
private final class HangingSlack: URLProtocol {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var seen: [String: [String]] = [:]

    static var session: URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [HangingSlack.self]
        return URLSession(configuration: configuration)
    }

    /// The paths requested with `token`, in order.
    static func requests(token: String) -> [String] { lock.withLock { seen["Bearer \(token)"] ?? [] } }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        let url = request.url!
        let bearer = request.value(forHTTPHeaderField: "Authorization") ?? ""
        Self.lock.withLock { Self.seen[bearer, default: []].append("\(url.host ?? ""):\(url.path)") }
        let status: Int
        let body: String
        switch (url.host, url.path) {
        case ("slack.com", "/api/auth.test"):
            (status, body) = (200, #"{"ok":true,"user_id":"UME1","user":"me","team_id":"TNATIVE","team":"acme"}"#)
        case ("slack.com", "/api/search.messages"):
            return // never answered: the poll waits here until it is cancelled
        default:
            (status, body) = (500, #"{"error":"not in this test"}"#)
        }
        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1",
                                       headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
}

/// This Mac's speech, made silent.
private struct SilentLocal: LocalSpeaking {
    func speak(_ text: String, voiceID: String) async throws {}
}

@MainActor
@Suite struct ChatMonitorCancellationTests {
    enum Interruption: CaseIterable { case stop, restart }

    @Test(arguments: Interruption.allCases)
    func aCancelledPollRecordsNoCancellation(_ interruption: Interruption) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("homespeaker-cancel-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let profile = HomeSpeakerProfile.extension(
            dataFolder: root.appendingPathComponent("data"), toolFolder: nil,
            messagePrefix: "test.\(UUID().uuidString).homespeaker")
        for url in [profile.settingsURL, profile.historyURL, profile.secretsURL, profile.monitorStatusURL] {
            try #require(url.path.hasPrefix(root.path + "/"), "\(url.path) is outside the scratch folder")
        }
        try #require(standInBeeperBase.port != 23373 && BeeperClient.isLoopback(standInBeeperBase))

        let slackToken = "fake-slack-cancel-\(UUID().uuidString)" // gitleaks:allow (made-up test token)
        let beeperToken = "fake-beeper-cancel-\(UUID().uuidString)" // gitleaks:allow (made-up test token)
        let engine = HomeSpeakerEngine(profile: profile, session: HangingSlack.session, local: SilentLocal())
        var config = SpeakerConfig(enabled: true, quietHoursEnabled: false,
                                   chatMonitor: ChatMonitorConfig(slackEnabled: true, beeperEnabled: true))
        config.speakHome = false
        config.speakLocal = true
        engine.config.config = config
        try engine.secrets.save(Secrets(slackToken: slackToken, beeperToken: beeperToken))

        let statusFile = ChatMonitorStatusFile(url: profile.monitorStatusURL)
        let monitor = ChatMonitorService(
            configManager: engine.config, secrets: engine.secrets, home: engine.home, announcer: engine.announcer,
            statusFile: statusFile, auth: engine.auth,
            chatSession: HangingSlack.session, slackSession: HangingSlack.session,
            beeperSession: HangingSlack.session, beeperBaseURL: standInBeeperBase)
        monitor.runsLoop = false
        defer { monitor.stop() }
        monitor.start()
        await monitor.readSlackIdentity()
        try #require(monitor.slackUser == "me")

        // A poll waiting on Slack, as the loop's would be.
        let poll = Task { @MainActor in await monitor.pollOnce() }
        let deadline = Date().addingTimeInterval(5)
        while !HangingSlack.requests(token: slackToken).contains("slack.com:/api/search.messages") {
            try #require(Date() < deadline, "the poll never asked Slack")
            try await Task.sleep(for: .milliseconds(10))
        }

        // What stop() does to the loop, then (for a restart) a new run.
        poll.cancel()
        switch interruption {
        case .stop: monitor.stop()
        case .restart: monitor.restartIfRunning()
        }
        await poll.value

        #expect(monitor.isRunning == (interruption == .restart))
        #expect(monitor.lastPollTime == nil, "the cancelled poll recorded a poll time")
        #expect(!(monitor.lastError ?? "").contains("cancelled"), "\(monitor.lastError ?? "")")
        #expect(monitor.statusSnapshot.lastError == nil, "\(monitor.statusSnapshot.lastError ?? "")")
        let written = statusFile.read()
        #expect(written?.lastError == nil, "\(written?.lastError ?? "")")
        #expect(written?.isRunning == (interruption == .restart))
        // The old poll stopped at Slack: it never read the new run's Beeper.
        #expect(HangingSlack.requests(token: beeperToken).isEmpty, "\(HangingSlack.requests(token: beeperToken))")
    }
}

// MARK: - Slack Client & Google Chat Client Unit Tests

private final class MockChatProtocol: URLProtocol {
    typealias Handler = @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)
    private static let lock = NSLock()
    nonisolated(unsafe) private static var handlers: [String: Handler] = [:]

    static func session(tokens: [String], handler: @escaping Handler) -> URLSession {
        lock.withLock {
            for token in tokens {
                handlers["Bearer \(token)"] = handler
            }
        }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockChatProtocol.self]
        return URLSession(configuration: config)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}
    override func startLoading() {
        let auth = request.value(forHTTPHeaderField: "Authorization") ?? ""
        let handler = Self.lock.withLock { Self.handlers[auth] }
        guard let handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }
}

@Suite struct SlackClientStatusTests {
    @Test func rateLimitedReturns429WithRetryAfter() async throws {
        let token = "slack-429-\(UUID().uuidString)"
        let session = MockChatProtocol.session(tokens: [token]) { req in
            let res = HTTPURLResponse(url: req.url!, statusCode: 429, httpVersion: "HTTP/1.1", headerFields: ["Retry-After": "30"])!
            return (res, Data("rate limit".utf8))
        }
        let client = SlackClient(token: token, session: session)
        await #expect(throws: ChatMonitorError.slack("rate limited (HTTP 429), retry after 30s")) {
            _ = try await client.identity()
        }
    }

    @Test func serverErrorReturnsHTTPStatus() async throws {
        let token = "slack-500-\(UUID().uuidString)"
        let session = MockChatProtocol.session(tokens: [token]) { req in
            let res = HTTPURLResponse(url: req.url!, statusCode: 500, httpVersion: "HTTP/1.1", headerFields: nil)!
            return (res, Data("Internal error".utf8))
        }
        let client = SlackClient(token: token, session: session)
        await #expect(throws: ChatMonitorError.slack("HTTP 500")) {
            _ = try await client.identity()
        }
    }

    @Test func invalidJSONResponseThrowsError() async throws {
        let token = "slack-badjson-\(UUID().uuidString)"
        let session = MockChatProtocol.session(tokens: [token]) { req in
            let res = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!
            return (res, Data("not valid json".utf8))
        }
        let client = SlackClient(token: token, session: session)
        await #expect(throws: ChatMonitorError.slack("invalid JSON response")) {
            _ = try await client.identity()
        }
    }
}

@Suite struct GoogleChatClientRetryTests {
    final class TokenBox: @unchecked Sendable {
        var calls: [(purpose: GoogleAuth.Purpose, forceRefresh: Bool)] = []
    }

    @Test func unauthorizedRefreshesTokenAndRetriesRequest() async throws {
        let tokenBox = TokenBox()
        let initialToken = "gchat-init-\(UUID().uuidString)"
        let refreshedToken = "gchat-fresh-\(UUID().uuidString)"

        let session = MockChatProtocol.session(tokens: [initialToken, refreshedToken]) { req in
            let auth = req.value(forHTTPHeaderField: "Authorization")
            if auth == "Bearer \(initialToken)" {
                let res = HTTPURLResponse(url: req.url!, statusCode: 401, httpVersion: "HTTP/1.1", headerFields: nil)!
                return (res, Data(#"{"error": {"message": "Invalid Credentials"}}"#.utf8))
            } else if auth == "Bearer \(refreshedToken)" {
                let res = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!
                return (res, Data(#"{"spaces": [{"name": "spaces/s1", "displayName": "Engineering"}]}"#.utf8))
            } else {
                let res = HTTPURLResponse(url: req.url!, statusCode: 500, httpVersion: "HTTP/1.1", headerFields: nil)!
                return (res, Data(#"{"error": {"message": "Unexpected Token"}}"#.utf8))
            }
        }

        let client = GoogleChatClient(session: session) { purpose, forceRefresh in
            tokenBox.calls.append((purpose, forceRefresh))
            return forceRefresh ? refreshedToken : initialToken
        }

        let spaces = try await client.spaces()
        #expect(spaces.count == 1)
        #expect(spaces[0].name == "spaces/s1")
        #expect(spaces[0].displayName == "Engineering")

        #expect(tokenBox.calls.count == 2)
        #expect(tokenBox.calls[0].purpose == .chat && tokenBox.calls[0].forceRefresh == false)
        #expect(tokenBox.calls[1].purpose == .chat && tokenBox.calls[1].forceRefresh == true)
    }

    @Test func unauthorizedRetryFailureThrowsError() async throws {
        let token = "gchat-fail-\(UUID().uuidString)"
        let session = MockChatProtocol.session(tokens: [token]) { req in
            let res = HTTPURLResponse(url: req.url!, statusCode: 401, httpVersion: "HTTP/1.1", headerFields: nil)!
            return (res, Data(#"{"error": {"message": "Unauthorized"}}"#.utf8))
        }

        let client = GoogleChatClient(session: session) { _, _ in
            return token
        }

        await #expect(throws: ChatMonitorError.googleChat("Unauthorized")) {
            _ = try await client.spaces()
        }
    }
}
