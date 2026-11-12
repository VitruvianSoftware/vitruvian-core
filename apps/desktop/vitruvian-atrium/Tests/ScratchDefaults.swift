// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

// The one way tests here open a UserDefaults suite. Kept the same, word for
// word below the licence lines, in every Swift test folder of the repository;
// `bazel run //tools/conformance:check` fails a test that calls
// UserDefaults(suiteName:) itself, or a copy of this file that differs.

import Foundation
import ObjectiveC

/// UserDefaults suites for tests, kept out of the account's real
/// ~/Library/Preferences.
///
/// A suite a test saves would otherwise stay there as a file for good:
/// taking the domain away leaves the file behind, empty. On 2026-11-02 some
/// 56,000 of them had stopped macOS saving any app's settings.
///
/// Under `bazel test`, //tools/swift-test-preferences already opens every
/// suite in a folder under the test's TEST_TMPDIR, and says so in
/// SWIFT_TEST_PREFERENCES_CONTAINER. Run any other way (`swift test`, Xcode),
/// a suite opened here goes to a folder of this process's own in the
/// temporary directory, through the same container initializer.
nonisolated enum ScratchDefaults {
    /// The suite called `name`. Opening it again, here or through
    /// `UserDefaults(suiteName:)` in the code under test, sees what was saved,
    /// as the app's next launch would.
    static func suite(named name: String) -> UserDefaults? {
        if ProcessInfo.processInfo.environment["SWIFT_TEST_PREFERENCES_CONTAINER"] != nil {
            return UserDefaults(suiteName: name)
        }
        guard let container = ownContainer,
              let method = class_getInstanceMethod(UserDefaults.self, containerInitializer),
              let allocated = UserDefaults.perform(NSSelectorFromString("alloc"))?.takeUnretainedValue()
        else {
            preconditionFailure("ScratchDefaults: no UserDefaults container to keep this test's preferences in")
        }
        // The initializer takes over the allocated object; leaving the one
        // reference unbalanced costs a few bytes for the run, where an extra
        // release would crash.
        typealias Initializer = @convention(c) (AnyObject, Selector, NSString, NSURL) -> UserDefaults?
        let initialize = unsafeBitCast(method_getImplementation(method), to: Initializer.self)
        return initialize(allocated, containerInitializer, name as NSString, container as NSURL)
    }

    private static let containerInitializer = NSSelectorFromString("_initWithSuiteName:container:")

    private static let ownContainer: URL? = {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("swift-test-preferences-\(getpid())-\(UUID().uuidString)", isDirectory: true)
        let preferences = folder.appendingPathComponent("Library/Preferences", isDirectory: true)
        guard UserDefaults.instancesRespond(to: containerInitializer),
              (try? FileManager.default.createDirectory(at: preferences, withIntermediateDirectories: true)) != nil
        else { return nil }
        return folder
    }()
}
