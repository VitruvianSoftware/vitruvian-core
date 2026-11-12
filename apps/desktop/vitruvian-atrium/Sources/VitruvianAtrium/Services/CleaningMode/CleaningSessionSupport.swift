// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import CoreGraphics
import Foundation

/// What Cleaning Mode does when the login session or its tap changes under
/// it, as plain answers the manager carries out.
///
/// A switched-away session cannot keep a filter tap in the input chain: the
/// window server would make the account on screen wait for it. Cleaning is a
/// temporary, local state, so leaving the session ends it on the spot. The
/// features the lock suspended stay suspended while the session is away and
/// come back only when it returns.
package enum CleaningSessionSupport {
    /// What a session change asks of the manager.
    package enum SessionStep: Equatable {
        /// Nothing changes.
        case keep
        /// End the lock now, leaving the suspended features suspended until
        /// the session comes back.
        case endLockKeepingFeaturesSuspended
        /// Resume the features a lock that ended with the session left
        /// suspended.
        case resumeSuspendedFeatures
    }

    /// `locked` is whether the lock is up; `featuresAwaitSession` whether an
    /// earlier session change ended it and left its features suspended.
    package static func sessionChanged(isActive: Bool, locked: Bool,
                                       featuresAwaitSession: Bool) -> SessionStep {
        if isActive {
            return featuresAwaitSession ? .resumeSuspendedFeatures : .keep
        }
        return locked ? .endLockKeepingFeaturesSuspended : .keep
    }

    /// What a tap the window server switched off does next.
    package enum DisabledTapStep: Equatable {
        /// Put the tap back, so the keyboard stays locked.
        case rearm
        /// End the lock. The suspended features come back only while this
        /// session is the one on screen to use them.
        case endLock(restoreSuspendedFeatures: Bool)
    }

    /// The tap goes back only into the session on screen, and only with
    /// Accessibility: a tap put back into a switched-away session is the stall
    /// the gate exists to end, and one without the grant cannot hold the lock.
    package static func tapDisabled(sessionIsActive: Bool, accessibilityGranted: Bool,
                                    hasTap: Bool) -> DisabledTapStep {
        guard sessionIsActive, accessibilityGranted, hasTap else {
            return .endLock(restoreSuspendedFeatures: sessionIsActive)
        }
        return .rearm
    }
}

/// One event the cleaning tap sees, as the lock's decision reads it.
package enum CleaningTapEvent: Equatable {
    /// The window server switched the tap off.
    case tapDisabled
    /// A mouse button went down or came up.
    case mouseButton(Int64, isDown: Bool)
    /// A key the unlock gesture counts, or one that resets its count: a key
    /// press, a modifier change or a system key going down.
    case unlockKey(code: Int64, isRepeat: Bool)
    /// Everything else the lock holds back: key releases, scrolling, trackpad
    /// gestures and system events that are no key press.
    case other
}

package enum CleaningTapSupport {
    /// What the tap's event is to the lock. `field` reads one of the event's
    /// integer fields and `systemKey` decodes a system-defined event; each is
    /// read only for the kinds of event that carry it.
    ///
    /// Shift, control, option, command, fn and caps lock arrive as
    /// flags-changed events rather than key-downs, and they are the keys
    /// nearest Escape: a cloth resting on them must reset the count like any
    /// other key, so they reach the counter too. Both the press and the release
    /// report the same key code and neither is Escape, so each one resets and
    /// the pair is idempotent. Modifiers never auto-repeat.
    package static func classify(type: CGEventType,
                                 field: (CGEventField) -> Int64,
                                 systemKey: () -> CleaningSystemKeyEvent?) -> CleaningTapEvent {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            return .tapDisabled
        case .leftMouseDown:
            return .mouseButton(0, isDown: true)
        case .leftMouseUp:
            return .mouseButton(0, isDown: false)
        case .rightMouseDown:
            return .mouseButton(1, isDown: true)
        case .rightMouseUp:
            return .mouseButton(1, isDown: false)
        case .otherMouseDown:
            return .mouseButton(field(.mouseEventButtonNumber), isDown: true)
        case .otherMouseUp:
            return .mouseButton(field(.mouseEventButtonNumber), isDown: false)
        case .keyDown:
            let code = field(.keyboardEventKeycode)
            return .unlockKey(code: code, isRepeat: field(.keyboardEventAutorepeat) != 0)
        case .flagsChanged:
            return .unlockKey(code: field(.keyboardEventKeycode), isRepeat: false)
        default:
            guard type.rawValue == CleaningSystemKeyEvent.systemDefinedEventTypeRawValue,
                  let key = systemKey(), key.isKeyDown else { return .other }
            return .unlockKey(code: key.code, isRepeat: key.isRepeat)
        }
    }
}
