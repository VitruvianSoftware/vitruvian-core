// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import SwiftUI
import VitruvianCore
import VitruvianDesign
import VitruvianServices
import VitruvianUI

/// The closed island's Nexus sparkles: they swing each second while a session
/// runs, and keep still under Reduce Motion.
enum NexusSparkleMotionTests {
    static func run(_ suite: TestSuite) {
        for second in 0..<4 {
            suite.expect(NexusSparkleMotion.scale(elapsedSeconds: second, reduceMotion: false)
                             == (second % 2 == 0 ? 1.15 : 0.85),
                         "the sparkles swing between 85 % and 115 % each second (\(second)s)")
            suite.expect(NexusSparkleMotion.scale(elapsedSeconds: second, reduceMotion: true) == 1,
                         "under Reduce Motion the sparkles keep still at their own size (\(second)s)")
        }
        suite.expect(NexusSparkleMotion.animation(reduceMotion: true) == nil,
                     "under Reduce Motion nothing animates the sparkles")
        suite.expect(NexusSparkleMotion.animation(reduceMotion: false) != nil,
                     "without Reduce Motion the swing is animated")
    }
}
