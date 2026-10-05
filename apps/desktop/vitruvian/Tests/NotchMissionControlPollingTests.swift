// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import VitruvianCore
import VitruvianDesign
import VitruvianServices
import VitruvianUI

/// Runs the production polling with a clock and an overview double. It
/// neither opens windows nor queries the window server.
enum NotchMissionControlPollingTests {
    /// What the polling reads, and how often it probed.
    final class Island {
        var now: TimeInterval = 100
        var panelIsVisible = true
        var concealed = false
        var overview = false
        var overviewReads = 0
        var frameReads = 0
    }

    static func run(_ suite: TestSuite) {
        let island = Island()
        let polling = NotchMissionControlPolling(inputs: .init(
            panelIsVisible: { island.panelIsVisible },
            concealed: { island.concealed },
            overviewIsVisible: { island.overviewReads += 1; return island.overview },
            uptime: { island.now },
            sample: { island.frameReads += 1 }))
        defer { polling.stop() }
        polling.sync()
        suite.expect(polling.timer?.timeInterval == 0.25 && island.frameReads == 0,
                     "resting islands use four window-list checks per second and no frame probe")
        let idleTimer = polling.timer!
        polling.sync()
        suite.expect(polling.timer === idleTimer, "presentation updates reuse the idle timer")
        let before = island.overviewReads
        island.now += 0.1
        polling.refresh()
        suite.expect(island.overviewReads == before, "incidental idle checks respect the reduced cadence")
        island.overview = true
        polling.refresh(now: true)
        suite.expect(polling.timer?.timeInterval == 0.08 && !idleTimer.isValid && island.frameReads == 1,
                     "an immediate reveal check detects overview and replaces the idle timer with the fast timer")
        let activeTimer = polling.timer!
        island.now += 0.1
        polling.refresh()
        suite.expect(polling.timer === activeTimer && island.frameReads == 1,
                     "an open overview keeps fast detection but throttles expensive frame probes")
        island.concealed = true
        island.panelIsVisible = false
        island.overview = false
        island.now += 0.1
        polling.refresh()
        suite.expect(polling.timer === activeTimer && island.frameReads == 2,
                     "a concealed island retains fast restoration after the overview disappears")
        island.concealed = false
        island.panelIsVisible = true
        polling.sync()
        suite.expect(polling.timer?.timeInterval == 0.25 && !activeTimer.isValid,
                     "a restored island returns to the idle cadence")
        let restoredTimer = polling.timer!
        island.panelIsVisible = false
        polling.sync()
        suite.expect(polling.timer == nil && !restoredTimer.isValid,
                     "an ordinary hidden island stops polling completely")

        let reopened = Island()
        let reopening = NotchMissionControlPolling(inputs: .init(
            panelIsVisible: { reopened.panelIsVisible },
            concealed: { reopened.concealed },
            overviewIsVisible: { reopened.overview },
            uptime: { reopened.now },
            sample: { reopened.frameReads += 1 }))
        defer { reopening.stop() }
        reopened.overview = true
        reopening.refresh(now: true)
        reopened.overview = false
        reopened.now += 0.1
        reopening.refresh()
        reopened.overview = true
        reopened.now += 0.3
        reopening.refresh()
        suite.expect(reopened.frameReads == 2,
                     "an overview that opens again is probed at once, sooner than a lasting one")
    }
}
