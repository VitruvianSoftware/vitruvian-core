// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import AppKit
import CourierCore
@preconcurrency import UserNotifications

/// The system's notification centre for the coordinator: shows a notification for a message or a reminder, with
/// "Mark as Read", an inline "Reply" (messages only) and "Remind in 1 Hour" / "Remind in 8 Hours" (with a plan that
/// includes reminders), and sends a click or a button back to the coordinator. Everything it decides is in
/// CourierCore; this only carries it out.
///
/// UNUserNotificationCenter aborts in a process that is not an app bundle (`swift run`, a bare binary), so every
/// use is behind `isAvailable`, and without a bundle the notifier does nothing.
@MainActor
final class Notifier: NSObject, NotificationDelivering, UNUserNotificationCenterDelegate {
    static let categoryID = "com.vitruviansoftware.courier.message"
    static let reminderCategoryID = "com.vitruviansoftware.courier.reminder"
    static let scheduledCategoryID = "com.vitruviansoftware.courier.scheduled"
    static let typingCategoryID = "com.vitruviansoftware.courier.typing"
    static let markReadActionID = "com.vitruviansoftware.courier.mark-read"
    static let replyActionID = "com.vitruviansoftware.courier.reply"
    static let remindOneHourActionID = "com.vitruviansoftware.courier.remind-1h"
    static let remindEightHoursActionID = "com.vitruviansoftware.courier.remind-8h"

    /// Whether the plan includes reminders, which decides if the remind-later buttons are offered. Read when the
    /// categories are registered, at the first notification or permission request.
    var entitlement: any EntitlementProvider = AlwaysEntitled()

    /// Where clicks and buttons go. Set once, before the first notification can come.
    weak var coordinator: NotificationCoordinator?

    /// There is an app bundle to notify as.
    static var isAvailable: Bool {
        Bundle.main.bundleURL.pathExtension == "app" && Bundle.main.bundleIdentifier != nil
    }

    private var started = false

    /// Takes the delegate and registers the actions, once.
    private func start() -> UNUserNotificationCenter? {
        guard Self.isAvailable else { return nil }
        let center = UNUserNotificationCenter.current()
        guard !started else { return center }
        started = true
        center.delegate = self
        center.setNotificationCategories(Set(NotificationCategory.allCases.map(category)))
        return center
    }

    /// The system's category for one of ours, with the buttons the plan allows (`NotificationCategory.actions`).
    private func category(_ category: NotificationCategory) -> UNNotificationCategory {
        let actions = category.actions(entitlement: entitlement).map(action)
        return UNNotificationCategory(identifier: Self.categoryID(of: category), actions: actions,
                                      intentIdentifiers: [], options: [])
    }

    private func action(_ action: NotificationAction) -> UNNotificationAction {
        switch action {
        case .markRead:
            UNNotificationAction(identifier: Self.markReadActionID, title: String(localized: "Mark as Read"), options: [])
        case .reply:
            UNTextInputNotificationAction(
                identifier: Self.replyActionID, title: String(localized: "Reply"), options: [],
                textInputButtonTitle: String(localized: "Send"), textInputPlaceholder: String(localized: "Message"))
        case .remindOneHour:
            UNNotificationAction(identifier: Self.remindOneHourActionID,
                                 title: String(localized: "Remind in 1 Hour"), options: [])
        case .remindEightHours:
            UNNotificationAction(identifier: Self.remindEightHoursActionID,
                                 title: String(localized: "Remind in 8 Hours"), options: [])
        }
    }

    private static func categoryID(of category: NotificationCategory) -> String {
        switch category {
        case .message: categoryID
        case .reminder: reminderCategoryID
        case .scheduled: scheduledCategoryID
        case .typing: typingCategoryID
        }
    }

    // MARK: - NotificationDelivering

    func requestPermission() {
        guard let center = start() else { return }
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in
            // Refusing is the person's choice; the Dock badge and the inbox still work.
        }
    }

    func deliver(_ content: NotificationContent) {
        guard let center = start() else { return }
        let message = UNMutableNotificationContent()
        message.title = content.title
        if let subtitle = content.subtitle { message.subtitle = subtitle }
        message.body = content.body
        // Someone typing is a quiet heads-up; their message, when it comes, makes the sound.
        message.sound = content.category == .typing ? nil : .default
        message.threadIdentifier = content.threadIdentifier
        message.categoryIdentifier = Self.categoryID(of: content.category)
        message.userInfo = content.userInfo
        // The event's id is the request's, so the same event shown twice replaces itself.
        center.add(UNNotificationRequest(identifier: content.eventID, content: message, trigger: nil))
    }

    func clear(roomID: String) {
        guard let center = start() else { return }
        center.getDeliveredNotifications { delivered in
            let ids = delivered.filter { $0.request.content.threadIdentifier == roomID }.map(\.request.identifier)
            if !ids.isEmpty { center.removeDeliveredNotifications(withIdentifiers: ids) }
        }
    }

    func remove(notificationID: String) {
        guard let center = start() else { return }
        // Shown, or added a moment ago and not shown yet.
        center.removePendingNotificationRequests(withIdentifiers: [notificationID])
        center.removeDeliveredNotifications(withIdentifiers: [notificationID])
    }

    // MARK: - UNUserNotificationCenterDelegate

    /// A message for another chat shows even while Courier is in front.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification)
        async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse) async {
        let roomID = response.notification.request.content.userInfo["room_id"] as? String
        let action = response.actionIdentifier
        let typed = (response as? UNTextInputNotificationResponse)?.userText
        guard let roomID else { return }
        await MainActor.run {
            switch action {
            case Self.markReadActionID:
                Task { await coordinator?.markRead(roomID: roomID) }
            case Self.replyActionID:
                if let typed { Task { await coordinator?.reply(roomID: roomID, text: typed) } }
            case Self.remindOneHourActionID:
                Task { await coordinator?.remind(roomID: roomID, after: NotificationCoordinator.remindOneHour) }
            case Self.remindEightHoursActionID:
                Task { await coordinator?.remind(roomID: roomID, after: NotificationCoordinator.remindEightHours) }
            case UNNotificationDefaultActionIdentifier:
                coordinator?.open(roomID: roomID)
            default:
                break
            }
        }
    }
}
