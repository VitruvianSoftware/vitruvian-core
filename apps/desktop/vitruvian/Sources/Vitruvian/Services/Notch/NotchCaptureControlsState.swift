// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import Foundation

/// The capture controls the island hosts while a screenshot or recording
/// selection is up: the options they edit, whether they wait compact around
/// the camera, whether a selection is being dragged, and how to cancel. It
/// decides which clicks the controls take and what the pointer's comings and
/// goings do to them. `NotchService` keeps the window, the timers and the
/// hover, and applies what this returns.
package struct NotchCaptureControlsState {
    package private(set) var options: ScreenCaptureSelectionOptions?
    package private(set) var collapsed = false
    /// A selection is being dragged; the controls stay compact and let every
    /// click through.
    package private(set) var selectionInProgress = false
    package private(set) var cancel: (() -> Void)?

    package init() {}

    /// What the pointer moving over or off the controls asks of the island.
    package enum HoverResponse: Equatable {
        case none
        /// The pointer is on open controls: their closing waits.
        case keepOpen
        /// The pointer left open controls: they close after the hover exit delay.
        case closeSoon
        /// Open controls the pointer never reached close after their own delay.
        case closeLater
        /// The pointer left compact controls before they opened.
        case cancelOpening
        /// The pointer rests on compact controls: they open after the hover delay.
        case openSoon
    }

    /// The controls appear compact around the camera, clear of what is being
    /// captured, and open while the pointer rests on them.
    package mutating func begin(_ options: ScreenCaptureSelectionOptions, cancel: @escaping () -> Void) {
        self.options = options
        self.cancel = cancel
        collapsed = true
        selectionInProgress = false
    }

    package mutating func end() {
        options = nil
        collapsed = false
        selectionInProgress = false
        cancel = nil
    }

    package mutating func collapse() {
        collapsed = true
    }

    package mutating func expand() {
        collapsed = false
    }

    package mutating func setSelectionInProgress(_ active: Bool) {
        selectionInProgress = active
    }

    /// Shown, and no selection is being dragged.
    package var canExpand: Bool {
        options != nil && !selectionInProgress
    }

    /// Whether the controls take a click at the pointer. Only shown, visible
    /// controls do; everywhere else the click falls through to the selection
    /// beneath. While collapsing, the window still reserves the open frame, so
    /// compact controls take only their own hover area.
    package func takesMouse(overWindow: @autoclosure () -> Bool, overHoverArea: @autoclosure () -> Bool) -> Bool {
        options != nil && !selectionInProgress && overWindow() && (!collapsed || overHoverArea())
    }

    /// Whether open controls may close now: no selection is being dragged,
    /// no control has focus and the pointer is away.
    package func mayCollapse(focused: Bool, pointerInside: Bool) -> Bool {
        options != nil && !collapsed && !selectionInProgress && !focused && !pointerInside
    }

    /// What the pointer moving from `wasInside` to `inside` asks of the
    /// island, given its pending closing and opening and whether a click
    /// suppressed hovering.
    package func hoverResponse(inside: Bool, wasInside: Bool, closingPending: Bool, openingPending: Bool,
                               suppressed: Bool) -> HoverResponse {
        guard options != nil, !selectionInProgress else { return .none }
        if !collapsed {
            if inside { return .keepOpen }
            // Leaving closes them, as it closes an island opened by hover.
            if wasInside { return .closeSoon }
            return closingPending ? .none : .closeLater
        }
        if inside == wasInside, openingPending { return .none }
        return inside && !suppressed ? .openSoon : .cancelOpening
    }
}
