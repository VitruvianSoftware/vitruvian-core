// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import CoreFoundation
import Foundation
import Testing

/// The suites the binary's runner runs, each as a Swift Testing case. They
/// run one at a time on the main thread, as the binary runs them, from the
/// app's directory, since they read repository files by app-relative paths.
@Suite(.serialized)
@MainActor
struct UnitTests {
    init() {
        Self.enterAppDirectory()
    }

    @Test(arguments: TestGroups.names)
    func runs(_ name: String) async {
        // A main-actor test runs inside a main-queue callout, and the run loop
        // drains no more of the main queue under one; the suites spin the run
        // loop to let queued main-queue work through. So each suite runs from
        // a run loop block instead, on the main thread as under the binary's
        // runner, and its failures come back here to be recorded.
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

    /// The suite's failed checks, or why it could not run.
    private static func run(_ name: String) -> [String] {
        let suite = TestSuite()
        guard let body = TestGroups.all(suite).first(where: { $0.0 == name })?.1 else {
            return ["no suite named \(name)"]
        }
        body()
        return suite.checks > 0 ? suite.failures : suite.failures + ["\(name) executed no assertions"]
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
