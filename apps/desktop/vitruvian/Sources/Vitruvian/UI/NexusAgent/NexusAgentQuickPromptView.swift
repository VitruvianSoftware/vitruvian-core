// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import NexusAgentUI
import SwiftUI
import VitruvianCore
import VitruvianDesign
import VitruvianServices

/// The Nexus Agent chat as this app shows it, in its floating window and in
/// the notch. The chat itself is the shared `NexusAgentChatView`
/// (apps/desktop/nexus-agent/macos/Sources/NexusAgentUI), which knows no
/// app; this view hands it what is this app's: the service, the text in the
/// app's language, the backdrop behind the floating window, the pin, and
/// docking to the notch.
///
/// It observes the service and the language, and builds the text and the
/// chrome again each time either changes, so a new language or a new pin
/// state reaches the chat at once.
package struct NexusAgentQuickPromptView: View {
    package let embeddedInNotch: Bool

    @ObservedObject private var service: NexusAgentService
    @ObservedObject private var l10n = L10n.shared

    /// The app shows its one service. The snapshot tool
    /// (Tools/NexusAgentChatSnapshots.swift) hands in a service built over
    /// fake files instead, so that it never reads the user's own.
    package init(embeddedInNotch: Bool = false, service: NexusAgentService = .shared) {
        self.embeddedInNotch = embeddedInNotch
        self.service = service
    }

    package var body: some View {
        NexusAgentChatView(engine: service,
                           strings: Self.strings(for: l10n.language),
                           chrome: Self.chrome(for: service, embeddedInNotch: embeddedInNotch))
    }

    /// The chat's text in `language`. The fields this app has words for come
    /// from its own strings, translated or not; the rest keep the shared
    /// view's English, which is what the chat showed for them before.
    package static func strings(for language: AppLanguage) -> NexusAgentChatStrings {
        let own = FeatureStrings.nexusAgent(language)
        var strings = NexusAgentChatStrings()
        strings.quickPromptTitle = own.quickPromptTitle
        strings.workingFolder = own.workingFolder
        strings.send = own.send
        strings.stopReply = own.stopReply
        strings.newChat = own.newChat
        strings.thinking = own.thinking
        strings.working = own.working
        strings.agentFailed = own.agentFailed
        strings.sessionsToggle = own.sessionsToggle
        strings.planModeOn = own.planModeOn
        strings.planModeOff = own.planModeOff
        strings.sessionsFilter = own.sessionsFilter
        strings.noSessions = own.noSessions
        // This app has one line for an empty list, filtered or not, and
        // keeps it: its words did not change when the shared view learned
        // to tell the two apart.
        strings.noMatchingSessions = own.noSessions
        strings.untitledSession = own.untitledSession
        strings.pinWindow = own.pinWindow
        strings.unpinWindow = own.unpinWindow
        strings.scrollToBottom = own.scrollToBottom
        strings.newMessages = own.newMessages
        strings.retry = own.retry
        strings.worktreeModeOn = own.worktreeModeOn
        strings.worktreeModeOff = own.worktreeModeOff
        strings.worktreeContext = own.worktreeContext
        strings.planContext = own.planContext
        // Two lines that name this app's own shortcuts, so they are said
        // here and not in the shared view's defaults.
        strings.environmentHint = "Type a prompt above to start an agent session. Use ⌥⌘G to switch between Chat and Telemetry."
        strings.newChatShortcut = " (⌘N)"
        return strings
    }

    /// What this app puts around the chat. The pin and the dock button are
    /// offered in the notch as well as in the floating window, as they
    /// always were; the backdrop is handed over either way and the chat
    /// leaves it out when it is embedded.
    package static func chrome(for service: NexusAgentService, embeddedInNotch: Bool) -> NexusAgentChatChrome {
        NexusAgentChatChrome(
            backdrop: AnyView(HUDBackdrop(cornerRadius: NexusAgentQuickPromptLayout.cornerRadius)),
            isEmbedded: embeddedInNotch,
            isPinned: Binding(get: { service.isPinned }, set: { service.isPinned = $0 }),
            // The folder picker counts as a click outside the prompt, which
            // hides it; this brings it back.
            showWindow: { service.showQuickPrompt() },
            dockToNotch: { service.dockToNotch() },
            dockToNotchHelp: "Dock into MacBook Notch (⌥⌘G)",
            errorScheme: "vitruvian-error",
            // This app's drawer has never had Clear All; a conversation is
            // deleted from its row's menu, one at a time.
            offersClearAll: false)
    }
}
