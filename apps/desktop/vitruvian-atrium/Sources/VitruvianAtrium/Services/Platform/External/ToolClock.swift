// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import Foundation

/// Something a clock will do later, unless it is called off first.
@MainActor
package protocol ToolTimer: AnyObject {
    /// Calls it off. Safe to call twice, and after it has run.
    func cancel()
}

/// Time, as the tool runtime sees it. Every deadline, wait and limit of the
/// runtime is counted on one of these, so a test moves time by hand and
/// never waits for it.
@MainActor
package protocol ToolClock: AnyObject {
    /// Seconds on a clock that only goes forward.
    var now: TimeInterval { get }
    /// Runs `work` once, on the main actor, `delay` seconds from now.
    func after(_ delay: TimeInterval, _ work: @escaping @MainActor () -> Void) -> any ToolTimer
}

/// The Mac's own clock: seconds since it started, which do not count while
/// it sleeps. A deadline therefore never runs out because the lid was shut.
@MainActor
package final class SystemToolClock: ToolClock {
    package static let shared = SystemToolClock()

    private final class Scheduled: ToolTimer {
        private var work: (@MainActor () -> Void)?

        init(_ work: @escaping @MainActor () -> Void) {
            self.work = work
        }

        func fire() {
            let work = self.work
            self.work = nil
            work?()
        }

        func cancel() {
            work = nil
        }
    }

    package init() {}

    package var now: TimeInterval { ProcessInfo.processInfo.systemUptime }

    package func after(_ delay: TimeInterval, _ work: @escaping @MainActor () -> Void) -> any ToolTimer {
        let timer = Scheduled(work)
        DispatchQueue.main.asyncAfter(deadline: .now() + max(0, delay)) {
            MainActor.assumeIsolated { timer.fire() }
        }
        return timer
    }
}
