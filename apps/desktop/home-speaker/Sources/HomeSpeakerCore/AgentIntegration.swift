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
import ServiceManagement

/// Installs the Claude Code Stop hook. The hook is this very binary run with
/// `--claude-stop-hook`, so the only thing written into the user's settings
/// is the path to the app they already have.
public struct AgentIntegration {
    public static let shared = AgentIntegration()

    /// Marker every hook entry we write carries, so ours can be found and
    /// replaced without touching hooks the user added themselves.
    public static let hookMarker = ClaudeStopHook.argument
    /// The hook the 1.x releases pointed at; treated as ours for cleanup.
    static let legacyHookMarker = "stop_broadcast.py"

    private let fileManager = FileManager.default
    private let settingsURL: URL
    private let executablePath: String

    public init(
        settingsURL: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/settings.json"),
        executablePath: String = Bundle.main.executablePath ?? CommandLine.arguments[0]
    ) {
        self.settingsURL = settingsURL
        self.executablePath = executablePath
    }

    /// The exact command line Claude Code will run.
    public var hookCommand: String { Self.hookCommand(executable: executablePath) }

    public static func hookCommand(executable: String) -> String {
        "\"\(executable)\" \(hookMarker)"
    }

    // MARK: Pure settings transforms

    static func isOurs(_ command: String) -> Bool {
        command.contains(hookMarker) || command.contains(legacyHookMarker)
    }

    /// Returns `settings` with our Stop hook present exactly once. Existing
    /// Stop hooks that are not ours are preserved in place; stale copies of
    /// ours (an older app path) are replaced. Idempotent.
    public static func mergeStopHook(into settings: [String: Any], command: String) -> [String: Any] {
        var out = settings
        var hooks = (out["hooks"] as? [String: Any]) ?? [:]
        var stop = (hooks["Stop"] as? [[String: Any]]) ?? []

        stop = stop.compactMap { group in
            var g = group
            let inner = (g["hooks"] as? [[String: Any]]) ?? []
            let kept = inner.filter { !isOurs(($0["command"] as? String) ?? "") }
            if kept.isEmpty && !inner.isEmpty { return nil }   // group held only ours
            g["hooks"] = kept
            return g
        }
        stop.append(["hooks": [["type": "command", "command": command, "timeout": 10]]])

        hooks["Stop"] = stop
        out["hooks"] = hooks
        return out
    }

    /// Returns `settings` without any of our Stop hooks; drops the `Stop`
    /// key (and `hooks`) when nothing else remains so the file stays tidy.
    public static func removeStopHook(from settings: [String: Any]) -> [String: Any] {
        var out = settings
        guard var hooks = out["hooks"] as? [String: Any],
              let stop = hooks["Stop"] as? [[String: Any]] else { return out }
        let remaining = stop.compactMap { group -> [String: Any]? in
            var g = group
            let kept = ((g["hooks"] as? [[String: Any]]) ?? []).filter { !isOurs(($0["command"] as? String) ?? "") }
            if kept.isEmpty { return nil }
            g["hooks"] = kept
            return g
        }
        if remaining.isEmpty { hooks.removeValue(forKey: "Stop") } else { hooks["Stop"] = remaining }
        if hooks.isEmpty { out.removeValue(forKey: "hooks") } else { out["hooks"] = hooks }
        return out
    }

    /// The command of our installed hook, if any.
    public static func installedHookCommand(in settings: [String: Any]) -> String? {
        guard let hooks = settings["hooks"] as? [String: Any],
              let stop = hooks["Stop"] as? [[String: Any]] else { return nil }
        for group in stop {
            for h in (group["hooks"] as? [[String: Any]]) ?? [] {
                if let c = h["command"] as? String, isOurs(c) { return c }
            }
        }
        return nil
    }

    // MARK: File I/O

    public enum HookStatus: Equatable {
        case notInstalled
        case installed
        /// Installed, but pointing at a path that is not this app (an older
        /// location, or the 1.x python script).
        case stale(String)
    }

    public func hookStatus() -> HookStatus {
        guard let cmd = Self.installedHookCommand(in: readSettings()) else { return .notInstalled }
        return cmd == hookCommand ? .installed : .stale(cmd)
    }

    public func isClaudeCodeHookInstalled() -> Bool { hookStatus() == .installed }

    public func installClaudeCodeHook() throws {
        try writeSettings(Self.mergeStopHook(into: readSettings(), command: hookCommand))
    }

    public func removeClaudeCodeHook() throws {
        try writeSettings(Self.removeStopHook(from: readSettings()))
    }

    /// Called on every launch: if the user moved the app (Downloads ->
    /// Applications), point the hook at the new location.
    public func repairHookIfMoved() {
        if case .stale = hookStatus() { try? installClaudeCodeHook() }
    }

    private func readSettings() -> [String: Any] {
        guard let data = try? Data(contentsOf: settingsURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        return json
    }

    private func writeSettings(_ settings: [String: Any]) throws {
        let dir = settingsURL.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: dir.path) {
            try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        let data = try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: settingsURL, options: .atomic)
    }

    // MARK: Legacy 1.x launch agent

    /// The 1.x releases wrote a LaunchAgent for an external python daemon
    /// that this app no longer uses. Detect it so Settings can offer cleanup.
    public static let legacyLaunchAgentLabel = "com.james.chat-monitor"

    public var legacyLaunchAgentURL: URL {
        fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(Self.legacyLaunchAgentLabel).plist")
    }

    public func isLegacyLaunchAgentInstalled() -> Bool {
        fileManager.fileExists(atPath: legacyLaunchAgentURL.path)
    }

    public func removeLegacyLaunchAgent() throws {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        proc.arguments = ["bootout", "gui/\(getuid())/\(Self.legacyLaunchAgentLabel)"]
        try? proc.run()
        proc.waitUntilExit()
        try fileManager.removeItem(at: legacyLaunchAgentURL)
    }
}

/// "Open at Login" for the app itself, through the system login-items API.
/// Only meaningful when running from a real .app bundle; from a bare
/// `.build/release` binary registration fails and `isEnabled` stays false.
public enum LoginItem {
    public static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    public static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }

    /// True when macOS wants the user to confirm in System Settings.
    public static var requiresApproval: Bool {
        SMAppService.mainApp.status == .requiresApproval
    }
}
