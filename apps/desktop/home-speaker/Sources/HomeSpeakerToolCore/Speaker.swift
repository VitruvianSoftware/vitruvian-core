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

/// One thing the tool asks HomeSpeaker's program to do, as its flags do.
public enum Job: Equatable, Sendable {
    case say(String)
    case volume
    case setVolume(Int)
    case mute
    case unmute
    /// One of the commands that must run as HomeSpeaker.app: sign out,
    /// discover, the login item, the media-pause test.
    case app(AppCommand)
    /// `--sign-in [--chat]`: the browser sign-in, which can take minutes.
    case signIn(chatOnly: Bool)

    /// Setting HomeSpeaker up, not speaking: these run beside a speaker
    /// job, so a slow sign-in never holds up a mute.
    public var isSetup: Bool {
        switch self {
        case .say, .volume, .setVolume, .mute, .unmute: return false
        case .app, .signIn: return true
        }
    }
}

/// The default speaker's volume, as `HomeSpeaker --volume` prints it.
public struct Volume: Equatable, Sendable {
    public var speaker: String
    public var percent: Int?
    public var muted: Bool?
    public var online: Bool?

    public init(speaker: String, percent: Int? = nil, muted: Bool? = nil, online: Bool? = nil) {
        self.speaker = speaker
        self.percent = percent
        self.muted = muted
        self.online = online
    }
}

public enum JobResult: Equatable, Sendable {
    /// Spoken; the line HomeSpeaker printed says where.
    case spoke(String)
    /// Not spoken, and why, in HomeSpeaker's words.
    case notSpoken(String)
    case volume(Volume)
    /// The volume could not be read or set: why, in HomeSpeaker's words.
    case unavailable(String)
    /// A setup job ran; the lines it printed.
    case done([String])
    /// A setup job failed: why, in HomeSpeaker's words.
    case failed(String)
    /// The homes `--discover` (without `--save`) listed.
    case homes([HomeStructure])
    /// What `--login-item` said the login item is, and, when switching it
    /// failed, why: HomeSpeaker still prints the state it ended in.
    case loginItem(LoginItemState, problem: String? = nil)
}

/// Runs jobs on HomeSpeaker's program and answers later, from any thread.
public protocol SpeakerDriver: AnyObject {
    /// HomeSpeaker is on this Mac.
    var isInstalled: Bool { get }
    /// The HomeSpeaker program the jobs run; nil when it is not installed.
    var program: URL? { get }
    func run(_ job: Job, then: @escaping @Sendable (JobResult) -> Void)
}

/// Drives the HomeSpeaker that is installed, through its program, as the
/// Mac agent does for the phone: `--say` speaks with the person's sign-in
/// and default speaker, `--volume` and the rest answer with JSON. The
/// program is started and not waited for; its end is reported to `then`
/// on a thread of the system's.
///
/// Its lasting role is how the extension finds the app and reads it:
/// `locate`, `isAppRunning`, `arguments` and `result` stay. `SystemOtherApp`
/// uses them to run the app's own `--login-item disable` when the person
/// picks the extension. The extension runs on its own engine
/// (`EngineDriver`), so the tool gives this no jobs.
///
/// A job it is given runs through `run`, the one place a program of the
/// app's is started (`SystemOtherApp.runProgram` by default).
public final class ProcessDriver: SpeakerDriver {
    public static let bundleID = HomeSpeakerProfile.appBundleID
    public static let usualPlaces = ["/Applications/HomeSpeaker.app", "~/Applications/HomeSpeaker.app"]

    public let binary: URL?
    private let runProgram: ProgramRunning

    public init(binary: URL?, run: @escaping ProgramRunning = SystemOtherApp.runProgram) {
        self.binary = binary
        runProgram = run
    }

    /// HomeSpeaker.app is running as an app, by the app profile's own check
    /// (`HomeSpeakerProfile.isAppRunning(among:)`): a command-line run of
    /// the app's program does not count.
    public static func isAppRunning(_ apps: [HomeSpeakerProfile.RunningApp]) -> Bool {
        HomeSpeakerProfile.isAppRunning(among: apps)
    }

    /// `isAppRunning(_:)` over this Mac's running applications.
    public static func isAppRunning() -> Bool {
        isAppRunning(HomeSpeakerProfile.runningApps())
    }

    public var isInstalled: Bool { binary != nil }
    public var program: URL? { binary }

    /// The environment variable that names the program to drive instead of
    /// the installed app: a build of HomeSpeaker's, or, set and empty, no
    /// HomeSpeaker at all, which is how a test keeps the tool off this Mac's.
    public static let programVariable = "HOMESPEAKER_PROGRAM"

    /// HomeSpeaker's program: the one the environment names, else the app
    /// Launch Services knows by its bundle id, else the app in one of the
    /// usual places; nil with none. A copy in the Trash is passed over:
    /// Launch Services still knows apps there, and one found first must not
    /// hide the copy that is installed.
    public static func locate(environment: [String: String], known: () -> URL?, home: String,
                              isExecutable: (String) -> Bool) -> URL? {
        if let named = environment[programVariable] {
            let path = named.trimmingCharacters(in: .whitespaces)
            return !path.isEmpty && isExecutable(path) ? URL(fileURLWithPath: path) : nil
        }
        var candidates: [URL] = []
        if let known = known() { candidates.append(known) }
        candidates += usualPlaces.map { URL(fileURLWithPath: $0.replacingOccurrences(of: "~", with: home)) }
        for app in candidates where !OtherDoorPresence.isInTrash(app.path) {
            let program = app.appendingPathComponent("Contents/MacOS/HomeSpeaker")
            if isExecutable(program.path) { return program }
        }
        return nil
    }

    public static func arguments(for job: Job) -> [String] {
        switch job {
        case .say(let text): return ["--say", text]
        case .volume: return ["--volume"]
        case .setVolume(let level): return ["--set-volume", String(min(100, max(0, level)))]
        case .mute: return ["--mute"]
        case .unmute: return ["--unmute"]
        case .app(let command): return AppCommandParser.arguments(for: command)
        case .signIn(let chatOnly): return ["--sign-in"] + (chatOnly ? ["--chat"] : [])
        }
    }

    /// The homes in what `--discover` printed: each `home: <name> (<id>)`
    /// line, split at the last " (" so a name with brackets in it stays
    /// whole. The indented, tab-separated speaker lines under each are not
    /// homes.
    public static func homes(in output: String) -> [HomeStructure] {
        output.split(whereSeparator: \.isNewline).compactMap { line in
            guard line.hasPrefix("home: "), line.hasSuffix(")") else { return nil }
            let body = line.dropFirst("home: ".count).dropLast()
            guard let split = body.range(of: " (", options: .backwards) else { return nil }
            let name = String(body[..<split.lowerBound])
            let id = String(body[split.upperBound...])
            guard !id.isEmpty else { return nil }
            return HomeStructure(id: id, name: name)
        }
    }

    /// `login item: <state>`, as `--login-item` prints it.
    public static func loginItemState(in output: String) -> LoginItemState? {
        for line in output.split(whereSeparator: \.isNewline) where line.hasPrefix("login item: ") {
            return LoginItemState(rawValue: String(line.dropFirst("login item: ".count)).trimmingCharacters(in: .whitespaces))
        }
        return nil
    }

    /// A failure's words without the "error: " each of HomeSpeaker's
    /// complaints starts with.
    static func complaint(_ text: String) -> String {
        text.split(whereSeparator: \.isNewline)
            .map { $0.hasPrefix("error: ") ? String($0.dropFirst("error: ".count)) : String($0) }
            .joined(separator: " ")
    }

    /// What the program's end means for `job`.
    public static func result(of job: Job, status: Int32, output: String, error: String) -> JobResult {
        let said = output.trimmingCharacters(in: .whitespacesAndNewlines)
        let complained = error.trimmingCharacters(in: .whitespacesAndNewlines)
        switch job {
        case .say:
            // `--say` exits 0 when something was heard, or nothing was
            // meant to be (quiet hours, no outputs); what it printed says.
            if status == 0 {
                return said.isEmpty ? .notSpoken(complained) : .spoke(said)
            }
            return .notSpoken(complained.isEmpty ? said : complained)
        case .volume, .setVolume, .mute, .unmute:
            guard let data = said.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return .unavailable(complained.isEmpty ? "HomeSpeaker printed no answer" : complained)
            }
            guard object["available"] as? Bool == true else {
                return .unavailable(object["reason"] as? String ?? "the speaker is not available")
            }
            return .volume(Volume(speaker: object["speaker"] as? String ?? "", percent: object["percent"] as? Int,
                                  muted: object["muted"] as? Bool, online: object["online"] as? Bool))
        case .app, .signIn:
            guard status == 0 else {
                let why = complaint(complained.isEmpty ? said : complained)
                let problem = why.isEmpty ? "HomeSpeaker stopped with status \(status)" : why
                if case .app(.loginItem) = job, let state = loginItemState(in: said) {
                    return .loginItem(state, problem: problem)
                }
                return .failed(problem)
            }
            if case .app(.discover(save: false, _)) = job { return .homes(homes(in: said)) }
            if case .app(.loginItem) = job {
                guard let state = loginItemState(in: said) else { return .failed("HomeSpeaker did not say what the login item is") }
                return .loginItem(state)
            }
            return .done(said.split(whereSeparator: \.isNewline).map(String.init))
        }
    }

    /// Starts the program and does not wait for it; its end is reported to
    /// `then` on a thread of the system's. A program that could not be
    /// started reads as `runProgram` says (status -1, "could not be started").
    public func run(_ job: Job, then: @escaping @Sendable (JobResult) -> Void) {
        guard let binary else { return then(job.isSetup ? .failed("HomeSpeaker is not installed") : .unavailable("HomeSpeaker is not installed")) }
        let runProgram = runProgram
        let arguments = Self.arguments(for: job)
        Task.detached {
            let ran = await runProgram(binary, arguments)
            then(Self.result(of: job, status: ran.status, output: ran.output, error: ran.error))
        }
    }
}
