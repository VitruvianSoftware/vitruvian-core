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

import AppKit
import XCTest

import HomeSpeakerCore
import HomeSpeakerToolCore

// Closing the app when the person picks the extension (design 7.4, step 3).
// Every part here is a stand-in: the running apps, the program run and the
// file manager. The "app" is a folder in the temporary folder, its program
// an empty file that is never run. Nothing here reaches this Mac's
// HomeSpeaker.

/// A running application, as `NSRunningApplication` describes it.
private final class StandInApp: RunningAppHandle, @unchecked Sendable {
    let bundleIdentifier: String?
    let activationPolicy: NSApplication.ActivationPolicy
    /// False for an app that ignores being asked to quit.
    let quitsWhenAsked: Bool
    private(set) var askedToQuit = false

    init(_ policy: NSApplication.ActivationPolicy, bundleIdentifier: String? = HomeSpeakerProfile.appBundleID,
         quitsWhenAsked: Bool = true) {
        self.bundleIdentifier = bundleIdentifier
        activationPolicy = policy
        self.quitsWhenAsked = quitsWhenAsked
    }

    func terminate() -> Bool {
        askedToQuit = true
        return quitsWhenAsked
    }

    var gone: Bool { askedToQuit && quitsWhenAsked }
}

/// This Mac, as the app's controller sees it: what is running, and each
/// run of the app's program, answered with `answer`.
private final class StandInMac: @unchecked Sendable {
    var apps: [StandInApp] = []
    var runs: [(program: URL, arguments: [String])] = []
    var answer = ProgramRun(status: 0, output: "login item: disabled\n", error: "")
    var waited: [Double] = []

    func running() -> [any RunningAppHandle] { apps.filter { !$0.gone } }

    func run(_ program: URL, _ arguments: [String]) -> ProgramRun {
        runs.append((program, arguments))
        return answer
    }
}

/// The Finder's part: records each call, and moves or removes nothing.
private final class StandInWorkspace: FileManager, @unchecked Sendable {
    private(set) var calls: [String] = []

    override func trashItem(at url: URL, resultingItemURL outResultingURL: AutoreleasingUnsafeMutablePointer<NSURL?>?) throws {
        calls.append("recycle \(url.path)")
        outResultingURL?.pointee = URL(fileURLWithPath: "/stand-in/.Trash/\(url.lastPathComponent)") as NSURL
    }

    override func removeItem(at URL: URL) throws { calls.append("removeItem \(URL.path)") }
    override func removeItem(atPath path: String) throws { calls.append("removeItem \(path)") }
}

final class OtherAppTests: XCTestCase {
    private var folder: URL!
    private var mac: StandInMac!
    private var workspace: StandInWorkspace!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("homespeaker-other-app-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        mac = StandInMac()
        workspace = StandInWorkspace()
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    /// `<folder>/<place>/HomeSpeaker.app` with `version` in its Info.plist
    /// (none when nil), and its program: an empty file, never run.
    private func makeApp(version: String?, in place: String = "Applications") throws -> URL {
        let bundle = folder.appendingPathComponent(place).appendingPathComponent("HomeSpeaker.app")
        let macOS = bundle.appendingPathComponent("Contents/MacOS")
        try FileManager.default.createDirectory(at: macOS, withIntermediateDirectories: true)
        if let version { try writeVersion(version, to: bundle) }
        let program = macOS.appendingPathComponent("HomeSpeaker")
        try Data().write(to: program)
        return program
    }

    private func writeVersion(_ version: String, to bundle: URL) throws {
        let plist: [String: Any] = ["CFBundleIdentifier": HomeSpeakerProfile.appBundleID,
                                    "CFBundleShortVersionString": version]
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            .write(to: bundle.appendingPathComponent("Contents/Info.plist"))
    }

    private func app(program: URL?) -> SystemOtherApp {
        let mac = self.mac!
        return SystemOtherApp(program: program, runningApps: { mac.running() },
                              run: { mac.run($0, $1) }, fileManager: workspace,
                              wait: { mac.waited.append($0) })
    }

    // MARK: Quitting

    func testQuitAsksOnlyTheMenuBarApp() async throws {
        let script = StandInApp(.prohibited)
        let menuBar = StandInApp(.accessory)
        let stranger = StandInApp(.regular, bundleIdentifier: "com.example.other")
        mac.apps = [script, menuBar, stranger]
        let other = app(program: try makeApp(version: "1.19.0"))
        XCTAssertTrue(other.isRunning)

        let quit = await other.quit(timeout: 5)

        XCTAssertTrue(quit)
        XCTAssertTrue(menuBar.askedToQuit, "the menu bar app is asked to quit")
        XCTAssertFalse(script.askedToQuit, "a command-line run of the app's program (a script's --say) is never stopped")
        XCTAssertFalse(stranger.askedToQuit, "another app is never stopped")
        XCTAssertFalse(other.isRunning)
    }

    func testQuitWithOnlyACommandLineRunHasNothingToDo() async throws {
        let script = StandInApp(.prohibited)
        mac.apps = [script]
        let other = app(program: try makeApp(version: "1.19.0"))
        XCTAssertFalse(other.isRunning, "a command-line run is not the app running")

        let quit = await other.quit(timeout: 5)

        XCTAssertTrue(quit)
        XCTAssertFalse(script.askedToQuit)
        XCTAssertEqual(mac.waited, [], "nothing to wait for")
    }

    func testQuitSaysWhenTheAppStaysOpen() async throws {
        let stubborn = StandInApp(.accessory, quitsWhenAsked: false)
        mac.apps = [stubborn]
        let other = app(program: try makeApp(version: "1.19.0"))

        let quit = await other.quit(timeout: 2)

        XCTAssertFalse(quit, "still running when the time is up")
        XCTAssertTrue(stubborn.askedToQuit)
        XCTAssertEqual(mac.waited.reduce(0, +), 2, accuracy: 0.001, "waits the whole timeout, and no longer")
    }

    // MARK: The login item

    func testTheLoginItemIsTurnedOffByTheAppsOwnProgram() async throws {
        let program = try makeApp(version: "1.18.0")
        let other = app(program: program)

        let result = await other.turnOffLoginItem()

        XCTAssertNoThrow(try result.get())
        XCTAssertEqual(mac.runs.map(\.program), [program])
        XCTAssertEqual(mac.runs.map(\.arguments), [["--login-item", "disable"]])
    }

    func testANotFoundLoginItemIsOffToo() async throws {
        // The app's own --login-item disable ends 0 with "not found": there
        // is nothing to start at login. Judged by how the program ended and
        // ProcessDriver.result's reading, not by the words alone.
        mac.answer = ProgramRun(status: 0, output: "login item: not found\n", error: "")
        let other = app(program: try makeApp(version: "1.18.0"))

        let result = await other.turnOffLoginItem()

        XCTAssertNoThrow(try result.get())
    }

    func testALoginItemFailureIsSaid() async throws {
        let other = app(program: try makeApp(version: "1.18.0"))
        let expected = "Open at Login could not be turned off: could not disable the login item: denied. "
            + SystemOtherApp.whereToLook

        mac.answer = ProgramRun(status: 1, output: "login item: enabled\n", error: "error: could not disable the login item: denied\n")
        var result = await other.turnOffLoginItem()
        XCTAssertEqual(result.failure?.sentence, expected)

        mac.answer = ProgramRun(status: 0, output: "login item: enabled\n", error: "")
        result = await other.turnOffLoginItem()
        XCTAssertEqual(result.failure?.sentence,
                       "Open at Login is still on. " + SystemOtherApp.whereToLook,
                       "an ending of 0 that leaves the login item on is still a failure")

        mac.answer = ProgramRun(status: 0, output: "", error: "")
        result = await other.turnOffLoginItem()
        XCTAssertEqual(result.failure?.sentence,
                       "Open at Login could not be turned off: HomeSpeaker did not say what the login item is. "
                           + SystemOtherApp.whereToLook)

        mac.answer = ProgramRun(status: 2, output: "", error: "error: unexpected argument \"disable\" for --login-item\n")
        result = await other.turnOffLoginItem()
        XCTAssertEqual(result.failure?.sentence,
                       "Open at Login could not be turned off: unexpected argument \"disable\" for --login-item. "
                           + SystemOtherApp.whereToLook)
    }

    func testAVeryOldAppIsToldWhereToLook() async throws {
        XCTAssertEqual(SystemOtherApp.whereToLook, "Turn it off in System Settings > General > Login Items.")
        let old = app(program: try makeApp(version: "1.13.1", in: "old"))

        let result = await old.turnOffLoginItem()

        XCTAssertEqual(result.failure?.sentence,
                       "This copy of the app is too old to turn off its own Open at Login. " + SystemOtherApp.whereToLook)
        XCTAssertTrue(mac.runs.isEmpty, "an app without --login-item is never run: it would open as the app")

        let unknown = app(program: try makeApp(version: nil, in: "unknown"))
        let unknownResult = await unknown.turnOffLoginItem()
        XCTAssertEqual(unknownResult.failure, result.failure, "a version that does not read is treated as too old")
        XCTAssertTrue(mac.runs.isEmpty)

        let first = app(program: try makeApp(version: "1.13.2", in: "first"))
        _ = await first.turnOffLoginItem()
        XCTAssertEqual(mac.runs.count, 1, "1.13.2 is the first with --login-item")
    }

    func testTheVersionIsReadAfresh() throws {
        let program = try makeApp(version: "1.18.0")
        let other = app(program: program)
        XCTAssertEqual(other.version, "1.18.0")

        try writeVersion("1.19.0", to: program.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent())
        XCTAssertEqual(other.version, "1.19.0", "an updated app shows its new version")

        XCTAssertNil(app(program: nil).version)
    }

    // MARK: The Trash

    func testTheTrashIsRecycleNeverRemove() throws {
        let program = try makeApp(version: "1.18.0")
        let bundle = program.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let other = app(program: program)

        let trashed = try other.moveToTrash()

        XCTAssertEqual(trashed.path, "/stand-in/.Trash/HomeSpeaker.app")
        XCTAssertEqual(workspace.calls, ["recycle \(bundle.path)"], "the app is moved to the Trash, and nothing is removed")
    }

    func testTheTrashWaitsForTheAppToQuit() throws {
        mac.apps = [StandInApp(.accessory)]
        let other = app(program: try makeApp(version: "1.18.0"))

        XCTAssertThrowsError(try other.moveToTrash()) { error in
            XCTAssertEqual(error as? OtherAppError, .stillRunning)
        }
        XCTAssertEqual(workspace.calls, [], "a running app is never moved: both would speak until it quit")

        mac.apps = [StandInApp(.prohibited)]
        XCTAssertNoThrow(try other.moveToTrash(), "a script's command-line run is not the app running")
    }

    func testACopyInTheTrashIsNeverTrashedAgain() throws {
        let other = app(program: try makeApp(version: "1.18.0", in: ".Trash"))

        XCTAssertThrowsError(try other.moveToTrash()) { error in
            XCTAssertEqual(error as? OtherAppError, .alreadyInTrash)
        }
        XCTAssertEqual(workspace.calls, [])
    }

    func testOnlyAnAppIsEverMoved() throws {
        let bare = folder.appendingPathComponent("build/HomeSpeaker")
        try FileManager.default.createDirectory(at: bare.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data().write(to: bare)

        for program in [bare, nil] as [URL?] {
            XCTAssertThrowsError(try app(program: program).moveToTrash()) { error in
                XCTAssertEqual(error as? OtherAppError, .notAnApp)
            }
        }
        XCTAssertEqual(workspace.calls, [], "a bare program, or none, is never moved")
    }

    // MARK: The plan

    func testAnOldAppMustLoseItsLoginItem() {
        for version in ["1.18.0", "1.13.1", "0.9", nil] as [String?] {
            XCTAssertEqual(OtherAppPlan.forChoosingTheExtension(appVersion: version),
                           [.quit, .oldAppWarning, .turnOffLoginItem(ticked: true, optional: false), .moveToTrash(ticked: false)],
                           "an app older than 1.19 cannot hear the choice: \(version ?? "unknown")")
        }
    }

    func testANewAppIsOfferedNotForced() {
        for version in ["1.19.0", "1.20.3", "2.0"] {
            XCTAssertEqual(OtherAppPlan.forChoosingTheExtension(appVersion: version),
                           [.quit, .turnOffLoginItem(ticked: true, optional: true), .moveToTrash(ticked: false)], version)
        }
    }

    func testTheAppQuitsBeforeAnythingElse() {
        for version in ["1.18.0", "1.19.0", nil] as [String?] {
            let steps = OtherAppPlan.forChoosingTheExtension(appVersion: version)
            XCTAssertEqual(steps.first, .quit, "quit always, and first")
            XCTAssertEqual(steps.last, .moveToTrash(ticked: false), "the Trash comes last, after the app has quit")
        }
    }

    func testTheStepsSayThePlansWords() {
        XCTAssertEqual(OtherAppPlan.Step.quit.text, "The app has quit.")
        XCTAssertEqual(OtherAppPlan.Step.turnOffLoginItem(ticked: true, optional: true).text, "Turn off the app's Open at Login")
        XCTAssertEqual(OtherAppPlan.Step.moveToTrash(ticked: false).text, "Move HomeSpeaker.app to the Trash")
        XCTAssertEqual(OtherAppPlan.Step.moveToTrash(ticked: false).warning,
                       "Your phone remote and scripts that call HomeSpeaker.app will stop working until they are pointed at the extension.")
        XCTAssertEqual(OtherAppPlan.Step.oldAppWarning.text,
                       "This copy of the app is older than 1.19 and will take the Claude Code hook back if it is opened again. Move it to the Trash, or update it.")
        XCTAssertNil(OtherAppPlan.Step.quit.warning)
    }

    func testVersionsCompareByTheirNumbers() {
        XCTAssertTrue(OtherAppVersion.isOlder("1.13.1", than: "1.13.2"))
        XCTAssertFalse(OtherAppVersion.isOlder("1.13.2", than: "1.13.2"))
        XCTAssertTrue(OtherAppVersion.isOlder("1.9.9", than: "1.19"), "by number, not by letter")
        XCTAssertFalse(OtherAppVersion.isOlder("1.19", than: "1.19.0"))
        XCTAssertFalse(OtherAppVersion.isOlder("1.100.0", than: "1.19.0"))
        XCTAssertTrue(OtherAppVersion.isOlder(nil, than: "1.19.0"), "unknown is old")
        XCTAssertTrue(OtherAppVersion.isOlder("", than: "1.19.0"))
        XCTAssertTrue(OtherAppVersion.isOlder("one.two", than: "1.19.0"))
    }
}

private extension Result {
    var failure: Failure? {
        if case .failure(let failure) = self { return failure }
        return nil
    }
}
