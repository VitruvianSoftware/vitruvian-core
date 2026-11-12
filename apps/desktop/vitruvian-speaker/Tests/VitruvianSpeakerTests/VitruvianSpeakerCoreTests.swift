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

// swift-testing (not XCTest): XCTest is absent from the Command Line Tools
// toolchain, so `swift test` only works here with the Testing framework.

@Suite struct SpeechCleaningTests {
    @Test func markdownIsStripped() {
        let input = "**Problem:** The build failed.\n\n```bash\nexit 1\n```\n**Fix:** We restarted `nginx`.\n- Point 1\n- Point 2"
        let output = GoogleHomeClient.cleanForSpeech(input)
        #expect(!output.contains("```"))
        #expect(!output.contains("`nginx`"))
        #expect(output.contains("nginx"))
        #expect(output.contains("Problem:"))
        #expect(output.contains("Fix:"))
    }

    @Test func agentEmbedTagsAreStripped() {
        let input = "<agent-embed src=\"file:///Users/james/.gemini/antigravity/brain/abc/status.html\"></agent-embed>\nAll checks passed."
        let output = GoogleHomeClient.cleanForSpeech(input)
        #expect(!output.contains("agent-embed"))
        #expect(!output.contains("file://"))
        #expect(output == "All checks passed.")
    }
}

@Suite struct SpeakerConfigCodableTests {
    @Test func roundTrip() throws {
        var config = SpeakerConfig(enabled: true, defaultTarget: "lake_office_display")
        config.targets["lake_office_display"] = SpeakerDevice(
            id: "device@324ed736", type: "GoogleDisplayDevice", name: "Lake Office display", room: "Lake Office")
        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(SpeakerConfig.self, from: data)
        #expect(decoded.enabled == true)
        #expect(decoded.defaultTarget == "lake_office_display")
        #expect(decoded.targets["lake_office_display"]?.name == "Lake Office display")
    }
}

@Suite struct AgentIntegrationTests {
    @Test func checksDoNotCrash() {
        let agent = AgentIntegration.shared
        _ = agent.isClaudeCodeHookInstalled()
        _ = agent.isLegacyLaunchAgentInstalled()
    }

    /// Removing the 1.x launch agent stops it through the injected
    /// `bootout`, so a test never runs launchctl against the live session.
    @Test func legacyLaunchAgentRemovalGoesThroughTheBootoutSeam() throws {
        final class Asked: @unchecked Sendable {
            let lock = NSLock()
            var targets: [String] = []
        }
        let asked = Asked()
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("homespeaker-legacy-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: home) }
        let agent = AgentIntegration(home: home, executablePath: "", bootout: { target in
            asked.lock.withLock { asked.targets.append(target) }
        })
        try FileManager.default.createDirectory(at: agent.legacyLaunchAgentURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("<plist/>".utf8).write(to: agent.legacyLaunchAgentURL)
        #expect(agent.isLegacyLaunchAgentInstalled())
        try agent.removeLegacyLaunchAgent()
        #expect(!agent.isLegacyLaunchAgentInstalled())
        #expect(asked.targets == ["gui/\(getuid())/\(AgentIntegration.legacyLaunchAgentLabel)"])
        #expect(asked.targets == [AgentIntegration.legacyLaunchAgentTarget])
    }

    /// An integration pointed at no program reads state and cleans up, but
    /// never installs a hook that could not run.
    @Test func anIntegrationWithNoProgramRefusesToInstall() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("homespeaker-noprogram-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: home) }
        let agent = AgentIntegration(home: home, executablePath: "", bootout: { _ in })
        #expect(throws: AgentIntegration.IntegrationError.self) { try agent.installHook(for: .claudeCode) }
        try AgentIntegration(home: home, executablePath: "/Applications/HomeSpeaker.app/Contents/MacOS/HomeSpeaker", bootout: { _ in })
            .installHook(for: .claudeCode)
        if case .stale = agent.hookStatus(for: .claudeCode) {} else { Issue.record("an existing hook reads as not this integration's") }
        try agent.removeHook(for: .claudeCode)
        #expect(agent.hookStatus(for: .claudeCode) == .notInstalled)
    }
}

// MARK: - Quiet Hours

private func at(_ hhmm: String) -> Date {
    let parts = hhmm.split(separator: ":").map { Int($0)! }
    var comps = DateComponents()
    comps.year = 2026; comps.month = 9; comps.day = 18
    comps.hour = parts[0]; comps.minute = parts[1]
    return Calendar(identifier: .gregorian).date(from: comps)!
}

private func quiet(enabled: Bool? = true, start: String? = "22:00", end: String? = "07:00") -> SpeakerConfig {
    SpeakerConfig(quietHoursEnabled: enabled, quietHoursStart: start, quietHoursEnd: end)
}

@Suite struct QuietHoursTests {
    @Test func overnightWindowCoversLateNightAndEarlyMorning() {
        let cfg = quiet()
        #expect(cfg.isInQuietHours(at: at("23:30")))
        #expect(cfg.isInQuietHours(at: at("03:00")))
        #expect(cfg.isInQuietHours(at: at("22:00")), "start boundary is inclusive")
        #expect(!cfg.isInQuietHours(at: at("07:00")), "end boundary is exclusive")
        #expect(!cfg.isInQuietHours(at: at("12:00")))
        #expect(!cfg.isInQuietHours(at: at("21:59")))
    }

    @Test func sameDayWindow() {
        let cfg = quiet(start: "13:00", end: "14:30")
        #expect(cfg.isInQuietHours(at: at("13:00")))
        #expect(cfg.isInQuietHours(at: at("14:29")))
        #expect(!cfg.isInQuietHours(at: at("14:30")))
        #expect(!cfg.isInQuietHours(at: at("12:59")))
        #expect(!cfg.isInQuietHours(at: at("23:00")))
    }

    @Test func disabledOrMissingIsNeverQuiet() {
        #expect(!quiet(enabled: false).isInQuietHours(at: at("23:30")))
        #expect(!quiet(enabled: nil).isInQuietHours(at: at("23:30")))
        #expect(!quiet(start: nil).isInQuietHours(at: at("23:30")))
        #expect(!quiet(end: nil).isInQuietHours(at: at("23:30")))
    }

    @Test func malformedTimesFailOpen() {
        #expect(!quiet(start: "ten pm").isInQuietHours(at: at("23:30")))
        #expect(!quiet(start: "25:00").isInQuietHours(at: at("23:30")))
        #expect(!quiet(end: "07:60").isInQuietHours(at: at("23:30")))
        #expect(!quiet(start: "22:00", end: "22:00").isInQuietHours(at: at("22:00")), "zero-length window is never quiet")
    }

    @Test func minutesSinceMidnightParser() {
        #expect(SpeakerConfig.minutesSinceMidnight("22:00") == 22 * 60)
        #expect(SpeakerConfig.minutesSinceMidnight("7:05") == 7 * 60 + 5)
        #expect(SpeakerConfig.minutesSinceMidnight(" 07:05 ") == 7 * 60 + 5)
        #expect(SpeakerConfig.minutesSinceMidnight("24:00") == nil)
        #expect(SpeakerConfig.minutesSinceMidnight("0700") == nil)
        #expect(SpeakerConfig.minutesSinceMidnight("") == nil)
    }

    @Test func gateSuppressesUnlessForced() {
        let cfg = quiet()
        #expect(GoogleHomeClient.isSuppressedByQuietHours(config: cfg, force: false, at: at("23:30")))
        #expect(!GoogleHomeClient.isSuppressedByQuietHours(config: cfg, force: true, at: at("23:30")))
        #expect(!GoogleHomeClient.isSuppressedByQuietHours(config: cfg, force: false, at: at("12:00")))
        #expect(!GoogleHomeClient.isSuppressedByQuietHours(config: nil, force: false, at: at("23:30")))
    }

    @Test func broadcastThrowsQuietHoursBeforeTouchingCredentials() async throws {
        // Suppression must be decided before any token or network I/O.
        let target = SpeakerDevice(id: "device@x", type: "SpeakerDevice", name: "Test")
        await #expect(throws: BroadcastError.quietHours(until: "07:00")) {
            _ = try await GoogleHomeClient.shared.broadcast(
                text: "hello", target: target, structureId: "s", config: quiet(), force: false, at: at("23:30"))
        }
    }
}

// MARK: - Target de-duplication

private func sampleTargets() -> [String: SpeakerDevice] {
    let lake = SpeakerDevice(id: "device@lake", type: "GoogleDisplayDevice", name: "Lake Office display", room: "Lake Office")
    return [
        "lake_office": lake,
        "lake_office_display": lake,
        "kitchen": SpeakerDevice(id: "device@kitchen", type: "SpeakerDevice", name: "Kitchen Home", room: "Kitchen"),
        "all": SpeakerDevice(id: "structure@s", type: "Structure", name: "Whole Home (All Speakers)", room: "All"),
    ]
}

@Suite struct TargetDedupTests {
    @Test func duplicateDeviceIdsCollapseToOneEntry() {
        let unique = SpeakerConfig(defaultTarget: "kitchen", targets: sampleTargets()).uniqueTargets()
        #expect(unique.count == 3)
        #expect(Set(unique.map { $0.device.id }).count == 3)
    }

    @Test func defaultTargetKeyIsKeptSoPickerSelectionStaysValid() {
        let keys = SpeakerConfig(defaultTarget: "lake_office_display", targets: sampleTargets()).uniqueTargets().map { $0.key }
        #expect(keys.contains("lake_office_display"))
        #expect(!keys.contains("lake_office"))
    }

    @Test func shortestAliasWinsWhenNeitherIsDefault() {
        let keys = SpeakerConfig(defaultTarget: "kitchen", targets: sampleTargets()).uniqueTargets().map { $0.key }
        #expect(keys.contains("lake_office"))
        #expect(!keys.contains("lake_office_display"))
    }

    @Test func sortedByDisplayName() {
        let names = SpeakerConfig(defaultTarget: "kitchen", targets: sampleTargets()).uniqueTargets().map { $0.device.name }
        #expect(names == names.sorted())
    }

    @Test func displayLineIsSingleLineAndSkipsRedundantRoom() {
        #expect(SpeakerDevice(id: "a", type: "SpeakerDevice", name: "Kitchen Home", room: "Kitchen").displayLine == "Kitchen Home")
        #expect(SpeakerDevice(id: "a", type: "SpeakerDevice", name: "Mini pair", room: "Master Bedroom").displayLine == "Mini pair · Master Bedroom")
        #expect(SpeakerDevice(id: "a", type: "SpeakerDevice", name: "Solo").displayLine == "Solo")
        #expect(!SpeakerDevice(id: "a", type: "SpeakerDevice", name: "X", room: "Y").displayLine.contains("\n"))
    }
}

// MARK: - Chat monitor config wiring

@Suite struct ChatMonitorConfigTests {
    @Test func legacyConfigWithoutChatMonitorKeyDecodesWithDefaults() throws {
        let legacy = Data("""
        {"enabled": true, "default_target": "kitchen", "structure_id": "s", "targets": {}}
        """.utf8)
        let cfg = try JSONDecoder().decode(SpeakerConfig.self, from: legacy)
        #expect(cfg.chatMonitor == nil)
        #expect(cfg.effectiveChatMonitor == ChatMonitorConfig())
        #expect(!cfg.effectiveChatMonitor.slackEnabled, "monitoring is opt-in")
        #expect(!cfg.effectiveChatMonitor.googleChatEnabled)
        #expect(cfg.effectiveChatMonitor.pollIntervalSeconds == 15)
    }

    @Test func roundTripsInSnakeCaseWithoutSecrets() throws {
        var cfg = SpeakerConfig()
        cfg.chatMonitor = ChatMonitorConfig(slackEnabled: false, googleChatEnabled: true, pollIntervalSeconds: 30)
        let data = try JSONEncoder().encode(cfg)
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let monitor = try #require(json["chat_monitor"] as? [String: Any])
        #expect(monitor["slack_enabled"] as? Bool == false)
        #expect(monitor["google_chat_enabled"] as? Bool == true)
        #expect(monitor["poll_interval_seconds"] as? Int == 30)
        #expect(monitor["slack_token"] == nil, "secrets are never persisted to the config file")
        #expect(try JSONDecoder().decode(SpeakerConfig.self, from: data).chatMonitor == cfg.chatMonitor)
    }

    @Test func anySourceEnabledFollowsTheToggles() {
        #expect(!ChatMonitorConfig().anySourceEnabled)
        #expect(ChatMonitorConfig(slackEnabled: false, googleChatEnabled: true).anySourceEnabled)
        #expect(ChatMonitorConfig(slackEnabled: true, googleChatEnabled: false).anySourceEnabled)
    }

    @Test func pollIntervalIsClamped() {
        #expect(ChatMonitorConfig(pollIntervalSeconds: 1).clampedPollInterval == 5)
        #expect(ChatMonitorConfig(pollIntervalSeconds: 9999).clampedPollInterval == 300)
    }
}

// MARK: - Which Google sign-in client is used

/// A folder of its own, removed by the OS later; nothing here touches the
/// person's real files.
private func scratchFolder() throws -> URL {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("homespeaker-oauth-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}

/// An app bundle on disk whose Info.plist carries `info`, the way the
/// packaged HomeSpeaker.app carries its sign-in client.
private func bundle(with info: [String: String], in root: URL) throws -> Bundle {
    let contents = root.appendingPathComponent("Fake-\(UUID().uuidString).app/Contents")
    try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
    var plist = info
    plist["CFBundleIdentifier"] = "test.homespeaker.fake"
    try (plist as NSDictionary).write(to: contents.appendingPathComponent("Info.plist"))
    return try #require(Bundle(url: contents.deletingLastPathComponent()))
}

@Suite struct OAuthClientTests {
    private let own = OAuthClient(clientId: "own", clientSecret: "own-secret")
    private let shipped = OAuthClient(clientId: "shipped", clientSecret: "shipped-secret")
    private let saved = GoogleCredentials(
        clientId: "saved", clientSecret: "saved-secret", accessToken: "a", refreshToken: "r")

    private func person(own: Bool = false, saved: Bool = false) -> Secrets {
        var secrets = Secrets()
        if own {
            secrets.oauthClientIdOverride = "own"
            secrets.oauthClientSecretOverride = "own-secret"
        }
        if saved { secrets.google = self.saved }
        return secrets
    }

    @Test func theOwnClientWins() {
        #expect(OAuthClient.resolve(secrets: person(own: true, saved: true), shipped: shipped) == own)
    }

    @Test func theShippedClientIsNext() {
        #expect(OAuthClient.resolve(secrets: person(saved: true), shipped: shipped) == shipped)
        #expect(OAuthClient.resolve(secrets: person(), shipped: shipped) == shipped)
    }

    @Test func aSavedLoginsClientIsLast() {
        #expect(OAuthClient.resolve(secrets: person(saved: true), shipped: nil)
                == OAuthClient(clientId: "saved", clientSecret: "saved-secret"))
        #expect(OAuthClient.resolve(secrets: person(), shipped: nil) == nil, "no client anywhere is none")
    }

    @Test func aBlankOwnClientIsNotAnOwnClient() {
        var secrets = person(saved: true)
        secrets.oauthClientIdOverride = "  \n"
        #expect(OAuthClient.resolve(secrets: secrets, shipped: shipped) == shipped)
    }

    @Test func anEmptyShippedFileIsNone() throws {
        let tool = try scratchFolder()
        let file = tool.appendingPathComponent("google-oauth-client.json")
        #expect(OAuthClientFile.read(file) == nil, "no file")
        try Data().write(to: file)
        #expect(OAuthClientFile.read(file) == nil, "an empty file")
        try Data(#"{"client_id": "", "client_secret": "s"}"#.utf8).write(to: file)
        #expect(OAuthClientFile.read(file) == nil, "a blank client id")
        try Data("not json".utf8).write(to: file)
        #expect(OAuthClientFile.read(file) == nil, "a file that is not a client")
        try Data(#"{"client_id": " id ", "client_secret": "s"}"#.utf8).write(to: file)
        #expect(OAuthClientFile.read(file) == OAuthClient(clientId: "id", clientSecret: "s"))
    }

    @Test func theExtensionReadsItsToolFoldersFile() throws {
        let root = try scratchFolder()
        let tool = root.appendingPathComponent("tool")
        try FileManager.default.createDirectory(at: tool, withIntermediateDirectories: true)
        let profile = HomeSpeakerProfile.extension(
            dataFolder: root.appendingPathComponent("data"), toolFolder: tool, messagePrefix: "test.oauth")
        #expect(profile.shippedClient == nil, "nothing shipped yet")
        try Data(#"{"client_id": "ext", "client_secret": "ext-secret"}"#.utf8)
            .write(to: tool.appendingPathComponent("google-oauth-client.json"))
        #expect(profile.shippedClient == OAuthClient(clientId: "ext", clientSecret: "ext-secret"),
                "read when asked, so a file put there later is found")
    }

    @Test func anExtensionWithNoToolFolderShipsNothing() throws {
        let root = try scratchFolder()
        let profile = HomeSpeakerProfile.extension(
            dataFolder: root, toolFolder: nil, messagePrefix: "test.oauth")
        #expect(profile.shippedClient == nil)
    }

    @Test func theExtensionNeverReadsTheMainBundle() throws {
        let root = try scratchFolder()
        let withClient = try bundle(
            with: ["GoogleOAuthClientID": "app-id", "GoogleOAuthClientSecret": "app-secret"], in: root)
        let tool = root.appendingPathComponent("tool")
        try FileManager.default.createDirectory(at: tool, withIntermediateDirectories: true)
        let profile = HomeSpeakerProfile.extension(
            dataFolder: root.appendingPathComponent("data"), toolFolder: tool,
            messagePrefix: "test.oauth", bundle: withClient)
        #expect(profile.shippedClient == nil, "a client in the bundle that runs it is not the extension's")

        try Data(#"{"client_id": "ext", "client_secret": "s"}"#.utf8)
            .write(to: tool.appendingPathComponent("google-oauth-client.json"))
        #expect(profile.shippedClient?.clientId == "ext", "only its own file counts")
    }

    @Test func theAppReadsItsBundlesInfoPlist() throws {
        let root = try scratchFolder()
        let withClient = try bundle(
            with: ["GoogleOAuthClientID": "app-id", "GoogleOAuthClientSecret": "app-secret"], in: root)
        #expect(HomeSpeakerProfile.app(bundle: withClient).shippedClient
                == OAuthClient(clientId: "app-id", clientSecret: "app-secret"))

        let idOnly = try bundle(with: ["GoogleOAuthClientID": "app-id"], in: root)
        #expect(HomeSpeakerProfile.app(bundle: idOnly).shippedClient
                == OAuthClient(clientId: "app-id", clientSecret: ""), "a missing secret is empty, as before")

        let blank = try bundle(with: ["GoogleOAuthClientID": "  "], in: root)
        #expect(HomeSpeakerProfile.app(bundle: blank).shippedClient == nil)
        #expect(HomeSpeakerProfile.app(bundle: try bundle(with: [:], in: root)).shippedClient == nil)
    }
}
