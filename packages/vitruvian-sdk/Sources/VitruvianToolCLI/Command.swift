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

/// The `vitruvian-tool` command: its arguments read, and each of its verbs.
/// It is a library so that the tests can call it; the program itself is
/// three lines (`Sources/vitruvian-tool/main.swift`).
public enum VitruvianToolCommand {
    /// Runs the command. `arguments` are those after the program's name.
    /// `say` takes each line it prints. Returns the status to exit with.
    public static func main(_ arguments: [String],
                            environment: [String: String] = ProcessInfo.processInfo.environment,
                            typing: Int32 = STDIN_FILENO,
                            say: @escaping (String) -> Void = { print($0) }) -> Int32 {
        var rest = arguments[...]
        switch rest.popFirst() {
        case "validate"?:
            guard rest.count == 1, let folder = rest.first, !folder.hasPrefix("-") else { return usage(say) }
            return validate(url(folder, environment), say: say)
        case "run"?:
            guard let (folder, options) = runArguments(rest) else { return usage(say) }
            return run(folder: url(folder, environment), options: options, environment: environment,
                       typing: typing, say: say)
        case "help"?, "--help"?, "-h"?:
            say(Words.usage)
            return 0
        default:
            return usage(say)
        }
    }

    static func usage(_ say: (String) -> Void) -> Int32 {
        say(Words.usage)
        return 2
    }

    /// A path the person typed. `bazel run` starts a program in a folder of
    /// its own and says in `BUILD_WORKING_DIRECTORY` where the person was.
    static func url(_ path: String, _ environment: [String: String]) -> URL {
        let expanded = (path as NSString).expandingTildeInPath
        if expanded.hasPrefix("/") { return URL(fileURLWithPath: expanded) }
        let base = environment["BUILD_WORKING_DIRECTORY"] ?? FileManager.default.currentDirectoryPath
        return URL(fileURLWithPath: base, isDirectory: true).appendingPathComponent(expanded).standardizedFileURL
    }

    /// What follows `run`: the folder, and how to play the app. Nil when
    /// it cannot be read. There is no flag that makes `run` touch the
    /// clipboard, open a link or end a process, and there is not meant to
    /// be one.
    public static func runArguments(_ arguments: ArraySlice<String>) -> (folder: String, options: RunOptions)? {
        var options = RunOptions()
        var folder: String?
        var rest = arguments
        while let argument = rest.popFirst() {
            switch argument {
            case "--command":
                guard let command = rest.popFirst() else { return nil }
                options.commands.append(command)
            case "--refuse":
                options.refuse = true
            case "--app-path":
                options.appPath = true
            case "--wait":
                guard let seconds = rest.popFirst().flatMap(TimeInterval.init), seconds > 0 else { return nil }
                options.answerSeconds = seconds
            default:
                guard folder == nil, !argument.hasPrefix("-") else { return nil }
                folder = argument
            }
        }
        return folder.map { ($0, options) }
    }

    /// Starts the tool in `folder` and plays the app's side to it. What the
    /// person types is read from `typing` when `options` names no command.
    public static func run(folder: URL, options: RunOptions, environment: [String: String], typing: Int32,
                           say: @escaping (String) -> Void) -> Int32 {
        let report = FolderCheck.check(folder)
        guard report.problems.isEmpty, let manifest = report.manifest else {
            for problem in report.problems { say("NOT OK   " + Words.problem(problem)) }
            say("")
            say("Nothing was started: the app would refuse this folder.")
            return 1
        }
        let session = Session(manifest: manifest, options: options, typing: typing, say: say)
        let status = session.run(folder: report.folder, environment: environment)
        say("")
        say(status == 0 ? "run: OK" : "run: FAILED")
        return status
    }

    static func validate(_ folder: URL, say: (String) -> Void) -> Int32 {
        let report = FolderCheck.check(folder)
        if let manifest = report.manifest, !report.problems.contains(where: { $0.verdict == "manifest" }) {
            let commands = manifest.contributes?.commands?.count ?? 0
            say("ok       manifest: \(manifest.id) \(manifest.version), \(commands) command\(commands == 1 ? "" : "s")")
            if !report.problems.contains(where: { $0.verdict.hasPrefix("program") || $0.verdict == "quarantined" }) {
                say("ok       program: \(manifest.runtime.exec)")
            }
        }
        if let bytes = report.bytes, let things = report.things {
            say("ok       folder: \(things) thing\(things == 1 ? "" : "s"), \(max(1, bytes / 1024)) KB")
        }
        for problem in report.problems { say("NOT OK   " + Words.problem(problem)) }
        for note in report.notes { say("note     " + note) }
        if let first = report.problems.first {
            say("")
            say("The app would refuse this folder, and say: " + Words.problem(first) + ".")
            return 1
        }
        say("")
        say(Words.validateLimits)
        return 0
    }
}
