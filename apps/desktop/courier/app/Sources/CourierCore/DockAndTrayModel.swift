// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import Combine
import Foundation

/// Which unread count the Dock tile badge displays (`setting:appearance Dock badge count`).
public enum DockBadgeMode: String, CaseIterable, Codable, Sendable {
    /// Unmuted unread chats in the inbox (`attention_chats`, default).
    case unreadChats
    /// All unread chats in the inbox (`unread_chats`, including muted).
    case allChats
    /// No Dock badge (`""`).
    case none
}

/// One chat entry in the Dock menu or menu-bar status item menu.
public struct DockChatItem: Equatable, Sendable, Identifiable {
    public static let maxTitleLength = 40

    public let roomID: String
    public let title: String
    public var id: String { roomID }

    public init(roomID: String, title: String) {
        self.roomID = roomID
        self.title = title
    }

    public static func truncateTitle(_ raw: String) -> String {
        let base = raw.isEmpty ? String(localized: "Unnamed chat") : raw
        guard base.count > maxTitleLength else { return base }
        return String(base.prefix(maxTitleLength - 1)) + "…"
    }
}

/// Pure model for the Dock right-click menu (`applicationDockMenu`) and menu-bar tray menu (`02` §3.2).
public struct DockMenuModel: Equatable, Sendable {
    public static let maxUnreadChats = 5
    public static let maxRecentChats = 5

    public let unreadChats: [DockChatItem]
    public let recentChats: [DockChatItem]
    public var isEmpty: Bool { unreadChats.isEmpty && recentChats.isEmpty }

    public init(unreadChats: [DockChatItem] = [], recentChats: [DockChatItem] = []) {
        self.unreadChats = unreadChats
        self.recentChats = recentChats
    }

    public static func build(
        isLocked: Bool,
        inboxRows: [InboxRow],
        recentlyViewedRoomIDs: [String],
        currentRoomID: String?
    ) -> DockMenuModel {
        guard !isLocked else {
            return DockMenuModel(unreadChats: [], recentChats: [])
        }

        let unreadRows = inboxRows
            .filter { ($0.unread > 0 || $0.markedUnread) && !$0.lowPriority && !$0.hidden && !$0.archived }
            .sorted { $0.lastTS > $1.lastTS }
            .prefix(maxUnreadChats)

        let unreadItems = unreadRows.map { row in
            DockChatItem(roomID: row.roomID, title: DockChatItem.truncateTitle(row.name))
        }
        let unreadSet = Set(unreadItems.map(\.roomID))

        var rowsByID: [String: InboxRow] = [:]
        for row in inboxRows {
            rowsByID[row.roomID] = row
            rowsByID[row.id] = row
        }

        var recentItems: [DockChatItem] = []
        var seenRecent = Set<String>()
        for roomID in recentlyViewedRoomIDs {
            guard recentItems.count < maxRecentChats else { break }
            guard roomID != currentRoomID,
                  !unreadSet.contains(roomID),
                  seenRecent.insert(roomID).inserted,
                  let row = rowsByID[roomID],
                  !row.hidden,
                  row.unread == 0,
                  !row.markedUnread
            else {
                continue
            }
            recentItems.append(DockChatItem(roomID: row.roomID, title: DockChatItem.truncateTitle(row.name)))
        }

        return DockMenuModel(unreadChats: unreadItems, recentChats: recentItems)
    }
}

/// UserDefaults-backed settings for the Dock badge and menu-bar status item (`02` §1.4, §3.2).
@MainActor
public final class DockAndTrayPreferences: ObservableObject {
    @Published public var badgeMode: DockBadgeMode {
        didSet {
            guard !isInitializing else { return }
            defaults.set(badgeMode.rawValue, forKey: Self.key("badgeMode"))
        }
    }
    @Published public var showMenuBarIcon: Bool {
        didSet {
            guard !isInitializing else { return }
            defaults.set(showMenuBarIcon, forKey: Self.key("showMenuBarIcon"))
        }
    }

    public static func key(_ name: String) -> String { "courier.dock." + name }

    private let defaults: UserDefaults
    private var isInitializing = true

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let rawBadge = defaults.string(forKey: Self.key("badgeMode")) ?? DockBadgeMode.unreadChats.rawValue
        self.badgeMode = DockBadgeMode(rawValue: rawBadge) ?? .unreadChats
        self.showMenuBarIcon = defaults.object(forKey: Self.key("showMenuBarIcon")) as? Bool ?? true
        isInitializing = false
    }
}
