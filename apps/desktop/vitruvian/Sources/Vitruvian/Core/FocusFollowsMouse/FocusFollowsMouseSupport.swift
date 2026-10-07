// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Foundation

package enum FocusFollowsMouseSupport {
    package static let defaultDelayMilliseconds = 250
    package static let delayRange = 100...1_000

    package static func sanitizedDelay(_ milliseconds: Int) -> Int {
        min(max(milliseconds, delayRange.lowerBound), delayRange.upperBound)
    }

    /// Ask only the native mouse target's app. Visual overlays may sit above
    /// it without receiving input. Our interactive panels still stop the scan
    /// before any query: entering our Accessibility tree from a worker can
    /// deadlock against the main thread.
    package static func queryWindow<Result>(in windows: [[String: Any]],
                                    at point: CGPoint,
                                    pointerWindowID: CGWindowID,
                                    ownProcessID: pid_t,
                                    clickThroughWindowIDs: Set<CGWindowID>,
                                    query: (pid_t) -> Result?) -> Result? {
        guard pointerWindowID != kCGNullWindowID else { return nil }
        for window in windows {
            guard let bounds = WindowServerSupport.bounds(from: window),
                  bounds.contains(point),
                  (window[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1 > 0
            else { continue }

            guard let processID = (window[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value,
                  processID > 0 else { return nil }
            if processID == ownProcessID {
                guard let windowID = (window[kCGWindowNumber as String] as? NSNumber)?.uint32Value,
                      clickThroughWindowIDs.contains(windowID) else { return nil }
                continue
            }
            guard (window[kCGWindowNumber as String] as? NSNumber)?.uint32Value == pointerWindowID
            else { continue }
            // The Dock, the menu bar, a banner and the desktop are not what
            // hover follows, and neither is the app behind them, since the
            // pointer is on them and not on it.
            guard let layer = (window[kCGWindowLayer as String] as? NSNumber)?.intValue,
                  MouseAppExceptionSupport.appWindowLayers.contains(layer)
            else { return nil }
            return query(processID)
        }
        return nil
    }

    package static func shouldActivate(targetWindowID: CGWindowID,
                               focusedWindowID: CGWindowID?,
                               targetAppIsFrontmost: Bool) -> Bool {
        guard targetAppIsFrontmost else { return true }
        // Games may not expose focus through Accessibility. Reasserting it can
        // release their captured pointer, so require a known different window.
        guard let focusedWindowID else { return false }
        return focusedWindowID != targetWindowID
    }

    /// What hover does with `target`. A window that needs no activation is
    /// done with. A window the window server still parks on a hidden Space is
    /// a desktop switch in flight, since the switch is reported only once its
    /// animation ends: the activator would travel there and macOS replay the
    /// slide, so hover never travels between desktops and tries again later.
    /// `isParkedOnHiddenSpace` is asked last, as it asks the window server.
    package static func handoff(targetWindowID: CGWindowID,
                                focusedWindowID: CGWindowID?,
                                targetAppIsFrontmost: Bool,
                                isParkedOnHiddenSpace: (CGWindowID) -> Bool) -> FocusFollowsMouseHandoff {
        guard shouldActivate(targetWindowID: targetWindowID,
                             focusedWindowID: focusedWindowID,
                             targetAppIsFrontmost: targetAppIsFrontmost) else { return .notNeeded }
        return isParkedOnHiddenSpace(targetWindowID) ? .switchInFlight : .activate
    }

    /// Whether hover hands `target` to the activator at all.
    package static func handsToActivator(targetWindowID: CGWindowID,
                                         focusedWindowID: CGWindowID?,
                                         targetAppIsFrontmost: Bool,
                                         isParkedOnHiddenSpace: (CGWindowID) -> Bool) -> Bool {
        handoff(targetWindowID: targetWindowID, focusedWindowID: focusedWindowID,
                targetAppIsFrontmost: targetAppIsFrontmost,
                isParkedOnHiddenSpace: isParkedOnHiddenSpace) == .activate
    }

    /// Whether hover leaves the app at `point` alone: it answers to its own
    /// exception list (issue #358), asked before anything asks Accessibility
    /// about that app, so an excepted app is never even queried.
    package static func leavesAlone(_ point: CGPoint,
                                    excludes: (MouseExceptionScope, CGPoint) -> Bool) -> Bool {
        excludes(.focusFollowsMouse, point)
    }

    /// The process whose own Accessibility tree a hover hit test may enter, or
    /// nil for none. Never this app's: entering our tree from the worker can
    /// deadlock against the main thread. And always one app's tree, never a
    /// system-wide element, which could wander into ours when windows restack
    /// between the ownership lookup and the query.
    package static func hitTestProcess(_ processID: pid_t, ownProcessID: pid_t) -> pid_t? {
        processID > 0 && processID != ownProcessID ? processID : nil
    }

    /// A canceled focus handoff gives focus back to the window it took it
    /// from only while that app is in front and still reports that window.
    /// A read that fails or finds no window is unknown, so it restores nothing.
    package static func shouldRestoreFocus(to previousWindowID: CGWindowID,
                                           reportedFocusedWindowID: CGWindowID?,
                                           appIsFrontmost: Bool) -> Bool {
        appIsFrontmost && reportedFocusedWindowID == previousWindowID
    }
}

/// What a hover does with the window under the pointer: hand it to the
/// activator, leave it (it needs no activation), or try again once a desktop
/// switch still in flight has landed.
package enum FocusFollowsMouseHandoff: Equatable {
    case activate, notNeeded, switchInFlight
}

package struct FocusFollowsMouseEvaluation: Equatable {
    package let point: CGPoint
    package let generation: UInt64

    // Spelled out because a memberwise initializer never leaves its module.
    package init(point: CGPoint, generation: UInt64) {
        self.point = point
        self.generation = generation
    }
}

package struct FocusFollowsMouseState: Equatable {
    private enum EvaluationPhase: Equatable {
        case pending, evaluating, completed, cancelled
    }

    package private(set) var point: CGPoint?
    package private(set) var movedAt: TimeInterval = 0
    package private(set) var generation: UInt64 = 0
    private var phase = EvaluationPhase.pending
    private var windowID: CGWindowID?
    private var lastMovementAt: TimeInterval = 0
    private var movedDuringEvaluation = false

    package var hasPendingEvaluation: Bool {
        point != nil && phase == .pending
    }

    /// With a window ID, the delay counts time over that window, so moving
    /// within it keeps a pending lookup or a completed focus. A canceled
    /// attempt can try again after movement. Without an ID, movement always
    /// restarts the delay.
    package mutating func recordMovement(to point: CGPoint, at time: TimeInterval, windowID: CGWindowID? = nil) {
        defer {
            self.point = point
            lastMovementAt = time
        }
        if let windowID, windowID == self.windowID, self.point != nil {
            if phase == .evaluating { movedDuringEvaluation = true }
            if phase != .cancelled { return }
        }
        self.windowID = windowID
        movedAt = time
        generation &+= 1
        phase = .pending
        movedDuringEvaluation = false
    }

    package mutating func reset() {
        point = nil
        generation &+= 1
        phase = .pending
        movedDuringEvaluation = false
    }

    package mutating func nextEvaluation(at time: TimeInterval,
                                 delayMilliseconds: Int) -> FocusFollowsMouseEvaluation? {
        guard let point,
              hasPendingEvaluation,
              time - movedAt >= Double(FocusFollowsMouseSupport.sanitizedDelay(delayMilliseconds)) / 1_000
        else { return nil }
        phase = .evaluating
        movedDuringEvaluation = false
        return FocusFollowsMouseEvaluation(point: point, generation: generation)
    }

    /// A failed lookup or canceled handoff consumes no successful focus. Wait
    /// for movement, or preserve movement that arrived while the attempt ran.
    package mutating func finishEvaluation(_ evaluation: FocusFollowsMouseEvaluation, succeeded: Bool) {
        guard isCurrent(evaluation) else { return }
        phase = succeeded ? .completed : .cancelled
        if !succeeded, movedDuringEvaluation {
            movedAt = lastMovementAt
            generation &+= 1
            phase = .pending
        }
        movedDuringEvaluation = false
    }

    package func isCurrent(_ evaluation: FocusFollowsMouseEvaluation) -> Bool {
        evaluation.generation == generation && phase == .evaluating
    }

    // Spelled out because a default initializer never leaves its module.
    package init() {}
}
