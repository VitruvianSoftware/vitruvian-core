// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import Foundation

/// What the shared Nexus Agent code asks the app it runs in.
@MainActor
package protocol NexusAgentHost: AnyObject {
    /// The bot folder as the user configured it; empty means the standard one.
    var configuredBotDirectory: String { get }
    /// Whether the bot starts with the app.
    var startsBotAtLaunch: Bool { get }
    /// Plan mode, remembered between launches.
    var planMode: Bool { get set }
    /// Claude sessions the user archived here.
    var hiddenClaudeSessionIDs: [String] { get set }
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
package struct NexusAgentHostStrings: Sendable {
    /// The title of a session that has none.
    package var untitledSession: String
    /// The agent's CLI is not installed.
    package var missingAgent: String
    /// The agent's CLI could not start, or stopped with an error and no reply.
    package var agentFailed: String
    /// The user stopped a reply before any of it arrived.
    package var replyStopped: String
    /// The turn ended well with nothing to show.
    package var emptyReply: String
    /// What the provider is called when no engine is there to name it.
    package var fallbackProviderName: String
    /// The line a resumed session opens with when its transcript cannot be
    /// read: prefix, title, `resumedAfterTitle`, the step count if any,
    /// `resumedBeforeProvider`, the provider, `resumedSuffix`.
    package var resumedPrefix: String
    package var resumedAfterTitle: String
    package var resumedStepsPrefix: String
    package var resumedStepsSuffix: String
    package var resumedBeforeProvider: String
    package var resumedSuffix: String
    /// Around the name of the tool that is waiting for approval.
    package var usingToolPrefix: String
    package var usingToolSuffix: String
    /// After the provider's name, in the title of a notice about a turn.
    package var approvalRequiredTitleSuffix: String
    package var failedTitleSuffix: String
    package var doneTitleSuffix: String

    package init(untitledSession: String = "Untitled",
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
                 doneTitleSuffix: String = " — Done") {
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
    }

    /// The opening line of a resumed session; the step count is left out
    /// when there is none.
    package func resumedSession(title: String, steps: Int, provider: String) -> String {
        let stepCount = steps > 0 ? "\(resumedStepsPrefix)\(steps)\(resumedStepsSuffix)" : ""
        return "\(resumedPrefix)\(title)\(resumedAfterTitle)\(stepCount)\(resumedBeforeProvider)\(provider)\(resumedSuffix)"
    }

    package func usingTool(_ name: String) -> String {
        "\(usingToolPrefix)\(name)\(usingToolSuffix)"
    }

    package func approvalRequiredTitle(provider: String) -> String {
        "\(provider)\(approvalRequiredTitleSuffix)"
    }

    package func failedTitle(provider: String) -> String {
        "\(provider)\(failedTitleSuffix)"
    }

    package func doneTitle(provider: String) -> String {
        "\(provider)\(doneTitleSuffix)"
    }
}

/// What the session knows about a turn at the moment it tells the app.
package struct NexusAgentTurnNotice: Sendable {
    /// The CLI that ran the turn, as the user knows it.
    package var providerName: String
    /// For a turn that ended, the whole reply. For one waiting on approval,
    /// the tool and what it wants to run.
    package var text: String
    /// The agent reported an error, or stopped badly with no reply.
    package var failed: Bool
    /// The turn ran to its own end with nothing wrong: not stopped by the
    /// user, no error, a clean exit. Narrower than `!failed`, which also
    /// covers a stopped turn and a bad exit after a reply.
    package var endedCleanly: Bool

    package init(providerName: String, text: String, failed: Bool, endedCleanly: Bool) {
        self.providerName = providerName
        self.text = text
        self.failed = failed
        self.endedCleanly = endedCleanly
    }
}
