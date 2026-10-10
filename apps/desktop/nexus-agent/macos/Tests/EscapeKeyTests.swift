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

import XCTest

import NexusAgentCore

/// What Esc does in a window that shows the chat. Each app's window takes
/// the key before the chat's views see it and asks the session
/// (`pressEscape`), so the rule is tested here without a window: an editor
/// open in the chat closes first, then a reply in flight is stopped, and
/// only a press with neither is the window's.
@MainActor
final class EscapeKeyTests: XCTestCase {
    private typealias Key = NexusAgentEscapeKey

    // MARK: - The rule

    func testAnOpenEditorIsClosedWhateverElseIsGoingOn() {
        XCTAssertEqual(Key.action(inlineEditorOpen: true, replyToStop: false), .closeInlineEditor)
        XCTAssertEqual(Key.action(inlineEditorOpen: true, replyToStop: true), .closeInlineEditor,
                       "the editor comes before the reply: one press does not also stop it")
    }

    func testWithNoEditorAReplyInFlightIsStopped() {
        XCTAssertEqual(Key.action(inlineEditorOpen: false, replyToStop: true), .stopReply)
    }

    func testWithNothingInTheWayTheWindowGoes() {
        XCTAssertEqual(Key.action(inlineEditorOpen: false, replyToStop: false), .dismiss)
    }

    // MARK: - The session doing it

    private final class QuietHost: NexusAgentHost {
        var configuredBotDirectory = ""
        var startsBotAtLaunch = false
        var planMode = false
        var hiddenClaudeSessionIDs: [String] = []
        var chosenProviderID: UUID?
        var savedProviders: [NexusAgentCLIProvider] = []
        var promptHistory: [String] = []
        var worktreeMode = false
        var strings = NexusAgentHostStrings()
        func turnNeedsApproval(_ notice: NexusAgentTurnNotice) {}
        func turnFinished(_ notice: NexusAgentTurnNotice, isChatVisible: Bool) {}
    }

    /// An agent that is started and never answers, so a turn stays in
    /// flight until the test ends it. It counts how often it is told to stop.
    @MainActor
    private final class World {
        var terminations = 0
        var agentExit: (@MainActor @Sendable (Int32) -> Void)?

        var environment: NexusAgentEngine.Environment {
            NexusAgentEngine.Environment(
                defaults: UserDefaults(suiteName: "com.vitruviansoftware.nexus-agent.tests.unused")!,
                home: "/Users/rig",
                processEnvironment: ["PATH": "/usr/bin"],
                stateDirectory: "/Users/rig/state",
                isExecutable: { _ in false },
                fileExists: { _ in false },
                readFile: { _ in nil },
                readTail: { _, _ in nil },
                writePrivateFile: { _, _ in false },
                removeFile: { _ in },
                isBotProcess: { _ in false },
                signal: { _, _ in },
                launchBot: { _, _, _, _, _ in throw CocoaError(.fileWriteUnknown) },
                schedule: { _, _ in },
                openFile: { _ in },
                launchAgent: { [unowned self] _, _, _, _, _, onExit in
                    agentExit = onExit
                    return NexusAgentRunningAgent(terminate: { [unowned self] in terminations += 1 })
                },
                listSessions: { _, _, _ in [] })
        }
    }

    /// A session with a reply in flight in the conversation on show.
    private func sessionWithAReplyInFlight(_ world: World) -> NexusAgentQuickPromptSession {
        let session = NexusAgentQuickPromptSession(environment: world.environment, host: QuietHost())
        session.send("go on", configuration: NexusAgentConfiguration(model: "m1"), agentPath: "/fake/agy")
        XCTAssertTrue(session.isRunning)
        XCTAssertEqual(session.mode, .chat)
        return session
    }

    /// Ends the turn as a stopped agent does, and the timers with it.
    private func end(_ session: NexusAgentQuickPromptSession, _ world: World) {
        world.agentExit?(15)
        session.stopTranscriptFollower()
    }

    func testEscClosesTheModelEditorAndNothingElse() {
        let world = World()
        let session = sessionWithAReplyInFlight(world)
        defer { end(session, world) }
        session.isEditingModel = true

        XCTAssertEqual(session.pressEscape(stoppingReply: true), .closeInlineEditor,
                       "the key is taken: the window does not close")
        XCTAssertFalse(session.isEditingModel, "the editor is closed")
        XCTAssertEqual(world.terminations, 0, "the reply behind the editor goes on arriving")
        XCTAssertTrue(session.isRunning)
        XCTAssertEqual(session.mode, .chat)
    }

    func testTheNextEscStopsTheReplyAndTheOneAfterIsTheWindows() {
        let world = World()
        let session = sessionWithAReplyInFlight(world)
        defer { session.stopTranscriptFollower() }
        session.isEditingModel = true
        _ = session.pressEscape(stoppingReply: true)

        XCTAssertEqual(session.pressEscape(stoppingReply: true), .stopReply)
        XCTAssertEqual(world.terminations, 1, "the agent was told to stop, once")
        world.agentExit?(15)
        XCTAssertFalse(session.isRunning)

        XCTAssertEqual(session.pressEscape(stoppingReply: true), .dismiss, "nothing is left of the chat's: the window goes")
        XCTAssertEqual(world.terminations, 1)
        XCTAssertEqual(session.mode, .chat, "the conversation is kept")
    }

    func testEscWithNothingOpenAndNothingRunningIsTheWindows() {
        let session = NexusAgentQuickPromptSession(environment: World().environment, host: QuietHost())
        XCTAssertFalse(session.cancelInlineEditing(), "there is no editor to close")
        XCTAssertEqual(session.pressEscape(stoppingReply: true), .dismiss)
        XCTAssertEqual(session.mode, .compact)
        XCTAssertFalse(session.isEditingModel)
    }

    /// The standalone app's rule, kept: Esc stops a reply only while its
    /// conversation is what the window shows.
    func testAReplyBehindTheSessionListIsNotStopped() {
        let world = World()
        let session = sessionWithAReplyInFlight(world)
        defer { end(session, world) }
        session.toggleSessions(configuration: NexusAgentConfiguration())
        XCTAssertEqual(session.mode, .sessions)

        XCTAssertEqual(session.pressEscape(stoppingReply: true), .dismiss)
        XCTAssertEqual(world.terminations, 0)
        XCTAssertTrue(session.isRunning)
    }

    /// Vitruvian's windows close on Esc and let the reply go on arriving.
    /// They still close an open editor first.
    func testAWindowWhoseEscNeverStopsAReply() {
        let world = World()
        let session = sessionWithAReplyInFlight(world)
        defer { end(session, world) }

        XCTAssertEqual(session.pressEscape(stoppingReply: false), .dismiss)
        XCTAssertEqual(world.terminations, 0, "the reply goes on arriving behind the closed window")
        XCTAssertTrue(session.isRunning)

        session.isEditingModel = true
        XCTAssertEqual(session.pressEscape(stoppingReply: false), .closeInlineEditor)
        XCTAssertFalse(session.isEditingModel)
        XCTAssertEqual(world.terminations, 0)
    }

    func testCancellingClosesAnOpenEditorOnce() {
        let session = NexusAgentQuickPromptSession(environment: World().environment, host: QuietHost())
        session.isEditingModel = true
        XCTAssertTrue(session.cancelInlineEditing())
        XCTAssertFalse(session.isEditingModel)
        XCTAssertFalse(session.cancelInlineEditing(), "a second call finds nothing open")
    }
}
