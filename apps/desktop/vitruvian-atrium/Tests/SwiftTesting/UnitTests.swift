// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import CoreFoundation
import Foundation
import Testing

/// The suite running now, for `reportEarlyExit`.
nonisolated(unsafe) private var runningSuite: String?

/// How many suites this run was asked for, and how many have finished, for
/// `reportEarlyExit`.
nonisolated(unsafe) private var expectedSuites = 0
nonisolated(unsafe) private var finishedSuites = 0

/// A run that ends the process early, by `exit`, `NSApp.terminate` or a
/// stopped main run loop, prints nothing of its own, and the process can end
/// with status 0. So an exit while a suite runs, or between two suites,
/// becomes an abort that says where the run was and prints the stack, which
/// still holds whatever ended it.
nonisolated private func reportEarlyExit() {
    if let name = runningSuite {
        print("the process exited while the \(name) suite was running")
    } else if finishedSuites < expectedSuites {
        print("the process exited between suites, after \(finishedSuites) of \(expectedSuites)")
    } else {
        return
    }
    Thread.callStackSymbols.forEach { print("  " + $0) }
    abort()
}

/// Every suite in `TestGroups` as a Swift Testing case. They run one at a time
/// on the main thread, from the app's directory, since they read repository
/// files by app-relative paths. Each prints its line (`notch: OK (…)`) and its
/// failed checks, and records each failed check as an issue.
@Suite(.serialized)
@MainActor
struct UnitTests {
    init() {
        // Line-buffered, so a suite that crashes the run still leaves the
        // names of the suites that finished before it in the test log.
        setvbuf(stdout, nil, _IOLBF, 0)
        _ = Self.exitReport
        expectedSuites = TestGroups.selected.count
        Self.enterAppDirectory()
    }

    private static let exitReport = atexit(reportEarlyExit)

    /// Whether the run loop below is running.
    private static var keepsRunLoop = false

    /// Puts the suites under a run loop of our own, which starts again
    /// whenever it is stopped, and returns once it is running.
    ///
    /// The process's outermost run loop belongs to Swift's async `main`,
    /// which takes a stopped main run loop to mean the program is over and
    /// calls `exit(0)`. An app's own loop (`NSApplication.run`) just goes
    /// round again, and HIToolbox relies on that: it stops the main run loop
    /// (`SignalMainThread`) each time an event reaches a process that has made
    /// a window. Under the bare loop, the first event to arrive between two
    /// suites ended the run with status 0 and no message.
    ///
    /// The loop starts from a timer, and this waits for it. A timer, because
    /// each suite arrives as a run loop block, and with this loop started
    /// from a block of its own no suite ever ran. Waited for, so that it
    /// starts under the outermost loop: left to fire when it would, it
    /// started inside a suite that was spinning the run loop, and that suite
    /// never got its turn back. The timer's block never returns; the process
    /// ends when Swift Testing calls `exit`.
    private static func keepRunLoop() async {
        guard !keepsRunLoop else { return }
        keepsRunLoop = true
        await withCheckedContinuation { (running: CheckedContinuation<Void, Never>) in
            let keeper = CFRunLoopTimerCreateWithHandler(nil, CFAbsoluteTimeGetCurrent(), 0, 0, 0) { _ in
                running.resume()
                while true {
                    CFRunLoopRunInMode(.defaultMode, .greatestFiniteMagnitude, false)
                }
            }
            CFRunLoopAddTimer(CFRunLoopGetMain(), keeper, .commonModes)
        }
    }

    @Test(arguments: TestGroups.selected)
    func runs(_ name: String) async {
        await Self.keepRunLoop()
        // A main-actor test runs inside a main-queue callout, and the run loop
        // drains no more of the main queue under one; the suites spin the run
        // loop to let queued main-queue work through. So each suite runs from
        // a run loop block instead, on the main thread, and its failures come
        // back here to be recorded.
        let failures = await withCheckedContinuation { (finished: CheckedContinuation<[String], Never>) in
            CFRunLoopPerformBlock(CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue) {
                finished.resume(returning: MainActor.assumeIsolated { Self.run(name) })
            }
            CFRunLoopWakeUp(CFRunLoopGetMain())
        }
        for failure in failures {
            Issue.record(Comment(rawValue: failure))
        }
    }

    /// The suite's failed checks, or why it could not run. `TestSuite.run`
    /// prints the suite's line and fails a suite that checks nothing.
    private static func run(_ name: String) -> [String] {
        let suite = TestSuite()
        guard let body = TestGroups.all(suite).first(where: { $0.0 == name })?.1 else {
            return ["no suite named \(name); the suites are \(TestGroups.names)"]
        }
        runningSuite = name
        suite.run(name, body)
        runningSuite = nil
        finishedSuites += 1
        if finishedSuites == 1 { stopMainRunLoop() }
        for failure in suite.failures {
            print("  - \(failure)")
        }
        return suite.failures
    }

    /// Stops the main run loop once the first suite has returned, which is
    /// what HIToolbox does (`SignalMainThread`) whenever an event reaches a
    /// process that has made a window: a key press, the pointer, an app
    /// switching in. On a Mac someone is using, that happens between suites
    /// within seconds; on a CI runner it may never happen. Doing it here makes
    /// every run, on every machine, prove that a stop does not end it.
    private static func stopMainRunLoop() {
        let main = CFRunLoopGetMain()
        CFRunLoopPerformBlock(main, CFRunLoopMode.commonModes.rawValue) { CFRunLoopStop(CFRunLoopGetMain()) }
        CFRunLoopWakeUp(main)
    }

    /// Bazel runs a test from its runfiles; the app's files sit below them
    /// at the package's own path.
    private static func enterAppDirectory() {
        let environment = ProcessInfo.processInfo.environment
        guard let runfiles = environment["TEST_SRCDIR"], let workspace = environment["TEST_WORKSPACE"] else { return }
        let app = "\(runfiles)/\(workspace)/apps/desktop/vitruvian"
        if FileManager.default.fileExists(atPath: app + "/Sources") {
            FileManager.default.changeCurrentDirectoryPath(app)
        }
    }
}
