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

// Guards for credentials written by more than one process: the secrets file
// keeps every writer's change, a saved token or sign-in reaches the running
// app's chat monitor, and the app and the tool judge setup by one rule.

private func scratchDir() throws -> URL {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("homespeaker-creds-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}

private func creds(_ refresh: String, scopes: [String] = []) -> GoogleCredentials {
    GoogleCredentials(clientId: "c", clientSecret: "s", accessToken: "a", refreshToken: refresh, scopes: scopes)
}

// MARK: - The secrets file's lock

/// Each `SecretStore` here has its own queue, so nothing in-process keeps
/// two of them apart: only the `flock`. A BSD flock belongs to an open file
/// description, so two stores in one process contend for it exactly as the
/// app and the tool, in two processes, do.
@Suite struct SecretStoreLockTests {
    @Test func concurrentUpdatesFromSeparateStoresAreNeverLost() throws {
        let url = try scratchDir().appendingPathComponent("secrets.json")
        let stores = (0..<8).map { _ in SecretStore(fileURL: url) }
        let rounds = 200
        DispatchQueue.concurrentPerform(iterations: rounds) { i in
            try? stores[i % stores.count].update { $0.slackToken = ($0.slackToken ?? "") + "x" }
        }
        #expect(SecretStore(fileURL: url).load().slackToken?.count == rounds,
                "every read-modify-write saw the one before it")
    }

    @Test func concurrentWritersOfDifferentKeysAllSurvive() throws {
        let url = try scratchDir().appendingPathComponent("secrets.json")
        let writes: [@Sendable (inout Secrets) -> Void] = [
            { $0.google = creds("home") },
            { $0.googleChat = creds("chat") },
            { $0.slackToken = "xoxp-slack" },
            { $0.oauthClientIdOverride = "client-id" },
            { $0.oauthClientSecretOverride = "client-secret" },
        ]
        // Many rounds, each writer its own store: one lost update in any
        // round leaves a key missing at the end of it.
        for _ in 0..<20 {
            try SecretStore(fileURL: url).clear()
            DispatchQueue.concurrentPerform(iterations: writes.count) { i in
                try? SecretStore(fileURL: url).update(writes[i])
            }
            let s = SecretStore(fileURL: url).load()
            #expect(s.google?.refreshToken == "home")
            #expect(s.googleChat?.refreshToken == "chat")
            #expect(s.slackToken == "xoxp-slack")
            #expect(s.oauthClientIdOverride == "client-id")
            #expect(s.oauthClientSecretOverride == "client-secret")
        }
    }

    @Test func sequentialUpdatesKeepEachOthersKeys() throws {
        let url = try scratchDir().appendingPathComponent("secrets.json")
        let app = SecretStore(fileURL: url)
        let tool = SecretStore(fileURL: url)
        try app.update { $0.google = creds("home") }
        try tool.update { $0.slackToken = "xoxp-1" }
        try app.update { $0.google?.accessToken = "refreshed" }
        try tool.update { $0.slackToken = nil }
        try tool.update { $0.slackToken = "xoxp-2" }
        let s = app.load()
        #expect(s.google?.accessToken == "refreshed")
        #expect(s.slackToken == "xoxp-2")
    }

    /// One store, one call after another, every kind: the lock is never
    /// taken twice by the same store, so none of these waits on itself.
    @Test func oneStoreNeverWaitsOnItself() throws {
        let url = try scratchDir().appendingPathComponent("secrets.json")
        let store = SecretStore(fileURL: url)
        try store.save(Secrets(slackToken: "a"))
        try store.update { $0.slackToken = ($0.slackToken ?? "") + "b" }
        #expect(store.load().slackToken == "ab")
        try store.clear()
        #expect(store.load() == Secrets())
        try store.update { $0.slackToken = "c" }
        #expect(store.load().slackToken == "c")
    }

    @Test func theLockFileSitsBesideTheSecretsAndIsOwnerOnly() throws {
        let dir = try scratchDir()
        let store = SecretStore(fileURL: dir.appendingPathComponent("HomeSpeaker/secrets.json"))
        #expect(store.lockURL.lastPathComponent == "secrets.json.lock")
        #expect(store.lockURL.deletingLastPathComponent() == store.fileURL.deletingLastPathComponent())
        try store.update { $0.slackToken = "x" }
        let lockPerms = try FileManager.default.attributesOfItem(atPath: store.lockURL.path)[.posixPermissions] as? Int
        #expect(lockPerms == 0o600)
        let filePerms = try FileManager.default.attributesOfItem(atPath: store.fileURL.path)[.posixPermissions] as? Int
        #expect(filePerms == 0o600)
        let dirPerms = try FileManager.default.attributesOfItem(
            atPath: store.fileURL.deletingLastPathComponent().path)[.posixPermissions] as? Int
        #expect(dirPerms == 0o700)
    }

    @Test func clearingWhereNothingWasEverSavedCreatesNothing() throws {
        let dir = try scratchDir().appendingPathComponent("never")
        let store = SecretStore(fileURL: dir.appendingPathComponent("secrets.json"))
        try store.clear()
        #expect(!FileManager.default.fileExists(atPath: dir.path))
    }

    /// Held by "another process" (a separate descriptor), the lock makes a
    /// writer wait; released, the writer goes ahead and keeps what the
    /// holder wrote.
    @Test func aWriterWaitsForTheHolder() async throws {
        let url = try scratchDir().appendingPathComponent("secrets.json")
        let store = SecretStore(fileURL: url)
        try store.save(Secrets(slackToken: "before"))
        let fd = open(store.lockURL.path, O_RDWR | O_CREAT, 0o600)
        #expect(fd >= 0)
        #expect(flock(fd, LOCK_EX) == 0)
        let done = Posted()
        let writer = Task.detached {
            try? SecretStore(fileURL: url).update { $0.google = creds("home") }
            done.add(true)
        }
        try await Task.sleep(for: .milliseconds(300))
        #expect(done.values.isEmpty, "the update waits while the lock is held")
        // The holder's own write, made while it held the lock.
        let data = try JSONEncoder().encode(Secrets(slackToken: "holder"))
        try data.write(to: url, options: .atomic)
        flock(fd, LOCK_UN)
        close(fd)
        await writer.value
        #expect(done.values == [true])
        let s = store.load()
        #expect(s.slackToken == "holder", "read after the holder let go, so its write is kept")
        #expect(s.google?.refreshToken == "home")
    }
}

// MARK: - The setup rules

@Suite struct SetupProblemsTests {
    private func config(slack: Bool = false, chat: Bool = false, source: ChatMonitorConfig.GoogleChatSource = .auto) -> ChatMonitorConfig {
        ChatMonitorConfig(slackEnabled: slack, googleChatEnabled: chat, googleChatSource: source)
    }

    @Test func everySourceOffHasNoProblems() {
        #expect(ChatMonitorService.setupProblems(config: config(), hasSlackToken: false, hasChatScopes: false, gwsInstalled: false).isEmpty)
    }

    @Test func slackOnWithoutATokenIsAProblemAndWithOneIsNot() {
        #expect(ChatMonitorService.setupProblems(config: config(slack: true), hasSlackToken: false, hasChatScopes: false, gwsInstalled: false)
                == [.slackTokenMissing])
        #expect(ChatMonitorService.setupProblems(config: config(slack: true), hasSlackToken: true, hasChatScopes: false, gwsInstalled: false)
                .isEmpty)
    }

    @Test func googleChatFollowsChooseChatSource() {
        let cases: [(ChatMonitorConfig.GoogleChatSource, Bool, Bool, [ChatMonitorError])] = [
            (.api, false, true, [.googleChatScopeMissing]),
            (.api, true, false, []),
            (.gws, true, false, [.gwsNotInstalled]),
            (.gws, false, true, []),
            (.auto, false, false, [.noGoogleChatSource]),
            (.auto, true, false, []),
            (.auto, false, true, []),
        ]
        for (source, scopes, gws, expected) in cases {
            let problems = ChatMonitorService.setupProblems(
                config: config(chat: true, source: source), hasSlackToken: false, hasChatScopes: scopes, gwsInstalled: gws)
            #expect(problems == expected, "\(source) scopes:\(scopes) gws:\(gws)")
        }
    }

    @Test func slackComesBeforeGoogleChatAndAnOffSourceSaysNothing() {
        #expect(ChatMonitorService.setupProblems(config: config(slack: true, chat: true, source: .gws),
                                                 hasSlackToken: false, hasChatScopes: false, gwsInstalled: false)
                == [.slackTokenMissing, .gwsNotInstalled])
        #expect(ChatMonitorService.setupProblems(config: config(slack: false, chat: false, source: .api),
                                                 hasSlackToken: false, hasChatScopes: false, gwsInstalled: false).isEmpty)
    }

    /// start() goes by the same rules: Google Chat on through the API with
    /// no Chat sign-in says so and does not start. (No gws lookup and no
    /// network: the API is the only way asked for.)
    @Test @MainActor func startSaysWhatSetupProblemsSays() throws {
        let dir = try scratchDir()
        let secrets = SecretStore(fileURL: dir.appendingPathComponent("s.json"))
        let manager = ConfigManager(configPath: dir.appendingPathComponent("c.json"),
                                    historyPath: dir.appendingPathComponent("h.json"), secrets: secrets)
        manager.config.effectiveChatMonitor = config(chat: true, source: .api)
        let service = ChatMonitorService(configManager: manager, secrets: secrets)
        service.start()
        defer { service.stop() }
        #expect(!service.isRunning)
        #expect(service.lastError == ChatMonitorError.googleChatScopeMissing.localizedDescription)
    }
}

// MARK: - The credentials-changed notice

/// A monitor that starts only when the secrets let it, by the monitor's
/// own rules: what `ChatMonitorService.start()` does, without the network.
@MainActor
final class GatedChatMonitor: ChatMonitorControlling {
    var isRunning = false
    var calls: [String] = []
    let config: ConfigManager
    let secrets: SecretStore
    init(config: ConfigManager, secrets: SecretStore) {
        self.config = config
        self.secrets = secrets
    }
    func start() {
        calls.append("start")
        guard !isRunning else { return }
        let s = secrets.load()
        let problems = ChatMonitorService.setupProblems(
            config: config.config.effectiveChatMonitor, hasSlackToken: !(s.slackToken?.isEmpty ?? true),
            hasChatScopes: s.hasChatAccess, gwsInstalled: false)
        isRunning = config.config.effectiveChatMonitor.anySourceEnabled && problems.isEmpty
    }
    func stop() {
        calls.append("stop")
        isRunning = false
    }
}

@MainActor
@Suite(.serialized) struct CredentialsChangedNoticeTests {
    private func manager(_ secrets: SecretStore) throws -> ConfigManager {
        let dir = try scratchDir()
        return ConfigManager(configPath: URL(fileURLWithPath: "/fake/.gemini/speaker_broadcast.json"),
                             historyPath: dir.appendingPathComponent("history.json"), secrets: secrets, fileSystem: MemoryFiles())
    }

    @Test func theDecision() {
        #expect(CredentialsChangedNotice.decide(isRunning: true, anySourceEnabled: true) == .restart)
        #expect(CredentialsChangedNotice.decide(isRunning: true, anySourceEnabled: false) == .restart)
        #expect(CredentialsChangedNotice.decide(isRunning: false, anySourceEnabled: true) == .start)
        #expect(CredentialsChangedNotice.decide(isRunning: false, anySourceEnabled: false) == .none)
    }

    @Test func applyRestartsARunningMonitorStartsAWaitingOneAndLeavesAnOffOneAlone() throws {
        let secrets = SecretStore(fileURL: try scratchDir().appendingPathComponent("secrets.json"))
        let manager = try manager(secrets)
        let running = FakeChatMonitor(running: true)
        CredentialsChangedNotice.apply(config: manager, monitor: running)
        #expect(running.calls == ["stop", "start"])

        manager.config.effectiveChatMonitor.slackEnabled = true
        let waiting = FakeChatMonitor(running: false)
        CredentialsChangedNotice.apply(config: manager, monitor: waiting)
        #expect(waiting.calls == ["start"])

        manager.config.effectiveChatMonitor.slackEnabled = false
        let off = FakeChatMonitor(running: false)
        CredentialsChangedNotice.apply(config: manager, monitor: off)
        #expect(off.calls.isEmpty, "every source off: nothing to start")
    }

    @Test func applyRereadsTheLogin() throws {
        let secrets = SecretStore(fileURL: try scratchDir().appendingPathComponent("secrets.json"))
        let manager = try manager(secrets)
        #expect(!manager.isConnectedToGoogle)
        var signedIn = creds("r")
        signedIn.email = "someone@example.com"
        try secrets.update { $0.google = signedIn }
        CredentialsChangedNotice.apply(config: manager, monitor: FakeChatMonitor(running: false))
        #expect(manager.isConnectedToGoogle, "a `--sign-in` from the terminal shows in the menu bar")
        #expect(manager.googleEmail == "someone@example.com")
    }

    /// The whole path, through a real distributed notification under a name
    /// of its own: Slack is on with no token, so the monitor is not running;
    /// the tool saves a token and posts; the app hears it and the monitor
    /// starts.
    @Test func aSavedSlackTokenStartsAMonitorThatWasWaitingForIt() async throws {
        let secrets = SecretStore(fileURL: try scratchDir().appendingPathComponent("secrets.json"))
        let manager = try manager(secrets)
        manager.config.effectiveChatMonitor.slackEnabled = true
        let monitor = GatedChatMonitor(config: manager, secrets: secrets)
        monitor.start()
        #expect(!monitor.isRunning, "no token: Slack cannot run")

        let name = Notification.Name("com.vitruviansoftware.homespeaker.test.credentials-changed.\(UUID().uuidString)")
        let token = CredentialsChangedNotice.listen(name: name, config: manager, monitor: monitor)
        defer { DistributedNotificationCenter.default().removeObserver(token) }

        try secrets.update { $0.slackToken = "xoxp-new" }
        CredentialsChangedNotice.post(name: name)
        for _ in 0..<100 where !monitor.isRunning { try await Task.sleep(for: .milliseconds(50)) }
        #expect(monitor.isRunning)
        #expect(monitor.calls == ["start", "start"])
    }

    @Test func aPostedNoticeReachesTheListener() async throws {
        let name = Notification.Name("com.vitruviansoftware.homespeaker.test.credentials-changed.\(UUID().uuidString)")
        var heard = 0
        let token = CredentialsChangedNotice.listen(name: name) { heard += 1 }
        defer { DistributedNotificationCenter.default().removeObserver(token) }
        CredentialsChangedNotice.post(name: name)
        CredentialsChangedNotice.post(name: name)
        for _ in 0..<100 where heard < 2 { try await Task.sleep(for: .milliseconds(50)) }
        #expect(heard == 2)
    }

    /// The two notices are two names: a sign-in never reads as a sign-out.
    @Test func itIsNotTheSignOutNotice() {
        #expect(CredentialsChangedNotice.notificationName(for: .app()) != SignOutNotice.notificationName(for: .app()))
    }
}
