// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import VitruvianCore
import VitruvianDesign

/// Pure state machine for the cleaning-mode unlock gesture: it counts deliberate
/// presses of one required key. Other keys reset the count, auto-repeat is ignored,
/// and a long pause restarts it. Extracted from the event tap so the logic can be
/// tested deterministically.
package struct CleaningUnlockCounter {
    package let requiredKeyCode: Int64
    package let threshold: Int
    /// A required-key press only counts if it lands within this window of the previous
    /// one; a longer gap restarts the count.
    package let pressWindow: TimeInterval

    package private(set) var progress = 0
    private var lastKeyTime: TimeInterval = -.greatestFiniteMagnitude

    /// The window Cleaning Mode ships with. At 2s, someone pressing Escape
    /// slower than once per two seconds could never unlock (#697); see
    /// `CleaningModeManager` for what the window still guards against.
    package static let shippedPressWindow: TimeInterval = 6.0

    package init(requiredKeyCode: Int64, threshold: Int, pressWindow: TimeInterval) {
        self.requiredKeyCode = requiredKeyCode
        self.threshold = threshold
        self.pressWindow = pressWindow
    }

    /// Registers a key-down at `time` (a monotonic clock). `isRepeat` is true for
    /// auto-repeat events, which never count. Returns true once `progress` reaches
    /// the threshold, signalling the caller to unlock.
    package mutating func registerKeyDown(code: Int64, time: TimeInterval, isRepeat: Bool) -> Bool {
        guard !isRepeat else { return false }
        guard code == requiredKeyCode else {
            progress = 0
            lastKeyTime = -.greatestFiniteMagnitude
            return false
        }
        if time - lastKeyTime <= pressWindow {
            progress += 1
        } else {
            progress = 1
        }
        lastKeyTime = time
        return progress >= threshold
    }

    package mutating func reset() {
        progress = 0
        lastKeyTime = -.greatestFiniteMagnitude
    }
}

package struct CleaningSystemKeyEvent: Equatable {
    package static let systemDefinedEventTypeRawValue: UInt32 = 14
    package static let powerKeySubtype = 1
    package static let auxiliaryControlButtonsSubtype = 8
    package static let keyDownState = 10
    package static let keyUpState = 11

    private static let syntheticKeyCodeBase: Int64 = 10_000

    package let code: Int64
    package let isKeyDown: Bool
    package let isRepeat: Bool

    package static func decode(subtype: Int, data1: Int) -> CleaningSystemKeyEvent? {
        switch subtype {
        case auxiliaryControlButtonsSubtype:
            return decodeAuxiliaryControl(data1: data1)
        case powerKeySubtype:
            return CleaningSystemKeyEvent(code: syntheticKeyCodeBase + Int64(powerKeySubtype),
                                          isKeyDown: true,
                                          isRepeat: false)
        default:
            return nil
        }
    }

    private static func decodeAuxiliaryControl(data1: Int) -> CleaningSystemKeyEvent? {
        let raw = UInt32(truncatingIfNeeded: data1)
        let keyCode = Int64((raw >> 16) & 0xffff)
        let state = Int((raw >> 8) & 0xff)
        guard state == keyDownState || state == keyUpState else { return nil }
        return CleaningSystemKeyEvent(code: syntheticKeyCodeBase + keyCode,
                                      isKeyDown: state == keyDownState,
                                      isRepeat: (raw & 0x1) != 0)
    }

    // Spelled out because a memberwise initializer never leaves its module.
    package init(code: Int64, isKeyDown: Bool, isRepeat: Bool) {
        self.code = code
        self.isKeyDown = isKeyDown
        self.isRepeat = isRepeat
    }
}
