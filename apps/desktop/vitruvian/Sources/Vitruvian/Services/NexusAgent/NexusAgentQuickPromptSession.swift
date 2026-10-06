// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware
//
// Adapted from the standalone Nexus Agent app (apps/desktop/nexus-agent,
// MIT, Copyright (c) 2026 VitruvianSoftware): the streaming chat of its
// Quick Prompt window: the pill, the recent-sessions drawer and the chat.

import Foundation
import VitruvianCore

/// One bubble in the Quick Prompt.
package struct NexusAgentChatMessage: Identifiable, Equatable {
    package enum Role: Equatable { case user, agent }

    package let id: UUID
    package let role: Role
    package var text: String
    package var isError: Bool

    package init(id: UUID = UUID(), role: Role, text: String, isError: Bool = false) {
        self.id = id
        self.role = role
        self.text = text
        self.isError = isError
    }
}

/// A running agent turn, as the session can stop it.
package struct NexusAgentRunningAgent {
    package var terminate: () -> Void

    package init(terminate: @escaping () -> Void) {
        self.terminate = terminate
    }
}

/// The Quick Prompt's conversation: each turn runs `agy -p` with streamed
/// JSON and continues the conversation agy named on the first one, so the
/// agent keeps the context until New chat.
@MainActor
package final class NexusAgentQuickPromptSession: ObservableObject {
    @Published package private(set) var messages: [NexusAgentChatMessage] = []
    @Published package private(set) var isRunning = false
    /// The tool the agent is using right now, if any.
    @Published package private(set) var activity: String?
    @Published package private(set) var conversationID: String?
    @Published package var draft = ""
    /// Bumped when the prompt is shown, so the view puts the caret back.
    @Published package var focusSerial = 0
    /// Pill, drawer or chat; the service sizes the panel to match.
    @Published package private(set) var mode: NexusAgentQuickPromptMode = .compact
    @Published package private(set) var sessions: [NexusAgentSessionSummary] = []
    @Published package var sessionFilter = ""
    /// Turns run with `--mode plan` (read-only) while on. Remembered.
    @Published package var planMode: Bool {
        didSet { environment.defaults[Preferences.nexusAgentPlanMode] = planMode }
    }

    private let environment: NexusAgentService.Environment
    private var running: NexusAgentRunningAgent?
    private var buffer = NexusAgentLineBuffer()
    private var replyID: UUID?
    /// Callbacks from a turn that has since been stopped or replaced are dropped.
    private var turn = 0
    private var stoppedByUser = false
    private var reportedError = false
    /// Output that is not stream JSON (agy's own errors), kept for a failure.
    private var noise: [String] = []

    package init(environment: NexusAgentService.Environment) {
        self.environment = environment
        self.planMode = environment.defaults[Preferences.nexusAgentPlanMode]
    }

    /// Send is offered only for a prompt with text and no turn in flight.
    package var canSend: Bool {
        !isRunning && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    package var filteredSessions: [NexusAgentSessionSummary] {
        NexusAgentSessionSummary.filter(sessions, by: sessionFilter)
    }

    /// Opens the drawer with a fresh list from agy, or closes it again.
    package func toggleSessions(configuration: NexusAgentConfiguration) {
        if mode == .sessions {
            mode = messages.isEmpty ? .compact : .chat
            return
        }
        sessionFilter = ""
        sessions = environment.listSessions(workingDirectory(for: configuration))
        mode = .sessions
    }

    /// Continues a past conversation: the next turn passes its id to agy.
    package func resume(_ summary: NexusAgentSessionSummary) {
        newChat()
        conversationID = summary.id
        mode = .chat
    }

    /// The agy flags for this turn: plan mode overrides the bot's approval mode.
    package func turnConfiguration(_ configuration: NexusAgentConfiguration) -> NexusAgentConfiguration {
        var turn = configuration
        if planMode { turn.approvalMode = .plan }
        return turn
    }

    private var strings: NexusAgentFeatureStrings { FeatureStrings.nexusAgent(L10n.shared.language) }

    /// Starts a turn with the bot's own settings. A turn that cannot start
    /// says why in the conversation.
    package func send(_ prompt: String, configuration: NexusAgentConfiguration, agentPath: String?) {
        let text = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isRunning else { return }
        draft = ""
        mode = .chat
        messages.append(NexusAgentChatMessage(role: .user, text: text))
        guard let agentPath else {
            messages.append(NexusAgentChatMessage(role: .agent, text: strings.missingAgent, isError: true))
            return
        }
        turn += 1
        let current = turn
        buffer = NexusAgentLineBuffer()
        noise = []
        stoppedByUser = false
        reportedError = false
        let reply = NexusAgentChatMessage(role: .agent, text: "")
        replyID = reply.id
        messages.append(reply)
        isRunning = true
        activity = nil
        let arguments = NexusAgentSupport.agentArguments(prompt: text, configuration: turnConfiguration(configuration),
                                                         conversationID: conversationID)
        let childEnvironment = NexusAgentSupport.childEnvironment(base: environment.processEnvironment,
                                                                  home: environment.home)
        do {
            running = try environment.launchAgent(agentPath, arguments, workingDirectory(for: configuration),
                                                  childEnvironment,
                                                  { [weak self] data in self?.receive(data, turn: current) },
                                                  { [weak self] status in self?.agentDidExit(status, turn: current) })
        } catch {
            isRunning = false
            replace(reply: strings.agentFailed, isError: true)
            replyID = nil
        }
    }

    /// Ends the turn in flight; what arrived so far stays.
    package func stop() {
        guard isRunning else { return }
        stoppedByUser = true
        running?.terminate()
    }

    package func newChat() {
        stop()
        turn += 1
        running = nil
        isRunning = false
        activity = nil
        replyID = nil
        conversationID = nil
        messages = []
        mode = .compact
    }

    /// The bot's folder setting, `~` expanded; home when unset or gone.
    package func workingDirectory(for configuration: NexusAgentConfiguration) -> String {
        let configured = configuration.workingDirectory.trimmingCharacters(in: .whitespaces)
        guard !configured.isEmpty else { return environment.home }
        let expanded = NexusAgentSupport.botDirectory(configured: configured, home: environment.home)
        return environment.fileExists(expanded) ? expanded : environment.home
    }

    // MARK: - Stream

    private func receive(_ data: Data, turn current: Int) {
        guard current == turn else { return }
        for line in buffer.append(data) { handle(line) }
    }

    private func handle(_ line: String) {
        guard let event = NexusAgentStreamEvent.parse(line) else {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { noise = Array((noise + [trimmed]).suffix(5)) }
            return
        }
        switch event {
        case .started(let id):
            if let id { conversationID = id }
        case .text(let delta):
            activity = nil
            appendToReply(delta)
        case .tool(let name, let done):
            activity = done ? nil : name
        case .finished(_, let response, let error, let id):
            activity = nil
            if let id { conversationID = id }
            if let response, currentReplyText.isEmpty { appendToReply(response) }
            if let error {
                reportedError = true
                messages.append(NexusAgentChatMessage(role: .agent, text: error, isError: true))
            }
        }
    }

    private func agentDidExit(_ status: Int32, turn current: Int) {
        guard current == turn else { return }
        if let rest = buffer.finish() { handle(rest) }
        running = nil
        isRunning = false
        activity = nil
        if stoppedByUser {
            if currentReplyText.isEmpty { replace(reply: strings.replyStopped, isError: false) }
        } else if currentReplyText.isEmpty {
            if reportedError {
                // agy said what went wrong in a bubble of its own.
                removeReply()
            } else if status != 0 {
                let detail = ([strings.agentFailed] + noise).joined(separator: "\n")
                replace(reply: detail, isError: true)
            } else {
                replace(reply: strings.emptyReply, isError: false)
            }
        }
        replyID = nil
    }

    private var currentReplyText: String {
        guard let replyID, let message = messages.first(where: { $0.id == replyID }) else { return "" }
        return message.text
    }

    private func appendToReply(_ text: String) {
        guard let replyID, let index = messages.firstIndex(where: { $0.id == replyID }) else { return }
        messages[index].text += text
    }

    private func replace(reply text: String, isError: Bool) {
        guard let replyID, let index = messages.firstIndex(where: { $0.id == replyID }) else { return }
        messages[index].text = text
        messages[index].isError = isError
    }

    private func removeReply() {
        guard let replyID else { return }
        messages.removeAll { $0.id == replyID }
    }
}
