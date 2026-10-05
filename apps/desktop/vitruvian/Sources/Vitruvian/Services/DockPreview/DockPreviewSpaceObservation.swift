// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import AppKit

/// While previews list only the current desktop's windows, a desktop change
/// ends the open session: the list and any hover prefetched on the old
/// desktop. There is at most one observer, removed once previews stop or list
/// every desktop.
@MainActor
package final class DockPreviewSpaceObservation {
    /// What the preview reports when it syncs and when a change arrives.
    package struct State {
        package var isRunning: Bool
        package var currentSpaceOnly: Bool
        package var isDraggingWindow: Bool

        package init(isRunning: Bool, currentSpaceOnly: Bool, isDraggingWindow: Bool) {
            self.isRunning = isRunning
            self.currentSpaceOnly = currentSpaceOnly
            self.isDraggingWindow = isDraggingWindow
        }
    }

    private let center: NotificationCenter
    private let name: Notification.Name
    private let state: () -> State
    private let endSession: () -> Void
    private var observer: NSObjectProtocol?

    package var isObserving: Bool { observer != nil }

    package init(center: NotificationCenter = NSWorkspace.shared.notificationCenter,
                 name: Notification.Name = NSWorkspace.activeSpaceDidChangeNotification,
                 state: @escaping () -> State, endSession: @escaping () -> Void) {
        self.center = center
        self.name = name
        self.state = state
        self.endSession = endSession
    }

    package func sync() {
        let current = state()
        guard current.isRunning, current.currentSpaceOnly else {
            stop()
            return
        }
        guard observer == nil else { return }
        observer = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            // Delivered on the main queue.
            MainActor.assumeIsolated {
                guard let self else { return }
                let current = self.state()
                // A window being dragged can still be carried to another desktop.
                guard current.isRunning, current.currentSpaceOnly, !current.isDraggingWindow else { return }
                // Pinned panels keep their existing refresh cycle.
                self.endSession()
            }
        }
    }

    package func stop() {
        if let observer {
            center.removeObserver(observer)
        }
        observer = nil
    }
}
