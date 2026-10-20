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

private func scratch() -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("homespeaker-plugins-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private let app = "/Applications/HomeSpeaker.app/Contents/MacOS/HomeSpeaker"

/// Installing, updating and removing the Antigravity and OpenCode plugins:
/// each in its own place, each found again, and nothing else touched.
@Suite struct AgentPluginInstallTests {
    @Test func antigravityGetsAPluginFolderWithAFlatStopHook() throws {
        let home = scratch()
        let a = AgentIntegration(home: home, executablePath: app)
        #expect(a.status(of: .antigravity).hook == .notInstalled)

        try a.installHook(for: .antigravity)
        let folder = home.appendingPathComponent(".gemini/config/plugins/home-speaker")
        let manifest = try JSONSerialization.jsonObject(with: Data(contentsOf: folder.appendingPathComponent("plugin.json"))) as? [String: Any]
        #expect(manifest?["name"] as? String == "home-speaker")
        let hooks = try JSONSerialization.jsonObject(with: Data(contentsOf: folder.appendingPathComponent("hooks.json"))) as? [String: Any]
        let stop = (hooks?["home-speaker"] as? [String: Any])?["Stop"] as? [[String: Any]]
        // agy's own hook docs: Stop takes handler objects directly, no matcher group.
        #expect(stop?.count == 1)
        #expect(stop?.first?["matcher"] == nil)
        #expect(stop?.first?["command"] as? String == "\"\(app)\" --antigravity-hook")
        #expect(stop?.first?["timeout"] as? Int == 10)
        #expect(a.status(of: .antigravity).hook == .installed)
        #expect(a.status(of: .antigravity).hookProgram == app)

        try a.removeHook(for: .antigravity)
        #expect(!FileManager.default.fileExists(atPath: folder.path))
        #expect(a.status(of: .antigravity).hook == .notInstalled)
    }

    @Test func anAntigravityPluginOfAnotherProgramOrAnOlderShapeNeedsAnUpdate() throws {
        let home = scratch()
        let old = "/Users/me/Downloads/HomeSpeaker.app/Contents/MacOS/HomeSpeaker"
        try AgentIntegration(home: home, executablePath: old).installHook(for: .antigravity)
        let a = AgentIntegration(home: home, executablePath: app)
        #expect(a.status(of: .antigravity).hook == .stale("\"\(old)\" --antigravity-hook"))

        try a.installHook(for: .antigravity)
        #expect(a.status(of: .antigravity).hook == .installed)

        // Same program, older files (an earlier grouped shape): Update.
        let hooks = home.appendingPathComponent(".gemini/config/plugins/home-speaker/hooks.json")
        try #"{"home-speaker":{"Stop":[{"matcher":"*","hooks":[{"type":"command","command":"\"\#(app)\" --antigravity-hook"}]}]}}"#
            .write(to: hooks, atomically: true, encoding: .utf8)
        #expect(a.status(of: .antigravity).hook == .stale("\"\(app)\" --antigravity-hook"))
    }

    @Test func openCodeGetsOnePluginFile() throws {
        let home = scratch()
        let a = AgentIntegration(home: home, executablePath: app)
        try a.installHook(for: .opencode)
        let file = home.appendingPathComponent(".config/opencode/plugins/home-speaker.ts")
        let text = try String(contentsOf: file, encoding: .utf8)
        #expect(text.contains("// Command: \"\(app)\" --opencode-hook"))
        #expect(text.contains("const PROGRAM = \"\(app)\""))
        #expect(text.contains("export default {"))
        #expect(text.contains("id: \"home-speaker\""))
        #expect(text.contains("setup(ctx)"))
        #expect(text.contains("event.data && event.data.sessionID"))
        #expect(text.contains("ctx.session.context({ sessionID })"))
        #expect(text.contains("\"session.idle\""))
        #expect(text.contains("[\"--opencode-hook\"]"))
        #expect(a.status(of: .opencode).hook == .installed)

        try "// Command: \"\(app)\" --opencode-hook\n".write(to: file, atomically: true, encoding: .utf8)
        #expect(a.status(of: .opencode).hook == .stale("\"\(app)\" --opencode-hook"), "an older plugin is updated")
        try a.installHook(for: .opencode)
        #expect(a.status(of: .opencode).hook == .installed)

        try a.removeHook(for: .opencode)
        #expect(!FileManager.default.fileExists(atPath: file.path))
    }

    @Test func aFileOfTheSameNameSomeoneElseWroteIsLeftAlone() throws {
        let home = scratch()
        let a = AgentIntegration(home: home, executablePath: app)
        let file = home.appendingPathComponent(".config/opencode/plugins/home-speaker.ts")
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "export const Mine = async () => ({})\n".write(to: file, atomically: true, encoding: .utf8)
        let folder = home.appendingPathComponent(".gemini/config/plugins/home-speaker")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try #"{"home-speaker":{"Stop":[{"command":"say done"}]}}"#
            .write(to: folder.appendingPathComponent("hooks.json"), atomically: true, encoding: .utf8)

        #expect(a.status(of: .opencode).hook == .notInstalled)
        #expect(a.status(of: .antigravity).hook == .notInstalled)
        try a.removeHook(for: .opencode)
        try a.removeHook(for: .antigravity)
        #expect(FileManager.default.fileExists(atPath: file.path))
        #expect(FileManager.default.fileExists(atPath: folder.path))
    }

    @Test(arguments: [CodingAgent.antigravity, .opencode])
    func onlyHomeSpeakerIsEverInstalled(agent: CodingAgent) throws {
        let home = scratch()
        let a = AgentIntegration(home: home, executablePath: "/usr/bin/true")
        #expect(throws: AgentIntegration.IntegrationError.notHomeSpeaker("/usr/bin/true")) { try a.installHook(for: agent) }
        #expect(!FileManager.default.fileExists(atPath: agent.settingsURL(home: home).path))
    }

    @Test(arguments: [CodingAgent.antigravity, .opencode])
    func aMovedAppRepairsEveryPlugin(agent: CodingAgent) throws {
        let home = scratch()
        try AgentIntegration(home: home, executablePath: "/gone/HomeSpeaker.app/Contents/MacOS/HomeSpeaker").installHook(for: agent)
        let a = AgentIntegration(home: home, executablePath: app)
        a.repairHookIfMoved(choice: nil)
        #expect(a.status(of: agent).hook == .installed)
    }

    @Test func eachAgentSaysWhereItsHookGoes() {
        #expect(CodingAgent.claudeCode.hookFootnote.contains("~/.claude/settings.json"))
        #expect(CodingAgent.antigravity.hookFootnote.contains("~/.gemini/config/plugins/home-speaker"))
        #expect(CodingAgent.opencode.hookFootnote.contains("~/.config/opencode/plugins/home-speaker.ts"))
    }
}

/// Reading each agent's finished turn, and speaking it once.
@Suite struct AgentTurnReaderTests {
    /// Antigravity's own transcript lines: every tool argument is a JSON
    /// value written into a string.
    static func step(_ type: String, _ content: String = "", calls: [[String: Any]] = []) -> String {
        var obj: [String: Any] = ["type": type, "source": type == "USER_INPUT" ? "USER_EXPLICIT" : "MODEL", "content": content]
        if !calls.isEmpty { obj["tool_calls"] = calls }
        return String(data: try! JSONSerialization.data(withJSONObject: obj), encoding: .utf8)!
    }

    static func runCommand(_ command: String) -> [String: Any] {
        let encoded = String(data: try! JSONSerialization.data(withJSONObject: command, options: .fragmentsAllowed), encoding: .utf8)!
        return ["name": "run_command", "args": ["CommandLine": encoded, "Cwd": "\"/tmp\""]]
    }

    @Test func antigravitysLastReplyOfTheTurnIsSpoken() {
        let lines = [
            Self.step("USER_INPUT", "first"),
            Self.step("PLANNER_RESPONSE", "old answer"),
            Self.step("USER_INPUT", "second"),
            Self.step("PLANNER_RESPONSE", "", calls: [Self.runCommand("grep -n \"speaker-broadcast\" f.swift")]),
            Self.step("GENERIC", "tool output"),
            Self.step("EPHEMERAL_MESSAGE", "contract"),
            Self.step("PLANNER_RESPONSE", "It is done."),
        ]
        let entries = AntigravityHook.parseTranscript(lines.joined(separator: "\n"))
        #expect(entries.count == 5, "only the person's and the model's steps")
        #expect(ClaudeStopHook.textToSpeak(entries: entries) == "It is done.")
    }

    @Test func anAntigravityTurnThatAlreadySpokeIsNotSpokenAgain() {
        let viaShell = [Self.step("USER_INPUT", "q"),
                        Self.step("PLANNER_RESPONSE", "", calls: [Self.runCommand("speaker-broadcast \"All done.\"")]),
                        Self.step("PLANNER_RESPONSE", "All done.")]
        #expect(ClaudeStopHook.textToSpeak(entries: AntigravityHook.parseTranscript(viaShell.joined(separator: "\n"))) == nil)

        let viaHome: [String: Any] = ["name": "call_mcp_tool", "args": [
            "ServerName": "\"home_mcp\"", "ToolName": "\"run_home_actions\"",
            "Arguments": #"{"actions":[{"trait":"AssistantBroadcast","text":"hi"}]}"#]]
        let mcp = [Self.step("USER_INPUT", "q"), Self.step("PLANNER_RESPONSE", "hi", calls: [viaHome])]
        #expect(ClaudeStopHook.textToSpeak(entries: AntigravityHook.parseTranscript(mcp.joined(separator: "\n"))) == nil)
    }

    @Test func onlyAFinishedIdleTurnIsSpoken() {
        #expect(AntigravityHook.isTurnEnd(["terminationReason": "NO_TOOL_CALL", "fullyIdle": true]))
        #expect(AntigravityHook.isTurnEnd([:]), "an older agy that sends neither")
        #expect(!AntigravityHook.isTurnEnd(["terminationReason": "USER_CANCELED", "fullyIdle": true]))
        #expect(!AntigravityHook.isTurnEnd(["terminationReason": "ERROR"]))
        #expect(!AntigravityHook.isTurnEnd(["terminationReason": "NO_TOOL_CALL", "fullyIdle": false]), "a background task will wake it")
    }

    @Test func theTailStartsOnAWholeLine() throws {
        let dir = scratch()
        let url = dir.appendingPathComponent("t.jsonl")
        try "aaaaaaaaaa\nbbbb\ncc\n".write(to: url, atomically: true, encoding: .utf8)
        #expect(AntigravityHook.readTail(of: url, bytes: 8) == "cc\n")
        #expect(AntigravityHook.readTail(of: url, bytes: 100) == "aaaaaaaaaa\nbbbb\ncc\n")
        #expect(AntigravityHook.readTail(of: dir.appendingPathComponent("none"), bytes: 8) == nil)
    }

    @Test func openCodesMessagesReadAsATurn() {
        let messages: [[String: Any]] = [
            ["info": ["role": "user"], "parts": [["type": "text", "text": "q1"]]],
            ["info": ["role": "assistant"], "parts": [["type": "text", "text": "old"]]],
            ["info": ["role": "user"], "parts": [["type": "text", "text": "q2"]]],
            ["info": ["role": "assistant"], "parts": [
                ["type": "step-start"],
                ["type": "tool", "tool": "bash", "state": ["status": "completed", "input": ["command": "ls"]]],
                ["type": "text", "text": "Listed it."],
                ["type": "text", "text": "reminder", "synthetic": true],
            ]],
        ]
        #expect(ClaudeStopHook.textToSpeak(entries: OpenCodeHook.parseMessages(messages)) == "Listed it.")

        var spoke = messages
        spoke[3] = ["info": ["role": "assistant"], "parts": [
            ["type": "tool", "tool": "bash", "state": ["input": ["command": "speaker-broadcast \"Listed it.\""]]],
            ["type": "text", "text": "Listed it."],
        ]]
        #expect(ClaudeStopHook.textToSpeak(entries: OpenCodeHook.parseMessages(spoke)) == nil)
    }

    @Test func openCodeV2ContextMessagesReadAsATurn() {
        let messages: [[String: Any]] = [
            ["id": "msg_1", "type": "user", "text": "first question"],
            ["id": "msg_2", "type": "assistant", "content": [["type": "text", "text": "older reply"]]],
            ["id": "msg_3", "type": "idle", "outcome": "succeeded"],
            ["id": "msg_4", "type": "user", "text": "second question"],
            ["id": "msg_5", "type": "assistant", "content": [
                ["type": "reasoning", "text": "thinking..."],
                ["type": "tool", "id": "call_1", "name": "shell", "state": ["status": "completed", "input": ["command": "ls -la"]]],
                ["type": "text", "text": "OpenCode 2.0 is ready."],
            ]],
            ["id": "msg_6", "type": "idle", "outcome": "succeeded"],
        ]
        #expect(ClaudeStopHook.textToSpeak(entries: OpenCodeHook.parseMessages(messages)) == "OpenCode 2.0 is ready.")

        var spokeInTool = messages
        spokeInTool[4] = ["id": "msg_5", "type": "assistant", "content": [
            ["type": "tool", "id": "call_1", "name": "shell", "state": ["status": "completed", "input": ["command": "speaker-broadcast \"OpenCode 2.0 is ready.\""]]],
            ["type": "text", "text": "OpenCode 2.0 is ready."],
        ]]
        #expect(ClaudeStopHook.textToSpeak(entries: OpenCodeHook.parseMessages(spokeInTool)) == nil)

        var spokeInShellEntry = messages
        spokeInShellEntry.insert(["id": "msg_4b", "type": "shell", "command": "speaker-broadcast \"OpenCode 2.0 is ready.\""], at: 4)
        #expect(ClaudeStopHook.textToSpeak(entries: OpenCodeHook.parseMessages(spokeInShellEntry)) == nil)
    }

    @Test func theDetachedAnnouncementSaysWhoItIsFor() {
        #expect(DetachedAnnouncement.arguments(text: "hi", agent: .claudeCode) == ["--announce", "hi"])
        #expect(DetachedAnnouncement.arguments(text: "hi", agent: .antigravity) == ["--announce", "hi", "--source", "antigravity"])
        #expect(DetachedAnnouncement.arguments(text: "hi", agent: .opencode) == ["--announce", "hi", "--source", "opencode"])
        for agent in CodingAgent.allCases {
            #expect(HomeSpeakerCommandLine.parse(DetachedAnnouncement.arguments(text: "hi", agent: agent)) == .announce("hi", agent))
        }
    }
}

/// The whole hook, from stdin to a speaker, with stand-ins.
@Suite struct AgentHookRunTests {
    private final class Calls: @unchecked Sendable {
        private let lock = NSLock()
        private var items: [String] = []
        func add(_ s: String) { lock.withLock { items.append(s) } }
        var all: [String] { lock.withLock { items } }
    }

    @MainActor private static func manager(_ dir: URL, antigravity: Bool = true, opencode: Bool = true) -> ConfigManager {
        let m = ConfigManager(configPath: dir.appendingPathComponent("c.json"),
                              historyPath: dir.appendingPathComponent("h.json"),
                              secrets: SecretStore(fileURL: dir.appendingPathComponent("s.json")))
        m.config.enabled = true
        m.config.effectiveSpeakHome = true
        m.config.effectiveSpeakLocal = false
        m.config.structureId = "s1"
        m.config.targets = ["kitchen": SpeakerDevice(id: "d1", type: "SPEAKER", name: "Kitchen speaker")]
        m.config.defaultTarget = "kitchen"
        m.config.effectiveAnnouncementStyle = .verbatim
        m.config.setAnnounces(.antigravity, antigravity)
        m.config.setAnnounces(.opencode, opencode)
        return m
    }

    /// Writes an Antigravity log folder: the cut-short transcript and the
    /// full one beside it, which the hook prefers.
    private static func antigravityLogs(_ dir: URL, reply: String) throws -> URL {
        let logs = dir.appendingPathComponent("logs")
        try FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
        let cut = [AgentTurnReaderTests.step("USER_INPUT", "q"), AgentTurnReaderTests.step("PLANNER_RESPONSE", "cut short")]
        let full = [AgentTurnReaderTests.step("USER_INPUT", "q"), AgentTurnReaderTests.step("PLANNER_RESPONSE", reply)]
        try cut.joined(separator: "\n").write(to: logs.appendingPathComponent("transcript.jsonl"), atomically: true, encoding: .utf8)
        try full.joined(separator: "\n").write(to: logs.appendingPathComponent("transcript_full.jsonl"), atomically: true, encoding: .utf8)
        return logs.appendingPathComponent("transcript.jsonl")
    }

    private static func runAntigravity(_ dir: URL, _ payload: [String: Any], manager: ConfigManager) async throws -> [String] {
        let home = Calls()
        let output = await HomeSpeakerCommandLine.stopHook(
            .antigravity, input: try JSONSerialization.data(withJSONObject: payload), config: { manager },
            history: BroadcastHistory(fileURL: dir.appendingPathComponent("hist.json")), standsAside: false,
            lockDirectory: dir, launchDetached: { _ in Issue.record("nothing goes detached here") }
        ) { text, _, _, _ in
            home.add(text)
            return true
        }
        #expect(output == CLIOutput(stdout: ["{}"]), "Antigravity always gets a JSON answer")
        return home.all
    }

    @Test func antigravitysHookSpeaksTheFullReplyOnce() async throws {
        let dir = scratch()
        let manager = await Self.manager(dir)
        let path = try Self.antigravityLogs(dir, reply: "The plugin is installed.")
        let payload: [String: Any] = ["transcriptPath": path.path, "terminationReason": "NO_TOOL_CALL", "fullyIdle": true]
        #expect(try await Self.runAntigravity(dir, payload, manager: manager) == ["The plugin is installed."])
        #expect(try await Self.runAntigravity(dir, payload, manager: manager).isEmpty, "the same words a moment later")
        let history = BroadcastHistory(fileURL: dir.appendingPathComponent("hist.json")).load()
        #expect(history.first?.source == "Antigravity")
    }

    @Test func antigravitysHookIsSilentWhenSwitchedOffOrNotDone() async throws {
        let dir = scratch()
        let path = try Self.antigravityLogs(dir, reply: "Not yet.")
        let off = await Self.manager(dir, antigravity: false)
        let done: [String: Any] = ["transcript_path": path.path]
        #expect(try await Self.runAntigravity(dir, done, manager: off).isEmpty)
        let on = await Self.manager(dir)
        let busy: [String: Any] = ["transcriptPath": path.path, "terminationReason": "NO_TOOL_CALL", "fullyIdle": false]
        #expect(try await Self.runAntigravity(dir, busy, manager: on).isEmpty)
    }

    @Test func openCodesHookSpeaksTheLastReplyAndHandsStylingOver() async throws {
        let dir = scratch()
        let manager = await Self.manager(dir)
        let payload: [String: Any] = ["sessionID": "ses_1", "messages": [
            ["info": ["role": "user"], "parts": [["type": "text", "text": "q"]]],
            ["info": ["role": "assistant"], "parts": [["type": "text", "text": "OpenCode is done."]]],
        ]]
        let input = try JSONSerialization.data(withJSONObject: payload)
        let history = BroadcastHistory(fileURL: dir.appendingPathComponent("hist.json"))
        let home = Calls()
        let output = await HomeSpeakerCommandLine.stopHook(
            .opencode, input: input, config: { manager }, history: history, standsAside: false, lockDirectory: dir,
            launchDetached: { _ in }
        ) { text, _, _, _ in
            home.add(text)
            return true
        }
        #expect(output == CLIOutput(stdout: ["{}"]))
        #expect(home.all == ["OpenCode is done."])
        #expect(history.load().first?.source == "OpenCode")

        // With a style, the reply goes to `--announce … --source opencode`, whole.
        await MainActor.run { manager.config.effectiveAnnouncementStyle = .plain }
        let other = scratch()
        let detached = Calls()
        _ = await HomeSpeakerCommandLine.stopHook(
            .opencode, input: input, config: { manager }, history: history, standsAside: false, lockDirectory: other,
            launchDetached: { detached.add($0) }
        ) { _, _, _, _ in
            Issue.record("a styled reply is not broadcast from the hook")
            return true
        }
        #expect(detached.all == ["OpenCode is done."])
    }

    @Test(arguments: [CodingAgent.antigravity, .opencode])
    func badInputAnswersAndSaysNothing(agent: CodingAgent) async {
        for input in [Data(), Data("garbage".utf8), Data("{}".utf8)] {
            let output = await HomeSpeakerCommandLine.stopHook(
                agent, input: input, config: { Issue.record("settings read for bad input"); return .shared },
                history: BroadcastHistory(fileURL: scratch().appendingPathComponent("h.json")), standsAside: false
            ) { _, _, _, _ in
                Issue.record("spoke on bad input")
                return false
            }
            #expect(output == CLIOutput(stdout: ["{}"]))
        }
    }
}
