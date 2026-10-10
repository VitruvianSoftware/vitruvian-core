// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import AppKit
import Foundation
import VitruvianCore
import VitruvianServices

/// The URL cleaner over a clipboard and a preference suite of its own, with
/// the clipboard lane, the main queue and the timer run by hand. Nothing here
/// touches the real clipboard, and no test waits for a timer.
@MainActor
enum URLCleanerTests {
    static let dirty = "https://example.com/path?utm_source=news&id=42"
    static let cleaned = "https://example.com/path?id=42"

    static func run(_ suite: TestSuite) {
        runRule(suite)
        automaticClean(suite)
        whatIsLeftAlone(suite)
        stopping(suite)
        copyByHand(suite)
        oneLook(suite)
    }

    /// The cleaner's outside world for one test. Only the test's own thread
    /// touches it.
    nonisolated final class CleanerRig: @unchecked Sendable {
        let board = NSPasteboard.withUniqueName()
        let defaults: UserDefaults
        var lane: [@Sendable () -> Void] = []
        var main: [() -> Void] = []
        /// The tick of each timer that is running, by the order it started.
        var ticks: [Int: () -> Void] = [:]
        var started: [(interval: TimeInterval, tolerance: TimeInterval)] = []
        var stopped = 0
        /// What a tool said on screen, as "symbol: message".
        var said: [String] = []
        /// The capabilities and preference keys a tool used without
        /// declaring them.
        var undeclared: [String] = []

        init() {
            let domain = "com.vitruviansoftware.vitruvian.tests.url-cleaner"
            let defaults = UserDefaults(suiteName: domain)!
            defaults.removePersistentDomain(forName: domain)
            self.defaults = defaults
            board.clearContents()
        }

        func close() {
            defaults.removePersistentDomain(forName: "com.vitruviansoftware.vitruvian.tests.url-cleaner")
            board.releaseGlobally()
        }

        /// Installs or removes the feature in the hub, and flips its own
        /// switch.
        func set(installed: Bool, enabled: Bool) {
            defaults.set(installed, forKey: AppFeature.urlCleaner.availabilityKey)
            defaults.set(enabled, forKey: DefaultsKey.urlCleanerEnabled)
        }

        /// Runs what waits on the lane, then what that handed to the main
        /// queue, until both are empty.
        func settle() {
            while !lane.isEmpty || !main.isEmpty {
                while !lane.isEmpty { lane.removeFirst()() }
                while !main.isEmpty { main.removeFirst()() }
            }
        }

        /// Fires every running timer once, as the run loop would.
        func tick() {
            for key in ticks.keys.sorted() { ticks[key]?() }
        }

        func startTimer(_ interval: TimeInterval, _ tolerance: TimeInterval,
                        _ tick: @escaping @MainActor () -> Void) -> () -> Void {
            let key = started.count
            started.append((interval, tolerance))
            ticks[key] = { MainActor.assumeIsolated { tick() } }
            return { [self] in
                ticks[key] = nil
                stopped += 1
            }
        }

        /// Copies as another app would: one item, its text, and the app's
        /// name when it gives one.
        func copy(_ text: String, source: String? = nil) {
            board.clearContents()
            if let source { board.setString(source, forType: .source) }
            board.setString(text, forType: .string)
        }

        var text: String? { board.string(forType: .string) }

        /// The clipboard, its lane and its timer, as the broker reaches them.
        var watching: ClipboardWatcher.Environment {
            ClipboardWatcher.Environment(
                lane: { [self] in lane.append($0) },
                main: { [self] work in main.append { MainActor.assumeIsolated { work() } } },
                pasteboard: { [self] in board },
                every: { [self] in startTimer($0, $1, $2) })
        }

        /// A broker whose hub, preferences, clipboard and screen are this
        /// rig's.
        @MainActor func broker() -> CapabilityBroker {
            CapabilityBroker(
                environment: .init(
                    isInstalled: { [self] id in AppFeature(rawValue: id.rawValue)?.isAvailable(in: defaults) ?? true },
                    isGranted: { _ in true },
                    allows: { _, _ in true },
                    reportUndeclared: { [self] _, capability in undeclared.append(capability.rawValue) }),
                backings: .init(
                    notify: .init(beep: {}, hud: { [self] icon, message in said.append("\(icon): \(message)") }),
                    open: .init(open: { _ in true }),
                    clipboard: .init(write: { _, _ in }, watching: watching),
                    processes: .inert,
                    storage: .init(read: { [self] in defaults.object(forKey: $0) },
                                   undeclaredKey: { [self] in undeclared.append($0) })))
        }
    }

    /// The cleaner over `rig`, and how the app re-decides whether it runs.
    static func bench(_ rig: CleanerRig) -> (cleaner: URLCleanerService, sync: () -> Void) {
        let cleaner = URLCleanerService(environment: .init(
            defaults: rig.defaults,
            lane: { rig.lane.append($0) },
            main: { work in rig.main.append { MainActor.assumeIsolated { work() } } },
            pasteboard: { rig.board },
            every: { rig.startTimer($0, $1, $2) }))
        return (cleaner, { cleaner.syncWithPreferences() })
    }

    /// Whether this Mac's pasteboard counts the app's signature, written
    /// after the copy it signs, as one more change.
    static func signingMovesTheCount() -> Bool {
        let probe = NSPasteboard.withUniqueName()
        defer { probe.releaseGlobally() }
        probe.clearContents()
        probe.setString("a", forType: .string)
        let counted = probe.changeCount
        probe.declareVitruvianSource()
        return probe.changeCount != counted
    }

    /// Installed in the hub and switched on: the cleaner watches. Anything
    /// else: it does not.
    static func runRule(_ suite: TestSuite) {
        for installed in [false, true] {
            for enabled in [false, true] {
                let rig = CleanerRig()
                rig.set(installed: installed, enabled: enabled)
                let (cleaner, sync) = bench(rig)
                sync()
                let wanted = installed && enabled
                suite.expect(cleaner.isRunning == wanted && rig.ticks.count == (wanted ? 1 : 0),
                             "installed \(installed), switched on \(enabled): the cleaner "
                                 + (wanted ? "watches the clipboard" : "leaves the clipboard alone"))
                rig.close()
            }
        }

        let rig = CleanerRig()
        defer { rig.close() }
        rig.set(installed: true, enabled: true)
        let (cleaner, sync) = bench(rig)
        sync()
        suite.expect(rig.started.count == 1 && rig.started[0].interval == 0.8 && rig.started[0].tolerance == 0.25,
                     "the cleaner looks at the clipboard every 0.8 seconds, give or take a quarter")
        sync()
        suite.expect(rig.started.count == 1 && cleaner.isRunning,
                     "deciding again while it runs starts no second timer")
        rig.set(installed: true, enabled: false)
        sync()
        suite.expect(!cleaner.isRunning && rig.ticks.isEmpty && rig.stopped == 1,
                     "switching it off stops the timer at once")
        sync()
        suite.expect(rig.stopped == 1, "deciding again while it is off stops nothing twice")
        rig.set(installed: true, enabled: true)
        sync()
        suite.expect(cleaner.isRunning && rig.started.count == 2 && rig.ticks.count == 1,
                     "switching it back on starts a new timer")
    }

    static func automaticClean(_ suite: TestSuite) {
        let rig = CleanerRig()
        defer { rig.close() }
        rig.set(installed: true, enabled: true)
        // A link that was already on the clipboard when the cleaner started.
        rig.copy(dirty)
        let (cleaner, sync) = bench(rig)
        sync()
        suite.expect(rig.lane.count == 1, "starting takes one look, to know where the clipboard stands")
        rig.tick()
        suite.expect(rig.lane.count == 1, "a tick waits for the look before it to answer")
        rig.settle()
        rig.tick()
        rig.settle()
        suite.expect(rig.text == dirty && cleaner.lastCleaned == nil,
                     "a link copied before the cleaner started is left alone")

        rig.copy(dirty, source: "com.example.reader")
        rig.tick()
        suite.expect(rig.lane.count == 1 && rig.text == dirty,
                     "a tick puts one look on the clipboard lane, and nothing changes until the lane runs it")
        rig.settle()
        suite.expect(rig.text == cleaned && rig.board.string(forType: .URL) == cleaned
                         && rig.board.string(forType: .source) == "com.example.reader",
                     "a copied link with tracking parts is replaced, as text and as a link, and keeps the app it named")
        suite.expect(cleaner.lastCleaned == cleaned && cleaner.lastRemoved == URLCleaning.clean(dirty)?.removed
                         && !cleaner.lastRemoved.isEmpty,
                     "the cleaner says what it cleaned and what it took out")

        // Its own rewrite is not a new copy: a rule that would change the
        // cleaned link is not applied to it.
        rig.defaults.set("id", forKey: DefaultsKey.urlCleanerCustomParameters)
        rig.tick()
        rig.settle()
        suite.expect(rig.text == cleaned, "the cleaner does not look again at what it wrote itself")
        rig.copy("https://example.com/a?id=7&page=2")
        rig.tick()
        rig.settle()
        suite.expect(rig.text == "https://example.com/a?page=2" && cleaner.lastRemoved == ["id"],
                     "a rule saved in Settings is read at the next copy")
        suite.expect(cleaner.clean("https://example.com/b?id=1&page=3")?.url == "https://example.com/b?page=3",
                     "the field in Settings cleans under the saved rules")
    }

    /// What the automatic clean must not touch.
    static func whatIsLeftAlone(_ suite: TestSuite) {
        let rig = CleanerRig()
        defer { rig.close() }
        rig.set(installed: true, enabled: true)
        let (cleaner, sync) = bench(rig)
        sync()
        rig.settle()
        func look() {
            rig.tick()
            rig.settle()
        }

        rig.copy("https://example.com/?id=42")
        var count = rig.board.changeCount
        look()
        suite.expect(rig.board.changeCount == count && cleaner.lastCleaned == nil,
                     "a link with nothing to take out is left exactly as it was copied")

        rig.copy("not a link ?utm_source=x")
        count = rig.board.changeCount
        look()
        suite.expect(rig.board.changeCount == count, "text that is not a link is left alone")

        rig.board.clearContents()
        rig.board.setString(dirty, forType: .string)
        rig.board.setData(Data([0x89, 0x50, 0x4E, 0x47]), forType: .png)
        count = rig.board.changeCount
        look()
        suite.expect(rig.board.changeCount == count && rig.text == dirty,
                     "a link beside a picture is the picture's fallback, and is left alone")

        rig.board.clearContents()
        rig.board.setString(dirty, forType: .string)
        rig.board.setString("secret", forType: NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType"))
        count = rig.board.changeCount
        look()
        suite.expect(rig.board.changeCount == count && rig.text == dirty,
                     "a copy marked as a secret is left alone")

        rig.board.clearContents()
        rig.board.setString(dirty, forType: .string)
        rig.board.setString("<p>Read <a href=\"\(dirty)\">this</a> and <a href=\"https://other.example/\">that</a></p>",
                            forType: .html)
        count = rig.board.changeCount
        look()
        suite.expect(rig.board.changeCount == count && rig.text == dirty,
                     "a link whose HTML says more than the link is left alone")

        rig.board.clearContents()
        rig.board.setString(dirty, forType: .string)
        rig.board.setString("<a href=\"\(dirty)\">\(dirty)</a>", forType: .html)
        look()
        suite.expect(rig.text == cleaned && rig.board.string(forType: .html) == nil,
                     "a link whose HTML only formats it is cleaned, and the formatting goes")

        rig.board.clearContents()
        rig.board.setString(dirty, forType: .URL)
        look()
        suite.expect(rig.text == cleaned && rig.board.string(forType: .URL) == cleaned,
                     "a link copied only as a link, with no text beside it, is cleaned too")
    }

    static func stopping(_ suite: TestSuite) {
        let rig = CleanerRig()
        defer { rig.close() }
        rig.set(installed: true, enabled: true)
        let (cleaner, sync) = bench(rig)
        sync()
        rig.settle()

        rig.copy(dirty)
        rig.tick()
        rig.set(installed: true, enabled: false)
        sync()
        suite.expect(!cleaner.isRunning && rig.ticks.isEmpty && rig.lane.count == 1,
                     "switching the cleaner off while a look waits stops the timer and leaves the look on the lane")
        rig.settle()
        suite.expect(rig.text == dirty && cleaner.lastCleaned == nil,
                     "a look that was waiting when the cleaner was switched off changes nothing")

        rig.set(installed: true, enabled: true)
        sync()
        rig.settle()
        rig.tick()
        rig.settle()
        suite.expect(cleaner.isRunning && rig.text == dirty,
                     "switched back on, it starts from the clipboard as it is")

        rig.copy(dirty)
        rig.set(installed: false, enabled: true)
        sync()
        rig.tick()
        rig.settle()
        suite.expect(!cleaner.isRunning && rig.text == dirty, "removing the feature in the hub stops it")
    }

    static func copyByHand(_ suite: TestSuite) {
        let rig = CleanerRig()
        defer { rig.close() }
        rig.set(installed: true, enabled: true)
        let (cleaner, sync) = bench(rig)
        sync()
        rig.settle()
        let manual = "https://example.com/by-hand"

        // A copy by hand while a look waits calls the look off.
        rig.copy(dirty)
        rig.tick()
        cleaner.copy(manual)
        suite.expect(cleaner.lastCleaned == manual,
                     "a copy by hand is the last cleaned link at once, before the clipboard answers")
        rig.settle()
        suite.expect(rig.text == manual && rig.board.string(forType: .URL) == manual
                         && rig.board.string(forType: .source) == Bundle.main.bundleIdentifier,
                     "a copy by hand puts the link on the clipboard as text and as a link, signed as the app's own")
        suite.expect(cleaner.lastCleaned == manual && cleaner.lastRemoved.isEmpty,
                     "the look it called off reports nothing")

        // After its own copy the cleaner settles on the count it read before
        // it signed the copy. Whether signing moves the count is the
        // pasteboard's business; either way the next tick does what it does
        // today.
        let signingMoves = signingMovesTheCount()
        cleaner.copy(dirty)
        rig.settle()
        rig.tick()
        rig.settle()
        suite.expect(rig.text == (signingMoves ? cleaned : dirty),
                     "after a copy by hand the cleaner looks at the link again only if signing it moved the clipboard's count")

        rig.set(installed: true, enabled: false)
        sync()
        cleaner.copy(manual)
        rig.settle()
        suite.expect(rig.text == manual && !cleaner.isRunning,
                     "a copy by hand works while automatic cleaning is switched off")
    }

    /// One look at a clipboard, as the lane runs it. `since` is the count
    /// the cleaner last knew; `cancelled` is a look called off before it ran.
    static func look(at board: NSPasteboard, since: Int, cancelled: Bool = false)
        -> (changeCount: Int, cleaned: URLCleaning.Result?)? {
        let token = URLCleanerService.PollToken()
        if cancelled { token.cancel() }
        return URLCleanerService.pollPasteboard(sinceChangeCount: since, token: token, pasteboard: board,
                                                rules: URLCleaning.Rules.none)
            .map { (changeCount: $0.changeCount, cleaned: $0.cleaned) }
    }

    static func oneLook(_ suite: TestSuite) {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        board.clearContents()
        board.setString(dirty, forType: .string)
        let before = board.changeCount

        let same = look(at: board, since: before)
        suite.expect(same?.changeCount == before && same?.cleaned == nil && board.string(forType: .string) == dirty,
                     "a clipboard that has not changed since the last look is left alone")
        suite.expect(look(at: board, since: before - 1, cancelled: true) == nil
                         && board.string(forType: .string) == dirty && board.changeCount == before,
                     "a look that was called off answers nothing and changes nothing")
        let rewritten = look(at: board, since: before - 1)
        suite.expect(rewritten?.cleaned?.url == cleaned && rewritten?.changeCount == board.changeCount
                         && board.changeCount != before,
                     "a look that rewrites answers with the clipboard's count after the rewrite")
    }
}
