// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import VitruvianCore
import VitruvianDesign
import VitruvianServices
import VitruvianUI

/// Which Escape presses cancel the level typed into a mixer row, as the
/// field's monitor asks. No field is shown, no monitor is installed and no
/// key is posted.
enum MixerPercentKeyTests {
    static func run(_ suite: TestSuite) {
        func cancels(keyCode: UInt16 = 53, isActive: Bool = true, inFieldWindow: Bool = true,
                     composing: Bool = false) -> Bool {
            MixerPercentEscape.cancelsLevel(keyCode: keyCode, isActive: isActive,
                                            inFieldWindow: inFieldWindow, composing: { composing })
        }
        suite.expect(!cancels(inFieldWindow: false),
                     "Esc in another app window such as Settings stays there and keeps the level being typed")
        suite.expect(!cancels(composing: true), "a composing input method keeps Esc in the mixer level field")
        suite.expect(cancels(), "Esc cancels the level being typed once composition ends")
        suite.expect(!cancels(keyCode: 36), "only Esc cancels the level being typed")
        suite.expect(!cancels(isActive: false), "a level field that is not being edited ignores Esc")
        var asked = false
        _ = MixerPercentEscape.cancelsLevel(keyCode: 53, isActive: true, inFieldWindow: false,
                                            composing: { asked = true; return false })
        suite.expect(!asked, "Esc outside the field's window never asks the input method")
    }
}
