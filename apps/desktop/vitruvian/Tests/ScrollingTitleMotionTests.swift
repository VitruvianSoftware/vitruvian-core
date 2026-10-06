// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import SwiftUI
import VitruvianCore
import VitruvianDesign
import VitruvianServices
import VitruvianUI

/// Uses the view's own scroll decision with controlled environment inputs,
/// and renders the view to see where a resting name sits.
enum ScrollingTitleMotionTests {
    static func run(_ suite: TestSuite) {
        restingPlacement(suite)
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

    /// Both panels draw their window names through this one view and hang it
    /// differently: centred under a grid thumbnail, on the leading edge beside
    /// a Dock preview card's buttons. A short name rests where it is told to.
    private static func restingPlacement(_ suite: TestSuite) {
        func inkStart(_ alignment: Alignment) -> Int? {
            let renderer = ImageRenderer(content: ScrollingTitle(text: "Mail", weight: .regular, width: 160,
                                                                 alignment: alignment, scrolls: false))
            renderer.scale = 1
            guard let image = renderer.cgImage, image.width > 0,
                  let alpha = SwitcherSupport.alphaGrid(of: image, gridSize: image.width) else { return nil }
            let side = image.width
            return (0..<side).first { column in
                (0..<side).contains { row in alpha[row * side + column] > 0 }
            }
        }
        let leading = inkStart(.leading)
        let centred = inkStart(.center)
        let trailing = inkStart(.trailing)
        suite.expect(leading != nil && centred != nil && trailing != nil,
                     "the scrolling name is one view, not a copy in each panel, and it draws the name it is given")
        if let leading, let centred, let trailing {
            suite.expect(leading < 8 && centred > leading + 40 && trailing > centred + 40,
                         "the shared name view is told where to sit instead of always taking the leading edge")
        }
    }
}
