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
@testable import VitruvianSpeakerCore

// Guards for "Say who it's from": an agent's announcement can start with
// its app ("Claude:"), and with its session too ("Claude, Courier:") only
// while another session of the same app has spoken lately.

private func said(
    _ agent: CodingAgent, session: String?, name: String? = nil, minutesAgo: Double = 1
) -> BroadcastLogItem {
    BroadcastLogItem(
        timestamp: Date().addingTimeInterval(-minutesAgo * 60), text: "x", targetName: "Office",
        source: agent.displayName, session: session.map { SessionOrigin(id: $0, name: name) })
}

private let courier = SessionOrigin(id: "c-1", name: "vitruvian-core: Courier")

@Suite struct SourceLabelLeadTests {
    @Test func offSaysNothingAndAppSaysTheApp() {
        #expect(SourceLabel.lead(.off, agent: .claudeCode, session: courier, history: []) == nil)
        #expect(SourceLabel.lead(.app, agent: .claudeCode, session: courier, history: [said(.claudeCode, session: "x")]) == "Claude: ")
        #expect(SourceLabel.lead(.app, agent: .antigravity, session: nil, history: []) == "Antigravity: ")
    }

    @Test func theSessionIsNamedOnlyWhileAnotherSessionOfTheAppIsTalking() {
        let alone = SourceLabel.lead(.appAndSession, agent: .claudeCode, session: courier, history: [said(.claudeCode, session: "c-1")])
        #expect(alone == "Claude: ", "its own earlier announcements are not another session")
        let busy = SourceLabel.lead(.appAndSession, agent: .claudeCode, session: courier, history: [said(.claudeCode, session: "d-2")])
        #expect(busy == "Claude, Courier: ")
    }

    @Test func otherAppsOldAnnouncementsAndUnknownSessionsDoNotCount() {
        let otherApp = [said(.antigravity, session: "a-1")]
        #expect(SourceLabel.lead(.appAndSession, agent: .claudeCode, session: courier, history: otherApp) == "Claude: ")
        let stale = [said(.claudeCode, session: "d-2", minutesAgo: 31)]
        #expect(SourceLabel.lead(.appAndSession, agent: .claudeCode, session: courier, history: stale) == "Claude: ")
        // Written by a version that kept no session: no evidence of another.
        let older = [BroadcastLogItem(text: "x", targetName: "Office", source: "Claude Code")]
        #expect(SourceLabel.lead(.appAndSession, agent: .claudeCode, session: courier, history: older) == "Claude: ")
        // A busy app, but no name to say for this session: just the app.
        let unnamed = SessionOrigin(id: "c-1", name: nil)
        #expect(SourceLabel.lead(.appAndSession, agent: .claudeCode, session: unnamed,
                                 history: [said(.claudeCode, session: "d-2")]) == "Claude: ")
    }
}

@Suite struct SourceLabelNameTests {
    @Test(arguments: [
        ("vitruvian-core: Vitruvian Speaker", "Vitruvian Speaker"),
        ("Watch: upstream hermetic Android NDK (retire our patch)", "upstream hermetic Android"),
        ("abrialcode - pricing engine", "pricing engine"),
        ("claude-speaker-source-label", "claude speaker source"),
        ("Slack - Chandini", "Chandini"),
        ("vitruvian-core:  Android Remote", "Android Remote"),
    ])
    func shortNames(raw: String, expected: String) {
        #expect(SourceLabel.shortName(raw) == expected)
    }

    @Test func emptyOrPunctuationIsNoName() {
        #expect(SourceLabel.shortName("") == nil)
        #expect(SourceLabel.shortName("(…)") == nil)
    }

    @Test func theHomeFolderSaysNothingAboutTheSession() {
        #expect(SourceLabel.folderName(FileManager.default.homeDirectoryForCurrentUser.path) == nil)
        #expect(SourceLabel.folderName(nil) == nil)
        #expect(SourceLabel.folderName("/Users/someone/Workspace/courier") == "courier")
    }

    @Test func aClaudeSessionIsNamedByItsLatestTitleElseItsFolder() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("hs-title-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("abc.jsonl")
        try [
            #"{"type":"custom-title","customTitle":"vitruvian-core: Old Name","sessionId":"abc"}"#,
            #"{"message":{"role":"user","content":"hi"}}"#,
            #"{"type":"custom-title","customTitle":"vitruvian-core: Courier","sessionId":"abc"}"#,
        ].joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
        #expect(SessionOrigin.claudeCode(sessionID: "abc", transcriptPath: url.path, cwd: "/x/vitruvian-core")?.name == "Courier")
        let untitled = dir.appendingPathComponent("def.jsonl")
        try #"{"message":{"role":"user","content":"hi"}}"#.write(to: untitled, atomically: true, encoding: .utf8)
        #expect(SessionOrigin.claudeCode(sessionID: "def", transcriptPath: untitled.path, cwd: "/x/courier")?.name == "courier")
        #expect(SessionOrigin.claudeCode(sessionID: "", transcriptPath: url.path, cwd: nil) == nil)
    }

    @Test func aSayFindsItsClaudeSessionFromTheEnvironment() throws {
        let projects = FileManager.default.temporaryDirectory.appendingPathComponent("hs-projects-\(UUID().uuidString)")
        let folder = projects.appendingPathComponent("-Users-someone-repo")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try #"{"type":"custom-title","customTitle":"repo: Dedupe"}"#
            .write(to: folder.appendingPathComponent("s-9.jsonl"), atomically: true, encoding: .utf8)
        let env = ["CLAUDE_CODE_SESSION_ID": "s-9", "PWD": "/Users/someone/repo"]
        #expect(SessionOrigin.fromEnvironment(env, agent: .claudeCode, claudeProjects: projects) == SessionOrigin(id: "s-9", name: "Dedupe"))
        let agy = ["ANTIGRAVITY_CONVERSATION_ID": "conv-1", "PWD": "/Users/someone/courier"]
        #expect(SessionOrigin.fromEnvironment(agy, agent: .antigravity) == SessionOrigin(id: "conv-1", name: "courier"))
        #expect(SessionOrigin.fromEnvironment(env, agent: nil) == nil, "a person's own --say has no session")
    }

    @Test func anAntigravityConversationIsItsTranscriptFolder() {
        let path = "/Users/someone/.gemini/antigravity/brain/conv-7/.system_generated/logs/transcript.jsonl"
        #expect(SessionOrigin.antigravity(transcriptPath: path, cwd: "/Users/someone/Workspace/wand")
                == SessionOrigin(id: "conv-7", name: "wand"))
        #expect(SessionOrigin.antigravity(transcriptPath: "/tmp/transcript.jsonl", cwd: nil) == nil)
    }
}

@Suite struct SourceLabelHandOverTests {
    @Test func theDetachedAnnouncementCarriesTheSession() {
        for agent in CodingAgent.allCases {
            let args = DetachedAnnouncement.arguments(text: "Done.", agent: agent, session: courier)
            #expect(VitruvianSpeakerCommandLine.parse(args) == .announce("Done.", agent, courier))
        }
        // Without a session: exactly the forms every release has used.
        #expect(DetachedAnnouncement.arguments(text: "Done.", agent: .claudeCode) == ["--announce", "Done."])
        #expect(VitruvianSpeakerCommandLine.parse(["--announce", "Done.", "--source", "agy"]) == .announce("Done.", .antigravity))
    }

    @Test func aMalformedHandOverIsNotAnAnnouncement() {
        for bad in [
            ["--announce", "Done.", "--session"],
            ["--announce", "Done.", "--session-name", "Courier"],
            ["--announce", "Done.", "--session", "a", "--session", "b"],
            ["--announce", "Done.", "--colour", "red"],
            ["--announce", "Done.", "--source", "nobody"],
        ] {
            if case .announce = VitruvianSpeakerCommandLine.parse(bad) { Issue.record("\(bad) parsed as an announcement") }
        }
    }

    @Test func historyKeepsTheSessionAndOlderFilesStillRead() throws {
        let item = said(.claudeCode, session: "c-1", name: "Courier")
        let back = try JSONDecoder().decode(BroadcastLogItem.self, from: JSONEncoder().encode(item))
        #expect(back.session == "c-1" && back.sessionName == "Courier")
        let old = #"{"id":"6F9619FF-8B86-D011-B42D-00CF4FC964FF","timestamp":0,"text":"t","targetName":"Office","source":"Say"}"#
        let decoded = try JSONDecoder().decode(BroadcastLogItem.self, from: Data(old.utf8))
        #expect(decoded.session == nil)
    }
}

@Suite struct SourceLabelSettingTests {
    @Test func offUnlessChosenAndAnUnknownValueReadsAsOff() throws {
        #expect(SpeakerConfig().effectiveAnnounceSource == .off)
        var config = SpeakerConfig()
        config.effectiveAnnounceSource = .appAndSession
        let json = String(decoding: try JSONEncoder().encode(config), as: UTF8.self)
        #expect(json.contains(#""announce_source":"app_and_session""#))
        #expect(try JSONDecoder().decode(SpeakerConfig.self, from: Data(json.utf8)).effectiveAnnounceSource == .appAndSession)
        let future = json.replacingOccurrences(of: "app_and_session", with: "something_newer")
        #expect(try JSONDecoder().decode(SpeakerConfig.self, from: Data(future.utf8)).effectiveAnnounceSource == .off)
    }

    @Test func theCatalogListsItAsAChoiceAndActionsSetIt() throws {
        let entry = SettingsCatalog(config: SpeakerConfig()).entry(.announceSource)
        #expect(entry.kind == .choice && entry.shown)
        #expect(entry.choices.map(\.value) == ["off", "app", "app_and_session"])
        var config = SpeakerConfig()
        _ = try SettingsActions.applySet(key: .announceSource, value: "app", to: &config)
        #expect(config.effectiveAnnounceSource == .app)
    }
}

/// The whole Claude Code hook, from stdin to the speaker.
@Suite struct SourceLabelHookTests {
    private final class Heard: @unchecked Sendable {
        private let lock = NSLock()
        private var items: [String] = []
        func add(_ s: String) { lock.withLock { items.append(s) } }
        var all: [String] { lock.withLock { items } }
    }

    @MainActor private static func manager(_ dir: URL, _ mode: AnnounceSourceLabel) -> ConfigManager {
        let m = ConfigManager(configPath: dir.appendingPathComponent("c.json"),
                              historyPath: dir.appendingPathComponent("h.json"),
                              secrets: SecretStore(fileURL: dir.appendingPathComponent("s.json")))
        m.config.enabled = true
        m.config.effectiveSpeakHome = true
        m.config.effectiveSpeakLocal = false
        m.config.structureId = "s1"
        m.config.targets = ["office": SpeakerDevice(id: "d1", type: "SPEAKER", name: "Office")]
        m.config.defaultTarget = "office"
        m.config.effectiveAnnouncementStyle = .verbatim
        m.config.effectiveAnnounceSource = mode
        return m
    }

    /// One session's turn: a transcript titled `title` ending in `reply`.
    private static func turn(_ dir: URL, session: String, title: String, reply: String) throws -> Data {
        let url = dir.appendingPathComponent("\(session).jsonl")
        try [
            #"{"type":"custom-title","customTitle":"\#(title)"}"#,
            #"{"message":{"role":"user","content":"is it done?"}}"#,
            #"{"message":{"role":"assistant","content":[{"type":"text","text":"\#(reply)"}]}}"#,
        ].joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
        return try JSONSerialization.data(withJSONObject: ["transcript_path": url.path, "session_id": session, "cwd": "/x/repo"])
    }

    private static func run(_ input: Data, _ dir: URL, _ manager: ConfigManager, heard: Heard, launched: Heard) async {
        _ = await VitruvianSpeakerCommandLine.claudeStopHook(
            input: input, config: { manager }, history: BroadcastHistory(fileURL: dir.appendingPathComponent("hist.json")),
            standsAside: false, lockDirectory: dir, launchDetached: { launched.add($0) },
            broadcaster: { text, _, _, _ in heard.add(text); return true })
    }

    @Test func twoSessionsAreToldApartAndOneIsNot() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("hs-label-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let manager = await Self.manager(dir, .appAndSession)
        let heard = Heard(), launched = Heard()
        await Self.run(try Self.turn(dir, session: "a", title: "repo: Courier", reply: "Courier is built."), dir, manager, heard: heard, launched: launched)
        await Self.run(try Self.turn(dir, session: "b", title: "repo: Dedupe", reply: "Dedupe is done."), dir, manager, heard: heard, launched: launched)
        await Self.run(try Self.turn(dir, session: "a", title: "repo: Courier", reply: "Courier is shipped."), dir, manager, heard: heard, launched: launched)
        #expect(heard.all == ["Claude: Courier is built.", "Claude, Dedupe: Dedupe is done.", "Claude, Courier: Courier is shipped."])
        #expect(launched.all.isEmpty)
        let history = BroadcastHistory(fileURL: dir.appendingPathComponent("hist.json")).load()
        #expect(history.map(\.text) == ["Courier is shipped.", "Dedupe is done.", "Courier is built."], "the label is not listed")
    }

    @Test func offSpeaksExactlyAsBefore() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("hs-label-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let manager = await Self.manager(dir, .off)
        let heard = Heard(), launched = Heard()
        await Self.run(try Self.turn(dir, session: "a", title: "repo: Courier", reply: "Courier is built."), dir, manager, heard: heard, launched: launched)
        await Self.run(try Self.turn(dir, session: "b", title: "repo: Dedupe", reply: "Dedupe is done."), dir, manager, heard: heard, launched: launched)
        #expect(heard.all == ["Courier is built.", "Dedupe is done."])
    }
}
