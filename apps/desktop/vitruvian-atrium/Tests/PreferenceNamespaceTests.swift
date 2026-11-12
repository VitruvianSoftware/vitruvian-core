// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import VitruvianAtriumCore
import VitruvianAtriumDesign
import VitruvianAtriumServices
import VitruvianAtriumUI

/// A defaults suite a test opens never reaches the account's real
/// ~/Library/Preferences. Every test opens its suites through `ScratchDefaults`,
/// and under `bazel test` //tools/swift-test-preferences saves them, and
/// `UserDefaults.standard`, in a container folder under TEST_TMPDIR. Leftover
/// test suites in the real folder had grown to some 56,000 files by
/// 2026-11-02 and stopped macOS saving any app's settings.
/// `bazel run //tools/conformance:check` fails a test that opens a suite
/// any other way.
enum PreferenceNamespaceTests {
    static func run(_ suite: TestSuite) {
        let fileManager = FileManager.default
        guard let container = ProcessInfo.processInfo.environment["SWIFT_TEST_PREFERENCES_CONTAINER"] else {
            suite.expect(false, "the unit tests run with a preferences container of their own")
            return
        }
        let containerPreferences = container + "/Library/Preferences"
        let realPreferences = (getpwuid(getuid())?.pointee.pw_dir).map { String(cString: $0) + "/Library/Preferences" }
        suite.expect(realPreferences != nil, "the account's real preferences folder is found")
        guard let realPreferences else { return }

        func savedValue(_ key: String, in plist: String) -> Any? {
            guard let data = fileManager.contents(atPath: plist),
                  let values = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
            else { return nil }
            return values[key]
        }

        func eventually(_ condition: () -> Bool) -> Bool {
            let deadline = Date().addingTimeInterval(5)
            while !condition() {
                guard Date() < deadline else { return false }
                Thread.sleep(forTimeInterval: 0.05)
            }
            return true
        }

        let name = "vitru.tests.preference-namespace.\(UUID().uuidString)"
        guard let defaults = ScratchDefaults.suite(named: name) else {
            suite.expect(false, "a test opens a defaults suite")
            return
        }
        defaults.set(true, forKey: "saved")
        defaults.synchronize()
        suite.expect(eventually { fileManager.fileExists(atPath: containerPreferences + "/\(name).plist") },
                     "a test's defaults suite is saved in the test's own container")
        suite.expect(!fileManager.fileExists(atPath: realPreferences + "/\(name).plist"),
                     "a test's defaults suite never reaches ~/Library/Preferences")
        suite.expect(ScratchDefaults.suite(named: name)?.bool(forKey: "saved") == true,
                     "opening the suite again reads back what was saved")

        let key = "vitru.tests.preference-namespace.standard"
        let program = ProcessInfo.processInfo.processName
        UserDefaults.standard.set(true, forKey: key)
        UserDefaults.standard.synchronize()
        defer { UserDefaults.standard.removeObject(forKey: key) }
        suite.expect(eventually {
            (savedValue(key, in: containerPreferences + "/\(program).plist") as? Bool) == true
        }, "UserDefaults.standard saves in the test's own container")
        suite.expect(savedValue(key, in: realPreferences + "/\(program).plist") == nil,
                     "UserDefaults.standard never saves in ~/Library/Preferences")
    }
}
