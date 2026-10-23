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
    /// How full the context window was after this reply's latest step.
    public var contextUsage: NexusAgentContextUsage?
    /// Reasoning tokens the model reported for this reply.
    public var thinkingTokens: Int?
    /// How long the model spent reasoning before it answered.
    public var thinkingDurationMs: Int?

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
        approvalRequest: NexusAgentApprovalRequest? = nil,
        contextUsage: NexusAgentContextUsage? = nil,
        thinkingTokens: Int? = nil,
        thinkingDurationMs: Int? = nil
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
        self.contextUsage = contextUsage
        self.thinkingTokens = thinkingTokens
        self.thinkingDurationMs = thinkingDurationMs
    }
}

/// A running agent turn, as the session can stop it and, for a turn that
/// reads its input as stream-json, write to it.
public struct NexusAgentRunningAgent {
    public var terminate: () -> Void
    /// Writes to the agent's standard input; nil when it has none open.
    public var sendInput: ((Data) -> Void)?
    /// Ends the agent's standard input. Claude Code reading stream-json
    /// waits for more until it ends, so the turn's end closes it.
    public var closeInput: (() -> Void)?

    public init(terminate: @escaping () -> Void,
                sendInput: ((Data) -> Void)? = nil,
                closeInput: (() -> Void)? = nil) {
        self.terminate = terminate
        self.sendInput = sendInput
        self.closeInput = closeInput
    }
}

/// The Quick Prompt's conversation: each turn runs `agy -p` with streamed
/// JSON and continues the conversation agy named on the first one, so the
/// agent keeps the context until New chat.
@MainActor
public final class NexusAgentQuickPromptSession: ObservableObject {
    @Published public var messages: [NexusAgentChatMessage] = []
    @Published public private(set) var isRunning = false
    /// True while at least one tool approval card in the conversation is awaiting a decision.
    @Published public private(set) var hasPendingApproval = false
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
    /// The drawer row whose name is open for editing (Rename…), if any. Kept
    /// here for the same reason as `isEditingModel`: Esc closes it first.
    @Published public var renamingSessionID: String?
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
    /// When this turn's first thought arrived, for the "Thought for" timer.
    private var thinkingStartedAt: Date?
    /// Slash commands the CLI last reported; merged with the built-ins.
    @Published public private(set) var cliSlashCommands: [String] = []
    /// Every `/` command the composer offers.
    public var slashCommands: [NexusAgentSlashCommand] {
        NexusAgentSlashCommand.merged(cli: cliSlashCommands)
    }
    /// The commands that match the draft, empty unless it is a lone `/word`.
    public var matchingSlashCommands: [NexusAgentSlashCommand] {
        NexusAgentSlashCommand.matching(draft, in: slashCommands)
    }
    /// Files and screenshots that go with the next turn. They are handed to
    /// the agent when the turn starts, and the list is empty again then.
    @Published public var attachments: [NexusAgentAttachment] = []
    /// The next turn continues a copy of the open conversation instead of
    /// the conversation itself (Claude's `--fork-session`). Set by Fork,
    /// cleared when that turn starts.
    @Published public var forkNextTurn = false
    /// A prompt sent while a turn was still running. It goes as the next
    /// turn once this one ends cleanly; a turn that is stopped or fails
    /// leaves it here, on show, for the user to send or drop. A second
    /// prompt queued meanwhile is added below the first, after a blank
    /// line, so nothing typed is lost (`queue`).
    @Published public var queuedPrompt: String?
    /// The working tree as it was before the last turn, when the chat runs
    /// in a git repository (`NexusAgentSupport.gitCheckpoint`), and the
    /// folder it was taken in. Undo Turn puts the files back from it.
    @Published public private(set) var undoCheckpoint: String?
    private var undoCheckpointDirectory: String?
    /// Takes the working tree's checkpoint before a turn, and puts it back
    /// on Undo Turn. The live ones run git; a test can put its own here.
    public var takeCheckpoint: (String) -> String? = { directory in
        guard NexusAgentSupport.isGitRepo(at: URL(fileURLWithPath: directory)) else { return nil }
        return NexusAgentSupport.gitCheckpoint(in: directory)
    }
    public var restoreCheckpoint: (String, String) -> Bool = { checkpoint, directory in
        NexusAgentSupport.restoreGitCheckpoint(checkpoint, in: directory)
    }
    /// The settings and program the last turn ran with: a queued prompt
    /// goes with the same ones.
    private var lastTurnConfiguration: NexusAgentConfiguration?
    private var lastTurnAgentPath: String?
    /// The drawer's sessions as the provider listed them, before the
    /// user's pins and names (`sessionPreferences`) are applied.
    private var listedSessions: [NexusAgentSessionSummary] = []
    /// Pins and renamed titles of the drawer's sessions. The host keeps
    /// them; they are read each time, never kept here.
    public var sessionPreferences: NexusAgentSessionPreferences { host.sessionPreferences }
    /// The working folder's files for `@` mentions, read once per folder.
    @Published public private(set) var workspaceFiles: [String] = []
    private var workspaceFilesDirectory: String?
    private var workspaceFilesCache: [String: [String]] = [:]
    private var currentToolCalls = 0
    /// Tools the user allowed for the rest of the conversation: a later
    /// request for one is answered yes without asking again. Cleared by
    /// New chat and by resuming another conversation.
    public private(set) var sessionAllowedTools: Set<String> = []
    /// The `request_id`s this turn's agent is waiting on an answer to. An
    /// approval card from an earlier turn answers nothing.
    private var awaitingAnswers: Set<String> = []
    /// True once the turn's result has come and its input is closed.
    private var turnInputClosed = false
    /// True once a step of this turn has said how much context it used.
    private var turnReportedContext = false
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
        refreshSessions(configuration: configuration)
        mode = .sessions
    }

    /// Refreshes the session list using the active provider, with the
    /// user's pins and names applied (pinned ones first).
    public func refreshSessions(configuration: NexusAgentConfiguration) {
        listedSessions = environment.listSessions(sessionsDirectory(for: configuration), configuration.activeProvider,
                                                  host.hiddenClaudeSessionIDs)
        sessions = sessionPreferences.apply(to: listedSessions)
    }

    // MARK: - Pins, names and forks

    /// Pins a session to the top of the drawer, or lets it go back to its
    /// place by date. Remembered across launches.
    public func togglePin(_ summary: NexusAgentSessionSummary) {
        var preferences = host.sessionPreferences
        preferences.togglePin(summary.id)
        host.sessionPreferences = preferences
        sessions = sessionPreferences.apply(to: listedSessions)
    }

    /// Gives a session a name of the user's own in the drawer; an empty
    /// name gives it back the one the provider recorded. The provider's
    /// own files are not touched.
    public func rename(_ summary: NexusAgentSessionSummary, to title: String) {
        renamingSessionID = nil
        var preferences = host.sessionPreferences
        preferences.rename(id: summary.id, to: title.trimmingCharacters(in: .whitespacesAndNewlines))
        host.sessionPreferences = preferences
        sessions = sessionPreferences.apply(to: listedSessions)
        if conversationID == summary.id {
            let renamed = sessions.first(where: { $0.id == summary.id })?.title ?? ""
            if !renamed.isEmpty { sessionTitle = renamed }
        }
    }

    /// Opens a past session so that the next turn continues a copy of it:
    /// the original is left as it was.
    public func fork(_ summary: NexusAgentSessionSummary, configuration: NexusAgentConfiguration) {
        resume(summary, configuration: configuration)
        forkNextTurn = true
    }

    /// The open conversation's next turn goes to a copy of it. False, and
    /// nothing changed, when there is no conversation yet to copy.
    @discardableResult
    public func forkCurrentConversation() -> Bool {
        guard let conversationID, !conversationID.isEmpty else { return false }
        forkNextTurn = true
        return true
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
        if !messages.isEmpty {
            recordCurrentTranscriptState()
        }
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

    private func recordCurrentTranscriptState() {
        guard let convID = conversationID, !convID.isEmpty else { return }
        let provider = activeProvider ?? engine?.configuration.activeProvider ?? .antigravity
        guard let path = environment.transcriptPath(convID, provider),
              let attrs = try? FileManager.default.attributesOfItem(atPath: path) else { return }
        lastTranscriptModDate = attrs[.modificationDate] as? Date
        lastTranscriptSize = (attrs[.size] as? NSNumber)?.uint64Value
    }

    /// Merges transcript messages from disk with the in-memory messages so
    /// live turn metrics (cost, tokens, duration, thinking time, approvals)
    /// are never wiped by a transcript reload.
    public nonisolated static func mergingTranscriptReload(existing: [NexusAgentChatMessage],
                                                           reloaded: [NexusAgentChatMessage]) -> [NexusAgentChatMessage] {
        guard !existing.isEmpty else { return reloaded }
        guard reloaded.count > existing.count else { return existing }
        var merged = existing
        for idx in existing.count..<reloaded.count {
            merged.append(reloaded[idx])
        }
        return merged
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
                    let merged = Self.mergingTranscriptReload(existing: self.messages, reloaded: reloaded)
                    if merged != self.messages {
                        self.messages = merged
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
        sessionAllowedTools = []
        lastFailedPrompt = nil
        conversationID = summary.id
        let effectiveTitle = summary.title.isEmpty
            ? (summary.preview.split(separator: "\n").first.map(String.init) ?? "")
            : summary.title
        sessionTitle = effectiveTitle.isEmpty ? nil : effectiveTitle
        isResumed = true
        resetComposerExtras()

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
        refreshPendingApproval()
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
        lastTurnConfiguration = configuration
        lastTurnAgentPath = agentPath
        // What goes with this turn is taken now, and the composer is clear
        // of it: the next prompt starts with no attachments and no fork.
        let turnAttachments = attachments
        let fork = forkNextTurn && conversationID != nil
        attachments = []
        forkNextTurn = false
        // A command of the user's own is not agy: it has its own program,
        // found from its template, and its own way of answering.
        if configuration.activeProvider.route == .custom {
            sendCommand(NexusAgentSupport.promptWithAttachments(text, turnAttachments), configuration: configuration)
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
        let modes = TurnModes(plan: planMode, worktree: worktreeMode, attachments: turnAttachments, fork: fork)
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
        /// What was attached when the prompt was sent, and whether it was
        /// to go to a copy of the conversation.
        var attachments: [NexusAgentAttachment] = []
        var fork = false
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
        awaitingAnswers = []
        turnInputClosed = false
        turnReportedContext = false
        commandOutput = Data()
        commandErrors = Data()
        thinkingStartedAt = nil
        // The files as they are before the agent touches them, for Undo
        // Turn. Outside a git repository (or in read-only plan mode or an
        // isolated git worktree) there is none, and no undo.
        let directory = workingDirectory(for: configuration)
        undoCheckpoint = (planMode || worktreeMode) ? nil : takeCheckpoint(directory)
        undoCheckpointDirectory = undoCheckpoint == nil ? nil : directory
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
        sendQueuedPrompt(afterCleanTurn: !stoppedByUser && !failed)
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
            ollamaDefaultModel: ollamaDefaultModel,
            attachments: modes.attachments,
            forkSession: modes.fork)
        let childEnvironment = NexusAgentSupport.childEnvironment(base: environment.processEnvironment,
                                                                  home: environment.home)
        do {
            running = try environment.launchAgent(agentPath, arguments, workingDirectory(for: configuration),
                                                  childEnvironment,
                                                  { [weak self] data in self?.receive(data, turn: current) },
                                                  { [weak self] status in self?.agentDidExit(status, turn: current) })
            if NexusAgentSupport.asksOverStandardInput(configuration: Self.turnConfiguration(configuration, planMode: modes.plan),
                                                       planMode: modes.plan) {
                // The prompt was left off the command line; it goes in as
                // the first line, and the input stays open for answers.
                let prompt = NexusAgentSupport.promptWithAttachments(text, modes.attachments)
                running?.sendInput?(NexusAgentSupport.stdinUserMessage(prompt))
            }
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
        refreshPendingApproval()
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
        guard isEditingModel || renamingSessionID != nil else { return false }
        isEditingModel = false
        renamingSessionID = nil
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
            inlineEditorOpen: isEditingModel || renamingSessionID != nil,
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
        hasPendingApproval = false
        activity = nil
        replyID = nil
        conversationID = nil
        sessionAllowedTools = []
        sessionTitle = nil
        isResumed = false
        lastFailedPrompt = nil
        elapsedTimer?.invalidate()
        elapsedTimer = nil
        elapsedSeconds = 0
        messages = []
        mode = .compact
        resetComposerExtras()
    }

    /// What belonged to the conversation that was open: a prompt waiting
    /// for it, a fork of it, the undo of its last turn. Attachments are the
    /// composer's, not the conversation's, and stay.
    private func resetComposerExtras() {
        queuedPrompt = nil
        forkNextTurn = false
        undoCheckpoint = nil
        undoCheckpointDirectory = nil
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

    /// One line of the agent's output: every event in it, in order (one
    /// line of Claude's can carry several tool calls). A line with none is
    /// kept as noise, for a failure's message.
    private func handle(_ line: String) {
        let events = NexusAgentStreamEvent.parseAll(line)
        guard !events.isEmpty else {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { noise = Array((noise + [trimmed]).suffix(5)) }
            return
        }
        for event in events { handle(event: event) }
    }

    private func refreshPendingApproval() {
        let pending = isRunning && messages.contains { $0.approvalRequest?.status == .pending }
        if hasPendingApproval != pending {
            hasPendingApproval = pending
        }
    }

    private func finishThinkingIfNeeded() {
        guard let started = thinkingStartedAt, let idx = replyIndex() else { return }
        if messages[idx].thinkingDurationMs == nil {
            messages[idx].thinkingDurationMs = max(1, Int(Date().timeIntervalSince(started) * 1000))
        }
        thinkingStartedAt = nil
    }

    private func handle(event: NexusAgentStreamEvent) {
        switch event {
        case .started(let id):
            if let id { conversationID = id }
        case .text(let delta):
            activity = nil
            appendToReply(delta)
        case .tool(let name, let done):
            finishThinkingIfNeeded()
            activity = done ? nil : name
            if done { currentToolCalls += 1 }
            if let replyID, let idx = messages.firstIndex(where: { $0.id == replyID }) {
                messages[idx].toolCalls = currentToolCalls
            }
        case .approval(var req):
            finishThinkingIfNeeded()
            if let requestID = req.requestID {
                guard !turnInputClosed else { break }
                awaitingAnswers.insert(requestID)
                if sessionAllowedTools.contains(req.toolName) {
                    // Allowed for the session already: answered at once,
                    // and shown as such rather than asked again.
                    req.status = .sessionAllowed
                    answer(req, decision: .sessionAllowed)
                }
            }
            activity = strings.usingTool(req.toolName)
            currentToolCalls += 1
            if let replyID, let idx = messages.firstIndex(where: { $0.id == replyID }) {
                if let shown = messages[idx].approvalRequest, shown.status == .pending, shown.id != req.id {
                    // Parallel tool calls ask together; a card still
                    // waiting is kept, and this one gets its own bubble.
                    let nextMsg = NexusAgentChatMessage(role: .agent, text: "", toolCalls: currentToolCalls,
                                                        modelName: messages[idx].modelName, approvalRequest: req)
                    messages.append(nextMsg)
                    self.replyID = nextMsg.id
                } else {
                    messages[idx].approvalRequest = req
                    messages[idx].toolCalls = currentToolCalls
                }
            } else {
                let msg = NexusAgentChatMessage(role: .agent, text: "", toolCalls: currentToolCalls, approvalRequest: req)
                messages.append(msg)
                replyID = msg.id
            }
            refreshPendingApproval()
            guard req.status == .pending else { break }
            host.turnNeedsApproval(NexusAgentTurnNotice(
                providerName: providerName,
                text: "\(req.toolName): \(req.commandOrPath)",
                failed: false,
                endedCleanly: false
            ))
        case .toolStep(let step):
            finishThinkingIfNeeded()
            activity = step.isFinished ? nil : step.title
            guard let idx = replyIndex() else { break }
            var steps = messages[idx].toolSteps ?? []
            if let existing = steps.firstIndex(where: { $0.id == step.id }) {
                steps[existing] = step
            } else {
                steps.append(step)
                currentToolCalls += 1
                messages[idx].toolCalls = currentToolCalls
            }
            messages[idx].toolSteps = steps
        case .toolStepResult(let id, let output, let isError):
            activity = nil
            guard let idx = replyIndex(),
                  var steps = messages[idx].toolSteps,
                  let at = steps.firstIndex(where: { $0.id == id }) else { break }
            steps[at].isFinished = true
            steps[at].output = output ?? steps[at].output
            steps[at].isError = isError
            messages[idx].toolSteps = steps
        case .slashCommands(let names):
            cliSlashCommands = names
        case .thinking(let delta):
            if thinkingStartedAt == nil { thinkingStartedAt = Date() }
            guard let idx = replyIndex() else { break }
            messages[idx].thinkingText = (messages[idx].thinkingText ?? "") + delta
        case .thinkingTokens(let count):
            guard let idx = replyIndex() else { break }
            messages[idx].thinkingTokens = count
        case .contextUsage(let usage):
            turnReportedContext = true
            if let replyID, let idx = messages.firstIndex(where: { $0.id == replyID }) {
                messages[idx].contextUsage = resolvedContext(usage, at: idx)
            }
        case .finished(let status, let response, let error, let id, let metrics):
            finishThinkingIfNeeded()
            activity = nil
            // Claude Code reading stream-json waits for another message
            // until its input ends; the turn is over, so it is ended.
            turnInputClosed = true
            awaitingAnswers = []
            running?.closeInput?()
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
                    if let fromResult = metrics.contextUsage {
                        // A result summed over several steps gives only their
                        // average; the latest step's own count, when one came,
                        // is the truer one, and only the window is taken.
                        let live = messages[idx].contextUsage
                        if turnReportedContext, let live, (metrics.numTurns ?? 1) > 1 {
                            if fromResult.contextWindow > 0 {
                                messages[idx].contextUsage = live.with(contextWindow: fromResult.contextWindow)
                            }
                        } else {
                            messages[idx].contextUsage = resolvedContext(fromResult, at: idx)
                        }
                    }
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
    /// The decision is shown on the card; when the agent is waiting on it
    /// (Claude Code's `can_use_tool`), it is also sent on the agent's
    /// standard input, which lets the tool run or refuses it. Allow for
    /// Session also answers later requests for the same tool by itself.
    public func decideApproval(messageID: UUID, decision: NexusAgentApprovalRequest.Status) {
        guard decision != .pending,
              let idx = messages.firstIndex(where: { $0.id == messageID }),
              let request = messages[idx].approvalRequest,
              request.status == .pending else { return }
        messages[idx].approvalRequest?.status = decision
        if decision == .sessionAllowed { sessionAllowedTools.insert(request.toolName) }
        refreshPendingApproval()
        answer(request, decision: decision)
    }

    /// Sends a decision to the agent, once, if this turn's agent is the
    /// one waiting on it.
    private func answer(_ request: NexusAgentApprovalRequest, decision: NexusAgentApprovalRequest.Status) {
        guard let requestID = request.requestID, awaitingAnswers.remove(requestID) != nil,
              let line = NexusAgentSupport.approvalResponseJSON(for: request, decision: decision) else { return }
        running?.sendInput?(line)
    }

    private func agentDidExit(_ status: Int32, turn current: Int) {
        guard current == turn else { return }
        if let rest = buffer.finish() { handle(rest) }
        finishThinkingIfNeeded()
        running = nil
        isRunning = false
        refreshPendingApproval()
        recordCurrentTranscriptState()
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
        sendQueuedPrompt(afterCleanTurn: !stoppedByUser && !hadError && lastFailedPrompt == nil)
    }

    // MARK: - The queue

    /// Holds a prompt typed while a turn runs, to go as the next turn. A
    /// prompt already waiting is kept and this one goes under it, after a
    /// blank line: one turn carries both, and nothing typed is dropped.
    public func queue(_ prompt: String) {
        let text = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        if let waiting = queuedPrompt, !waiting.isEmpty {
            queuedPrompt = waiting + "\n\n" + text
        } else {
            queuedPrompt = text
        }
    }

    /// Puts the waiting prompt back in the composer to be changed, ahead
    /// of anything typed there since.
    public func editQueuedPrompt() {
        guard let waiting = queuedPrompt else { return }
        queuedPrompt = nil
        let typed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        draft = typed.isEmpty ? waiting : waiting + "\n\n" + typed
        focusSerial += 1
    }

    /// Drops the waiting prompt.
    public func cancelQueuedPrompt() {
        queuedPrompt = nil
    }

    /// A turn ended. When it ended cleanly the waiting prompt goes now, with
    /// the settings and program of the turn that ended. A turn the user
    /// stopped, or one that failed, leaves it waiting, on show.
    private func sendQueuedPrompt(afterCleanTurn clean: Bool) {
        guard clean, !isRunning, let waiting = queuedPrompt,
              let configuration = lastTurnConfiguration else { return }
        queuedPrompt = nil
        send(waiting, configuration: configuration, agentPath: lastTurnAgentPath)
    }

    // MARK: - Undo Turn

    /// Undo Turn is offered after a turn that ran in a git repository, once
    /// it is over.
    public var canUndoLastTurn: Bool {
        undoCheckpoint != nil && !isRunning
    }

    /// Puts the working tree's files back as they were before the last
    /// turn. The conversation is kept as it was, and `note` is added to it
    /// as the agent's: the agent still remembers that turn, so the chat
    /// does not pretend it never happened. False, with nothing changed,
    /// when there is nothing to undo or git could not restore it.
    @discardableResult
    public func undoLastTurn(note: String) -> Bool {
        guard canUndoLastTurn, let checkpoint = undoCheckpoint, let directory = undoCheckpointDirectory,
              restoreCheckpoint(checkpoint, directory) else { return false }
        undoCheckpoint = nil
        undoCheckpointDirectory = nil
        if !note.isEmpty { messages.append(NexusAgentChatMessage(role: .agent, text: note)) }
        return true
    }

    /// A step's context use with its window filled in from the model the
    /// reply runs (or the settings name) and the provider.
    private func resolvedContext(_ usage: NexusAgentContextUsage, at index: Int) -> NexusAgentContextUsage {
        let provider = engine?.configuration.activeProvider ?? activeProvider ?? .antigravity
        let model = messages[index].modelName ?? engine?.configuration.model
        return usage.resolved(model: model, provider: provider)
    }

    /// How full the context window is: the latest reply that says so, or,
    /// for a conversation none has reported on yet (the first reply still
    /// arriving, a transcript without counts), an estimate from its length.
    /// Nil for an empty conversation.
    public func currentContextUsage(provider: NexusAgentCLIProvider, model: String?) -> NexusAgentContextUsage? {
        Self.contextUsage(of: messages, provider: provider, model: model)
    }

    public nonisolated static func contextUsage(of messages: [NexusAgentChatMessage], provider: NexusAgentCLIProvider,
                                                model: String?) -> NexusAgentContextUsage? {
        guard !messages.isEmpty else { return nil }
        let model = model.flatMap { $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0 }
        // The model the settings name may say more ("opus[1m]") than the
        // one the reply recorded, so it is asked first.
        if let reply = messages.last(where: { $0.contextUsage != nil }), let reported = reply.contextUsage {
            return reported.resolved(model: model ?? reply.modelName, provider: provider)
        }
        let characters = messages.reduce(0) { $0 + $1.text.count + ($1.thinkingText?.count ?? 0) }
        return .estimate(characters: characters,
                         contextWindow: NexusAgentContextUsage.defaultContextWindow(for: model, provider: provider))
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

    /// The in-flight reply, created empty when a tool or thought comes first.
    private func replyIndex() -> Int? {
        if let replyID, let idx = messages.firstIndex(where: { $0.id == replyID }) { return idx }
        guard isRunning else { return nil }
        let msg = NexusAgentChatMessage(role: .agent, text: "")
        messages.append(msg)
        replyID = msg.id
        return messages.count - 1
    }

    private func appendToReply(_ text: String) {
        finishThinkingIfNeeded()
        guard let replyID, let index = messages.firstIndex(where: { $0.id == replyID }) else { return }
        if engine?.configuration.activeProvider.route == .opencode,
           !messages[index].text.isEmpty,
           !messages[index].text.hasSuffix("\n"),
           !text.hasPrefix("\n") {
            messages[index].text += "\n\n" + text
        } else {
            messages[index].text += text
        }
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

// MARK: - The composer: slash commands, attachments, @ mentions

/// What Return did with the composer's text (`submitDraft`).
public enum NexusAgentSubmitOutcome: Equatable {
    /// Nothing: the draft was empty.
    case nothing
    /// The draft went to the agent as a turn.
    case sent
    /// A turn is running: the draft waits for it (`queuedPrompt`).
    case queued
    /// A `/` command the chat runs itself.
    case command(NexusAgentSlashCommandResult)
}

/// What a built-in `/` command did (`runSlashCommand`).
public enum NexusAgentSlashCommandResult: Equatable {
    /// `/clear`: a new conversation.
    case newChat
    /// `/plan` and `/worktree`: the switch as it is now.
    case planMode(Bool)
    case worktreeMode(Bool)
    /// `/effort`: the effort now chosen.
    case effort(NexusAgentEffort)
    /// `/model` alone: the model's editor is open.
    case editModel
    /// `/model <name>`: that model is chosen.
    case model(String)
    /// `/cost`: the totals were added to the conversation.
    case cost(NexusAgentCostTotals)
    /// `/fork`: the next turn goes to a copy of the conversation.
    case forked
    /// `/fork` with no conversation yet: nothing to copy.
    case nothingToFork
    /// Not the chat's own (`/compact`, or a command the CLI reported, or
    /// one nobody knows): the text was sent to the agent as the prompt, or
    /// queued behind the running turn.
    case sentToAgent(String)
}

/// The tokens and cost of a conversation so far, added up over its replies.
public struct NexusAgentCostTotals: Equatable, Sendable {
    public var inputTokens: Int
    public var outputTokens: Int
    public var cachedTokens: Int
    public var costUSD: Double?
    public var replies: Int

    public init(inputTokens: Int = 0, outputTokens: Int = 0, cachedTokens: Int = 0, costUSD: Double? = nil,
                replies: Int = 0) {
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.cachedTokens = cachedTokens
        self.costUSD = costUSD
        self.replies = replies
    }

    /// The English line `/cost` adds when the app passes none of its own.
    public var englishSummary: String {
        var parts = ["Input \(inputTokens) tokens", "Output \(outputTokens) tokens", "Cached \(cachedTokens) tokens"]
        if let costUSD { parts.append(String(format: "Cost $%.4f", costUSD)) }
        return "Session so far (\(replies) \(replies == 1 ? "reply" : "replies")): " + parts.joined(separator: " · ")
    }
}

/// The `@` mention being typed in a prompt: the last word of the draft,
/// when it starts with `@`.
public enum NexusAgentMention {
    /// What follows the `@` of the draft's last word, or nil when the last
    /// word is not a mention (or the draft ends in a space, which closes it).
    public static func activeQuery(in draft: String) -> String? {
        guard let last = draft.last, !last.isWhitespace else { return nil }
        let word = draft.split(whereSeparator: \.isWhitespace).last.map(String.init) ?? ""
        guard word.hasPrefix("@") else { return nil }
        return String(word.dropFirst())
    }

    /// The draft with its mention swapped for `@path` and a space, so the
    /// next word can be typed at once. A draft with no mention is unchanged.
    public static func replacingActiveQuery(in draft: String, with path: String) -> String {
        guard let query = activeQuery(in: draft) else { return draft }
        let kept = draft.dropLast(query.count + 1)
        return kept + "@" + path + " "
    }
}

extension NexusAgentQuickPromptSession {
    /// The effort `/effort` moves to: Auto, Low, Medium, High, Max, and
    /// round again.
    public nonisolated static func nextEffort(after effort: NexusAgentEffort) -> NexusAgentEffort {
        let order: [NexusAgentEffort] = [.automatic, .low, .medium, .high, .max]
        let at = order.firstIndex(of: effort) ?? 0
        return order[(at + 1) % order.count]
    }

    /// Moves back one entry in `promptHistory` when the draft is empty or
    /// still showing the currently recalled history entry. False when the user
    /// has typed or edited their own text.
    @discardableResult
    public func recallPreviousPrompt() -> Bool {
        guard !promptHistory.isEmpty else { return false }
        let matchesCurrentHistory = historyIndex >= 0
            && historyIndex < promptHistory.count
            && draft == promptHistory[historyIndex]
        guard draft.isEmpty || matchesCurrentHistory else {
            historyIndex = -1
            return false
        }
        if historyIndex < 0 { historyIndex = promptHistory.count }
        historyIndex = max(0, historyIndex - 1)
        draft = promptHistory[historyIndex]
        return true
    }

    /// Moves forward one entry in `promptHistory` (or back to an empty draft at
    /// the end) only when `draft` still equals the recalled history entry. If
    /// the user edited the recalled text, resets `historyIndex` and returns
    /// false so Down arrow moves the text caret instead of erasing the draft.
    @discardableResult
    public func recallNextPrompt() -> Bool {
        guard historyIndex >= 0, historyIndex < promptHistory.count else {
            historyIndex = -1
            return false
        }
        guard draft == promptHistory[historyIndex] else {
            historyIndex = -1
            return false
        }
        if historyIndex < promptHistory.count - 1 {
            historyIndex += 1
            draft = promptHistory[historyIndex]
        } else {
            historyIndex = -1
            draft = ""
        }
        return true
    }

    /// The conversation's tokens and cost, added up over the replies that
    /// report them. The cost is nil when no reply reported one.
    public nonisolated static func costTotals(of messages: [NexusAgentChatMessage]) -> NexusAgentCostTotals {
        var totals = NexusAgentCostTotals()
        for message in messages where message.role == .agent {
            let reported = message.inputTokens != nil || message.outputTokens != nil || message.totalCostUSD != nil
            guard reported else { continue }
            totals.replies += 1
            totals.inputTokens += message.inputTokens ?? 0
            totals.outputTokens += message.outputTokens ?? 0
            totals.cachedTokens += message.cachedTokens ?? 0
            if let cost = message.totalCostUSD { totals.costUSD = (totals.costUSD ?? 0) + cost }
        }
        return totals
    }

    /// Return in the composer. A `/` command the chat knows is run here; any
    /// other text is a prompt, which waits behind a turn that is running and
    /// is sent otherwise. `costSummary` words `/cost`'s line, in the app's
    /// language.
    @discardableResult
    public func submitDraft(configuration: NexusAgentConfiguration, agentPath: String?,
                            costSummary: (NexusAgentCostTotals) -> String = { $0.englishSummary })
        -> NexusAgentSubmitOutcome {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return .nothing }
        let wasRunning = isRunning
        if let result = runSlashCommand(text, configuration: configuration, agentPath: agentPath,
                                        costSummary: costSummary) {
            // The agent's own command is a prompt like any other.
            if case .sentToAgent = result { return wasRunning ? .queued : .sent }
            return .command(result)
        }
        if isRunning {
            queue(text)
            draft = ""
            return .queued
        }
        send(text, configuration: configuration, agentPath: agentPath)
        return .sent
    }

    /// Runs `text` when it is a `/` command: the chat's own built-ins here,
    /// anything else (`/compact` included) sent to the agent, which knows
    /// its own. Nil when `text` is not a command, and nothing is done.
    @discardableResult
    public func runSlashCommand(_ text: String, configuration: NexusAgentConfiguration, agentPath: String?,
                                costSummary: (NexusAgentCostTotals) -> String = { $0.englishSummary })
        -> NexusAgentSlashCommandResult? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("/"), trimmed.count > 1 else { return nil }
        let parts = trimmed.dropFirst().split(maxSplits: 1, whereSeparator: \.isWhitespace)
        let name = parts.first.map { String($0).lowercased() } ?? ""
        let argument = parts.count > 1 ? String(parts[1]).trimmingCharacters(in: .whitespaces) : ""
        // A path (`/Users/me/notes.txt`) is a prompt, not a command.
        guard !name.isEmpty, !name.contains("/") else { return nil }

        func done(_ result: NexusAgentSlashCommandResult) -> NexusAgentSlashCommandResult {
            draft = ""
            historyIndex = -1
            return result
        }
        func dispatchPrompt(_ promptText: String) -> NexusAgentSlashCommandResult {
            if isRunning {
                queue(promptText)
            } else {
                send(promptText, configuration: configuration, agentPath: agentPath)
            }
            return done(.sentToAgent(promptText))
        }
        switch name {
        case "clear":
            newChat()
            return done(.newChat)
        case "plan":
            if !argument.isEmpty {
                planMode = true
                return dispatchPrompt(argument)
            }
            planMode.toggle()
            return done(.planMode(planMode))
        case "worktree":
            if !argument.isEmpty {
                worktreeMode = true
                return dispatchPrompt(argument)
            }
            worktreeMode.toggle()
            return done(.worktreeMode(worktreeMode))
        case "effort":
            let base = engine?.configuration ?? configuration
            let next = Self.nextEffort(after: base.effort)
            var changed = base
            changed.effort = next
            engine?.updateChatConfiguration(changed)
            return done(.effort(next))
        case "model":
            if argument.isEmpty {
                mode = .chat
                isEditingModel = true
                return done(.editModel)
            }
            engine?.selectModel(argument)
            return done(.model(argument))
        case "cost":
            let totals = Self.costTotals(of: messages)
            mode = .chat
            // Text only: figures on the note itself would be added in
            // again by the next `/cost`.
            messages.append(NexusAgentChatMessage(role: .agent, text: costSummary(totals)))
            return done(.cost(totals))
        case "fork":
            guard forkCurrentConversation() else { return done(.nothingToFork) }
            if !argument.isEmpty {
                return dispatchPrompt(argument)
            }
            return done(.forked)
        default:
            // The agent's own command: a turn like any prompt, or a wait
            // behind the one running.
            return dispatchPrompt(trimmed)
        }
    }

    // MARK: Attachments

    /// Adds a file for the next turn; one already attached is not added
    /// twice. False when it was already there.
    @discardableResult
    public func addAttachment(url: URL) -> Bool {
        let standardized = url.standardizedFileURL
        guard !attachments.contains(where: { $0.url.standardizedFileURL == standardized }) else { return false }
        attachments.append(NexusAgentAttachment(url: standardized))
        return true
    }

    public func removeAttachment(id: UUID) {
        attachments.removeAll { $0.id == id }
    }

    /// Attaches what the pasteboard holds: its files, or else an image
    /// (a screenshot copied to the clipboard), written to a PNG in the
    /// temporary folder. False when it held neither.
    @discardableResult
    public func pasteFromClipboard(_ pasteboard: NSPasteboard = .general) -> Bool {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: options) as? [URL], !urls.isEmpty {
            for url in urls { addAttachment(url: url) }
            return true
        }
        guard let png = Self.pngData(from: pasteboard) else { return false }
        return attachImage(data: png)
    }

    /// Attaches an image given as data (pasted, or dropped from an app that
    /// gives no file), written to a PNG in the temporary folder. False when
    /// the data is no image.
    @discardableResult
    public func attachImage(data: Data) -> Bool {
        let png: Data
        if data.starts(with: [0x89, 0x50, 0x4E, 0x47]) {
            png = data
        } else if let image = NSBitmapImageRep(data: data),
                  let converted = image.representation(using: .png, properties: [:]) {
            png = converted
        } else {
            return false
        }
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("nexus-agent-paste-\(UUID().uuidString.prefix(8)).png")
        guard (try? png.write(to: file, options: .atomic)) != nil else { return false }
        attachments.append(NexusAgentAttachment(url: file, isImage: true))
        return true
    }

    /// True when the pasteboard holds an image and no text: what ⌘V in the
    /// composer attaches instead of pasting.
    public nonisolated static func pasteboardHasImageOnly(_ pasteboard: NSPasteboard) -> Bool {
        let types = pasteboard.types ?? []
        guard !types.contains(.string) else { return false }
        return types.contains(.png) || types.contains(.tiff)
    }

    nonisolated static func pngData(from pasteboard: NSPasteboard) -> Data? {
        if let png = pasteboard.data(forType: .png) { return png }
        guard let tiff = pasteboard.data(forType: .tiff), let image = NSBitmapImageRep(data: tiff) else { return nil }
        return image.representation(using: .png, properties: [:])
    }

    // MARK: @ mentions

    /// The `@` query in the draft, when one is being typed.
    public var activeMentionQuery: String? {
        NexusAgentMention.activeQuery(in: draft)
    }

    /// The working folder's files that match the `@` being typed.
    public var matchingWorkspaceFiles: [String] {
        guard let query = activeMentionQuery else { return [] }
        return NexusAgentSupport.filterWorkspaceFiles(workspaceFiles, query: query, limit: 8)
    }

    /// Reads the working folder's files for `@` mentions, off the main
    /// thread, once per folder; a folder already read is answered at once.
    public func loadWorkspaceFiles(configuration: NexusAgentConfiguration) {
        let directory = workingDirectory(for: configuration)
        guard workspaceFilesDirectory != directory else { return }
        workspaceFilesDirectory = directory
        if let cached = workspaceFilesCache[directory] {
            workspaceFiles = cached
            return
        }
        workspaceFiles = []
        Task { [weak self] in
            let files = await Task.detached(priority: .utility) {
                NexusAgentSupport.listWorkspaceFiles(in: directory, limit: 5000)
            }.value
            guard let self else { return }
            self.workspaceFilesCache[directory] = files
            if self.workspaceFilesDirectory == directory { self.workspaceFiles = files }
        }
    }

    /// Puts the chosen file in place of the `@` being typed.
    public func completeMention(with path: String) {
        draft = NexusAgentMention.replacingActiveQuery(in: draft, with: path)
    }

    /// Puts the chosen command in the composer: `/name ` ready for an
    /// argument when it takes one, else `/name`, to run on Return.
    public func completeSlashCommand(_ command: NexusAgentSlashCommand) {
        draft = "/" + command.name + (command.argumentHint == nil ? "" : " ")
    }
}
