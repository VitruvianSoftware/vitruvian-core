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

    /// Saved as the id's text, so the preference stays a plain string.
    package var chosenProviderID: UUID? {
        get { UUID(uuidString: defaults[Preferences.nexusAgentChosenProvider]) }
        set { defaults[Preferences.nexusAgentChosenProvider] = newValue?.uuidString ?? "" }
    }

    /// Saved as JSON. Nothing saved, or something that cannot be read, is
    /// no providers of the user's own: the built-in three are still offered.
    package var savedProviders: [NexusAgentCLIProvider] {
        get {
            (try? JSONDecoder().decode([NexusAgentCLIProvider].self,
                                       from: defaults[Preferences.nexusAgentSavedProviders])) ?? []
        }
        set {
            guard let data = try? JSONEncoder().encode(newValue) else { return }
            defaults[Preferences.nexusAgentSavedProviders] = data
        }
    }

    /// The archived Claude sessions as they are saved: always in the app's
    /// own defaults, whatever `defaults` this host was built with, which is
    /// where they have been kept since before there was a host.
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

    /// What the user is told about a turn: the notch notice, whether the
    /// "done" sound plays and, when one is due, the system notification.
    /// Decided apart from the telling, so the decision can be tested.
    package struct TurnAnnouncement: Equatable {
        package var notchTitle: String
        package var notchDetail: String
        package var notchSymbol: String
        package var playsSound: Bool
        package var notificationTitle: String?
        package var notificationBody: String?

        package init(notchTitle: String, notchDetail: String, notchSymbol: String, playsSound: Bool,
                     notificationTitle: String? = nil, notificationBody: String? = nil) {
            self.notchTitle = notchTitle
            self.notchDetail = notchDetail
            self.notchSymbol = notchSymbol
            self.playsSound = playsSound
            self.notificationTitle = notificationTitle
            self.notificationBody = notificationBody
        }
    }

    /// A turn waiting on approval is a notch notice and nothing else.
    nonisolated package static func announcement(needingApproval notice: NexusAgentTurnNotice,
                                                 strings: NexusAgentHostStrings) -> TurnAnnouncement {
        TurnAnnouncement(notchTitle: strings.approvalRequiredTitle(provider: notice.providerName),
                         notchDetail: notice.text,
                         notchSymbol: "hand.raised.fill",
                         playsSound: false)
    }

    /// The notch always hears of it. The sound is for a turn that ended
    /// well. The system notification is for a user who is not looking at
    /// the chat, and says nothing for a turn that ended with no reply.
    nonisolated package static func announcement(finished notice: NexusAgentTurnNotice, isChatVisible: Bool,
                                                 strings: NexusAgentHostStrings) -> TurnAnnouncement {
        let name = notice.providerName
        let reply = notice.text
        let firstLine = reply.components(separatedBy: .newlines).first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) ?? reply
        var announcement = TurnAnnouncement(
            notchTitle: notice.failed ? strings.failedTitle(provider: name) : strings.doneTitle(provider: name),
            notchDetail: String(firstLine.prefix(80)),
            notchSymbol: notice.failed ? "exclamationmark.triangle.fill" : "sparkles",
            playsSound: notice.endedCleanly)
        guard !isChatVisible else { return announcement }
        if notice.failed {
            announcement.notificationTitle = strings.failedTitle(provider: name)
            announcement.notificationBody = String(reply.prefix(200))
        } else if !reply.isEmpty {
            announcement.notificationTitle = strings.doneTitle(provider: name)
            announcement.notificationBody = String(firstLine.prefix(200))
        }
        return announcement
    }

    package func turnNeedsApproval(_ notice: NexusAgentTurnNotice) {
        announce(Self.announcement(needingApproval: notice, strings: strings))
    }

    package func turnFinished(_ notice: NexusAgentTurnNotice, isChatVisible: Bool) {
        announce(Self.announcement(finished: notice, isChatVisible: isChatVisible, strings: strings))
    }

    /// The notch first, then the sound, then the notification.
    private func announce(_ announcement: TurnAnnouncement) {
        _ = NotchService.shared.show(NotchNotice(
            event: .agents,
            title: announcement.notchTitle,
            detail: announcement.notchDetail,
            symbol: announcement.notchSymbol
        ))
        if announcement.playsSound { NSSound(named: "Tink")?.play() }
        if let title = announcement.notificationTitle, let body = announcement.notificationBody {
            Notifier.post(title: title, body: body)
        }
    }
}
