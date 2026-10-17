// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import AppKit
import CoreGraphics
import CourierCore

/// What macOS says about whether someone is at the Mac: the screen lock (the distributed notifications
/// com.apple.screenIsLocked / screenIsUnlocked), the display sleeping (NSWorkspace), and the time since the last
/// keyboard, mouse or trackpad input (the HID system's event source).
@MainActor
final class SystemPresence: PresenceSource {
    private(set) var isScreenLocked: Bool
    private(set) var isDisplayAsleep = false
    var onChange: (@MainActor () -> Void)?
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []

    init() {
        // The lock notifications only say when it changes; at launch the session itself says.
        let session = CGSessionCopyCurrentDictionary() as? [String: Any]
        isScreenLocked = (session?["CGSSessionScreenIsLocked"] as? Bool) ?? false

        let distributed = DistributedNotificationCenter.default()
        observe(distributed, Notification.Name("com.apple.screenIsLocked")) { $0.isScreenLocked = true }
        observe(distributed, Notification.Name("com.apple.screenIsUnlocked")) { $0.isScreenLocked = false }
        let workspace = NSWorkspace.shared.notificationCenter
        observe(workspace, NSWorkspace.screensDidSleepNotification) { $0.isDisplayAsleep = true }
        observe(workspace, NSWorkspace.screensDidWakeNotification) { $0.isDisplayAsleep = false }
    }

    var secondsSinceLastInput: TimeInterval {
        // kCGAnyInputEventType (~0): any keyboard, mouse or trackpad event, from the HID system (not just this app).
        guard let any = CGEventType(rawValue: ~0) else { return 0 }
        return CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: any)
    }

    private func observe(_ center: NotificationCenter, _ name: Notification.Name,
                         _ apply: @escaping @MainActor (SystemPresence) -> Void) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                apply(self)
                self.onChange?()
            }
        }
        observers.append((center, token))
    }
}
