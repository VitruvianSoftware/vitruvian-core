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
@testable import VitruvianCodeCore
@testable import VitruvianCodeUI
import XCTest

@MainActor
final class ChatModesTests: XCTestCase {

    // MARK: - .auto approval mode and globalChoices / .env

    func testAutoApprovalModeIsAbsentFromGlobalChoicesAndNeverWrittenToEnv() {
        XCTAssertEqual(VitruvianCodeApprovalMode.auto.rawValue, "auto")
        XCTAssertTrue(VitruvianCodeApprovalMode.allCases.contains(.auto))
        XCTAssertFalse(VitruvianCodeApprovalMode.globalChoices.contains(.auto))
        XCTAssertEqual(
            VitruvianCodeApprovalMode.globalChoices,
            [.yolo, .acceptEdits, .plan, .standard]
        )

        let autoConfig = VitruvianCodeConfiguration(
            botToken: "123:abc",
            approvalMode: .auto,
            activeProvider: .claude
        )

        // Fresh .env: .auto falls back to standard (empty value), never "auto".
        let renderedFresh = VitruvianCodeEnvFile.render(autoConfig, over: nil)
        XCTAssertFalse(renderedFresh.contains("AGY_APPROVAL_MODE=auto"))
        XCTAssertEqual(VitruvianCodeEnvFile.parse(renderedFresh).approvalMode, .standard)

        // Existing .env with a valid bot mode keeps that mode when configuration holds .auto.
        let existingAcceptEdits = "TELEGRAM_BOT_TOKEN=123:abc\nAGY_APPROVAL_MODE=accept-edits\n"
        let renderedOverExisting = VitruvianCodeEnvFile.render(autoConfig, over: existingAcceptEdits)
        XCTAssertFalse(renderedOverExisting.contains("AGY_APPROVAL_MODE=auto"))
        XCTAssertEqual(VitruvianCodeEnvFile.parse(renderedOverExisting).approvalMode, .acceptEdits)

        // Existing .env that somehow had "auto" is sanitized to standard, never kept as "auto".
        let existingAuto = "TELEGRAM_BOT_TOKEN=123:abc\nAGY_APPROVAL_MODE=auto\n"
        let renderedSanitized = VitruvianCodeEnvFile.render(autoConfig, over: existingAuto)
        XCTAssertFalse(renderedSanitized.contains("AGY_APPROVAL_MODE=auto"))
        XCTAssertEqual(VitruvianCodeEnvFile.parse(renderedSanitized).approvalMode, .standard)

        // Connection choices per provider match step 1b rules.
        XCTAssertEqual(VitruvianCodeCLIProvider.antigravity.availableConnections, [nil, .commandLine, .acp])
        XCTAssertEqual(
            VitruvianCodeCLIProvider.claude.availableConnections,
            [nil, .commandLine, .claudeSDK, .claudeACP]
        )
        XCTAssertEqual(VitruvianCodeCLIProvider.ollama.availableConnections, [nil, .commandLine])
        XCTAssertEqual(VitruvianCodeCLIProvider.opencode.availableConnections, [nil, .commandLine])
    }

    // MARK: - Per-chat approval mode and /plan persistence

    func testPerChatModeSurvivesSaveReopenAndNewChat() {
        let rig = ComposerRig()
        rig.host.planMode = false
        let config = VitruvianCodeConfiguration(approvalMode: .yolo, activeProvider: .claude)
        let session = rig.session()

        XCTAssertNil(session.chatApprovalMode)
        XCTAssertNil(session.chatPlanMode)
        XCTAssertEqual(session.effectiveApprovalMode(for: config), .yolo)
        XCTAssertFalse(session.effectivePlanMode)

        // Set per-chat approval mode to .auto and toggle /plan in this chat.
        session.chatApprovalMode = .auto
        let slashResult = session.runSlashCommand("/plan", configuration: config, agentPath: "/fake/claude")
        XCTAssertEqual(slashResult, .planMode(true))
        XCTAssertEqual(session.chatPlanMode, true)
        XCTAssertFalse(rig.host.planMode, "/plan changes only this chat, leaving host.planMode untouched")
        XCTAssertEqual(session.effectiveApprovalMode(for: config), .auto)
        XCTAssertTrue(session.effectivePlanMode)
        XCTAssertEqual(session.turnConfiguration(config).approvalMode, .plan)

        // Sending a turn assigns conversationID and persists "<raw>|plan" in host.chatModes.
        session.send("draft plan", configuration: config, agentPath: "/fake/claude")
        rig.agentOutput?(Data(#"{"type":"system","subtype":"init","session_id":"conv-mode-1"}"#.utf8 + Data("\n".utf8)))
        rig.agentOutput?(Data(#"{"type":"result","stop_reason":"end_turn","session_id":"conv-mode-1","result":"planned"}"#.utf8 + Data("\n".utf8)))
        rig.finishCleanly()

        XCTAssertEqual(session.conversationID, "conv-mode-1")
        XCTAssertEqual(rig.host.chatModes["conv-mode-1"], "auto|plan")

        // New chat clears per-chat overrides back to host/global defaults while keeping saved conversation entry.
        session.newChat()
        XCTAssertNil(session.chatApprovalMode)
        XCTAssertNil(session.chatPlanMode)
        XCTAssertEqual(session.effectiveApprovalMode(for: config), .yolo)
        XCTAssertFalse(session.effectivePlanMode)
        XCTAssertEqual(rig.host.chatModes["conv-mode-1"], "auto|plan")

        // Reopening the saved conversation in a fresh session restores both chatApprovalMode and chatPlanMode.
        let reopened = rig.session()
        reopened.resume(
            VitruvianCodeSessionSummary(id: "conv-mode-1", title: "Draft plan", steps: 2, modified: nil),
            configuration: config
        )
        XCTAssertEqual(reopened.chatApprovalMode, .auto)
        XCTAssertEqual(reopened.chatPlanMode, true)
        XCTAssertEqual(reopened.effectiveApprovalMode(for: config), .auto)
        XCTAssertTrue(reopened.effectivePlanMode)
        XCTAssertEqual(reopened.turnConfiguration(config).approvalMode, .plan)

        // Toggling /plan off in the reopened conversation stores an explicit "|noplan" next to the mode.
        _ = reopened.runSlashCommand("/plan", configuration: config, agentPath: "/fake/claude")
        XCTAssertEqual(reopened.chatPlanMode, false)
        XCTAssertFalse(reopened.effectivePlanMode)
        XCTAssertEqual(rig.host.chatModes["conv-mode-1"], "auto|noplan")
        XCTAssertEqual(reopened.turnConfiguration(config).approvalMode, .auto)
    }

    // MARK: - --state-dir override

    func testStateDirOverrideMovesEveryDerivedPathUnderOverride() {
        XCTAssertNil(try VitruvianCodeSupport.stateDirectoryOverride(arguments: ["/Applications/VitruvianCode"]))
        XCTAssertEqual(
            try VitruvianCodeSupport.stateDirectoryOverride(
                arguments: ["/Applications/VitruvianCode", "--state-dir", "/tmp/isolated-run/"]
            ),
            "/tmp/isolated-run"
        )
        XCTAssertEqual(
            try VitruvianCodeSupport.stateDirectoryOverride(
                arguments: ["/Applications/VitruvianCode", "--state-dir=/tmp/isolated-eq/"]
            ),
            "/tmp/isolated-eq"
        )

        let rig = ComposerRig()
        rig.host.configuredBotDirectory = "/Users/rig/real-bot-folder"
        let overrideRoot = "/tmp/vc-isolated-test-copy"

        var env = rig.environment
        env.stateDirectoryOverride = overrideRoot
        let engine = VitruvianCodeEngine(environment: env, host: rig.host)

        let derivedPaths = [
            engine.botDirectory,
            engine.envFilePath,
            engine.envExamplePath,
            engine.stateDirectory,
            engine.pidFilePath,
            engine.logsDirectory,
            engine.logPath,
            engine.session.accountManager.stateDirectory,
            engine.session.automationManager.stateDirectory.path,
            engine.session.orchestrationCoordinator.worktreeRoot,
        ]

        for path in derivedPaths {
            XCTAssertTrue(
                path.hasPrefix(overrideRoot + "/"),
                "expected \(path) to live under \(overrideRoot)"
            )
            XCTAssertFalse(
                path.hasPrefix("/Users/rig"),
                "expected \(path) not to touch /Users/rig"
            )
        }

        XCTAssertEqual(engine.botDirectory, "/tmp/vc-isolated-test-copy/bot")
        XCTAssertEqual(engine.envFilePath, "/tmp/vc-isolated-test-copy/bot/.env")
        XCTAssertEqual(engine.envExamplePath, "/tmp/vc-isolated-test-copy/bot/.env.example")
        XCTAssertEqual(engine.stateDirectory, "/tmp/vc-isolated-test-copy/state")
        XCTAssertEqual(engine.pidFilePath, "/tmp/vc-isolated-test-copy/state/.bot.pid")
        XCTAssertEqual(engine.logsDirectory, "/tmp/vc-isolated-test-copy/logs")
        XCTAssertEqual(engine.logPath, "/tmp/vc-isolated-test-copy/logs/bot.log")
        XCTAssertEqual(engine.session.accountManager.stateDirectory, "/tmp/vc-isolated-test-copy/state")
        XCTAssertEqual(engine.session.automationManager.stateDirectory.path, "/tmp/vc-isolated-test-copy/state")
        XCTAssertEqual(engine.session.orchestrationCoordinator.worktreeRoot, "/tmp/vc-isolated-test-copy/worktrees")
    }

    // MARK: - --state-dir: validation and separate preferences

    func testStateDirMustBeAnAbsolutePath() {
        for bad in ["relative/dir", "./here", "../up", "~/home-relative", "  "] {
            XCTAssertThrowsError(
                try VitruvianCodeSupport.stateDirectoryOverride(arguments: ["app", "--state-dir", bad]),
                "\(bad) must be refused"
            )
        }
        XCTAssertThrowsError(try VitruvianCodeSupport.stateDirectoryOverride(arguments: ["app", "--state-dir"])) {
            XCTAssertEqual($0 as? VitruvianCodeSupport.StateDirectoryError, .missingValue)
        }
        XCTAssertThrowsError(try VitruvianCodeSupport.stateDirectoryOverride(arguments: ["app", "--state-dir=rel"])) {
            XCTAssertEqual($0 as? VitruvianCodeSupport.StateDirectoryError, .notAbsolute("rel"))
        }
        let message = VitruvianCodeSupport.StateDirectoryError.notAbsolute("rel").description
        XCTAssertTrue(message.contains("absolute path") && message.contains("\"rel\""), message)
    }

    func testStateDirPreferencesSuiteIsStableAndSeparatePerFolder() {
        let a = VitruvianCodeSupport.preferencesSuiteName(bundleIdentifier: "com.example.app", stateDirectory: "/tmp/a")
        XCTAssertEqual(a, VitruvianCodeSupport.preferencesSuiteName(bundleIdentifier: "com.example.app", stateDirectory: "/tmp/a"))
        XCTAssertNotEqual(a, VitruvianCodeSupport.preferencesSuiteName(bundleIdentifier: "com.example.app", stateDirectory: "/tmp/b"))
        XCTAssertTrue(a.hasPrefix("com.example.app.statedir."))
        XCTAssertEqual(a.count, "com.example.app.statedir.".count + 16)
        // FNV-1a of "/tmp/a" is fixed, so the name is the same on every launch.
        XCTAssertEqual(a, "com.example.app.statedir.6cc13bddf2746ce7")
    }

    func testTheEngineOfAStateDirCopyGetsItsOwnPreferencesNotTheStandardOnes() {
        let folder = "/tmp/vc-prefs-\(UUID().uuidString)"
        let isolated = VitruvianCodeEngine.Environment.live(stateDirectoryOverride: folder)
        let key = "vitruvian-code-tests.statedir.probe.\(UUID().uuidString)"
        isolated.defaults.set("only here", forKey: key)
        defer {
            isolated.defaults.removeObject(forKey: key)
            let name = VitruvianCodeSupport.preferencesSuiteName(
                bundleIdentifier: Bundle.main.bundleIdentifier ?? "com.vitruviansoftware.vitruvian-code",
                stateDirectory: folder
            )
            isolated.defaults.removePersistentDomain(forName: name)
        }
        XCTAssertEqual(isolated.defaults.string(forKey: key), "only here")
        XCTAssertNil(UserDefaults.standard.object(forKey: key), "the copy must not write the real app's settings")

        // No override: the standard settings, as before.
        let normal = VitruvianCodeEngine.Environment.live(stateDirectoryOverride: nil)
        XCTAssertNil(normal.defaults.object(forKey: key), "and the real app does not see the copy's")
    }

    // MARK: - Hidden Connection picker flag is in memory only

    func testShowingTheConnectionSettingIsNeverSaved() throws {
        let host = try appSource("StandaloneHost.swift")
        XCTAssertTrue(host.contains("var showsConnectionSetting = false {"), "kept on the instance")
        XCTAssertFalse(host.contains("\"showsConnectionSetting\""), "never a saved key")
    }

    // MARK: - Per-chat overrides are independent

    func testAPlanOnlyChatStillFollowsALaterChangeOfTheGlobalApprovalMode() {
        let rig = ComposerRig()
        let session = rig.session()
        var config = VitruvianCodeConfiguration(approvalMode: .yolo, activeProvider: .claude)
        session.send("hello", configuration: config, agentPath: "/fake/claude")
        rig.agentOutput?(Data(#"{"type":"system","subtype":"init","session_id":"conv-plan-only"}"#.utf8 + Data("\n".utf8)))
        rig.finishCleanly()
        XCTAssertEqual(session.conversationID, "conv-plan-only")

        _ = session.runSlashCommand("/plan", configuration: config, agentPath: "/fake/claude")
        XCTAssertNil(session.chatApprovalMode, "only the plan switch is the chat's own")
        XCTAssertEqual(rig.host.chatModes["conv-plan-only"], "|plan", "the mode part is empty")

        // The global mode changes later: the chat's mode follows it.
        config.approvalMode = .standard
        XCTAssertEqual(session.effectiveApprovalMode(for: config), .standard)

        // And after a reopen it still does: nothing froze the old global mode.
        let reopened = rig.session()
        reopened.resume(
            VitruvianCodeSessionSummary(id: "conv-plan-only", title: "t", steps: 1, modified: nil),
            configuration: config
        )
        XCTAssertNil(reopened.chatApprovalMode)
        XCTAssertEqual(reopened.chatPlanMode, true)
        XCTAssertEqual(reopened.effectiveApprovalMode(for: config), .standard)
        config.approvalMode = .acceptEdits
        XCTAssertEqual(reopened.effectiveApprovalMode(for: config), .acceptEdits)

        // A mode-only chat is stored as the bare mode.
        XCTAssertEqual(VitruvianCodeQuickPromptSession.encodeChatMode(mode: .standard, plan: nil), "default")
        XCTAssertEqual(VitruvianCodeQuickPromptSession.encodeChatMode(mode: nil, plan: true), "|plan")
        XCTAssertEqual(VitruvianCodeQuickPromptSession.encodeChatMode(mode: nil, plan: false), "|noplan")
        XCTAssertNil(VitruvianCodeQuickPromptSession.encodeChatMode(mode: nil, plan: nil))
        let modeOnly = VitruvianCodeQuickPromptSession.decodeChatMode("default")
        XCTAssertEqual(modeOnly?.mode, .standard)
        XCTAssertNil(modeOnly?.plan)
        XCTAssertNil(VitruvianCodeQuickPromptSession.decodeChatMode("nonsense|plan"))
    }

    func testThePlanButtonTogglesTheChatsOverrideNeverTheHostsPlanMode() {
        let rig = ComposerRig()
        rig.host.planMode = false
        let session = rig.session()
        XCTAssertFalse(session.planMode)

        // The button sets `session.planMode` (a toggle on the binding).
        session.planMode.toggle()
        XCTAssertTrue(session.planMode)
        XCTAssertEqual(session.chatPlanMode, true, "the chat has its own override now")
        XCTAssertFalse(rig.host.planMode, "the button never writes the host's plan mode")

        session.planMode = false
        XCTAssertEqual(session.chatPlanMode, false)
        XCTAssertFalse(rig.host.planMode)

        session.newChat()
        XCTAssertNil(session.chatPlanMode)
        rig.host.planMode = true
        session.hostPlanModeDidChange()
        XCTAssertTrue(session.planMode, "a chat without an override follows the host's new starting value")
        XCTAssertNil(session.chatPlanMode)
    }

    func testTheBadgeShowsTheChatsEffectiveModeNotTheGlobalOne() {
        let rig = ComposerRig()
        let session = rig.session()
        let global = VitruvianCodeConfiguration(approvalMode: .yolo, activeProvider: .claude)
        XCTAssertEqual(ChatApprovalModeBadge.current(session: session, configuration: global), .yolo)

        session.chatApprovalMode = .standard
        XCTAssertEqual(ChatApprovalModeBadge.current(session: session, configuration: global), .standard,
                       "the chat's own mode, not the global yolo")

        session.planMode = true
        XCTAssertEqual(ChatApprovalModeBadge.current(session: session, configuration: global), .plan)
        session.planMode = false
        session.newChat()
        XCTAssertEqual(ChatApprovalModeBadge.current(session: session, configuration: global), .yolo)
    }

    private func appSource(_ name: String) throws -> String {
        let relative = "apps/desktop/vitruvian-code/macos/Sources/VitruvianCode/\(name)"
        var candidates: [String] = []
        let environment = ProcessInfo.processInfo.environment
        if let runfiles = environment["TEST_SRCDIR"] {
            for workspace in [environment["TEST_WORKSPACE"], "_main"].compactMap({ $0 }) {
                candidates.append("\(runfiles)/\(workspace)/\(relative)")
            }
        }
        let here = (#filePath as NSString).deletingLastPathComponent
        candidates.append((here as NSString).deletingLastPathComponent + "/Sources/VitruvianCode/\(name)")
        let path = try XCTUnwrap(candidates.first { FileManager.default.fileExists(atPath: $0) }, "cannot find \(name)")
        return try String(contentsOfFile: path, encoding: .utf8)
    }
}
