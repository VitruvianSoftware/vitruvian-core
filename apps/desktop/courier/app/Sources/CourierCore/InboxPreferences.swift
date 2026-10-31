// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import Combine
import Foundation

/// What hovering a row offers.
public enum HoverAction: String, CaseIterable, Sendable { case archive, toggleRead, menu, nothing }

/// What double-clicking a row does.
public enum DoubleClickAction: String, CaseIterable, Sendable {
    case openInNewWindow, archive, toggleRead, toggleMute, toggleLowPriority, nothing
}

public typealias DoubleClickChatAction = DoubleClickAction

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
    @Published public var showSpaceBar: Bool {
        didSet {
            guard canMutate({ showSpaceBar = oldValue }) else { return }
            set(showSpaceBar, "showSpaceBar")
        }
    }
    @Published public var regularPinnedRows: Bool {
        didSet {
            guard canMutate({ regularPinnedRows = oldValue }) else { return }
            set(regularPinnedRows, "regularPinnedRows")
        }
    }
    @Published public var showUnreadCounts: Bool {
        didSet {
            guard canMutate({ showUnreadCounts = oldValue }) else { return }
            set(showUnreadCounts, "showUnreadCounts")
        }
    }
    @Published public var showPreviews: Bool {
        didSet {
            guard canMutate({ showPreviews = oldValue }) else { return }
            set(showPreviews, "showPreviews")
        }
    }
    @Published public var compactList: Bool {
        didSet {
            guard canMutate({ compactList = oldValue }) else { return }
            set(compactList, "compactList")
        }
    }
    @Published public var showNetworkIcons: Bool {
        didSet {
            guard canMutate({ showNetworkIcons = oldValue }) else { return }
            set(showNetworkIcons, "showNetworkIcons")
        }
    }
    @Published public var colorNetworkIcons: Bool {
        didSet {
            guard canMutate({ colorNetworkIcons = oldValue }) else { return }
            set(colorNetworkIcons, "colorNetworkIcons")
        }
    }
    @Published public var hoverAction: HoverAction {
        didSet {
            guard canMutate({ hoverAction = oldValue }) else { return }
            set(hoverAction.rawValue, "hoverAction")
        }
    }
    @Published public var doubleClickAction: DoubleClickAction {
        didSet {
            guard canMutate({ doubleClickAction = oldValue }) else { return }
            set(doubleClickAction.rawValue, "doubleClickAction")
        }
    }
    public var doubleClickChat: DoubleClickAction {
        get { doubleClickAction }
        set { doubleClickAction = newValue }
    }
    @Published public var remindDefault: RemindCondition {
        didSet {
            guard canMutate({ remindDefault = oldValue }) else { return }
            set(remindDefault.rawValue, "remindDefault")
        }
    }
    @Published public var archiveAfterReminder: Bool {
        didSet {
            guard canMutate({ archiveAfterReminder = oldValue }) else { return }
            set(archiveAfterReminder, "archiveAfterReminder")
        }
    }
    @Published public var markReadOnArchive: Bool {
        didSet {
            guard canMutate({ markReadOnArchive = oldValue }) else { return }
            set(markReadOnArchive, "markReadOnArchive")
        }
    }
    @Published public var afterArchive: AfterAction {
        didSet {
            guard canMutate({ afterArchive = oldValue }) else { return }
            set(afterArchive.rawValue, "afterArchive")
        }
    }
    @Published public var afterToggleRead: AfterAction {
        didSet {
            guard canMutate({ afterToggleRead = oldValue }) else { return }
            set(afterToggleRead.rawValue, "afterToggleRead")
        }
    }
    @Published public var requestNotifications: Bool {
        didSet {
            guard canMutate({ requestNotifications = oldValue }) else { return }
            set(requestNotifications, "requestNotifications")
            if notifications.requestNotificationsEnabled != requestNotifications {
                notifications.requestNotificationsEnabled = requestNotifications
            }
        }
    }
    @Published public var lastUsedReminder: Date? {
        didSet {
            guard canMutate({ lastUsedReminder = oldValue }) else { return }
            set(lastUsedReminder, "lastUsedReminder")
        }
    }
    /// "Notify when someone starts typing (supported platforms only)" (02 §1.5, off): one notification per burst of
    /// typing in a chat that would notify for a message (`NotificationPolicy.shouldNotifyTyping`).
    @Published public var typingNotifications: Bool {
        didSet {
            guard canMutate({ typingNotifications = oldValue }) else { return }
            set(typingNotifications, "typingNotifications")
            if notifications.typingNotificationsEnabled != typingNotifications {
                notifications.typingNotificationsEnabled = typingNotifications
            }
        }
    }
    /// Customizable time suggestions for Remind Me and Send Later (`setting:general Time suggestions`, min 1, max 8).
    @Published public var timeSuggestions: [String] {
        didSet {
            guard canMutate({ timeSuggestions = oldValue }) else { return }
            set(timeSuggestions, "timeSuggestions")
        }
    }
    public let notifications: NotificationPreferences

    /// The key a setting is kept under.
    public static func key(_ name: String) -> String { "courier.inbox." + name }

    private let defaults: UserDefaults
    private var isInitializing = true
    private var isRevertingLockedSetting = false

    private func canMutate(_ revert: () -> Void) -> Bool {
        guard !isInitializing, !isRevertingLockedSetting else { return false }
        guard AppLockGate.isCurrentActionAllowedForSettings else {
            isRevertingLockedSetting = true
            revert()
            isRevertingLockedSetting = false
            return false
        }
        return true
    }

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
        if let storedSuggestions = defaults.stringArray(forKey: Self.key("timeSuggestions")),
           !storedSuggestions.isEmpty {
            timeSuggestions = Array(storedSuggestions.prefix(ReminderPresets.maxSuggestionsCount))
        } else {
            timeSuggestions = ReminderPresets.defaultSuggestions
        }

        notifPrefs.onRequestNotificationsChanged = { [weak self] enabled in
            guard let self, self.requestNotifications != enabled else { return }
            self.requestNotifications = enabled
        }
        notifPrefs.onTypingNotificationsChanged = { [weak self] enabled in
            guard let self, self.typingNotifications != enabled else { return }
            self.typingNotifications = enabled
        }
        isInitializing = false
    }

    private func set(_ value: Any?, _ name: String) {
        if let value {
            defaults.set(value, forKey: Self.key(name))
        } else {
            defaults.removeObject(forKey: Self.key(name))
        }
    }

    @discardableResult
    public func addTimeSuggestion(_ raw: String) -> Bool {
        guard AppLockGate.isCurrentActionAllowedForSettings else { return false }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              timeSuggestions.count < ReminderPresets.maxSuggestionsCount,
              !timeSuggestions.contains(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame })
        else { return false }
        timeSuggestions.append(trimmed)
        return true
    }

    public func removeTimeSuggestion(_ suggestion: String) {
        guard AppLockGate.isCurrentActionAllowedForSettings else { return }
        guard timeSuggestions.count > ReminderPresets.minSuggestionsCount else { return }
        timeSuggestions.removeAll { $0 == suggestion }
    }

    public func resetTimeSuggestions() {
        guard AppLockGate.isCurrentActionAllowedForSettings else { return }
        timeSuggestions = ReminderPresets.defaultSuggestions
    }
}
