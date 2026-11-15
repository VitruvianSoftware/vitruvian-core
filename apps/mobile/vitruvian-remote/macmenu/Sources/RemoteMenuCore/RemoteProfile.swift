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

/// Where one Vitruvian Remote installation keeps its settings, `0600`
/// credentials/pairing files, log file, and `vitruvian-remote-agent` binary.
///
/// | | `.app` (Standalone) | `.extension` (Vitruvian Tool) |
/// |---|---|---|
/// | Settings | `~/.config/vitruvian-remote-agent/settings.json` | `<data>/settings.json` |
/// | Config dir (`0600` tokens & pairing) | `~/.config/vitruvian-remote-agent` | `<data>/config` |
/// | Log file | `~/Library/Logs/vitruvian-remote-agent.log` | `<data>/vitruvian-remote-agent.log` |
/// | Agent binary | `~/.local/bin/vitruvian-remote-agent` (or app bundle) | `<toolFolder>/bin/vitruvian-remote-agent` |
/// | LaunchAgent plist | `~/Library/LaunchAgents/com.vitruvian.remote-agent.plist` | `nil` (supervised by tool) |
/// | Live lock | `nil` | `<data>/running.lock` |
public struct RemoteProfile: Sendable, Equatable {
    public enum Door: String, Codable, Sendable, Equatable {
        case app
        case `extension`
    }

    public static let appBundleID = "com.vitruviansoftware.remote"
    public static let extensionToolID = "dev.vitruvian.remote"

    public let door: Door
    public let settingsURL: URL
    public let configDirURL: URL
    public let logURL: URL
    public let agentBinaryURL: URL
    public let launchAgentPlistURL: URL?
    public let liveLockURL: URL?
    public let toolFolder: URL?
    public let choiceFileURL: URL

    public init(
        door: Door,
        settingsURL: URL,
        configDirURL: URL,
        logURL: URL,
        agentBinaryURL: URL,
        launchAgentPlistURL: URL?,
        liveLockURL: URL?,
        toolFolder: URL?,
        choiceFileURL: URL
    ) {
        self.door = door
        self.settingsURL = settingsURL
        self.configDirURL = configDirURL
        self.logURL = logURL
        self.agentBinaryURL = agentBinaryURL
        self.launchAgentPlistURL = launchAgentPlistURL
        self.liveLockURL = liveLockURL
        self.toolFolder = toolFolder
        self.choiceFileURL = choiceFileURL
    }

    /// The shared choice file read by both the standalone app and the Vitruvian extension.
    public static func defaultChoiceFileURL(
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> URL {
        home
            .appendingPathComponent(".config", isDirectory: true)
            .appendingPathComponent("vitruvian-remote-agent", isDirectory: true)
            .appendingPathComponent("remote_door.json")
    }

    /// The standalone app profile: preserves the exact `~/.config/vitruvian-remote-agent`,
    /// `~/.local/bin/vitruvian-remote-agent`, and `~/Library/Logs/vitruvian-remote-agent.log`
    /// paths used by `macagent/install.sh` and `AgentPaths`, falling back to a bundled
    /// `vitruvian-remote-agent` inside `VitruvianRemote.app/Contents/MacOS/` if `~/.local/bin`
    /// does not have one yet.
    public static func app(
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        bundledAgentURL: URL? = Bundle.main.executableURL?
            .deletingLastPathComponent()
            .appendingPathComponent("vitruvian-remote-agent"),
        fileExists: (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) }
    ) -> Self {
        let paths = AgentPaths(home: home)
        let configDir = home
            .appendingPathComponent(".config", isDirectory: true)
            .appendingPathComponent("vitruvian-remote-agent", isDirectory: true)
        let plistURL = home
            .appendingPathComponent("Library/LaunchAgents", isDirectory: true)
            .appendingPathComponent("\(AgentPaths.label).plist")
        let chosenBinary: URL
        if fileExists(paths.binary.path) {
            chosenBinary = paths.binary
        } else if let bundledAgentURL, fileExists(bundledAgentURL.path) {
            chosenBinary = bundledAgentURL
        } else {
            chosenBinary = paths.binary
        }
        return Self(
            door: .app,
            settingsURL: configDir.appendingPathComponent("settings.json"),
            configDirURL: configDir,
            logURL: paths.log,
            agentBinaryURL: chosenBinary,
            launchAgentPlistURL: plistURL,
            liveLockURL: nil,
            toolFolder: nil,
            choiceFileURL: defaultChoiceFileURL(home: home)
        )
    }

    /// The Vitruvian extension profile: keeps everything in `dataFolder` and runs
    /// `vitruvian-remote-agent` directly from `toolFolder/bin/vitruvian-remote-agent`.
    public static func `extension`(
        dataFolder: URL,
        toolFolder: URL?,
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        choiceFileURL: URL? = nil
    ) -> Self {
        let configDir = dataFolder.appendingPathComponent("config", isDirectory: true)
        let binaryURL = (toolFolder ?? dataFolder)
            .appendingPathComponent("bin", isDirectory: true)
            .appendingPathComponent("vitruvian-remote-agent")
        return Self(
            door: .extension,
            settingsURL: dataFolder.appendingPathComponent("settings.json"),
            configDirURL: configDir,
            logURL: dataFolder.appendingPathComponent("vitruvian-remote-agent.log"),
            agentBinaryURL: binaryURL,
            launchAgentPlistURL: nil,
            liveLockURL: dataFolder.appendingPathComponent("running.lock"),
            toolFolder: toolFolder,
            choiceFileURL: choiceFileURL ?? defaultChoiceFileURL(home: home)
        )
    }

    /// Works out the extension's `tool` and `data` folders from its executable path
    /// (`.../Tools/<id>/bin/tool` -> `.../Tools/<id>` and `.../ToolData/<id>`).
    public static func extensionFolders(program: URL) -> (tool: URL, data: URL)? {
        guard program.isFileURL, program.baseURL == nil, program.path.hasPrefix("/") else {
            return nil
        }
        let parts = program.standardizedFileURL.pathComponents
        guard parts.count >= 6 else { return nil }
        let tail = Array(parts.suffix(4))
        guard tail[0] == "Tools", tail[2] == "bin", tail[3] == "tool" else { return nil }
        let id = tail[1]
        guard !id.isEmpty, id != ".", id != ".." else { return nil }
        let parent = URL(
            fileURLWithPath: NSString.path(withComponents: Array(parts.dropLast(4))),
            isDirectory: true
        )
        return (
            tool: parent.appendingPathComponent("Tools", isDirectory: true).appendingPathComponent(id, isDirectory: true),
            data: parent.appendingPathComponent("ToolData", isDirectory: true).appendingPathComponent(id, isDirectory: true)
        )
    }

    // MARK: - Files inside configDirURL

    public var tokenURL: URL { configDirURL.appendingPathComponent("token") }
    public var pairedURL: URL { configDirURL.appendingPathComponent("paired") }
    public var pairJSONURL: URL { configDirURL.appendingPathComponent("pair.json") }
    public var mcpTokenURL: URL { configDirURL.appendingPathComponent("mcp-token") }
    public var hookTokenURL: URL { configDirURL.appendingPathComponent("hook-token") }
    public var notifyEnabledURL: URL { configDirURL.appendingPathComponent("notify-enabled") }
    public var ntfyTokenURL: URL { configDirURL.appendingPathComponent("ntfy-token") }
    public var prometheusTokenURL: URL { configDirURL.appendingPathComponent("prometheus-token") }

    /// The `0600` credential and state files copied when migrating between `.app` and `.extension`.
    public static let portableConfigFileNames: [String] = [
        "token",
        "paired",
        "mcp-token",
        "hook-token",
        "notify-enabled",
        "ntfy-token",
        "prometheus-token",
    ]

    /// The exact command written into `~/.claude/settings.json` for this profile's
    /// `PermissionRequest` hook.
    public func hookCommandLine(
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> String {
        let exe = Self.shellQuote(agentBinaryURL.path)
        let defaultDir = home
            .appendingPathComponent(".config", isDirectory: true)
            .appendingPathComponent("vitruvian-remote-agent", isDirectory: true)
            .standardizedFileURL.path
        let thisDir = configDirURL.standardizedFileURL.path
        if door == .app && thisDir == defaultDir {
            return "\(exe) permission-hook"
        }
        return "\(exe) permission-hook --config-dir \(Self.shellQuote(thisDir))"
    }

    /// The `claude mcp add` command for registering this profile's `/mcp/phone` bridge
    /// with Claude Code. Single-quotes the `mcp-token` path when it contains spaces
    /// (such as `Application Support`).
    public var mcpAddCommand: String {
        let quotedPath = Self.shellQuote(mcpTokenURL.path)
        return #"claude mcp add --transport http vitruvian-remote-phone http://127.0.0.1:7411/mcp/phone --header "Authorization: Bearer $(cat \#(quotedPath))""#
    }

    /// Quotes a path for POSIX sh when it contains spaces or special characters.
    public static func shellQuote(_ s: String) -> String {
        guard !s.isEmpty else { return "''" }
        let safeChars = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789/._-+")
        if s.unicodeScalars.allSatisfy({ safeChars.contains($0) }) {
            return s
        }
        return "'" + s.replacingOccurrences(of: "'", with: #"'\''"#) + "'"
    }
}
