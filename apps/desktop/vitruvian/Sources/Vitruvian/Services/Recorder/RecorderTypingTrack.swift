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
package final class RecorderTypingSampler {
    private let pauseClock: RecorderPauseClock
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private let lock = NSLock()
    private var times: [Double] = []

    package init(pauseClock: RecorderPauseClock) {
        self.pauseClock = pauseClock
    }

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

    package func stop() -> RecorderTypingTrack {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        globalMonitor = nil
        localMonitor = nil
        return lock.withLock {
            let track = RecorderTypingTrack(times: times)
            times.removeAll()
            return track
        }
    }

    private func record(_ event: NSEvent) {
        guard !event.isARepeat else { return }
        let now = CACurrentMediaTime()
        lock.withLock {
            guard let time = pauseClock.eventTime(now) else { return }
            times.append(time)
        }
    }

    deinit {
        _ = stop()
    }
}
