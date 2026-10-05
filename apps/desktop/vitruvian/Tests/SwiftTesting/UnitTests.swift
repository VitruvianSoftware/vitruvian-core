// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import Foundation
import Testing

/// The suites the binary's runner runs, each as a Swift Testing case. They
/// run one at a time on the main actor, as the binary runs them, from the
/// app's directory, since they read repository files by app-relative paths.
@Suite(.serialized)
@MainActor
struct UnitTests {
    init() {
        Self.enterAppDirectory()
    }

    @Test(arguments: TestGroups.names)
    func runs(_ name: String) {
        let suite = TestSuite()
        guard let body = TestGroups.all(suite).first(where: { $0.0 == name })?.1 else {
            Issue.record(Comment(rawValue: "no suite named \(name)"))
            return
        }
        body()
        #expect(suite.checks > 0, "\(name) executed no assertions")
        for failure in suite.failures {
            Issue.record(Comment(rawValue: failure))
        }
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
