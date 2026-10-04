// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import VitruvianCore
import VitruvianDesign
import VitruvianServices
import VitruvianUI

/// The module's own selection check with its desktop query passed in, and
/// production observation methods with an isolated notification center. No
/// windows, system notifications, desktop changes or synthetic input are used.
enum DockPreviewScopeTests {
    enum NSWorkspace {
        static let shared = Workspace()
        static let activeSpaceDidChangeNotification = Notification.Name("test.desktop.changed")
    }

    final class Workspace {
        let notificationCenter = NotificationCenter()
    }

    final class Service {
        typealias NSWorkspace = DockPreviewScopeTests.NSWorkspace
        var isRunning = false
        var currentSpaceOnly = false
        var isDraggingWindow = false
        var spaceChangeObserver: NSObjectProtocol?
        var sessionEnds = 0
        var pendingHover = false
        var windows = [1]

        func endSession() {
            sessionEnds += 1
            pendingHover = false
            windows = []
        }
    }

    static func run(_ suite: TestSuite) {
        var hidden = false, queries = 0
        func mayActivate(currentSpaceOnly: Bool) -> Bool {
            WindowEnumerator.dockPreviewMayActivate(windowID: 1, currentSpaceOnly: currentSpaceOnly) { _ in
                queries += 1
                return hidden
            }
        }
        suite.expect(mayActivate(currentSpaceOnly: true), "a current-desktop window can be selected")
        hidden = true
        suite.expect(!mayActivate(currentSpaceOnly: true),
               "a window moved off desktop cannot be selected before the panel refreshes")
        queries = 0
        suite.expect(mayActivate(currentSpaceOnly: false) && queries == 0,
               "all-desktop mode allows travel without an extra scope query")
        hidden = false
        suite.expect(mayActivate(currentSpaceOnly: true),
               "returning to the window's desktop restores selection without stale history")
        queries = 0
        let windowless = WindowEnumerator.dockPreviewMayActivate(windowID: nil, currentSpaceOnly: true) { _ in
            queries += 1
            return true
        }
        suite.expect(windowless && queries == 0, "an item with no window is never asked about")

        let service = Service()
        let center = NSWorkspace.shared.notificationCenter
        func changeDesktop() {
            center.post(name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
        }
        service.currentSpaceOnly = true
        service.syncSpaceObservation()
        suite.expect(service.spaceChangeObserver == nil, "a disabled preview does not observe desktop changes")
        service.isRunning = true
        service.syncSpaceObservation()
        service.syncSpaceObservation()
        service.pendingHover = true
        changeDesktop()
        suite.expect(service.sessionEnds == 1 && service.windows.isEmpty && !service.pendingHover,
               "one desktop change dismisses the old list and invalidates its prefetched hover exactly once")
        service.windows = [2]
        service.syncSpaceObservation()
        changeDesktop()
        suite.expect(service.sessionEnds == 2 && service.windows.isEmpty,
               "changing another preference cannot leave the next desktop list stale")
        service.isDraggingWindow = true
        changeDesktop()
        suite.expect(service.sessionEnds == 2, "a window being dragged can still be carried to another desktop")
        service.isDraggingWindow = false
        service.currentSpaceOnly = false
        service.syncSpaceObservation()
        changeDesktop()
        suite.expect(service.spaceChangeObserver == nil && service.sessionEnds == 2,
               "all-desktop previews keep their session and stop observing desktop changes")
        service.currentSpaceOnly = true
        service.syncSpaceObservation()
        service.isRunning = false
        changeDesktop()
        suite.expect(service.sessionEnds == 2, "a queued desktop notification cannot act after disabling previews")
        service.stopSpaceObservation()
        suite.expect(service.spaceChangeObserver == nil, "stopping the tap removes desktop observation")
        service.isRunning = true
        service.syncSpaceObservation()
        changeDesktop()
        suite.expect(service.sessionEnds == 3, "re-enabling scoped previews restores exactly one observer")
        service.stopSpaceObservation()
    }
}
