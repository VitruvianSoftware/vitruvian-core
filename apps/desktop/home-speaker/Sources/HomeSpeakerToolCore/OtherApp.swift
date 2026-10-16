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
import Foundation
import HomeSpeakerCore

// Closing the app, when the person picks the extension (design 7.4, step 3).
// The app is asked to quit, then, as the person ticks them, its Open at
// Login is turned off and it is moved to the Trash. Each part of this Mac
// that does it is handed in, so tests use stand-ins and never reach the
// app that is installed.

/// One running application, as `NSRunningApplication` describes it.
public protocol RunningAppHandle: AnyObject {
    var bundleIdentifier: String? { get }
    var activationPolicy: NSApplication.ActivationPolicy { get }
    /// Where the running application was started from.
    var bundleURL: URL? { get }
    /// Asks the application to quit, as the Dock's Quit does. False when it
    /// could not be asked.
    func terminate() -> Bool
}

extension NSRunningApplication: RunningAppHandle {}

/// How one run of a program ended.
public struct ProgramRun: Equatable, Sendable {
    public var status: Int32
    public var output: String
    public var error: String

    public init(status: Int32, output: String, error: String) {
        self.status = status
        self.output = output
        self.error = error
    }
}

/// Runs a program with arguments, waits for it, and says how it ended.
public typealias ProgramRunning = @Sendable (_ program: URL, _ arguments: [String]) async -> ProgramRun

/// A sentence the person reads when a step did not work.
public struct OtherAppProblem: Error, Equatable, Sendable {
    public let sentence: String
    public init(_ sentence: String) { self.sentence = sentence }
}

/// Why the app was not moved to the Trash.
public enum OtherAppError: Error, Equatable, LocalizedError {
    /// There is no HomeSpeaker.app: no program, or a program outside an app.
    case notAnApp
    /// It is in the Trash already, so it is not installed.
    case alreadyInTrash
    /// It is still running. Moved now, both HomeSpeakers could speak until
    /// it quit: it is quit first.
    case stillRunning

    public var errorDescription: String? {
        switch self {
        case .notAnApp: return "HomeSpeaker.app was not found."
        case .alreadyInTrash: return "HomeSpeaker.app is in the Trash already."
        case .stillRunning: return "HomeSpeaker.app is still open. Quit it, then move it to the Trash."
        }
    }
}

/// The installed HomeSpeaker app, as the extension closes it.
public protocol OtherAppControlling: Sendable {
    /// The app is running as the menu bar app. A command-line run of its
    /// program, such as a script's `--say`, does not count.
    var isRunning: Bool { get }
    /// The app's version, from its Info.plist, read afresh each time: an
    /// updated app shows its new version. Nil when it does not read.
    var version: String? { get }
    /// Asks the menu bar app to quit, and waits up to `timeout` seconds for
    /// it to go. True when it is not running at the end.
    func quit(timeout: Double) async -> Bool
    /// Runs the app's own `--login-item disable`: only an app can switch its
    /// own login item off. A failure is the sentence the person reads.
    func turnOffLoginItem() async -> Result<Void, OtherAppProblem>
    /// Runs the app's own `--login-item enable`, when the person picks the
    /// app again. A failure, or an app too old for the flag, is the sentence
    /// the person reads, with where to turn it on by hand.
    func turnOnLoginItem() async -> Result<Void, OtherAppProblem>
    /// Opens the menu bar app, as the Finder does: the app as it is found
    /// now, never a copy in the Trash. True when it was opened.
    func open() async -> Bool
    /// Moves HomeSpeaker.app to the Trash, never deleting it, and says where
    /// it went. Refused while the app is running.
    func moveToTrash() throws -> URL
}

/// The real one, built from the app's program as `ProcessDriver.locate`
/// finds it, which passes over a copy in the Trash.
public final class SystemOtherApp: OtherAppControlling, @unchecked Sendable {
    /// The first version with `--login-item` (`AppCommands.swift`, #3325).
    public static let loginItemFlagSince = "1.13.2"
    /// Where a person turns Open at Login off by hand.
    public static let whereToLook = "Turn it off in System Settings > General > Login Items & Extensions."
    /// Where a person turns it on by hand.
    public static let whereToTurnOn = "Turn it on in System Settings > General > Login Items & Extensions."
    static let tooOldForLoginItem = "This copy of the app is too old to turn off its own Open at Login."
    static let tooOldToTurnOn = "This copy of the app is too old to turn on its own Open at Login."

    // Immutable after init. The file manager is only asked to move the app
    // to the Trash.
    private let locate: @Sendable () -> URL?
    private let runningApps: @Sendable () -> [any RunningAppHandle]
    private let run: ProgramRunning
    private let fileManager: FileManager
    private let wait: @Sendable (Double) async -> Void
    private let openApp: @Sendable (URL) async -> Bool

    /// Every part is handed in, with no defaults, so nothing can reach this
    /// Mac's app by being left out. `onThisMac(locate:)` is the real set.
    /// `locate` finds the app's program afresh each time it is asked, so an
    /// app installed, moved or put in the Trash since is seen as it is now.
    public init(locate: @escaping @Sendable () -> URL?, runningApps: @escaping @Sendable () -> [any RunningAppHandle],
                run: @escaping ProgramRunning, fileManager: FileManager,
                wait: @escaping @Sendable (Double) async -> Void,
                openApp: @escaping @Sendable (URL) async -> Bool) {
        self.locate = locate
        self.runningApps = runningApps
        self.run = run
        self.fileManager = fileManager
        self.wait = wait
        self.openApp = openApp
    }

    /// The app always at `program`.
    public convenience init(program: URL?, runningApps: @escaping @Sendable () -> [any RunningAppHandle],
                            run: @escaping ProgramRunning, fileManager: FileManager,
                            wait: @escaping @Sendable (Double) async -> Void,
                            openApp: @escaping @Sendable (URL) async -> Bool) {
        self.init(locate: { program }, runningApps: runningApps, run: run, fileManager: fileManager, wait: wait,
                  openApp: openApp)
    }

    /// The app as `locate` finds it, through this Mac's running
    /// applications, a real run of its program, the default file manager's
    /// Trash, and the Finder's way of opening an app.
    public static func onThisMac(locate: @escaping @Sendable () -> URL?) -> SystemOtherApp {
        SystemOtherApp(locate: locate,
                       runningApps: { NSRunningApplication.runningApplications(withBundleIdentifier: HomeSpeakerProfile.appBundleID) },
                       run: runProgram, fileManager: .default,
                       wait: { try? await Task.sleep(for: .seconds($0)) },
                       openApp: openWithWorkspace)
    }

    /// The app's program as it is found now. Nil when there is none, or
    /// when the only one is in the Trash.
    public var program: URL? {
        guard let found = locate(), !OtherDoorPresence.isInTrash(found.path) else { return nil }
        return found
    }

    /// `HomeSpeaker.app`, when the program is `HomeSpeaker.app/Contents/MacOS/<name>`.
    /// A bare program, such as a build's, is no app: it has no version and
    /// is never moved.
    public var bundle: URL? {
        guard let program = locate() else { return nil }
        let macOS = program.deletingLastPathComponent()
        let contents = macOS.deletingLastPathComponent()
        let bundle = contents.deletingLastPathComponent()
        guard macOS.lastPathComponent == "MacOS", contents.lastPathComponent == "Contents",
              bundle.pathExtension == "app" else { return nil }
        return bundle
    }

    public var isRunning: Bool {
        HomeSpeakerProfile.isAppRunning(among: runningApps().map { ($0.bundleIdentifier, $0.activationPolicy) })
    }

    public var version: String? {
        guard let bundle else { return nil }
        let plist = bundle.appendingPathComponent("Contents/Info.plist")
        return NSDictionary(contentsOf: plist)?["CFBundleShortVersionString"] as? String
    }

    /// How often `quit` looks again while it waits.
    static let quitCheck = 0.1

    public func quit(timeout: Double) async -> Bool {
        // Only the app this controller found is asked, matched by where it
        // runs from, never by its bundle id alone: with none found (a test's
        // `HOMESPEAKER_PROGRAM=""`, say), or a copy elsewhere running, no
        // HomeSpeaker that happens to run on this Mac is quit.
        guard let bundle else { return !isRunning }
        let targets = menuBarApps(at: bundle)
        guard !targets.isEmpty else { return true }
        for app in targets { _ = app.terminate() }
        let checks = max(1, Int((timeout / Self.quitCheck).rounded(.up)))
        for _ in 0..<checks {
            if menuBarApps(at: bundle).isEmpty { return true }
            await wait(timeout / Double(checks))
        }
        return menuBarApps(at: bundle).isEmpty
    }

    /// The menu bar apps running from exactly `bundle`. A command-line run
    /// of the program has the `.prohibited` policy, and may be a script
    /// speaking: it is never one of them.
    private func menuBarApps(at bundle: URL) -> [any RunningAppHandle] {
        let wanted = Self.canonical(bundle)
        return runningApps().filter {
            $0.bundleIdentifier == HomeSpeakerProfile.appBundleID && $0.activationPolicy != .prohibited
                && $0.bundleURL.map(Self.canonical) == wanted
        }
    }

    /// A bundle's path with `.`, `..` and links resolved.
    static func canonical(_ url: URL) -> String {
        url.standardizedFileURL.resolvingSymlinksInPath().path
    }

    public func turnOffLoginItem() async -> Result<Void, OtherAppProblem> {
        guard let program else { return .failure(OtherAppProblem(OtherAppError.notAnApp.errorDescription ?? "")) }
        // An app without the flag would open as the app instead, so it is
        // not run at all. Nor is one whose version does not read.
        guard !OtherAppVersion.isOlder(version, than: Self.loginItemFlagSince) else {
            return .failure(OtherAppProblem("\(Self.tooOldForLoginItem) \(Self.whereToLook)"))
        }
        let job = Job.app(.loginItem(.disable))
        let ran = await run(program, ProcessDriver.arguments(for: job))
        // Read as the tool reads every run of `--login-item`: by how it
        // ended, then by the state it printed.
        switch ProcessDriver.result(of: job, status: ran.status, output: ran.output, error: ran.error) {
        case .loginItem(.notRegistered, nil), .loginItem(.notFound, nil):
            return .success(())
        case .loginItem(_, let problem?), .failed(let problem):
            return .failure(OtherAppProblem("Open at Login could not be turned off: \(problem). \(Self.whereToLook)"))
        case .loginItem(_, nil):
            return .failure(OtherAppProblem("Open at Login is still on. \(Self.whereToLook)"))
        default:
            return .failure(OtherAppProblem("Open at Login could not be turned off. \(Self.whereToLook)"))
        }
    }

    public func turnOnLoginItem() async -> Result<Void, OtherAppProblem> {
        guard let program else {
            return .failure(OtherAppProblem("\(OtherAppError.notAnApp.errorDescription ?? "") \(Self.whereToTurnOn)"))
        }
        guard !OtherAppVersion.isOlder(version, than: Self.loginItemFlagSince) else {
            return .failure(OtherAppProblem("\(Self.tooOldToTurnOn) \(Self.whereToTurnOn)"))
        }
        let job = Job.app(.loginItem(.enable))
        let ran = await run(program, ProcessDriver.arguments(for: job))
        // By how it ended, then by the state it printed: only "enabled" is on.
        switch ProcessDriver.result(of: job, status: ran.status, output: ran.output, error: ran.error) {
        case .loginItem(.enabled, nil):
            return .success(())
        case .loginItem(_, let problem?), .failed(let problem):
            return .failure(OtherAppProblem("Open at Login could not be turned on: \(problem). \(Self.whereToTurnOn)"))
        default:
            return .failure(OtherAppProblem("Open at Login could not be turned on. \(Self.whereToTurnOn)"))
        }
    }

    public func open() async -> Bool {
        // Never a copy in the Trash: Launch Services still knows those.
        guard let bundle, !OtherDoorPresence.isInTrash(bundle.path + "/") else { return false }
        return await openApp(bundle)
    }

    /// Opens the app at `bundle` as the Finder does, in the background.
    public static let openWithWorkspace: @Sendable (URL) async -> Bool = { bundle in
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        do {
            _ = try await NSWorkspace.shared.openApplication(at: bundle, configuration: configuration)
            return true
        } catch {
            return false
        }
    }

    public func moveToTrash() throws -> URL {
        guard let bundle else { throw OtherAppError.notAnApp }
        guard !OtherDoorPresence.isInTrash(bundle.path + "/") else { throw OtherAppError.alreadyInTrash }
        guard !isRunning else { throw OtherAppError.stillRunning }
        // The Trash, as the Finder's Move to Trash: the person can put it back.
        var moved: NSURL?
        try fileManager.trashItem(at: bundle, resultingItemURL: &moved)
        return (moved as URL?) ?? bundle
    }

    /// Runs `program` and waits for it to end. Its output is a line or
    /// two, so reading it at the end never fills the pipe.
    public static let runProgram: ProgramRunning = { program, arguments in
        await withCheckedContinuation { (finished: CheckedContinuation<ProgramRun, Never>) in
            let process = Process()
            process.executableURL = program
            process.arguments = arguments
            let output = Pipe()
            let error = Pipe()
            process.standardOutput = output
            process.standardError = error
            process.standardInput = FileHandle.nullDevice
            process.terminationHandler = { process in
                let printed = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                let complained = String(decoding: error.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                finished.resume(returning: ProgramRun(status: process.terminationStatus, output: printed, error: complained))
            }
            do {
                try process.run()
            } catch {
                finished.resume(returning: ProgramRun(
                    status: -1, output: "", error: "error: HomeSpeaker could not be started: \(error.localizedDescription)"))
            }
        }
    }
}

// MARK: - The plan

/// What the extension does and offers once the person picks it, in order
/// (design 7.4, step 3). The app quits first, always: the Trash comes last
/// and `moveToTrash` refuses a running app, so the two never both speak
/// because the app was moved while it still ran.
public enum OtherAppPlan {
    /// The first app that hears the choice file and goes quiet by itself.
    public static let hearsTheChoiceSince = "1.19.0"

    public enum Step: Equatable, Sendable {
        /// Done at once, and said.
        case quit
        /// The app is older than 1.19: it will not hear the choice.
        case oldAppWarning
        /// Offered with a tick box; not `optional` for an old app: opened
        /// again at login, it would take the hook back.
        case turnOffLoginItem(ticked: Bool, optional: Bool)
        /// Offered with a tick box, after the app has quit.
        case moveToTrash(ticked: Bool)

        /// The words the person reads.
        public var text: String {
            switch self {
            case .quit: return "The app has quit."
            case .oldAppWarning:
                return "This copy of the app is older than 1.19 and will take the Claude Code hook back if it is opened again. Move it to the Trash, or update it."
            case .turnOffLoginItem: return DoorWords.turnOffLoginItem
            case .moveToTrash: return DoorWords.moveToTrash
            }
        }

        /// What the person is told before they tick it.
        public var warning: String? {
            guard case .moveToTrash = self else { return nil }
            return DoorWords.trashWarning
        }
    }

    /// Quit always; the login item offered and ticked; the Trash offered and
    /// not ticked. An app older than 1.19, or one whose version does not
    /// read, must lose its login item, and the person is warned.
    public static func forChoosingTheExtension(appVersion: String?) -> [Step] {
        let old = OtherAppVersion.isOlder(appVersion, than: hearsTheChoiceSince)
        return [.quit] + (old ? [.oldAppWarning] : [])
            + [.turnOffLoginItem(ticked: true, optional: !old), .moveToTrash(ticked: false)]
    }
}

/// Versions compared by their numbers: 1.9 is older than 1.19.
public enum OtherAppVersion {
    /// True when `version` is older than `than`, and when it is missing or
    /// does not read as numbers: an unknown app is treated as an old one.
    public static func isOlder(_ version: String?, than: String) -> Bool {
        guard let mine = numbers(version), let theirs = numbers(than) else { return true }
        for i in 0..<max(mine.count, theirs.count) {
            let a = i < mine.count ? mine[i] : 0
            let b = i < theirs.count ? theirs[i] : 0
            if a != b { return a < b }
        }
        return false
    }

    /// `1.19.0` as [1, 19, 0]; a part's trailing words, as in `0-beta`, are
    /// dropped. Nil when a part does not start with a number.
    static func numbers(_ version: String?) -> [Int]? {
        guard let version, !version.isEmpty else { return nil }
        var parts: [Int] = []
        for part in version.split(separator: ".", omittingEmptySubsequences: false) {
            guard let number = Int(String(part.prefix(while: \.isASCII).prefix(while: \.isNumber))) else { return nil }
            parts.append(number)
        }
        return parts
    }
}
