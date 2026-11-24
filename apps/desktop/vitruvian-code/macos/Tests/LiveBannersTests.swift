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
import SwiftUI
@testable import VitruvianCodeCore
@testable import VitruvianCodeUI
import XCTest

@MainActor
final class LiveBannersTests: XCTestCase {
    private var scratchSuites: [(UserDefaults, String)] = []

    override func tearDown() {
        for (defaults, domain) in scratchSuites {
            defaults.removePersistentDomain(forName: domain)
        }
        scratchSuites.removeAll()
        super.tearDown()
    }

    private static let claudeSDKProvider = VitruvianCodeCLIProvider(
        id: VitruvianCodeCLIProvider.claude.id,
        name: "Claude Code",
        commandTemplate: VitruvianCodeCLIProvider.claude.commandTemplate,
        connection: .claudeSDK
    )

    // MARK: - 1. Notice Banners

    func testBannerCapsAtThreeAndOrdersNewestFirst() {
        var state = AgentLiveState()
        state.apply(.notice(severity: "info", title: "Notice 1", detail: nil))
        state.apply(.notice(severity: "warning", title: "Notice 2", detail: "D2"))
        state.apply(.notice(severity: "error", title: "Notice 3", detail: nil))
        state.apply(.notice(severity: "info", title: "Notice 4", detail: "D4"))

        let visible = AgentBannerLogic.visibleNotices(
            from: state.notices,
            dismissedIDs: state.dismissedNoticeIDs
        )
        XCTAssertEqual(visible.count, 3)
        XCTAssertEqual(visible.map(\.title), ["Notice 4", "Notice 3", "Notice 2"])
    }

    func testDismissNoticeIsPerNoticeAndPreservesStoredOrder() {
        var state = AgentLiveState()
        state.apply(.notice(severity: "info", title: "N1", detail: nil))
        state.apply(.notice(severity: "warning", title: "N2", detail: nil))
        state.apply(.notice(severity: "error", title: "N3", detail: nil))
        state.apply(.notice(severity: "info", title: "N4", detail: nil))

        let id3 = state.notices[2].id
        state.dismissNotice(id: id3)

        XCTAssertEqual(state.notices.map(\.title), ["N1", "N2", "N3", "N4"], "stored notice order must remain unchanged")
        let visible = AgentBannerLogic.visibleNotices(
            from: state.notices,
            dismissedIDs: state.dismissedNoticeIDs
        )
        XCTAssertEqual(visible.map(\.title), ["N4", "N2", "N1"])
    }

    func testBannerRendersAgentTextVerbatimNeverMarkdown() throws {
        let untrusted = "**Bold** [click me](https://evil.example/phish) `code`"
        let rendered = AgentBannerLogic.verbatimText(untrusted)
        let mirrorDesc = String(describing: rendered)
        XCTAssertTrue(mirrorDesc.contains("verbatim"), "must construct Text(verbatim:): \(mirrorDesc)")

        let source = try uiSource("AgentBannerView.swift")
        XCTAssertTrue(source.contains("Text(verbatim: text)"), "AgentBannerView must use Text(verbatim:)")
        XCTAssertFalse(source.contains("AttributedString(markdown:"), "AgentBannerView must never parse markdown")
        XCTAssertFalse(source.contains("markdown("), "AgentBannerView must never call markdown helper")
    }

    // MARK: - 2. Compaction Timeline & Chip

    func testMultipleCompactionsProduceDistinctTimelineRowsAndTransitionToDone() async throws {
        let connections = LiveBannersLockedBox<[LiveBannersMockConnection]>([])
        let env = makeEnvironment { spec in
            let conn = LiveBannersMockConnection(spec: spec)
            connections.withValue { $0.append(conn) }
            return conn
        }
        let session = VitruvianCodeQuickPromptSession(environment: env, host: LiveBannersMockHost())
        session.takeCheckpoint = { _ in nil }
        let config = VitruvianCodeConfiguration(approvalMode: .standard, activeProvider: Self.claudeSDKProvider)

        session.send("Turn 1", configuration: config, agentPath: "/fake/claude")
        try await waitUntil("turn 1 prompts") { connections.value.first?.promptCalls.count == 1 }
        let conn = try XCTUnwrap(connections.value.first)

        conn.emit(.compaction(id: "cmp-1", status: "running", summary: nil))
        try await waitUntil("cmp-1 in progress") {
            session.liveState.compactions.count == 1 && session.liveState.compactions[0].isInProgress
        }
        conn.emit(.compaction(id: "cmp-1", status: "completed", summary: "180000 -> 42000 tokens"))
        conn.emit(.compaction(id: "cmp-2", status: "running", summary: nil))
        conn.emit(.compaction(id: "cmp-2", status: "completed", summary: "195000 -> 51000 tokens"))
        conn.emit(.finished(status: "completed", response: "Done", error: nil, conversationID: "s-cmp"))
        conn.finishPrompt(with: .endTurn)
        try await waitUntil("turn 1 done") { !session.isRunning }

        XCTAssertEqual(session.liveState.compactions.count, 2)
        let rows = session.messages.compactMap(\.compaction)
        XCTAssertEqual(rows.count, 2, "timeline must keep every compaction, not only the latest")
        XCTAssertEqual(rows.map(\.id), ["cmp-1", "cmp-2"])
        XCTAssertEqual(rows[0].status, "completed")
        XCTAssertEqual(rows[0].summary, "180000 -> 42000 tokens")
        XCTAssertEqual(rows[1].summary, "195000 -> 51000 tokens")
        XCTAssertTrue(session.messages.filter { $0.compaction != nil }.allSatisfy { VitruvianCodeTimeline.isShown($0) })
        await session.stopAll()
    }

    func testCompactionChipThreshold() {
        let below = VitruvianCodeContextUsage(inputTokens: 150_000, cachedTokens: 49_999, outputTokens: 0, contextWindow: 1_000_000)
        let atThreshold = VitruvianCodeContextUsage(inputTokens: 150_000, cachedTokens: 49_000, outputTokens: 1_000, contextWindow: 1_000_000)
        let estimated = VitruvianCodeContextUsage(inputTokens: 250_000, cachedTokens: 0, outputTokens: 0, contextWindow: 1_000_000, isEstimate: true)

        XCTAssertEqual(AgentCompactionSuggestion.minContextTokens, 200_000)
        XCTAssertFalse(
            AgentCompactionSuggestion.shouldShow(
                isIdle: true, isLiveChat: true, isClaude: true, isCompacting: false, isDismissed: false, contextUsage: below
            )
        )
        XCTAssertTrue(
            AgentCompactionSuggestion.shouldShow(
                isIdle: true, isLiveChat: true, isClaude: true, isCompacting: false, isDismissed: false, contextUsage: atThreshold
            )
        )
        XCTAssertFalse(
            AgentCompactionSuggestion.shouldShow(
                isIdle: true, isLiveChat: true, isClaude: true, isCompacting: false, isDismissed: false, contextUsage: estimated
            )
        )
        XCTAssertFalse(
            AgentCompactionSuggestion.shouldShow(
                isIdle: false, isLiveChat: true, isClaude: true, isCompacting: false, isDismissed: false, contextUsage: atThreshold
            )
        )
        XCTAssertFalse(
            AgentCompactionSuggestion.shouldShow(
                isIdle: true, isLiveChat: true, isClaude: false, isCompacting: false, isDismissed: false, contextUsage: atThreshold
            )
        )
    }

    func testCompactionChipKeepHidesUntilNextCompaction() async throws {
        let connections = LiveBannersLockedBox<[LiveBannersMockConnection]>([])
        let env = makeEnvironment { spec in
            let conn = LiveBannersMockConnection(spec: spec)
            connections.withValue { $0.append(conn) }
            return conn
        }
        let session = VitruvianCodeQuickPromptSession(environment: env, host: LiveBannersMockHost())
        session.takeCheckpoint = { _ in nil }
        let config = VitruvianCodeConfiguration(approvalMode: .standard, activeProvider: Self.claudeSDKProvider)

        session.send("Hello", configuration: config, agentPath: "/fake/claude")
        try await waitUntil("prompt sent") { connections.value.first?.promptCalls.count == 1 }
        let conn = try XCTUnwrap(connections.value.first)
        conn.emit(.contextUsage(VitruvianCodeContextUsage(inputTokens: 190_000, cachedTokens: 15_000, outputTokens: 5_000, contextWindow: 1_000_000)))
        conn.emit(.finished(status: "completed", response: "OK", error: nil, conversationID: "s-keep"))
        conn.finishPrompt(with: .endTurn)
        try await waitUntil("turn done") { !session.isRunning }

        XCTAssertTrue(session.shouldShowCompactionChip(for: config))
        session.keepContextWithoutCompacting()
        XCTAssertFalse(session.shouldShowCompactionChip(for: config))

        // Next compaction re-enables chip eligibility once idle and still >= threshold.
        session.send("Turn 2", configuration: config, agentPath: "/fake/claude")
        try await waitUntil("prompt 2 sent") { conn.promptCalls.count == 2 }
        conn.emit(.compaction(id: "cmp-reset", status: "completed", summary: nil))
        conn.emit(.contextUsage(VitruvianCodeContextUsage(inputTokens: 205_000, cachedTokens: 0, outputTokens: 0, contextWindow: 1_000_000)))
        conn.emit(.finished(status: "completed", response: "OK 2", error: nil, conversationID: "s-keep"))
        conn.finishPrompt(with: .endTurn)
        try await waitUntil("turn 2 done") { !session.isRunning }

        XCTAssertTrue(session.shouldShowCompactionChip(for: config))
        await session.stopAll()
    }

    func testCompactionChipCompactSendsSlashCompact() async throws {
        let connections = LiveBannersLockedBox<[LiveBannersMockConnection]>([])
        let env = makeEnvironment { spec in
            let conn = LiveBannersMockConnection(spec: spec)
            connections.withValue { $0.append(conn) }
            return conn
        }
        let session = VitruvianCodeQuickPromptSession(environment: env, host: LiveBannersMockHost())
        session.takeCheckpoint = { _ in nil }
        let config = VitruvianCodeConfiguration(approvalMode: .standard, activeProvider: Self.claudeSDKProvider)

        session.send("Initial", configuration: config, agentPath: "/fake/claude")
        try await waitUntil("prompt 1 sent") { connections.value.first?.promptCalls.count == 1 }
        let conn = try XCTUnwrap(connections.value.first)
        conn.emit(.finished(status: "completed", response: "OK", error: nil, conversationID: "s-compact"))
        conn.finishPrompt(with: .endTurn)
        try await waitUntil("turn 1 done") { !session.isRunning }

        session.draft = "unsent draft"
        session.compactFromSuggestion(configuration: config, agentPath: "/fake/claude")
        try await waitUntil("compact prompt sent") { conn.promptCalls.count == 2 }
        XCTAssertEqual(conn.promptCalls[1], [.text("/compact")])
        XCTAssertEqual(session.draft, "unsent draft")

        conn.emit(.finished(status: "completed", response: "Compacted", error: nil, conversationID: "s-compact"))
        conn.finishPrompt(with: .endTurn)
        try await waitUntil("turn 2 done") { !session.isRunning }
        await session.stopAll()
    }

    // MARK: - 3. Usage Limit Wait

    func testUsageLimitWithAndWithoutResetAndResumeGate() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let beforeReset = AgentLiveState.UsageLimit(resetsAt: now.addingTimeInterval(120))
        let atReset = AgentLiveState.UsageLimit(resetsAt: now)
        let afterReset = AgentLiveState.UsageLimit(resetsAt: now.addingTimeInterval(-5))
        let noReset = AgentLiveState.UsageLimit(resetsAt: nil)

        XCTAssertFalse(AgentUsageLimitState.canResume(beforeReset, now: now), "Resume must stay disabled before reset")
        XCTAssertTrue(AgentUsageLimitState.canResume(atReset, now: now), "Resume enabled at reset")
        XCTAssertTrue(AgentUsageLimitState.canResume(afterReset, now: now), "Resume enabled after reset")
        XCTAssertFalse(AgentUsageLimitState.canResume(noReset, now: now), "Resume disabled when reset time is unknown")
        XCTAssertEqual(AgentUsageLimitState.remainingSeconds(beforeReset, now: now), 120)
        XCTAssertNil(AgentUsageLimitState.remainingSeconds(noReset, now: now))
        XCTAssertEqual(AgentUsageLimitState.formattedCountdown(seconds: 120), "2m 00s")
        XCTAssertEqual(AgentUsageLimitState.formattedCountdown(seconds: 3_720), "1h 02m")
    }

    func testUsageLimitNeverAutoSendsAndClearsOnLaterSuccess() async throws {
        let connections = LiveBannersLockedBox<[LiveBannersMockConnection]>([])
        let env = makeEnvironment { spec in
            let conn = LiveBannersMockConnection(spec: spec)
            connections.withValue { $0.append(conn) }
            return conn
        }
        let session = VitruvianCodeQuickPromptSession(environment: env, host: LiveBannersMockHost())
        session.takeCheckpoint = { _ in nil }
        let config = VitruvianCodeConfiguration(approvalMode: .standard, activeProvider: Self.claudeSDKProvider)

        let pastReset = Date().addingTimeInterval(0.05)
        session.send("Hit limit", configuration: config, agentPath: "/fake/claude")
        try await waitUntil("prompt 1 sent") { connections.value.first?.promptCalls.count == 1 }
        let conn = try XCTUnwrap(connections.value.first)
        conn.emit(.usageLimit(resetsAt: pastReset))
        conn.emit(.finished(status: "error", response: nil, error: "Limit reached", conversationID: "s-limit"))
        conn.finishPrompt(with: .error)
        try await waitUntil("turn 1 failed") { !session.isRunning }

        XCTAssertNotNil(session.liveState.usageLimit)
        // Wait well past reset: session MUST NOT auto-send.
        try await Task.sleep(nanoseconds: 120_000_000)
        XCTAssertEqual(conn.promptCalls.count, 1, "usage limit reset must never auto-send")
        XCTAssertFalse(session.isRunning)

        // Attempt resume before reset fails; after reset succeeds once.
        XCTAssertFalse(
            session.resumeAfterUsageLimit(
                configuration: config,
                agentPath: "/fake/claude",
                now: pastReset.addingTimeInterval(-10)
            )
        )
        XCTAssertEqual(conn.promptCalls.count, 1)

        XCTAssertTrue(
            session.resumeAfterUsageLimit(
                configuration: config,
                agentPath: "/fake/claude",
                now: pastReset.addingTimeInterval(1)
            )
        )
        try await waitUntil("resumed prompt sent") { conn.promptCalls.count == 2 }
        XCTAssertNil(session.liveState.usageLimit)

        // Emit another usage limit, then complete a subsequent turn cleanly -> clears usageLimit.
        conn.emit(.finished(status: "completed", response: "OK", error: nil, conversationID: "s-limit"))
        conn.finishPrompt(with: .endTurn)
        try await waitUntil("turn 2 done") { !session.isRunning }
        XCTAssertNil(session.liveState.usageLimit)

        session.send("Turn 3", configuration: config, agentPath: "/fake/claude")
        try await waitUntil("turn 3 sent") { conn.promptCalls.count == 3 }
        conn.emit(.usageLimit(resetsAt: Date().addingTimeInterval(600)))
        conn.emit(.finished(status: "completed", response: "Partial", error: nil, conversationID: "s-limit"))
        conn.finishPrompt(with: .endTurn)
        try await waitUntil("turn 3 done") { !session.isRunning }
        XCTAssertNotNil(session.liveState.usageLimit)

        session.send("Turn 4", configuration: config, agentPath: "/fake/claude")
        try await waitUntil("turn 4 sent") { conn.promptCalls.count == 4 }
        conn.emit(.finished(status: "completed", response: "Clean", error: nil, conversationID: "s-limit"))
        conn.finishPrompt(with: .endTurn)
        try await waitUntil("turn 4 done") { !session.isRunning }
        XCTAssertNil(session.liveState.usageLimit, "later succeeding turn must clear usage limit")
        await session.stopAll()
    }

    // MARK: - 4. Error Card & Per-Chat Command-Line Override

    func testUseCommandLineOverrideIsPerChatAndPersists() async throws {
        let specs = LiveBannersLockedBox<[AgentConnectionSpec]>([])
        let connections = LiveBannersLockedBox<[LiveBannersMockConnection]>([])
        let env = makeEnvironment { spec in
            specs.withValue { $0.append(spec) }
            let conn = LiveBannersMockConnection(spec: spec)
            connections.withValue { $0.append(conn) }
            return conn
        }
        let host = LiveBannersMockHost()
        let session = VitruvianCodeQuickPromptSession(environment: env, host: host)
        session.takeCheckpoint = { _ in nil }
        let config = VitruvianCodeConfiguration(approvalMode: .standard, activeProvider: Self.claudeSDKProvider)

        session.send("Prompt A", configuration: config, agentPath: "/fake/claude")
        try await waitUntil("turn 1 prompt") { connections.value.first?.promptCalls.count == 1 }
        let conn1 = try XCTUnwrap(connections.value.first)
        conn1.emit(.started(conversationID: "conv-cli-1"))
        conn1.emit(.connectionFailed(AgentFailure(kind: .startupFailed, message: "Helper died")))
        conn1.failPrompt(with: ACPConnectionError.notStarted)
        try await waitUntil("turn 1 failed") { !session.isRunning }

        session.useCommandLineForThisChat(configuration: config, agentPath: "/fake/claude")
        try await waitUntil("command-line override prompt") { specs.value.count == 2 }

        XCTAssertEqual(session.chatConnectionOverride, .commandLine)
        XCTAssertEqual(host.chatConnections["conv-cli-1"], "commandLine")
        XCTAssertEqual(specs.value[1].kind, .commandLine)
        XCTAssertFalse(session.isLiveChat(for: config))

        let conn2 = connections.value[1]
        conn2.emit(.finished(status: "completed", response: "CLI OK", error: nil, conversationID: "conv-cli-1"))
        conn2.finishPrompt(with: .endTurn)
        try await waitUntil("cli turn done") { !session.isRunning }

        // New chat clears the per-chat override.
        session.newChat()
        XCTAssertNil(session.chatConnectionOverride)
        XCTAssertTrue(session.isLiveChat(for: config))

        // Reopening the old chat restores its per-chat override.
        session.resume(
            VitruvianCodeSessionSummary(id: "conv-cli-1", title: "CLI Chat", steps: 1, modified: nil),
            configuration: config
        )
        XCTAssertEqual(session.chatConnectionOverride, .commandLine)
        XCTAssertFalse(session.isLiveChat(for: config))
        await session.stopAll()
    }

    func testUseCommandLineOverrideSendsFailedPromptOnce() async throws {
        let specs = LiveBannersLockedBox<[AgentConnectionSpec]>([])
        let connections = LiveBannersLockedBox<[LiveBannersMockConnection]>([])
        let env = makeEnvironment { spec in
            specs.withValue { $0.append(spec) }
            let conn = LiveBannersMockConnection(spec: spec)
            connections.withValue { $0.append(conn) }
            return conn
        }
        let session = VitruvianCodeQuickPromptSession(environment: env, host: LiveBannersMockHost())
        session.takeCheckpoint = { _ in nil }
        let config = VitruvianCodeConfiguration(approvalMode: .standard, activeProvider: Self.claudeSDKProvider)

        session.send("Retry once", configuration: config, agentPath: "/fake/claude")
        try await waitUntil("turn 1 prompt") { connections.value.first?.promptCalls.count == 1 }
        let conn1 = try XCTUnwrap(connections.value.first)
        conn1.emit(.connectionFailed(AgentFailure(kind: .startupFailed, message: "Start failed")))
        conn1.failPrompt(with: ACPConnectionError.notStarted)
        try await waitUntil("turn 1 failed") { !session.isRunning }

        session.useCommandLineForThisChat(configuration: config, agentPath: "/fake/claude")
        try await waitUntil("override sent once") { connections.value.count == 2 && connections.value[1].promptCalls.count == 1 }
        let conn2 = connections.value[1]
        XCTAssertEqual(conn2.promptCalls[0], [.text("Retry once")])
        conn2.emit(.finished(status: "completed", response: "OK", error: nil, conversationID: "conv-once"))
        conn2.finishPrompt(with: .endTurn)
        try await waitUntil("override turn done") { !session.isRunning }

        // Calling it a second time with no failed prompt does NOT re-send.
        session.useCommandLineForThisChat(configuration: config, agentPath: "/fake/claude")
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(connections.value.count, 2)
        await session.stopAll()
    }

    func testUseCommandLineOverrideLeavesProviderSettingUntouchedAndNeverAutomatic() async throws {
        let specs = LiveBannersLockedBox<[AgentConnectionSpec]>([])
        let connections = LiveBannersLockedBox<[LiveBannersMockConnection]>([])
        let env = makeEnvironment { spec in
            specs.withValue { $0.append(spec) }
            let conn = LiveBannersMockConnection(spec: spec)
            connections.withValue { $0.append(conn) }
            return conn
        }
        let host = LiveBannersMockHost()
        host.savedProviders = [Self.claudeSDKProvider]
        let session = VitruvianCodeQuickPromptSession(environment: env, host: host)
        session.takeCheckpoint = { _ in nil }
        let config = VitruvianCodeConfiguration(approvalMode: .standard, activeProvider: Self.claudeSDKProvider)

        session.send("Fail live", configuration: config, agentPath: "/fake/claude")
        try await waitUntil("turn 1 prompt") { connections.value.first?.promptCalls.count == 1 }
        let conn1 = try XCTUnwrap(connections.value.first)
        conn1.emit(.connectionFailed(AgentFailure(kind: .startupFailed, message: "Boom")))
        conn1.failPrompt(with: ACPConnectionError.notStarted)
        try await waitUntil("turn 1 failed") { !session.isRunning }

        // Must never switch automatically on failure.
        XCTAssertNil(session.chatConnectionOverride)
        XCTAssertEqual(connections.value.count, 1)
        XCTAssertEqual(config.activeProvider.connection, .claudeSDK)
        XCTAssertEqual(host.savedProviders.first?.connection, .claudeSDK)

        session.useCommandLineForThisChat(configuration: config, agentPath: "/fake/claude")
        try await waitUntil("override ran") { connections.value.count == 2 && connections.value[1].promptCalls.count == 1 }
        XCTAssertEqual(config.activeProvider.connection, .claudeSDK, "provider config must remain unchanged")
        XCTAssertEqual(host.savedProviders.first?.connection, .claudeSDK, "saved provider must remain unchanged")

        connections.value[1].emit(.finished(status: "completed", response: "CLI OK", error: nil, conversationID: "conv-no-auto"))
        connections.value[1].finishPrompt(with: .endTurn)
        try await waitUntil("done") { !session.isRunning }
        await session.stopAll()
    }

    func testRetryAndCommandLineResendTheFailedPromptsFilesOnceAndKeepModes() async throws {
        let specs = LiveBannersLockedBox<[AgentConnectionSpec]>([])
        let connections = LiveBannersLockedBox<[LiveBannersMockConnection]>([])
        let env = makeEnvironment { spec in
            specs.withValue { $0.append(spec) }
            let conn = LiveBannersMockConnection(spec: spec)
            connections.withValue { $0.append(conn) }
            return conn
        }
        let session = VitruvianCodeQuickPromptSession(environment: env, host: LiveBannersMockHost())
        session.takeCheckpoint = { _ in nil }
        let config = VitruvianCodeConfiguration(approvalMode: .standard, activeProvider: Self.claudeSDKProvider)
        session.chatApprovalMode = .standard
        session.chatPlanMode = true
        let file = URL(fileURLWithPath: "/tmp/notes.txt")
        XCTAssertTrue(session.addAttachment(url: file))

        session.send("With a file", configuration: config, agentPath: "/fake/claude")
        try await waitUntil("turn 1 prompt") { connections.value.first?.promptCalls.count == 1 }
        XCTAssertTrue(session.attachments.isEmpty, "the composer is clear once the prompt is sent")
        let conn1 = try XCTUnwrap(connections.value.first)
        conn1.emit(.connectionFailed(AgentFailure(kind: .startupFailed, message: "Boom")))
        conn1.failPrompt(with: ACPConnectionError.notStarted)
        try await waitUntil("turn 1 failed") { !session.isRunning }

        // Two clicks in a row: one send, and the draft the user is typing is untouched.
        session.draft = "half typed"
        session.useCommandLineForThisChat(configuration: config, agentPath: "/fake/claude")
        session.useCommandLineForThisChat(configuration: config, agentPath: "/fake/claude")
        session.retryFailedPrompt(configuration: config, agentPath: "/fake/claude")
        try await waitUntil("one command-line send") { connections.value.count == 2 && connections.value[1].promptCalls.count == 1 }
        try await Task.sleep(nanoseconds: 80_000_000)
        XCTAssertEqual(connections.value.count, 2, "a running turn is never overlapped")
        XCTAssertEqual(connections.value[1].promptCalls.count, 1, "the failed prompt goes exactly once")
        XCTAssertEqual(connections.value[1].promptCalls[0], [.text("@/tmp/notes.txt"), .text("With a file")],
                       "the failed prompt's file goes with it")
        XCTAssertEqual(session.draft, "half typed")
        XCTAssertTrue(session.attachments.isEmpty)
        XCTAssertEqual(specs.value[1].kind, .commandLine)
        XCTAssertEqual(specs.value[1].configuration.approvalMode, .plan, "plan mode still applies on the command line")
        connections.value[1].emit(.finished(status: "completed", response: "OK", error: nil, conversationID: "c"))
        connections.value[1].finishPrompt(with: .endTurn)
        try await waitUntil("done") { !session.isRunning }
        await session.stopAll()
    }

    func testRetryKeepsTheFailedPromptsFiles() async throws {
        let connections = LiveBannersLockedBox<[LiveBannersMockConnection]>([])
        let env = makeEnvironment { spec in
            let conn = LiveBannersMockConnection(spec: spec)
            connections.withValue { $0.append(conn) }
            return conn
        }
        let session = VitruvianCodeQuickPromptSession(environment: env, host: LiveBannersMockHost())
        session.takeCheckpoint = { _ in nil }
        let config = VitruvianCodeConfiguration(approvalMode: .standard, activeProvider: Self.claudeSDKProvider)
        XCTAssertTrue(session.addAttachment(url: URL(fileURLWithPath: "/tmp/shot.png")))
        session.send("Look", configuration: config, agentPath: "/fake/claude")
        try await waitUntil("prompt") { connections.value.first?.promptCalls.count == 1 }
        let conn1 = try XCTUnwrap(connections.value.first)
        conn1.emit(.connectionFailed(AgentFailure(kind: .exited, message: "died")))
        conn1.failPrompt(with: ACPConnectionError.notStarted)
        try await waitUntil("failed") { !session.isRunning }

        session.retryFailedPrompt(configuration: config, agentPath: "/fake/claude")
        try await waitUntil("retry sent") { connections.value.count >= 1 && connections.value.last?.promptCalls.count ?? 0 >= 1 && session.isRunning }
        let sent = connections.value.flatMap(\.promptCalls)
        XCTAssertEqual(sent.last, [.image(path: "/tmp/shot.png"), .text("Look")])
        await session.stopAll()
    }

    // MARK: - 5. Crash States & Lock

    func testMidTurnCrashMarksTurnInterrupted() async throws {
        let connections = LiveBannersLockedBox<[LiveBannersMockConnection]>([])
        let env = makeEnvironment { spec in
            let conn = LiveBannersMockConnection(spec: spec)
            connections.withValue { $0.append(conn) }
            return conn
        }
        let session = VitruvianCodeQuickPromptSession(environment: env, host: LiveBannersMockHost())
        session.takeCheckpoint = { _ in nil }
        let config = VitruvianCodeConfiguration(approvalMode: .standard, activeProvider: Self.claudeSDKProvider)

        session.send("Do work", configuration: config, agentPath: "/fake/claude")
        try await waitUntil("prompt started") { connections.value.first?.promptCalls.count == 1 }
        let conn = try XCTUnwrap(connections.value.first)
        conn.emit(.text("Partial output before crash"))
        conn.emit(.connectionFailed(AgentFailure(kind: .exited, message: "Process died mid-turn")))
        conn.emit(.finished(status: "error", response: nil, error: "Process died mid-turn", conversationID: "s-int"))
        conn.failPrompt(with: ACPConnectionError.notStarted)
        try await waitUntil("turn interrupted") { !session.isRunning }

        let interruptedMsg = session.messages.first(where: { $0.text.contains("Partial output before crash") })
        XCTAssertEqual(interruptedMsg?.stopReason, "interrupted")
        XCTAssertEqual(session.lastLiveFailure?.source, .interrupted)
        XCTAssertTrue(VitruvianCodeTimeline.isShown(VitruvianCodeChatMessage(role: .agent, text: "", stopReason: "interrupted")))
        await session.stopAll()
    }

    func testAUserStopNeverShowsAsInterruptedOrCrashed() async throws {
        let connections = LiveBannersLockedBox<[LiveBannersMockConnection]>([])
        let env = makeEnvironment { spec in
            let conn = LiveBannersMockConnection(spec: spec)
            connections.withValue { $0.append(conn) }
            return conn
        }
        let session = VitruvianCodeQuickPromptSession(environment: env, host: LiveBannersMockHost())
        session.takeCheckpoint = { _ in nil }
        let config = VitruvianCodeConfiguration(approvalMode: .standard, activeProvider: Self.claudeSDKProvider)

        session.send("Long work", configuration: config, agentPath: "/fake/claude")
        try await waitUntil("prompt started") { connections.value.first?.promptCalls.count == 1 }
        let conn = try XCTUnwrap(connections.value.first)
        conn.emit(.text("Some output"))
        session.stop()
        // The connection dies as it is being stopped.
        conn.emit(.connectionFailed(AgentFailure(kind: .exited, message: "Agent process exited unexpectedly (signal SIGTERM).")))
        try await waitUntil("failure seen") { session.messages.contains { $0.isError } }
        // Judged before the turn's own end arrives, which would overwrite the mark.
        XCTAssertFalse(session.messages.contains { $0.stopReason == "interrupted" }, "a stop is not an interruption")
        XCTAssertNil(session.lastLiveFailure, "a stop is not a crash")
        conn.emit(.finished(status: "cancelled", response: nil, error: nil, conversationID: "s-stop"))
        conn.failPrompt(with: ACPConnectionError.notStarted)
        try await waitUntil("stopped") { !session.isRunning }

        XCTAssertFalse(session.messages.contains { $0.stopReason == "interrupted" }, "a stop is not an interruption")
        XCTAssertNil(session.lastLiveFailure, "a stop is not a crash")
        await session.stopAll()
    }

    func testClaudeSDKDistinguishesHelperCrashFromClaudeCrash() async throws {
        // 1. Helper process exits unexpectedly -> .helperCrashed
        let helperAgent = ScriptedACPAgent()
        let helperConn = ClaudeSDKConnection(
            launchSpec: AgentProcessLaunchSpec(executable: "/fake/node", arguments: ["helper.mjs"], workingDirectory: "/tmp"),
            bundled: BundledNode(nodeURL: URL(fileURLWithPath: "/fake/node"), helperURL: URL(fileURLWithPath: "/fake/helper.mjs")),
            claudePath: "/fake/claude",
            providerID: Self.claudeSDKProvider.id,
            secrets: nil,
            modeProvider: { (.standard, false) },
            versionProbe: { "2.1.326" },
            processFactory: helperAgent.makeProcessFactory()
        )
        let helperEvents = ACPEventStreamReader(helperConn.events)
        let helperDriver = Task {
            try await helperAgent.playSteps([
                .expectClientRequest(method: "initialize"),
                .agentSend(.object([
                    "jsonrpc": .string("2.0"),
                    "id": .string("$id"),
                    "result": .object([
                        "protocolVersion": .int(1),
                        "agentInfo": .object(["name": .string("vitruvian-claude-helper"), "version": .string("0.1.0")]),
                        "agentCapabilities": .object([
                            "loadSession": .bool(false),
                            "promptCapabilities": .object(["image": .bool(true), "embeddedContext": .bool(true)]),
                            "sessionCapabilities": .object(["resume": .object([:]), "close": .object([:])]),
                        ]),
                        "authMethods": .array([]),
                    ]),
                ])),
                .expectClientRequest(method: "session/new"),
                .agentSend(.object(["jsonrpc": .string("2.0"), "id": .string("$id"), "result": .object(["sessionId": .string("s-h1")])])),
                .expectClientRequest(method: "session/prompt"),
            ])
        }
        _ = try await helperConn.start(AgentSessionRequest(workingDirectory: "/tmp"))
        let helperPromptTask = Task { try await helperConn.prompt([.text("Hi")]) }
        try await withACPTestTimeout(seconds: 3.0) { try await helperDriver.value }
        await helperAgent.simulateExit(AgentProcessExit(exitCode: nil, signal: SIGKILL))
        _ = try? await helperPromptTask.value
        let helperStream = try await helperEvents.collectAllUntilEnd(timeout: 3.0)
        let helperFailure = helperStream.compactMap { event -> AgentFailure? in
            if case .connectionFailed(let f) = event { return f }
            return nil
        }.first
        XCTAssertEqual(helperFailure?.kind, .helperCrashed)

        // 2. Helper stays alive and reports underlying `claude` query died via JSON-RPC error -> .agentCrashed
        let claudeAgent = ScriptedACPAgent()
        let claudeConn = ClaudeSDKConnection(
            launchSpec: AgentProcessLaunchSpec(executable: "/fake/node", arguments: ["helper.mjs"], workingDirectory: "/tmp"),
            bundled: BundledNode(nodeURL: URL(fileURLWithPath: "/fake/node"), helperURL: URL(fileURLWithPath: "/fake/helper.mjs")),
            claudePath: "/fake/claude",
            providerID: Self.claudeSDKProvider.id,
            secrets: nil,
            modeProvider: { (.standard, false) },
            versionProbe: { "2.1.326" },
            processFactory: claudeAgent.makeProcessFactory()
        )
        let claudeEvents = ACPEventStreamReader(claudeConn.events)
        let claudeDriver = Task {
            try await claudeAgent.playSteps([
                .expectClientRequest(method: "initialize"),
                .agentSend(.object([
                    "jsonrpc": .string("2.0"),
                    "id": .string("$id"),
                    "result": .object([
                        "protocolVersion": .int(1),
                        "agentInfo": .object(["name": .string("vitruvian-claude-helper"), "version": .string("0.1.0")]),
                        "agentCapabilities": .object([
                            "loadSession": .bool(false),
                            "promptCapabilities": .object(["image": .bool(true), "embeddedContext": .bool(true)]),
                            "sessionCapabilities": .object(["resume": .object([:]), "close": .object([:])]),
                        ]),
                        "authMethods": .array([]),
                    ]),
                ])),
                .expectClientRequest(method: "session/new"),
                .agentSend(.object(["jsonrpc": .string("2.0"), "id": .string("$id"), "result": .object(["sessionId": .string("s-c1")])])),
                .expectClientRequest(method: "session/prompt"),
                .agentSend(.object([
                    "jsonrpc": .string("2.0"),
                    "id": .string("$id"),
                    "error": .object([
                        "code": .int(-32603),
                        "message": .string("Claude SDK query ended before producing a result"),
                    ]),
                ])),
            ])
        }
        _ = try await claudeConn.start(AgentSessionRequest(workingDirectory: "/tmp"))
        _ = try? await claudeConn.prompt([.text("Hi")])
        try await withACPTestTimeout(seconds: 3.0) { try await claudeDriver.value }
        let claudeStream = try await claudeEvents.collectAllUntilEnd(timeout: 3.0)
        let claudeFailure = claudeStream.compactMap { event -> AgentFailure? in
            if case .connectionFailed(let f) = event { return f }
            return nil
        }.first
        XCTAssertEqual(claudeFailure?.kind, .agentCrashed)
        await claudeConn.stop()
    }

    func testThreeFailureLockExplainsLockAndStillOffersCommandLine() async throws {
        let specs = LiveBannersLockedBox<[AgentConnectionSpec]>([])
        let failStarts = LiveBannersLockedBox<Bool>(true)
        let env = makeEnvironment { spec in
            specs.withValue { $0.append(spec) }
            let conn = LiveBannersMockConnection(spec: spec)
            conn.failStart = failStarts.value
            return conn
        }
        let session = VitruvianCodeQuickPromptSession(environment: env, host: LiveBannersMockHost())
        session.takeCheckpoint = { _ in nil }
        let config = VitruvianCodeConfiguration(approvalMode: .standard, activeProvider: Self.claudeSDKProvider)

        for attempt in 1...3 {
            session.send("Attempt \(attempt)", configuration: config, agentPath: "/fake/claude")
            try await waitUntil("attempt \(attempt) failed") {
                session.consecutiveRestartFailures == attempt && !session.isRunning
            }
        }
        XCTAssertTrue(session.isConnectionLockedAfterFailures)
        XCTAssertEqual(session.lastLiveFailure?.isLocked, true)

        // 4th send is blocked by lockout and produces lock explanation message.
        let countBefore = specs.value.count
        session.send("Attempt 4", configuration: config, agentPath: "/fake/claude")
        XCTAssertEqual(specs.value.count, countBefore)
        let lockMsg = session.messages.last(where: \.isError)?.text ?? ""
        XCTAssertTrue(lockMsg.contains("3") && lockMsg.lowercased().contains("locked"), "lock message must explain 3-failure lock: \(lockMsg)")
        XCTAssertEqual(session.lastLiveFailure?.isLocked, true)

        // User can still switch this chat to command line.
        failStarts.withValue { $0 = false }
        session.useCommandLineForThisChat(configuration: config, agentPath: "/fake/claude")
        try await waitUntil("command-line fallback started") { specs.value.count == countBefore + 1 }
        XCTAssertEqual(specs.value.last?.kind, .commandLine)
        XCTAssertFalse(session.isConnectionLockedAfterFailures)
        await session.stopAll()
    }

    // MARK: - Helpers

    private func uiSource(_ name: String) throws -> String {
        let relative = "apps/desktop/vitruvian-code/macos/Sources/VitruvianCodeUI/\(name)"
        var candidates: [String] = []
        let environment = ProcessInfo.processInfo.environment
        if let runfiles = environment["TEST_SRCDIR"] {
            for workspace in [environment["TEST_WORKSPACE"], "_main"].compactMap({ $0 }) {
                candidates.append("\(runfiles)/\(workspace)/\(relative)")
            }
        }
        let here = (#filePath as NSString).deletingLastPathComponent
        candidates.append((here as NSString).deletingLastPathComponent + "/Sources/VitruvianCodeUI/\(name)")
        let path = try XCTUnwrap(candidates.first { FileManager.default.fileExists(atPath: $0) }, "cannot find \(name)")
        return try String(contentsOfFile: path, encoding: .utf8)
    }

    private func waitUntil(
        _ description: String,
        timeout: TimeInterval = 4.0,
        condition: @escaping @MainActor () -> Bool
    ) async throws {
        try await withACPTestTimeout(seconds: timeout, description: description) { @MainActor in
            while !condition() {
                try? await Task.sleep(nanoseconds: 5_000_000)
            }
        }
    }

    private func makeEnvironment(
        makeConnection: @escaping (AgentConnectionSpec) -> any AgentConnection
    ) -> VitruvianCodeEngine.Environment {
        let domain = "com.vitruviansoftware.vitruvian-code.tests.live-banners.\(UUID().uuidString)"
        let defaults = ScratchDefaults.suite(named: domain)!
        defaults.removePersistentDomain(forName: domain)
        scratchSuites.append((defaults, domain))
        return VitruvianCodeEngine.Environment(
            defaults: defaults,
            home: "/tmp",
            processEnvironment: [:],
            stateDirectory: "/tmp/vitruvian-code-test-state",
            isExecutable: { _ in true },
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
            makeConnection: makeConnection,
            runProgram: { _, _ in nil }
        )
    }
}

private final class LiveBannersLockedBox<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var rawValue: Value

    init(_ initial: Value) { rawValue = initial }

    var value: Value { lock.withLock { rawValue } }

    func withValue(_ body: (inout Value) -> Void) {
        lock.withLock { body(&rawValue) }
    }
}

@MainActor
private final class LiveBannersMockConnection: PersistentAgentConnection {
    let spec: AgentConnectionSpec
    var capabilities = AgentCapabilities(resumeSession: true, closeSession: true)
    let events: AsyncStream<AgentEvent>
    private let continuation: AsyncStream<AgentEvent>.Continuation

    private(set) var startCalls: [AgentSessionRequest] = []
    private(set) var promptCalls: [[PromptBlock]] = []
    var failStart = false
    var isStopped = false
    var isConnected: Bool { !isStopped }

    private var promptContinuation: CheckedContinuation<AgentStopReason, any Error>?

    init(spec: AgentConnectionSpec) {
        self.spec = spec
        var captured: AsyncStream<AgentEvent>.Continuation!
        self.events = AsyncStream { captured = $0 }
        self.continuation = captured
    }

    func start(_ request: AgentSessionRequest) async throws -> String {
        startCalls.append(request)
        if failStart {
            throw ACPConnectionError.notStarted
        }
        return request.resumeSessionID ?? "mock-banners-1"
    }

    func syncPlanMode(_ planSwitch: Bool) async throws {}
    func syncMode(approvalMode: VitruvianCodeApprovalMode, planSwitch: Bool) async throws {}

    func prompt(_ blocks: [PromptBlock]) async throws -> AgentStopReason {
        promptCalls.append(blocks)
        return try await withCheckedThrowingContinuation { cont in
            self.promptContinuation = cont
        }
    }

    func cancel() async {}
    func answer(_ requestID: String, _ choice: AgentAnswer) async throws {}
    func setConfigOption(_ id: String, _ value: AgentConfigValue) async throws -> [AgentConfigOption] { [] }

    func stop() async {
        isStopped = true
        continuation.finish()
    }

    func emit(_ event: AgentEvent) {
        continuation.yield(event)
    }

    func finishPrompt(with reason: AgentStopReason) {
        let cont = promptContinuation
        promptContinuation = nil
        cont?.resume(returning: reason)
    }

    func failPrompt(with error: any Error) {
        let cont = promptContinuation
        promptContinuation = nil
        cont?.resume(throwing: error)
    }
}

@MainActor
private final class LiveBannersMockHost: VitruvianCodeHost {
    var configuredBotDirectory = ""
    var startsBotAtLaunch = false
    var planMode = false
    var hiddenClaudeSessionIDs: [String] = []
    var chosenProviderID: UUID? = VitruvianCodeCLIProvider.claude.id
    var chosenModels: [UUID: String] = [:]
    var savedProviders: [VitruvianCodeCLIProvider] = []
    var promptHistory: [String] = []
    var worktreeMode = false
    var timelineOnLeft = true
    var sessionPreferences = VitruvianCodeSessionPreferences()
    var chatModes: [String: String] = [:]
    var chatConnections: [String: String] = [:]
    var showsConnectionSetting = false
    var strings = VitruvianCodeHostStrings()

    func turnNeedsApproval(_ notice: VitruvianCodeTurnNotice) {}
    func turnFinished(_ notice: VitruvianCodeTurnNotice, isChatVisible: Bool) {}
}
