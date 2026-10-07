// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware
//
// Adapted from the standalone Nexus Agent app (apps/desktop/nexus-agent,
// MIT, Copyright (c) 2026 VitruvianSoftware): the streaming chat of its
// Quick Prompt window: the pill, the recent-sessions drawer and the chat.

import AppKit
import Foundation
import VitruvianCore

/// One bubble in the Quick Prompt.
package struct NexusAgentChatMessage: Identifiable, Equatable {
    package enum Role: Equatable { case user, agent }

    package let id: UUID
    package let role: Role
    package var text: String
    package var isError: Bool
    package var durationMs: Int?
    package var inputTokens: Int?
    package var outputTokens: Int?
    package var cachedTokens: Int?
    package var numTurns: Int?
    package var toolCalls: Int?
    package var modelName: String?
    package var stopReason: String?
    package var toolSteps: [NexusAgentToolStep]?
    package var thinkingText: String?
    package var totalCostUSD: Double?
    package var approvalRequest: NexusAgentApprovalRequest?

    package init(
        id: UUID = UUID(),
        role: Role,
        text: String,
        isError: Bool = false,
        durationMs: Int? = nil,
        inputTokens: Int? = nil,
        outputTokens: Int? = nil,
        cachedTokens: Int? = nil,
        numTurns: Int? = nil,
        toolCalls: Int? = nil,
        modelName: String? = nil,
        stopReason: String? = nil,
        toolSteps: [NexusAgentToolStep]? = nil,
        thinkingText: String? = nil,
        totalCostUSD: Double? = nil,
        approvalRequest: NexusAgentApprovalRequest? = nil
    ) {
        self.id = id
        self.role = role
        self.text = text
        self.isError = isError
        self.durationMs = durationMs
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.cachedTokens = cachedTokens
        self.numTurns = numTurns
        self.toolCalls = toolCalls
        self.modelName = modelName
        self.stopReason = stopReason
        self.toolSteps = toolSteps
        self.thinkingText = thinkingText
        self.totalCostUSD = totalCostUSD
        self.approvalRequest = approvalRequest
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
    @Published package var messages: [NexusAgentChatMessage] = []
    @Published package private(set) var isRunning = false
    /// The tool the agent is using right now, if any.
    @Published package private(set) var activity: String?
    @Published package private(set) var conversationID: String?
    @Published package var draft = ""
    /// Bumped when the prompt is shown, so the view puts the caret back.
    @Published package var focusSerial = 0
    @Published package private(set) var mode: NexusAgentQuickPromptMode = .compact
    @Published package private(set) var sessions: [NexusAgentSessionSummary] = []
    @Published package var sessionFilter = ""
    /// The active session's title when resumed from the drawer.
    @Published package private(set) var sessionTitle: String?
    /// True while viewing or continuing a resumed conversation.
    @Published package private(set) var isResumed = false
    /// The last prompt that failed, allowing 1-click retry.
    @Published package var lastFailedPrompt: String?
    /// Elapsed seconds during current active generation.
    @Published package private(set) var elapsedSeconds: Int = 0
    /// History of sent prompts for Up/Down arrow navigation.
    @Published package var promptHistory: [String] = []
    @Published package var historyIndex: Int = -1
    /// Callback when an agent turn completes (reply text, isError).
    package var onTurnFinished: ((String, Bool) -> Void)?
    /// Turns run with `--mode plan` (read-only) while on. Remembered.
    @Published package var planMode: Bool {
        didSet { environment.defaults[Preferences.nexusAgentPlanMode] = planMode }
    }
    /// Turns run with `-w` (isolated git worktree) while on.
    @Published package var worktreeMode: Bool = false

    @Published package private(set) var activeSubagents: [NexusAgentActiveSubagent] = []
    @Published package var isFollowerActive: Bool = false
    package weak var service: NexusAgentService?
    private var followerTimer: Timer?
    private var lastTranscriptModDate: Date?
    private var lastTranscriptSize: UInt64?
    private var activeProvider: NexusAgentCLIProvider?

    private let environment: NexusAgentService.Environment
    private var running: NexusAgentRunningAgent?
    private var buffer = NexusAgentLineBuffer()
    private var replyID: UUID?
    private var currentToolCalls = 0
    private var elapsedTimer: Timer?
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

    /// Opens the drawer with a fresh list from the active provider, or closes it again.
    package func toggleSessions(configuration: NexusAgentConfiguration) {
        if mode == .sessions {
            mode = messages.isEmpty ? .compact : .chat
            return
        }
        sessionFilter = ""
        sessions = environment.listSessions(sessionsDirectory(for: configuration), configuration.activeProvider)
        mode = .sessions
    }

    /// Refreshes the session list using the active provider.
    package func refreshSessions(configuration: NexusAgentConfiguration) {
        sessions = environment.listSessions(sessionsDirectory(for: configuration), configuration.activeProvider)
    }

    /// Archives a session and reloads the drawer list.
    package func archive(_ summary: NexusAgentSessionSummary, configuration: NexusAgentConfiguration) {
        if let service {
            service.archiveSession(summary, configuration: configuration)
        } else {
            NexusAgentService.shared.archiveSession(summary, configuration: configuration)
        }
        refreshSessions(configuration: configuration)
    }

    /// Unarchives a session and reloads the drawer list.
    package func unarchive(_ summary: NexusAgentSessionSummary, configuration: NexusAgentConfiguration) {
        if let service {
            service.unarchiveSession(summary, configuration: configuration)
        } else {
            NexusAgentService.shared.unarchiveSession(summary, configuration: configuration)
        }
        refreshSessions(configuration: configuration)
    }

    /// Starts watching the transcript file for live updates while in chat mode.
    package func startTranscriptFollower(provider: NexusAgentCLIProvider? = nil) {
        if let provider { self.activeProvider = provider }
        guard let convID = conversationID, !convID.isEmpty, mode == .chat else { return }
        stopTranscriptFollower()
        isFollowerActive = true
        checkTranscriptUpdates()
        followerTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.checkTranscriptUpdates()
            }
        }
    }

    /// Stops watching the transcript file.
    package func stopTranscriptFollower() {
        followerTimer?.invalidate()
        followerTimer = nil
        isFollowerActive = false
        lastTranscriptModDate = nil
        lastTranscriptSize = nil
    }

    /// Checks the transcript file for updates and refreshes messages and active subagents.
    package func checkTranscriptUpdates() {
        guard let convID = conversationID, !convID.isEmpty else { return }
        let provider = activeProvider ?? .antigravity
        guard let path = environment.transcriptPath(convID, provider) else { return }

        let fm = FileManager.default
        var isChanged = false
        if let attrs = try? fm.attributesOfItem(atPath: path) {
            let modDate = attrs[.modificationDate] as? Date
            let size = (attrs[.size] as? NSNumber)?.uint64Value
            if modDate != lastTranscriptModDate || size != lastTranscriptSize {
                lastTranscriptModDate = modDate
                lastTranscriptSize = size
                isChanged = true
            }
        } else {
            isChanged = true
        }

        if isChanged {
            if let raw = environment.readTranscriptRaw(convID, provider) {
                let parsedSubagents = NexusAgentService.parseActiveSubagents(from: raw)
                if self.activeSubagents != parsedSubagents {
                    self.activeSubagents = parsedSubagents
                }
                if !isRunning, let reloaded = environment.readTranscript(convID, provider) {
                    if reloaded != self.messages {
                        self.messages = reloaded
                    }
                }
            }
        }
    }

    /// Continues a past conversation: the next turn passes its id to the active provider.
    package func resume(_ summary: NexusAgentSessionSummary, configuration: NexusAgentConfiguration = NexusAgentConfiguration()) {
        stop()
        turn += 1
        running = nil
        isRunning = false
        activity = nil
        replyID = nil
        conversationID = summary.id
        let effectiveTitle = summary.title.isEmpty
            ? (summary.preview.split(separator: "\n").first.map(String.init) ?? "")
            : summary.title
        sessionTitle = effectiveTitle.isEmpty ? nil : effectiveTitle
        isResumed = true

        if let loaded = environment.readTranscript(summary.id, configuration.activeProvider), !loaded.isEmpty {
            messages = loaded
        } else {
            var restored: [NexusAgentChatMessage] = []
            if !summary.preview.isEmpty {
                restored.append(NexusAgentChatMessage(role: .user, text: summary.preview))
            }
            let title = sessionTitle ?? strings.untitledSession
            let steps = summary.steps > 0 ? " (\(summary.steps) steps)" : ""
            restored.append(NexusAgentChatMessage(
                role: .agent,
                text: "Resumed “\(title)”\(steps). \(configuration.activeProvider.name) remembers earlier turns — send a message to continue."
            ))
            messages = restored
        }
        mode = .chat
        startTranscriptFollower(provider: configuration.activeProvider)
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
        if !promptHistory.contains(text) { promptHistory.append(text) }
        historyIndex = -1
        lastFailedPrompt = nil
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
        currentToolCalls = 0
        let model = configuration.model.trimmingCharacters(in: .whitespaces)
        let reply = NexusAgentChatMessage(role: .agent, text: "", modelName: model.isEmpty ? nil : model)
        replyID = reply.id
        messages.append(reply)
        isRunning = true
        startTranscriptFollower(provider: configuration.activeProvider)
        activity = nil
        elapsedSeconds = 0
        elapsedTimer?.invalidate()
        elapsedTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.elapsedSeconds += 1
            }
        }
        let arguments = NexusAgentSupport.agentArguments(prompt: text, configuration: turnConfiguration(configuration),
                                                         conversationID: conversationID,
                                                         planMode: planMode,
                                                         worktreeMode: worktreeMode)
        let childEnvironment = NexusAgentSupport.childEnvironment(base: environment.processEnvironment,
                                                                  home: environment.home)
        do {
            running = try environment.launchAgent(agentPath, arguments, workingDirectory(for: configuration),
                                                  childEnvironment,
                                                  { [weak self] data in self?.receive(data, turn: current) },
                                                  { [weak self] status in self?.agentDidExit(status, turn: current) })
        } catch {
            isRunning = false
            stopTranscriptFollower()
            elapsedTimer?.invalidate()
            elapsedTimer = nil
            replace(reply: strings.agentFailed, isError: true)
            replyID = nil
        }
    }

    /// Ends the turn in flight; what arrived so far stays.
    package func stop() {
        guard isRunning else { return }
        stoppedByUser = true
        stopTranscriptFollower()
        elapsedTimer?.invalidate()
        elapsedTimer = nil
        running?.terminate()
    }

    package func newChat() {
        stop()
        stopTranscriptFollower()
        activeSubagents = []
        turn += 1
        running = nil
        isRunning = false
        activity = nil
        replyID = nil
        conversationID = nil
        sessionTitle = nil
        isResumed = false
        lastFailedPrompt = nil
        elapsedTimer?.invalidate()
        elapsedTimer = nil
        elapsedSeconds = 0
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

    /// The folder for recent sessions: empty when unset so all workspaces match.
    package func sessionsDirectory(for configuration: NexusAgentConfiguration) -> String {
        let configured = configuration.workingDirectory.trimmingCharacters(in: .whitespaces)
        guard !configured.isEmpty else { return "" }
        let expanded = NexusAgentSupport.botDirectory(configured: configured, home: environment.home)
        return environment.fileExists(expanded) ? expanded : ""
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
            if done { currentToolCalls += 1 }
            if let replyID, let idx = messages.firstIndex(where: { $0.id == replyID }) {
                messages[idx].toolCalls = currentToolCalls
            }
        case .approval(let req):
            activity = "Using \(req.toolName)…"
            currentToolCalls += 1
            if let replyID, let idx = messages.firstIndex(where: { $0.id == replyID }) {
                messages[idx].approvalRequest = req
                messages[idx].toolCalls = currentToolCalls
            } else {
                let msg = NexusAgentChatMessage(role: .agent, text: "", toolCalls: currentToolCalls, approvalRequest: req)
                messages.append(msg)
                replyID = msg.id
            }
        case .finished(let status, let response, let error, let id, let metrics):
            activity = nil
            if let id { conversationID = id }
            if let response, currentReplyText.isEmpty { appendToReply(response) }
            if let replyID, let idx = messages.firstIndex(where: { $0.id == replyID }) {
                if let metrics {
                    messages[idx].durationMs = metrics.durationMs
                    messages[idx].inputTokens = metrics.inputTokens
                    messages[idx].outputTokens = metrics.outputTokens
                    messages[idx].cachedTokens = metrics.cachedTokens
                    messages[idx].numTurns = metrics.numTurns
                    messages[idx].totalCostUSD = metrics.totalCostUSD
                }
                messages[idx].toolCalls = currentToolCalls
                messages[idx].stopReason = status
            }
            if let error {
                reportedError = true
                messages.append(NexusAgentChatMessage(role: .agent, text: error, isError: true))
            }
        }
    }

    /// Resolves an interactive tool execution approval request.
    package func decideApproval(messageID: UUID, decision: NexusAgentApprovalRequest.Status) {
        guard let idx = messages.firstIndex(where: { $0.id == messageID }) else { return }
        messages[idx].approvalRequest?.status = decision
    }

    private func agentDidExit(_ status: Int32, turn current: Int) {
        guard current == turn else { return }
        if let rest = buffer.finish() { handle(rest) }
        running = nil
        isRunning = false
        activity = nil
        elapsedTimer?.invalidate()
        elapsedTimer = nil
        elapsedSeconds = 0
        let completedReply = currentReplyText
        let hadError = reportedError || (status != 0 && completedReply.isEmpty)
        if stoppedByUser {
            if currentReplyText.isEmpty { replace(reply: strings.replyStopped, isError: false) }
        } else if currentReplyText.isEmpty {
            if reportedError {
                // agy said what went wrong in a bubble of its own.
                removeReply()
                lastFailedPrompt = messages.last(where: { $0.role == .user })?.text
            } else if status != 0 {
                let detail = ([strings.agentFailed] + noise).joined(separator: "\n")
                replace(reply: detail, isError: true)
                lastFailedPrompt = messages.last(where: { $0.role == .user })?.text
            } else {
                replace(reply: strings.emptyReply, isError: false)
                NSSound(named: "Tink")?.play()
            }
        } else {
            if status != 0 || reportedError {
                lastFailedPrompt = messages.last(where: { $0.role == .user })?.text
            } else {
                NSSound(named: "Tink")?.play()
            }
        }
        onTurnFinished?(completedReply, hadError)
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
