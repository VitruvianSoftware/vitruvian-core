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

// Guards for where HomeSpeaker keeps its files. The app's profile is today's
// paths exactly, so an app user notices nothing. The extension's profile
// keeps everything in the data folder Vitruvian gives it, and never the
// app's files. An engine built on a profile reads and writes one secrets
// file, for its settings, its sign-in and its speakers alike.
//
// No test here reads, writes or checks for the person's real files
// (`~/.gemini/…`, `~/Library/Application Support/HomeSpeaker/secrets.json`):
// paths are only compared, and every file written is in a scratch folder.

private func scratchDir() throws -> URL {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("homespeaker-profile-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}

/// A message prefix no real app or extension on this Mac listens on.
private func testPrefix() -> String { "test.\(UUID().uuidString).homespeaker" }

/// A profile in `root`, checked to be there before any engine is built on
/// it: if a bug pointed one of its files at the person's real ones, the
/// test stops here, before an engine could read or write them.
private func scratchProfile(in root: URL) throws -> HomeSpeakerProfile {
    let profile = HomeSpeakerProfile.extension(
        dataFolder: root.appendingPathComponent("data"), toolFolder: nil, messagePrefix: testPrefix())
    for url in [profile.settingsURL, profile.historyURL, profile.secretsURL, profile.monitorStatusURL] {
        try #require(url.path.hasPrefix(root.path + "/"), "\(url.path) is outside the scratch folder")
    }
    return profile
}

/// This Mac's speech, made silent.
private struct SilentLocal: LocalSpeaking {
    func speak(_ text: String, voiceID: String) async throws {}
}

@Suite struct HomeSpeakerProfileTests {
    @Test func appProfileIsTodays() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let profile = HomeSpeakerProfile.app(home: home)
        #expect(profile.door == .app)
        #expect(profile.settingsURL == ConfigManager.defaultConfigURL())
        #expect(profile.historyURL == BroadcastHistory.defaultURL())
        #expect(profile.secretsURL == SecretStore.defaultURL())
        #expect(profile.monitorStatusURL == ChatMonitorStatusFile.defaultURL())
        #expect(profile.messagePrefix == "com.vitruviansoftware.homespeaker")
        #expect(profile.liveLockURL == nil)
        #expect(profile.toolFolder == nil)
        // Byte for byte, the paths the app has always used.
        #expect(profile.settingsURL.path == home.path + "/.gemini/speaker_broadcast.json")
        #expect(profile.historyURL.path == home.path + "/.gemini/speaker_history.json")
        #expect(profile.monitorStatusURL.path == home.path + "/.gemini/speaker_monitor_status.json")
        #expect(profile.secretsURL.path.hasSuffix("/Library/Application Support/HomeSpeaker/secrets.json"))
        #expect(HomeSpeakerProfile.app() == profile)
    }

    @Test func appProfileFollowsTheHomeItIsGiven() throws {
        let home = try scratchDir()
        let profile = HomeSpeakerProfile.app(home: home)
        #expect(profile.settingsURL == home.appendingPathComponent(".gemini/speaker_broadcast.json"))
        #expect(profile.historyURL == home.appendingPathComponent(".gemini/speaker_history.json"))
        #expect(profile.monitorStatusURL == home.appendingPathComponent(".gemini/speaker_monitor_status.json"))
    }

    @Test func extensionProfileLivesInItsDataFolder() throws {
        let root = try scratchDir()
        let data = root.appendingPathComponent("ToolData/dev.vitruvian.homespeaker")
        let tool = root.appendingPathComponent("Tools/dev.vitruvian.homespeaker")
        let prefix = testPrefix()
        let profile = HomeSpeakerProfile.extension(dataFolder: data, toolFolder: tool, messagePrefix: prefix)

        #expect(profile.door == .extension)
        #expect(profile.settingsURL == data.appendingPathComponent("settings.json"))
        #expect(profile.historyURL == data.appendingPathComponent("history.json"))
        #expect(profile.secretsURL == data.appendingPathComponent("secrets.json"))
        #expect(profile.monitorStatusURL == data.appendingPathComponent("speaker_monitor_status.json"))
        #expect(profile.liveLockURL == data.appendingPathComponent("running.lock"))
        #expect(profile.toolFolder == tool)
        #expect(profile.messagePrefix == prefix)

        let app = HomeSpeakerProfile.app()
        let urls = [profile.settingsURL, profile.historyURL, profile.secretsURL,
                    profile.monitorStatusURL, profile.liveLockURL].compactMap { $0 }
        #expect(urls.count == 5)
        for url in urls {
            #expect(url.path.hasPrefix(data.path + "/"), "\(url.path) is outside the data folder")
            #expect(!url.path.contains("/.gemini/"), "\(url.path) is the app's settings folder")
            #expect(!url.path.contains("Application Support/HomeSpeaker/"), "\(url.path) is the app's secrets folder")
            #expect(![app.settingsURL, app.historyURL, app.secretsURL, app.monitorStatusURL].contains(url))
        }
    }

    @Test func extensionProfileHasItsOwnMessagesByDefault() {
        let profile = HomeSpeakerProfile.extension(dataFolder: URL(fileURLWithPath: "/x/data"), toolFolder: nil)
        #expect(profile.messagePrefix == "dev.vitruvian.homespeaker")
        #expect(profile.messagePrefix != HomeSpeakerProfile.app().messagePrefix)
        #expect(profile.toolFolder == nil)
    }

    @Test func extensionFoldersFromTheProgram() {
        let base = "/Users/someone/Library/Application Support/com.vitruviansoftware.vitruvian"
        let program = URL(fileURLWithPath: base + "/Tools/dev.vitruvian.homespeaker/bin/tool")
        let folders = HomeSpeakerProfile.extensionFolders(program: program)
        #expect(folders?.tool.path == base + "/Tools/dev.vitruvian.homespeaker")
        #expect(folders?.data.path == base + "/ToolData/dev.vitruvian.homespeaker")

        // Anything else is not the extension's program: no folder is guessed.
        let others: [URL] = [
            URL(fileURLWithPath: "/Users/someone/repo/bazel-bin/apps/desktop/home-speaker/built/homespeaker/bin/tool"),
            URL(fileURLWithPath: "Tools/dev.vitruvian.homespeaker/bin/tool"),
            URL(string: "Tools/dev.vitruvian.homespeaker/bin/tool")!,
            URL(fileURLWithPath: "/Applications/HomeSpeaker.app/Contents/MacOS/HomeSpeaker"),
            URL(fileURLWithPath: base + "/Tools/dev.vitruvian.homespeaker/bin/other"),
            URL(fileURLWithPath: "/Tools/dev.vitruvian.homespeaker/bin/tool"),
        ]
        for other in others {
            #expect(HomeSpeakerProfile.extensionFolders(program: other) == nil, "\(other) gave folders")
        }
    }
}

@MainActor
@Suite struct HomeSpeakerEngineTests {
    @Test func oneEngineOneSecretsFile() async throws {
        let profile = try scratchProfile(in: try scratchDir())
        let engine = HomeSpeakerEngine(
            profile: profile, session: URLSession(configuration: .ephemeral), local: SilentLocal())

        #expect(engine.profile == profile)
        #expect(engine.secrets.fileURL == profile.secretsURL)
        #expect(engine.history.fileURL == profile.historyURL)
        #expect(engine.config.secrets === engine.secrets)
        #expect(engine.config.history === engine.history)
        #expect(engine.home.auth === engine.auth)
        #expect((engine.announcer.home as? GoogleHomeClient) === engine.home)
        // Paths only: the app's file is never opened, even to look at it.
        #expect(SecretStore.shared.fileURL != profile.secretsURL)
        // Required, so that a wrong store stops the test here, before the
        // round trip below could read whatever file that store points at.
        try #require(engine.auth.store.fileURL == profile.secretsURL)
        try #require(engine.home.auth.store.fileURL == profile.secretsURL)

        // A login saved through the engine's secrets is the one its sign-in
        // hands out, without a network call (the token is fresh).
        let creds = GoogleCredentials(
            clientId: "test-client", clientSecret: "",
            accessToken: "test-access-\(UUID().uuidString)", refreshToken: "test-refresh",
            expiry: Date().addingTimeInterval(3600), scopes: [GoogleAuth.homeScope])
        try engine.secrets.update { $0.google = creds }
        #expect(try await engine.auth.validAccessToken() == creds.accessToken)
        #expect(try await engine.home.auth.validAccessToken() == creds.accessToken)
        engine.config.checkConnection()
        #expect(engine.config.isConnectedToGoogle)
        #expect(FileManager.default.fileExists(atPath: profile.secretsURL.path))
    }

    @Test func theEngineSettingsAreTheProfiles() throws {
        let profile = try scratchProfile(in: try scratchDir())
        let engine = HomeSpeakerEngine(
            profile: profile, session: URLSession(configuration: .ephemeral), local: SilentLocal())
        engine.config.config.defaultTarget = "kitchen"
        try engine.config.trySaveConfig()
        let onDisk = try JSONSerialization.jsonObject(with: Data(contentsOf: profile.settingsURL)) as? [String: Any]
        #expect(onDisk?["default_target"] as? String == "kitchen")

        engine.config.addLogItem(BroadcastLogItem(timestamp: Date(), text: "hello", targetName: "Kitchen", source: "Test"))
        #expect(BroadcastHistory(fileURL: profile.historyURL).load().map(\.text) == ["hello"])
    }
}
