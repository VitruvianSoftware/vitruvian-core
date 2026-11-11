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
import VitruvianCodeCore
import VitruvianCodeUI
import XCTest

@MainActor
final class OrcaFleetCatalogAndJumpTests: XCTestCase {

    // MARK: - 27+ Agent CLI Catalog & Stream Parsers

    func testCatalogContainsAllOrcaCLIAgentsAndDetectsInstalledBinaries() {
        let presets = VitruvianCodeCatalog.allPresets
        XCTAssertGreaterThanOrEqual(presets.count, 27)

        let expectedNames: Set<String> = [
            "Claude Code", "Codex", "Grok CLI", "Gemini CLI", "Cursor CLI",
            "GitHub Copilot CLI", "OpenCode", "Amp", "OpenClaude", "Antigravity",
            "Pi", "oh-my-pi", "Hermes Agent", "Devin CLI", "Goose", "Auggie",
            "Autohand Code", "Charm Crush", "Cline CLI", "CodeBuddy", "Codebuff",
            "Freebuff", "Command Code", "Continue CLI", "Droid", "Kilocode",
            "Kimi CLI", "Kiro CLI", "Mistral Vibe", "Qwen Code", "Rovo Dev",
        ]
        let actualNames = Set(presets.map(\.name))
        for expected in expectedNames {
            XCTAssertTrue(actualNames.contains(expected), "Missing preset: \(expected)")
        }

        let fakeBins: Set<String> = [
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/gemini",
            "/Users/tester/.local/bin/goose",
        ]
        let installed = VitruvianCodeCatalog.installedPresets(
            pathVariable: "/usr/bin:/bin",
            home: "/Users/tester",
            isExecutable: { fakeBins.contains($0) },
            fileExists: { fakeBins.contains($0) }
        )
        XCTAssertEqual(Set(installed.map(\.id)), ["codex", "gemini-cli", "goose"])

        let codexPreset = presets.first { $0.id == "codex" }!
        let provider = VitruvianCodeCatalog.toCLIProvider(codexPreset)
        XCTAssertEqual(provider.name, "Codex")
        XCTAssertFalse(provider.isBuiltIn)
        XCTAssertEqual(VitruvianCodeCatalog.toCLIProvider(presets.first { $0.id == "claude-code" }!), .claude)
    }

    func testCodexAndGeminiStreamEventParsers() {
        let codexStart = #"{"type":"thread.started","thread_id":"thr_abc123"}"#
        XCTAssertEqual(
            VitruvianCodeCatalog.parseCodexEventLine(codexStart),
            VitruvianCodeParsedEvent(kind: .started, sessionID: "thr_abc123")
        )

        let codexMsg = #"{"type":"item.completed","item":{"id":"msg_1","type":"agent_message","text":"Refactored parser."}}"#
        let parsedMsg = VitruvianCodeCatalog.parseCodexEventLine(codexMsg)
        XCTAssertEqual(parsedMsg?.kind, .text)
        XCTAssertEqual(parsedMsg?.text, "Refactored parser.")
        XCTAssertEqual(parsedMsg?.streamEvent, .text("Refactored parser."))

        let codexTool = #"{"type":"item.started","item":{"id":"call_9","type":"command_execution","command":"git status"}}"#
        let parsedTool = VitruvianCodeCatalog.parseCodexEventLine(codexTool)
        XCTAssertEqual(parsedTool?.kind, .toolUse)
        XCTAssertEqual(parsedTool?.toolName, "git status")

        let codexTurnDone = #"{"type":"turn.completed","thread_id":"thr_abc123","usage":{"input_tokens":512,"output_tokens":128}}"#
        let parsedDone = VitruvianCodeCatalog.parseCodexEventLine(codexTurnDone)
        XCTAssertEqual(parsedDone?.kind, .finished)
        XCTAssertEqual(parsedDone?.inputTokens, 512)
        XCTAssertEqual(parsedDone?.outputTokens, 128)

        let geminiInit = #"{"type":"init","session_id":"gem_42"}"#
        XCTAssertEqual(
            VitruvianCodeCatalog.parseGeminiEventLine(geminiInit),
            VitruvianCodeParsedEvent(kind: .started, sessionID: "gem_42")
        )

        let geminiDelta = #"{"type":"content_delta","session_id":"gem_42","text":"Hello from Gemini"}"#
        XCTAssertEqual(
            VitruvianCodeCatalog.parseGeminiEventLine(geminiDelta),
            VitruvianCodeParsedEvent(kind: .text, sessionID: "gem_42", text: "Hello from Gemini")
        )

        let geminiResult = #"{"type":"result","session_id":"gem_42","status":"success","stats":{"input_tokens":300,"output_tokens":75}}"#
        let parsedGeminiDone = VitruvianCodeCatalog.parseGeminiEventLine(geminiResult)
        XCTAssertEqual(parsedGeminiDone?.kind, .finished)
        XCTAssertEqual(parsedGeminiDone?.inputTokens, 300)
        XCTAssertEqual(parsedGeminiDone?.outputTokens, 75)
    }

    // MARK: - Multi-Account Switcher & 5h/7d Dual Quota

    func testMultiAccountProfilePersistenceSwitchingAndDualQuota() {
        var files: [String: String] = [
            "/Users/tester/.claude/work-creds.json": #"{"token":"work-secret"}"#,
            "/Users/tester/.claude/personal-creds.json": #"{"token":"personal-secret"}"#,
        ]
        let stateDir = "/Users/tester/Library/Application Support/Vitruvian Code"
        let liveCredPath = "/Users/tester/.claude/.credentials.json"

        let manager = VitruvianCodeAccountManager(
            stateDirectory: stateDir,
            targetCredentialPaths: ["Claude Code": liveCredPath],
            readFile: { files[$0] },
            writePrivateFile: { path, content in
                files[path] = content
                return true
            }
        )

        let workID = UUID()
        let personalID = UUID()
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let quota = VitruvianCodeDualQuotaWindow(
            fiveHourUsedPercent: 42.5,
            fiveHourResetsAt: now.addingTimeInterval(7_200),
            sevenDayUsedPercent: 84.0,
            sevenDayResetsAt: now.addingTimeInterval(172_800),
            planTier: "Max 20x"
        )
        XCTAssertTrue(quota.isNearLimit)
        XCTAssertEqual(quota.fiveHourResetCountdown(from: now), "2h 0m")
        XCTAssertEqual(quota.sevenDayResetCountdown(from: now), "2d 0h")

        manager.addProfile(VitruvianCodeAccountProfile(
            id: workID,
            providerName: "Claude Code",
            accountLabel: "Work",
            emailOrHandle: "eng@company.io",
            credentialFilePath: "/Users/tester/.claude/work-creds.json",
            isActive: true,
            quota: quota
        ))
        manager.addProfile(VitruvianCodeAccountProfile(
            id: personalID,
            providerName: "Claude Code",
            accountLabel: "Personal",
            emailOrHandle: "me@example.com",
            credentialFilePath: "/Users/tester/.claude/personal-creds.json",
            isActive: false
        ))

        XCTAssertEqual(manager.activeProfile(for: "Claude Code")?.id, workID)
        XCTAssertTrue(manager.switchAccount(id: personalID))
        XCTAssertEqual(manager.activeProfile(for: "Claude Code")?.id, personalID)
        XCTAssertEqual(files[liveCredPath], #"{"token":"personal-secret"}"#)

        let reloaded = VitruvianCodeAccountManager(
            stateDirectory: stateDir,
            targetCredentialPaths: ["Claude Code": liveCredPath],
            readFile: { files[$0] },
            writePrivateFile: { path, content in
                files[path] = content
                return true
            }
        )
        XCTAssertEqual(reloaded.profiles.count, 2)
        XCTAssertEqual(reloaded.activeProfile(for: "Claude Code")?.id, personalID)
    }

    // MARK: - Unified Inbox & Telemetry

    func testUnifiedInboxRecordingAndFleetStats() {
        let inbox = VitruvianCodeInboxCenter()
        XCTAssertEqual(inbox.unreadCount, 0)

        let approvalNotice = VitruvianCodeTurnNotice(
            providerName: "Claude Code",
            text: "Bash: rm -rf build/",
            failed: false,
            endedCleanly: false
        )
        inbox.recordApprovalNeeded(approvalNotice, sessionID: "sess-1", worktreeName: "feat-auth")
        XCTAssertEqual(inbox.unreadCount, 1)
        XCTAssertEqual(inbox.entries.first?.category, .needsApproval)

        let completedNotice = VitruvianCodeTurnNotice(
            providerName: "Codex",
            text: "All 14 tests pass.",
            failed: false,
            endedCleanly: true
        )
        inbox.recordTurnNotice(completedNotice, sessionID: "sess-2", worktreeName: "fix-parser", durationSeconds: 125)
        XCTAssertEqual(inbox.stats.agentsSpawned, 1)
        XCTAssertEqual(inbox.stats.totalAgentSeconds, 125)
        XCTAssertEqual(inbox.stats.formattedAgentTime, "2m 5s")
        XCTAssertEqual(inbox.unreadCount, 2)

        let failedNotice = VitruvianCodeTurnNotice(
            providerName: "Gemini CLI",
            text: "",
            failed: true,
            endedCleanly: false,
            failureDetail: "Process exited with code 1"
        )
        inbox.recordTurnNotice(failedNotice, sessionID: "sess-3", worktreeName: "feat-ui", durationSeconds: 40)
        XCTAssertEqual(inbox.entries.first?.category, .failed)
        XCTAssertEqual(inbox.entries.first?.summary, "Process exited with code 1")

        inbox.markRead(id: inbox.entries[0].id)
        XCTAssertEqual(inbox.unreadCount, 2)

        inbox.clearResolved()
        XCTAssertEqual(inbox.entries.count, 1)
        XCTAssertEqual(inbox.entries.first?.category, .needsApproval)
    }

    // MARK: - GitHub & Linear Tasks Service

    func testGitHubPRsAndIssuesParsingAndWorktreePrompts() {
        let prJSON = """
        [
          {
            "number": 412,
            "title": "Add multi-account quota bar",
            "headRefName": "feat/quota-bar",
            "url": "https://github.com/org/repo/pull/412",
            "state": "OPEN",
            "author": { "login": "wren" },
            "statusCheckRollup": [
              { "conclusion": "SUCCESS" },
              { "conclusion": "FAILURE" }
            ]
          }
        ]
        """
        let prs = VitruvianCodeTaskService.parseGitHubPRs(json: prJSON)
        XCTAssertEqual(prs.count, 1)
        XCTAssertEqual(prs[0].numberOrKey, "#412")
        XCTAssertEqual(prs[0].branchName, "feat/quota-bar")
        XCTAssertEqual(prs[0].ciPassing, false)
        XCTAssertEqual(prs[0].authorOrAssignee, "wren")
        XCTAssertTrue(VitruvianCodeTaskService.worktreePrompt(for: prs[0]).contains("failing"))

        let issueJSON = """
        [
          {
            "number": 89,
            "title": "Support 27 CLI agent harnesses in catalog!",
            "url": "https://github.com/org/repo/issues/89",
            "state": "OPEN",
            "author": { "login": "alice" }
          }
        ]
        """
        let issues = VitruvianCodeTaskService.parseGitHubIssues(json: issueJSON)
        XCTAssertEqual(issues.count, 1)
        XCTAssertEqual(issues[0].branchName, "issue/89-support-27-cli-agent-harnesses")
    }

    // MARK: - ⌘K Jump Palette Fuzzy Search

    func testJumpPaletteFuzzySearchRanking() {
        let targets: [VitruvianCodeJumpTarget] = [
            VitruvianCodeJumpTarget(id: "1", kind: .session, title: "Refactor Auth Middleware", subtitle: "Claude Code", badge: "Session", payload: "s1"),
            VitruvianCodeJumpTarget(id: "2", kind: .worktree, title: "feat-orca-fleet", subtitle: "/worktrees/feat-orca-fleet", badge: "Worktree", payload: "w1"),
            VitruvianCodeJumpTarget(id: "3", kind: .agentPreset, title: "Codex", subtitle: "codex exec --json", badge: "Agent", payload: "codex"),
            VitruvianCodeJumpTarget(id: "4", kind: .task, title: "#412 Add quota bar", subtitle: "GitHub PR", badge: "PR", payload: "412"),
        ]

        let codexHits = VitruvianCodeJumpSearch.filter(query: "codex", targets: targets)
        XCTAssertEqual(codexHits.first?.id, "3")

        let subseqHits = VitruvianCodeJumpSearch.filter(query: "fof", targets: targets)
        XCTAssertEqual(subseqHits.first?.id, "2")

        let prHits = VitruvianCodeJumpSearch.filter(query: "412", targets: targets)
        XCTAssertEqual(prHits.first?.id, "4")
    }

    func testEnableCatalogPresetPersistsToSavedProvidersAndDetectsInstalledIDs() throws {
        let rig = ComposerRig()
        let engine = VitruvianCodeEngine(environment: rig.environment, host: rig.host)
        let cursorPreset = try XCTUnwrap(VitruvianCodeCatalog.allPresets.first { $0.id == "cursor-cli" })

        engine.enableCatalogPreset(cursorPreset)
        XCTAssertEqual(engine.activeProvider.name, cursorPreset.name)
        XCTAssertTrue(rig.host.savedProviders.contains { $0.name == cursorPreset.name })
        XCTAssertTrue(engine.installedCatalogPresetIDs.contains("cursor-cli"))

        engine.load()
        XCTAssertEqual(engine.activeProvider.name, cursorPreset.name)
    }
}
