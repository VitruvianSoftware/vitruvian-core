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

/// A prompt typed while a turn runs waits for it, and goes when it ends
/// cleanly; Undo Turn puts the files back.
@MainActor
final class QueuedPromptTests: XCTestCase {
    private let configuration = NexusAgentConfiguration(model: "m1")

    func testReturnWhileRunningQueuesAndACleanEndSendsIt() {
        let rig = ComposerRig()
        let session = rig.session()
        session.send("first", configuration: configuration, agentPath: "/fake/agy")
        session.draft = "second"
        XCTAssertEqual(session.submitDraft(configuration: configuration, agentPath: "/fake/agy"), .queued)
        XCTAssertEqual(session.queuedPrompt, "second")
        XCTAssertEqual(session.draft, "")
        XCTAssertEqual(rig.launches.count, 1)

        rig.finishCleanly()
        XCTAssertNil(session.queuedPrompt)
        XCTAssertTrue(session.isRunning, "the queued prompt is the next turn")
        XCTAssertEqual(rig.launches.count, 2)
        XCTAssertEqual(session.messages.filter { $0.role == .user }.map(\.text), ["first", "second"])
        rig.finishCleanly()
        session.stopTranscriptFollower()
    }

    func testASecondQueuedPromptGoesUnderTheFirst() {
        let session = ComposerRig().session()
        session.queue("one")
        session.queue("two")
        XCTAssertEqual(session.queuedPrompt, "one\n\ntwo")
        session.queue("   ")
        XCTAssertEqual(session.queuedPrompt, "one\n\ntwo")
    }

    func testAStoppedTurnKeepsItWaiting() {
        let rig = ComposerRig()
        let session = rig.session()
        session.send("first", configuration: configuration, agentPath: "/fake/agy")
        session.queue("later")
        session.stop()
        rig.agentExit?(15)
        XCTAssertFalse(session.isRunning)
        XCTAssertEqual(session.queuedPrompt, "later", "a stop is not a go-ahead")
        XCTAssertEqual(rig.launches.count, 1)
        session.stopTranscriptFollower()
    }

    func testAFailedTurnKeepsItWaiting() {
        let rig = ComposerRig()
        let session = rig.session()
        session.send("first", configuration: configuration, agentPath: "/fake/agy")
        session.queue("later")
        rig.agentExit?(1)
        XCTAssertNotNil(session.lastFailedPrompt)
        XCTAssertEqual(session.queuedPrompt, "later")
        XCTAssertEqual(rig.launches.count, 1)
        session.stopTranscriptFollower()
    }

    func testEditPutsItBackInTheComposer() {
        let session = ComposerRig().session()
        session.queue("waiting")
        session.draft = "typed"
        session.editQueuedPrompt()
        XCTAssertNil(session.queuedPrompt)
        XCTAssertEqual(session.draft, "waiting\n\ntyped")
        session.queue("x")
        session.cancelQueuedPrompt()
        XCTAssertNil(session.queuedPrompt)
    }

    func testNewChatDropsTheQueue() {
        let session = ComposerRig().session()
        session.queue("waiting")
        session.newChat()
        XCTAssertNil(session.queuedPrompt)
    }

    func testUndoRestoresTheCheckpointOnceAndSaysSo() {
        let rig = ComposerRig()
        let session = rig.session()
        var restored: [(String, String)] = []
        session.takeCheckpoint = { _ in "abc123" }
        session.restoreCheckpoint = { sha, directory in restored.append((sha, directory)); return true }

        session.send("edit things", configuration: configuration, agentPath: "/fake/agy")
        XCTAssertFalse(session.canUndoLastTurn, "not while the turn runs")
        rig.finishCleanly()
        XCTAssertTrue(session.canUndoLastTurn)
        let count = session.messages.count

        XCTAssertTrue(session.undoLastTurn(note: "restored"))
        XCTAssertEqual(restored.map(\.0), ["abc123"])
        XCTAssertEqual(restored.first?.1, "/Users/rig", "the folder the turn ran in")
        XCTAssertEqual(session.messages.count, count + 1, "the conversation is kept, with a note")
        XCTAssertEqual(session.messages.last?.text, "restored")
        XCTAssertFalse(session.canUndoLastTurn)
        XCTAssertFalse(session.undoLastTurn(note: "again"))
        session.stopTranscriptFollower()
    }

    func testNoCheckpointMeansNoUndo() {
        let rig = ComposerRig()
        let session = rig.session()
        session.send("x", configuration: configuration, agentPath: "/fake/agy")
        rig.finishCleanly()
        XCTAssertFalse(session.canUndoLastTurn)
        session.stopTranscriptFollower()
    }

    func testAFailedRestoreChangesNothing() {
        let rig = ComposerRig()
        let session = rig.session()
        session.takeCheckpoint = { _ in "abc" }
        session.restoreCheckpoint = { _, _ in false }
        session.send("x", configuration: configuration, agentPath: "/fake/agy")
        rig.finishCleanly()
        let count = session.messages.count
        XCTAssertFalse(session.undoLastTurn(note: "n"))
        XCTAssertEqual(session.messages.count, count)
        XCTAssertTrue(session.canUndoLastTurn, "it can be tried again")
        session.stopTranscriptFollower()
    }

    func testPlanAndWorktreeModesSkipTakingAnUndoCheckpoint() {
        let rig = ComposerRig()
        let session = rig.session()
        var checkpointsTaken = 0
        session.takeCheckpoint = { _ in
            checkpointsTaken += 1
            return "sha-\(checkpointsTaken)"
        }

        session.planMode = true
        session.send("read only", configuration: configuration, agentPath: "/fake/agy")
        rig.finishCleanly()
        XCTAssertEqual(checkpointsTaken, 0, "plan mode does not checkpoint the working tree")
        XCTAssertFalse(session.canUndoLastTurn)

        session.planMode = false
        session.worktreeMode = true
        session.send("in worktree", configuration: configuration, agentPath: "/fake/agy")
        rig.finishCleanly()
        XCTAssertEqual(checkpointsTaken, 0, "worktree mode runs in an isolated worktree, not workingDirectory")
        XCTAssertFalse(session.canUndoLastTurn)
        session.stopTranscriptFollower()
    }
}
