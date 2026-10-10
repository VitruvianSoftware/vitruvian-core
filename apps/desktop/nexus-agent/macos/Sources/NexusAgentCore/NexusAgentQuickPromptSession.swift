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
//
// Shared by the standalone Nexus Agent app and the Nexus Agent feature of the
// Vitruvian desktop app. Written for Vitruvian and released under MIT by its
// copyright holder on 2026-10-09 (apps/desktop/vitruvian/UPSTREAM.md).

import AppKit
import Foundation

/// One bubble in the Quick Prompt.
public struct NexusAgentChatMessage: Identifiable, Equatable {
    public enum Role: Equatable { case user, agent }

    public let id: UUID
    public let role: Role
    public var text: String
    public var isError: Bool
    public var durationMs: Int?
    public var inputTokens: Int?
    public var outputTokens: Int?
    public var cachedTokens: Int?
    public var numTurns: Int?
    public var toolCalls: Int?
    public var modelName: String?
    public var stopReason: String?
    public var toolSteps: [NexusAgentToolStep]?
    public var thinkingText: String?
    public var totalCostUSD: Double?
    public var approvalRequest: NexusAgentApprovalRequest?

    public init(
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
public struct NexusAgentRunningAgent {
    public var terminate: () -> Void

    public init(terminate: @escaping () -> Void) {
        self.terminate = terminate
    }
}

/// The Quick Prompt's conversation: each turn runs `agy -p` with streamed
/// JSON and continues the conversation agy named on the first one, so the
/// agent keeps the context until New chat.
@MainActor
public final class NexusAgentQuickPromptSession: ObservableObject {
    @Published public var messages: [NexusAgentChatMessage] = []
    @Published public private(set) var isRunning = false
    /// The tool the agent is using right now, if any.
    @Published public private(set) var activity: String?
    @Published public private(set) var conversationID: String?
    @Published public var draft = ""
    /// Bumped when the prompt is shown, so the view puts the caret back.
    @Published public var focusSerial = 0
    /// True while the model's name is open for editing in the
    /// conversation's header. The view shows its editor exactly while this
    /// is true: it sets it on a click on the model's name, and clears it
    /// when the name is saved or the header goes. It is kept here, and not
    /// in the view, so that the window can ask what Esc means
    /// (`pressEscape`) and close the editor (`cancelInlineEditing`).
    @Published public var isEditingModel = false
    @Published public private(set) var mode: NexusAgentQuickPromptMode = .compact
    @Published public private(set) var sessions: [NexusAgentSessionSummary] = []
    /// True from the moment Clear All is asked for until its last delete
    /// is over. A second Clear All is not started meanwhile.
    @Published public private(set) var isClearingSessions = false
    @Published public var sessionFilter = ""
    /// The active session's title when resumed from the drawer.
    @Published public private(set) var sessionTitle: String?
    /// True while viewing or continuing a resumed conversation.
    @Published public private(set) var isResumed = false
    /// The last prompt that failed, allowing 1-click retry.
    @Published public var lastFailedPrompt: String?
    /// Elapsed seconds during current active generation.
    @Published public private(set) var elapsedSeconds: Int = 0
    /// History of sent prompts for Up/Down arrow navigation, oldest first.
    /// It starts as what the host kept, and each new prompt is handed back.
    @Published public var promptHistory: [String]
    @Published public var historyIndex: Int = -1
    /// Called when an agent turn completes, in place of telling the host
    /// directly: the engine sets it, to add whether its chat is on screen.
    var onTurnFinished: ((NexusAgentTurnNotice) -> Void)?
    /// Turns run with `--mode plan` (read-only) while on. Remembered.
    @Published public var planMode: Bool {
        didSet { host.planMode = planMode }
    }
    /// Turns run with `-w` (isolated git worktree) while on. Remembered.
    @Published public var worktreeMode: Bool {
        didSet { host.worktreeMode = worktreeMode }
    }
    /// How many prompts the host is given to keep. The running chat holds
    /// every prompt sent since it opened; only what is saved is cut.
    public static let savedPromptHistoryLimit = 20

    @Published public private(set) var activeSubagents: [NexusAgentActiveSubagent] = []
    @Published public var isFollowerActive: Bool = false
    public internal(set) weak var engine: NexusAgentEngine?
    private var followerTimer: Timer?
    private var lastTranscriptModDate: Date?
    private var lastTranscriptSize: UInt64?
    private var activeProvider: NexusAgentCLIProvider?

    private let environment: NexusAgentEngine.Environment
    /// The app's settings, text and notices. Asked each time, never kept.
    private let host: any NexusAgentHost
    private var running: NexusAgentRunningAgent?
    private var buffer = NexusAgentLineBuffer()
    private var replyID: UUID?
    private var currentToolCalls = 0
    private var elapsedTimer: Timer?
    /// Callbacks from a turn that has since been stopped or replaced are dropped.
    private var turn = 0
    private var stoppedByUser = false
    /// True from the moment a turn asks Ollama which models it has until
    /// the agent is started with the answer, or the turn is stopped.
    private var awaitingModel = false
    private var reportedError = false
    /// What the agent said went wrong this turn, as its error bubble shows
    /// it; the last one, if it said so more than once.
    private var reportedErrorText: String?
    /// Output that is not stream JSON (agy's own errors), kept for a failure.
    private var noise: [String] = []
    /// Everything a provider's own command has printed this turn, and
    /// everything it has written to standard error, kept apart.
    private var commandOutput = Data()
    private var commandErrors = Data()

    public init(environment: NexusAgentEngine.Environment, host: any NexusAgentHost) {
        self.environment = environment
        self.host = host
        self.planMode = host.planMode
        self.worktreeMode = host.worktreeMode
        self.promptHistory = host.promptHistory
    }

    /// Send is offered only for a prompt with text and no turn in flight.
    public var canSend: Bool {
        !isRunning && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public var filteredSessions: [NexusAgentSessionSummary] {
        NexusAgentSessionSummary.filter(sessions, by: sessionFilter)
    }

    /// Opens the drawer with a fresh list from the active provider, or closes it again.
    public func toggleSessions(configuration: NexusAgentConfiguration) {
        if mode == .sessions {
            mode = messages.isEmpty ? .compact : .chat
            return
        }
        sessionFilter = ""
        sessions = environment.listSessions(sessionsDirectory(for: configuration), configuration.activeProvider,
                                            host.hiddenClaudeSessionIDs)
        mode = .sessions
    }

    /// Refreshes the session list using the active provider.
    public func refreshSessions(configuration: NexusAgentConfiguration) {
        sessions = environment.listSessions(sessionsDirectory(for: configuration), configuration.activeProvider,
                                            host.hiddenClaudeSessionIDs)
    }

    /// Archives a session and reloads the drawer list. A session with no
    /// engine does the engine's work itself, with its own home and host.
    public func archive(_ summary: NexusAgentSessionSummary, configuration: NexusAgentConfiguration) {
        if let engine {
            engine.archiveSession(summary, configuration: configuration)
        } else {
            NexusAgentEngine.archiveSession(home: environment.home, id: summary.id,
                                            provider: configuration.activeProvider, host: host)
        }
        refreshSessions(configuration: configuration)
    }

    /// Unarchives a session and reloads the drawer list.
    public func unarchive(_ summary: NexusAgentSessionSummary, configuration: NexusAgentConfiguration) {
        if let engine {
            engine.unarchiveSession(summary, configuration: configuration)
        } else {
            NexusAgentEngine.unarchiveSession(home: environment.home, id: summary.id,
                                              provider: configuration.activeProvider, host: host)
        }
        refreshSessions(configuration: configuration)
    }

    /// Deletes an agy conversation for good and reloads the drawer list.
    /// Returns false, having changed nothing, for any other provider's.
    /// If it was the conversation open in the chat, the chat is new: the
    /// next prompt would otherwise try to resume one that is gone.
    @discardableResult
    public func delete(_ summary: NexusAgentSessionSummary, configuration: NexusAgentConfiguration) -> Bool {
        let deleted = NexusAgentEngine.deleteSession(id: summary.id, provider: configuration.activeProvider,
                                                     environment: environment)
        if deleted, conversationID == summary.id { newChat() }
        refreshSessions(configuration: configuration)
        return deleted
    }

    /// Deletes every agy conversation of the working folder, as the
    /// standalone app's "Clear All" does, and reloads the drawer list.
    ///
    /// The folder is the one the settings name, or home when they name
    /// none. It is used as named even if it is gone, and never widened:
    /// the drawer lists every folder's conversations when none is set,
    /// but "all" here is always one folder's.
    ///
    /// It comes back at once, before anything is deleted. The deleting is
    /// up to 200 runs of `sqlite3`, each of which can wait two seconds on
    /// an index agy has locked, so none of it is waited for on the main
    /// thread: `isClearingSessions` is true until it is over, and the list
    /// is read again then. The task it returns ends at that moment with
    /// how many went, for a caller that wants to know. Asked again while
    /// one clear is under way, it does nothing and its task gives 0.
    @discardableResult
    public func deleteAll(in configuration: NexusAgentConfiguration) -> Task<Int, Never> {
        guard !isClearingSessions else { return Task { 0 } }
        isClearingSessions = true
        let configured = configuration.workingDirectory.trimmingCharacters(in: .whitespaces)
        let directory = configured.isEmpty
            ? environment.home
            : NexusAgentSupport.botDirectory(configured: configured, home: environment.home)
        return Task { [weak self] in
            guard let environment = self?.environment else { return 0 }
            let deleted = await NexusAgentEngine.deletedSessionIDsOffMain(
                directory: directory, provider: configuration.activeProvider, environment: environment)
            guard let self else { return deleted.count }
            self.isClearingSessions = false
            // As for one conversation: the open chat is new if it went too.
            if let open = self.conversationID, deleted.contains(open) { self.newChat() }
            self.refreshSessions(configuration: configuration)
            return deleted.count
        }
    }

    /// Starts watching the transcript file for live updates while in chat mode.
    public func startTranscriptFollower(provider: NexusAgentCLIProvider? = nil) {
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
    public func stopTranscriptFollower() {
        followerTimer?.invalidate()
        followerTimer = nil
        isFollowerActive = false
        lastTranscriptModDate = nil
        lastTranscriptSize = nil
    }

    /// Checks the transcript file for updates and refreshes messages and active subagents.
    public func checkTranscriptUpdates() {
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
                let parsedSubagents = NexusAgentEngine.parseActiveSubagents(from: raw)
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
    public func resume(_ summary: NexusAgentSessionSummary, configuration: NexusAgentConfiguration = NexusAgentConfiguration()) {
        // A turn still waiting for its model is dropped, not ended.
        awaitingModel = false
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
            restored.append(NexusAgentChatMessage(
                role: .agent,
                text: strings.resumedSession(title: title, steps: summary.steps,
                                             provider: configuration.activeProvider.name)
            ))
            messages = restored
        }
        mode = .chat
        startTranscriptFollower(provider: configuration.activeProvider)
    }

    /// The agy flags for this turn: plan mode overrides the bot's approval mode.
    public func turnConfiguration(_ configuration: NexusAgentConfiguration) -> NexusAgentConfiguration {
        Self.turnConfiguration(configuration, planMode: planMode)
    }

    /// The same rule for a plan mode taken earlier than now.
    private static func turnConfiguration(_ configuration: NexusAgentConfiguration,
                                          planMode: Bool) -> NexusAgentConfiguration {
        var turn = configuration
        if planMode { turn.approvalMode = .plan }
        return turn
    }

    private var strings: NexusAgentHostStrings { host.strings }

    /// Starts a turn with the bot's own settings. A turn that cannot start
    /// says why in the conversation.
    public func send(_ prompt: String, configuration: NexusAgentConfiguration, agentPath: String?) {
        let text = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isRunning else { return }
        draft = ""
        mode = .chat
        messages.append(NexusAgentChatMessage(role: .user, text: text))
        // A prompt the history already holds, anywhere in it, is neither
        // added again nor moved to the end; a new one goes last and the
        // host is given the most recent ones to keep.
        if !promptHistory.contains(text) {
            promptHistory.append(text)
            host.promptHistory = Array(promptHistory.suffix(Self.savedPromptHistoryLimit))
        }
        historyIndex = -1
        lastFailedPrompt = nil
        // A command of the user's own is not agy: it has its own program,
        // found from its template, and its own way of answering.
        if configuration.activeProvider.route == .custom {
            sendCommand(text, configuration: configuration)
            return
        }
        guard let agentPath else {
            // Named for the provider that was to run the turn: it is
            // Claude's program that is missing when Claude is chosen.
            let reason = strings.missingProgram(of: configuration.activeProvider)
            messages.append(NexusAgentChatMessage(role: .agent, text: reason, isError: true))
            // With the chat out of sight nobody sees that bubble, so the
            // host is told as it is of any other failed turn.
            report(NexusAgentTurnNotice(providerName: providerName, text: "", failed: true, endedCleanly: false,
                                        failureDetail: reason))
            return
        }
        // Plan mode and worktree mode are the user's as they stand now, when
        // the prompt is sent. A turn that has to wait before it starts (see
        // below) runs with these, whatever is switched while it waits: a
        // prompt sent in plan mode must not start outside it.
        let modes = TurnModes(plan: planMode, worktree: worktreeMode)
        let current = beginTurn(configuration: configuration, followsTranscript: true)
        let model = configuration.model.trimmingCharacters(in: .whitespaces)
        // Whatever is run as Ollama needs a model, not the built-in provider alone.
        guard configuration.activeProvider.route == .ollama, model.isEmpty else {
            launch(text, configuration: configuration, agentPath: agentPath, modes: modes,
                   ollamaDefaultModel: NexusAgentSupport.ollamaFallbackModel, turn: current)
            return
        }
        // Ollama must be told a model and the settings name none, so it is
        // asked which ones it has. That runs a program, so the turn waits
        // for it off the main thread, already showing as running.
        awaitingModel = true
        let runProgram = environment.runProgram
        Task { [weak self] in
            let listing = await runProgram("ollama", ["list"])
            guard let self, self.awaitingModel, current == self.turn else { return }
            self.awaitingModel = false
            self.launch(text, configuration: configuration, agentPath: agentPath, modes: modes,
                        ollamaDefaultModel: NexusAgentSupport.ollamaDefaultModel(fromList: listing), turn: current)
        }
    }

    /// The two switches of the chat as they stood when a prompt was sent.
    private struct TurnModes: Sendable {
        var plan: Bool
        var worktree: Bool
    }

    /// Puts a new turn on screen as running: an empty reply to fill, the
    /// clock started. Returns the turn's number, which its callbacks carry
    /// so that those of a turn since stopped or replaced are dropped.
    private func beginTurn(configuration: NexusAgentConfiguration, followsTranscript: Bool) -> Int {
        turn += 1
        buffer = NexusAgentLineBuffer()
        noise = []
        stoppedByUser = false
        reportedError = false
        reportedErrorText = nil
        currentToolCalls = 0
        commandOutput = Data()
        commandErrors = Data()
        let model = configuration.model.trimmingCharacters(in: .whitespaces)
        let reply = NexusAgentChatMessage(role: .agent, text: "", modelName: model.isEmpty ? nil : model)
        replyID = reply.id
        messages.append(reply)
        isRunning = true
        if followsTranscript { startTranscriptFollower(provider: configuration.activeProvider) }
        activity = nil
        elapsedSeconds = 0
        elapsedTimer?.invalidate()
        elapsedTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.elapsedSeconds += 1
            }
        }
        return turn
    }

    /// One turn of a provider's own command, as the standalone app runs
    /// one. The template gives the program and its arguments, with the
    /// prompt as part of exactly one of them; the program is started
    /// directly, never through a shell. A plain command has no plan flag,
    /// so in plan mode the rules go in front of the prompt instead.
    private func sendCommand(_ text: String, configuration: NexusAgentConfiguration) {
        let template = configuration.activeProvider.commandTemplate
        guard let command = NexusAgentSupport.providerCommand(
            template: template,
            prompt: planMode ? NexusAgentSupport.planModePrompt(text) : text,
            model: configuration.model) else {
            refuse(text, saying: strings.invalidCommandTemplate(template))
            return
        }
        // A template that would take its program's name from the prompt has
        // no program (see `providerCommand`): it is refused as a program
        // that is not installed, naming the word as written. A program that
        // is looked for and not found is named as it was looked for. Either
        // way the sentence is the provider's `missingProgram`, the one a
        // settings page shows, so the two always name the same program.
        guard !command.executable.isEmpty,
              let path = NexusAgentSupport.executablePath(
                  named: command.executable,
                  pathVariable: environment.processEnvironment["PATH"] ?? "",
                  isExecutable: environment.isExecutable,
                  fileExists: environment.fileExists) else {
            refuse(text, saying: strings.missingProgram(of: configuration.activeProvider,
                                                        model: configuration.model))
            return
        }
        // A plain command keeps no transcript to follow.
        let current = beginTurn(configuration: configuration, followsTranscript: false)
        let childEnvironment = NexusAgentSupport.commandEnvironment(base: environment.processEnvironment,
                                                                    fileExists: environment.fileExists)
        do {
            running = try environment.launchCommand(
                path, command.arguments, workingDirectory(for: configuration), childEnvironment,
                { [weak self] data in self?.receiveCommand(data, isErrors: false, turn: current) },
                { [weak self] data in self?.receiveCommand(data, isErrors: true, turn: current) },
                { [weak self] status in self?.commandDidExit(status, turn: current) })
        } catch {
            isRunning = false
            elapsedTimer?.invalidate()
            elapsedTimer = nil
            // The system's own words for why, as the standalone shows them.
            let reason = error.localizedDescription
            replace(reply: reason, isError: true)
            lastFailedPrompt = text
            replyID = nil
            report(NexusAgentTurnNotice(providerName: providerName, text: "", failed: true, endedCleanly: false,
                                        failureDetail: reason))
        }
    }

    /// A command that cannot even start says why in the conversation, and
    /// leaves the prompt ready to be tried again. Whatever the reason (no
    /// such program, an empty template, a template refused because the
    /// prompt would name the program), the host is told as it is of any
    /// other failed turn, in the bubble's words: with the chat out of
    /// sight the bubble is seen by nobody.
    private func refuse(_ prompt: String, saying reason: String) {
        messages.append(NexusAgentChatMessage(role: .agent, text: reason, isError: true))
        lastFailedPrompt = prompt
        report(NexusAgentTurnNotice(providerName: providerName, text: "", failed: true, endedCleanly: false,
                                    failureDetail: reason))
    }

    private func receiveCommand(_ data: Data, isErrors: Bool, turn current: Int) {
        guard current == turn else { return }
        guard !isErrors else {
            commandErrors.append(data)
            return
        }
        commandOutput.append(data)
        // The reply grows as the command prints. A piece can end in the
        // middle of a letter; then the reply waits for the rest of it.
        if let printed = String(data: commandOutput, encoding: .utf8) {
            replace(reply: printed, isError: false)
        }
    }

    private func commandDidExit(_ status: Int32, turn current: Int) {
        guard current == turn else { return }
        running = nil
        isRunning = false
        activity = nil
        elapsedTimer?.invalidate()
        elapsedTimer = nil
        elapsedSeconds = 0
        let outcome = NexusAgentSupport.commandOutcome(output: commandOutput, errors: commandErrors, status: status)
        let printed = String(data: commandOutput, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        commandOutput = Data()
        commandErrors = Data()
        var completedReply = ""
        var failed = false
        var endedCleanly = false
        // The words of the error bubble, when the turn ends in one.
        var failureDetail: String?
        if stoppedByUser || outcome == .stopped {
            // What arrived before the stop stays, as in any other turn.
            replace(reply: printed.isEmpty ? strings.replyStopped : printed, isError: false)
            completedReply = printed
            failed = printed.isEmpty && status != 0
        } else {
            switch outcome {
            case .reply(let text):
                replace(reply: text, isError: false)
                completedReply = text
                endedCleanly = true
            case .failed(let code, let errors):
                let reason = errors.isEmpty ? strings.commandExited(status: code) : errors
                replace(reply: reason, isError: true)
                failureDetail = reason
                failed = true
            case .noOutput, .stopped:
                replace(reply: strings.commandNoOutput, isError: true)
                failureDetail = strings.commandNoOutput
                failed = true
            }
            if failed { lastFailedPrompt = messages.last(where: { $0.role == .user })?.text }
        }
        report(NexusAgentTurnNotice(providerName: providerName, text: completedReply,
                                    failed: failed, endedCleanly: endedCleanly, failureDetail: failureDetail))
        replyID = nil
    }

    /// Tells the app a turn ended.
    private func report(_ notice: NexusAgentTurnNotice) {
        if let onTurnFinished {
            onTurnFinished(notice)
        } else {
            // Built without an engine there is no window to be away from:
            // the host's in-app notice is due, its notification is not.
            host.turnFinished(notice, isChatVisible: true)
        }
    }

    /// Starts the agent for a turn `send` has already put on screen, in
    /// the modes the prompt was sent in, not the ones set by now.
    private func launch(_ text: String, configuration: NexusAgentConfiguration, agentPath: String,
                        modes: TurnModes, ollamaDefaultModel: String, turn current: Int) {
        let arguments = NexusAgentSupport.agentArguments(
            prompt: text,
            configuration: Self.turnConfiguration(configuration, planMode: modes.plan),
            conversationID: conversationID,
            planMode: modes.plan,
            worktreeMode: modes.worktree,
            ollamaDefaultModel: ollamaDefaultModel)
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
            let reason = strings.agentFailed
            replace(reply: reason, isError: true)
            replyID = nil
            // A turn that could not start is a failed turn to the host, in
            // the bubble's words: with the chat out of sight the bubble is
            // seen by nobody, and the app would otherwise say nothing.
            report(NexusAgentTurnNotice(providerName: providerName, text: "", failed: true, endedCleanly: false,
                                        failureDetail: reason))
        }
    }

    /// Ends the turn in flight; what arrived so far stays.
    public func stop() {
        guard isRunning else { return }
        stoppedByUser = true
        stopTranscriptFollower()
        elapsedTimer?.invalidate()
        elapsedTimer = nil
        running?.terminate()
        if awaitingModel {
            // The agent has not started, so nothing will report an exit:
            // the turn ends here, as a stopped one. The model's name, when
            // it arrives, finds nothing waiting for it.
            awaitingModel = false
            agentDidExit(0, turn: turn)
        }
    }

    /// Closes whatever is being edited in place in the chat: the model's
    /// name, which is the only such editor. True when one was open. The
    /// view's editor goes with `isEditingModel`; what was typed in it is
    /// not saved.
    @discardableResult
    public func cancelInlineEditing() -> Bool {
        guard isEditingModel else { return false }
        isEditingModel = false
        return true
    }

    /// Esc, pressed in a window that shows this chat. The chat's own part
    /// of the key is done here, as `NexusAgentEscapeKey` decides it: an
    /// open editor is closed, or else the reply arriving in the
    /// conversation on show is stopped. `.dismiss` comes back when there
    /// was neither, and the key is then the window's.
    ///
    /// `stoppingReply` is false for a window whose Esc never stops a reply:
    /// it closes, and the reply goes on arriving.
    public func pressEscape(stoppingReply: Bool) -> NexusAgentEscapeKey.Action {
        let action = NexusAgentEscapeKey.action(
            inlineEditorOpen: isEditingModel,
            replyToStop: stoppingReply && mode == .chat && isRunning)
        switch action {
        case .closeInlineEditor: cancelInlineEditing()
        case .stopReply: stop()
        case .dismiss: break
        }
        return action
    }

    public func newChat() {
        // A turn still waiting for its model is dropped, not ended.
        awaitingModel = false
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
    public func workingDirectory(for configuration: NexusAgentConfiguration) -> String {
        let configured = configuration.workingDirectory.trimmingCharacters(in: .whitespaces)
        guard !configured.isEmpty else { return environment.home }
        let expanded = NexusAgentSupport.botDirectory(configured: configured, home: environment.home)
        return environment.fileExists(expanded) ? expanded : environment.home
    }

    /// The folder for recent sessions: empty when unset so all workspaces match.
    public func sessionsDirectory(for configuration: NexusAgentConfiguration) -> String {
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
            activity = strings.usingTool(req.toolName)
            currentToolCalls += 1
            if let replyID, let idx = messages.firstIndex(where: { $0.id == replyID }) {
                messages[idx].approvalRequest = req
                messages[idx].toolCalls = currentToolCalls
            } else {
                let msg = NexusAgentChatMessage(role: .agent, text: "", toolCalls: currentToolCalls, approvalRequest: req)
                messages.append(msg)
                replyID = msg.id
            }
            host.turnNeedsApproval(NexusAgentTurnNotice(
                providerName: providerName,
                text: "\(req.toolName): \(req.commandOrPath)",
                failed: false,
                endedCleanly: false
            ))
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
                reportedErrorText = error
                messages.append(NexusAgentChatMessage(role: .agent, text: error, isError: true))
            }
        }
    }

    /// Resolves an interactive tool execution approval request.
    public func decideApproval(messageID: UUID, decision: NexusAgentApprovalRequest.Status) {
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
        // True on the two paths below where nothing went wrong, which is
        // when the host plays its "done" sound.
        var endedCleanly = false
        // The words of the turn's error bubble, when it has one: what agy
        // said went wrong, or below, what is said for a bad exit. A turn
        // the user stopped before anything arrived has no such bubble.
        var failureDetail = reportedErrorText
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
                failureDetail = detail
                lastFailedPrompt = messages.last(where: { $0.role == .user })?.text
            } else {
                replace(reply: strings.emptyReply, isError: false)
                endedCleanly = true
            }
        } else {
            if status != 0 || reportedError {
                lastFailedPrompt = messages.last(where: { $0.role == .user })?.text
            } else {
                endedCleanly = true
            }
        }
        report(NexusAgentTurnNotice(providerName: providerName, text: completedReply,
                                    failed: hadError, endedCleanly: endedCleanly,
                                    failureDetail: hadError ? failureDetail : nil))
        replyID = nil
    }

    /// The active provider as the engine names it; a session on its own
    /// has only the host's stand-in.
    private var providerName: String {
        engine?.configuration.activeProvider.name ?? strings.fallbackProviderName
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
