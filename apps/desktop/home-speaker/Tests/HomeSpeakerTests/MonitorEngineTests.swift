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

// The chat monitor reads Google Chat with the sign-in of the engine it is
// given, not the app's. Without that, the extension's monitor would read Chat
// as whoever the standalone app is signed in as, and its own sign-in would be
// ignored.
//
// Nothing here reaches the network, and nothing reads or writes the person's
// real files: the engine is on a temporary extension profile with a message
// prefix nothing else listens on, and every request, Google Chat's and the
// sign-in's, goes to a stand-in session that answers in this process.

private func scratchDir() throws -> URL {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("homespeaker-monitor-engine-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}

/// This Mac's speech, made silent.
private struct SilentLocal: LocalSpeaking {
    func speak(_ text: String, voiceID: String) async throws {}
}

/// A session that answers every request in this process, and remembers who
/// asked for what and with which bearer token. Google Chat gets one empty
/// space; anything else gets a 500, which the test would notice.
private final class StandInChat: URLProtocol {
    struct Request: Equatable {
        let host: String
        let path: String
        let bearer: String?
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var seen: [Request] = []

    static var requests: [Request] { lock.withLock { seen } }

    static var session: URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StandInChat.self]
        return URLSession(configuration: configuration)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        let url = request.url!
        let bearer = request.value(forHTTPHeaderField: "Authorization").map {
            $0.hasPrefix("Bearer ") ? String($0.dropFirst("Bearer ".count)) : $0
        }
        Self.lock.withLock { Self.seen.append(Request(host: url.host ?? "", path: url.path, bearer: bearer)) }

        let isChat = url.host == "chat.googleapis.com"
        let body: String
        if isChat, url.path.hasSuffix("/messages") {
            body = #"{"messages":[]}"#
        } else if isChat, url.path == "/v1/spaces" {
            body = #"{"spaces":[{"name":"spaces/AAAA","displayName":"Team"}]}"#
        } else {
            body = "{}"
        }
        let response = HTTPURLResponse(
            url: url, statusCode: isChat ? 200 : 500, httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
}

@MainActor
@Suite struct MonitorEngineTests {
    @Test func theMonitorReadsChatWithItsEnginesSignIn() async throws {
        let root = try scratchDir()
        defer { try? FileManager.default.removeItem(at: root) }
        let profile = HomeSpeakerProfile.extension(
            dataFolder: root.appendingPathComponent("data"), toolFolder: nil,
            messagePrefix: "test.\(UUID().uuidString).homespeaker")
        // Stop before an engine is built if any of the profile's files is
        // not in the scratch folder: it would be someone's real one.
        for url in [profile.settingsURL, profile.historyURL, profile.secretsURL, profile.monitorStatusURL] {
            try #require(url.path.hasPrefix(root.path + "/"), "\(url.path) is outside the scratch folder")
        }

        let session = StandInChat.session
        let engine = HomeSpeakerEngine(profile: profile, session: session, local: SilentLocal())

        // The extension's own Chat login, with a token that is good for a
        // day, so nothing needs refreshing.
        let token = "extension-chat-token-\(UUID().uuidString)"
        try engine.secrets.save(Secrets(googleChat: GoogleCredentials(
            clientId: "test-client", clientSecret: "test-secret",
            accessToken: token, refreshToken: "test-refresh",
            expiry: Date().addingTimeInterval(86_400),
            scopes: GoogleAuth.identityScopes + GoogleAuth.chatScopes,
            userId: "1234567890", email: "extension@example.test")))
        engine.config.config.effectiveChatMonitor = ChatMonitorConfig(
            slackEnabled: false, googleChatEnabled: true, googleChatSource: .api)

        let monitor = ChatMonitorService(
            configManager: engine.config, secrets: engine.secrets, home: engine.home,
            announcer: engine.announcer, statusFile: ChatMonitorStatusFile(url: profile.monitorStatusURL),
            auth: engine.auth, chatSession: session)
        monitor.start()
        defer { monitor.stop() }
        try #require(monitor.isRunning, "the monitor did not start: \(monitor.lastError ?? "no error shown")")
        #expect(monitor.googleChatVia == "api")

        // The first poll lists the spaces, then asks each for its messages.
        let polled = {
            StandInChat.requests.contains { $0.host == "chat.googleapis.com" && $0.path.hasSuffix("/messages") }
        }
        for _ in 0..<200 where !polled() { try await Task.sleep(for: .milliseconds(25)) }
        try #require(polled(), "the monitor never read Google Chat")

        let chat = StandInChat.requests.filter { $0.host == "chat.googleapis.com" }
        #expect(!chat.isEmpty)
        #expect(chat.allSatisfy { $0.bearer == token },
                "Chat was read with \(chat.map { $0.bearer ?? "no token" }), not the engine's own login")
        #expect(StandInChat.requests.allSatisfy { $0.host == "chat.googleapis.com" },
                "something other than Google Chat was asked: \(StandInChat.requests.map(\.host))")
    }
}
