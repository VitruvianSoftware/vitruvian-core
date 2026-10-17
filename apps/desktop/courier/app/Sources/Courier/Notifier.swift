// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import AppKit
import CourierCore
@preconcurrency import UserNotifications

/// The system's notification centre for the coordinator: shows a notification for a message, with "Mark as Read"
/// and an inline "Reply", and sends a click or a button back to the coordinator. Everything it decides is in
/// CourierCore; this only carries it out.
///
/// UNUserNotificationCenter aborts in a process that is not an app bundle (`swift run`, a bare binary), so every
/// use is behind `isAvailable`, and without a bundle the notifier does nothing.
@MainActor
final class Notifier: NSObject, NotificationDelivering, UNUserNotificationCenterDelegate {
    static let categoryID = "com.vitruviansoftware.courier.message"
    static let markReadActionID = "com.vitruviansoftware.courier.mark-read"
    static let replyActionID = "com.vitruviansoftware.courier.reply"

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
        let markRead = UNNotificationAction(identifier: Self.markReadActionID,
                                            title: String(localized: "Mark as Read"), options: [])
        let reply = UNTextInputNotificationAction(
            identifier: Self.replyActionID, title: String(localized: "Reply"), options: [],
            textInputButtonTitle: String(localized: "Send"),
            textInputPlaceholder: String(localized: "Message"))
        center.setNotificationCategories([
            UNNotificationCategory(identifier: Self.categoryID, actions: [reply, markRead], intentIdentifiers: [],
                                   options: []),
        ])
        return center
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
        message.sound = .default
        message.threadIdentifier = content.threadIdentifier
        message.categoryIdentifier = Self.categoryID
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
            case UNNotificationDefaultActionIdentifier:
                coordinator?.open(roomID: roomID)
            default:
                break
            }
        }
    }
}
