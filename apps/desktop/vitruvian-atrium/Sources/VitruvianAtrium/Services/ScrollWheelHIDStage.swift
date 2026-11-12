// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Foundation
import VitruvianCore

/// Watches the HID stage for the wheel taps that sit further down, so they can
/// leave remote scrolling alone (see `ScrollWheelHIDStageLedger`).
///
/// The tap only notes each wheel event and hands it on untouched. It is an
/// active tap rather than a listener because the window server waits for an
/// active tap before passing the event on: the note is always there by the
/// time the event reaches the annotated stage, which a listener, told
/// asynchronously, could not promise. It lives on the pointer thread with the
/// other taps in the path of every wheel event, and only while a wheel tap
/// wants it.
// `@unchecked Sendable`: the lock guards its state across the pointer,
// wheel-tap and main threads.
package final class ScrollWheelHIDStage: @unchecked Sendable {
    package static let shared = ScrollWheelHIDStage()

    package enum Client: Hashable {
        case smoothScroll
        case wheelTap
    }

    /// Guards everything below; the callback runs on the pointer thread, the
    /// wheel taps ask from theirs and the main thread arms and tears down.
    private let lock = NSLock()
    private var ledger = ScrollWheelHIDStageLedger()
    private var clients = Set<Client>()
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    /// Main thread only, like `setWatching`.
    private var creationRetryUsed = false

    private init() {}

    /// Whether `event` came in at the HID stage. Answers yes while nothing
    /// is watching, so the wheel features never go dead with this tap.
    package func passed(_ event: CGEvent) -> Bool {
        let timestamp = event.timestamp
        let sourceProcessID = event.getIntegerValueField(.eventSourceUnixProcessID)
        return lock.withLock { ledger.passed(timestamp, sourceProcessID: sourceProcessID) }
    }

    /// Main thread. Each wheel tap asks for the watch while it runs; the tap
    /// goes back with the last one, and with them when the session switches
    /// away. A failed create gets one more try half a second later, as the
    /// wheel taps' own do, and again on the next request.
    package func setWatching(_ wanted: Bool, for client: Client) {
        let (port, source) = lock.withLock { () -> (CFMachPort?, CFRunLoopSource?) in
            if wanted {
                clients.insert(client)
            } else {
                clients.remove(client)
            }
            guard clients.isEmpty, tap != nil else { return (nil, nil) }
            let current = (tap, runLoopSource)
            tap = nil
            runLoopSource = nil
            ledger.reset()
            return current
        }
        if let port {
            CGEvent.tapEnable(tap: port, enable: false)
            if let source {
                PointerTapRunLoop.remove(source, invalidating: port)
            }
            return
        }
        guard wanted, lock.withLock({ tap == nil }) else { return }
        guard let created = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .tailAppendEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(1 << CGEventType.scrollWheel.rawValue),
            callback: { _, type, event, userInfo in
                guard let userInfo else { return Unmanaged.passUnretained(event) }
                let stage = Unmanaged<ScrollWheelHIDStage>.fromOpaque(userInfo).takeUnretainedValue()
                stage.handle(type: type, event: event)
                return Unmanaged.passUnretained(event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            // Without the watch remote scroll counts as local, so a create
            // that failed during the session handoff gets another look once
            // the switch settles.
            guard !creationRetryUsed else { return }
            creationRetryUsed = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                guard let self, let client = self.lock.withLock({ self.clients.first }) else { return }
                self.setWatching(true, for: client)
            }
            return
        }
        creationRetryUsed = false
        let createdSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, created, 0)
        lock.withLock {
            tap = created
            runLoopSource = createdSource
        }
        if let createdSource {
            PointerTapRunLoop.add(createdSource)
        }
        CGEvent.tapEnable(tap: created, enable: true)
        // Nothing is noted before the tap is on, so until then every event
        // still counts as having come through.
        lock.withLock { ledger.isWatching = true }
    }

    private func handle(type: CGEventType, event: CGEvent) {
        // Re-armed like the wheel taps, except in a session that was switched
        // away from, where they are about to hand this tap back.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if SessionActivity.shared.isActive, let port = lock.withLock({ tap }) {
                CGEvent.tapEnable(tap: port, enable: true)
            }
            return
        }
        guard type == .scrollWheel else { return }
        let timestamp = event.timestamp
        lock.withLock { ledger.note(timestamp) }
    }
}

// MARK: - Ledger

/// The wheel events that came in at the HID stage, told apart from those
/// posted further down the event path.
///
/// Both wheel taps sit at the annotated stage, which also sees scroll posted
/// at the session tap. That is where Screen Sharing, Apple Remote Desktop and
/// VNC post the controlling computer's scrolling, trackpad included, as
/// phaseless pixel events that read as a mouse wheel. Taps at the HID stage
/// never saw them, so they were never turned, capped or smoothed here; the
/// controlling computer already scrolled them its own way.
///
/// A hardware event carries source process id 0 and can only come in at the
/// HID stage, so it always counts. A posted one counts when the HID tap noted
/// its timestamp, which it keeps on its way down. Both readings are compared
/// as nanoseconds: at the HID stage a hardware event reads in mach ticks, a
/// posted one in nanoseconds (`EventTimestamp`, #1689). Events overtake one
/// another between the stages, so the last few hundred are kept rather than
/// only the newest.
package struct ScrollWheelHIDStageLedger {
    package static let capacity = 256
    /// A posted event reads the same at both stages; the slack only covers
    /// a rounding the system might do differently, and is far below the
    /// time between two wheel events.
    package static let tolerance: UInt64 = 1_000

    /// False while no HID tap is noting anything. Every event then counts as
    /// having come through, so a tap that could not be created leaves the
    /// wheel features working for local input rather than off.
    package var isWatching = false
    private var timestamps = [UInt64](repeating: 0, count: capacity)
    private var next = 0

    // Spelled out because a memberwise initializer never leaves its module.
    package init() {}

    /// `raw` is the timestamp as the tap reads it, in either unit.
    package mutating func note(_ raw: UInt64, nowTicks: UInt64 = mach_absolute_time(),
                               timebase: EventTimestamp.Timebase = EventTimestamp.machTimebase) {
        timestamps[next] = EventTimestamp.nanoseconds(raw: raw, nowTicks: nowTicks, timebase: timebase)
        next = (next + 1) % Self.capacity
    }

    package func passed(_ raw: UInt64, sourceProcessID: Int64, nowTicks: UInt64 = mach_absolute_time(),
                        timebase: EventTimestamp.Timebase = EventTimestamp.machTimebase) -> Bool {
        guard isWatching else { return true }
        guard sourceProcessID != 0 else { return true }
        guard raw != 0 else { return false }
        let nanoseconds = EventTimestamp.nanoseconds(raw: raw, nowTicks: nowTicks, timebase: timebase)
        return timestamps.contains { noted in
            noted != 0 && (noted >= nanoseconds ? noted - nanoseconds : nanoseconds - noted) <= Self.tolerance
        }
    }

    package mutating func reset() {
        isWatching = false
        timestamps = [UInt64](repeating: 0, count: Self.capacity)
        next = 0
    }
}
