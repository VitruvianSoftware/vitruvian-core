// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import VitruvianCore

/// How often the island looks for Mission Control while it shows or hides
/// for it, and when a look is worth a frame probe. `NotchWindowHost` owns it
/// and passes in what it reads; tests pass a clock and an overview double.
@MainActor
package final class NotchMissionControlPolling {
    package struct Inputs {
        package var panelIsVisible: () -> Bool
        /// The island is hidden for an overview and waits to come back.
        package var concealed: () -> Bool
        /// The window list's answer: whether an overview covers the island's screen.
        package var overviewIsVisible: () -> Bool
        package var uptime: () -> TimeInterval
        /// Reads the desktop's frame, which waits up to a frame for the window server.
        package var sample: () -> Void

        package init(panelIsVisible: @escaping () -> Bool, concealed: @escaping () -> Bool,
                     overviewIsVisible: @escaping () -> Bool, uptime: @escaping () -> TimeInterval,
                     sample: @escaping () -> Void) {
            self.panelIsVisible = panelIsVisible
            self.concealed = concealed
            self.overviewIsVisible = overviewIsVisible
            self.uptime = uptime
            self.sample = sample
        }
    }

    // `nonisolated(unsafe)`: `deinit` reads it too, once nothing else holds the object.
    nonisolated(unsafe) package private(set) var timer: Timer?
    private var overviewWasVisible = false
    private var lastCheck: TimeInterval = -.infinity
    private var lastProbe: TimeInterval = -.infinity
    private let inputs: Inputs

    package init(inputs: Inputs) {
        self.inputs = inputs
    }

    deinit { timer?.invalidate() }

    package func sync() {
        updateTimer()
        if inputs.panelIsVisible() { refresh(now: true) }
    }

    package func stop() {
        timer?.invalidate()
        timer = nil
    }

    private var checkInterval: TimeInterval {
        overviewWasVisible || inputs.concealed() ? 0.08 : 0.25
    }

    private func updateTimer() {
        guard inputs.panelIsVisible() || inputs.concealed() else {
            timer?.invalidate()
            timer = nil
            return
        }
        let interval = checkInterval
        if timer?.timeInterval != interval {
            timer?.invalidate()
            let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
                // Added to the main run loop below, so it fires on the main thread.
                MainActor.assumeIsolated { self?.refresh() }
            }
            timer.tolerance = interval / 2
            self.timer = timer
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    package func refresh(now immediate: Bool = false) {
        let now = inputs.uptime()
        guard immediate || now - lastCheck >= checkInterval else { return }
        lastCheck = now
        // Most of the time no overview is up. Poll less often then, but keep
        // the original restore cadence and immediate checks before revealing.
        defer { updateTimer() }
        let overview = inputs.overviewIsVisible()
        let appeared = overview && !overviewWasVisible
        overviewWasVisible = overview
        // The window list costs a fraction of a millisecond; a probe reading
        // waits up to a frame for the window server. Without an overview the
        // desktop needs no reading at all. While one stays up the reading is
        // repeated slowly, and once it closes the desktop is confirmed promptly.
        let concealed = inputs.concealed()
        guard overview || concealed else { return }
        let interval = concealed && !overview ? 0.08 : 0.5
        guard immediate || appeared || now - lastProbe >= interval else { return }
        lastProbe = now
        inputs.sample()
    }
}
