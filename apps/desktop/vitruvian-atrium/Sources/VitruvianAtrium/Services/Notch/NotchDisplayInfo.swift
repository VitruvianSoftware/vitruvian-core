// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import AppKit

/// A display as the island reads it. `NotchService.Environment.displays`
/// lists them; a test can describe one without a screen.
package struct NotchDisplayInfo: Equatable {
    package var id: CGDirectDisplayID
    package var frame: CGRect
    package var visibleFrame: CGRect
    package var safeAreaTop: CGFloat
    /// The width of the camera housing between the menu bar's two halves, or
    /// 0 on a display without one.
    package var cameraWidth: CGFloat
    package var backingScale: CGFloat
    package var isBuiltIn: Bool
    /// The display the menu bar is on when displays share Spaces.
    package var hasMenuBar: Bool

    package init(id: CGDirectDisplayID, frame: CGRect, visibleFrame: CGRect, safeAreaTop: CGFloat,
                 cameraWidth: CGFloat, backingScale: CGFloat, isBuiltIn: Bool, hasMenuBar: Bool) {
        self.id = id
        self.frame = frame
        self.visibleFrame = visibleFrame
        self.safeAreaTop = safeAreaTop
        self.cameraWidth = cameraWidth
        self.backingScale = backingScale
        self.isBuiltIn = isBuiltIn
        self.hasMenuBar = hasMenuBar
    }

    @MainActor
    package init(screen: NSScreen) {
        let cameraWidth: CGFloat
        if let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            cameraWidth = max(0, right.minX - left.maxX)
        } else { cameraWidth = 0 }
        self.init(id: screen.notchDisplayID, frame: screen.frame, visibleFrame: screen.visibleFrame,
                  safeAreaTop: screen.safeAreaInsets.top, cameraWidth: cameraWidth,
                  backingScale: screen.backingScaleFactor,
                  isBuiltIn: CGDisplayIsBuiltin(screen.notchDisplayID) != 0,
                  hasMenuBar: NSScreen.withMenuBar == screen)
    }
}
