// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import VitruvianCore
import VitruvianDesign
import VitruvianServices
import VitruvianUI

/// Runs the production CPU reading against scripted host tick counters.
enum SystemMonitorCPUTests {
    static func run(_ suite: TestSuite) {
        var previous: (busy: UInt64, total: UInt64, time: TimeInterval)?
        var held: Double?
        var heldReadAt: TimeInterval?
        func read(_ ticks: (UInt32, UInt32, UInt32, UInt32), now: TimeInterval) -> Double? {
            SystemMonitor.cpuUsage(ticks: ticks, now: now, previous: &previous,
                                   held: &held, heldReadAt: &heldReadAt)
        }
        suite.expect(read((100, 100, 800, 0), now: 0) == nil, "the first CPU read only sets a baseline")
        suite.expect(read((200, 200, 1_400, 0), now: 5) == 0.25,
                     "a regular CPU read is the busy share since the last one")
        held = 0.25
        heldReadAt = 5
        suite.expect(read((1_200, 1_200, 1_600, 0), now: 65) == nil,
                     "a CPU read after a long gap only resets the baseline instead of reporting the gap's average")
        suite.expect(held == nil && heldReadAt == nil,
                     "a CPU read after a long gap drops the value and read time held from before the gap")
        suite.expect(read((1_300, 1_300, 1_800, 0), now: 70) == 0.5, "sampling resumes from the reset baseline")
        suite.expect(read((1_300, 1_300, 1_800, 0), now: 75) == nil,
                     "a CPU read whose ticks have not advanced reports nothing")
        suite.expect(read((1_300, 1_300, 1_900, 100), now: 80) == 0.5, "niced ticks count as busy")
    }
}
