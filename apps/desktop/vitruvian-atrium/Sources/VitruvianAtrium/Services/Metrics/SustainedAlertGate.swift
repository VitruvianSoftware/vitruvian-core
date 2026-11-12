// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import VitruvianCore
import VitruvianDesign

/// Decides when a reading over its limit deserves a notification.
///
/// A single sample proves nothing: a short burst can push the hottest core
/// sensor or the CPU load past the limit and be gone again before the panel
/// is even open. The alert waits for the reading to hold across separate
/// samples, one gate per metric.
package struct SustainedAlertGate {
    /// How long the reading has to hold.
    package static let sustainedSeconds: TimeInterval = 12

    private var heldSince: TimeInterval?
    private var lastReadingAt: TimeInterval?

    /// `readAt` is when the metric was actually read. The monitor keeps
    /// serving the last reading in between reads, and counting those repeats
    /// would let one burst age into an alert on its own. It comes from the
    /// system uptime clock, which stops while the Mac sleeps, so a sleep in
    /// the middle cannot pass for a long sustained stretch either.
    package mutating func shouldAlert(reading: Double?,
                              threshold: Double,
                              readAt: TimeInterval?) -> Bool {
        guard let reading, let readAt, reading >= threshold else {
            reset()
            return false
        }
        guard readAt != lastReadingAt else { return false }
        lastReadingAt = readAt
        guard let since = heldSince else {
            heldSince = readAt
            return false
        }
        return readAt - since >= Self.sustainedSeconds
    }

    package mutating func reset() {
        heldSince = nil
        lastReadingAt = nil
    }

    // Spelled out because a default initializer never leaves its module.
    package init() {}
}
