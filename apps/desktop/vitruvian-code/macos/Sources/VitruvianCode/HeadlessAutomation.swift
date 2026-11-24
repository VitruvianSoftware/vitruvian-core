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
import VitruvianCodeCore

/// `VitruvianCode --run-automation <id>`: runs one scheduled task and exits.
/// A LaunchAgent that a schedule exported starts the app this way, with the
/// app closed. No window, menu bar item, hotkey, bot or update check is
/// started: only the engine's saved settings and the shared runner.
@MainActor
enum HeadlessAutomation {
    /// Starts the run and never returns: the process exits with the run's
    /// status when it is done.
    static func start(taskID: UUID, arguments: [String]) -> Never {
        let application = NSApplication.shared
        application.setActivationPolicy(.prohibited)
        Task { @MainActor in
            let code = await run(taskID: taskID, arguments: arguments)
            exit(code)
        }
        application.run()
        exit(0)
    }

    private static func run(taskID: UUID, arguments: [String]) async -> Int32 {
        let stateDirectoryOverride: String?
        do {
            stateDirectoryOverride = try VitruvianCodeSupport.stateDirectoryOverride(arguments: arguments)
        } catch {
            FileHandle.standardError.write(Data("VitruvianCode: \(error)\n".utf8))
            return 2
        }
        if let stateDirectoryOverride {
            AppPreferences.useSuite(forStateDirectory: stateDirectoryOverride)
        }
        let host = StandaloneHost()
        var environment = VitruvianCodeEngine.Environment.live(stateDirectoryOverride: stateDirectoryOverride)
        environment.defaults = AppPreferences.defaults
        let engine = StandaloneEngine(environment: environment, host: host)

        let log = AutomationLog(path: (engine.logsDirectory as NSString).appendingPathComponent("automation.log"))
        let runner = engine.makeAutomationRunner(notifier: UnattendedRunNotifier(), log: { log.write($0) })

        // A stop from launchd, a logout or the user ends the run, and with it
        // the agent's process group, before the process goes.
        var sources: [DispatchSourceSignal] = []
        for number in [SIGTERM, SIGINT, SIGHUP] {
            signal(number, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: number, queue: .main)
            source.setEventHandler { MainActor.assumeIsolated { runner.abort() } }
            source.resume()
            sources.append(source)
        }
        let outcome = await runner.run(taskID: taskID)
        sources.forEach { $0.cancel() }
        return outcome.exitCode
    }
}

/// Where a scheduled run writes what it did: one line each, with a time, in
/// `logs/automation.log`, and on standard error. Only the words the runner
/// gives it, which hold no prompt and no output of the agent. The file is
/// cut back to its last part when it grows past a quarter of a megabyte.
final class AutomationLog {
    private let path: String
    private static let limit = 256 * 1024

    init(path: String) {
        self.path = path
    }

    func write(_ message: String) {
        let line = "\(ISO8601DateFormatter().string(from: Date())) \(message)\n"
        FileHandle.standardError.write(Data(line.utf8))
        let directory = (path as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        if let size = (try? FileManager.default.attributesOfItem(atPath: path)[.size]) as? Int, size > Self.limit,
           let existing = try? Data(contentsOf: URL(fileURLWithPath: path)) {
            try? existing.suffix(Self.limit / 2).write(to: URL(fileURLWithPath: path), options: .atomic)
        }
        if !FileManager.default.fileExists(atPath: path) {
            FileManager.default.createFile(atPath: path, contents: nil, attributes: [.posixPermissions: 0o600])
        }
        guard let handle = FileHandle(forWritingAtPath: path) else { return }
        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: Data(line.utf8))
    }
}
