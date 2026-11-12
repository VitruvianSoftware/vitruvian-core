// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import VitruvianCore
import VitruvianDesign
import VitruvianServices
import VitruvianUI

/// The module's own selection check with its desktop query passed in, and
/// the module's desktop-change observer on an isolated notification center.
/// No windows, system notifications, desktop changes or synthetic input are used.
enum DockPreviewScopeTests {
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

        // The production observer, on its own notification center.
        final class Preview {
            var isRunning = false
            var currentSpaceOnly = false
            var isDraggingWindow = false
            var sessionEnds = 0
        }
        let preview = Preview()
        let center = NotificationCenter()
        let desktopChanged = Notification.Name("test.desktop.changed")
        let observation = DockPreviewSpaceObservation(
            center: center, name: desktopChanged,
            state: {
                .init(isRunning: preview.isRunning, currentSpaceOnly: preview.currentSpaceOnly,
                      isDraggingWindow: preview.isDraggingWindow)
            },
            endSession: { preview.sessionEnds += 1 })
        func changeDesktop() {
            center.post(name: desktopChanged, object: nil)
        }
        preview.currentSpaceOnly = true
        observation.sync()
        suite.expect(!observation.isObserving, "a disabled preview does not observe desktop changes")
        preview.isRunning = true
        observation.sync()
        observation.sync()
        changeDesktop()
        suite.expect(preview.sessionEnds == 1, "one desktop change ends the open session exactly once")
        observation.sync()
        changeDesktop()
        suite.expect(preview.sessionEnds == 2,
               "changing another preference cannot leave the next desktop list stale")
        preview.isDraggingWindow = true
        changeDesktop()
        suite.expect(preview.sessionEnds == 2, "a window being dragged can still be carried to another desktop")
        preview.isDraggingWindow = false
        preview.currentSpaceOnly = false
        observation.sync()
        changeDesktop()
        suite.expect(!observation.isObserving && preview.sessionEnds == 2,
               "all-desktop previews keep their session and stop observing desktop changes")
        preview.currentSpaceOnly = true
        observation.sync()
        preview.isRunning = false
        changeDesktop()
        suite.expect(preview.sessionEnds == 2, "a queued desktop notification cannot act after disabling previews")
        observation.stop()
        suite.expect(!observation.isObserving, "stopping the tap removes desktop observation")
        preview.isRunning = true
        observation.sync()
        changeDesktop()
        suite.expect(preview.sessionEnds == 3, "re-enabling scoped previews restores exactly one observer")
        observation.stop()
    }
}
