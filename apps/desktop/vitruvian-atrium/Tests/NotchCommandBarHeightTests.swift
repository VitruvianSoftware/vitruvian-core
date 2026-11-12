// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import VitruvianServices

extension NotchPresentationRefreshContract {
    /// The island's handling of the Command Bar's measured height, on a real
    /// island with an inert window. Nothing reaches the desktop.
    static func commandBarHeightChecks(_ suite: TestSuite) {
        /// Lets the main queue run everything sent to it so far, however busy the runner.
        func nextTurn() {
            var reached = false
            DispatchQueue.main.async { reached = true }
            let deadline = Date(timeIntervalSinceNow: 2)
            while !reached && Date() < deadline {
                RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.001))
            }
            suite.expect(reached, "the Command Bar height fixture drains the main queue")
        }
        let fixture = island()
        suite.expect(fixture.island.presentCommandBar() != nil && fixture.island.showingCommandBar,
                     "the Command Bar opens in the island")
        let field = fixture.island.commandBarSurfaceSize.height
        fixture.island.updateCommandBarHeight(100)
        nextTurn()
        let fitted = fixture.island.commandBarSurfaceSize.height
        // Measured while SwiftUI draws the rows: the field alone, then the rows.
        fixture.island.updateCommandBarHeight(50)
        fixture.island.updateCommandBarHeight(300.4)
        suite.expect(fixture.island.commandBarSurfaceSize.height == fitted,
                     "the bar's measured height waits for the next turn of the main loop, not the pass that drew the rows")
        nextTurn()
        suite.expect(fixture.island.commandBarSurfaceSize.height == fitted + 201,
                     "the island fits the bar once, at the latest height measured in that pass")
        // A height measured as the bar closes goes with it, and a bar opened
        // again starts from its field.
        fixture.island.updateCommandBarHeight(320)
        fixture.island.collapse()
        suite.expect(fixture.island.presentCommandBar() != nil, "the Command Bar opens in the island again")
        nextTurn()
        suite.expect(fixture.island.commandBarSurfaceSize.height == field,
                     "a height measured as the bar closes goes with it")
        fixture.island.collapse()
    }
}
