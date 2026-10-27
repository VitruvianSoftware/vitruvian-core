// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import AppKit

/// A window offscreen only to change displays. The music wave reads this
/// and keeps its pose instead of falling to dots.
@MainActor
package protocol NotchWaveHold: AnyObject {
    var holdsWave: Bool { get }
}

package enum NotchWave {
    /// Posted on a panel's window when it starts or stops holding the wave, so
    /// the bars under it redraw at once rather than at the next visibility change.
    package static let holdNotification = Notification.Name("NotchEqualizerHoldWave")
}

/// The bars of a music wave as the island's windows move them between
/// displays: drawn in their present pose, read, taken over and let go. The
/// view that draws them lives in UI, which this layer cannot name.
@MainActor
package protocol NotchWavePosing: AnyObject {
    func refreshMotion()
    func barHeights() -> [CGFloat]
    func adopt(heights: [CGFloat])
    func releasePose()
}

extension NSView {
    /// The equalizers under this view draw their present pose. A hosting view
    /// keeps them as descendants, including a copy another display is showing.
    package func refreshEqualizerMotion() {
        (self as? NotchWavePosing)?.refreshMotion()
        subviews.forEach { $0.refreshEqualizerMotion() }
    }

    package func collectEqualizerHeights() -> [[CGFloat]] {
        var found: [[CGFloat]] = []
        if let bars = self as? NotchWavePosing { found.append(bars.barHeights()) }
        subviews.forEach { found.append(contentsOf: $0.collectEqualizerHeights()) }
        return found
    }

    package func adoptEqualizerHeights(_ heights: [[CGFloat]]) {
        var remaining = heights
        adoptEqualizerHeights(from: &remaining)
    }

    private func adoptEqualizerHeights(from heights: inout [[CGFloat]]) {
        if let bars = self as? NotchWavePosing, !heights.isEmpty {
            bars.adopt(heights: heights.removeFirst())
        }
        subviews.forEach { $0.adoptEqualizerHeights(from: &heights) }
    }

    package func releaseEqualizerPose() {
        (self as? NotchWavePosing)?.releasePose()
        subviews.forEach { $0.releaseEqualizerPose() }
    }
}
