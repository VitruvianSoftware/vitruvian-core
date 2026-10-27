// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import Combine
import Foundation

/// What hovering a row offers.
public enum HoverAction: String, CaseIterable, Sendable { case archive, toggleRead, menu, nothing }

/// What double-clicking a row does. "Open in New Window" comes with 4.5, and becomes the default then.
public enum DoubleClickAction: String, CaseIterable, Sendable {
    case archive, toggleRead, toggleMute, toggleLowPriority, nothing
}

/// Which chat opens after the open one is archived, or its read state toggled.
public enum AfterAction: String, CaseIterable, Sendable { case selectNext, selectPrevious, closeChat, nothing }

/// When a reminder brings a chat back. Inferred (inventory 01 §18): "if no reply" means "if I haven't sent a message
/// since setting it" (the engine decides it).
public enum RemindCondition: String, CaseIterable, Sendable {
    case ifNoReply = "if_no_reply", always

    /// As the protocol has it.
    public var wire: ReminderCondition { ReminderCondition(rawValue: rawValue) }
}

/// The inbox's settings, kept in UserDefaults under "courier.inbox.<name>". These are the Mac's own settings, not
/// chat state: nothing here reaches the engine or a network.
public final class InboxPreferences: ObservableObject {
    @Published public var showSpaceBar: Bool { didSet { set(showSpaceBar, "showSpaceBar") } }
    @Published public var regularPinnedRows: Bool { didSet { set(regularPinnedRows, "regularPinnedRows") } }
    @Published public var showUnreadCounts: Bool { didSet { set(showUnreadCounts, "showUnreadCounts") } }
    @Published public var showPreviews: Bool { didSet { set(showPreviews, "showPreviews") } }
    @Published public var compactList: Bool { didSet { set(compactList, "compactList") } }
    @Published public var showNetworkIcons: Bool { didSet { set(showNetworkIcons, "showNetworkIcons") } }
    @Published public var colorNetworkIcons: Bool { didSet { set(colorNetworkIcons, "colorNetworkIcons") } }
    @Published public var hoverAction: HoverAction { didSet { set(hoverAction.rawValue, "hoverAction") } }
    @Published public var doubleClickAction: DoubleClickAction {
        didSet { set(doubleClickAction.rawValue, "doubleClickAction") }
    }
    @Published public var remindDefault: RemindCondition { didSet { set(remindDefault.rawValue, "remindDefault") } }
    @Published public var archiveAfterReminder: Bool { didSet { set(archiveAfterReminder, "archiveAfterReminder") } }
    @Published public var markReadOnArchive: Bool { didSet { set(markReadOnArchive, "markReadOnArchive") } }
    @Published public var afterArchive: AfterAction { didSet { set(afterArchive.rawValue, "afterArchive") } }
    @Published public var afterToggleRead: AfterAction { didSet { set(afterToggleRead.rawValue, "afterToggleRead") } }
    @Published public var requestNotifications: Bool {
        didSet {
            set(requestNotifications, "requestNotifications")
            if notifications.requestNotificationsEnabled != requestNotifications {
                notifications.requestNotificationsEnabled = requestNotifications
            }
        }
    }
    @Published public var lastUsedReminder: Date? { didSet { set(lastUsedReminder, "lastUsedReminder") } }
    /// "Notify when someone starts typing (supported platforms only)" (02 §1.5, off): one notification per burst of
    /// typing in a chat that would notify for a message (`NotificationPolicy.shouldNotifyTyping`).
    @Published public var typingNotifications: Bool {
        didSet {
            set(typingNotifications, "typingNotifications")
            if notifications.typingNotificationsEnabled != typingNotifications {
                notifications.typingNotificationsEnabled = typingNotifications
            }
        }
    }
    public let notifications: NotificationPreferences

    /// The key a setting is kept under.
    public static func key(_ name: String) -> String { "courier.inbox." + name }

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let notifPrefs = NotificationPreferences(defaults: defaults)
        self.notifications = notifPrefs
        func bool(_ name: String, _ fallback: Bool) -> Bool {
            defaults.object(forKey: Self.key(name)) as? Bool ?? fallback
        }
        func value<T: RawRepresentable>(_ name: String, _ fallback: T) -> T where T.RawValue == String {
            defaults.string(forKey: Self.key(name)).flatMap(T.init(rawValue:)) ?? fallback
        }
        showSpaceBar = bool("showSpaceBar", true)
        regularPinnedRows = bool("regularPinnedRows", false)
        showUnreadCounts = bool("showUnreadCounts", true)
        showPreviews = bool("showPreviews", true)
        compactList = bool("compactList", false)
        showNetworkIcons = bool("showNetworkIcons", true)
        colorNetworkIcons = bool("colorNetworkIcons", true)
        hoverAction = value("hoverAction", HoverAction.archive)
        doubleClickAction = value("doubleClickAction", DoubleClickAction.nothing)
        remindDefault = value("remindDefault", RemindCondition.ifNoReply)
        archiveAfterReminder = bool("archiveAfterReminder", false)
        markReadOnArchive = bool("markReadOnArchive", false)
        afterArchive = value("afterArchive", AfterAction.selectNext)
        afterToggleRead = value("afterToggleRead", AfterAction.selectNext)
        requestNotifications = bool("requestNotifications", notifPrefs.requestNotificationsEnabled)
        lastUsedReminder = defaults.object(forKey: Self.key("lastUsedReminder")) as? Date
        typingNotifications = bool("typingNotifications", notifPrefs.typingNotificationsEnabled)

        notifPrefs.onRequestNotificationsChanged = { [weak self] enabled in
            guard let self, self.requestNotifications != enabled else { return }
            self.requestNotifications = enabled
        }
        notifPrefs.onTypingNotificationsChanged = { [weak self] enabled in
            guard let self, self.typingNotifications != enabled else { return }
            self.typingNotifications = enabled
        }
    }

    private func set(_ value: Any?, _ name: String) {
        if let value {
            defaults.set(value, forKey: Self.key(name))
        } else {
            defaults.removeObject(forKey: Self.key(name))
        }
    }
}
