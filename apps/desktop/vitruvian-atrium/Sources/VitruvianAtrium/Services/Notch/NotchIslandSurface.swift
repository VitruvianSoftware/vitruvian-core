// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import VitruvianCore

/// The island as a chooser begun from one of its pages sees it, to decide
/// whether it can still return there.
package struct NotchIslandSurface {
    package var window: (any IslandWindowing)?
    package var acceptsUserInteraction: Bool
    package var expanded: Bool
    package var selected: NotchModule
    package var showingAppPanel: Bool
    package var showingMetric: Bool
    package var showingCaptureControls: Bool

    package init(window: (any IslandWindowing)?, acceptsUserInteraction: Bool, expanded: Bool,
                 selected: NotchModule, showingAppPanel: Bool = false, showingMetric: Bool = false,
                 showingCaptureControls: Bool = false) {
        self.window = window
        self.acceptsUserInteraction = acceptsUserInteraction
        self.expanded = expanded
        self.selected = selected
        self.showingAppPanel = showingAppPanel
        self.showingMetric = showingMetric
        self.showingCaptureControls = showingCaptureControls
    }

    /// Whether `module`'s page is open on its own in `window`, which is still
    /// the island's, on screen and taking input.
    @MainActor
    package func shows(_ module: NotchModule, in window: any IslandWindowing) -> Bool {
        acceptsUserInteraction && self.window === window && window.isVisible
            && expanded && selected == module && !showingAppPanel
            && !showingMetric && !showingCaptureControls
    }

    @MainActor
    package static var current: NotchIslandSurface {
        let notch = NotchService.shared
        return NotchIslandSurface(window: notch.presentationWindow,
                                  acceptsUserInteraction: notch.acceptsUserInteraction,
                                  expanded: notch.expanded, selected: notch.selected,
                                  showingAppPanel: notch.showingAppPanel,
                                  showingMetric: notch.selectedMetric != nil,
                                  showingCaptureControls: notch.captureControls != nil)
    }
}
