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

/// Locates and runs the `claude` CLI for installing, updating, and removing the
/// Vitruvian Speaker Claude Code plugin without assuming login-shell `PATH`.
public enum ClaudeCLI {
    public struct CommandResult: Equatable, Sendable {
        public let exitCode: Int32
        public let stdout: String
        public let stderr: String

        public init(exitCode: Int32, stdout: String, stderr: String) {
            self.exitCode = exitCode
            self.stdout = stdout
            self.stderr = stderr
        }
    }

    public static func versionSortDescending(_ lhs: String, _ rhs: String) -> Bool {
        lhs.compare(rhs, options: .numeric) == .orderedDescending
    }

    /// Returns candidate paths for the `claude` executable in priority order:
    /// native installers first, system package managers (when enabled), then
    /// Node/runtime version managers (Volta, fnm, nvm, asdf, mise, bun, pnpm, npm).
    public static func candidatePaths(
        home: URL,
        searchPath: String? = ProcessInfo.processInfo.environment["PATH"],
        includeSystemPaths: Bool = true,
        fileManager: FileManager = .default
    ) -> [String] {
        var candidates: [String] = [
            home.appendingPathComponent(".local/bin/claude").path,
            home.appendingPathComponent(".claude/local/claude").path,
        ]

        if includeSystemPaths {
            candidates.append("/opt/homebrew/bin/claude")
            candidates.append("/usr/local/bin/claude")
            if let searchPath, !searchPath.isEmpty {
                for entry in searchPath.split(separator: ":").map(String.init) where !entry.isEmpty {
                    candidates.append(URL(fileURLWithPath: entry, isDirectory: true).appendingPathComponent("claude").path)
                }
            }
        }

        candidates.append(home.appendingPathComponent(".volta/bin/claude").path)

        let fnmRoots = [
            home.appendingPathComponent("Library/Application Support/fnm", isDirectory: true),
            home.appendingPathComponent(".local/share/fnm", isDirectory: true),
            home.appendingPathComponent(".fnm", isDirectory: true),
        ]
        for root in fnmRoots {
            candidates.append(root.appendingPathComponent("aliases/default/bin/claude").path)
        }
        for root in fnmRoots {
            let versionsDir = root.appendingPathComponent("node-versions", isDirectory: true)
            if let versions = try? fileManager.contentsOfDirectory(atPath: versionsDir.path) {
                for version in versions.sorted(by: versionSortDescending) {
                    candidates.append(
                        versionsDir
                            .appendingPathComponent(version, isDirectory: true)
                            .appendingPathComponent("installation/bin/claude")
                            .path
                    )
                }
            }
        }

        let nvmDir = home.appendingPathComponent(".nvm/versions/node", isDirectory: true)
        if let versions = try? fileManager.contentsOfDirectory(atPath: nvmDir.path) {
            for version in versions.sorted(by: versionSortDescending) {
                candidates.append(
                    nvmDir
                        .appendingPathComponent(version, isDirectory: true)
                        .appendingPathComponent("bin/claude")
                        .path
                )
            }
        }

        candidates.append(home.appendingPathComponent(".asdf/shims/claude").path)
        candidates.append(home.appendingPathComponent(".local/share/mise/shims/claude").path)
        candidates.append(home.appendingPathComponent(".bun/bin/claude").path)
        candidates.append(home.appendingPathComponent("Library/pnpm/claude").path)
        candidates.append(home.appendingPathComponent(".npm-global/bin/claude").path)

        var seen: Set<String> = []
        return candidates.filter { seen.insert($0).inserted }
    }

    public static func findExecutable(
        home: URL,
        searchPath: String? = ProcessInfo.processInfo.environment["PATH"],
        includeSystemPaths: Bool = true,
        fileManager: FileManager = .default
    ) -> String? {
        for path in candidatePaths(
            home: home,
            searchPath: searchPath,
            includeSystemPaths: includeSystemPaths,
            fileManager: fileManager
        ) where fileManager.isExecutableFile(atPath: path) {
            return path
        }
        return nil
    }

    public static func subprocessEnvironment(
        home: URL,
        executablePath: String,
        baseEnvironment: [String: String] = ProcessInfo.processInfo.environment,
        includeSystemPaths: Bool = true
    ) -> [String: String] {
        var env = baseEnvironment
        env["HOME"] = home.path
        env["DISABLE_AUTOUPDATER"] = "1"
        env.removeValue(forKey: "CLAUDECODE")

        let execDir = URL(fileURLWithPath: executablePath).deletingLastPathComponent().path
        var pathParts = [
            execDir,
            home.appendingPathComponent(".local/bin").path,
            home.appendingPathComponent(".volta/bin").path,
            home.appendingPathComponent(".asdf/shims").path,
            home.appendingPathComponent(".local/share/mise/shims").path,
            home.appendingPathComponent(".bun/bin").path,
            home.appendingPathComponent("Library/pnpm").path,
            home.appendingPathComponent(".npm-global/bin").path,
        ]
        if includeSystemPaths {
            pathParts.append(contentsOf: ["/opt/homebrew/bin", "/usr/local/bin"])
            if let existing = baseEnvironment["PATH"], !existing.isEmpty {
                pathParts.append(contentsOf: existing.split(separator: ":").map(String.init))
            }
        }
        pathParts.append(contentsOf: ["/usr/bin", "/bin"])

        var seen: Set<String> = []
        let deduped = pathParts.filter { !$0.isEmpty && seen.insert($0).inserted }
        env["PATH"] = deduped.joined(separator: ":")
        return env
    }

    public static func execute(
        executablePath: String,
        arguments: [String],
        home: URL,
        includeSystemPaths: Bool = true
    ) throws -> CommandResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        process.environment = subprocessEnvironment(
            home: home,
            executablePath: executablePath,
            includeSystemPaths: includeSystemPaths
        )

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        process.standardInput = FileHandle.nullDevice

        final class Box: @unchecked Sendable {
            var data = Data()
        }
        let stdoutBox = Box()
        let stderrBox = Box()
        let group = DispatchGroup()

        try process.run()

        group.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            stdoutBox.data = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }
        group.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            stderrBox.data = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }

        group.wait()
        process.waitUntilExit()

        return CommandResult(
            exitCode: process.terminationStatus,
            stdout: String(decoding: stdoutBox.data, as: UTF8.self),
            stderr: String(decoding: stderrBox.data, as: UTF8.self)
        )
    }
}

public struct ClaudeCLIRunner: Sendable {
    public let findExecutable: @Sendable () -> String?
    public let run: @Sendable (_ arguments: [String]) throws -> ClaudeCLI.CommandResult

    public var isAvailable: Bool { findExecutable() != nil }

    public init(
        findExecutable: @escaping @Sendable () -> String?,
        run: @escaping @Sendable (_ arguments: [String]) throws -> ClaudeCLI.CommandResult
    ) {
        self.findExecutable = findExecutable
        self.run = run
    }

    public static func live(home: URL) -> ClaudeCLIRunner {
        ClaudeCLIRunner(
            findExecutable: {
                ClaudeCLI.findExecutable(home: home, includeSystemPaths: true)
            },
            run: { arguments in
                guard let path = ClaudeCLI.findExecutable(home: home, includeSystemPaths: true) else {
                    throw NSError(
                        domain: "VitruvianSpeakerCore.ClaudeCLI",
                        code: 127,
                        userInfo: [NSLocalizedDescriptionKey: "claude executable not found"]
                    )
                }
                return try ClaudeCLI.execute(
                    executablePath: path,
                    arguments: arguments,
                    home: home,
                    includeSystemPaths: true
                )
            }
        )
    }

    /// Searches only inside `home` so tests using a scratch home directory
    /// never invoke the user's real `~/.claude` or ambient system `claude`.
    public static func scopedToHome(_ home: URL) -> ClaudeCLIRunner {
        ClaudeCLIRunner(
            findExecutable: {
                ClaudeCLI.findExecutable(home: home, searchPath: nil, includeSystemPaths: false)
            },
            run: { arguments in
                guard let path = ClaudeCLI.findExecutable(home: home, searchPath: nil, includeSystemPaths: false) else {
                    throw NSError(
                        domain: "VitruvianSpeakerCore.ClaudeCLI",
                        code: 127,
                        userInfo: [NSLocalizedDescriptionKey: "claude executable not found in \(home.path)"]
                    )
                }
                return try ClaudeCLI.execute(
                    executablePath: path,
                    arguments: arguments,
                    home: home,
                    includeSystemPaths: false
                )
            }
        )
    }
}
