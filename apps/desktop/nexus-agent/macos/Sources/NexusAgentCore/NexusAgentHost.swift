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

import Foundation

/// What the shared Nexus Agent code asks the app it runs in.
@MainActor
public protocol NexusAgentHost: AnyObject {
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
    /// Providers beyond the built-in three: the user's own, and built-in
    /// ones whose command they edited.
    var savedProviders: [NexusAgentCLIProvider] { get set }
    /// Prompts the user sent before, oldest first, for the up and down
    /// arrows. The session hands over at most the twenty most recent.
    var promptHistory: [String] { get set }
    /// Worktree mode, remembered between launches.
    var worktreeMode: Bool { get set }
    /// User-facing text, in the app's language right now.
    var strings: NexusAgentHostStrings { get }
    /// A turn paused for the user to approve a tool.
    func turnNeedsApproval(_ notice: NexusAgentTurnNotice)
    /// A turn ended. `isChatVisible` is false when the user cannot see it.
    func turnFinished(_ notice: NexusAgentTurnNotice, isChatVisible: Bool)
}

/// The text the engine and the chat session show a user. The defaults are
/// the English text; an app with translations passes its own.
///
/// Text that wraps a name (a tool, a provider, a session title) is kept as
/// the pieces around it, so every field is plain text a translation can
/// replace; the functions below put the pieces back together.
public struct NexusAgentHostStrings: Sendable {
    /// The title of a session that has none.
    public var untitledSession: String
    /// The agent's CLI is not installed.
    public var missingAgent: String
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
    /// `NexusAgentEngine.Problem`, for an app that has only a log to say it in.
    public var problemMissingToken: String
    public var problemMissingBot: String
    public var problemMissingNode: String
    public var problemStartFailed: String
    public var problemSaveFailed: String

    public init(untitledSession: String = "Untitled",
                 missingAgent: String = "The Antigravity CLI (agy) was not found.",
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
                 problemMissingBot: String = "The bot is not installed: src/bot.js was not found in the bot folder.",
                 problemMissingNode: String = "Node.js was not found. Install Node, then start the bot again.",
                 problemStartFailed: String = "The bot could not be started.",
                 problemSaveFailed: String = "The settings could not be saved.") {
        self.untitledSession = untitledSession
        self.missingAgent = missingAgent
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
}

/// What the session knows about a turn at the moment it tells the app.
public struct NexusAgentTurnNotice: Sendable {
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

    public init(providerName: String, text: String, failed: Bool, endedCleanly: Bool) {
        self.providerName = providerName
        self.text = text
        self.failed = failed
        self.endedCleanly = endedCleanly
    }
}
