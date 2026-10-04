// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import VitruvianCore
import VitruvianDesign
import VitruvianServices
import VitruvianUI

/// Uses the view's own scroll decision with controlled environment inputs.
enum ScrollingTitleMotionTests {
    static func run(_ suite: TestSuite) {
        func shouldScroll(hovered: Bool, overflows: Bool, reduceMotion: Bool) -> Bool {
            ScrollingTitle.shouldScroll(scrolls: hovered, reduceMotion: reduceMotion, overflows: overflows)
        }
        for hovered in [false, true] {
            for overflow in [false, true] {
                for reduced in [false, true] {
                    suite.expect(shouldScroll(hovered: hovered, overflows: overflow, reduceMotion: reduced)
                                     == (hovered && overflow && !reduced),
                                 "title motion follows hover, overflow and Reduce Motion (\(hovered), \(overflow), \(reduced))")
                }
            }
        }
        suite.expect(!shouldScroll(hovered: true, overflows: true, reduceMotion: true),
                     "a hovered overflowing title stays still under Reduce Motion")
        suite.expect(shouldScroll(hovered: true, overflows: true, reduceMotion: false),
                     "turning Reduce Motion off restores title scrolling")
        var measured = 0
        _ = ScrollingTitle.shouldScroll(scrolls: false, reduceMotion: false,
                                        overflows: { measured += 1; return true }())
        _ = ScrollingTitle.shouldScroll(scrolls: true, reduceMotion: true,
                                        overflows: { measured += 1; return true }())
        suite.expect(measured == 0, "a title that cannot scroll is never measured")
    }
}
