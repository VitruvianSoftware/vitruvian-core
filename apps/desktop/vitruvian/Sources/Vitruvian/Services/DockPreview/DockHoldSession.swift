// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import AppKit
import CoreGraphics
import VitruvianCore
import VitruvianDesign

/// A Dock preview that keeps an auto-hidden Dock visible: the hold itself, the
/// window geometry from before it, the key tap that ends it and the workspace
/// changes that end it. `DockPreviewService` owns one and supplies the system
/// through `Host`; tests pass doubles.
@MainActor
package final class DockHoldSession<Item> {
    /// Restores one window to where it was before the hold, if the Dock
    /// change moved it, while `isCurrent` holds.
    package typealias FrameRestorer = (_ item: Item, _ isCurrent: @escaping @MainActor @Sendable () -> Bool)
        -> (() -> Void)?

    /// What the session asks of the preview service and the system.
    @MainActor
    package struct Host {
        /// Starts the key tap that ends the hold; false when it cannot.
        package var startInputTap: () -> Bool
        package var stopInputTap: () -> Void
        /// Captures every window's geometry before the Dock moves.
        package var captureFrames: () -> FrameRestorer
        package var isRunning: () -> Bool
        /// Drops a pointer move already queued, so it cannot reopen the
        /// preview a key just ended.
        package var dropQueuedPointer: () -> Void
        /// Ends the preview, which releases the hold.
        package var endSession: () -> Void
        /// Whether the window's Space lets it come forward, and bringing it
        /// forward.
        package var mayActivate: (Item) -> Bool
        package var activate: (Item) -> Void
        /// Where the workspace changes in `endingNotifications` are posted.
        package var notificationCenter: NotificationCenter

        // Spelled out because a memberwise initializer never leaves its module.
        package init(startInputTap: @escaping () -> Bool, stopInputTap: @escaping () -> Void,
                     captureFrames: @escaping () -> FrameRestorer, isRunning: @escaping () -> Bool,
                     dropQueuedPointer: @escaping () -> Void, endSession: @escaping () -> Void,
                     mayActivate: @escaping (Item) -> Bool, activate: @escaping (Item) -> Void,
                     notificationCenter: NotificationCenter) {
            self.startInputTap = startInputTap
            self.stopInputTap = stopInputTap
            self.captureFrames = captureFrames
            self.isRunning = isRunning
            self.dropQueuedPointer = dropQueuedPointer
            self.endSession = endSession
            self.mayActivate = mayActivate
            self.activate = activate
            self.notificationCenter = notificationCenter
        }
    }

    /// The workspace changes that end a held preview.
    package static var endingNotifications: [Notification.Name] {
        [NSWorkspace.activeSpaceDidChangeNotification,
         NSWorkspace.willSleepNotification,
         NSWorkspace.sessionDidResignActiveNotification]
    }

    package let hold: DockAutohideHold
    private let host: Host
    private var frames: FrameRestorer?
    private var generation = 0
    private var observers: [NSObjectProtocol] = []

    package init(hold: DockAutohideHold, host: Host) {
        self.hold = hold
        self.host = host
    }

    /// Holds the Dock visible for this preview. Moving to another Dock icon
    /// keeps the hold, its observers and the geometry from before it.
    package func begin() {
        guard observers.isEmpty, host.startInputTap() else { return }
        generation &+= 1
        let frames = host.captureFrames()
        guard hold.begin() else {
            host.stopInputTap()
            return
        }
        self.frames = frames
        observers = Self.endingNotifications.map { name in
            host.notificationCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                // Delivered on the main queue.
                MainActor.assumeIsolated { self?.host.endSession() }
            }
        }
    }

    /// The key tap's event. A key, or losing the tap, ends the preview.
    package func handleInput(type: CGEventType) {
        guard hold.isHolding else { return }
        if type == .keyDown || type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            host.dropQueuedPointer()
            host.endSession()
        }
    }

    package func release() {
        // Restore before invalidating an active input callback: detaching the
        // tap must never let its key reach the system ahead of this write.
        hold.end()
        frames = nil
        host.stopInputTap()
        for observer in observers {
            host.notificationCenter.removeObserver(observer)
        }
        observers.removeAll()
    }

    /// Brings the chosen window forward. Under a hold its geometry from before
    /// the hold is captured first and repaired only after it is activated.
    package func commit(_ item: Item) {
        let generation = self.generation
        let restoreFrame = frames?(item) { [weak self] in
            guard let self else { return false }
            return self.host.isRunning() && self.generation == generation
        }
        host.endSession()
        guard host.mayActivate(item) else { return }
        host.activate(item)
        restoreFrame?()
    }
}
