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

import NexusAgentCore
import XCTest

/// The composer's `/` commands: which the chat runs itself, and which go to
/// the agent.
@MainActor
final class SlashCommandTests: XCTestCase {
    private let configuration = NexusAgentConfiguration(model: "m1")

    func testEffortCyclesThroughEveryLevelAndRoundAgain() {
        typealias S = NexusAgentQuickPromptSession
        XCTAssertEqual(S.nextEffort(after: .automatic), .low)
        XCTAssertEqual(S.nextEffort(after: .low), .medium)
        XCTAssertEqual(S.nextEffort(after: .medium), .high)
        XCTAssertEqual(S.nextEffort(after: .high), .max)
        XCTAssertEqual(S.nextEffort(after: .max), .automatic)
    }

    func testPlanAndWorktreeToggleLocallyAndClearTheDraft() {
        let rig = ComposerRig()
        let session = rig.session()
        session.draft = "/plan"
        XCTAssertEqual(session.submitDraft(configuration: configuration, agentPath: "/fake/agy"),
                       .command(.planMode(true)))
        XCTAssertTrue(session.planMode)
        XCTAssertEqual(session.draft, "")
        XCTAssertTrue(rig.launches.isEmpty, "nothing went to the agent")

        session.draft = "/worktree"
        XCTAssertEqual(session.submitDraft(configuration: configuration, agentPath: "/fake/agy"),
                       .command(.worktreeMode(true)))
        XCTAssertTrue(session.worktreeMode)
    }

    func testModelAloneOpensTheEditor() {
        let session = ComposerRig().session()
        session.draft = "/model"
        XCTAssertEqual(session.submitDraft(configuration: configuration, agentPath: nil), .command(.editModel))
        XCTAssertTrue(session.isEditingModel)
    }

    func testClearStartsANewChat() {
        let rig = ComposerRig()
        let session = rig.session()
        session.send("hello", configuration: configuration, agentPath: "/fake/agy")
        rig.finishCleanly()
        XCTAssertFalse(session.messages.isEmpty)
        session.draft = "/clear"
        XCTAssertEqual(session.submitDraft(configuration: configuration, agentPath: "/fake/agy"), .command(.newChat))
        XCTAssertTrue(session.messages.isEmpty)
        XCTAssertEqual(session.mode, .compact)
    }

    func testCompactAndUnknownCommandsGoToTheAgentAsThePrompt() {
        let rig = ComposerRig()
        let session = rig.session()
        session.draft = "/compact"
        XCTAssertEqual(session.submitDraft(configuration: configuration, agentPath: "/fake/agy"), .sent)
        XCTAssertEqual(rig.launches.count, 1)
        XCTAssertTrue(rig.launches[0].contains(where: { $0.contains("/compact") }), "\(rig.launches[0])")
        XCTAssertEqual(session.messages.first?.text, "/compact")
        rig.finishCleanly()

        XCTAssertEqual(session.runSlashCommand("/review now", configuration: configuration, agentPath: "/fake/agy"),
                       .sentToAgent("/review now"))
        XCTAssertEqual(rig.launches.count, 2)
        session.stopTranscriptFollower()
    }

    func testAPathIsAPromptNotACommand() {
        let session = ComposerRig().session()
        XCTAssertNil(session.runSlashCommand("/Users/me/notes.txt explain", configuration: configuration,
                                             agentPath: nil))
        XCTAssertNil(session.runSlashCommand("hello", configuration: configuration, agentPath: nil))
        XCTAssertNil(session.runSlashCommand("/", configuration: configuration, agentPath: nil))
    }

    func testCostAddsUpTheRepliesAndSaysSo() {
        let session = ComposerRig().session()
        session.messages = [
            NexusAgentChatMessage(role: .user, text: "a"),
            NexusAgentChatMessage(role: .agent, text: "b", inputTokens: 100, outputTokens: 20, cachedTokens: 5,
                                  totalCostUSD: 0.01),
            NexusAgentChatMessage(role: .agent, text: "c", inputTokens: 50, outputTokens: 10, totalCostUSD: 0.02),
            NexusAgentChatMessage(role: .agent, text: "no figures"),
        ]
        let result = session.runSlashCommand("/cost", configuration: configuration, agentPath: nil,
                                             costSummary: { "total \($0.inputTokens)" })
        guard case .cost(let totals) = result else { return XCTFail("\(String(describing: result))") }
        XCTAssertEqual(totals.inputTokens, 150)
        XCTAssertEqual(totals.outputTokens, 30)
        XCTAssertEqual(totals.cachedTokens, 5)
        XCTAssertEqual(totals.costUSD ?? 0, 0.03, accuracy: 0.0001)
        XCTAssertEqual(totals.replies, 2)
        XCTAssertEqual(session.messages.last?.text, "total 150")
        XCTAssertNil(session.messages.last?.inputTokens, "the note carries no figures to be counted again")
        XCTAssertEqual(NexusAgentQuickPromptSession.costTotals(of: session.messages), totals)
    }

    func testForkNeedsAConversationAndGoesWithTheNextTurnOnly() {
        let rig = ComposerRig()
        let session = rig.session()
        XCTAssertEqual(session.runSlashCommand("/fork", configuration: configuration, agentPath: nil), .nothingToFork)
        XCTAssertFalse(session.forkNextTurn)

        session.resume(NexusAgentSessionSummary(id: "conv-9", title: "Old", steps: 2, modified: nil),
                       configuration: NexusAgentConfiguration(activeProvider: .claude))
        XCTAssertEqual(session.runSlashCommand("/fork", configuration: configuration, agentPath: nil), .forked)
        XCTAssertTrue(session.forkNextTurn)
        session.send("go", configuration: NexusAgentConfiguration(activeProvider: .claude), agentPath: "/fake/claude")
        XCTAssertFalse(session.forkNextTurn, "the fork is used up by the turn")
        XCTAssertTrue(rig.launches.last?.contains("--fork-session") ?? false, "\(rig.launches)")
        rig.finishCleanly()
        session.send("again", configuration: NexusAgentConfiguration(activeProvider: .claude), agentPath: "/fake/claude")
        XCTAssertFalse(rig.launches.last?.contains("--fork-session") ?? true)
        rig.finishCleanly()
        session.stopTranscriptFollower()
    }

    func testForkFromTheDrawerResumesAndArms() {
        let session = ComposerRig().session()
        session.fork(NexusAgentSessionSummary(id: "conv-3", title: "T", steps: 1, modified: nil),
                     configuration: configuration)
        XCTAssertEqual(session.conversationID, "conv-3")
        XCTAssertTrue(session.forkNextTurn)
        session.stopTranscriptFollower()
    }

    func testPinsAndNamesGoThroughTheHost() {
        let rig = ComposerRig()
        rig.sessions = [
            NexusAgentSessionSummary(id: "a", title: "First", steps: 1, modified: nil),
            NexusAgentSessionSummary(id: "b", title: "Second", steps: 1, modified: nil),
        ]
        let session = rig.session()
        session.refreshSessions(configuration: configuration)
        XCTAssertEqual(session.sessions.map(\.id), ["a", "b"])

        session.togglePin(session.sessions[1])
        XCTAssertEqual(session.sessions.map(\.id), ["b", "a"], "pinned first")
        XCTAssertTrue(session.sessions[0].isPinned)
        XCTAssertTrue(rig.host.sessionPreferences.isPinned("b"), "kept by the host")

        session.renamingSessionID = "a"
        session.rename(session.sessions[1], to: "  Renamed  ")
        XCTAssertNil(session.renamingSessionID, "the editor closes")
        XCTAssertEqual(session.sessions.first(where: { $0.id == "a" })?.title, "Renamed")

        session.togglePin(session.sessions[0])
        XCTAssertEqual(session.sessions.map(\.id), ["a", "b"], "unpinned goes back to its place")
    }

    func testEscClosesTheRenameEditorFirst() {
        let session = ComposerRig().session()
        session.renamingSessionID = "a"
        XCTAssertEqual(session.pressEscape(stoppingReply: true), .closeInlineEditor)
        XCTAssertNil(session.renamingSessionID)
    }
}
