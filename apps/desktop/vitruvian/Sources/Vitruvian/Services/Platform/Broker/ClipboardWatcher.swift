// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import AppKit
import VitruvianCore

/// The broker's hold on the clipboard: the one timer that looks at it for
/// the tools that ask, and the reads and writes those tools make. Every
/// touch of the pasteboard runs on the shared clipboard lane, off the main
/// thread, and nobody waits for it: the lane can be wedged behind an app
/// that promised content and stopped answering (issue #887).
///
/// The timer runs only while a tool is watched for. The broker's checks
/// run when a watch starts; the tool host stops a tool that is removed.
@MainActor
package final class ClipboardWatcher {
    /// What the watcher reaches. The app's is the shared clipboard lane,
    /// the general pasteboard and a run-loop timer. A test passes a
    /// pasteboard of its own and runs the lane, the main queue and the
    /// timer by hand.
    package struct Environment {
        /// Runs work on the clipboard lane, off the main thread.
        package var lane: (@escaping @Sendable () -> Void) -> Void
        /// Hands work from the lane back to the main thread.
        package var main: @Sendable (@escaping @MainActor @Sendable () -> Void) -> Void
        /// The pasteboard, asked for on the lane.
        package var pasteboard: @Sendable () -> NSPasteboard
        /// Starts a repeating tick on the main thread, given its interval
        /// and its tolerance. Calling the result stops it.
        package var every: (TimeInterval, TimeInterval, @escaping @MainActor () -> Void) -> (() -> Void)

        package init(lane: @escaping (@escaping @Sendable () -> Void) -> Void,
                     main: @escaping @Sendable (@escaping @MainActor @Sendable () -> Void) -> Void,
                     pasteboard: @escaping @Sendable () -> NSPasteboard,
                     every: @escaping (TimeInterval, TimeInterval, @escaping @MainActor () -> Void) -> (() -> Void)) {
            self.lane = lane
            self.main = main
            self.pasteboard = pasteboard
            self.every = every
        }

        @MainActor package static let live = Environment(
            lane: { GeneralPasteboardAccess.shared.async($0) },
            main: { work in DispatchQueue.main.async { work() } },
            pasteboard: { .general },
            every: { interval, tolerance, tick in
                let timer = Timer(timeInterval: interval, repeats: true) { _ in
                    // Added to the main run loop below, so it fires on the main thread.
                    MainActor.assumeIsolated { tick() }
                }
                timer.tolerance = tolerance
                RunLoop.main.add(timer, forMode: .common)
                return { timer.invalidate() }
            })

        /// Runs nothing and starts no timer. For tests of other
        /// capabilities.
        package static var inert: Environment {
            Environment(lane: { _ in }, main: { _ in }, pasteboard: { .general }, every: { _, _, _ in {} })
        }
    }

    /// How often the clipboard is looked at, and how far the system may
    /// move a look to save power. These are the cadence the link cleaner
    /// has always had; a copy is noticed within a second.
    package static let interval: TimeInterval = 0.8
    package static let tolerance: TimeInterval = 0.25

    /// One tool's watch: its rule, and where it last saw the clipboard.
    @MainActor
    private final class Watch {
        let tool: ToolID
        let rule: ClipboardRewriteRule
        let onRewrite: @MainActor (ClipboardReplacement) -> Void
        var lastChangeCount = 0
        var lookInFlight = false
        var token: ClipboardPollToken?

        init(tool: ToolID, rule: ClipboardRewriteRule, onRewrite: @escaping @MainActor (ClipboardReplacement) -> Void) {
            self.tool = tool
            self.rule = rule
            self.onRewrite = onRewrite
        }
    }

    private let environment: Environment
    private var watches: [Watch] = []
    private var stopTimer: (() -> Void)?

    package init(environment: Environment) {
        self.environment = environment
    }

    /// True while the timer runs.
    package var isWatching: Bool { stopTimer != nil }

    // MARK: - Watching

    /// Starts looking at the clipboard for `tool`, and replacing a copied
    /// link when `rule` says so. `onRewrite` hears each replacement, on the
    /// main thread. A tool that is watched for already keeps its watch, so
    /// the timer's beat is not disturbed.
    package func start(for tool: ToolID, rule: ClipboardRewriteRule,
                       onRewrite: @escaping @MainActor (ClipboardReplacement) -> Void) {
        guard held(by: tool) == nil else { return }
        let watch = Watch(tool: tool, rule: rule, onRewrite: onRewrite)
        watches.append(watch)
        if stopTimer == nil {
            stopTimer = environment.every(Self.interval, Self.tolerance) { [weak self] in self?.tick() }
        }
        baseline(watch)
    }

    /// Stops looking for `tool`. A look of its that is waiting on the lane
    /// does nothing when its turn comes. The timer stops with the last
    /// watch.
    package func stop(for tool: ToolID) {
        guard let index = watches.firstIndex(where: { $0.tool == tool }) else { return }
        let watch = watches.remove(at: index)
        if watches.isEmpty {
            stopTimer?()
            stopTimer = nil
        }
        callOff(watch)
    }

    /// The watch `tool` holds, when it has one.
    private func held(by tool: ToolID) -> Watch? {
        watches.first { $0.tool == tool }
    }

    private func tick() {
        for watch in watches { look(watch) }
    }

    /// Reads the change count the clipboard stands at when a watch starts,
    /// away from the main thread, so what was copied before is never taken
    /// for a new copy. It shares the lane with Clipboard History, so
    /// neither can race AppKit's pasteboard type cache while starting up.
    private func baseline(_ watch: Watch) {
        guard !watch.lookInFlight else { return }
        let token = ClipboardPollToken()
        watch.token = token
        watch.lookInFlight = true
        let board = environment.pasteboard
        let main = environment.main
        environment.lane { [weak self, weak watch] in
            guard !token.isCancelled else { return }
            let changeCount = board().changeCount
            main {
                guard let self, let watch, watch.token === token else { return }
                watch.token = nil
                watch.lookInFlight = false
                guard self.watches.contains(where: { $0 === watch }) else { return }
                watch.lastChangeCount = changeCount
            }
        }
    }

    /// One look for one watch. Skipped while its last look has not
    /// answered, so a wedged lane never piles looks up.
    private func look(_ watch: Watch) {
        guard !watch.lookInFlight else { return }
        let sinceChangeCount = watch.lastChangeCount
        let token = ClipboardPollToken()
        watch.token = token
        watch.lookInFlight = true
        let rule = watch.rule
        let board = environment.pasteboard
        let main = environment.main
        environment.lane { [weak self, weak watch] in
            guard !token.isCancelled else { return }
            let result = ClipboardRewrite.poll(since: sinceChangeCount, token: token, rule: rule, pasteboard: board())
            main {
                guard let self, let watch, watch.token === token else { return }
                watch.token = nil
                watch.lookInFlight = false
                guard self.watches.contains(where: { $0 === watch }), let result else { return }
                watch.lastChangeCount = result.changeCount
                if let replaced = result.replaced { watch.onRewrite(replaced) }
            }
        }
    }

    private func callOff(_ watch: Watch) {
        watch.token?.cancel()
        watch.token = nil
        watch.lookInFlight = false
    }

    // MARK: - Reading and writing

    /// The clipboard's text, read on the lane and handed back on the main
    /// thread. Nil when it holds none.
    package func readText(completion: @escaping @MainActor (String?) -> Void) {
        let board = environment.pasteboard
        let main = environment.main
        environment.lane {
            let text = board().string(forType: .string)
            main { completion(text) }
        }
    }

    /// Replaces the clipboard with a link `tool` made itself: as text and
    /// as a URL, signed as the app's own. A look of that tool's that is
    /// waiting is called off first, and once the write is done its watch
    /// counts the clipboard as seen up to the count read before signing, so
    /// the tool's own write is not a new copy to it.
    package func writeLink(_ link: String, by tool: ToolID, completion: @escaping @MainActor () -> Void) {
        if let watch = held(by: tool) { callOff(watch) }
        let board = environment.pasteboard
        let main = environment.main
        environment.lane { [weak self] in
            let pasteboard = board()
            let changeCount = ClipboardRewrite.write(link, to: pasteboard)
            // Unlike a rewrite of what another app copied, this link is the app's own.
            pasteboard.declareVitruvianSource()
            main {
                if let self, let watch = self.held(by: tool) {
                    watch.lastChangeCount = max(watch.lastChangeCount, changeCount)
                }
                completion()
            }
        }
    }
}
