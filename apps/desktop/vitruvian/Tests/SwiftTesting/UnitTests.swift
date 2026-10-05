// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import CoreFoundation
import Foundation
import Testing

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
        Self.enterAppDirectory()
    }

    @Test(arguments: TestGroups.selected)
    func runs(_ name: String) async {
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
        suite.run(name, body)
        for failure in suite.failures {
            print("  - \(failure)")
        }
        return suite.failures
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
