// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Combine
import UniformTypeIdentifiers
import VitruvianCore
import VitruvianDesign

@MainActor
package final class URLCleanerService: ObservableObject {
    package static let shared = URLCleanerService(environment: .live)
    nonisolated private static let urlType = NSPasteboard.PasteboardType(UTType.url.identifier)

    /// What the cleaner reaches outside itself. The app's is the saved
    /// preferences, the shared clipboard lane, the general pasteboard and a
    /// run-loop timer. A test passes a suite and a pasteboard of its own, and
    /// runs the lane, the main queue and the timer by hand.
    package struct Environment {
        /// Where the hub's switch, the cleaner's own switch and the rules
        /// are saved.
        package var defaults: UserDefaults
        /// Runs work on the clipboard lane, off the main thread.
        package var lane: (@escaping @Sendable () -> Void) -> Void
        /// Hands work from the lane back to the main thread.
        package var main: @Sendable (@escaping @MainActor @Sendable () -> Void) -> Void
        /// The pasteboard to watch, asked for on the lane.
        package var pasteboard: @Sendable () -> NSPasteboard
        /// Starts a repeating tick on the main thread, given its interval
        /// and its tolerance. Calling the result stops it.
        package var every: (TimeInterval, TimeInterval, @escaping @MainActor () -> Void) -> (() -> Void)

        package init(defaults: UserDefaults,
                     lane: @escaping (@escaping @Sendable () -> Void) -> Void,
                     main: @escaping @Sendable (@escaping @MainActor @Sendable () -> Void) -> Void,
                     pasteboard: @escaping @Sendable () -> NSPasteboard,
                     every: @escaping (TimeInterval, TimeInterval, @escaping @MainActor () -> Void) -> (() -> Void)) {
            self.defaults = defaults
            self.lane = lane
            self.main = main
            self.pasteboard = pasteboard
            self.every = every
        }

        @MainActor package static let live = Environment(
            defaults: .standard,
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
    }

    @Published package private(set) var isRunning = false
    @Published package private(set) var lastCleaned: String?
    /// Names the last automatic clean took out, so Settings can say what the
    /// silent rewrite did rather than only that it is running.
    @Published package private(set) var lastRemoved: [String] = []

    /// `cancelled` sits under `lock`, so it is `@unchecked Sendable`.
    package final class PollToken: @unchecked Sendable {
        private let lock = NSLock()
        private var cancelled = false

        package init() {}

        package func cancel() {
            lock.lock()
            cancelled = true
            lock.unlock()
        }

        package var isCancelled: Bool {
            lock.lock()
            defer { lock.unlock() }
            return cancelled
        }
    }

    package struct PollResult {
        package let changeCount: Int
        package let cleaned: URLCleaning.Result?
    }

    private let environment: Environment
    private var stopTimer: (() -> Void)?
    private var lastChangeCount = 0
    private var pollInFlight = false
    private var pollToken: PollToken?

    package init(environment: Environment) {
        self.environment = environment
    }

    package func syncWithPreferences() {
        if AppFeature.urlCleaner.isAvailable(in: environment.defaults),
           environment.defaults[Preferences.urlCleanerEnabled] {
            start()
        } else {
            stop()
        }
    }

    package func clean(_ text: String) -> URLCleaning.Result? {
        URLCleaning.clean(text, rules: Self.rules(in: environment.defaults))
    }

    /// Writes on the shared lane and settles the change count on the main
    /// queue, where the poll compares against it. The caller never waits: the
    /// lane can be wedged behind an app that promised pasteboard content and
    /// stopped answering (issue #887).
    package func copy(_ urlString: String) {
        cancelPoll()
        lastCleaned = urlString
        let board = environment.pasteboard
        let main = environment.main
        environment.lane { [weak self] in
            let pasteboard = board()
            let changeCount = Self.writeToPasteboard(urlString, to: pasteboard)
            // Unlike a rewrite of what another app copied, this link is ours.
            pasteboard.declareVitruvianSource()
            main {
                guard let self else { return }
                self.lastChangeCount = max(self.lastChangeCount, changeCount)
            }
        }
    }

    package func stop() {
        stopTimer?()
        stopTimer = nil
        cancelPoll()
        isRunning = false
    }

    private func start() {
        guard stopTimer == nil else {
            isRunning = true
            return
        }
        stopTimer = environment.every(0.8, 0.25) { [weak self] in self?.cleanClipboardIfNeeded() }
        isRunning = true
        baselinePasteboard()
    }

    /// Reads the initial change count away from the main thread. It shares the
    /// same serial lane as Clipboard History, so neither service can race
    /// AppKit's pasteboard type cache while starting up.
    private func baselinePasteboard() {
        guard !pollInFlight else { return }
        let token = PollToken()
        pollToken = token
        pollInFlight = true
        let board = environment.pasteboard
        let main = environment.main
        environment.lane { [weak self] in
            guard !token.isCancelled else { return }
            let changeCount = board().changeCount
            main {
                guard let self, self.pollToken === token else { return }
                self.pollToken = nil
                self.pollInFlight = false
                guard self.isRunning else { return }
                self.lastChangeCount = changeCount
            }
        }
    }

    private func cleanClipboardIfNeeded() {
        guard !pollInFlight else { return }
        let sinceChangeCount = lastChangeCount
        let token = PollToken()
        pollToken = token
        pollInFlight = true
        let board = environment.pasteboard
        let main = environment.main
        // UserDefaults is safe to use from any thread.
        nonisolated(unsafe) let defaults = environment.defaults
        environment.lane { [weak self] in
            guard !token.isCancelled else { return }
            let result = Self.pollPasteboard(sinceChangeCount: sinceChangeCount, token: token,
                                             pasteboard: board(), defaults: defaults)
            main {
                guard let self, self.pollToken === token else { return }
                self.pollToken = nil
                self.pollInFlight = false
                guard self.isRunning, let result else { return }
                self.lastChangeCount = result.changeCount
                if let cleaned = result.cleaned {
                    self.lastCleaned = cleaned.url
                    self.lastRemoved = cleaned.removed
                }
            }
        }
    }

    /// Runs only on GeneralPasteboardAccess. Reading the change count, types
    /// and payload plus any rewrite is one serialized transaction.
    /// `pasteboard` and `rules` are the general pasteboard and the stored
    /// rules, except in the tests, which pass a private pasteboard.
    /// `defaults` is where the stored rules are read when `rules` is nil.
    nonisolated package static func pollPasteboard(sinceChangeCount: Int, token: PollToken,
                                                   pasteboard: NSPasteboard = .general,
                                                   rules: URLCleaning.Rules? = nil,
                                                   defaults: UserDefaults = .standard) -> PollResult? {
        let changeCount = pasteboard.changeCount
        guard !token.isCancelled else { return nil }
        guard changeCount != sinceChangeCount else {
            return PollResult(changeCount: changeCount, cleaned: nil)
        }

        // The types decide before any content is read: a picture or a file
        // is never fetched only to be left alone. Some "copy link" commands
        // put the link on the pasteboard only as a URL, with no text next
        // to it.

        // The rewrite is for a link something was actually taken out of. A
        // copy with nothing to remove is left exactly as the user put it,
        // because writing to the pasteboard discards whatever else the copy
        // carried, and a link the cleaner did not need to touch is the one
        // most likely to come back spelled differently.
        let types = (pasteboard.types ?? []).map(\.rawValue)
        guard URLCleaning.canRewritePasteboard(types: types),
              // The rewrite writes one item, so a copy of several is left alone.
              pasteboard.pasteboardItems?.count == 1,
              let text = pasteboard.string(forType: .string) ?? pasteboard.string(forType: urlType),
              let cleaned = URLCleaning.clean(text, rules: rules ?? Self.rules(in: defaults)),
              !cleaned.removed.isEmpty,
              !token.isCancelled else {
            return PollResult(changeCount: changeCount, cleaned: nil)
        }
        // The rewrite drops the HTML, which is only right when the HTML adds
        // nothing to the link but formatting.
        if types.contains("public.html"),
           !URLCleaning.markupAddsOnlyFormatting(pasteboard.string(forType: .html) ?? "", to: text) {
            return PollResult(changeCount: changeCount, cleaned: nil)
        }
        // Another app may have copied since the read. Nothing compares and
        // swaps across processes, so this narrows the window, not closes it.
        guard pasteboard.changeCount == changeCount else {
            return PollResult(changeCount: changeCount, cleaned: nil)
        }

        // The app the copy named as its source stays named, and a copy from
        // another device stays marked as one, so the clipboard history does
        // not credit the cleaned link to the app in front.
        let rewrittenChangeCount = writeToPasteboard(cleaned.url, source: pasteboard.string(forType: .source),
                                                     remote: types.contains("com.apple.is-remote-clipboard"),
                                                     to: pasteboard)
        return PollResult(changeCount: rewrittenChangeCount, cleaned: cleaned)
    }

    nonisolated private static func rules(in defaults: UserDefaults) -> URLCleaning.Rules {
        URLCleaning.rules(
            globalNames: defaults[Preferences.urlCleanerCustomParameters],
            siteNames: defaults[Preferences.urlCleanerSiteParameters],
            disabledNames: defaults[Preferences.urlCleanerDisabledParameters])
    }

    @discardableResult
    nonisolated private static func writeToPasteboard(_ urlString: String, source: String? = nil, remote: Bool = false,
                                                      to pasteboard: NSPasteboard = .general) -> Int {
        pasteboard.clearContents()
        pasteboard.setString(urlString, forType: .string)
        pasteboard.setString(urlString, forType: urlType)
        if let source { pasteboard.setString(source, forType: .source) }
        if remote { pasteboard.setData(Data(), forType: .remoteClipboard) }
        return pasteboard.changeCount
    }

    private func cancelPoll() {
        pollToken?.cancel()
        pollToken = nil
        pollInFlight = false
    }
}
