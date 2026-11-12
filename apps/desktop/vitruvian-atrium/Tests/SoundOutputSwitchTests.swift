// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import VitruvianCore
import VitruvianDesign
import VitruvianServices
import VitruvianUI

/// The real shortcut switch runs against in-memory outputs. Nothing is routed.
enum SoundOutputSwitchContract {
    static func run(_ suite: TestSuite) {
        var outputs: [(uid: String, canBeDefaultOutput: Bool)] = [("BuiltInSpeakerDevice", true),
                                                                  ("ExternalDisplay", true)]
        var switchedTo: [String] = []
        func switchOutput(in selected: [String]) -> Bool {
            AppVolumeMixer.switchToNextSoundOutput(in: selected, outputs: outputs,
                                                   currentUID: "BuiltInSpeakerDevice") {
                switchedTo.append($0)
                return true
            }
        }
        suite.expect(switchOutput(in: ["BuiltInSpeakerDevice"]) && switchedTo.isEmpty,
                     "the only selected output already playing is not reported as a failed switch")
        suite.expect(!switchOutput(in: ["USBHeadphones"]) && switchedTo.isEmpty,
                     "a selection with no connected output still fails")
        suite.expect(switchOutput(in: ["BuiltInSpeakerDevice", "ExternalDisplay"])
                     && switchedTo == ["ExternalDisplay"],
                     "two selected outputs still switch to the next one")

        // The AirPlay entry is a per-app route: the mixer never marks it as a
        // possible system output, so the shortcut skips it like any output
        // that cannot be the default.
        let airPlayUID = AirPlayRouteManager.airPlaySentinelUID
        outputs = [("BuiltInSpeakerDevice", true), (airPlayUID, false), ("ExternalDisplay", true)]
        switchedTo = []
        suite.expect(switchOutput(in: ["BuiltInSpeakerDevice", airPlayUID, "ExternalDisplay"])
                     && switchedTo == ["ExternalDisplay"],
                     "the output shortcut skips the per-app AirPlay entry")
    }
}
