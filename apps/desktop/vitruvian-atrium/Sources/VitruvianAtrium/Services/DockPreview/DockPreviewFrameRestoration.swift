// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import VitruvianCore
import VitruvianDesign

/// Captured before the temporary Dock preference can change any window bounds.
/// Keep all visible windows so moving between Dock icons retains the same baseline.
package struct DockPreviewFrameRestoration {
    private let windows: [[String: Any]]
    private let screens: [Screen]

    /// A display as it was when the hold began, in Accessibility coordinates.
    package struct Screen: Sendable {
        package let id: CGDirectDisplayID
        package var frame: CGRect
        package var visibleFrame: CGRect

        package init(id: CGDirectDisplayID, frame: CGRect, visibleFrame: CGRect) {
            self.id = id
            self.frame = frame
            self.visibleFrame = visibleFrame
        }
    }

    /// What restoring a window asks of the system: a display's frames now,
    /// in Accessibility coordinates, the frontmost process, the focused
    /// window, the restore itself, and the wait between checks. `system`
    /// reads AppKit and the window activator and waits on the main queue.
    package struct RestoreHost: Sendable {
        package typealias Frames = (frame: CGRect, visibleFrame: CGRect)
        package var screen: @MainActor @Sendable (CGDirectDisplayID) -> Frames?
        package var frontmostPID: @MainActor @Sendable () -> pid_t?
        package var focusedWindow: @MainActor @Sendable (pid_t) -> CGWindowID?
        package var restore: @MainActor @Sendable (SwitcherItem, _ original: CGRect, _ heldVisibleFrame: CGRect) -> Void
        package var after: @Sendable (TimeInterval, @escaping @MainActor @Sendable () -> Void) -> Void

        package init(screen: @escaping @MainActor @Sendable (CGDirectDisplayID) -> Frames?,
                     frontmostPID: @escaping @MainActor @Sendable () -> pid_t?,
                     focusedWindow: @escaping @MainActor @Sendable (pid_t) -> CGWindowID?,
                     restore: @escaping @MainActor @Sendable (SwitcherItem, CGRect, CGRect) -> Void,
                     after: @escaping @Sendable (TimeInterval, @escaping @MainActor @Sendable () -> Void) -> Void) {
            self.screen = screen
            self.frontmostPID = frontmostPID
            self.focusedWindow = focusedWindow
            self.restore = restore
            self.after = after
        }

        package static var system: RestoreHost {
            RestoreHost(
                screen: { id in
                    DockPreviewFrameRestoration.screen(id).map {
                        (DockPreviewFrameRestoration.axFrame($0.frame),
                         DockPreviewFrameRestoration.axFrame($0.visibleFrame))
                    }
                },
                frontmostPID: { NSWorkspace.shared.frontmostApplication?.processIdentifier },
                focusedWindow: { WindowActivator.focusedWindowID(for: $0) },
                restore: { WindowActivator.restoreFrameAfterDockHold($0, original: $1, heldVisibleFrame: $2) },
                after: { delay, work in DispatchQueue.main.asyncAfter(deadline: .now() + delay) { work() } })
        }
    }

    package init() {
        windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                             kCGNullWindowID) as? [[String: Any]] ?? []
        screens = NSScreen.screens.compactMap { screen in
            guard let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
            else { return nil }
            return Screen(id: id.uint32Value, frame: Self.axFrame(screen.frame),
                          visibleFrame: Self.axFrame(screen.visibleFrame))
        }
    }

    package func restoration(for item: SwitcherItem, isCurrent: @escaping @MainActor @Sendable () -> Bool) -> (() -> Void)? {
        guard let windowID = item.windowID, !item.isFullscreen, !item.isMinimized,
              !item.isOnHiddenSpace,
              let window = windows.first(where: {
                  ($0[kCGWindowNumber as String] as? NSNumber)?.uint32Value == windowID
                      && ($0[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == item.windowOwnerPID
              }),
              let bounds = window[kCGWindowBounds as String] as? [String: Any],
              let original = CGRect(dictionaryRepresentation: bounds as CFDictionary),
              let screen = screens.first(where: { $0.visibleFrame.contains(original) }),
              let currentScreen = Self.screen(screen.id)
        else { return nil }
        let heldVisibleFrame = Self.axFrame(currentScreen.visibleFrame)
        guard heldVisibleFrame != screen.visibleFrame,
              !heldVisibleFrame.contains(original) else { return nil }

        // Activation is immediate. Repair only after the work area has recovered,
        // and only if this exact window still owns focus and was Dock-constrained.
        return {
            Self.restore(item, original: original, screen: screen,
                         heldVisibleFrame: heldVisibleFrame, isCurrent: isCurrent, attempt: 0)
        }
    }

    package static func restore(_ item: SwitcherItem, original: CGRect, screen: Screen,
                                heldVisibleFrame: CGRect, isCurrent: @escaping @MainActor @Sendable () -> Bool,
                                attempt: Int, host: RestoreHost = .system) {
        host.after(attempt == 0 ? 0.15 : 0.05) {
            guard isCurrent(), let currentScreen = host.screen(screen.id),
                  currentScreen.frame == screen.frame,
                  host.frontmostPID() == item.pid,
                  host.focusedWindow(item.windowOwnerPID) == item.windowID
            else { return }
            guard currentScreen.visibleFrame == screen.visibleFrame else {
                if attempt < 15 {
                    restore(item, original: original, screen: screen,
                            heldVisibleFrame: heldVisibleFrame, isCurrent: isCurrent, attempt: attempt + 1, host: host)
                }
                return
            }
            host.restore(item, original, heldVisibleFrame)
        }
    }

    private static func screen(_ id: CGDirectDisplayID) -> NSScreen? {
        NSScreen.screens.first {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == id
        }
    }

    private static func axFrame(_ rect: CGRect) -> CGRect {
        let top = NSScreen.screens.first?.frame.maxY ?? 0
        return CGRect(x: rect.minX, y: top - rect.maxY, width: rect.width, height: rect.height)
    }
}
