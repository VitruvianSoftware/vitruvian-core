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
        await session.waitForDiffReviewRefresh()
        XCTAssertEqual(session.diffReviewSession.source, .agentReported)
        XCTAssertEqual(session.diffReviewSession.files.map(\.displayPath), ["Sources/B.swift"])
        XCTAssertEqual(gitCalls.value, 0)

        // Fallback to git when latest turn has no diffs.
        session.messages = [user2, VitruvianCodeChatMessage(role: .agent, text: "Done")]
        session.refreshDiffReview(configuration: liveConfig)
        await session.waitForDiffReviewRefresh()
        XCTAssertGreaterThanOrEqual(gitCalls.value, 1)
        XCTAssertEqual(session.diffReviewSession.source, .git)
        XCTAssertEqual(session.diffReviewSession.files.map(\.displayPath), ["Sources/GitFile.swift"])
    }

    // MARK: - Round 1 defect regression tests

    func testToolLocationOpenActionSafety() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("vitruvian-loc-safety-\(UUID().uuidString)")
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }

        let cRealRoot = Darwin.realpath(root.path, nil)
        defer { free(cRealRoot) }
        let realRoot = URL(fileURLWithPath: String(cString: try XCTUnwrap(cRealRoot)), isDirectory: true)

        let commandURL = realRoot.appendingPathComponent("run.command")
        try "#!/bin/sh\necho pwned\n".write(to: commandURL, atomically: true, encoding: .utf8)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: commandURL.path)
        XCTAssertEqual(
            VitruvianCodeToolStepDetail.locationOpenAction(for: commandURL),
            .openAsText(commandURL),
            ".command script must open as plain text, never execute"
        )

        let appBundleURL = realRoot.appendingPathComponent("Fake.app", isDirectory: true)
        let contentsURL = appBundleURL.appendingPathComponent("Contents", isDirectory: true)
        try fm.createDirectory(at: contentsURL, withIntermediateDirectories: true)
        try "{}".write(to: contentsURL.appendingPathComponent("Info.plist"), atomically: true, encoding: .utf8)
        XCTAssertEqual(
            VitruvianCodeToolStepDetail.locationOpenAction(for: appBundleURL),
            .reveal(appBundleURL),
            ".app bundle must be revealed in Finder, never launched"
        )

        let symlinkToCommand = realRoot.appendingPathComponent("alias-to-script")
        try fm.createSymbolicLink(at: symlinkToCommand, withDestinationURL: commandURL)
        XCTAssertEqual(
            VitruvianCodeToolStepDetail.locationOpenAction(for: symlinkToCommand),
            .openAsText(commandURL),
            "symlink to .command must resolve to its real target and open as text"
        )

        let symlinkToApp = realRoot.appendingPathComponent("innocent.txt")
        try fm.createSymbolicLink(at: symlinkToApp, withDestinationURL: appBundleURL)
        XCTAssertEqual(
            VitruvianCodeToolStepDetail.locationOpenAction(for: symlinkToApp),
            .reveal(appBundleURL),
            "symlink named .txt pointing to .app must resolve before deciding"
        )

        let swiftURL = realRoot.appendingPathComponent("Auth.swift")
        try "struct Auth {}\n".write(to: swiftURL, atomically: true, encoding: .utf8)
        var components = URLComponents(url: swiftURL, resolvingAgainstBaseURL: false)
        components?.fragment = "L42"
        let swiftWithLineURL = try XCTUnwrap(components?.url)
        XCTAssertEqual(
            VitruvianCodeToolStepDetail.locationOpenAction(for: swiftWithLineURL),
            .openAsText(swiftURL)
        )

        let subDirURL = realRoot.appendingPathComponent("Sources", isDirectory: true)
        try fm.createDirectory(at: subDirURL, withIntermediateDirectories: true)
        XCTAssertEqual(
            VitruvianCodeToolStepDetail.locationOpenAction(for: subDirURL),
            .reveal(subDirURL)
        )

        let binaryURL = realRoot.appendingPathComponent("archive.bin")
        try Data([0x00, 0xFF, 0x7F, 0x45]).write(to: binaryURL)
        XCTAssertEqual(
            VitruvianCodeToolStepDetail.locationOpenAction(for: binaryURL),
            .reveal(binaryURL)
        )

        let missingURL = realRoot.appendingPathComponent("Missing.swift")
        XCTAssertEqual(
            VitruvianCodeToolStepDetail.locationOpenAction(for: missingURL),
            .none
        )

        let brokenSymlink = realRoot.appendingPathComponent("broken.swift")
        try fm.createSymbolicLink(at: brokenSymlink, withDestinationURL: missingURL)
        XCTAssertEqual(
            VitruvianCodeToolStepDetail.locationOpenAction(for: brokenSymlink),
            .none
        )
    }

    func testDiffReviewExcludesPendingFailedAndDeniedSteps() {
        let user = VitruvianCodeChatMessage(role: .user, text: "Edit files")
        let pendingStep = VitruvianCodeToolStep(
            id: "step-pending",
            title: "Edit Pending.swift",
            isFinished: false,
            kind: .edit,
            isError: false,
            diffs: [VitruvianCodeToolStep.Diff(path: "Sources/Pending.swift", oldText: "a", newText: "b")]
        )
        let failedStep = VitruvianCodeToolStep(
            id: "step-failed",
            title: "Edit Failed.swift",
            isFinished: true,
            kind: .edit,
            isError: true,
            diffs: [VitruvianCodeToolStep.Diff(path: "Sources/Failed.swift", oldText: "c", newText: "d")]
        )
        let deniedStepWithoutErrorFlag = VitruvianCodeToolStep(
            id: "step-denied",
            title: "Edit Denied.swift",
            isFinished: true,
            kind: .edit,
            isError: false,
            diffs: [VitruvianCodeToolStep.Diff(path: "Sources/Denied.swift", oldText: "e", newText: "f")]
        )
        let deniedApprovalMsg = VitruvianCodeChatMessage(
            role: .agent,
            text: "",
            toolSteps: [pendingStep, failedStep, deniedStepWithoutErrorFlag],
            approvalRequest: VitruvianCodeApprovalRequest(
                id: "step-denied",
                toolName: "Edit",
                commandOrPath: "Sources/Denied.swift",
                status: .denied,
                requestID: "perm-denied"
            )
        )

        // When only pending, failed, and denied steps exist, no diffs may appear in diff review.
        XCTAssertTrue(VitruvianCodeQuickPromptSession.latestTurnReportedDiffs(from: [user, deniedApprovalMsg]).isEmpty)
        XCTAssertEqual(
            VitruvianCodeQuickPromptSession.selectDiffReviewSource(
                isLiveChat: true,
                messages: [user, deniedApprovalMsg],
                workingDirectory: "/repo"
            ),
            .gitFallback
        )

        // Approved finished non-error step in the same turn is included while the others stay excluded.
        let completedStep = VitruvianCodeToolStep(
            id: "step-ok",
            title: "Edit Ok.swift",
            isFinished: true,
            kind: .edit,
            isError: false,
            diffs: [VitruvianCodeToolStep.Diff(path: "Sources/Ok.swift", oldText: "g", newText: "h")]
        )
        let okMsg = VitruvianCodeChatMessage(
            role: .agent,
            text: "Done",
            toolSteps: [completedStep],
            approvalRequest: VitruvianCodeApprovalRequest(
                id: "step-ok",
                toolName: "Edit",
                commandOrPath: "Sources/Ok.swift",
                status: .approved,
                requestID: "perm-ok"
            )
        )
        let diffs = VitruvianCodeQuickPromptSession.latestTurnReportedDiffs(from: [user, deniedApprovalMsg, okMsg])
        XCTAssertEqual(diffs.map(\.path), ["Sources/Ok.swift"])
    }

    func testACPDeniedPermissionMarksToolStepError() {
        let options = [
            AgentPermissionOption(id: "allow", name: "Allow", kind: .allowOnce),
            AgentPermissionOption(id: "allow-sess", name: "Always", kind: .allowAlways),
            AgentPermissionOption(id: "deny-once", name: "Deny", kind: .rejectOnce),
            AgentPermissionOption(id: "deny-always", name: "Never", kind: .rejectAlways),
        ]
        XCTAssertTrue(ACPConnection.isDeniedPermissionOutcome(.cancelled, options: options))
        XCTAssertTrue(ACPConnection.isDeniedPermissionOutcome(.selected(optionId: "deny-once"), options: options))
        XCTAssertTrue(ACPConnection.isDeniedPermissionOutcome(.selected(optionId: "deny-always"), options: options))
        XCTAssertFalse(ACPConnection.isDeniedPermissionOutcome(.selected(optionId: "allow"), options: options))
        XCTAssertFalse(ACPConnection.isDeniedPermissionOutcome(.selected(optionId: "allow-sess"), options: options))

        let completedCall = ACPToolCall(
            toolCallId: "call-1",
            title: "Edit File.swift",
            kind: "edit",
            status: "completed",
            content: [.diff(path: "/repo/File.swift", oldText: "old", newText: "new")]
        )
        let forcedError = ACPConnection.makeToolStep(from: completedCall, forceError: true)
        XCTAssertTrue(forcedError.isFinished)
        XCTAssertTrue(forcedError.isError)

        for status in ["cancelled", "canceled", "denied", "rejected", "failed"] {
            let deniedStatusCall = ACPToolCall(
                toolCallId: "call-status-\(status)",
                title: "Edit File.swift",
                kind: "edit",
                status: status
            )
            let step = ACPConnection.makeToolStep(from: deniedStatusCall)
            XCTAssertTrue(step.isFinished, "status \(status) must be terminal")
            XCTAssertTrue(step.isError, "status \(status) must be marked error")
        }
    }

    func testBuildDiffFilesAnchorsRealLineNumbersAndGuardsReads() throws {
        let fm = FileManager.default
        let container = fm.temporaryDirectory.appendingPathComponent("vitruvian-diff-anchor-\(UUID().uuidString)")
        let workdir = container.appendingPathComponent("repo")
        let outsideDir = container.appendingPathComponent("outside")
        try fm.createDirectory(at: workdir.appendingPathComponent("Sources"), withIntermediateDirectories: true)
        try fm.createDirectory(at: outsideDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: container) }

        // 1. Unique match offsets line numbers to real file coordinates (lines 18-20).
        var authLines = (1...25).map { "let value\($0) = \($0)" }
        authLines[17] = "let token = validate(input)"
        authLines[18] = "guard token.isValid else { return nil }"
        authLines[19] = "return token"
        let authURL = workdir.appendingPathComponent("Sources/Auth.swift")
        try (authLines.joined(separator: "\n") + "\n").write(to: authURL, atomically: true, encoding: .utf8)

        let authDiff = VitruvianCodeToolStep.Diff(
            path: authURL.path,
            oldText: "let token = validate(input)\nguard !token.isExpired else { return nil }\nreturn token",
            newText: "let token = validate(input)\nguard token.isValid else { return nil }\nreturn token"
        )
        let authFiles = VitruvianCodeDiffParser.buildDiffFiles(from: [authDiff], workingDirectory: workdir.path)
        XCTAssertEqual(authFiles.count, 1)
        let authHunk = try XCTUnwrap(authFiles[0].hunks.first)
        XCTAssertTrue(authHunk.header.hasPrefix("@@ -18,3 +18,3 @@"), "Got header \(authHunk.header)")
        let nonHeaderAuth = authHunk.lines.filter { $0.kind != .header }
        XCTAssertEqual(nonHeaderAuth.map(\.anchorLineNumber), [18, 19, 19, 20])
        XCTAssertEqual(nonHeaderAuth[2].kind, .addition)
        XCTAssertEqual(nonHeaderAuth[2].newLineNumber, 19)

        // 2. Duplicate match leaves line numbers nil.
        let dupURL = workdir.appendingPathComponent("Sources/Dup.swift")
        let dupContent = "func a() {\n    return 42\n}\nfunc b() {\n    return 42\n}\n"
        try dupContent.write(to: dupURL, atomically: true, encoding: .utf8)
        let dupDiff = VitruvianCodeToolStep.Diff(path: "Sources/Dup.swift", oldText: "    return 0", newText: "    return 42")
        let dupFiles = VitruvianCodeDiffParser.buildDiffFiles(from: [dupDiff], workingDirectory: workdir.path)
        let dupLines = try XCTUnwrap(dupFiles.first?.hunks.first?.lines.filter { $0.kind != .header })
        XCTAssertTrue(dupLines.allSatisfy { $0.oldLineNumber == nil && $0.newLineNumber == nil && $0.anchorLineNumber == nil })

        // 3. Deletion-only diff leaves line numbers nil.
        let delDiff = VitruvianCodeToolStep.Diff(path: "Sources/Auth.swift", oldText: "let value1 = 1", newText: "")
        let delFiles = VitruvianCodeDiffParser.buildDiffFiles(from: [delDiff], workingDirectory: workdir.path)
        let delLines = try XCTUnwrap(delFiles.first?.hunks.first?.lines.filter { $0.kind != .header })
        XCTAssertTrue(delLines.allSatisfy { $0.oldLineNumber == nil && $0.newLineNumber == nil && $0.anchorLineNumber == nil })

        // 4. Missing file leaves line numbers nil.
        let missingDiff = VitruvianCodeToolStep.Diff(path: "Sources/Missing.swift", oldText: "a", newText: "b")
        let missingFiles = VitruvianCodeDiffParser.buildDiffFiles(from: [missingDiff], workingDirectory: workdir.path)
        let missingLines = try XCTUnwrap(missingFiles.first?.hunks.first?.lines.filter { $0.kind != .header })
        XCTAssertTrue(missingLines.allSatisfy { $0.anchorLineNumber == nil })

        // 5. Files outside workingDirectory (absolute, relative .. traversal, and symlink escape) must NOT be read.
        let secretURL = outsideDir.appendingPathComponent("Secret.swift")
        try "let secretPrefix = 1\nlet uniqueSecretLine = 999\n".write(to: secretURL, atomically: true, encoding: .utf8)
        let symlinkEscapeURL = workdir.appendingPathComponent("Sources/Escape.swift")
        try fm.createSymbolicLink(at: symlinkEscapeURL, withDestinationURL: secretURL)

        for outsidePath in [secretURL.path, "../outside/Secret.swift", symlinkEscapeURL.path] {
            let outsideDiff = VitruvianCodeToolStep.Diff(path: outsidePath, oldText: "old", newText: "let uniqueSecretLine = 999")
            let outsideFiles = VitruvianCodeDiffParser.buildDiffFiles(from: [outsideDiff], workingDirectory: workdir.path)
            let outsideLines = try XCTUnwrap(outsideFiles.first?.hunks.first?.lines.filter { $0.kind != .header })
            XCTAssertTrue(
                outsideLines.allSatisfy { $0.oldLineNumber == nil && $0.newLineNumber == nil && $0.anchorLineNumber == nil },
                "File outside workdir must not be read for path \(outsidePath)"
            )
        }

        // 6. Files exceeding size cap are not read.
        let bigURL = workdir.appendingPathComponent("Sources/Big.swift")
        try "let bigUniqueMarker = 777\nlet padding = \"0123456789012345678901234567890123456789\"\n".write(
            to: bigURL,
            atomically: true,
            encoding: .utf8
        )
        let bigDiff = VitruvianCodeToolStep.Diff(path: "Sources/Big.swift", oldText: "old", newText: "let bigUniqueMarker = 777")
        let cappedFiles = VitruvianCodeDiffParser.buildDiffFiles(
            from: [bigDiff],
            workingDirectory: workdir.path,
            maxAnchoredFileBytes: 32
        )
        let cappedLines = try XCTUnwrap(cappedFiles.first?.hunks.first?.lines.filter { $0.kind != .header })
        XCTAssertTrue(cappedLines.allSatisfy { $0.anchorLineNumber == nil })
    }

    func testRefreshDiffReviewGenerationTokenDropsStaleGitResultAndBuildsOffMainThread() async throws {
        let domain = "com.vitruviansoftware.vitruvian-code.tests.diff-race.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(ScratchDefaults.suite(named: domain))
        defaults.removePersistentDomain(forName: domain)
        defer { defaults.removePersistentDomain(forName: domain) }

        let gate = AsyncGate()
        let builderRanOffMainThread = LockedFlag()

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
                    await gate.enterAndWait()
                }
                return """
                diff --git a/Sources/StaleGit.swift b/Sources/StaleGit.swift
                --- a/Sources/StaleGit.swift
                +++ b/Sources/StaleGit.swift
                @@ -1,1 +1,1 @@
                -let old = 0
                +let old = 1
                """
            }
        )

        let session = VitruvianCodeQuickPromptSession(environment: env, host: TestDiffReviewHost())
        session.diffReviewFilesBuilder = { diffs, workdir in
            if !Thread.isMainThread {
                builderRanOffMainThread.setTrue()
            }
            return VitruvianCodeDiffParser.buildDiffFiles(from: diffs, workingDirectory: workdir)
        }

        var liveProvider = VitruvianCodeCLIProvider.antigravity
        liveProvider.connection = .acp
        let liveConfig = VitruvianCodeConfiguration(workingDirectory: "/repo", activeProvider: liveProvider)

        let userMsg = VitruvianCodeChatMessage(role: .user, text: "Edit")
        session.messages = [userMsg, VitruvianCodeChatMessage(role: .agent, text: "Thinking")]

        // Refresh #1 starts git diff and blocks at gate.
        session.refreshDiffReview(configuration: liveConfig)
        await gate.waitUntilEntered()

        // Refresh #2 supersedes #1 with agent-reported diffs built off the main thread.
        session.messages = [
            userMsg,
            VitruvianCodeChatMessage(
                role: .agent,
                text: "Edited",
                toolSteps: [
                    VitruvianCodeToolStep(
                        title: "Edit LiveEdit.swift",
                        isFinished: true,
                        kind: .edit,
                        isError: false,
                        diffs: [VitruvianCodeToolStep.Diff(path: "/repo/Sources/LiveEdit.swift", oldText: "a", newText: "b")]
                    )
                ]
            ),
        ]
        session.refreshDiffReview(configuration: liveConfig)
        await session.waitForDiffReviewRefresh()

        XCTAssertTrue(builderRanOffMainThread.value, "buildDiffFiles file reads must run off the main thread")
        XCTAssertEqual(session.diffReviewSession.source, .agentReported)
        XCTAssertEqual(session.diffReviewSession.files.map(\.displayPath), ["Sources/LiveEdit.swift"])

        // Release Refresh #1's stale git task; it must NOT overwrite .agentReported with .git.
        await gate.release()
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(session.diffReviewSession.source, .agentReported)
        XCTAssertEqual(session.diffReviewSession.files.map(\.displayPath), ["Sources/LiveEdit.swift"])
    }
}

private actor AsyncGate {
    private var entered = false
    private var released = false
    private var enterWaiter: CheckedContinuation<Void, Never>?
    private var releaseWaiter: CheckedContinuation<Void, Never>?

    func enterAndWait() async {
        entered = true
        enterWaiter?.resume()
        enterWaiter = nil
        if released { return }
        await withCheckedContinuation { continuation in
            if released {
                continuation.resume()
            } else {
                releaseWaiter = continuation
            }
        }
    }

    func waitUntilEntered() async {
        if entered { return }
        await withCheckedContinuation { continuation in
            if entered {
                continuation.resume()
            } else {
                enterWaiter = continuation
            }
        }
    }

    func release() {
        released = true
        releaseWaiter?.resume()
        releaseWaiter = nil
    }
}

private final class LockedFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var flag = false

    var value: Bool {
        lock.withLock { flag }
    }

    func setTrue() {
        lock.withLock { flag = true }
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
