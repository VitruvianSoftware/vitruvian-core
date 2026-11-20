// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation

// How a search result's row reads: its date, where its chat is, who sent it and the groups a person is in.

/// A found message's date: the time today, the day and month this year, else the whole date.
public enum SearchDate {
    public static func text(forMillis millis: Int64, now: Date = Date(), calendar: Calendar = .current,
                            locale: Locale = .current,
                            timeFormat: TimeFormatPreference = .system) -> String {
        guard millis > 0 else { return "" }
        let date = Date(timeIntervalSince1970: TimeInterval(millis) / 1000)
        let style = Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone)
        if calendar.isDate(date, inSameDayAs: now) {
            if timeFormat != .system {
                return timeFormat.formatTime(date, locale: locale, timeZone: calendar.timeZone)
            }
            return date.formatted(style.hour().minute())
        }
        if calendar.isDate(date, equalTo: now, toGranularity: .year) {
            return date.formatted(style.month(.abbreviated).day())
        }
        return date.formatted(style.year().month(.abbreviated).day())
    }
}

extension ChatPlace {
    /// The tag a result outside the inbox carries; nil in the inbox (and for a place this app doesn't know).
    public var tag: String? {
        switch self {
        case .archive: String(localized: "Archived")
        case .lowPriority: String(localized: "Low priority")
        case .hidden: String(localized: "Hidden")
        case .requests: String(localized: "Request")
        default: nil
        }
    }
}

extension InboxRow {
    /// Where the chat is, decided as the engine decides a message's place: hidden, then a request, then low
    /// priority, then archived, else the inbox.
    public var place: ChatPlace {
        if hidden { return .hidden }
        if request { return .requests }
        if lowPriority { return .lowPriority }
        if archived { return .archive }
        return .inbox
    }
}

extension PersonHit {
    /// "In <group>", or "In <group> and N other groups".
    public var groupsLine: String {
        let others = groups - 1
        switch others {
        case ...0: return String(localized: "In \(roomName)")
        case 1: return String(localized: "In \(roomName) and 1 other group")
        default: return String(localized: "In \(roomName) and \(others) other groups")
        }
    }
}

extension MessageHit {
    /// Who sent it: "You" for mine, else their name (their ID when they have none).
    public var senderLine: String {
        if mine { return String(localized: "You") }
        return senderName.isEmpty ? sender : senderName
    }
}

/// Where a found message is, in one line: "Kent Hua in Eddie & Kent · Google Chat"; in a one-to-one chat, whose
/// title is only the other person's name, "Kent Hua · Google Chat".
public enum SearchResultLocation {
    /// - Parameters:
    ///   - sender: who sent it, as the row says it ("You" for mine).
    ///   - chatTitle: the chat's title, as the inbox row shows it. Left out of a one-to-one chat's line.
    ///   - networkName: the network's name for people ("Google Chat"). Left out when empty.
    ///   - isDirect: a one-to-one chat.
    ///   - scopedToSingleChat: true when search is scoped to one chat; omits the redundant chat and network names.
    public static func subtitle(
        sender: String,
        chatTitle: String,
        networkName: String,
        isDirect: Bool,
        scopedToSingleChat: Bool = false
    ) -> String {
        if scopedToSingleChat {
            return sender
        }
        let title = chatTitle.isEmpty ? String(localized: "Unnamed chat") : chatTitle
        switch (isDirect, networkName.isEmpty) {
        case (true, true):
            return sender
        case (true, false):
            return String(localized: "\(sender) · \(networkName)",
                          comment: "Search result in a one-to-one chat: who sent it, then the network.")
        case (false, true):
            return String(localized: "\(sender) in \(title)",
                          comment: "Search result in a group: who sent it, then the chat's title.")
        case (false, false):
            return String(localized: "\(sender) in \(title) · \(networkName)",
                          comment: "Search result in a group: who sent it, the chat's title, then the network.")
        }
    }
}

/// The display name for the in-chat search scope chip and empty-state prompt, matching the chat header.
@MainActor
public enum SearchScopePresentation {
    /// Resolves the scope chat's display name: prefers `openChatDisplayTitle` when searching the open chat,
    /// then `inbox.chatTitle(forRoomID:fetchedRow:)` (formatted with confirmed group members & stripped tags),
    /// then `"Unnamed chat"` once `scopeRow` is loaded with an empty name. Returns `nil` when unscoped or while
    /// an unknown room's row is still loading.
    public static func displayName(
        scopeRoomID: String?,
        scopeRow: InboxRow?,
        inbox: InboxModel,
        openChatRoomID: String? = nil,
        openChatDisplayTitle: String? = nil
    ) -> String? {
        guard let roomID = scopeRoomID ?? scopeRow?.id, !roomID.isEmpty else { return nil }
        if let openChatRoomID, openChatRoomID == roomID,
           let headerTitle = openChatDisplayTitle?.trimmingCharacters(in: .whitespacesAndNewlines),
           !headerTitle.isEmpty {
            return headerTitle
        }
        if let title = inbox.chatTitle(forRoomID: roomID, fetchedRow: scopeRow) {
            return title
        }
        if let scopeRow {
            let formatted = inbox.displayTitle(for: scopeRow).trimmingCharacters(in: .whitespacesAndNewlines)
            return formatted.isEmpty ? String(localized: "Unnamed chat") : formatted
        }
        return nil
    }
}

/// Which optional controls the search panel and filter bar display for the current scope.
public struct SearchPanelControls: Equatable, Sendable {
    public let showsAccountsFilter: Bool
    public let showsChatTypeFilter: Bool
    public let showsCommandsChip: Bool

    public init(showsAccountsFilter: Bool, showsChatTypeFilter: Bool, showsCommandsChip: Bool) {
        self.showsAccountsFilter = showsAccountsFilter
        self.showsChatTypeFilter = showsChatTypeFilter
        self.showsCommandsChip = showsCommandsChip
    }

    public static func resolve(
        isScopedToChat: Bool,
        hasAccounts: Bool,
        filters: SearchFilterSet,
        hasCommandBarAction: Bool
    ) -> SearchPanelControls {
        if isScopedToChat {
            return SearchPanelControls(
                showsAccountsFilter: false,
                showsChatTypeFilter: filters.chatType != nil,
                showsCommandsChip: false
            )
        }
        return SearchPanelControls(
            showsAccountsFilter: hasAccounts || !filters.networks.isEmpty,
            showsChatTypeFilter: true,
            showsCommandsChip: hasCommandBarAction
        )
    }
}

extension InboxModel {
    /// The title of the chat a found message is in, as that chat's inbox row shows it (`displayTitle(for:)`, the
    /// inbox's own): the engine's `room_name` is the bridge's name, and a group still named by its members' names
    /// shows shorter in the list ("Eddie & Kent"). `fetchedRow` is the chat's row when the inbox's list doesn't
    /// have it (an old chat past the first pages of the list). With no row at all, the engine's name.
    public func chatTitle(for hit: MessageHit, fetchedRow: InboxRow? = nil) -> String {
        chatTitle(forRoomID: hit.roomID, fetchedRow: fetchedRow) ?? hit.roomName
    }

    /// The same for a chat by its ID (the open chat, for "Press ⌘F to search in …"); nil when there is no row, or
    /// the row has no title.
    public func chatTitle(forRoomID roomID: String, fetchedRow: InboxRow? = nil) -> String? {
        guard let row = row(of: roomID) ?? fetchedRow else { return nil }
        let title = displayTitle(for: row)
        return title.isEmpty ? nil : title
    }
}

/// The first line of the search panel while a chat is open: "Press ⌘F to search in <chat>". Return on it, or a
/// click, searches that chat with what is typed.
public struct SearchInChatOffer: Equatable, Sendable {
    public let roomID: String
    /// The chat's title as its inbox row shows it; empty when the chat has no row yet.
    public let title: String
    /// The chord that opens in-chat search ("⌘F" unless the person changed it); nil when it has none.
    public let shortcut: String?

    public init(roomID: String, title: String, shortcut: String?) {
        self.roomID = roomID
        self.title = title
        self.shortcut = shortcut
    }

    public var text: String {
        let name = title.isEmpty ? String(localized: "this chat") : title
        if let shortcut, !shortcut.isEmpty {
            return String(localized: "Press \(shortcut) to search in \(name)",
                          comment: "First line of the search panel while a chat is open. The first argument is the shortcut, the second the chat's title.")
        }
        return String(localized: "Search in \(name)",
                      comment: "First line of the search panel while a chat is open, when Search in Chat has no shortcut. The argument is the chat's title.")
    }

    /// The offer for the open chat, from where the app keeps the chord: Search in Chat in the shortcut registry.
    @MainActor
    public static func make(roomID: String?, title: String, hotkeys: HotkeyRegistry) -> SearchInChatOffer? {
        guard let roomID, !roomID.isEmpty else { return nil }
        return SearchInChatOffer(roomID: roomID, title: title,
                                 shortcut: hotkeys.primaryChord(for: HotkeyID.searchInChat)?.symbols)
    }
}
