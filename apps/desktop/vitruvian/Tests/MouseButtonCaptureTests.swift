// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import Foundation
import VitruvianCore
import VitruvianDesign
import VitruvianServices
import VitruvianUI

/// What a button pressed while Mouse settings wait for one means
/// (`MouseButtonCapture`), for the shortcut capture and the Spaces drag.
enum MouseButtonCaptureContract {
    static func run(_ suite: TestSuite) {
        let text = MouseButtonFeatureStrings.enUS
        let wheel = MouseButtonShortcutSupport.sideWheelLeftInput
        let free: Int64 = 4
        let mappedButton: Int64 = 5
        let pending: Int64 = 6
        let drag: Int64 = 7
        let radial: Int64 = 8
        func outcome(_ kind: MouseButtonCapture.Kind, _ button: Int64,
                     spacesButton: Int64? = nil) -> MouseButtonCapture.Outcome {
            MouseButtonCapture.outcome(kind, button: button, mapped: { $0 == mappedButton }, pending: pending,
                                       spacesButton: spacesButton, wheelClaims: { $0 == radial })
        }

        // The shortcut capture.
        suite.expect(outcome(.shortcut, free) == .accept && outcome(.shortcut, wheel) == .accept,
                     "a shortcut takes a free extra button or a side-wheel direction")
        suite.expect(outcome(.shortcut, 1) == .unsupported, "a shortcut cannot take the primary buttons")
        suite.expect(outcome(.shortcut, radial) == .wheel, "a button the radial menu opens on is refused")
        suite.expect(outcome(.shortcut, mappedButton) == .taken && outcome(.shortcut, pending) == .taken,
                     "a mapped button, or one being mapped, is refused")
        suite.expect(outcome(.shortcut, drag, spacesButton: drag) == .taken
                     && outcome(.shortcut, drag, spacesButton: nil) == .accept,
                     "the drag's button is spoken for only while the drag is switched on")

        // The drag capture.
        suite.expect(outcome(.spaces, free) == .accept, "the drag takes a free extra button")
        suite.expect(outcome(.spaces, wheel) == .unsupported,
                     "the drag refuses a side-wheel direction: a tick is nothing to hold")
        suite.expect(outcome(.spaces, pending) == .taken,
                     "the drag capture refuses a button that is mid-way through becoming a shortcut")
        suite.expect(outcome(.spaces, mappedButton) == .taken && outcome(.spaces, radial) == .wheel,
                     "the drag refuses a mapped button and the radial menu's")

        // Each capture's words.
        suite.expect(MouseButtonCapture.waitingPrompt(.shortcut, text: text) == text.captureWaiting
                     && MouseButtonCapture.waitingPrompt(.spaces, text: text) == text.spacesCaptureWaiting
                     && text.spacesCaptureWaiting != text.captureWaiting,
                     "the drag capture's waiting prompt never invites the side wheel the drag refuses")
        let dragRefusals = [MouseButtonCapture.Outcome.unsupported, .taken].compactMap {
            MouseButtonCapture.feedback($0, .spaces, text: text)
        }
        suite.expect(dragRefusals == [text.spacesCaptureUnsupported, text.spacesCaptureExists]
                     && !dragRefusals.contains(text.captureUnsupported) && !dragRefusals.contains(text.captureExists),
                     "the drag capture's refusals recommend only what the drag accepts and point at no list")
        suite.expect(MouseButtonCapture.feedback(.unsupported, .shortcut, text: text) == text.captureUnsupported
                     && MouseButtonCapture.feedback(.taken, .shortcut, text: text) == text.captureExists
                     && MouseButtonCapture.feedback(.wheel, .shortcut, text: text) == text.captureWheel
                     && MouseButtonCapture.feedback(.accept, .shortcut, text: text) == nil,
                     "the shortcut capture refuses in its own words and says nothing when it takes the button")

        // The two switches.
        suite.expect(MouseButtonCapture.spacesButton(afterSwitch: false, current: 7) == 0
                     && MouseButtonCapture.spacesButton(afterSwitch: true, current: 7) == 7,
                     "the drag's own OFF branch drops its binding, so no hidden button ever refuses a shortcut")
        suite.expect(MouseButtonCapture.isEngaged(shortcuts: true, spaces: false)
                     && MouseButtonCapture.isEngaged(shortcuts: false, spaces: true)
                     && !MouseButtonCapture.isEngaged(shortcuts: false, spaces: false),
                     "either mouse-button switch engages the tap and its permission, the exception list and the panel row")
        suite.expect(Set(AppFeature.mouseButtonShortcuts.enabledKeys)
                     == [DefaultsKey.mouseButtonShortcutsEnabled, DefaultsKey.mouseSpacesGestureEnabled],
                     "the feature's engaged keys are the same two switches")
    }
}
