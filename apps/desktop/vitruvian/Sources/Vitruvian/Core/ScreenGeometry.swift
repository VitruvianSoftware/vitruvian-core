// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import AppKit

/// What placing something on a display reads of it. Placement decisions take
/// these instead of `NSScreen`, so they run against stand-in displays.
package struct ScreenGeometry: Equatable {
    package let displayID: CGDirectDisplayID
    package let frame: CGRect
    package let visibleFrame: CGRect
    package let scale: CGFloat

    package init(displayID: CGDirectDisplayID, frame: CGRect, visibleFrame: CGRect, scale: CGFloat) {
        self.displayID = displayID
        self.frame = frame
        self.visibleFrame = visibleFrame
        self.scale = scale
    }

    /// The display a pointer in AppKit's global coordinates is on, counting
    /// its top row and not the row below its bottom, else `fallback`.
    package static func under(_ point: CGPoint, among screens: [ScreenGeometry],
                              fallback: ScreenGeometry?) -> ScreenGeometry? {
        NSScreen.screen(containing: point, among: screens, frame: { $0.frame }, fallback: fallback)
    }
}

extension NSScreen {
    package var geometry: ScreenGeometry {
        ScreenGeometry(displayID: displayID, frame: frame, visibleFrame: visibleFrame, scale: backingScaleFactor)
    }

    /// Every attached display, in AppKit's order.
    package static var geometries: [ScreenGeometry] { screens.map(\.geometry) }
}
