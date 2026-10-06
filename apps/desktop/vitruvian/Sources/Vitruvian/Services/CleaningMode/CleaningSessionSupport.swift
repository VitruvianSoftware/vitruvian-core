// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

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
