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
    case opencode

    public var displayName: String {
        switch self {
        case .claudeCode: return "Claude Code"
        case .antigravity: return "Antigravity"
        case .opencode: return "OpenCode"
        }
    }

    /// Whether this app can install a deterministic end-of-turn hook for
    /// the agent. All three can: Claude Code through a `Stop` hook in its
    /// settings, Antigravity (agy 1.4) through a plugin whose `hooks.json`
    /// has a `Stop` hook, OpenCode (2.x) through a plugin file that answers
    /// `session.idle`.
    public var supportsHook: Bool { true }

    /// The CLI flag this binary answers to for the agent's hook.
    public var hookArgument: String {
        switch self {
        case .claudeCode: return ClaudeStopHook.argument
        case .antigravity: return AntigravityHook.argument
        case .opencode: return OpenCodeHook.argument
        }
    }

    /// Hook event that fires once the agent has finished a turn.
    var eventKey: String { "Stop" }

    /// Where the hook goes, as Settings names it.
    public var hookLocationName: String {
        switch self {
        case .claudeCode: return "~/.claude/settings.json"
        case .antigravity: return "~/.gemini/config/plugins/home-speaker"
        case .opencode: return "~/.config/opencode/plugins/home-speaker.ts"
        }
    }

    /// One sentence on what installing writes and what removing takes away.
    public var hookFootnote: String {
        switch self {
        case .claudeCode:
            return "Adds one entry to the Stop hooks in ~/.claude/settings.json. Other hooks you have are left untouched."
        case .antigravity:
            return "Installs the home-speaker plugin in ~/.gemini/config/plugins/home-speaker (plugin.json and hooks.json); its Stop hook runs HomeSpeaker when a turn ends. Remove deletes that folder only. New Antigravity sessions pick it up."
        case .opencode:
            return "Writes the plugin file ~/.config/opencode/plugins/home-speaker.ts, which runs HomeSpeaker when a session goes idle. Remove deletes that file only. OpenCode loads it the next time it starts."
        }
    }

    /// What the hook is called in that agent's own words.
    public var hookKind: String {
        switch self {
        case .claudeCode: return "hook"
        case .antigravity, .opencode: return "plugin"
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
        case .opencode: return "~/.config/opencode/AGENTS.md"
        }
    }

    /// The line that tells the agent to announce its replies itself. Kept
    /// identical to what the google-home skill documents so existing
    /// setups are recognised.
    public static let broadcastInstruction = """
    - Follow the `home-speaker-broadcast` skill: Accompany top-level conversational responses to the user with a concise spoken broadcast (1-2 sentences) by executing the CLI tool `speaker-broadcast "<summary>"` (never run `speaker-broadcast` from a background subagent or a delegated `claude -p` helper call). Always use the CLI rather than manual `home_mcp` calls with device IDs, because `speaker-broadcast` dynamically resolves the live `default_target` from `~/.gemini/speaker_broadcast.json`, checks quiet hours, and verifies enabled status on every execution without caching state. When the user asks to turn speaker broadcasts on/off or change the target room, update `~/.gemini/speaker_broadcast.json` (or run `speaker-broadcast --set-target <room>`) and confirm.
    """

    /// The file (Claude Code) or folder (Antigravity's plugin) or file
    /// (OpenCode's plugin) the hook lives in.
    public func settingsURL(home: URL) -> URL {
        switch self {
        case .claudeCode: return home.appendingPathComponent(".claude/settings.json")
        case .antigravity: return home.appendingPathComponent(".gemini/config/plugins/\(AgentPlugins.name)")
        case .opencode: return home.appendingPathComponent(".config/opencode/plugins/\(AgentPlugins.name).ts")
        }
    }

    /// Where the agent keeps itself; used to tell "not installed" from
    /// "installed but not hooked" so the user is never told to install
    /// something they don't have.
    func installMarkers(home: URL) -> [URL] {
        switch self {
        case .claudeCode: return [home.appendingPathComponent(".claude")]
        case .antigravity: return [home.appendingPathComponent(".gemini/antigravity-cli"), home.appendingPathComponent(".gemini/antigravity"), home.appendingPathComponent(".gemini/config")]
        case .opencode: return [home.appendingPathComponent(".config/opencode"), home.appendingPathComponent(".local/share/opencode")]
        }
    }

    /// Instruction files the user may already have told the agent to
    /// broadcast from (the prompt-driven way, before hooks existed).
    /// Hook files outside the agent's settings that also speak replies. The
    /// 1.x google-home skill shipped its own `hooks.json`, and Claude Code
    /// loads it: with the app's hook installed too, every reply is announced
    /// twice, because each de-duplicates against its own lock file.
    func rivalHookFiles(home: URL) -> [URL] {
        switch self {
        case .claudeCode:
            return [home.appendingPathComponent(".claude/skills/google-home/hooks/hooks.json")]
        case .antigravity, .opencode:
            return []
        }
    }

    func instructionFiles(home: URL) -> [URL] {
        switch self {
        case .claudeCode: return [home.appendingPathComponent(".claude/CLAUDE.md"), home.appendingPathComponent("CLAUDE.md")]
        case .antigravity: return [home.appendingPathComponent(".gemini/AGENTS.md"), home.appendingPathComponent(".gemini/GEMINI.md")]
        case .opencode: return [home.appendingPathComponent(".config/opencode/AGENTS.md")]
        }
    }

    /// One Claude Code hook entry; it times out in seconds.
    func entry(command: String) -> [String: Any] {
        ["type": "command", "command": command, "timeout": 10]
    }

    /// Wraps entries in a Claude Code hook group.
    func group(_ entries: [[String: Any]]) -> [String: Any] {
        ["hooks": entries]
    }
}

/// Installs the agent hooks. A hook is this very binary run with the
/// agent's flag, so the only thing written into the user's settings is the
/// path to the app they already have.
public struct AgentIntegration {
    public static let shared = AgentIntegration()

    /// Markers every hook entry we write carries, so ours can be found and
    /// replaced without touching hooks the user added themselves.
    static let markers = [ClaudeStopHook.argument, "--antigravity-hook", "--opencode-hook"]
    /// The hook the 1.x releases pointed at; treated as ours for cleanup.
    static let legacyHookMarker = "stop_broadcast.py"

    private let fileManager = FileManager.default
    private let home: URL
    private let executablePath: String
    /// Stops a launchd job by its service target (`gui/<uid>/<label>`).
    /// Injected so tests never stop a job in the live login session.
    private let bootout: @Sendable (String) -> Void

    /// `executablePath` is the HomeSpeaker program the hooks will run. A
    /// process other than the app (the Vitruvian tool's `bin/tool`) must pass
    /// the HomeSpeaker it located: the default is whatever is running, and a
    /// hook pointed at another program would never speak. An empty path
    /// gives an integration that can read the agents' state and clean up,
    /// but never install a hook (`installHook` refuses it).
    public init(
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        executablePath: String = AgentIntegration.runningExecutable(),
        bootout: @escaping @Sendable (String) -> Void = AgentIntegration.launchctlBootout
    ) {
        self.home = home
        self.executablePath = executablePath
        self.bootout = bootout
    }

    /// `launchctl bootout <target>`, waited for. A job that is not loaded
    /// makes launchctl fail, which is fine: the plist is removed regardless.
    public static let launchctlBootout: @Sendable (String) -> Void = { target in
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        proc.arguments = ["bootout", target]
        do {
            try proc.run()
            proc.waitUntilExit()
        } catch {}
    }

    /// The running program as an absolute path: the bundle's executable, else
    /// argv[0] made absolute against the working directory (a bare
    /// `.build/debug/HomeSpeaker` would otherwise be written as a relative
    /// hook that only works from this one folder).
    public static func runningExecutable(
        bundleExecutable: String? = Bundle.main.executablePath,
        argv0: String = CommandLine.arguments.first ?? "",
        currentDirectory: String = FileManager.default.currentDirectoryPath
    ) -> String {
        if let bundleExecutable, !bundleExecutable.isEmpty { return bundleExecutable }
        let url = argv0.hasPrefix("/") ? URL(fileURLWithPath: argv0)
            : URL(fileURLWithPath: currentDirectory).appendingPathComponent(argv0)
        return url.standardizedFileURL.path
    }

    /// The program's file name every HomeSpeaker build has: the app bundle's
    /// `Contents/MacOS/HomeSpeaker`, SwiftPM's `.build/*/HomeSpeaker`.
    public static let programName = "HomeSpeaker"

    /// The Vitruvian extension's tool id. Its program is
    /// `…/Tools/<extensionToolID>/bin/tool`.
    public static let extensionToolID = "dev.vitruvian.homespeaker"

    /// True when `path` is a HomeSpeaker program, the only thing a hook may
    /// run: a copy of the app's program, or the extension's.
    public static func isHomeSpeakerProgram(_ path: String) -> Bool {
        isAppProgram(path) || isExtensionProgram(path)
    }

    /// True when `path` is a copy of the app's program, wherever it is.
    public static func isAppProgram(_ path: String) -> Bool {
        URL(fileURLWithPath: path).lastPathComponent == programName
    }

    /// True when `path` is the extension's program, the whole shape
    /// `/…/Tools/dev.vitruvian.homespeaker/bin/tool`. Any other tool's
    /// `bin/tool` is not HomeSpeaker.
    public static func isExtensionProgram(_ path: String) -> Bool {
        guard path.hasPrefix("/"),
              let folders = HomeSpeakerProfile.extensionFolders(program: URL(fileURLWithPath: path)) else { return false }
        return folders.tool.lastPathComponent == extensionToolID
    }

    public enum IntegrationError: Error, Equatable, LocalizedError {
        /// The hook would run something that is not HomeSpeaker.
        case notHomeSpeaker(String)

        public var errorDescription: String? {
            switch self {
            case .notHomeSpeaker(let path):
                return "\(path) is not the HomeSpeaker app, so a hook pointing at it would never speak. Install the hook from HomeSpeaker itself."
            }
        }
    }

    public var hookExecutablePath: String { executablePath }

    /// The exact command line the agent will run.
    public func hookCommand(for agent: CodingAgent) -> String {
        Self.hookCommand(executable: executablePath, agent: agent)
    }

    public static func hookCommand(executable: String, agent: CodingAgent = .claudeCode) -> String {
        "\"\(executable)\" \(agent.hookArgument)"
    }

    /// The program a hook command runs: the quoted path this integration
    /// writes (`"<program>" --claude-stop-hook`), else the first word (the
    /// 1.x hook's `python3`).
    public static func program(ofHookCommand command: String) -> String {
        let trimmed = command.drop { $0 == " " }
        if trimmed.first == "\"" {
            let rest = trimmed.dropFirst()
            if let close = rest.firstIndex(of: "\"") { return String(rest[..<close]) }
            return String(rest)
        }
        return String(trimmed.prefix { $0 != " " })
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
        /// A second, independent hook file that also speaks replies. With
        /// ours installed as well, every answer is announced twice.
        public var rivalHook: URL?
        /// The program the agent's HomeSpeaker hook runs, whichever program
        /// that is (this one, another copy of the app, the extension's).
        /// Nil when no HomeSpeaker hook is installed.
        public var hookProgram: String?

        /// Announcements will happen one way or another.
        public var isConfigured: Bool { hook == .installed || configuredByInstruction }

        /// True when two hooks would both speak the same reply. Only an
        /// agent this app hooks can be doubled up this way: the rival is a
        /// second hook file, and without ours installed there is one voice.
        public var speaksTwice: Bool { agent.supportsHook && hook == .installed && rivalHook != nil }

        /// The warning Settings shows when `speaksTwice`, naming the file
        /// that also speaks; nil otherwise.
        public var speaksTwiceWarning: String? {
            guard speaksTwice, let rival = rivalHook else { return nil }
            return "Every reply is spoken twice: \(rival.lastPathComponent) in \(rival.deletingLastPathComponent().lastPathComponent) also announces it."
        }

        /// Which of the three shapes the agent's Settings section takes.
        public var section: Section {
            if !isInstalled { return .notInstalled }
            if !agent.supportsHook { return .instructionDriven }
            return .hook
        }

        public init(
            agent: CodingAgent, isInstalled: Bool, hook: HookStatus, configuredByInstruction: Bool, rivalHook: URL?,
            hookProgram: String? = nil
        ) {
            self.agent = agent
            self.isInstalled = isInstalled
            self.hook = hook
            self.configuredByInstruction = configuredByInstruction
            self.rivalHook = rivalHook
            self.hookProgram = hookProgram
        }
    }

    public enum Section: Equatable, Sendable {
        /// The agent is not on this Mac.
        case notInstalled
        /// Driven by a line in its instruction file (no hook support).
        case instructionDriven
        /// Driven by our hook; the "spoken twice" warning lives here.
        case hook
    }

    public func status(of agent: CodingAgent) -> AgentStatus {
        let installed = agent.installMarkers(home: home).contains { fileManager.fileExists(atPath: $0.path) }
        let hook: HookStatus
        let command = installedCommand(agent)
        if let cmd = command {
            hook = cmd == hookCommand(for: agent) && pluginIsCurrent(agent) ? .installed : .stale(cmd)
        } else {
            hook = .notInstalled
        }
        let byInstruction = agent.instructionFiles(home: home).contains { url in
            (try? String(contentsOf: url, encoding: .utf8)).map(Self.mentionsBroadcastInstruction) ?? false
        }
        let rival = agent.rivalHookFiles(home: home).first { url in
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { return false }
            return text.contains("stop_broadcast") || text.contains("speaker-broadcast")
        }
        return AgentStatus(
            agent: agent, isInstalled: installed, hook: hook,
            configuredByInstruction: byInstruction, rivalHook: rival,
            hookProgram: command.map(Self.program(ofHookCommand:)))
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
        guard Self.isHomeSpeakerProgram(executablePath) else { throw IntegrationError.notHomeSpeaker(executablePath) }
        switch agent {
        case .claudeCode:
            try writeSettings(Self.mergeHook(into: readSettings(agent), command: hookCommand(for: agent), agent: agent), agent)
        case .antigravity:
            let folder = agent.settingsURL(home: home)
            try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
            for (name, data) in try AgentPlugins.antigravityFiles(command: hookCommand(for: agent)) {
                try data.write(to: folder.appendingPathComponent(name), options: .atomic)
            }
        case .opencode:
            let file = agent.settingsURL(home: home)
            try fileManager.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(AgentPlugins.openCodePlugin(program: executablePath).utf8).write(to: file, options: .atomic)
        }
    }

    public func removeHook(for agent: CodingAgent) throws {
        switch agent {
        case .claudeCode:
            try writeSettings(Self.removeHook(from: readSettings(agent), agent: agent), agent)
        case .antigravity, .opencode:
            // Only a plugin this app wrote is removed; a file of the same
            // name someone else put there is left alone.
            let url = agent.settingsURL(home: home)
            guard installedCommand(agent) != nil else { return }
            try fileManager.removeItem(at: url)
        }
    }

    /// The command of the agent's installed HomeSpeaker hook, wherever that
    /// agent keeps it; nil when there is none.
    private func installedCommand(_ agent: CodingAgent) -> String? {
        switch agent {
        case .claudeCode:
            return Self.installedHookCommand(in: readSettings(agent), agent: agent)
        case .antigravity:
            let file = agent.settingsURL(home: home).appendingPathComponent(AgentPlugins.antigravityHooksFile)
            return (try? Data(contentsOf: file)).flatMap(AgentPlugins.antigravityCommand(inHooks:))
        case .opencode:
            return (try? String(contentsOf: agent.settingsURL(home: home), encoding: .utf8))
                .flatMap(AgentPlugins.openCodeCommand(inPlugin:))
        }
    }

    /// True when the agent's plugin files are exactly what this app would
    /// write now, so an older plugin shows as one to update. Claude Code's
    /// hook is one line in a shared file: its command says it all.
    private func pluginIsCurrent(_ agent: CodingAgent) -> Bool {
        switch agent {
        case .claudeCode:
            return true
        case .antigravity:
            let folder = agent.settingsURL(home: home)
            guard let files = try? AgentPlugins.antigravityFiles(command: hookCommand(for: agent)) else { return false }
            return files.allSatisfy { name, data in (try? Data(contentsOf: folder.appendingPathComponent(name))) == data }
        case .opencode:
            return (try? String(contentsOf: agent.settingsURL(home: home), encoding: .utf8))
                == AgentPlugins.openCodePlugin(program: executablePath)
        }
    }

    public func installClaudeCodeHook() throws { try installHook(for: .claudeCode) }
    public func removeClaudeCodeHook() throws { try removeHook(for: .claudeCode) }

    /// Turns off a rival hook file by renaming it, so the reply stops being
    /// spoken twice. Reversible: the original is left beside it.
    public func disableRivalHook(for agent: CodingAgent) throws {
        guard let url = status(of: agent).rivalHook else { return }
        let disabled = url.deletingLastPathComponent()
            .appendingPathComponent(url.lastPathComponent + ".disabled-by-homespeaker")
        try? fileManager.removeItem(at: disabled)
        try fileManager.moveItem(at: url, to: disabled)
    }

    /// Called on every launch of the app: if the user moved the app
    /// (Downloads -> Applications), point every installed hook at the new
    /// location.
    ///
    /// A hook is re-pointed at this program when the program it runs does
    /// not exist, is another copy of the app, or is the extension's program
    /// while `choice` names the app. A hook that runs the extension's
    /// existing program is left alone while `choice` is the extension or
    /// nil (nobody has chosen), so the app never takes the hook back from an
    /// extension the person set it up for. `extensionProgramExists` answers
    /// whether the extension's program at a path is there.
    public func repairHookIfMoved(
        extensionProgramExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) },
        choice: HomeSpeakerProfile.Door?
    ) {
        // Only the app repairs, and never from the Trash, a mounted DMG, or a
        // Gatekeeper AppTranslocation mount. From any other program every
        // installed hook looks "moved", and repairing it would point it at
        // that program.
        guard Self.isAppProgram(executablePath),
              !OtherDoorPresence.isInTrash(executablePath),
              !OtherDoorPresence.isOnTemporaryVolume(executablePath) else { return }
        for agent in CodingAgent.allCases where agent.supportsHook {
            let status = status(of: agent)
            guard case .stale = status.hook else { continue }
            if let program = status.hookProgram, Self.isExtensionProgram(program),
               extensionProgramExists(program), choice != .app {
                continue
            }
            try? installHook(for: agent)
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

    /// The launchd service target the legacy agent runs as in this login.
    public static var legacyLaunchAgentTarget: String { "gui/\(getuid())/\(legacyLaunchAgentLabel)" }

    public func removeLegacyLaunchAgent() throws {
        bootout(Self.legacyLaunchAgentTarget)
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
