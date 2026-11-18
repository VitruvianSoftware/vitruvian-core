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
        let network = shortNetworkName(networkName)
        return network.isEmpty
            ? String(localized: "Unknown contact")
            : String(localized: "Unknown \(network) contact")
    }
}

extension RequestPresentation {
    /// The network's name short enough for a one-line request title: "Facebook Messenger" reads "Messenger", so
    /// "Unknown Messenger contact" fits instead of being cut before the word that matters.
    public static func shortNetworkName(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let prefix = "Facebook "
        if trimmed.hasPrefix(prefix), trimmed.count > prefix.count {
            return String(trimmed.dropFirst(prefix.count))
        }
        return trimmed
    }
}

extension RequestPresentation {
    /// What a request row's second line says.
    public enum Detail: Equatable, Sendable {
        /// The newest message, as any row shows it (media labels like "Photo" included).
        case preview
        /// This text instead.
        case text(String)
    }

    /// With previews on, the message. With them off, something that still tells requests apart: the sender's handle
    /// if the engine has one, else when they wrote ("Nov 14, 3:12 PM"), else "Message request".
    public static func detail(showPreviews: Bool, handle: String, lastTS: Int64,
                              locale: Locale = .current, timeZone: TimeZone = .current) -> Detail {
        if showPreviews { return .preview }
        let trimmed = handle.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return .text(trimmed) }
        if lastTS > 0 { return .text(requestTime(lastTS: lastTS, locale: locale, timeZone: timeZone)) }
        return .text(String(localized: "Message request"))
    }

    /// "Nov 14, 3:12 PM": the date as well as the time, since a request can be days old.
    public static func requestTime(lastTS: Int64, locale: Locale = .current, timeZone: TimeZone = .current) -> String {
        let date = Date(timeIntervalSince1970: Double(lastTS) / 1000)
        func format(_ template: String) -> String {
            let formatter = DateFormatter()
            formatter.locale = locale
            formatter.timeZone = timeZone
            formatter.setLocalizedDateFormatFromTemplate(template)
            return formatter.string(from: date)
        }
        // The system puts a narrow no-break space before AM/PM; a plain space reads the same and compares plainly.
        return "\(format("MMMd")), \(format("jmm"))"
            .replacingOccurrences(of: "\u{202F}", with: " ")
            .replacingOccurrences(of: "\u{00A0}", with: " ")
    }

    /// What VoiceOver says for a request row: who, on which network, and the line that tells it from the others.
    public static func accessibilityLabel(title: String, networkName: String, detail: String) -> String {
        [title, networkName, String(localized: "Message request"), detail]
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
    }

    /// The sender's handle (a username, phone number or email the bridge gave) from the chat's members: the first
    /// person who is not a bot and has one.
    public static func handle(from members: [Member]) -> String {
        for member in members where !member.isBot {
            if let identifier = member.identifiers.first(where: {
                !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }) {
                return identifier.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return ""
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
