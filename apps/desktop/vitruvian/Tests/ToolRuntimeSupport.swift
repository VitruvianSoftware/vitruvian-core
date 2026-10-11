// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import Foundation
import VitruvianCore
import VitruvianServices
import VitruvianToolProtocol

/// A clock a test moves by hand. Nothing on it happens until `advance`.
final class ManualToolClock: ToolClock {
    private final class Due: ToolTimer {
        let due: TimeInterval
        let order: Int
        var work: (@MainActor () -> Void)?

        init(due: TimeInterval, order: Int, work: @escaping @MainActor () -> Void) {
            self.due = due
            self.order = order
            self.work = work
        }

        func cancel() {
            work = nil
        }
    }

    private(set) var now: TimeInterval = 1_000
    private var timers: [Due] = []
    private var made = 0

    /// How many timers have still to run.
    var waiting: Int { timers.filter { $0.work != nil }.count }

    func after(_ delay: TimeInterval, _ work: @escaping @MainActor () -> Void) -> any ToolTimer {
        made += 1
        let timer = Due(due: now + max(0, delay), order: made, work: work)
        timers.append(timer)
        return timer
    }

    /// Moves time on by `seconds`. Each timer runs when its moment comes, the
    /// earliest first, and one that a timer sets runs too when it falls due.
    func advance(by seconds: TimeInterval) {
        let end = now + seconds
        while let next = timers.filter({ $0.work != nil && $0.due <= end })
            .min(by: { ($0.due, $0.order) < ($1.due, $1.order) }) {
            now = max(now, next.due)
            let work = next.work
            next.work = nil
            work?()
        }
        timers.removeAll { $0.work == nil }
        now = end
    }
}

enum ToolRuntimeSupport {
    /// Turns the run loop until `done` says so, for at most `seconds` of
    /// real time. True when it did. Only what starts a real program or
    /// reads the Mac's own clock needs this; everything else is moved by
    /// hand and never waits.
    @discardableResult
    static func wait(upTo seconds: TimeInterval = 20, until done: () -> Bool) -> Bool {
        let deadline = Date(timeIntervalSinceNow: seconds)
        while !done(), Date() < deadline {
            _ = RunLoop.main.run(mode: .default, before: Date(timeIntervalSinceNow: 0.005))
        }
        return done()
    }

    /// One line of JSON, as the bytes a tool would write.
    static func line(_ json: String) -> Data {
        Data((json + "\n").utf8)
    }
}
