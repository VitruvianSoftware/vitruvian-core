// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Foundation
import VitruvianAtriumCore

/// What Pinch Zoom made of one wheel event.
package enum PinchZoomVerdict: Equatable {
    /// Not a zoom wheel right now: no zoom modifier is held alone, or the
    /// open switcher steps by the wheel. The ordinary wheel path takes it.
    case notZoom
    /// Turned into a magnification gesture: the wheel event is dropped.
    case consumed
    /// A zoom wheel that was not turned: over one of this app's own windows
    /// (their controls keep the wheel), or before the tap has armed the
    /// current settings.
    case declined
}

/// Pinch Zoom: the selected modifier held alone with the mouse wheel becomes a
/// magnification gesture at the pointer, the one a trackpad pinch sends.
/// Both wheel taps hand it the wheel, the inverter's on the pointer thread and
/// the smooth scrolling one on the main thread, so a zoom tick never becomes a
/// glide. Its state is behind one lock, which also orders the gestures it posts:
/// a gesture is ended before a new one starts somewhere else, and before the
/// modifier, the settings or the tap change.
///
/// The gestures are posted to the session, so they reach the app under the
/// pointer, never this app's own windows.
package final class PinchZoomGesture: @unchecked Sendable {
    /// The phases of a magnification gesture this posts.
    package enum Phase: Int64 {
        case began = 1
        case changed = 2
        case ended = 4
    }

    /// One posted gesture event, for the poster.
    package struct Pinch: Equatable {
        package let phase: Phase
        package let magnification: Double
        package let location: CGPoint?

        // Spelled out because a memberwise initializer never leaves its module.
        package init(phase: Phase, magnification: Double, location: CGPoint?) {
            self.phase = phase
            self.magnification = magnification
            self.location = location
        }
    }

    /// Guards `state`: the inverter's tap runs on the pointer thread, while
    /// the smooth scrolling tap and every settings change run on main.
    private let lock = NSLock()
    private var state = ScrollZoomGestureState()
    private let switcherHoldsWheel: @Sendable () -> Bool
    private let isOwnWindow: @Sendable (CGPoint) -> Bool
    private let post: @Sendable (Pinch) -> Void

    package init(switcherHoldsWheel: @escaping @Sendable () -> Bool,
                 isOwnWindow: @escaping @Sendable (CGPoint) -> Bool,
                 post: @escaping @Sendable (Pinch) -> Void) {
        self.switcherHoldsWheel = switcherHoldsWheel
        self.isOwnWindow = isOwnWindow
        self.post = post
    }

    /// The real one: it yields to the given switcher while it steps by the
    /// wheel, leaves this app's windows their wheel, and posts to the session.
    package static func live(switcher: AppSwitcher) -> PinchZoomGesture {
        PinchZoomGesture(switcherHoldsWheel: { switcher.scrollNavigationActive },
                         isOwnWindow: { ScrollWheelTarget.shared.contains($0) },
                         post: { postToSession($0) })
    }

    /// New settings. A gesture under way ends, and none starts until the tap
    /// arms them with `start()`.
    package func update(_ preferences: ScrollZoomPreferences) {
        lock.withLock {
            let location = state.pinchLocation
            if state.update(preferences) { post(Pinch(phase: .ended, magnification: 0, location: location)) }
        }
    }

    /// The tap is live: the settings last given are the ones it turns.
    package func start() {
        lock.withLock { state.start() }
    }

    /// The tap is gone. A gesture under way ends.
    package func stop() {
        lock.withLock {
            let location = state.pinchLocation
            if state.stop() { post(Pinch(phase: .ended, magnification: 0, location: location)) }
        }
    }

    /// A modifier went down or up. A gesture ends as soon as its modifier is
    /// no longer the only one held.
    package func modifiersChanged(_ flags: CGEventFlags) {
        lock.withLock {
            if let modifier = state.pinchModifier,
               flags.intersection([.maskShift, .maskAlternate, .maskControl, .maskCommand]) != modifier.flag {
                endPinchLocked()
            }
        }
    }

    /// Turns one mouse wheel event into a magnification step, when the zoom
    /// modifier is held alone with it.
    package func consume(_ event: CGEvent, direction: ScrollDirectionPreferences) -> PinchZoomVerdict {
        guard !switcherHoldsWheel(), let action = direction.zoom.action(for: event) else { return .notZoom }
        guard !isOwnWindow(event.location) else {
            lock.withLock { endPinchLocked() }
            return .declined
        }
        let delta = ScrollWheelSupport.zoomDelta(action.delta, axis: action.axis,
                                                  invertVertical: direction.invertVertical,
                                                  invertHorizontal: direction.invertHorizontal)
        let location = event.location
        return lock.withLock { () -> PinchZoomVerdict in
            guard state.accepts(direction.zoom) else { return .declined }
            let previous = state.pinchLocation
            let transition = state.beginPinch(action.modifier, at: location)
            if transition.endPrevious { post(Pinch(phase: .ended, magnification: 0, location: previous)) }
            if transition.begin { post(Pinch(phase: .began, magnification: 0, location: location)) }
            post(Pinch(phase: .changed, magnification: delta * 0.005, location: location))
            return .consumed
        }
    }

    private func endPinchLocked() {
        let location = state.pinchLocation
        if state.endPinch() { post(Pinch(phase: .ended, magnification: 0, location: location)) }
    }

    /// A magnification gesture event (`NSEvent.EventType.gesture`, 29, of
    /// subtype magnify, 8), posted to the session at the pointer.
    private static func postToSession(_ pinch: Pinch) {
        guard let gesture = CGEvent(source: nil),
              let type = CGEventType(rawValue: 29),
              let subtype = CGEventField(rawValue: 110),
              let phase = CGEventField(rawValue: 132),
              let magnification = CGEventField(rawValue: 113) else { return }
        if let location = pinch.location { gesture.location = location }
        gesture.type = type
        gesture.setIntegerValueField(subtype, value: 8)
        gesture.setIntegerValueField(phase, value: pinch.phase.rawValue)
        gesture.setDoubleValueField(magnification, value: pinch.magnification)
        gesture.post(tap: .cgSessionEventTap)
    }
}
