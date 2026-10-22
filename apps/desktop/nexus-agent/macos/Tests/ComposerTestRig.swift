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

import AppKit
import Foundation
import NexusAgentCore

/// A host that says nothing and keeps nothing.
final class ComposerQuietHost: NexusAgentHost {
    var configuredBotDirectory = ""
    var startsBotAtLaunch = false
    var planMode = false
    var hiddenClaudeSessionIDs: [String] = []
    var chosenProviderID: UUID?
    var savedProviders: [NexusAgentCLIProvider] = []
    var promptHistory: [String] = []
    var worktreeMode = false
    var strings = NexusAgentHostStrings()
    var sessionPreferences = NexusAgentSessionPreferences()
    func turnNeedsApproval(_ notice: NexusAgentTurnNotice) {}
    func turnFinished(_ notice: NexusAgentTurnNotice, isChatVisible: Bool) {}
}

/// An agent that is started and answers only when the test says, keeping
/// every launch's arguments.
@MainActor
final class ComposerRig {
    var launches: [[String]] = []
    var terminations = 0
    /// What was written to the agent's standard input, line by line, and
    /// how many times it was closed.
    var inputs: [Data] = []
    var inputCloses = 0
    var agentExit: (@MainActor @Sendable (Int32) -> Void)?
    var agentOutput: (@MainActor @Sendable (Data) -> Void)?
    var sessions: [NexusAgentSessionSummary] = []
    let defaults: UserDefaults
    let host = ComposerQuietHost()

    init() {
        let suite = "com.vitruviansoftware.nexus-agent.tests.composer.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
    }

    var environment: NexusAgentEngine.Environment {
        NexusAgentEngine.Environment(
            defaults: defaults,
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
            launchAgent: { [unowned self] _, arguments, _, _, onOutput, onExit in
                launches.append(arguments)
                agentOutput = onOutput
                agentExit = onExit
                return NexusAgentRunningAgent(terminate: { [unowned self] in terminations += 1 },
                                              sendInput: { [unowned self] data in inputs.append(data) },
                                              closeInput: { [unowned self] in inputCloses += 1 })
            },
            listSessions: { [unowned self] _, _, _ in sessions })
    }

    func session() -> NexusAgentQuickPromptSession {
        let session = NexusAgentQuickPromptSession(environment: environment, host: host)
        // No git in tests unless a test asks for it.
        session.takeCheckpoint = { _ in nil }
        return session
    }

    /// A clean end to the turn in flight: exit 0.
    func finishCleanly() {
        agentExit?(0)
    }
}
