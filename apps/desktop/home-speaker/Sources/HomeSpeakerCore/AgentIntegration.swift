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

/// The coding agents HomeSpeaker can announce for. Each one has a hooks
/// file, an event that fires when a turn ends, and its own entry shape.
public enum CodingAgent: String, CaseIterable, Sendable {
    case claudeCode
    case antigravity

    public var displayName: String {
        switch self {
        case .claudeCode: return "Claude Code"
        case .antigravity: return "Antigravity"
        }
    }

    /// Whether this app can install a deterministic end-of-turn hook for
    /// the agent. Antigravity 1.2.7's CLI loads `~/.gemini/hooks.json` but
    /// never executes hooks in print mode, and the interactive path could
    /// not be verified, so Antigravity is driven by its instruction file
    /// instead (the `home-speaker-broadcast` line in AGENTS.md).
    public var supportsHook: Bool {
        switch self {
        case .claudeCode: return true
        case .antigravity: return false
        }
    }

    /// The CLI flag this binary answers to for the agent's hook.
    public var hookArgument: String {
        switch self {
        case .claudeCode: return ClaudeStopHook.argument
        case .antigravity: return "--antigravity-hook"   // reserved; not installed
        }
    }

    /// Hook event that fires once the agent has finished a turn.
    var eventKey: String {
        switch self {
        case .claudeCode: return "Stop"
        case .antigravity: return "Stop"
        }
    }

    /// The instruction file this app can append to when the user asks it to
    /// configure an agent the prompt-driven way.
    func primaryInstructionFile(home: URL) -> URL { instructionFiles(home: home)[0] }

    /// Name shown for that file.
    public var instructionFileName: String {
        switch self {
        case .claudeCode: return "~/.claude/CLAUDE.md"
        case .antigravity: return "~/.gemini/AGENTS.md"
        }
    }

    /// The line that tells the agent to announce its replies itself. Kept
    /// identical to what the google-home skill documents so existing
    /// setups are recognised.
    public static let broadcastInstruction = """
    - Follow the `home-speaker-broadcast` skill: Check `~/.gemini/speaker_broadcast.json` for broadcast status. When `"enabled": true`, accompany conversational responses with a concise spoken broadcast (1-2 sentences) to the active speaker (`default_target`) using `home_mcp` (`run_home_actions`) or `speaker-broadcast`. When the user asks to turn speaker broadcasts on/off or change the target room, update `~/.gemini/speaker_broadcast.json` and confirm.
    """

    func settingsURL(home: URL) -> URL {
        switch self {
        case .claudeCode: return home.appendingPathComponent(".claude/settings.json")
        case .antigravity: return home.appendingPathComponent(".gemini/settings.json")
        }
    }

    /// Where the agent keeps itself; used to tell "not installed" from
    /// "installed but not hooked" so the user is never told to install
    /// something they don't have.
    func installMarkers(home: URL) -> [URL] {
        switch self {
        case .claudeCode: return [home.appendingPathComponent(".claude")]
        case .antigravity: return [home.appendingPathComponent(".gemini/antigravity"), home.appendingPathComponent(".gemini/settings.json")]
        }
    }

    /// Instruction files the user may already have told the agent to
    /// broadcast from (the prompt-driven way, before hooks existed).
    func instructionFiles(home: URL) -> [URL] {
        switch self {
        case .claudeCode: return [home.appendingPathComponent(".claude/CLAUDE.md"), home.appendingPathComponent("CLAUDE.md")]
        case .antigravity: return [home.appendingPathComponent(".gemini/AGENTS.md"), home.appendingPathComponent(".gemini/GEMINI.md")]
        }
    }

    /// One hook entry in the agent's own dialect. Claude Code times out in
    /// seconds; Antigravity/Gemini in milliseconds and wants a name.
    func entry(command: String) -> [String: Any] {
        switch self {
        case .claudeCode: return ["type": "command", "command": command, "timeout": 10]
        case .antigravity: return ["name": "homespeaker", "type": "command", "command": command, "timeout": 10_000]
        }
    }

    /// Wraps entries in a group; Antigravity groups carry a matcher.
    func group(_ entries: [[String: Any]]) -> [String: Any] {
        switch self {
        case .claudeCode: return ["hooks": entries]
        case .antigravity: return ["matcher": "*", "hooks": entries]
        }
    }
}

/// Installs the agent hooks. A hook is this very binary run with the
/// agent's flag, so the only thing written into the user's settings is the
/// path to the app they already have.
public struct AgentIntegration {
    public static let shared = AgentIntegration()

    /// Markers every hook entry we write carries, so ours can be found and
    /// replaced without touching hooks the user added themselves.
    static let markers = [ClaudeStopHook.argument, "--antigravity-hook"]
    /// The hook the 1.x releases pointed at; treated as ours for cleanup.
    static let legacyHookMarker = "stop_broadcast.py"

    private let fileManager = FileManager.default
    private let home: URL
    private let executablePath: String

    public init(
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        executablePath: String = Bundle.main.executablePath ?? CommandLine.arguments[0]
    ) {
        self.home = home
        self.executablePath = executablePath
    }

    /// The exact command line the agent will run.
    public func hookCommand(for agent: CodingAgent) -> String {
        Self.hookCommand(executable: executablePath, agent: agent)
    }

    public static func hookCommand(executable: String, agent: CodingAgent = .claudeCode) -> String {
        "\"\(executable)\" \(agent.hookArgument)"
    }

    // Claude Code conveniences kept for callers and tests.
    public var hookCommand: String { hookCommand(for: .claudeCode) }
    public static func hookCommand(executable: String) -> String { hookCommand(executable: executable, agent: .claudeCode) }

    // MARK: Pure settings transforms

    static func isOurs(_ command: String) -> Bool {
        markers.contains(where: command.contains) || command.contains(legacyHookMarker)
    }

    /// Returns `settings` with our hook present exactly once under the
    /// agent's event. Existing hooks that are not ours are preserved in
    /// place; stale copies of ours (an older app path) are replaced.
    /// Idempotent.
    public static func mergeHook(into settings: [String: Any], command: String, agent: CodingAgent = .claudeCode) -> [String: Any] {
        var out = settings
        var hooks = (out["hooks"] as? [String: Any]) ?? [:]
        var groups = (hooks[agent.eventKey] as? [[String: Any]]) ?? []

        groups = groups.compactMap { group in
            var g = group
            let inner = (g["hooks"] as? [[String: Any]]) ?? []
            let kept = inner.filter { !isOurs(($0["command"] as? String) ?? "") }
            if kept.isEmpty && !inner.isEmpty { return nil }   // group held only ours
            g["hooks"] = kept
            return g
        }
        groups.append(agent.group([agent.entry(command: command)]))

        hooks[agent.eventKey] = groups
        out["hooks"] = hooks
        return out
    }

    /// Returns `settings` without any of our hooks under the agent's event;
    /// drops the event key (and `hooks`) when nothing else remains.
    public static func removeHook(from settings: [String: Any], agent: CodingAgent = .claudeCode) -> [String: Any] {
        var out = settings
        guard var hooks = out["hooks"] as? [String: Any],
              let groups = hooks[agent.eventKey] as? [[String: Any]] else { return out }
        let remaining = groups.compactMap { group -> [String: Any]? in
            var g = group
            let kept = ((g["hooks"] as? [[String: Any]]) ?? []).filter { !isOurs(($0["command"] as? String) ?? "") }
            if kept.isEmpty { return nil }
            g["hooks"] = kept
            return g
        }
        if remaining.isEmpty { hooks.removeValue(forKey: agent.eventKey) } else { hooks[agent.eventKey] = remaining }
        if hooks.isEmpty { out.removeValue(forKey: "hooks") } else { out["hooks"] = hooks }
        return out
    }

    /// The command of our installed hook under the agent's event, if any.
    public static func installedHookCommand(in settings: [String: Any], agent: CodingAgent = .claudeCode) -> String? {
        guard let hooks = settings["hooks"] as? [String: Any],
              let groups = hooks[agent.eventKey] as? [[String: Any]] else { return nil }
        for group in groups {
            for h in (group["hooks"] as? [[String: Any]]) ?? [] {
                if let c = h["command"] as? String, isOurs(c) { return c }
            }
        }
        return nil
    }

    // Claude Code names kept for existing callers and tests.
    public static func mergeStopHook(into settings: [String: Any], command: String) -> [String: Any] { mergeHook(into: settings, command: command, agent: .claudeCode) }
    public static func removeStopHook(from settings: [String: Any]) -> [String: Any] { removeHook(from: settings, agent: .claudeCode) }
    public static func installedHookCommand(in settings: [String: Any]) -> String? { installedHookCommand(in: settings, agent: .claudeCode) }

    /// True when the text tells an agent to broadcast on its own (the
    /// prompt-driven setup that predates hooks).
    public static func mentionsBroadcastInstruction(_ text: String) -> Bool {
        text.contains("speaker_broadcast.json") || text.contains("home-speaker-broadcast") || text.contains("speaker-broadcast")
    }

    // MARK: Status

    public enum HookStatus: Equatable {
        case notInstalled
        case installed
        /// Installed, but pointing at a path that is not this app (an older
        /// location, or the 1.x python script).
        case stale(String)
    }

    /// Everything Settings needs to describe one agent without guessing.
    public struct AgentStatus: Equatable {
        public var agent: CodingAgent
        /// The agent itself exists on this Mac.
        public var isInstalled: Bool
        public var hook: HookStatus
        /// An instruction file already tells the agent to broadcast itself.
        public var configuredByInstruction: Bool

        /// Announcements will happen one way or another.
        public var isConfigured: Bool { hook == .installed || configuredByInstruction }
    }

    public func status(of agent: CodingAgent) -> AgentStatus {
        let installed = agent.installMarkers(home: home).contains { fileManager.fileExists(atPath: $0.path) }
        let hook: HookStatus
        if let cmd = Self.installedHookCommand(in: readSettings(agent), agent: agent) {
            hook = cmd == hookCommand(for: agent) ? .installed : .stale(cmd)
        } else {
            hook = .notInstalled
        }
        let byInstruction = agent.instructionFiles(home: home).contains { url in
            (try? String(contentsOf: url, encoding: .utf8)).map(Self.mentionsBroadcastInstruction) ?? false
        }
        return AgentStatus(agent: agent, isInstalled: installed, hook: hook, configuredByInstruction: byInstruction)
    }

    /// Appends the broadcast instruction to the agent's instruction file,
    /// creating it if needed. No-op when the file already has it.
    public func addBroadcastInstruction(for agent: CodingAgent) throws {
        let url = agent.primaryInstructionFile(home: home)
        let existing = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        guard !Self.mentionsBroadcastInstruction(existing) else { return }
        let dir = url.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: dir.path) {
            try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        var text = existing
        if !text.isEmpty && !text.hasSuffix("\n") { text += "\n" }
        text += CodingAgent.broadcastInstruction + "\n"
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    public func hookStatus(for agent: CodingAgent = .claudeCode) -> HookStatus { status(of: agent).hook }
    public func hookStatus() -> HookStatus { hookStatus(for: .claudeCode) }
    public func isClaudeCodeHookInstalled() -> Bool { hookStatus() == .installed }

    public func installHook(for agent: CodingAgent) throws {
        try writeSettings(Self.mergeHook(into: readSettings(agent), command: hookCommand(for: agent), agent: agent), agent)
    }

    public func removeHook(for agent: CodingAgent) throws {
        try writeSettings(Self.removeHook(from: readSettings(agent), agent: agent), agent)
    }

    public func installClaudeCodeHook() throws { try installHook(for: .claudeCode) }
    public func removeClaudeCodeHook() throws { try removeHook(for: .claudeCode) }

    /// Called on every launch: if the user moved the app (Downloads ->
    /// Applications), point every installed hook at the new location.
    public func repairHookIfMoved() {
        for agent in CodingAgent.allCases where agent.supportsHook {
            if case .stale = hookStatus(for: agent) { try? installHook(for: agent) }
        }
    }

    private func readSettings(_ agent: CodingAgent) -> [String: Any] {
        guard let data = try? Data(contentsOf: agent.settingsURL(home: home)),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        return json
    }

    private func writeSettings(_ settings: [String: Any], _ agent: CodingAgent) throws {
        let url = agent.settingsURL(home: home)
        let dir = url.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: dir.path) {
            try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        let data = try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: url, options: .atomic)
    }

    // MARK: Legacy 1.x launch agent

    /// The 1.x releases wrote a LaunchAgent for an external python daemon
    /// that this app no longer uses. Detect it so Settings can offer cleanup.
    public static let legacyLaunchAgentLabel = "com.james.chat-monitor"

    public var legacyLaunchAgentURL: URL {
        home.appendingPathComponent("Library/LaunchAgents/\(Self.legacyLaunchAgentLabel).plist")
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
