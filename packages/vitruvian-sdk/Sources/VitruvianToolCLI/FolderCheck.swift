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
import VitruvianToolProtocol

/// The most a tool's folder may hold when the app adds it. The app copies
/// the folder whole, so these keep a wrongly picked folder from being
/// copied: a home folder, or a project with everything it depends on.
public struct FolderLimits: Equatable, Sendable {
    public var bytes: Int
    /// Files, folders and links together.
    public var things: Int

    public init(bytes: Int = 256 * 1_048_576, things: Int = 10_000) {
        self.bytes = bytes
        self.things = things
    }
}

/// What is wrong with a folder as a tool to add.
public enum FolderProblem: Equatable, Sendable {
    /// There is no `vitruvian-tool.json`, or it cannot be read.
    case noManifest
    /// The manifest breaks one of its own rules.
    case manifest(ManifestProblem)
    /// There is no file at the program's path.
    case programMissing(String)
    /// The program is, through a link, a file outside the folder.
    case programOutsideFolder(String)
    /// The program is not a file macOS will run.
    case programNotExecutable(String)
    /// macOS has quarantined the program, as it does to a download.
    case quarantined(String)
    /// The folder holds more than these limits.
    case tooBig(FolderLimits)

    /// The problem's name in `protocol/examples/folders.json`, where the app
    /// and this command are held to the same answers.
    public var verdict: String {
        switch self {
        case .noManifest: return "noManifest"
        case .manifest: return "manifest"
        case .programMissing: return "programMissing"
        case .programOutsideFolder: return "programOutsideFolder"
        case .programNotExecutable: return "programNotExecutable"
        case .quarantined: return "quarantined"
        case .tooBig: return "tooBig"
        }
    }
}

/// What `FolderCheck` found.
public struct FolderReport: Equatable, Sendable {
    /// The folder that was read, with every link followed.
    public let folder: URL
    /// The manifest, when the file could be read as one at all.
    public let manifest: ToolManifestFile?
    /// Everything found wrong, in the order the app looks. The first is the
    /// one the app would give as its reason.
    public let problems: [FolderProblem]
    /// Things worth knowing that refuse nothing.
    public let notes: [String]
    /// What the folder holds; nil when it is over the limits.
    public let bytes: Int?
    public let things: Int?

    public var verdict: String { problems.first?.verdict ?? "ok" }
}

/// Reads a folder the way the app does before it offers to add a tool, and
/// says what the app would refuse it for.
///
/// The rules about the manifest file are `ToolManifestFile.read`, the same
/// code the app runs. The rules about the folder are written here from the
/// design's words, not from the app's code, which is under another licence:
///
/// - the program is a file in the folder, with every link followed;
/// - it is a file macOS will run;
/// - macOS has not quarantined it;
/// - the folder holds at most 256 MB and 10,000 things, a link counted as
///   one thing and not followed.
///
/// `protocol/examples/folders.json` holds folders both sides are tested
/// against, so the two cannot come apart unseen.
public enum FolderCheck {
    public static func check(_ picked: URL, limits: FolderLimits = FolderLimits()) -> FolderReport {
        // A picked folder that is a link is followed first.
        let folder = picked.resolvingSymlinksInPath().standardizedFileURL
        var problems: [FolderProblem] = []
        var notes: [String] = []
        let manifest = readManifest(in: folder, into: &problems)

        if let manifest, ManifestRules.staysInsideFolder(manifest.runtime.exec) {
            let program = manifest.runtime.exec
            if let problem = programProblem(program, in: folder) {
                problems.append(problem)
            } else {
                let path = folder.appendingPathComponent(program).path
                if getxattr(path, "com.apple.quarantine", nil, 0, 0, 0) >= 0 { problems.append(.quarantined(program)) }
                if let note = interpreterNote(path) { notes.append(note) }
            }
        }

        var bytes = 0
        var things = 0
        let within = weigh(folder.path, limits, &bytes, &things)
        if !within { problems.append(.tooBig(limits)) }
        return FolderReport(folder: folder, manifest: manifest, problems: problems, notes: notes,
                            bytes: within ? bytes : nil, things: within ? things : nil)
    }

    /// The manifest, when it can be read as one. Every broken rule is added
    /// to `problems`, not only the first.
    private static func readManifest(in folder: URL, into problems: inout [FolderProblem]) -> ToolManifestFile? {
        let path = folder.appendingPathComponent(ToolManifestFile.fileName).path
        var status = stat()
        guard stat(path, &status) == 0 else {
            problems.append(.noManifest)
            return nil
        }
        // Asked before the file is read, so a huge file is never loaded.
        guard status.st_size <= ManifestLimits.maxBytes else {
            problems.append(.manifest(.tooLarge(bytes: Int(status.st_size))))
            return nil
        }
        guard let data = FileManager.default.contents(atPath: path) else {
            problems.append(.noManifest)
            return nil
        }
        switch ToolManifestFile.read(data) {
        case .success(let file):
            return file
        case .failure(let first):
            guard let file = try? JSONDecoder().decode(ToolManifestFile.self, from: data) else {
                problems.append(.manifest(first))
                return nil
            }
            problems += file.problems().map(FolderProblem.manifest)
            return file
        }
    }

    /// Why the program cannot be started from the folder, or nil.
    private static func programProblem(_ program: String, in folder: URL) -> FolderProblem? {
        let path = folder.appendingPathComponent(program).path
        // With every link followed. Nil when the path leads nowhere.
        guard let resolved = realpath(path, nil) else { return .programMissing(program) }
        defer { free(resolved) }
        let real = String(cString: resolved)
        var status = stat()
        guard stat(real, &status) == 0, status.st_mode & S_IFMT == S_IFREG else { return .programMissing(program) }
        guard let home = realpath(folder.path, nil) else { return .programMissing(program) }
        defer { free(home) }
        guard real.hasPrefix(String(cString: home) + "/") else { return .programOutsideFolder(program) }
        guard access(real, X_OK) == 0 else { return .programNotExecutable(program) }
        return nil
    }

    /// A program that starts through `env` finds its interpreter on the
    /// `PATH`, and the app's is shorter than a terminal's.
    private static func interpreterNote(_ path: String) -> String? {
        guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? handle.close() }
        let head = String(decoding: (try? handle.read(upToCount: 160)) ?? Data(), as: UTF8.self)
        guard head.hasPrefix("#!"), let line = head.split(separator: "\n").first, line.contains("/env ") else {
            return nil
        }
        let interpreter = line.split(separator: " ").last.map(String.init) ?? "its interpreter"
        return "the program starts through `env \(interpreter)`. The app starts a tool with the short PATH macOS "
            + "gives an app, \(shortPath), so `\(interpreter)` must be in one of those folders. "
            + "`vitruvian-tool run --app-path` starts it that way."
    }

    /// The `PATH` an app opened from the Finder has.
    public static let shortPath = "/usr/bin:/bin:/usr/sbin:/sbin"

    /// Adds up what is under `path`, and stops as soon as it is over a
    /// limit: false then. A link is one thing and is not followed.
    private static func weigh(_ path: String, _ limits: FolderLimits, _ bytes: inout Int, _ things: inout Int) -> Bool {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: path) else { return true }
        for name in names {
            let child = path + "/" + name
            var status = stat()
            guard lstat(child, &status) == 0 else { continue }
            things += 1
            let kind = status.st_mode & S_IFMT
            if kind == S_IFREG { bytes += Int(status.st_size) }
            if bytes > limits.bytes || things > limits.things { return false }
            if kind == S_IFDIR, !weigh(child, limits, &bytes, &things) { return false }
        }
        return true
    }
}
