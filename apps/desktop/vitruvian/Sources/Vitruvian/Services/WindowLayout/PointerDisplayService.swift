// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import VitruvianCore
import VitruvianDesign

/// Sends the pointer to the centre of the next display on a shortcut, in the
/// same order Next display cycles through. Warping the pointer needs no
/// permission.
@MainActor
package final class PointerDisplayService: ObservableObject {
    package static let shared = PointerDisplayService()

    @Published package private(set) var shortcutRegistrationFailed = false

    private let hotkey = QuickToolHotkey(id: 80)

    private init() {
        hotkey.onPress = { [weak self] in self?.moveToNextDisplay() }
    }

    package func syncWithPreferences() {
        let enabled = AppFeature.windowLayout.isAvailable
            && UserDefaults.standard.bool(forKey: DefaultsKey.pointerDisplayEnabled)
        // Like Window Layout's other keys, this one steps aside while an app
        // from Ignore apps is in front, so the key reaches that app.
        let front = NSWorkspace.shared.frontmostApplication
        let paused = WindowLayoutIgnoredApps.shared.contains(bundleID: front?.bundleIdentifier,
                                                             executablePath: front?.executableURL?.path)
        shortcutRegistrationFailed = !hotkey.sync(enabled: enabled && !paused,
                                                  shortcut: GlobalShortcutRole.pointerNextDisplay.savedShortcut,
                                                  storageKey: DefaultsKey.pointerDisplayShortcut)
    }

    package func suspend() {
        hotkey.unregister()
    }

    package func moveToNextDisplay() {
        let screens = NSScreen.screens
        // NSMouseInRect, like the brightness shortcuts: frame.contains misses
        // a pointer resting on a display's top edge.
        guard let currentIndex = screens.firstIndex(where: { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }),
              let target = WindowLayoutGeometry.adjacentDisplayIndex(currentIndex: currentIndex,
                                                                      frames: screens.map(\.frame),
                                                                      movingForward: true)
        else { return }
        let displayID = screens[target].displayID
        guard displayID != 0 else { return }
        let bounds = CGDisplayBounds(displayID)
        CGWarpMouseCursorPosition(CGPoint(x: bounds.midX, y: bounds.midY))
        // Without this the next physical movement can snap the pointer back
        // to where it was before the warp.
        CGAssociateMouseAndMouseCursorPosition(1)
    }
}
