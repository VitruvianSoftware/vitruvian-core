// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import AppKit
import VitruvianCore

/// The closed island following the pointer to another display. Movement is
/// watched only while the island can follow it there, each event only checks
/// whether the pointer left the island's display, and the island moves once
/// the pointer has rested there a moment; nothing polls at rest.
package final class NotchPointerFollower {
    /// The pointer, the displays and the clock. The app passes `.system`.
    package struct Environment {
        /// Starts watching pointer movement, drags included, in this app and
        /// in others, and returns what `removeMonitor` takes.
        package var addMonitors: (_ moved: @escaping () -> Void) -> [Any]
        package var removeMonitor: (Any) -> Void
        package var mouseLocation: () -> CGPoint
        package var displayCount: () -> Int
        /// The display the pointer is on.
        package var displayWithMouse: () -> CGDirectDisplayID?
        /// Runs an action after a delay on the main queue, and returns what cancels it.
        package var schedule: (_ delay: TimeInterval, _ action: @escaping () -> Void) -> () -> Void

        package init(addMonitors: @escaping (_ moved: @escaping () -> Void) -> [Any],
                     removeMonitor: @escaping (Any) -> Void,
                     mouseLocation: @escaping () -> CGPoint,
                     displayCount: @escaping () -> Int,
                     displayWithMouse: @escaping () -> CGDirectDisplayID?,
                     schedule: @escaping (_ delay: TimeInterval, _ action: @escaping () -> Void) -> () -> Void) {
            self.addMonitors = addMonitors
            self.removeMonitor = removeMonitor
            self.mouseLocation = mouseLocation
            self.displayCount = displayCount
            self.displayWithMouse = displayWithMouse
            self.schedule = schedule
        }

        package static let system = Environment(
            addMonitors: { moved in
                // A drag moves the pointer without mouse-moved events.
                let moves: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged]
                var tokens: [Any] = []
                if let token = NSEvent.addGlobalMonitorForEvents(matching: moves, handler: { _ in moved() }) {
                    tokens.append(token)
                }
                if let token = NSEvent.addLocalMonitorForEvents(matching: moves, handler: { event in
                    moved()
                    return event
                }) { tokens.append(token) }
                return tokens
            },
            removeMonitor: NSEvent.removeMonitor,
            mouseLocation: { NSEvent.mouseLocation },
            displayCount: { NSScreen.screens.count },
            displayWithMouse: { NSScreen.withMouse?.notchDisplayID },
            schedule: { delay, action in
                let work = DispatchWorkItem(block: action)
                DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
                return { work.cancel() }
            })
    }

    /// The island's side, read as the pointer moves.
    package struct Island {
        /// Running and not suspended.
        package var isActive: () -> Bool
        /// The display choice is the pointer's, or every display.
        package var followsPointer: () -> Bool
        package var hasWindow: () -> Bool
        /// The frame of the display the island is on.
        package var screenFrame: () -> CGRect
        /// Only a closed island at rest moves (`NotchService.canFollowPointer`).
        package var canFollow: () -> Bool
        /// Mission Control spans the displays; the island moves once it is back.
        package var isConcealedForMissionControl: () -> Bool
        package var displayID: () -> CGDirectDisplayID?
        /// Runs an action once the island's window has finished moving or closing.
        package var whenSettled: (@escaping () -> Void) -> Void
        package var move: (CGDirectDisplayID) -> Void

        package init(isActive: @escaping () -> Bool, followsPointer: @escaping () -> Bool,
                     hasWindow: @escaping () -> Bool, screenFrame: @escaping () -> CGRect,
                     canFollow: @escaping () -> Bool, isConcealedForMissionControl: @escaping () -> Bool,
                     displayID: @escaping () -> CGDirectDisplayID?,
                     whenSettled: @escaping (@escaping () -> Void) -> Void,
                     move: @escaping (CGDirectDisplayID) -> Void) {
            self.isActive = isActive
            self.followsPointer = followsPointer
            self.hasWindow = hasWindow
            self.screenFrame = screenFrame
            self.canFollow = canFollow
            self.isConcealedForMissionControl = isConcealedForMissionControl
            self.displayID = displayID
            self.whenSettled = whenSettled
            self.move = move
        }
    }

    /// How long the pointer stays on another display before the island
    /// follows, so passing over a display edge does not move it.
    package static let delay: TimeInterval = 0.2

    private let environment: Environment
    private let island: Island
    private var monitors: [Any] = []
    private var cancelPending: (() -> Void)?

    package init(environment: Environment, island: Island) {
        self.environment = environment
        self.island = island
    }

    package var isWatching: Bool { !monitors.isEmpty }
    /// A move waits for the pointer to rest.
    package var hasPendingMove: Bool { cancelPending != nil }

    /// Watches movement while the island can follow the pointer to another
    /// display, and stops otherwise.
    package func sync() {
        guard island.isActive(), island.followsPointer(), island.hasWindow(), environment.displayCount() > 1 else {
            stop()
            return
        }
        guard monitors.isEmpty else { return }
        monitors = environment.addMonitors { [weak self] in self?.pointerMoved() }
    }

    package func stop() {
        monitors.forEach(environment.removeMonitor)
        monitors.removeAll()
        cancelPendingMove()
    }

    /// The pointer moved: a pointer away from the island's display brings it
    /// there after a moment, and one back on it drops the move.
    package func pointerMoved() {
        guard island.followsPointer(), island.hasWindow() else { return }
        guard !NSMouseInRect(environment.mouseLocation(), island.screenFrame(), false) else {
            cancelPendingMove()
            return
        }
        guard cancelPending == nil, island.canFollow() else { return }
        cancelPending = environment.schedule(Self.delay) { [weak self] in
            guard let self else { return }
            self.cancelPending = nil
            // A closing island finishes on the display it closed on.
            self.island.whenSettled { [weak self] in self?.follow() }
        }
    }

    private func follow() {
        guard island.isActive(), island.followsPointer(), island.canFollow(), !island.isConcealedForMissionControl(),
              let target = environment.displayWithMouse(), target != island.displayID() else { return }
        island.move(target)
    }

    private func cancelPendingMove() {
        cancelPending?()
        cancelPending = nil
    }
}
