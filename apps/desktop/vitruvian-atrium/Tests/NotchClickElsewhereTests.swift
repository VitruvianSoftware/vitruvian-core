// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import VitruvianAtriumCore

/// The production click-elsewhere decision with controlled state, never posted input.
enum NotchClickElsewhereTests {
    static func run(_ suite: TestSuite) {
        func outcome(keepsSurface: Bool = false, overIsland: Bool = false, overVisibleCopy: Bool = false,
                     overStatusItem: Bool = false, overAssistiveKeyboard: Bool = false,
                     preview: Bool = false) -> NotchClickElsewhere.Outcome {
            NotchClickElsewhere.outcome(keepsSurface: keepsSurface, overIsland: overIsland,
                                        overVisibleCopy: overVisibleCopy, overStatusItem: overStatusItem,
                                        overAssistiveKeyboard: overAssistiveKeyboard,
                                        showsCapturePreview: preview)
        }
        suite.expect(outcome() == .collapse, "a click elsewhere collapses the island")
        suite.expect(outcome(preview: true) == .dismissPreview,
                     "a click elsewhere hands a screenshot preview to its controller instead of collapsing")
        for kept in [
            outcome(keepsSurface: true),
            outcome(keepsSurface: true, preview: true),
            outcome(overIsland: true, preview: true),
            outcome(overStatusItem: true),
            outcome(overAssistiveKeyboard: true, preview: true),
        ] {
            suite.expect(kept == .keep,
                         "pinning, menus, sheets, the island's own area, the status item and the assistive keyboard keep the island")
        }
        suite.expect(outcome(overVisibleCopy: true, preview: true) == .keep,
                     "clicking a visible island copy preserves the preview while it moves between displays")

        suite.expect(!NotchClickElsewhere.closesPreview(sharing: true),
                     "a click elsewhere keeps a preview whose share link is still being made")
        suite.expect(NotchClickElsewhere.closesPreview(sharing: false),
                     "a click elsewhere closes an idle screenshot preview")
    }
}
