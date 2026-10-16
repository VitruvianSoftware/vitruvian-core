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

// Comparing the app and the extension, and copying one into the other
// (design sections 7.4, 7.5 and 7.7).
//
// Both sides are profiles over a new temporary folder: an app-shaped one
// whose every path is inside it, and an extension one. No test reads or
// writes this Mac's real settings, sign-ins or history, and no request
// leaves the process: Google's revoke address is answered by a stand-in.

private func scratchDir() throws -> URL {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("homespeaker-door-copy-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}

private func testPrefix() -> String { "test.\(UUID().uuidString).homespeaker" }

/// The app's files, but all inside `root`.
private func appShaped(_ root: URL) throws -> HomeSpeakerProfile {
    let profile = HomeSpeakerProfile(
        door: .app,
        settingsURL: root.appendingPathComponent("gemini/speaker_broadcast.json"),
        historyURL: root.appendingPathComponent("gemini/speaker_history.json"),
        secretsURL: root.appendingPathComponent("HomeSpeaker/secrets.json"),
        messagePrefix: testPrefix(), liveLockURL: nil, toolFolder: nil)
    try requireInside(root, profile)
    return profile
}

private func extensionShaped(_ root: URL) throws -> HomeSpeakerProfile {
    let profile = HomeSpeakerProfile.extension(
        dataFolder: root.appendingPathComponent("data"), toolFolder: nil, messagePrefix: testPrefix())
    try requireInside(root, profile)
    return profile
}

/// Stops the test before anything is read or written if a path is not in
/// the scratch folder: it would be someone's real file.
private func requireInside(_ root: URL, _ profile: HomeSpeakerProfile) throws {
    for url in [profile.settingsURL, profile.historyURL, profile.secretsURL, profile.monitorStatusURL] {
        try #require(url.path.hasPrefix(root.path + "/"), "\(url.path) is outside the scratch folder")
    }
}

/// Real-looking tokens, unique to each test, so a leak is easy to find.
private struct Planted {
    let id = UUID().uuidString
    var slack: String { "xoxp-secret-123-\(id)" }
    var homeRefresh: String { "1//secret-home-\(id)" } // gitleaks:allow (made-up test token: a UUID behind a fake prefix)
    var chatRefresh: String { "1//secret-chat-\(id)" }
    var homeAccess: String { "ya29.secret-home-access-\(id)" }
    var chatAccess: String { "ya29.secret-chat-access-\(id)" }
    var clientSecret: String { "GOCSPX-secret-\(id)" }
    var ownClientSecret: String { "GOCSPX-own-secret-\(id)" }

    var all: [String] {
        [slack, homeRefresh, chatRefresh, homeAccess, chatAccess, clientSecret, ownClientSecret, "xoxp-secret-123", "1//secret"] // gitleaks:allow (made-up test tokens)
    }

    var secrets: Secrets {
        Secrets(
            google: GoogleCredentials(
                clientId: "client-\(id)", clientSecret: clientSecret,
                accessToken: homeAccess, refreshToken: homeRefresh,
                expiry: Date(timeIntervalSince1970: 2_000_000_000), scopes: [GoogleAuth.homeScope],
                userId: "1234", email: "person@example.test"),
            googleChat: GoogleCredentials(
                clientId: "client-\(id)", clientSecret: clientSecret,
                accessToken: chatAccess, refreshToken: chatRefresh,
                expiry: Date(timeIntervalSince1970: 2_000_000_000), scopes: GoogleAuth.chatScopes,
                userId: "1234", email: "person@example.test"),
            slackToken: slack,
            oauthClientIdOverride: "own-client-\(id)", oauthClientSecretOverride: ownClientSecret)
    }
}

private func setUpConfig(home: String = "Lake House") -> SpeakerConfig {
    var config = SpeakerConfig(
        defaultTarget: "kitchen", structureId: "structure-1", structureName: home,
        targets: [
            "kitchen": SpeakerDevice(id: "d1", type: "SPEAKER", name: "Kitchen"),
            "office": SpeakerDevice(id: "d2", type: "SPEAKER", name: "Office"),
            "whole_home": SpeakerDevice(id: "structure@1", type: "STRUCTURE", name: "Whole home"),
        ],
        quietHoursEnabled: true, quietHoursStart: "22:00", quietHoursEnd: "07:00",
        chatMonitor: ChatMonitorConfig(slackEnabled: true, googleChatEnabled: false))
    config.speakLocal = true
    return config
}

private func entries(_ count: Int, from start: Int, prefix: String) -> [BroadcastLogItem] {
    (0..<count).map { i in
        BroadcastLogItem(
            timestamp: Date(timeIntervalSince1970: TimeInterval(1_000_000 + (start + i) * 60)),
            text: "\(prefix) \(start + i)", targetName: "Kitchen", source: "Test")
    }
}

private func writeHistory(_ items: [BroadcastLogItem], to profile: HomeSpeakerProfile) throws {
    try FileManager.default.createDirectory(
        at: profile.historyURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    try JSONEncoder().encode(items).write(to: profile.historyURL)
}

/// One side, fully set up: settings, every kind of sign-in, and history.
private func fill(_ profile: HomeSpeakerProfile, _ planted: Planted, history: [BroadcastLogItem]) throws {
    try SpeakerConfigFile(url: profile.settingsURL).write(setUpConfig())
    try SecretStore(fileURL: profile.secretsURL).save(planted.secrets)
    try writeHistory(history, to: profile)
}

private func bytes(_ url: URL) -> Data? { try? Data(contentsOf: url) }

// MARK: - The stand-in for Google's revoke address

/// Answers every request in this process with 200, and remembers each one's
/// address and form body. Requests are told apart by the planted token in
/// the body, so tests running at once never see each other's.
private final class StandInGoogle: URLProtocol {
    struct Request: Equatable {
        let url: URL
        let body: String
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var seen: [Request] = []

    static var requests: [Request] { lock.withLock { seen } }

    static var session: URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StandInGoogle.self]
        return URLSession(configuration: configuration)
    }

    /// Revoke requests carrying `token`.
    static func revokes(of token: String) -> [Request] {
        requests.filter { $0.url == GoogleAuth.revokeEndpoint && $0.body == "token=\(token.formEncoded)" }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        let url = request.url!
        Self.lock.withLock { Self.seen.append(Request(url: url, body: Self.body(of: request))) }
        let response = HTTPURLResponse(
            url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data("{}".utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    private static func body(of request: URLRequest) -> String {
        if let data = request.httpBody { return String(decoding: data, as: UTF8.self) }
        guard let stream = request.httpBodyStream else { return "" }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let n = stream.read(&buffer, maxLength: buffer.count)
            guard n > 0 else { break }
            data.append(buffer, count: n)
        }
        return String(decoding: data, as: UTF8.self)
    }
}

/// This Mac's speech, made silent.
private struct QuietLocal: LocalSpeaking {
    func speak(_ text: String, voiceID: String) async throws {}
}

// MARK: - The snapshot

@Suite struct DoorSnapshotTests {
    @Test func aSnapshotHoldsNoToken() throws {
        let root = try scratchDir()
        defer { try? FileManager.default.removeItem(at: root) }
        let profile = try appShaped(root)
        let planted = Planted()
        try fill(profile, planted, history: entries(3, from: 0, prefix: "said"))

        let snapshot = DoorSnapshot(profile: profile)

        // Every stored property, by name and type. A new one must be added
        // here on purpose, and none may be able to carry a login.
        let properties = Mirror(reflecting: snapshot).children.map { ($0.label ?? "?", "\(type(of: $0.value))") }
        let expected: [(String, String)] = [
            ("settingsRead", "ConfigFileRead"), ("settingsChanged", "Optional<Date>"),
            ("googleEmail", "Optional<String>"), ("hasHomeLogin", "Bool"), ("hasChatLogin", "Bool"),
            ("hasSlackToken", "Bool"), ("hasOwnClient", "Bool"),
            ("homeName", "Optional<String>"), ("speakerCount", "Int"), ("defaultSpeaker", "Optional<String>"),
            ("outputs", "Outputs"), ("quietHours", "Optional<String>"), ("chatSources", "Array<String>"),
            ("historyCount", "Int"),
        ]
        #expect(properties.map(\.0) == expected.map(\.0))
        #expect(properties.map(\.1) == expected.map(\.1))
        for (_, typeName) in properties {
            #expect(!typeName.contains("Secrets") && !typeName.contains("GoogleCredentials"))
        }
        let everything = String(reflecting: snapshot) + "\(snapshot)"
        for token in planted.all {
            #expect(!everything.contains(token), "the snapshot shows a token")
        }

        // And what it does say.
        #expect(snapshot.googleEmail == "person@example.test")
        #expect(snapshot.hasHomeLogin && snapshot.hasChatLogin && snapshot.hasSlackToken && snapshot.hasOwnClient)
        #expect(snapshot.homeName == "Lake House")
        #expect(snapshot.speakerCount == 2, "the whole-home group is not a speaker")
        #expect(snapshot.defaultSpeaker == "Kitchen")
        #expect(snapshot.outputs == .both)
        #expect(snapshot.quietHours == "22:00 to 07:00")
        #expect(snapshot.chatSources == ["Slack"])
        #expect(snapshot.historyCount == 3)
        #expect(snapshot.settingsChanged != nil)
        #expect(snapshot.isSetUp)
    }

    @Test func aSnapshotWritesNothing() throws {
        let root = try scratchDir()
        defer { try? FileManager.default.removeItem(at: root) }
        let profile = try extensionShaped(root)

        let snapshot = DoorSnapshot(profile: profile)

        #expect(snapshot.settingsRead == .missing)
        #expect(!snapshot.isSetUp)
        #expect(snapshot.historyCount == 0)
        for url in [profile.settingsURL, profile.secretsURL, profile.historyURL] {
            #expect(!FileManager.default.fileExists(atPath: url.path), "\(url.lastPathComponent) was written")
        }
    }
}

// MARK: - Which way to copy (design 7.4, step 2)

@Suite struct DoorSuggestionTests {
    private let empty = DoorSnapshot()
    private func setUp(changed: Date?) -> DoorSnapshot {
        DoorSnapshot(settingsChanged: changed, hasHomeLogin: true, speakerCount: 2)
    }

    @Test func suggestCopyWhenTheChosenIsEmpty() {
        #expect(DoorCopy.suggest(chosen: empty, other: setUp(changed: Date())) == .copyFromOther)
        let speakersOnly = DoorSnapshot(speakerCount: 1)
        #expect(DoorCopy.suggest(chosen: empty, other: speakersOnly) == .copyFromOther)
    }

    @Test func suggestKeepWhenOnlyTheChosenIsSetUp() {
        #expect(DoorCopy.suggest(chosen: setUp(changed: nil), other: empty) == .keep)
        #expect(DoorCopy.suggest(chosen: empty, other: empty) == .keep, "nothing on either side to copy")
    }

    @Test func suggestTheNewerWhenBothAre() {
        let older = setUp(changed: Date(timeIntervalSince1970: 1_000))
        let newer = setUp(changed: Date(timeIntervalSince1970: 2_000))
        #expect(DoorCopy.suggest(chosen: older, other: newer) == .copyFromOther)
        #expect(DoorCopy.suggest(chosen: newer, other: older) == .keep)
        #expect(DoorCopy.suggest(chosen: newer, other: newer) == .keep, "a tie keeps what the chosen one has")
    }
}

// MARK: - The copy (design 7.5)

@Suite struct DoorCopyTests {
    @Test func copyCopiesSettingsSecretsAndHistory() throws {
        let root = try scratchDir()
        defer { try? FileManager.default.removeItem(at: root) }
        let app = try appShaped(root)
        let ext = try extensionShaped(root)
        let planted = Planted()
        let said = Array(entries(4, from: 0, prefix: "app").reversed())
        try fill(app, planted, history: said)

        let report = try DoorCopy.copy(from: app, to: ext)

        #expect(SpeakerConfigFile(url: ext.settingsURL).read() == .loaded(setUpConfig()))
        #expect(SecretStore(fileURL: ext.secretsURL).load() == planted.secrets)
        #expect(BroadcastHistory(fileURL: ext.historyURL).load() == said)
        #expect(report.settingsCopied)
        #expect(report.historyCount == 4)
        #expect(report.historyAdded == 4)
        #expect(DoorSnapshot(profile: ext).isSetUp)
    }

    @Test func theDestinationKeepsKeysItDoesNotKnow() throws {
        let root = try scratchDir()
        defer { try? FileManager.default.removeItem(at: root) }
        let app = try appShaped(root)
        let ext = try extensionShaped(root)
        try fill(ext, Planted(), history: [])
        // The app's settings file is shared with the phone and the CLI.
        let foreign = #"{"enabled": true, "default_target": "", "structure_id": "", "targets": {}, "phone_only": 7}"#
        try FileManager.default.createDirectory(
            at: app.settingsURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(foreign.utf8).write(to: app.settingsURL)

        _ = try DoorCopy.copy(from: ext, to: app)

        let object = try JSONSerialization.jsonObject(with: Data(contentsOf: app.settingsURL)) as? [String: Any]
        #expect(object?["phone_only"] as? Int == 7)
        #expect(SpeakerConfigFile(url: app.settingsURL).read() == .loaded(setUpConfig()))
    }

    @Test func theSourceIsUntouched() throws {
        let root = try scratchDir()
        defer { try? FileManager.default.removeItem(at: root) }
        let app = try appShaped(root)
        let ext = try extensionShaped(root)
        try fill(app, Planted(), history: entries(20, from: 0, prefix: "app"))
        try fill(ext, Planted(), history: entries(20, from: 10, prefix: "ext"))
        let files = [app.settingsURL, app.secretsURL, app.historyURL]
        let before = files.map(bytes)
        #expect(before.allSatisfy { $0 != nil })

        _ = try DoorCopy.copy(from: app, to: ext)

        #expect(files.map(bytes) == before, "the source's files changed")
    }

    @Test func historyIsMergedNotReplaced() throws {
        let root = try scratchDir()
        defer { try? FileManager.default.removeItem(at: root) }
        let app = try appShaped(root)
        let ext = try extensionShaped(root)
        // 20 each, 5 of them the same entries: 35 different, of which the
        // newest 30 stay.
        let shared = entries(5, from: 100, prefix: "shared")
        let appOnly = entries(15, from: 0, prefix: "app")
        let extOnly = entries(15, from: 50, prefix: "ext")
        try fill(app, Planted(), history: (appOnly + shared).reversed())
        try fill(ext, Planted(), history: (extOnly + shared).reversed())

        let report = try DoorCopy.copy(from: app, to: ext)

        let merged = BroadcastHistory(fileURL: ext.historyURL).load()
        #expect(merged.count == 30)
        #expect(Set(merged.map(\.id)).count == merged.count, "an entry is there twice")
        #expect(merged == Array((appOnly + extOnly + shared).sorted { $0.timestamp > $1.timestamp }.prefix(30)))
        #expect(merged.map(\.timestamp) == merged.map(\.timestamp).sorted(by: >), "not newest first")
        #expect(report.historyCount == 30)
        #expect(report.historyAdded == 10, "the app's 10 newest that this side did not have")
    }

    @Test func anUnreadableDestinationStopsTheCopy() throws {
        let root = try scratchDir()
        defer { try? FileManager.default.removeItem(at: root) }
        let app = try appShaped(root)
        let ext = try extensionShaped(root)
        try fill(app, Planted(), history: entries(3, from: 0, prefix: "app"))
        try FileManager.default.createDirectory(
            at: ext.settingsURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("{ not json".utf8).write(to: ext.settingsURL)

        #expect(throws: ConfigFileError.self) { try DoorCopy.copy(from: app, to: ext) }

        #expect(bytes(ext.settingsURL) == Data("{ not json".utf8), "the unreadable file was written over")
        #expect(!FileManager.default.fileExists(atPath: ext.secretsURL.path), "sign-ins were copied anyway")
        #expect(!FileManager.default.fileExists(atPath: ext.historyURL.path), "history was copied anyway")
    }

    @Test func anUnreadableSourceSignInFileStopsTheCopy() throws {
        let root = try scratchDir()
        defer { try? FileManager.default.removeItem(at: root) }
        let app = try appShaped(root)
        let ext = try extensionShaped(root)
        let planted = Planted()
        try fill(ext, planted, history: [])
        try SpeakerConfigFile(url: app.settingsURL).write(setUpConfig())
        try FileManager.default.createDirectory(
            at: app.secretsURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("{ broken".utf8).write(to: app.secretsURL)
        let settingsBefore = bytes(ext.settingsURL)

        #expect(throws: DoorCopyError.self) { try DoorCopy.copy(from: app, to: ext) }

        #expect(SecretStore(fileURL: ext.secretsURL).load() == planted.secrets, "this side's sign-ins were lost")
        #expect(bytes(ext.settingsURL) == settingsBefore)
    }

    @Test func theReportNamesNoToken() throws {
        let root = try scratchDir()
        defer { try? FileManager.default.removeItem(at: root) }
        let app = try appShaped(root)
        let ext = try extensionShaped(root)
        let planted = Planted()
        try fill(app, planted, history: entries(2, from: 0, prefix: "app"))

        let report = try DoorCopy.copy(from: app, to: ext)

        #expect(!report.lines.isEmpty)
        let text = report.lines.joined(separator: "\n") + String(reflecting: report)
        for token in planted.all {
            #expect(!text.contains(token), "the report shows a token")
        }
        // It says what came, in words.
        #expect(report.lines.contains { $0.contains("Google Home") && $0.contains("person@example.test") })
        #expect(report.lines.contains { $0.contains("Slack") })
        #expect(report.lines.contains(DoorCopy.copyNote))
    }

    @Test func theCopiedSecretsAre0600() throws {
        let root = try scratchDir()
        defer { try? FileManager.default.removeItem(at: root) }
        let app = try appShaped(root)
        let ext = try extensionShaped(root)
        try fill(app, Planted(), history: [])

        _ = try DoorCopy.copy(from: app, to: ext)

        let mode = try FileManager.default.attributesOfItem(atPath: ext.secretsURL.path)[.posixPermissions] as? Int
        #expect(mode == 0o600)
    }
}

// MARK: - Signing the quiet side out (design 7.7)

@MainActor
@Suite struct QuietSignOutTests {
    @Test func theQuietSideNeverRevokesASharedLogin() async throws {
        let root = try scratchDir()
        defer { try? FileManager.default.removeItem(at: root) }
        let active = try appShaped(root)
        let quiet = try extensionShaped(root)
        let planted = Planted()
        try fill(active, planted, history: [])
        _ = try DoorCopy.copy(from: active, to: quiet)
        let activeSecrets = try #require(bytes(active.secretsURL))

        // The two hold the same logins: the quiet side signs out here only.
        let engine = HomeSpeakerEngine(profile: quiet, session: StandInGoogle.session, local: QuietLocal())
        let out = await engine.signOut(chatOnly: false, otherSecrets: SecretStore(fileURL: active.secretsURL).load())

        #expect(out.exitCode == 0)
        #expect(StandInGoogle.revokes(of: planted.homeRefresh).isEmpty, "the shared Home login was revoked at Google")
        #expect(StandInGoogle.revokes(of: planted.chatRefresh).isEmpty, "the shared Chat login was revoked at Google")
        #expect(engine.secrets.load().google == nil && engine.secrets.load().googleChat == nil, "still signed in here")
        #expect(bytes(active.secretsURL) == activeSecrets, "the active side's sign-ins changed")

        // Logins the other side does not hold are revoked, as always.
        let own = Planted()
        try engine.secrets.save(own.secrets)
        let separate = await engine.signOut(chatOnly: false, otherSecrets: SecretStore(fileURL: active.secretsURL).load())
        #expect(separate.exitCode == 0)
        #expect(StandInGoogle.revokes(of: own.homeRefresh).count == 1)
        #expect(StandInGoogle.revokes(of: own.chatRefresh).count == 1)

        // With no other side at all, too.
        let alone = Planted()
        try engine.secrets.save(alone.secrets)
        _ = await engine.signOut(chatOnly: true, otherSecrets: nil)
        #expect(StandInGoogle.revokes(of: alone.chatRefresh).count == 1)
        #expect(StandInGoogle.revokes(of: alone.homeRefresh).isEmpty, "--chat signs out of Chat only")
    }

    @Test func aPartlySharedSignOutRevokesOnlyTheUnshared() async throws {
        let root = try scratchDir()
        defer { try? FileManager.default.removeItem(at: root) }
        let active = try appShaped(root)
        let quiet = try extensionShaped(root)
        // The two share the Home login; the Chat login is the quiet side's own.
        let shared = Planted()
        let own = Planted()
        try SecretStore(fileURL: active.secretsURL).save(Secrets(google: shared.secrets.google))
        let activeSecrets = try #require(bytes(active.secretsURL))
        let engine = HomeSpeakerEngine(profile: quiet, session: StandInGoogle.session, local: QuietLocal())
        try engine.secrets.save(Secrets(google: shared.secrets.google, googleChat: own.secrets.googleChat))

        let out = await engine.signOut(chatOnly: false, otherSecrets: SecretStore(fileURL: active.secretsURL).load())

        #expect(out.exitCode == 0)
        #expect(StandInGoogle.revokes(of: shared.homeRefresh).isEmpty, "the shared Home login was revoked at Google")
        #expect(StandInGoogle.revokes(of: own.chatRefresh).count == 1, "the unshared Chat login was left valid at Google")
        #expect(engine.secrets.load().google == nil && engine.secrets.load().googleChat == nil, "still signed in here")
        #expect(bytes(active.secretsURL) == activeSecrets, "the active side's sign-ins changed")
    }
}
