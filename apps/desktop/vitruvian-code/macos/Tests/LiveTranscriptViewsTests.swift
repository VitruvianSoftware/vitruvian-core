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
final class LiveTranscriptViewsTests: XCTestCase {
    // MARK: - Tool step mapping, merging, decoding, and security

    func testMakeToolStepMapsAllLocationsAndDiffs() {
        let call = ACPToolCall(
            toolCallId: "call-multi-1",
            title: "Update auth and router",
            kind: "edit",
            status: "completed",
            content: [
                .diff(path: "/repo/Sources/Auth.swift", oldText: "let a = 1", newText: "let a = 2"),
                .diff(path: "/repo/Sources/Router.swift", oldText: nil, newText: "let route = \"/v2\""),
                .content(.text("Applied 2 file changes")),
            ],
            locations: [
                ACPToolCallLocation(path: "/repo/Sources/Auth.swift", line: 42),
                ACPToolCallLocation(path: "/repo/Sources/Router.swift", line: nil),
                ACPToolCallLocation(path: "/repo/Tests/AuthTests.swift", line: 9),
            ]
        )

        let step = ACPConnection.makeToolStep(from: call)
        XCTAssertTrue(step.isFinished)
        XCTAssertFalse(step.isError)
        XCTAssertEqual(step.kind, .edit)
        XCTAssertEqual(step.filePath, "/repo/Sources/Auth.swift")
        XCTAssertEqual(step.diffOld, "let a = 1")
        XCTAssertEqual(step.diffNew, "let a = 2")
        XCTAssertEqual(step.output, "Applied 2 file changes")
        XCTAssertEqual(
            step.locations,
            [
                VitruvianCodeToolStep.Location(path: "/repo/Sources/Auth.swift", line: 42),
                VitruvianCodeToolStep.Location(path: "/repo/Sources/Router.swift", line: nil),
                VitruvianCodeToolStep.Location(path: "/repo/Tests/AuthTests.swift", line: 9),
            ]
        )
        XCTAssertEqual(
            step.diffs,
            [
                VitruvianCodeToolStep.Diff(path: "/repo/Sources/Auth.swift", oldText: "let a = 1", newText: "let a = 2"),
                VitruvianCodeToolStep.Diff(path: "/repo/Sources/Router.swift", oldText: nil, newText: "let route = \"/v2\""),
            ]
        )
    }

    func testToolCallUpdateMergingPreservesEarlierLocationsAndDiffs() {
        let initialCall = ACPToolCall(
            toolCallId: "call-merge-1",
            title: "Edit Config.swift",
            kind: "edit",
            status: "in_progress",
            content: [
                .diff(path: "/repo/Config.swift", oldText: "old", newText: "new"),
            ],
            locations: [
                ACPToolCallLocation(path: "/repo/Config.swift", line: 15),
                ACPToolCallLocation(path: "/repo/Other.swift", line: 3),
            ]
        )
        let emptyUpdate = ACPToolCall(
            toolCallId: "call-merge-1",
            title: nil,
            kind: nil,
            status: "completed",
            content: [.content(.text("Done"))],
            locations: []
        )

        let mergedACP = ACPConnection.mergeToolCall(previous: initialCall, incoming: emptyUpdate)
        let mergedStepFromACP = ACPConnection.makeToolStep(from: mergedACP)
        XCTAssertTrue(mergedStepFromACP.isFinished)
        XCTAssertEqual(mergedStepFromACP.locations.count, 2)
        XCTAssertEqual(mergedStepFromACP.diffs.count, 1)
        XCTAssertEqual(mergedStepFromACP.output, "Done")

        let initialStep = ACPConnection.makeToolStep(from: initialCall)
        let bareUpdateStep = VitruvianCodeToolStep(
            id: "call-merge-1",
            title: "Edit Config.swift",
            isFinished: true,
            kind: .other,
            filePath: nil,
            diffOld: nil,
            diffNew: nil,
            output: "Done",
            isError: false,
            locations: [],
            diffs: []
        )
        let mergedStep = initialStep.merging(with: bareUpdateStep)
        XCTAssertTrue(mergedStep.isFinished)
        XCTAssertEqual(mergedStep.kind, .edit)
        XCTAssertEqual(mergedStep.locations, initialStep.locations)
        XCTAssertEqual(mergedStep.diffs, initialStep.diffs)
        XCTAssertEqual(mergedStep.diffOld, "old")
        XCTAssertEqual(mergedStep.diffNew, "new")
        XCTAssertEqual(mergedStep.output, "Done")
    }

    func testDecodingLegacySavedToolStepWithoutLocationsOrDiffs() throws {
        let legacyJSON = """
        {
          "id": "legacy-1",
          "title": "Edit Sources/Legacy.swift",
          "detail": "edit_file",
          "isFinished": true,
          "kind": "edit",
          "filePath": "/repo/Sources/Legacy.swift",
          "diffOld": "var x = 1",
          "diffNew": "var x = 2",
          "output": "Updated",
          "isError": false
        }
        """
        let data = try XCTUnwrap(legacyJSON.data(using: .utf8))
        let decoded = try JSONDecoder().decode(VitruvianCodeToolStep.self, from: data)
        XCTAssertEqual(decoded.id, "legacy-1")
        XCTAssertEqual(decoded.filePath, "/repo/Sources/Legacy.swift")
        XCTAssertEqual(decoded.locations, [])
        XCTAssertEqual(decoded.diffs, [])
        XCTAssertEqual(
            decoded.effectiveLocations,
            [VitruvianCodeToolStep.Location(path: "/repo/Sources/Legacy.swift", line: nil)]
        )
        XCTAssertEqual(
            decoded.effectiveDiffs,
            [VitruvianCodeToolStep.Diff(path: "/repo/Sources/Legacy.swift", oldText: "var x = 1", newText: "var x = 2")]
        )
        XCTAssertTrue(decoded.hasDetail)

        var modern = decoded
        modern.locations = [VitruvianCodeToolStep.Location(path: "/repo/Sources/Legacy.swift", line: 27)]
        modern.diffs = [VitruvianCodeToolStep.Diff(path: "Sources/Legacy.swift", oldText: "var x = 1", newText: "var x = 2")]
        let encoded = try JSONEncoder().encode(modern)
        let roundTripped = try JSONDecoder().decode(VitruvianCodeToolStep.self, from: encoded)
        XCTAssertEqual(roundTripped, modern)
    }

    func testToolLocationRejectsNonFileURLsAndResolvesSafePaths() {
        for unsafe in [
            "https://evil.example.com/payload",
            "http://localhost:8080/run",
            "javascript:alert(1)",
            "ssh://host/repo/file.swift",
            "smb://server/share/file",
            "file://remote-host/etc/passwd",
            "/tmp/bad\0path.swift",
            "",
        ] {
            let loc = VitruvianCodeToolStep.Location(path: unsafe, line: 10)
            XCTAssertNil(
                VitruvianCodeToolStepDetail.safeLocationURL(for: loc, workingDirectory: "/workspace"),
                "Unsafe path must be rejected: \(unsafe)"
            )
            var opened: [URL] = []
            XCTAssertFalse(
                VitruvianCodeToolStepDetail.openLocation(loc, workingDirectory: "/workspace", openURL: { opened.append($0) })
            )
            XCTAssertTrue(opened.isEmpty)
        }

        let relative = VitruvianCodeToolStep.Location(path: "Sources/App.swift", line: 42)
        let resolvedRelative = VitruvianCodeToolStepDetail.safeLocationURL(for: relative, workingDirectory: "/workspace")
        XCTAssertEqual(resolvedRelative?.isFileURL, true)
        XCTAssertEqual(resolvedRelative?.path, "/workspace/Sources/App.swift")
        XCTAssertEqual(resolvedRelative?.fragment, "L42")

        var openedURLs: [URL] = []
        XCTAssertTrue(
            VitruvianCodeToolStepDetail.openLocation(relative, workingDirectory: "/workspace", openURL: { openedURLs.append($0) })
        )
        XCTAssertEqual(openedURLs, [try! XCTUnwrap(resolvedRelative)])

        // Relative path without a working directory cannot be placed safely.
        XCTAssertNil(VitruvianCodeToolStepDetail.safeLocationURL(for: relative, workingDirectory: nil))
    }

    func testLargeDiffIsCappedWithTruncationCount() {
        let oldText = (1...260).map { "line \($0)" }.joined(separator: "\n")
        let newText = (1...260).map { $0 == 1 ? "line 1 changed" : "line \($0)" }.joined(separator: "\n")
        let capped = VitruvianCodeLineDiff.cappedLines(old: oldText, new: newText)
        XCTAssertEqual(capped.lines.count, VitruvianCodeLineDiff.maxDisplayedLines)
        XCTAssertGreaterThan(capped.truncatedCount, 0)
    }

    // MARK: - Plan card state logic

    func testPlanCardStateAutoExpandsAndCollapses() {
        let strings = VitruvianCodeChatStrings()

        var state = AgentPlanCardState(entries: [])
        XCTAssertFalse(state.isVisible)
        XCTAssertFalse(state.isExpanded)

        let activeEntries = [
            PlanEntry(content: "Inspect files", status: .completed),
            PlanEntry(content: "Edit views", status: .inProgress),
            PlanEntry(content: "Run tests", status: .pending),
            PlanEntry(content: "Other step", status: .other),
        ]
        state.update(entries: activeEntries)
        XCTAssertTrue(state.isVisible)
        XCTAssertTrue(state.isExpanded, "unfinished plan must expand by default")
        XCTAssertEqual(state.completedCount, 1)
        XCTAssertEqual(state.totalCount, 4)
        XCTAssertEqual(state.inProgressIndex, 1)
        XCTAssertEqual(
            AgentPlanCardState.progressText(completed: state.completedCount, total: state.totalCount, strings: strings),
            "1 of 4 done"
        )

        // VoiceOver label includes each status.
        XCTAssertEqual(AgentPlanCardState.accessibilityLabel(for: activeEntries[0], strings: strings), "Completed: Inspect files")
        XCTAssertEqual(AgentPlanCardState.accessibilityLabel(for: activeEntries[1], strings: strings), "In progress: Edit views")
        XCTAssertEqual(AgentPlanCardState.accessibilityLabel(for: activeEntries[2], strings: strings), "Pending: Run tests")
        XCTAssertEqual(AgentPlanCardState.accessibilityLabel(for: activeEntries[3], strings: strings), "Other: Other step")

        // User collapse persists while still incomplete.
        state.toggle()
        XCTAssertFalse(state.isExpanded)
        state.update(entries: [
            PlanEntry(content: "Inspect files", status: .completed),
            PlanEntry(content: "Edit views", status: .completed),
            PlanEntry(content: "Run tests", status: .inProgress),
        ])
        XCTAssertFalse(state.isExpanded, "manual collapse stays respected while steps remain unfinished")

        // Completing all steps auto-collapses.
        state.toggle() // expand again
        XCTAssertTrue(state.isExpanded)
        state.update(entries: [
            PlanEntry(content: "Inspect files", status: .completed),
            PlanEntry(content: "Edit views", status: .completed),
            PlanEntry(content: "Run tests", status: .completed),
        ])
        XCTAssertTrue(state.allCompleted)
        XCTAssertFalse(state.isExpanded, "completed plan must auto-collapse")

        // Re-opening plan with new unfinished step auto-expands.
        state.update(entries: [
            PlanEntry(content: "Inspect files", status: .completed),
            PlanEntry(content: "Verify edge case", status: .inProgress),
        ])
        XCTAssertTrue(state.isExpanded)

        // Clearing on chat change hides card.
        var live = AgentLiveState()
        live.apply(.planReplaced(activeEntries))
        XCTAssertFalse(live.plan.isEmpty)
        live.reset()
        state.update(entries: live.plan)
        XCTAssertFalse(state.isVisible)
        XCTAssertFalse(state.isExpanded)
    }

    // MARK: - Timeline live metadata vs command-line isolation

    func testTimelineIncludesLiveToolsAndPlanWithoutChangingCommandLine() {
        let prompt1 = VitruvianCodeChatMessage(role: .user, text: "Inspect repo")
        let reply1 = VitruvianCodeChatMessage(
            role: .agent,
            text: "Inspected core types.",
            toolSteps: [
                VitruvianCodeToolStep(title: "Read AgentLiveState.swift", kind: .read),
                VitruvianCodeToolStep(title: "Edit ToolStepViews.swift", kind: .edit),
            ]
        )
        let prompt2 = VitruvianCodeChatMessage(role: .user, text: "Finish tests")
        let reply2 = VitruvianCodeChatMessage(
            role: .agent,
            text: "",
            toolSteps: [VitruvianCodeToolStep(title: "bazel test", isFinished: false, kind: .bash)]
        )
        let plan = [
            PlanEntry(content: "Inspect core", status: .completed),
            PlanEntry(content: "Run tests", status: .inProgress),
        ]

        // Command-line chat keeps tool/plan metadata empty.
        let cliTurns = VitruvianCodeTimeline.turns(from: [prompt1, reply1, prompt2, reply2])
        XCTAssertEqual(cliTurns.count, 2)
        XCTAssertEqual(cliTurns[0].toolStepCount, 0)
        XCTAssertEqual(cliTurns[0].toolStepTitles, [])
        XCTAssertNil(cliTurns[0].planProgress)
        XCTAssertNil(cliTurns[1].planProgress)

        // Live chat includes per-turn tool steps and latest-turn plan progress.
        let liveTurns = VitruvianCodeTimeline.turns(
            from: [prompt1, reply1, prompt2, reply2],
            livePlan: plan,
            includeLiveMetadata: true
        )
        XCTAssertEqual(liveTurns.count, 2)
        XCTAssertEqual(liveTurns[0].replySnippet, "Inspected core types.")
        XCTAssertEqual(liveTurns[0].toolStepCount, 2)
        XCTAssertEqual(liveTurns[0].toolStepTitles, ["Read AgentLiveState.swift", "Edit ToolStepViews.swift"])
        XCTAssertNil(liveTurns[0].planProgress)

        XCTAssertEqual(liveTurns[1].toolStepCount, 1)
        XCTAssertEqual(liveTurns[1].toolStepTitles, ["bazel test"])
        XCTAssertEqual(
            liveTurns[1].planProgress,
            VitruvianCodeTimeline.PlanProgress(completed: 1, total: 2, currentStep: "Run tests")
        )
        let strings = VitruvianCodeChatStrings()
        XCTAssertEqual(
            VitruvianCodeTimeline.toolStepsSummary(titles: liveTurns[0].toolStepTitles, count: liveTurns[0].toolStepCount, strings: strings),
            "2 tools: Read AgentLiveState.swift, Edit ToolStepViews.swift"
        )
        XCTAssertEqual(
            VitruvianCodeTimeline.toolStepsSummary(titles: liveTurns[1].toolStepTitles, count: liveTurns[1].toolStepCount, strings: strings),
            "1 tool: bazel test"
        )
    }

    // MARK: - Diff review source selection

    func testDiffReviewPrefersAgentReportedDiffsForLiveChatsAndFallsBackToGit() async throws {
        let user1 = VitruvianCodeChatMessage(role: .user, text: "Edit file A")
        let oldAgent = VitruvianCodeChatMessage(
            role: .agent,
            text: "Edited A",
            toolSteps: [
                VitruvianCodeToolStep(
                    title: "Edit A.swift",
                    kind: .edit,
                    diffs: [VitruvianCodeToolStep.Diff(path: "/repo/Sources/A.swift", oldText: "oldA", newText: "newA")]
                )
            ]
        )
        let user2 = VitruvianCodeChatMessage(role: .user, text: "Edit file B")
        let latestAgent = VitruvianCodeChatMessage(
            role: .agent,
            text: "Edited B",
            toolSteps: [
                VitruvianCodeToolStep(
                    title: "Edit B.swift",
                    kind: .edit,
                    diffs: [VitruvianCodeToolStep.Diff(path: "/repo/Sources/B.swift", oldText: "let x = 1", newText: "let x = 2\nlet y = 3")]
                )
            ]
        )
        let messages = [user1, oldAgent, user2, latestAgent]

        // Pure selection: live chat picks latest turn's agent-reported diffs only.
        let selection = VitruvianCodeQuickPromptSession.selectDiffReviewSource(
            isLiveChat: true,
            messages: messages,
            workingDirectory: "/repo"
        )
        guard case .agentReported(let selectedFiles) = selection else {
            return XCTFail("Expected .agentReported, got \(selection)")
        }
        XCTAssertEqual(selectedFiles.map(\.displayPath), ["Sources/B.swift"])
        XCTAssertEqual(selectedFiles[0].addedCount, 2)
        XCTAssertEqual(selectedFiles[0].removedCount, 1)

        // Command-line chat always uses git fallback even when steps have diffs.
        XCTAssertEqual(
            VitruvianCodeQuickPromptSession.selectDiffReviewSource(
                isLiveChat: false,
                messages: messages,
                workingDirectory: "/repo"
            ),
            .gitFallback
        )

        // Live chat without reported diffs on the latest turn falls back to git.
        XCTAssertEqual(
            VitruvianCodeQuickPromptSession.selectDiffReviewSource(
                isLiveChat: true,
                messages: [user2, VitruvianCodeChatMessage(role: .agent, text: "No edits")],
                workingDirectory: "/repo"
            ),
            .gitFallback
        )

        // End-to-end session refreshDiffReview check: live chat does NOT invoke git when diffs exist,
        // and falls back to git when the latest turn has no diffs.
        let gitCalls = LockedCounter()
        let domain = "com.vitruviansoftware.vitruvian-code.tests.live-transcript.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(ScratchDefaults.suite(named: domain))
        defaults.removePersistentDomain(forName: domain)
        defer { defaults.removePersistentDomain(forName: domain) }
        let env = VitruvianCodeEngine.Environment(
            defaults: defaults,
            home: "/tmp",
            processEnvironment: [:],
            stateDirectory: "/tmp/vitruvian-code-test-state",
            isExecutable: { _ in false },
            fileExists: { _ in true },
            readFile: { _ in nil },
            readTail: { _, _ in nil },
            writePrivateFile: { _, _ in true },
            removeFile: { _ in },
            isBotProcess: { _ in false },
            signal: { _, _ in },
            launchBot: { _, _, _, _, _ in 1 },
            schedule: { _, _ in },
            openFile: { _ in },
            launchAgent: { _, _, _, _, _, _ in throw CocoaError(.featureUnsupported) },
            runProgram: { program, _ in
                if program == "git" {
                    gitCalls.increment()
                }
                return """
                diff --git a/Sources/GitFile.swift b/Sources/GitFile.swift
                --- a/Sources/GitFile.swift
                +++ b/Sources/GitFile.swift
                @@ -1,1 +1,1 @@
                -let g = 0
                +let g = 1
                """
            }
        )
        let session = VitruvianCodeQuickPromptSession(environment: env, host: TestDiffReviewHost())
        var liveProvider = VitruvianCodeCLIProvider.antigravity
        liveProvider.connection = .acp
        let liveConfig = VitruvianCodeConfiguration(workingDirectory: "/repo", activeProvider: liveProvider)

        session.messages = messages
        session.refreshDiffReview(configuration: liveConfig)
        XCTAssertEqual(session.diffReviewSession.source, .agentReported)
        XCTAssertEqual(session.diffReviewSession.files.map(\.displayPath), ["Sources/B.swift"])
        XCTAssertEqual(gitCalls.value, 0)

        // Fallback to git when latest turn has no diffs.
        session.messages = [user2, VitruvianCodeChatMessage(role: .agent, text: "Done")]
        session.refreshDiffReview(configuration: liveConfig)
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertGreaterThanOrEqual(gitCalls.value, 1)
        XCTAssertEqual(session.diffReviewSession.source, .git)
        XCTAssertEqual(session.diffReviewSession.files.map(\.displayPath), ["Sources/GitFile.swift"])
    }
}

private final class LockedCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var value: Int {
        lock.withLock { count }
    }

    func increment() {
        lock.withLock { count += 1 }
    }
}

@MainActor
private final class TestDiffReviewHost: VitruvianCodeHost {
    var configuredBotDirectory = ""
    var startsBotAtLaunch = false
    var planMode = false
    var hiddenClaudeSessionIDs: [String] = []
    var chosenProviderID: UUID? = VitruvianCodeCLIProvider.antigravity.id
    var chosenModels: [UUID: String] = [:]
    var savedProviders: [VitruvianCodeCLIProvider] = []
    var promptHistory: [String] = []
    var worktreeMode = false
    var timelineOnLeft = true
    var sessionPreferences = VitruvianCodeSessionPreferences()
    var chatModes: [String: String] = [:]
    var showsConnectionSetting = false
    var strings = VitruvianCodeHostStrings()

    func turnNeedsApproval(_ notice: VitruvianCodeTurnNotice) {}
    func turnFinished(_ notice: VitruvianCodeTurnNotice, isChatVisible: Bool) {}
}
