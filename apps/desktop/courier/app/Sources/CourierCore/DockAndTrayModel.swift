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
                  !row.hidden
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
            guard !isInitializing, !isRevertingLockedSetting else { return }
            guard AppLockGate.shared.canPerform(.settingsChange) else {
                isRevertingLockedSetting = true
                badgeMode = oldValue
                isRevertingLockedSetting = false
                return
            }
            defaults.set(badgeMode.rawValue, forKey: Self.key("badgeMode"))
        }
    }
    @Published public var showMenuBarIcon: Bool {
        didSet {
            guard !isInitializing, !isRevertingLockedSetting else { return }
            guard AppLockGate.shared.canPerform(.settingsChange) else {
                isRevertingLockedSetting = true
                showMenuBarIcon = oldValue
                isRevertingLockedSetting = false
                return
            }
            defaults.set(showMenuBarIcon, forKey: Self.key("showMenuBarIcon"))
        }
    }

    public static func key(_ name: String) -> String { "courier.dock." + name }

    private let defaults: UserDefaults
    private var isInitializing = true
    private var isRevertingLockedSetting = false

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let rawBadge = defaults.string(forKey: Self.key("badgeMode")) ?? DockBadgeMode.unreadChats.rawValue
        self.badgeMode = DockBadgeMode(rawValue: rawBadge) ?? .unreadChats
        self.showMenuBarIcon = defaults.object(forKey: Self.key("showMenuBarIcon")) as? Bool ?? true
        isInitializing = false
    }
}

/// Sections in the Settings window targeted by menu commands (`About Courier`, `Accounts…`, `Keyboard Shortcuts`, etc.).
public enum SettingsSection: String, CaseIterable, Sendable {
    case general
    case accounts
    case appearance
    case inbox
    case messages
    case notifications
    case shortcuts
    case privacy
    case changelog
    case reportProblem
    case about
}

/// Shared menu action model invoked identically by the native macOS menu bar, the Dock menu (`applicationDockMenu`),
/// and the menu-bar status item (`02` §3.1, §3.2).
@MainActor
public final class AppMenuCoordinator: ObservableObject {
    @Published public private(set) var activeSettingsSection: SettingsSection = .inbox
    @Published public var isSidebarVisible: Bool = true
    @Published public private(set) var detachedChatRoomIDs: [String] = []
    @Published public private(set) var focusCount: Int = 0
    @Published public private(set) var quitRequestedCount: Int = 0
    public let settingsNavigation: SettingsNavigationModel
    public var onOpenCommandBar: @MainActor () -> Void = {}

    public let inbox: InboxModel
    public let lifecycle: SystemLifecycleModel
    private let showMainWindow: @MainActor () -> Void
    private let showSettingsWindow: @MainActor () -> Void
    private let hideApp: @MainActor () -> Void
    private let closeKeyWindow: @MainActor () -> Void
    private let closeAllAppWindows: @MainActor () -> Void
    private let openDetachedChat: @MainActor (String) -> Void
    private let quitApplication: @MainActor () -> Void

    public init(
        inbox: InboxModel,
        lifecycle: SystemLifecycleModel,
        settingsNavigation: SettingsNavigationModel? = nil,
        showMainWindow: @escaping @MainActor () -> Void = {},
        showSettingsWindow: @escaping @MainActor () -> Void = {},
        hideApp: @escaping @MainActor () -> Void = {},
        closeKeyWindow: @escaping @MainActor () -> Void = {},
        closeAllAppWindows: @escaping @MainActor () -> Void = {},
        openDetachedChat: @escaping @MainActor (String) -> Void = { _ in },
        quitApplication: @escaping @MainActor () -> Void = {}
    ) {
        self.inbox = inbox
        self.lifecycle = lifecycle
        self.settingsNavigation = settingsNavigation ?? SettingsNavigationModel()
        self.showMainWindow = showMainWindow
        self.showSettingsWindow = showSettingsWindow
        self.hideApp = hideApp
        self.closeKeyWindow = closeKeyWindow
        self.closeAllAppWindows = closeAllAppWindows
        self.openDetachedChat = openDetachedChat
        self.quitApplication = quitApplication
    }

    public func focusApp() {
        focusCount += 1
        showMainWindow()
    }

    public func quitApp() {
        quitRequestedCount += 1
        quitApplication()
    }

    @discardableResult
    public func openChatFromExternalMenu(_ roomID: String) async -> Bool {
        if lifecycle.isLocked {
            let unlocked = await lifecycle.unlockWithTouchID()
            guard unlocked, !lifecycle.isLocked else { return false }
        }
        showMainWindow()
        inbox.select(roomID)
        return true
    }

    public func lockOrUnlockApp() async {
        if lifecycle.isLocked {
            _ = await lifecycle.unlockWithTouchID()
        } else {
            lifecycle.lockApp()
        }
    }

    public func minimizeToMenuBar() {
        hideApp()
    }

    public func openSettings(_ section: SettingsSection) {
        guard !lifecycle.isLocked else { return }
        activeSettingsSection = section
        switch section {
        case .general, .inbox, .messages:
            settingsNavigation.openPane(.general)
        case .appearance:
            settingsNavigation.openPane(.appearance)
        case .notifications:
            settingsNavigation.openPane(.notifications)
        case .accounts:
            settingsNavigation.openPane(.accounts)
        case .shortcuts:
            settingsNavigation.openPane(.hotkeys)
        case .privacy, .changelog, .about:
            settingsNavigation.openPane(.about)
        case .reportProblem:
            settingsNavigation.openPane(.about)
            settingsNavigation.isPresentingProblemReport = true
        }
        showSettingsWindow()
    }

    public func openSettings(pane: SettingsPaneID, accountKey: String? = nil) {
        guard !lifecycle.isLocked else { return }
        settingsNavigation.openPane(pane, accountKey: accountKey)
        showSettingsWindow()
    }

    public func newChat() {
        guard !lifecycle.isLocked else { return }
        showMainWindow()
        inbox.openStartNewChat()
    }

    public func openCommandBar() {
        guard !lifecycle.isLocked else { return }
        showMainWindow()
        onOpenCommandBar()
    }

    public func openChatInNewWindow() {
        guard !lifecycle.isLocked, let roomID = inbox.selectedRoomID else { return }
        detachedChatRoomIDs.append(roomID)
        openDetachedChat(roomID)
    }

    public func closeWindow() {
        closeKeyWindow()
    }

    public func closeAllWindows() {
        closeAllAppWindows()
    }

    public func toggleSpaceBar() {
        guard !lifecycle.isLocked else { return }
        inbox.preferences.showSpaceBar.toggle()
    }

    public func toggleSidebar() {
        guard !lifecycle.isLocked else { return }
        isSidebarVisible.toggle()
    }
}
