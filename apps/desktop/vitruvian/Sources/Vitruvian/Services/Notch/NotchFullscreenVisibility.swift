// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import AppKit
import VitruvianCore

/// The island stepping aside while its display shows a full-screen Space, an
/// opt-in. Stepping aside puts down whatever the island was doing, and hands
/// the volume and brightness keys back to the system until it returns.
@MainActor
package final class NotchFullscreenVisibility {
    /// The preference and the Spaces. The app passes `.system`.
    package struct Environment {
        package var hidesInFullscreen: @MainActor () -> Bool
        /// Whether a display shows a full-screen Space now, or nil when the
        /// Spaces cannot be read, which leaves the island reachable.
        package var showsFullscreen: @MainActor (CGDirectDisplayID) -> Bool?

        package init(hidesInFullscreen: @escaping @MainActor () -> Bool,
                     showsFullscreen: @escaping @MainActor (CGDirectDisplayID) -> Bool?) {
            self.hidesInFullscreen = hidesInFullscreen
            self.showsFullscreen = showsFullscreen
        }

        @MainActor package static var system: Environment {
            Environment(
                hidesInFullscreen: { UserDefaults.standard.bool(forKey: DefaultsKey.notchHideInFullscreen) },
                showsFullscreen: {
                    SpaceWindowBridge.topology()?.isFullscreen(on: $0,
                                                              separateSpaces: NSScreen.screensHaveSeparateSpaces)
                })
        }
    }

    /// The island's side.
    package struct Island {
        /// Whether the island is stepping aside now (`hiddenInFullscreen`).
        package var hidden: () -> Bool
        package var setHidden: (Bool) -> Void
        /// Running and not suspended.
        package var isActive: () -> Bool
        /// Stepping aside, in this order.
        package var cancelHover: () -> Void
        package var releaseDrag: () -> Void
        package var cancelCaptureControls: () -> Void
        package var dismissNotice: () -> Void
        package var collapse: () -> Void
        /// Who owns the volume and brightness keys follows the island.
        package var feedbackRoutingDidChange: () -> Void
        /// Following a change of Space or app.
        package var updateScreen: () -> Void
        package var updateFullscreenDisplays: () -> Void
        package var syncMirrors: () -> Void
        package var syncVisibleConsumers: () -> Void
        package var refreshPresentation: () -> Void

        package init(hidden: @escaping () -> Bool, setHidden: @escaping (Bool) -> Void,
                     isActive: @escaping () -> Bool,
                     cancelHover: @escaping () -> Void, releaseDrag: @escaping () -> Void,
                     cancelCaptureControls: @escaping () -> Void, dismissNotice: @escaping () -> Void,
                     collapse: @escaping () -> Void, feedbackRoutingDidChange: @escaping () -> Void,
                     updateScreen: @escaping () -> Void, updateFullscreenDisplays: @escaping () -> Void,
                     syncMirrors: @escaping () -> Void, syncVisibleConsumers: @escaping () -> Void,
                     refreshPresentation: @escaping () -> Void) {
            self.hidden = hidden
            self.setHidden = setHidden
            self.isActive = isActive
            self.cancelHover = cancelHover
            self.releaseDrag = releaseDrag
            self.cancelCaptureControls = cancelCaptureControls
            self.dismissNotice = dismissNotice
            self.collapse = collapse
            self.feedbackRoutingDidChange = feedbackRoutingDidChange
            self.updateScreen = updateScreen
            self.updateFullscreenDisplays = updateFullscreenDisplays
            self.syncMirrors = syncMirrors
            self.syncVisibleConsumers = syncVisibleConsumers
            self.refreshPresentation = refreshPresentation
        }
    }

    private let environment: Environment
    private let island: Island

    package init(environment: Environment, island: Island) {
        self.environment = environment
        self.island = island
    }

    /// The island is on `displayID`; step aside or come back as its Space asks.
    package func update(displayID: CGDirectDisplayID) {
        // The preference comes first, so the Spaces are not read while it is off.
        let hidden = environment.hidesInFullscreen() && environment.showsFullscreen(displayID) == true
        guard hidden != island.hidden() else { return }
        island.setHidden(hidden)
        if hidden {
            island.cancelHover()
            island.releaseDrag()
            island.cancelCaptureControls()
            island.dismissNotice()
            island.collapse()
        }
        // Space changes do not run a full preference sync. Restore volume
        // and brightness key routing when the island becomes eligible for
        // feedback again, and hand the keys back while it is away.
        island.feedbackRoutingDidChange()
    }

    /// The Space or the app in front changed.
    package func environmentDidChange() {
        // Only the opt-in option depends on Spaces and the active app.
        guard island.isActive(), island.hidden() || environment.hidesInFullscreen() else { return }
        let wasHidden = island.hidden()
        island.updateScreen()
        // Each copy follows full screen on its own display.
        island.updateFullscreenDisplays()
        island.syncMirrors()
        // An unchanged state must not cut short a transition on screen, such
        // as the island closing after a click in another app.
        guard island.hidden() != wasHidden else { return }
        island.syncVisibleConsumers()
        island.refreshPresentation()
    }
}
