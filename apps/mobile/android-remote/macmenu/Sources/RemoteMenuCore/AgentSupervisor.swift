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

import Darwin
import Foundation

/// Inspects `~/.claude/settings.json` to see whether the `vitruvian-remote-agent`
/// `PermissionRequest` hook is installed.
public enum ClaudeHookInspector {
    public static func defaultSettingsURL(
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> URL {
        home
            .appendingPathComponent(".claude", isDirectory: true)
            .appendingPathComponent("settings.json")
    }

    /// True when `settingsURL` has a `hooks.PermissionRequest` entry whose command
    /// invokes `vitruvian-remote-agent` `permission-hook`.
    public static func isInstalled(at settingsURL: URL = defaultSettingsURL()) -> Bool {
        guard let data = try? Data(contentsOf: settingsURL),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let hooks = root["hooks"] as? [String: Any],
              let groups = hooks["PermissionRequest"] as? [[String: Any]]
        else {
            return false
        }
        for group in groups {
            guard let list = group["hooks"] as? [[String: Any]] else { continue }
            for entry in list {
                guard let cmd = entry["command"] as? String else { continue }
                let trimmed = cmd.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.contains("vitruvian-remote-agent") &&
                    (trimmed.hasSuffix("permission-hook") || trimmed.contains(" permission-hook "))
                {
                    return true
                }
            }
        }
        return false
    }
}

/// Supervises the `vitruvian-remote-agent` child process (for the Vitruvian extension,
/// or a standalone app without a LaunchAgent) and runs its CLI subcommands (`pair`,
/// `token --rotate`, `install-claude-hook`) against a `RemoteProfile`.
public final class AgentSupervisor: @unchecked Sendable {
    public typealias CommandRunner = @Sendable (URL, [String]) -> CommandResult

    public let profile: RemoteProfile
    public let home: URL
    public let claudeSettingsURL: URL
    public let allowChildSpawn: Bool
    private let runCommand: CommandRunner
    private let lock = NSLock()
    private var childProcess: Process?
    private var logFileHandle: FileHandle?
    private var lastStartedArgs: [String]?

    public init(
        profile: RemoteProfile,
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        claudeSettingsURL: URL? = nil,
        allowChildSpawn: Bool = true,
        runCommand: @escaping CommandRunner = Runner.runSync
    ) {
        self.profile = profile
        self.home = home
        self.claudeSettingsURL = claudeSettingsURL ?? ClaudeHookInspector.defaultSettingsURL(home: home)
        self.allowChildSpawn = allowChildSpawn
        self.runCommand = runCommand
    }

    deinit {
        stopSupervisedProcess()
    }

    // MARK: - Child Process Supervision

    public var isSupervisedProcessRunning: Bool {
        lock.lock()
        defer { lock.unlock() }
        return childProcess?.isRunning == true
    }

    /// Starts `vitruvian-remote-agent` as a supervised child process when not already
    /// running with the same arguments. Returns `true` if the child is running after the call.
    @discardableResult
    public func startSupervisedProcess(settings: RemoteSettings) -> Bool {
        guard allowChildSpawn else { return false }
        let binaryURL = profile.agentBinaryURL
        guard FileManager.default.isExecutableFile(atPath: binaryURL.path) else {
            return false
        }
        let args = settings.agentArguments(for: profile, home: home)

        lock.lock()
        if let existing = childProcess, existing.isRunning {
            if lastStartedArgs == args {
                lock.unlock()
                return true
            }
            lock.unlock()
            stopSupervisedProcess()
            lock.lock()
        }

        do {
            try FileManager.default.createDirectory(
                at: profile.configDirURL,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: NSNumber(value: Int16(0o700))]
            )
            let logDir = profile.logURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: logDir, withIntermediateDirectories: true)
            if !FileManager.default.fileExists(atPath: profile.logURL.path) {
                FileManager.default.createFile(
                    atPath: profile.logURL.path,
                    contents: nil,
                    attributes: [.posixPermissions: NSNumber(value: Int16(0o600))]
                )
            }
            let handle = try? FileHandle(forWritingTo: profile.logURL)
            _ = try? handle?.seekToEnd()

            let p = Process()
            p.executableURL = binaryURL
            p.arguments = args
            if let handle {
                p.standardOutput = handle
                p.standardError = handle
            } else {
                p.standardOutput = FileHandle.nullDevice
                p.standardError = FileHandle.nullDevice
            }
            p.standardInput = FileHandle.nullDevice
            try p.run()
            childProcess = p
            logFileHandle = handle
            lastStartedArgs = args
            lock.unlock()
            return true
        } catch {
            lock.unlock()
            return false
        }
    }

    /// Stops the supervised child process if one is running.
    public func stopSupervisedProcess() {
        lock.lock()
        let proc = childProcess
        let handle = logFileHandle
        childProcess = nil
        logFileHandle = nil
        lastStartedArgs = nil
        lock.unlock()

        if let proc, proc.isRunning {
            proc.terminate()
            let deadline = Date().addingTimeInterval(2.0)
            while proc.isRunning && Date() < deadline {
                usleep(50_000)
            }
            if proc.isRunning {
                kill(proc.processIdentifier, SIGKILL)
            }
        }
        try? handle?.close()
    }

    /// Restarts the agent for this profile.
    @discardableResult
    public func restartAgent(settings: RemoteSettings) -> CommandResult {
        guard allowChildSpawn else {
            return CommandResult(exitStatus: 0, output: "Agent restarted")
        }
        switch profile.door {
        case .extension:
            stopSupervisedProcess()
            let ok = startSupervisedProcess(settings: settings)
            return ok
                ? CommandResult(exitStatus: 0, output: "Agent restarted")
                : CommandResult(exitStatus: 1, output: "Could not start vitruvian-remote-agent at \(profile.agentBinaryURL.path)")
        case .app:
            if let plistURL = profile.launchAgentPlistURL,
               FileManager.default.fileExists(atPath: plistURL.path)
            {
                try? Self.writeLaunchAgentPlist(to: plistURL, profile: profile, settings: settings, home: home)
                let launchctl = URL(fileURLWithPath: "/bin/launchctl")
                _ = runCommand(launchctl, ["bootout", "gui/\(getuid())/\(AgentPaths.label)"])
                Self.waitForLoopbackPortToClose(port: 7411, timeout: 1.5)
                let boot = runCommand(launchctl, ["bootstrap", "gui/\(getuid())", plistURL.path])
                if boot.succeeded {
                    return boot
                }
                return runCommand(launchctl, AgentPaths.restartArguments(uid: getuid()))
            } else {
                stopSupervisedProcess()
                let ok = startSupervisedProcess(settings: settings)
                return ok
                    ? CommandResult(exitStatus: 0, output: "Agent restarted")
                    : CommandResult(exitStatus: 1, output: "Could not start vitruvian-remote-agent")
            }
        }
    }

    // MARK: - Subcommands (pair, token --rotate, install-claude-hook)

    private var configDirSubcommandArgs: [String] {
        let defaultDir = home
            .appendingPathComponent(".config", isDirectory: true)
            .appendingPathComponent("vitruvian-remote-agent", isDirectory: true)
            .standardizedFileURL.path
        let thisDir = profile.configDirURL.standardizedFileURL.path
        if profile.door == .app && thisDir == defaultDir {
            return []
        }
        return ["--config-dir", thisDir]
    }

    public func pair(code: String) -> CommandResult {
        guard let normalized = PairCode.normalize(code) else {
            return CommandResult(exitStatus: 2, output: "Code must be six digits")
        }
        return runCommand(profile.agentBinaryURL, ["pair"] + configDirSubcommandArgs + [normalized])
    }

    public func rotateToken() -> CommandResult {
        runCommand(profile.agentBinaryURL, ["token"] + configDirSubcommandArgs + ["--rotate"])
    }

    public func isPermissionHookInstalled() -> Bool {
        ClaudeHookInspector.isInstalled(at: claudeSettingsURL)
    }

    @discardableResult
    public func setPermissionHookEnabled(_ enabled: Bool) -> CommandResult {
        var args = ["install-claude-hook"]
        if !enabled {
            args.append("--remove")
        }
        args += ["--settings", claudeSettingsURL.path]
        args += configDirSubcommandArgs
        return runCommand(profile.agentBinaryURL, args)
    }

    // MARK: - Standalone LaunchAgent Management & Port Handoff

    /// Writes `~/Library/LaunchAgents/com.vitruvian.remote-agent.plist` with `settings`'s
    /// flags so the standalone LaunchAgent picks up configuration edits made in the UI.
    public static func writeLaunchAgentPlist(
        to plistURL: URL,
        profile: RemoteProfile,
        settings: RemoteSettings,
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) throws {
        let programArgs = [profile.agentBinaryURL.path] + settings.agentArguments(for: profile, home: home)
        let dict: [String: Any] = [
            "Label": AgentPaths.label,
            "ProgramArguments": programArgs,
            "RunAtLoad": true,
            "KeepAlive": true,
            "ProcessType": "Background",
            "StandardOutPath": profile.logURL.path,
            "StandardErrorPath": profile.logURL.path,
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: dict, format: .xml, options: 0)
        try FileLock.writeAtomically(data, to: plistURL, permissions: 0o644)
    }

    /// Stops the standalone LaunchAgent (`launchctl bootout gui/<uid>/com.vitruvian.remote-agent`),
    /// optionally removes the plist so it does not start at next login, and waits for port `7411`
    /// to close so the extension can bind `127.0.0.1:7411` cleanly.
    public func stopStandaloneAgent(
        disableLaunchAgentAtLogin: Bool = false
    ) {
        if disableLaunchAgentAtLogin {
            let plistURL = home
                .appendingPathComponent("Library/LaunchAgents", isDirectory: true)
                .appendingPathComponent("\(AgentPaths.label).plist")
            try? FileManager.default.removeItem(at: plistURL)
        }
        guard allowChildSpawn else { return }
        let launchctl = URL(fileURLWithPath: "/bin/launchctl")
        _ = runCommand(launchctl, ["bootout", "gui/\(getuid())/\(AgentPaths.label)"])
        Self.waitForLoopbackPortToClose(port: 7411, timeout: 2.5)
    }

    /// Waits until `127.0.0.1:<port>` is no longer accepting TCP connections, or `timeout` elapses.
    public static func waitForLoopbackPortToClose(port: UInt16 = 7411, timeout: TimeInterval = 2.0) {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if !isLoopbackPortOpen(port: port) {
                return
            }
            usleep(50_000)
        }
    }

    public static func isLoopbackPortOpen(port: UInt16 = 7411) -> Bool {
        let sock = socket(AF_INET, SOCK_STREAM, 0)
        guard sock >= 0 else { return false }
        defer { close(sock) }
        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")
        let connected = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(sock, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        return connected == 0
    }
}
