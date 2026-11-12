// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Darwin
import Foundation
import VitruvianCore
import VitruvianDesign
import VitruvianServices
import VitruvianUI

enum KeyboardDebounceTapTests {
    // The module's tap rule, with the state it reads supplied here; no event
    // tap is installed.
    static func run(_ suite: TestSuite) {
        var state = KeyboardDebounceState()
        let config = KeyboardDebounceConfig(enabled: true, globalWindowMs: 50, keyWindows: [:])
        let timebase = EventTimestamp.machTimebase
        func ticks(milliseconds: UInt64) -> UInt64 {
            milliseconds * 1_000_000 * timebase.denom / timebase.numer
        }
        // Stamped in mach ticks like hardware keys at the HID tap, shortly
        // before now so every reading stays near the current uptime.
        let pressed = mach_absolute_time() - ticks(milliseconds: 500)
        func key(down: Bool, at timestamp: UInt64) -> CGEvent? {
            let event = CGEvent(keyboardEventSource: nil, virtualKey: 13, keyDown: down)
            event?.setIntegerValueField(.eventSourceUnixProcessID, value: 0)
            event?.timestamp = timestamp
            return event
        }
        func passes(_ event: CGEvent?) -> Bool {
            guard let event else { return false }
            return !KeyboardDebounceService.suppresses(event.type, event: event, state: &state, config: config)
        }

        let hardwareKeyDown = key(down: true, at: pressed)
        suite.expect(passes(hardwareKeyDown), "a real key press passes key debounce")
        // Quit Protection confirms a held press by posting a copy of the
        // hardware key down, which keeps its time and source process id of 0.
        let quitProtectionCopy = hardwareKeyDown?.copy()
        quitProtectionCopy?.setIntegerValueField(.eventSourceUserData, value: OwnKeyEvent.quitProtectionMarker)
        suite.expect(passes(quitProtectionCopy),
                     "the Quit Protection copy of a held key passes right after the real press")
        let unmarkedCopy = hardwareKeyDown?.copy()
        suite.expect(!passes(unmarkedCopy), "the same copy without the marker is dropped as chatter")

        let released = pressed + ticks(milliseconds: 80)
        suite.expect(passes(key(down: false, at: released)), "releasing the key passes")
        suite.expect(!passes(key(down: true, at: released + ticks(milliseconds: 20))),
                     "a new press 20 ms after the release is dropped")
        suite.expect(passes(key(down: true, at: released + ticks(milliseconds: 55))),
                     "a press 55 ms after the release, just past the 50 ms window, passes")
    }
}
