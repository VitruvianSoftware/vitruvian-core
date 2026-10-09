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

import Foundation

/// Every piece of text the chat view shows, in the app's language right now.
/// The defaults are the English text, so `NexusAgentChatStrings()` is the
/// answer of an app with no translations; an app that has some passes its
/// own for the fields it has and leaves the rest.
///
/// Text that wraps a name or a number is kept as the pieces around it, as
/// `NexusAgentHostStrings` does, so every field is plain text a translation
/// can replace. Figures and their units (`2.2s`, `1.5K`, `$0.0450`) are not
/// text and are not here.
public struct NexusAgentChatStrings: Sendable, Equatable {
    // MARK: The pill and the follow-up bar

    /// The chat's title while a session has none.
    public var quickPromptTitle: String
    /// The pill's placeholder, around the provider's first name; and that name
    /// when the provider has none.
    public var askPrefix: String
    public var askSuffix: String
    public var fallbackProviderName: String
    /// The follow-up bar's placeholder, around the same name.
    public var followUpPrefix: String
    public var followUpSuffix: String
    /// The send and stop buttons.
    public var send: String
    public var stopReply: String
    /// The round buttons beside the pill.
    public var sessionsToggle: String
    public var planModeOn: String
    public var planModeOff: String
    public var worktreeModeOn: String
    public var worktreeModeOff: String
    public var workingFolder: String
    public var switchProvider: String

    // MARK: The sessions drawer

    /// The filter field, and what the list says when it is empty.
    public var sessionsFilter: String
    public var noSessions: String
    /// A session with no title.
    public var untitledSession: String
    /// The heading of the archived sessions, around their count.
    public var archivedPrefix: String
    public var archivedSuffix: String
    /// A row's buttons.
    public var archiveSession: String
    public var unarchiveSession: String
    /// A row's menu: open the conversation, and copy its title.
    public var resumeSession: String
    public var copySessionTitle: String
    /// The button that deletes every conversation of the working folder,
    /// and what it says after one click, while it waits for the second.
    public var clearAll: String
    public var clearAllConfirm: String
    /// The card an embedded chat shows in place of an empty list.
    public var agentEnvironment: String
    public var ready: String
    public var environmentProvider: String
    public var environmentModel: String
    public var environmentDirectory: String
    public var defaultModel: String
    /// The card's last line. The default says only what any app's chat can
    /// do; an app with shortcuts of its own to mention passes its own line.
    public var environmentHint: String

    // MARK: The chat's header

    /// Beside the title of a session that was reopened.
    public var resumed: String
    /// The new-chat button's tooltip, and the shortcut written after it.
    /// The view does not handle the shortcut: the app's window does, and an
    /// app whose window has another, or none, passes that here.
    public var newChat: String
    public var newChatShortcut: String
    /// The pin button's tooltip, unpinned and pinned.
    public var pinWindow: String
    public var unpinWindow: String
    /// The model badge: with no model set, while it is edited, and its
    /// tooltips (the model's name follows `modelHelpPrefix`).
    public var autoModel: String
    public var modelNamePlaceholder: String
    public var setModel: String
    public var modelHelpPrefix: String
    /// The folder badge: the picker's button, and its tooltip around the path.
    public var setWorkingDirectory: String
    public var workingDirectoryHelpPrefix: String
    public var workingDirectoryHelpSuffix: String

    // MARK: The conversation

    /// A turn in flight: with no tool named, and before a tool's name.
    public var thinking: String
    public var working: String
    /// A turn that failed, and the button that sends it again.
    public var agentFailed: String
    public var retry: String
    /// The button that appears when the chat is scrolled up.
    public var scrollToBottom: String
    public var newMessages: String
    /// The tool steps of a reply: one step with no title, and after the
    /// count of several.
    public var oneToolExecutionFinished: String
    public var toolExecutionsFinishedSuffix: String
    /// The button that opens a reply's reasoning.
    public var thinkingProcess: String
    /// The copy button, and what it says just after a click: under a
    /// message, and on a code block.
    public var copy: String
    public var copiedMessage: String
    public var copiedCode: String
    /// The line of figures under a reply; each follows its number.
    public var statsInSuffix: String
    public var statsOutSuffix: String
    public var statsCachedSuffix: String
    public var statsToolSuffix: String
    public var statsToolsSuffix: String
    /// The table that line opens into; `statsTokensSuffix` follows a count.
    public var statsModel: String
    public var statsDuration: String
    public var statsInput: String
    public var statsOutput: String
    public var statsCached: String
    public var statsCost: String
    public var statsToolCalls: String
    public var statsTurns: String
    public var statsStatus: String
    public var statsTokensSuffix: String
    /// The label of a code block that names no language.
    public var codeLabel: String
    /// A diagram card: its title and first tab, its second tab, the copy
    /// button's tooltip, and what it says when the diagram cannot be drawn.
    public var diagram: String
    public var diagramSource: String
    public var copySource: String
    public var diagramRenderFailed: String

    // MARK: A tool waiting for permission

    /// The card's title and its four states.
    public var permissionRequest: String
    public var awaitingConfirmation: String
    public var approved: String
    public var denied: String
    public var allowedForSession: String
    /// Its three buttons.
    public var allow: String
    public var deny: String
    public var allowForSession: String

    // MARK: Plan mode, worktree mode and subagents

    /// The two switches above the follow-up bar, and the line beside
    /// whichever is on.
    public var plan: String
    public var worktree: String
    public var planContext: String
    public var worktreeContext: String
    /// After the number of subagents at work: one, and several.
    public var subagentRunningSuffix: String
    public var subagentsRunningSuffix: String

    public init(
        quickPromptTitle: String = "Agent Quick Prompt",
        askPrefix: String = "Ask ",
        askSuffix: String = " anything…",
        fallbackProviderName: String = "Agent",
        followUpPrefix: String = "Follow up with ",
        followUpSuffix: String = "…",
        send: String = "Send",
        stopReply: String = "Stop",
        sessionsToggle: String = "Recent sessions",
        planModeOn: String = "Plan mode on (read-only)",
        planModeOff: String = "Turn on plan mode",
        worktreeModeOn: String = "Worktree mode on (isolated branch)",
        worktreeModeOff: String = "Enable git worktree",
        workingFolder: String = "Working folder",
        switchProvider: String = "Switch provider",
        sessionsFilter: String = "Filter sessions",
        noSessions: String = "No recent sessions",
        untitledSession: String = "Untitled",
        archivedPrefix: String = "Archived (",
        archivedSuffix: String = ")",
        archiveSession: String = "Archive session",
        unarchiveSession: String = "Unarchive session",
        resumeSession: String = "Resume",
        copySessionTitle: String = "Copy Title",
        clearAll: String = "Clear All",
        clearAllConfirm: String = "Confirm?",
        agentEnvironment: String = "Agent Environment",
        ready: String = "Ready",
        environmentProvider: String = "Provider",
        environmentModel: String = "Model",
        environmentDirectory: String = "Directory",
        defaultModel: String = "Default / Auto",
        environmentHint: String = "Type a prompt above to start an agent session.",
        resumed: String = "Resumed",
        newChat: String = "New chat",
        newChatShortcut: String = " (⌘N)",
        pinWindow: String = "Pin window",
        unpinWindow: String = "Unpin window",
        autoModel: String = "Auto",
        modelNamePlaceholder: String = "model name",
        setModel: String = "Set model",
        modelHelpPrefix: String = "Model: ",
        setWorkingDirectory: String = "Set Working Directory",
        workingDirectoryHelpPrefix: String = "Working Directory: ",
        workingDirectoryHelpSuffix: String = "\nClick to change",
        thinking: String = "Thinking…",
        working: String = "Working…",
        agentFailed: String = "The agent stopped with an error.",
        retry: String = "Retry",
        scrollToBottom: String = "Scroll to bottom",
        newMessages: String = "New messages",
        oneToolExecutionFinished: String = "1 tool execution finished",
        toolExecutionsFinishedSuffix: String = " tool executions finished",
        thinkingProcess: String = "Thinking process",
        copy: String = "Copy",
        copiedMessage: String = "Copied!",
        copiedCode: String = "Copied",
        statsInSuffix: String = " in",
        statsOutSuffix: String = " out",
        statsCachedSuffix: String = " cached",
        statsToolSuffix: String = " tool",
        statsToolsSuffix: String = " tools",
        statsModel: String = "Model",
        statsDuration: String = "Duration",
        statsInput: String = "Input",
        statsOutput: String = "Output",
        statsCached: String = "Cached",
        statsCost: String = "Cost",
        statsToolCalls: String = "Tool calls",
        statsTurns: String = "Turns",
        statsStatus: String = "Status",
        statsTokensSuffix: String = " tokens",
        codeLabel: String = "code",
        diagram: String = "Diagram",
        diagramSource: String = "Source",
        copySource: String = "Copy source",
        diagramRenderFailed: String = "Diagram render failed — showing source",
        permissionRequest: String = "Permission Request",
        awaitingConfirmation: String = "Awaiting confirmation",
        approved: String = "Approved",
        denied: String = "Denied",
        allowedForSession: String = "Allowed for Session",
        allow: String = "Allow",
        deny: String = "Deny",
        allowForSession: String = "Allow for Session",
        plan: String = "Plan",
        worktree: String = "Worktree",
        planContext: String = "Read-only — agent will explain without making changes",
        worktreeContext: String = "Isolated git branch — ask the agent to merge when finished",
        subagentRunningSuffix: String = " subagent running",
        subagentsRunningSuffix: String = " subagents running"
    ) {
        self.quickPromptTitle = quickPromptTitle
        self.askPrefix = askPrefix
        self.askSuffix = askSuffix
        self.fallbackProviderName = fallbackProviderName
        self.followUpPrefix = followUpPrefix
        self.followUpSuffix = followUpSuffix
        self.send = send
        self.stopReply = stopReply
        self.sessionsToggle = sessionsToggle
        self.planModeOn = planModeOn
        self.planModeOff = planModeOff
        self.worktreeModeOn = worktreeModeOn
        self.worktreeModeOff = worktreeModeOff
        self.workingFolder = workingFolder
        self.switchProvider = switchProvider
        self.sessionsFilter = sessionsFilter
        self.noSessions = noSessions
        self.untitledSession = untitledSession
        self.archivedPrefix = archivedPrefix
        self.archivedSuffix = archivedSuffix
        self.archiveSession = archiveSession
        self.unarchiveSession = unarchiveSession
        self.resumeSession = resumeSession
        self.copySessionTitle = copySessionTitle
        self.clearAll = clearAll
        self.clearAllConfirm = clearAllConfirm
        self.agentEnvironment = agentEnvironment
        self.ready = ready
        self.environmentProvider = environmentProvider
        self.environmentModel = environmentModel
        self.environmentDirectory = environmentDirectory
        self.defaultModel = defaultModel
        self.environmentHint = environmentHint
        self.resumed = resumed
        self.newChat = newChat
        self.newChatShortcut = newChatShortcut
        self.pinWindow = pinWindow
        self.unpinWindow = unpinWindow
        self.autoModel = autoModel
        self.modelNamePlaceholder = modelNamePlaceholder
        self.setModel = setModel
        self.modelHelpPrefix = modelHelpPrefix
        self.setWorkingDirectory = setWorkingDirectory
        self.workingDirectoryHelpPrefix = workingDirectoryHelpPrefix
        self.workingDirectoryHelpSuffix = workingDirectoryHelpSuffix
        self.thinking = thinking
        self.working = working
        self.agentFailed = agentFailed
        self.retry = retry
        self.scrollToBottom = scrollToBottom
        self.newMessages = newMessages
        self.oneToolExecutionFinished = oneToolExecutionFinished
        self.toolExecutionsFinishedSuffix = toolExecutionsFinishedSuffix
        self.thinkingProcess = thinkingProcess
        self.copy = copy
        self.copiedMessage = copiedMessage
        self.copiedCode = copiedCode
        self.statsInSuffix = statsInSuffix
        self.statsOutSuffix = statsOutSuffix
        self.statsCachedSuffix = statsCachedSuffix
        self.statsToolSuffix = statsToolSuffix
        self.statsToolsSuffix = statsToolsSuffix
        self.statsModel = statsModel
        self.statsDuration = statsDuration
        self.statsInput = statsInput
        self.statsOutput = statsOutput
        self.statsCached = statsCached
        self.statsCost = statsCost
        self.statsToolCalls = statsToolCalls
        self.statsTurns = statsTurns
        self.statsStatus = statsStatus
        self.statsTokensSuffix = statsTokensSuffix
        self.codeLabel = codeLabel
        self.diagram = diagram
        self.diagramSource = diagramSource
        self.copySource = copySource
        self.diagramRenderFailed = diagramRenderFailed
        self.permissionRequest = permissionRequest
        self.awaitingConfirmation = awaitingConfirmation
        self.approved = approved
        self.denied = denied
        self.allowedForSession = allowedForSession
        self.allow = allow
        self.deny = deny
        self.allowForSession = allowForSession
        self.plan = plan
        self.worktree = worktree
        self.planContext = planContext
        self.worktreeContext = worktreeContext
        self.subagentRunningSuffix = subagentRunningSuffix
        self.subagentsRunningSuffix = subagentsRunningSuffix
    }
}
