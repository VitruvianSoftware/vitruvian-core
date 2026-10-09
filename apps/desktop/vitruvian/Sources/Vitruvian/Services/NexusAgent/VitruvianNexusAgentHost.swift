// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import AppKit
import VitruvianCore

/// Vitruvian's answers to the shared Nexus Agent code: its saved settings,
/// its translations, and how it tells the user about a turn (the notch, a
/// sound and, away from the chat, a system notification).
///
/// Every answer is read when it is asked for, never kept: the user can
/// change a setting or the language while the app runs.
@MainActor
package final class VitruvianNexusAgentHost: NexusAgentHost {
    private let defaults: UserDefaults

    package init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    package var configuredBotDirectory: String { defaults[Preferences.nexusAgentBotDirectory] }

    package var startsBotAtLaunch: Bool { defaults[Preferences.nexusAgentAutoStart] }

    package var planMode: Bool {
        get { defaults[Preferences.nexusAgentPlanMode] }
        set { defaults[Preferences.nexusAgentPlanMode] = newValue }
    }

    package var hiddenClaudeSessionIDs: [String] {
        get { Self.savedHiddenClaudeSessionIDs }
        set { Self.savedHiddenClaudeSessionIDs = newValue }
    }

    /// The archived Claude sessions as they are saved: always in the app's
    /// own defaults, whatever `defaults` this host was built with, because
    /// the session list reads them back from there
    /// (`NexusAgentSessionSummary.claudeHiddenSessionIds`).
    nonisolated package static var savedHiddenClaudeSessionIDs: [String] {
        get { UserDefaults.standard.stringArray(forKey: "vitruvian.claude.hiddenSessionIds") ?? [] }
        set { UserDefaults.standard.set(newValue, forKey: "vitruvian.claude.hiddenSessionIds") }
    }

    package var strings: NexusAgentHostStrings {
        let translated = FeatureStrings.nexusAgent(L10n.shared.language)
        return NexusAgentHostStrings(untitledSession: translated.untitledSession,
                                     missingAgent: translated.missingAgent,
                                     agentFailed: translated.agentFailed,
                                     replyStopped: translated.replyStopped,
                                     emptyReply: translated.emptyReply)
    }

    package func turnNeedsApproval(_ notice: NexusAgentTurnNotice) {
        _ = NotchService.shared.show(NotchNotice(
            event: .agents,
            title: strings.approvalRequiredTitle(provider: notice.providerName),
            detail: notice.text,
            symbol: "hand.raised.fill"
        ))
    }

    /// The notch always hears of it. The sound is for a turn that ended
    /// well. The system notification is for a user who is not looking at
    /// the chat, and says nothing for a turn that ended with no reply.
    package func turnFinished(_ notice: NexusAgentTurnNotice, isChatVisible: Bool) {
        let strings = self.strings
        let name = notice.providerName
        let reply = notice.text
        let firstLine = reply.components(separatedBy: .newlines).first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) ?? reply
        _ = NotchService.shared.show(NotchNotice(
            event: .agents,
            title: notice.failed ? strings.failedTitle(provider: name) : strings.doneTitle(provider: name),
            detail: String(firstLine.prefix(80)),
            symbol: notice.failed ? "exclamationmark.triangle.fill" : "sparkles"
        ))
        if notice.endedCleanly { NSSound(named: "Tink")?.play() }
        guard !isChatVisible else { return }
        if notice.failed {
            Notifier.post(title: strings.failedTitle(provider: name), body: String(reply.prefix(200)))
        } else if !reply.isEmpty {
            Notifier.post(title: strings.doneTitle(provider: name), body: String(firstLine.prefix(200)))
        }
    }
}
