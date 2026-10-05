// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import VitruvianCore

/// A scroll as the gallery reads it. `NSEvent` is one; tests pass their own.
@MainActor
package protocol NotchScrollEvent {
    var locationInWindow: CGPoint { get }
    var scrollingDeltaY: CGFloat { get }
    var timestamp: TimeInterval { get }
    var hasPreciseScrollingDeltas: Bool { get }
    var phase: NSEvent.Phase { get }
    var momentumPhase: NSEvent.Phase { get }
    var modifierFlags: NSEvent.ModifierFlags { get }
}

extension NSEvent: NotchScrollEvent {}

/// The open island as the gallery's wheel sees it.
@MainActor
package struct NotchSectionScrollSurface {
    /// The island's window, in screen coordinates.
    package var frame: CGRect
    package var toScreen: (CGPoint) -> CGPoint
    /// Whether a screen point is on the island itself, not a transparent
    /// corner or a floating control.
    package var containsSurface: (CGPoint) -> Bool
    /// The open island's layout, whose header keeps its own gesture.
    package var geometry: NotchGeometry

    package init(frame: CGRect, toScreen: @escaping (CGPoint) -> CGPoint,
                 containsSurface: @escaping (CGPoint) -> Bool, geometry: NotchGeometry) {
        self.frame = frame
        self.toScreen = toScreen
        self.containsSurface = containsSurface
        self.geometry = geometry
    }
}

extension NotchSectionScroll {
    /// The rows one scroll steps the gallery by, or nil when the gallery
    /// leaves it to the island's gestures. `surface` is nil while the open
    /// island is not showing the gallery. A scroll the gallery does not take
    /// ends the sequence it was part of.
    @MainActor
    package mutating func route(_ event: some NotchScrollEvent, over surface: NotchSectionScrollSurface?) -> Int? {
        guard let surface,
              event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty else {
            self = Self()
            return nil
        }
        let screenPoint = surface.toScreen(event.locationInWindow)
        // The header keeps its own gesture; the tiles and the rest of the body step rows.
        guard surface.containsSurface(screenPoint),
              surface.frame.maxY - screenPoint.y > surface.geometry.headerBottom else {
            self = Self()
            return nil
        }
        return steps(deltaY: Double(event.scrollingDeltaY), timestamp: event.timestamp,
                     precise: event.hasPreciseScrollingDeltas, hasPhase: !event.phase.isEmpty,
                     began: event.phase.contains(.began),
                     ended: !event.phase.intersection([.ended, .cancelled]).isEmpty,
                     momentum: !event.momentumPhase.isEmpty)
    }
}
