// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import QuartzCore
import VitruvianCore
import VitruvianDesign

/// Moments when typing happened during one recording. No key or text is kept.
package struct RecorderTypingTrack: Codable, Equatable {
    package var times: [Double] = []

    package var isEmpty: Bool { times.isEmpty }

    package func encoded() -> Data? { try? JSONEncoder().encode(self) }

    package static func decoded(_ data: Data?) -> RecorderTypingTrack {
        guard let data, let value = try? JSONDecoder().decode(Self.self, from: data)
        else { return Self() }
        return value
    }

    // Spelled out because a memberwise initializer never leaves its module.
    package init(times: [Double] = []) {
        self.times = times
    }
}

/// The monitor exists only while recording and remembers timing, never keys.
/// `start()` and `stop()` are main-actor, so only the main thread touches the
/// monitors, and `times` sits under `lock`, so it is `@unchecked Sendable`.
package final class RecorderTypingSampler: @unchecked Sendable {
    private let pauseClock: RecorderPauseClock
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private let lock = NSLock()
    private var times: [Double] = []

    package init(pauseClock: RecorderPauseClock) {
        self.pauseClock = pauseClock
    }

    @MainActor
    package func start() {
        guard globalMonitor == nil, localMonitor == nil else { return }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.record(event)
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.record(event)
            return event
        }
    }

    @MainActor
    package func stop() -> RecorderTypingTrack {
        removeMonitors()
        return lock.withLock {
            let track = RecorderTypingTrack(times: times)
            times.removeAll()
            return track
        }
    }

    private func record(_ event: NSEvent) {
        guard !event.isARepeat else { return }
        record(at: CACurrentMediaTime())
    }

    /// One keystroke at `now` on the host clock, kept on the recording's own
    /// clock: nothing before it begins or while it is paused. The monitors
    /// call this while `stop()` may be reading, so the append is under the
    /// lock, the way the pointer sampler guards its buffer.
    package func record(at now: CFTimeInterval) {
        lock.withLock {
            guard let time = pauseClock.eventTime(now) else { return }
            times.append(time)
        }
    }

    private func removeMonitors() {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        globalMonitor = nil
        localMonitor = nil
    }

    /// The last reference can go on any thread, so this takes the monitors
    /// down directly rather than through the main-actor `stop()`; what was
    /// recorded goes with the sampler.
    deinit {
        removeMonitors()
    }
}
