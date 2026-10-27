// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import AppKit
import CourierCore
import UniformTypeIdentifiers
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
    static let messageOTPCategoryID = "com.vitruviansoftware.courier.message-otp"
    static let reminderCategoryID = "com.vitruviansoftware.courier.reminder"
    static let scheduledCategoryID = "com.vitruviansoftware.courier.scheduled"
    static let typingCategoryID = "com.vitruviansoftware.courier.typing"
    static let copyCodeActionID = "com.vitruviansoftware.courier.copy-code"
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
        case .copyCode:
            UNNotificationAction(identifier: Self.copyCodeActionID, title: String(localized: "Copy Code"), options: [])
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
        case .messageOTP: messageOTPCategoryID
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
        message.sound = Self.notificationSound(for: content.sound, category: content.category)
        message.threadIdentifier = content.threadIdentifier
        message.categoryIdentifier = Self.categoryID(of: content.category)
        message.userInfo = content.userInfo
        var preparedAttachment: PreparedNotificationAttachment?
        if let attachmentPath = content.attachmentPath,
           let prepared = Self.prepareAttachment(from: attachmentPath, identifier: content.eventID) {
            message.attachments = [prepared.attachment]
            preparedAttachment = prepared
        }
        // The event's id is the request's, so the same event shown twice replaces itself.
        center.add(UNNotificationRequest(identifier: content.eventID, content: message, trigger: nil)) { _ in
            preparedAttachment?.cleanup()
        }
    }

    /// Clones `path` to a temporary file URL so `UNNotificationAttachment` can move it without touching `media.Store`.
    static func makeAttachment(from path: String, identifier: String, mimeType: String? = nil) -> UNNotificationAttachment? {
        prepareAttachment(from: path, identifier: identifier, mimeType: mimeType)?.attachment
    }

    struct PreparedNotificationAttachment {
        let attachment: UNNotificationAttachment
        let tempDirectory: URL
        let options: [AnyHashable: Any]
        let cleanup: () -> Void
    }

    static func prepareAttachment(
        from path: String,
        identifier: String,
        mimeType: String? = nil
    ) -> PreparedNotificationAttachment? {
        let fm = FileManager.default
        guard !path.isEmpty, fm.fileExists(atPath: path) else { return nil }
        let srcURL = URL(fileURLWithPath: path)
        let resolvedType = resolveUTType(for: srcURL, mimeType: mimeType)
        let ext: String
        if !srcURL.pathExtension.isEmpty {
            ext = srcURL.pathExtension
        } else if let preferredExt = resolvedType?.preferredFilenameExtension {
            ext = preferredExt
        } else {
            ext = "jpg"
        }
        var options: [AnyHashable: Any] = [:]
        if let resolvedType {
            options[UNNotificationAttachmentOptionsTypeHintKey] = resolvedType.identifier
        }
        let tempDir = fm.temporaryDirectory.appendingPathComponent("courier-notif-\(UUID().uuidString)", isDirectory: true)
        do {
            try fm.createDirectory(at: tempDir, withIntermediateDirectories: true)
            let tempURL = tempDir.appendingPathComponent("attachment.\(ext)")
            try fm.copyItem(at: srcURL, to: tempURL)
            let attachment = try UNNotificationAttachment(
                identifier: identifier,
                url: tempURL,
                options: options.isEmpty ? nil : options
            )
            return PreparedNotificationAttachment(
                attachment: attachment,
                tempDirectory: tempDir,
                options: options,
                cleanup: {
                    try? FileManager.default.removeItem(at: tempDir)
                }
            )
        } catch {
            try? fm.removeItem(at: tempDir)
            return nil
        }
    }

    private static func resolveUTType(for url: URL, mimeType: String?) -> UTType? {
        if let mime = mimeType?.trimmingCharacters(in: .whitespacesAndNewlines),
           !mime.isEmpty,
           let utType = UTType(mimeType: mime) {
            return utType
        }
        if !url.pathExtension.isEmpty,
           let utType = UTType(filenameExtension: url.pathExtension) {
            return utType
        }
        if let handle = try? FileHandle(forReadingFrom: url) {
            defer { try? handle.close() }
            if let header = try? handle.read(upToCount: 16), header.count >= 4 {
                let bytes = [UInt8](header)
                if bytes.count >= 8, bytes[0...7] == [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A] {
                    return .png
                }
                if bytes[0...2] == [0xFF, 0xD8, 0xFF] {
                    return .jpeg
                }
                if bytes[0...3] == [0x47, 0x49, 0x46, 0x38] {
                    return .gif
                }
                if bytes.count >= 12,
                   bytes[0...3] == [0x52, 0x49, 0x46, 0x46],
                   bytes[8...11] == [0x57, 0x45, 0x42, 0x50] {
                    return .webP
                }
                if bytes[0...3] == [0x25, 0x50, 0x44, 0x46] {
                    return .pdf
                }
                if bytes.count >= 8, bytes[4...7] == [0x66, 0x74, 0x79, 0x70] {
                    return .mpeg4Movie
                }
            }
        }
        return nil
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
            case Self.copyCodeActionID:
                coordinator?.copyOTPCode(forRoomID: roomID)
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

    static func notificationSound(for choice: NotificationSoundChoice, category: NotificationCategory) -> UNNotificationSound? {
        guard category != .typing else { return nil }
        switch choice {
        case .none:
            return nil
        case .default:
            return .default
        case .beeper, .sounds, .double, .dreams, .not, .marimba, .rain, .harp, .record, .spirit:
            return UNNotificationSound(named: UNNotificationSoundName("\(choice.rawValue).caf"))
        }
    }

    /// Opens the macOS System Settings Notifications pane.
    func openSystemNotificationSettings(openURL: (URL) -> Void = { _ = NSWorkspace.shared.open($0) }) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") {
            openURL(url)
        }
    }

    /// Re-registers Courier's notification categories and delegate with the system notification center.
    func restartNotificationCenter() {
        started = false
        _ = start()
    }
}

/// Copies one-time verification codes to the general pasteboard with concealed and transient markers.
@MainActor
final class PasteboardClipboardSink: ClipboardSink {
    static let concealedType = NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")
    static let transientType = NSPasteboard.PasteboardType("org.nspasteboard.TransientType")

    private let pasteboard: NSPasteboard

    init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
    }

    func copyOTP(_ code: String) {
        pasteboard.clearContents()
        pasteboard.setString(code, forType: .string)
        pasteboard.setData(Data(), forType: Self.concealedType)
        pasteboard.setData(Data(), forType: Self.transientType)
    }
}

/// Plays in-app message sent/received sound effects at the configured volume.
@MainActor
final class SoundEffectPlayer: SoundEffectPlaying {
    private let backend: @MainActor (SoundEffectEvent, Float) -> Void

    init(backend: @escaping @MainActor (SoundEffectEvent, Float) -> Void = SoundEffectPlayer.defaultBackend) {
        self.backend = backend
    }

    func play(_ effect: SoundEffectEvent, volume: Double) {
        let clamped = Float(min(1.0, max(0.0, volume)))
        guard clamped > 0 else { return }
        backend(effect, clamped)
    }

    private static func defaultBackend(effect: SoundEffectEvent, volume: Float) {
        let name = effect == .messageSent ? "Hero" : "Tink"
        guard let sound = NSSound(named: NSSound.Name(name))?.copy() as? NSSound else { return }
        sound.volume = volume
        sound.play()
    }
}
