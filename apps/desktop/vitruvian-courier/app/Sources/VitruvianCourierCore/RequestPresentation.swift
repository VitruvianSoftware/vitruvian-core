// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation

/// How a message request is named, so two requests from strangers can be told apart.
public enum RequestPresentation {
    /// A name a bridge makes up when it knows nothing about the person: empty, or "<Network> user".
    public static func isPlaceholderName(_ name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return true }
        let lower = trimmed.lowercased()
        let placeholders = ["facebook user", "instagram user", "messenger user", "unknown user", "unknown",
                            "whatsapp user", "telegram user", "signal user", "linkedin user", "twitter user",
                            "x user", "tiktok user", "line user", "discord user", "slack user"]
        return placeholders.contains(lower)
    }

    /// The name to show: the chat's own, or for a placeholder the handle, or "Unknown <network> contact".
    public static func title(name: String, handle: String = "", networkName: String) -> String {
        guard isPlaceholderName(name) else { return name }
        let trimmedHandle = handle.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedHandle.isEmpty { return trimmedHandle }
        let network = networkName.trimmingCharacters(in: .whitespacesAndNewlines)
        return network.isEmpty
            ? String(localized: "Unknown contact")
            : String(localized: "Unknown \(network) contact")
    }
}

/// Where an empty list sends the person next.
public enum EmptyStateAction: Equatable, Sendable {
    case goToInbox
}

public struct EmptyStateGuidance: Equatable, Sendable {
    public let actions: [EmptyStateAction]
    /// Text under the message that says how to get something here, when the place has a gesture for it.
    public let howTo: String?

    public init(actions: [EmptyStateAction], howTo: String?) {
        self.actions = actions
        self.howTo = howTo
    }

    /// Send Later, Reminders, Archive and Low Priority end in "Go to Inbox"; Send Later also says how to schedule.
    public static func of(_ query: InboxQuery) -> EmptyStateGuidance {
        let precedence: [InboxFilter] = [.archived, .lowPriority, .hidden, .requests, .reminders, .sendLater]
        let place: String
        if let filter = precedence.first(where: query.filters.contains) {
            place = filter.rawValue
        } else {
            place = query.space
        }
        switch place {
        case "send_later", InboxFilter.sendLater.rawValue:
            return EmptyStateGuidance(
                actions: [.goToInbox],
                howTo: String(localized: "Right-click Send, or choose Send Later from the + menu."))
        case "reminders", InboxFilter.reminders.rawValue,
             "archive", InboxFilter.archived.rawValue,
             "low_priority", InboxFilter.lowPriority.rawValue:
            return EmptyStateGuidance(actions: [.goToInbox], howTo: nil)
        default:
            return EmptyStateGuidance(actions: [], howTo: nil)
        }
    }
}
