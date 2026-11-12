// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import Foundation
import VitruvianCore
import VitruvianDesign
import VitruvianServices
import VitruvianUI

/// The capture controls' state (`NotchCaptureControlsState`) on its own: the
/// clicks they take and what the pointer does to them.
enum NotchCaptureControlsStateTests {
    static func run(_ suite: TestSuite) {
        var state = NotchCaptureControlsState()
        suite.expect(!state.canExpand && !state.takesMouse(overWindow: true, overHoverArea: true)
                     && state.hoverResponse(inside: true, wasInside: false, closingPending: false,
                                            openingPending: false, suppressed: false) == .none,
                     "with no controls shown, nothing opens or takes a click")
        var cancels = 0
        let options = ScreenCaptureSelectionOptions(availableTools: [.screenshot], selectedTool: .screenshot,
                                                    showsCaptureMenu: false)
        state.begin(options, cancel: { cancels += 1 })
        suite.expect(state.options === options && state.collapsed && !state.selectionInProgress && state.canExpand,
                     "the controls start compact around the camera, ready to open")
        state.cancel?()
        suite.expect(cancels == 1, "the controls keep the capture's own cancel")

        // Clicks.
        suite.expect(state.takesMouse(overWindow: true, overHoverArea: true)
                     && !state.takesMouse(overWindow: true, overHoverArea: false)
                     && !state.takesMouse(overWindow: false, overHoverArea: true),
                     "compact controls take a click only over their own hover area")
        state.expand()
        suite.expect(state.takesMouse(overWindow: true, overHoverArea: false),
                     "open controls take a click anywhere on them")
        var read = false
        state.setSelectionInProgress(true)
        suite.expect(!state.takesMouse(overWindow: { read = true; return true }(), overHoverArea: true) && !read
                     && !state.canExpand,
                     "a selection being dragged lets every click through, without asking where the pointer is")
        state.setSelectionInProgress(false)

        // The pointer on open controls.
        func response(inside: Bool, wasInside: Bool, closing: Bool = false, opening: Bool = false,
                      suppressed: Bool = false) -> NotchCaptureControlsState.HoverResponse {
            state.hoverResponse(inside: inside, wasInside: wasInside, closingPending: closing,
                                openingPending: opening, suppressed: suppressed)
        }
        suite.expect(response(inside: true, wasInside: false) == .keepOpen, "the pointer on open controls keeps them open")
        suite.expect(response(inside: false, wasInside: true) == .closeSoon,
                     "leaving open controls closes them as leaving an island opened by hover does")
        suite.expect(response(inside: false, wasInside: false) == .closeLater
                     && response(inside: false, wasInside: false, closing: true) == .none,
                     "open controls the pointer never reached close after their own delay, scheduled once")
        suite.expect(state.mayCollapse(focused: false, pointerInside: false)
                     && !state.mayCollapse(focused: true, pointerInside: false)
                     && !state.mayCollapse(focused: false, pointerInside: true),
                     "a focused control or the pointer keeps open controls open")

        // The pointer on compact controls.
        state.collapse()
        suite.expect(!state.mayCollapse(focused: false, pointerInside: false), "compact controls have nothing to close")
        suite.expect(response(inside: true, wasInside: false) == .openSoon,
                     "the pointer resting on compact controls opens them after the hover delay")
        suite.expect(response(inside: true, wasInside: true, opening: true) == .none,
                     "a repeated report keeps the opening already under way")
        suite.expect(response(inside: false, wasInside: true, opening: true) == .cancelOpening,
                     "leaving compact controls cancels their opening")
        suite.expect(response(inside: true, wasInside: false, suppressed: true) == .cancelOpening,
                     "a click that suppressed hovering keeps compact controls closed")
        state.setSelectionInProgress(true)
        suite.expect(response(inside: true, wasInside: false) == .none,
                     "no pointer movement opens the controls during a selection")

        state.end()
        suite.expect(state.options == nil && !state.collapsed && !state.selectionInProgress && state.cancel == nil,
                     "ending the controls clears all of their state")
    }
}
