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
// Shared by the standalone Vitruvian Code app and the Code feature of the
// Vitruvian desktop app. Written for Vitruvian and released under MIT by its
// copyright holder on 2026-10-09 (apps/desktop/vitruvian-atrium/UPSTREAM.md).

import Foundation

/// What the shared Vitruvian Code code asks the app it runs in.
@MainActor
public protocol VitruvianCodeHost: AnyObject {
    /// The bot folder as the user configured it; empty means the standard one.
    var configuredBotDirectory: String { get }
    /// Whether the bot starts with the app.
    var startsBotAtLaunch: Bool { get }
    /// Plan mode, remembered between launches.
    var planMode: Bool { get set }
    /// Claude sessions the user archived here.
    var hiddenClaudeSessionIDs: [String] { get set }
    /// The provider the user last chose, by id; nil if they never chose.
    var chosenProviderID: UUID? { get set }
    /// The model the user last chose for each provider, keyed by provider id.
    var chosenModels: [UUID: String] { get set }
    /// Providers beyond the built-in three: the user's own, and built-in
    /// ones whose command they edited.
    var savedProviders: [VitruvianCodeCLIProvider] { get set }
    /// Prompts the user sent before, oldest first, for the up and down
    /// arrows. The session hands over at most the twenty most recent.
    var promptHistory: [String] { get set }
    /// Worktree mode, remembered between launches.
    var worktreeMode: Bool { get set }
    /// Whether the conversation's timeline sits on the left edge rather
    /// than the right, remembered between launches.
    var timelineOnLeft: Bool { get set }
    /// Sessions the user pinned or renamed in the drawer, remembered
    /// between launches. Defaults to nothing kept.
    var sessionPreferences: VitruvianCodeSessionPreferences { get set }
    /// Approval mode and plan switch saved per conversation ID (`"<mode>"` or `"<mode>|plan"`).
    var chatModes: [String: String] { get set }
    /// Per-conversation connection override (`AgentConnectionKind.rawValue`) keyed by conversation ID.
    var chatConnections: [String: String] { get set }
    /// User-facing text, in the app's language right now.
    var strings: VitruvianCodeHostStrings { get }
    /// A turn paused for the user to approve a tool.
    func turnNeedsApproval(_ notice: VitruvianCodeTurnNotice)
    /// A turn ended. `isChatVisible` is false when the user cannot see it.
    func turnFinished(_ notice: VitruvianCodeTurnNotice, isChatVisible: Bool)
}

public extension VitruvianCodeHost {
    var chosenModels: [UUID: String] {
        get { [:] }
        set {}
    }

    var sessionPreferences: VitruvianCodeSessionPreferences {
        get { VitruvianCodeSessionPreferences() }
        set {}
    }

    var chatModes: [String: String] {
        get { [:] }
        set {}
    }

    var chatConnections: [String: String] {
        get { [:] }
        set {}
    }
}

/// The text the engine and the chat session show a user. The defaults are
/// the English text; an app with translations passes its own.
///
/// Text that wraps a name (a tool, a provider, a session title) is kept as
/// the pieces around it, so every field is plain text a translation can
/// replace; the functions below put the pieces back together.
public struct VitruvianCodeHostStrings: Sendable {
    /// The title of a session that has none.
    public var untitledSession: String
    /// agy is not installed. Said only of agy, which it names: for any
    /// other program see `missingProgram(of:)`.
    public var missingAgent: String
    /// Follows a registry agent's name when its installed copy is gone.
    public var registryAgentNotInstalledSuffix: String
    /// The Claude provider is set to "Claude ACP" and its adapter is not installed.
    public var claudeAdapterNotInstalled: String
    /// The agent's CLI could not start, or stopped with an error and no reply.
    public var agentFailed: String
    /// The user stopped a reply before any of it arrived.
    public var replyStopped: String
    /// The turn ended well with nothing to show.
    public var emptyReply: String
    /// What the provider is called when no engine is there to name it.
    public var fallbackProviderName: String
    /// The line a resumed session opens with when its transcript cannot be
    /// read: prefix, title, `resumedAfterTitle`, the step count if any,
    /// `resumedBeforeProvider`, the provider, `resumedSuffix`.
    public var resumedPrefix: String
    public var resumedAfterTitle: String
    public var resumedStepsPrefix: String
    public var resumedStepsSuffix: String
    public var resumedBeforeProvider: String
    public var resumedSuffix: String
    /// Around the name of the tool that is waiting for approval.
    public var usingToolPrefix: String
    public var usingToolSuffix: String
    /// After the provider's name, in the title of a notice about a turn.
    public var approvalRequiredTitleSuffix: String
    public var failedTitleSuffix: String
    public var doneTitleSuffix: String
    /// Why the bot could not be started, or settings saved: one line per
    /// `VitruvianCodeEngine.Problem`, for an app that has only a log to say it in.
    public var problemMissingToken: String
    public var problemMissingBot: String
    public var problemMissingNode: String
    public var problemStartFailed: String
    public var problemSaveFailed: String
    /// A provider's own command that could not give a reply. The template
    /// follows `invalidCommandTemplatePrefix`; the program's name goes
    /// between the two `commandNotFound` pieces; the exit status follows
    /// `commandExitedPrefix`.
    public var invalidCommandTemplatePrefix: String
    public var commandNotFoundPrefix: String
    public var commandNotFoundSuffix: String
    public var commandExitedPrefix: String
    /// The command ran to its end and printed nothing.
    public var commandNoOutput: String
    /// The menu item that deletes a conversation.
    public var deleteSession: String
    /// Creating an isolated git worktree for a chat failed.
    public var worktreeCreationFailed: String
    /// Starting a fresh session in a worktree drops earlier conversation context.
    public var worktreeFreshSessionNotice: String
    /// A chat switched to another agent: it starts a new session and gets a summary of the chat.
    public var agentSwitchHandoffNotice: String
    /// Updating a live session config option failed.
    public var configOptionUpdateFailed: String
    /// Live session config options require an active connection.
    public var configOptionUnavailable: String
    /// An `@`-mentioned file path resolved outside the working directory and was omitted.
    public var mentionOutsideWorkspaceFormat: String
    /// Shown on a live turn interrupted mid-turn by a connection/process exit.
    public var turnInterrupted: String
    /// Shown when a live connection locks after repeated consecutive start failures.
    public var connectionLockedFormat: String
    /// A scheduled run with no window needed an approval or an answer. It
    /// was denied and the run failed. The body holds the task's name at `%@`
    /// and nothing else of the task.
    public var automationNeedsYouTitle: String
    public var automationNeedsYouBodyFormat: String

    public init(untitledSession: String = "Untitled",
                 missingAgent: String = "The Antigravity CLI (agy) was not found.",
                 registryAgentNotInstalledSuffix: String = " is not installed. Add it again in Settings, under Providers.",
                 claudeAdapterNotInstalled: String = "The Claude ACP adapter is not installed. Choose Claude ACP for Claude Code in Settings, under Providers, to install it.",
                 agentFailed: String = "The agent stopped with an error.",
                 replyStopped: String = "Reply stopped.",
                 emptyReply: String = "The agent returned no reply.",
                 fallbackProviderName: String = "Agent",
                 resumedPrefix: String = "Resumed “",
                 resumedAfterTitle: String = "”",
                 resumedStepsPrefix: String = " (",
                 resumedStepsSuffix: String = " steps)",
                 resumedBeforeProvider: String = ". ",
                 resumedSuffix: String = " remembers earlier turns — send a message to continue.",
                 usingToolPrefix: String = "Using ",
                 usingToolSuffix: String = "…",
                 approvalRequiredTitleSuffix: String = " — Approval Required",
                 failedTitleSuffix: String = " — Failed",
                 doneTitleSuffix: String = " — Done",
                 problemMissingToken: String = "Add your Telegram bot token in Settings before starting the bot.",
                 problemMissingBot: String = "The bot is not installed: bot-engine was not found in the app bundle.",
                 problemMissingNode: String = "Node.js was not found. Install Node, then start the bot again.",
                 problemStartFailed: String = "The bot could not be started.",
                 problemSaveFailed: String = "The settings could not be saved.",
                 invalidCommandTemplatePrefix: String = "Invalid command template: ",
                 commandNotFoundPrefix: String = "Could not find '",
                 commandNotFoundSuffix: String = "' in PATH. Is it installed?",
                 commandExitedPrefix: String = "Process exited with code ",
                 commandNoOutput: String = "No output from provider",
                 deleteSession: String = "Delete",
                 worktreeCreationFailed: String = "Could not create a git worktree for this chat.",
                 worktreeFreshSessionNotice: String = "Starting a new session. The agent won’t remember earlier messages in this chat.",
                 agentSwitchHandoffNotice: String = "Starting a new session with this agent. It gets a summary of this chat so far.",
                 configOptionUpdateFailed: String = "Could not update setting.",
                 configOptionUnavailable: String = "Send a message to reconnect before changing settings.",
                 mentionOutsideWorkspaceFormat: String = "Skipped %@: outside the working folder.",
                 turnInterrupted: String = "Interrupted",
                 connectionLockedFormat: String = "Live connection failed %@ times in a row and is locked for this chat. Start a new chat or use the command line.",
                 automationNeedsYouTitle: String = "Automation needs you",
                 automationNeedsYouBodyFormat: String = "%@ stopped because it needed an approval or an answer. Nothing was approved, so the run failed.") {
        self.untitledSession = untitledSession
        self.missingAgent = missingAgent
        self.registryAgentNotInstalledSuffix = registryAgentNotInstalledSuffix
        self.claudeAdapterNotInstalled = claudeAdapterNotInstalled
        self.agentFailed = agentFailed
        self.replyStopped = replyStopped
        self.emptyReply = emptyReply
        self.fallbackProviderName = fallbackProviderName
        self.resumedPrefix = resumedPrefix
        self.resumedAfterTitle = resumedAfterTitle
        self.resumedStepsPrefix = resumedStepsPrefix
        self.resumedStepsSuffix = resumedStepsSuffix
        self.resumedBeforeProvider = resumedBeforeProvider
        self.resumedSuffix = resumedSuffix
        self.usingToolPrefix = usingToolPrefix
        self.usingToolSuffix = usingToolSuffix
        self.approvalRequiredTitleSuffix = approvalRequiredTitleSuffix
        self.failedTitleSuffix = failedTitleSuffix
        self.doneTitleSuffix = doneTitleSuffix
        self.problemMissingToken = problemMissingToken
        self.problemMissingBot = problemMissingBot
        self.problemMissingNode = problemMissingNode
        self.problemStartFailed = problemStartFailed
        self.problemSaveFailed = problemSaveFailed
        self.invalidCommandTemplatePrefix = invalidCommandTemplatePrefix
        self.commandNotFoundPrefix = commandNotFoundPrefix
        self.commandNotFoundSuffix = commandNotFoundSuffix
        self.commandExitedPrefix = commandExitedPrefix
        self.commandNoOutput = commandNoOutput
        self.deleteSession = deleteSession
        self.worktreeCreationFailed = worktreeCreationFailed
        self.worktreeFreshSessionNotice = worktreeFreshSessionNotice
        self.agentSwitchHandoffNotice = agentSwitchHandoffNotice
        self.configOptionUpdateFailed = configOptionUpdateFailed
        self.configOptionUnavailable = configOptionUnavailable
        self.mentionOutsideWorkspaceFormat = mentionOutsideWorkspaceFormat
        self.turnInterrupted = turnInterrupted
        self.connectionLockedFormat = connectionLockedFormat
        self.automationNeedsYouTitle = automationNeedsYouTitle
        self.automationNeedsYouBodyFormat = automationNeedsYouBodyFormat
    }

    public func invalidCommandTemplate(_ template: String) -> String {
        "\(invalidCommandTemplatePrefix)\(template)"
    }

    public func commandNotFound(_ program: String) -> String {
        "\(commandNotFoundPrefix)\(program)\(commandNotFoundSuffix)"
    }

    /// What to say when `provider`'s program is not installed, naming the
    /// program that was looked for. agy has a sentence of its own, which
    /// an app may have translated. Any other program gets the sentence a
    /// missing command gets, around its name: `claude`, `ollama`, `opencode`, or the
    /// first word of a command of the user's own. That word may have the
    /// model in it (`{model} run {prompt}`), so the model in use is passed
    /// and filled in, as the chat does when it runs the command; with none
    /// passed the stand-in model is named, which is what would be run.
    public func missingProgram(of provider: VitruvianCodeCLIProvider, model: String = "") -> String {
        switch provider.route {
        case .antigravity:
            return missingAgent
        case .claude where provider.connection == .claudeACP:
            return claudeAdapterNotInstalled
        case .claude, .ollama, .opencode:
            return commandNotFound(provider.executableName)
        case .custom:
            return commandNotFound(
                VitruvianCodeSupport.programName(template: provider.commandTemplate, model: model) ?? "")
        case .registry:
            return provider.name + registryAgentNotInstalledSuffix
        }
    }

    public func commandExited(status: Int32) -> String {
        "\(commandExitedPrefix)\(status)"
    }

    /// The opening line of a resumed session; the step count is left out
    /// when there is none.
    public func resumedSession(title: String, steps: Int, provider: String) -> String {
        let stepCount = steps > 0 ? "\(resumedStepsPrefix)\(steps)\(resumedStepsSuffix)" : ""
        return "\(resumedPrefix)\(title)\(resumedAfterTitle)\(stepCount)\(resumedBeforeProvider)\(provider)\(resumedSuffix)"
    }

    public func usingTool(_ name: String) -> String {
        "\(usingToolPrefix)\(name)\(usingToolSuffix)"
    }

    public func approvalRequiredTitle(provider: String) -> String {
        "\(provider)\(approvalRequiredTitleSuffix)"
    }

    public func failedTitle(provider: String) -> String {
        "\(provider)\(failedTitleSuffix)"
    }

    public func doneTitle(provider: String) -> String {
        "\(provider)\(doneTitleSuffix)"
    }

    public func mentionOutsideWorkspace(_ path: String) -> String {
        if let range = mentionOutsideWorkspaceFormat.range(of: "%@") {
            return mentionOutsideWorkspaceFormat.replacingCharacters(in: range, with: path)
        }
        return "\(mentionOutsideWorkspaceFormat) \(path)"
    }

    /// The notification for a scheduled run that needed the user: only the
    /// task's name is in it.
    public func automationNeedsYou(taskName: String) -> (title: String, body: String) {
        let body: String
        if let range = automationNeedsYouBodyFormat.range(of: "%@") {
            body = automationNeedsYouBodyFormat.replacingCharacters(in: range, with: taskName)
        } else {
            body = "\(taskName): \(automationNeedsYouBodyFormat)"
        }
        return (automationNeedsYouTitle, body)
    }

    public func connectionLocked(count: Int) -> String {
        if let range = connectionLockedFormat.range(of: "%@") {
            return connectionLockedFormat.replacingCharacters(in: range, with: "\(count)")
        }
        return "\(connectionLockedFormat) (\(count))"
    }
}

/// What the session knows about a turn at the moment it tells the app.
public struct VitruvianCodeTurnNotice: Sendable {
    /// The CLI that ran the turn, as the user knows it.
    public var providerName: String
    /// For a turn that ended, the whole reply. For one waiting on approval,
    /// the tool and what it wants to run.
    public var text: String
    /// The agent reported an error, or stopped badly with no reply.
    public var failed: Bool
    /// The turn ran to its own end with nothing wrong: not stopped by the
    /// user, no error, a clean exit. Narrower than `!failed`, which also
    /// covers a stopped turn and a bad exit after a reply.
    public var endedCleanly: Bool
    /// For a failed turn, what went wrong, in the words of the error
    /// bubble the chat shows; nil when the turn has none, as when the user
    /// stopped it before anything arrived. `text` never holds this: it is
    /// the reply, which a failed turn may not have. An app that tells the
    /// user why a turn failed reads it; one that does not can ignore it.
    public var failureDetail: String?

    public init(providerName: String, text: String, failed: Bool, endedCleanly: Bool,
                failureDetail: String? = nil) {
        self.providerName = providerName
        self.text = text
        self.failed = failed
        self.endedCleanly = endedCleanly
        self.failureDetail = failureDetail
    }

    /// `failureDetail` on one line, for a place that has only one: its
    /// lines that are not blank, each without the space around it, joined
    /// by single spaces. Nil when there are no words. All of it is kept,
    /// because the first line alone is often the general "stopped with an
    /// error" and the program's own complaint comes after it; the app cuts
    /// the line to the length it has room for.
    public var failureSummary: String? {
        let lines = (failureDetail ?? "").components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return lines.isEmpty ? nil : lines.joined(separator: " ")
    }
}
