// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import AppKit
import VitruvianCore

/// Follows whether this user is at an awake, unlocked Mac: system sleep,
/// display sleep, who owns the console, the lock screen and screen savers, as
/// the workspace and the distributed notification center announce them.
///
/// It only reports. What a change means for the island (suspending it, the
/// lock sounds, the timer) stays with `NotchService`, which applies each
/// change to its `NotchSessionState`.
///
/// The notification centers and the delivery queue are injected: the app uses
/// the system's centers and the main queue, and a test posts to centers of its
/// own and, with no queue, reads each change as it is posted.
package final class NotchSessionTracker {
    package typealias Change = (inout NotchSessionState) -> Void

    private let workspace: NotificationCenter
    private let distributed: NotificationCenter
    private let queue: OperationQueue?
    private var tokens: [(NotificationCenter, NSObjectProtocol)] = []

    package init(workspace: NotificationCenter = NSWorkspace.shared.notificationCenter,
                 distributed: NotificationCenter = DistributedNotificationCenter.default(),
                 queue: OperationQueue? = .main) {
        self.workspace = workspace
        self.distributed = distributed
        self.queue = queue
    }

    deinit { stop() }

    /// The session as the system reports it now: who owns the console and
    /// whether the screen is locked. Sleep and screen savers are only ever
    /// announced, so they start out false.
    package static func current() -> NotchSessionState {
        var state = NotchSessionState()
        state.onConsole = SessionActivity.shared.isActive
        state.locked = (CGSessionCopyCurrentDictionary() as? [String: Any])?["CGSSessionScreenIsLocked"] as? Bool ?? false
        return state
    }

    /// Reports each change until `stop()`. Starting again replaces the
    /// observers rather than adding a second set.
    package func start(_ report: @escaping (Change) -> Void) {
        stop()
        observe(workspace, NSWorkspace.willSleepNotification) { report { $0.sleeping = true } }
        observe(workspace, NSWorkspace.didWakeNotification) {
            // Sleep ends a screen saver even when its stop goes unannounced.
            report { $0.sleeping = false; $0.screenSaverRunning = false }
        }
        observe(workspace, NSWorkspace.screensDidSleepNotification) { report { $0.displaysSleeping = true } }
        observe(workspace, NSWorkspace.screensDidWakeNotification) { report { $0.displaysSleeping = false } }
        observe(workspace, NSWorkspace.sessionDidResignActiveNotification) { report { $0.onConsole = false } }
        observe(workspace, NSWorkspace.sessionDidBecomeActiveNotification) { report { $0.onConsole = true } }
        observe(distributed, Notification.Name("com.apple.screenIsLocked")) { report { $0.locked = true } }
        observe(distributed, Notification.Name("com.apple.screenIsUnlocked")) {
            // No screen saver outlasts an unlock, whether or not its stop was announced.
            report { $0.locked = false; $0.screenSaverRunning = false }
        }
        observe(distributed, Notification.Name("com.apple.screensaver.didstart")) { report { $0.screenSaverRunning = true } }
        observe(distributed, Notification.Name("com.apple.screensaver.didstop")) { report { $0.screenSaverRunning = false } }
    }

    package func stop() {
        tokens.forEach { $0.0.removeObserver($0.1) }
        tokens.removeAll()
    }

    private func observe(_ center: NotificationCenter, _ name: Notification.Name, action: @escaping () -> Void) {
        tokens.append((center, center.addObserver(forName: name, object: nil, queue: queue) { _ in action() }))
    }
}
