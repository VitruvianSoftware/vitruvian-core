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

/// One thing the tool asks HomeSpeaker's program to do, as its flags do.
public enum Job: Equatable, Sendable {
    case say(String)
    case volume
    case setVolume(Int)
    case mute
    case unmute
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
public final class ProcessDriver: SpeakerDriver {
    public static let bundleID = "com.vitruviansoftware.homespeaker"
    public static let usualPlaces = ["/Applications/HomeSpeaker.app", "~/Applications/HomeSpeaker.app"]

    public let binary: URL?

    public init(binary: URL?) {
        self.binary = binary
    }

    public var isInstalled: Bool { binary != nil }
    public var program: URL? { binary }

    /// The environment variable that names the program to drive instead of
    /// the installed app: a build of HomeSpeaker's, or, set and empty, no
    /// HomeSpeaker at all, which is how a test keeps the tool off this Mac's.
    public static let programVariable = "HOMESPEAKER_PROGRAM"

    /// HomeSpeaker's program: the one the environment names, else the app
    /// Launch Services knows by its bundle id, else the app in one of the
    /// usual places; nil with none.
    public static func locate(environment: [String: String], known: () -> URL?, home: String,
                              isExecutable: (String) -> Bool) -> URL? {
        if let named = environment[programVariable] {
            let path = named.trimmingCharacters(in: .whitespaces)
            return !path.isEmpty && isExecutable(path) ? URL(fileURLWithPath: path) : nil
        }
        var candidates: [URL] = []
        if let known = known() { candidates.append(known) }
        candidates += usualPlaces.map { URL(fileURLWithPath: $0.replacingOccurrences(of: "~", with: home)) }
        for app in candidates {
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
        }
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
        }
    }

    public func run(_ job: Job, then: @escaping @Sendable (JobResult) -> Void) {
        guard let binary else { return then(.unavailable("HomeSpeaker is not installed")) }
        let process = Process()
        process.executableURL = binary
        process.arguments = Self.arguments(for: job)
        let output = Pipe()
        let error = Pipe()
        process.standardOutput = output
        process.standardError = error
        process.standardInput = FileHandle.nullDevice
        process.terminationHandler = { process in
            let printed = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            let complained = String(decoding: error.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            then(Self.result(of: job, status: process.terminationStatus, output: printed, error: complained))
        }
        do {
            try process.run()
        } catch {
            then(.unavailable("HomeSpeaker could not be started: \(error.localizedDescription)"))
        }
    }
}
