// Copyright (c) 2026 VitruvianSoftware
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.


import Foundation
import ObjectiveC
import XCTest

/// What a test saves through UserDefaults lands in a container under its own
/// TEST_TMPDIR, and nothing reaches the account's real ~/Library/Preferences.
///
/// Every check that writes first makes sure the redirect is in place, so a
/// broken redirect fails here without itself leaving a file in the real folder.
final class TestPreferencesTests: XCTestCase {
    private let fileManager = FileManager.default

    /// The account's real preferences folder, from the user database: the one
    /// cfprefsd saves to when nothing redirects it.
    private var realPreferences: String {
        guard let entry = getpwuid(getuid()), let dir = entry.pointee.pw_dir else { return "/nonexistent" }
        return String(cString: dir) + "/Library/Preferences"
    }

    private var containerPreferences: String {
        get throws {
            let tmp = try XCTUnwrap(ProcessInfo.processInfo.environment["TEST_TMPDIR"])
            let container = try XCTUnwrap(ProcessInfo.processInfo.environment["SWIFT_TEST_PREFERENCES_CONTAINER"])
            XCTAssertTrue(container.hasPrefix(tmp + "/"), "the container \(container) is not under TEST_TMPDIR")
            return container + "/Library/Preferences"
        }
    }

    /// True when the method behind `selector` is ours, linked into this
    /// program, rather than Foundation's.
    private func isRedirected(_ selector: Selector, classMethod: Bool = false) -> Bool {
        let cls: AnyClass = UserDefaults.self
        guard let method = classMethod ? class_getClassMethod(cls, selector) : class_getInstanceMethod(cls, selector)
        else { return false }
        var info = Dl_info()
        let implementation = unsafeBitCast(method_getImplementation(method), to: UnsafeRawPointer.self)
        guard dladdr(implementation, &info) != 0, let image = info.dli_fname else { return false }
        return String(cString: image) == CommandLine.arguments[0]
            || URL(fileURLWithPath: String(cString: image)).resolvingSymlinksInPath()
                == URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
    }

    private func requireRedirect() throws {
        let suites = isRedirected(NSSelectorFromString("initWithSuiteName:"))
        let standard = isRedirected(NSSelectorFromString("standardUserDefaults"), classMethod: true)
            && isRedirected(NSSelectorFromString("persistentDomainForName:"))
        XCTAssertTrue(suites, "UserDefaults(suiteName:) is not redirected")
        XCTAssertTrue(standard, "UserDefaults.standard is not redirected")
        guard suites, standard else { throw XCTSkip("not writing anything: it would land in the real folder") }
    }

    private func waitFor(_ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            if condition() { return true }
            Thread.sleep(forTimeInterval: 0.05)
        }
        return condition()
    }

    func testASuiteIsSavedInTheTestsContainerOnly() throws {
        try requireRedirect()
        let name = "swift-test-preferences.probe.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defaults.set("saved", forKey: "probe")
        XCTAssertTrue(defaults.synchronize())

        let saved = try containerPreferences + "/\(name).plist"
        XCTAssertTrue(waitFor { fileManager.fileExists(atPath: saved) }, "the suite was not saved to \(saved)")
        XCTAssertFalse(fileManager.fileExists(atPath: realPreferences + "/\(name).plist"),
                       "the suite reached the real preferences folder")
        // A second instance, like the app's next launch, reads it back.
        XCTAssertEqual(UserDefaults(suiteName: name)?.string(forKey: "probe"), "saved")
    }

    func testStandardIsSavedInTheTestsContainerOnly() throws {
        try requireRedirect()
        let key = "swift-test-preferences.probe.\(UUID().uuidString)"
        UserDefaults.standard.set(true, forKey: key)
        XCTAssertTrue(UserDefaults.standard.synchronize())

        let program = ProcessInfo.processInfo.processName
        let saved = try containerPreferences + "/\(program).plist"
        XCTAssertTrue(waitFor {
            (NSDictionary(contentsOfFile: saved)?[key] as? Bool) == true
        }, "UserDefaults.standard did not save to \(saved)")
        XCTAssertNil(NSDictionary(contentsOfFile: realPreferences + "/\(program).plist")?[key],
                     "UserDefaults.standard reached the real preferences folder")
    }

    func testTakingADomainAwayThroughStandardStaysInTheContainer() throws {
        try requireRedirect()
        let name = "swift-test-preferences.probe.\(UUID().uuidString)"
        UserDefaults(suiteName: name)?.set(1, forKey: "probe")
        XCTAssertEqual(UserDefaults(suiteName: name)?.integer(forKey: "probe"), 1)

        UserDefaults.standard.removePersistentDomain(forName: name)
        XCTAssertNil(UserDefaults(suiteName: name)?.object(forKey: "probe"))
        XCTAssertFalse(fileManager.fileExists(atPath: realPreferences + "/\(name).plist"))
    }

    func testAPersistentDomainReadsBackFromTheContainer() throws {
        try requireRedirect()
        XCTAssertTrue(isRedirected(NSSelectorFromString("persistentDomainForName:")))
        let name = "swift-test-preferences.probe.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        XCTAssertNil(defaults.persistentDomain(forName: name), "a new suite has nothing saved")

        defaults.set(true, forKey: "saved")
        XCTAssertEqual(defaults.persistentDomain(forName: name)?["saved"] as? Bool, true)
        XCTAssertEqual(UserDefaults.standard.persistentDomain(forName: name)?["saved"] as? Bool, true)
        defaults.register(defaults: ["registered": true])
        XCTAssertNil(defaults.persistentDomain(forName: name)?["registered"], "registered values are not saved")

        defaults.setPersistentDomain(["replaced": 1], forName: name)
        XCTAssertEqual(defaults.persistentDomain(forName: name)?.keys.sorted(), ["replaced"])
        defaults.removePersistentDomain(forName: name)
        XCTAssertNil(defaults.persistentDomain(forName: name))
        XCTAssertFalse(fileManager.fileExists(atPath: realPreferences + "/\(name).plist"))
    }

    func testTheSystemsGlobalSettingsStillRead() throws {
        // Apps read the language and region from the global domain, through
        // standard and through every suite; the redirect leaves those alone.
        XCTAssertNotNil(UserDefaults.standard.array(forKey: "AppleLanguages"))
        XCTAssertNotNil(UserDefaults(suiteName: "swift-test-preferences.reader")?.array(forKey: "AppleLanguages"))
    }
}
