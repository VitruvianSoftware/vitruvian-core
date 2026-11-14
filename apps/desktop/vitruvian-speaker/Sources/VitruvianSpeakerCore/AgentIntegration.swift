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

/// The coding agents Vitruvian Speaker can announce for. Each one has a hooks
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
        case .antigravity: return "~/.gemini/config/plugins/vitruvian-speaker"
        case .opencode: return "~/.config/opencode/plugins/vitruvian-speaker.ts"
        }
    }

    /// One sentence on what installing writes and what removing takes away.
    public var hookFootnote: String {
        switch self {
        case .claudeCode:
            return "Installs the vitruvian-speaker plugin in Claude Code (skill, Stop hook, and speaker-broadcast command), falling back to ~/.claude/settings.json if the claude CLI is unavailable."
        case .antigravity:
            return "Installs the vitruvian-speaker plugin in ~/.gemini/config/plugins/vitruvian-speaker (plugin.json, hooks.json, skills/vitruvian-speaker/SKILL.md, and bin/speaker-broadcast, which the skill runs by its full path). Remove deletes that folder only."
        case .opencode:
            return "Writes ~/.config/opencode/plugins/vitruvian-speaker.ts and ~/.config/opencode/skills/vitruvian-speaker (SKILL.md and bin/speaker-broadcast, which the skill runs by its full path), running Vitruvian Speaker when a session goes idle."
        }
    }

    /// What the hook is called in that agent's own words.
    /// True when the agent itself puts an installed plugin's `bin/` folder on
    /// the PATH of the shell it runs commands in, so a skill may run a
    /// command the plugin ships by its bare name. Claude Code does; neither
    /// Antigravity nor OpenCode does, so their skills name the command by
    /// its absolute path (`AgentPlugins.skillCommand`).
    public var putsPluginBinOnPATH: Bool {
        switch self {
        case .claudeCode: return true
        case .antigravity, .opencode: return false
        }
    }

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
    - Announce top-level replies aloud with `speaker-broadcast "<summary>"` (never run `speaker-broadcast` from a background subagent or a delegated `claude -p` helper). Run `speaker-broadcast --on`, `--off`, or `--set-target <room>` to change settings, and `speaker-broadcast --help` for the rest.
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
    private let claudeCLI: ClaudeCLIRunner
    public let dataFolder: URL

    /// Folder containing Speaker's generated local Claude Code directory marketplace.
    public var claudeMarketplaceDirectory: URL {
        dataFolder.appendingPathComponent("claude-marketplace", isDirectory: true)
    }

    public static func defaultDataFolder(home: URL, executablePath: String) -> URL {
        if let folders = VitruvianSpeakerProfile.extensionFolders(program: URL(fileURLWithPath: executablePath)) {
            return folders.data
        }
        return home.appendingPathComponent("Library/Application Support/Vitruvian Speaker", isDirectory: true)
    }

    /// `executablePath` is the Vitruvian Speaker program the hooks will run. A
    /// process other than the app (the Vitruvian tool's `bin/tool`) must pass
    /// the Vitruvian Speaker it located: the default is whatever is running, and a
    /// hook pointed at another program would never speak. An empty path
    /// gives an integration that can read the agents' state and clean up,
    /// but never install a hook (`installHook` refuses it).
    /// Non-live `home` defaults `claudeCLI` to `.scopedToHome(home)` so unit
    /// tests using a scratch directory never touch the real `~/.claude`.
    public init(
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        executablePath: String = AgentIntegration.runningExecutable(),
        bootout: @escaping @Sendable (String) -> Void = AgentIntegration.launchctlBootout,
        claudeCLI: ClaudeCLIRunner? = nil,
        dataFolder: URL? = nil
    ) {
        self.home = home
        self.executablePath = executablePath
        self.bootout = bootout
        if let claudeCLI {
            self.claudeCLI = claudeCLI
        } else if home.standardizedFileURL == FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL {
            self.claudeCLI = .live(home: home)
        } else {
            self.claudeCLI = .scopedToHome(home)
        }
        self.dataFolder = dataFolder ?? Self.defaultDataFolder(home: home, executablePath: executablePath)
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
    /// `.build/debug/VitruvianSpeaker` would otherwise be written as a relative
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

    /// The program's file name every Vitruvian Speaker build has: the app bundle's
    /// `Contents/MacOS/VitruvianSpeaker`, SwiftPM's `.build/*/VitruvianSpeaker`.
    public static let programName = "VitruvianSpeaker"

    /// The Vitruvian extension's tool id. Its program is
    /// `…/Tools/<extensionToolID>/bin/tool`.
    public static let extensionToolID = "dev.vitruvian.speaker"

    /// True when `path` is a Vitruvian Speaker program, the only thing a hook may
    /// run: a copy of the app's program, or the extension's.
    public static func isVitruvianSpeakerProgram(_ path: String) -> Bool {
        isAppProgram(path) || isExtensionProgram(path)
    }

    /// True when `path` is a copy of the app's program, wherever it is.
    public static func isAppProgram(_ path: String) -> Bool {
        URL(fileURLWithPath: path).lastPathComponent == programName
    }

    /// True when `path` is the extension's program, the whole shape
    /// `/…/Tools/dev.vitruvian.speaker/bin/tool`. Any other tool's
    /// `bin/tool` is not Vitruvian Speaker.
    public static func isExtensionProgram(_ path: String) -> Bool {
        guard path.hasPrefix("/"),
              let folders = VitruvianSpeakerProfile.extensionFolders(program: URL(fileURLWithPath: path)) else { return false }
        return folders.tool.lastPathComponent == extensionToolID
    }

    public enum IntegrationError: Error, Equatable, LocalizedError {
        /// The hook would run something that is not Vitruvian Speaker.
        case notVitruvianSpeaker(String)
        case corruptSettingsFile(String)
        case claudePluginCommandFailed(String)

        public var errorDescription: String? {
            switch self {
            case .notVitruvianSpeaker(let path):
                return "\(path) is not the Vitruvian Speaker app, so a hook pointing at it would never speak. Install the hook from Vitruvian Speaker itself."
            case .corruptSettingsFile(let path):
                return "Refusing to modify corrupt settings file: \(path)"
            case .claudePluginCommandFailed(let message):
                return "Claude plugin setup failed: \(message)"
            }
        }
    }

    public typealias AgentIntegrationError = IntegrationError

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
        text.contains("speaker_broadcast.json")
            || text.contains("vitruvian-speaker-broadcast")
            || text.contains("home-speaker-broadcast")
            || text.contains("speaker-broadcast")
    }

    /// True when a single line is a legacy Vitruvian/Home Speaker broadcast
    /// instruction that should be migrated in-place to `broadcastInstruction`.
    public static func isLegacyBroadcastInstructionLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != CodingAgent.broadcastInstruction else { return false }
        if trimmed.contains("vitruvian-speaker-broadcast") || trimmed.contains("home-speaker-broadcast") {
            return true
        }
        return trimmed.contains("speaker_broadcast.json") && trimmed.contains("speaker-broadcast")
    }

    /// True when a line was written by Vitruvian/Home Speaker's instruction
    /// installer (current or any historical wording). Custom user lines such as
    /// `"Use speaker-broadcast."` do not match.
    public static func isManagedBroadcastInstructionLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        if trimmed == CodingAgent.broadcastInstruction || isLegacyBroadcastInstructionLine(line) {
            return true
        }
        return trimmed.hasPrefix("- Announce top-level replies aloud with `speaker-broadcast")
    }

    /// Replaces legacy broadcast instruction line(s) in `text` with
    /// `CodingAgent.broadcastInstruction` when stale wording is present;
    /// returns `nil` if no legacy line needed updating.
    public static func migratingBroadcastInstruction(in text: String) -> String? {
        let endsWithNewline = text.hasSuffix("\n")
        let rawLines = text.components(separatedBy: "\n")
        let lines = (endsWithNewline && rawLines.last == "") ? Array(rawLines.dropLast()) : rawLines

        var replaced = false
        var didChange = false
        var out: [String] = []
        out.reserveCapacity(lines.count)

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed == CodingAgent.broadcastInstruction {
                if !replaced {
                    out.append(line)
                    replaced = true
                } else {
                    didChange = true
                }
            } else if isManagedBroadcastInstructionLine(line) {
                didChange = true
                if !replaced {
                    out.append(CodingAgent.broadcastInstruction)
                    replaced = true
                }
            } else {
                out.append(line)
            }
        }

        guard didChange else { return nil }
        return out.joined(separator: "\n") + (endsWithNewline || !out.isEmpty ? "\n" : "")
    }

    /// Removes Speaker-managed broadcast instruction line(s) (current and all
    /// historical wordings) from `text`, preserving user-written content.
    /// Returns `nil` when nothing needed removing.
    public static func removingBroadcastInstruction(from text: String) -> String? {
        let endsWithNewline = text.hasSuffix("\n")
        let rawLines = text.components(separatedBy: "\n")
        let lines = (endsWithNewline && rawLines.last == "") ? Array(rawLines.dropLast()) : rawLines

        var out: [String] = []
        out.reserveCapacity(lines.count)
        var didChange = false

        for line in lines {
            if isManagedBroadcastInstructionLine(line) {
                didChange = true
            } else {
                out.append(line)
            }
        }

        guard didChange else { return nil }
        if out.allSatisfy({ $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            return ""
        }
        return out.joined(separator: "\n") + (endsWithNewline || !out.isEmpty ? "\n" : "")
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
        /// The program the agent's Vitruvian Speaker hook runs, whichever program
        /// that is (this one, another copy of the app, the extension's).
        /// Nil when no Vitruvian Speaker hook is installed.
        public var hookProgram: String?
        /// True when Claude Code uses `~/.claude/settings.json` directly because
        /// the `claude` CLI is unavailable to install the unified plugin.
        public var usingSettingsFallback: Bool

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
            hookProgram: String? = nil,
            usingSettingsFallback: Bool = false
        ) {
            self.agent = agent
            self.isInstalled = isInstalled
            self.hook = hook
            self.configuredByInstruction = configuredByInstruction
            self.rivalHook = rivalHook
            self.hookProgram = hookProgram
            self.usingSettingsFallback = usingSettingsFallback
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
        let fallback = agent == .claudeCode && claudePluginMarketplaceRoot() == nil && command != nil
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
            hookProgram: command.map(Self.program(ofHookCommand:)),
            usingSettingsFallback: fallback)
    }

    /// Appends the broadcast instruction to the agent's instruction file,
    /// creating it if needed, or updates a legacy instruction line in-place.
    /// No-op when the file already mentions broadcasting with current text.
    public func addBroadcastInstruction(for agent: CodingAgent) throws {
        let url = agent.primaryInstructionFile(home: home)
        let existing = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        if let migrated = Self.migratingBroadcastInstruction(in: existing) {
            try migrated.write(to: url, atomically: true, encoding: .utf8)
            return
        }
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

    /// Updates or removes Speaker-managed broadcast instruction lines in existing
    /// agent instruction files under `home`. When an agent carries `SKILL.md`
    /// inside its plugin (not on Claude's `settings.json` fallback), Speaker's
    /// managed line is removed cleanly so there is one source of instructions.
    /// Never creates new files or removes custom wording.
    public func migrateBroadcastInstructions() {
        let claudeFallback = status(of: .claudeCode).usingSettingsFallback
        var seen: Set<URL> = []
        for agent in CodingAgent.allCases {
            let keepFallbackLine = (agent == .claudeCode && claudeFallback)
            for url in agent.instructionFiles(home: home) where seen.insert(url.standardizedFileURL).inserted {
                guard fileManager.fileExists(atPath: url.path),
                      let text = try? String(contentsOf: url, encoding: .utf8) else {
                    continue
                }
                let updated = keepFallbackLine
                    ? Self.migratingBroadcastInstruction(in: text)
                    : Self.removingBroadcastInstruction(from: text)
                guard let updated else { continue }
                try? updated.write(to: url, atomically: true, encoding: .utf8)
            }
        }
    }

    private func stripBroadcastInstructions(for agent: CodingAgent) {
        for url in agent.instructionFiles(home: home) {
            guard fileManager.fileExists(atPath: url.path),
                  let text = try? String(contentsOf: url, encoding: .utf8),
                  let updated = Self.removingBroadcastInstruction(from: text) else {
                continue
            }
            try? updated.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    public func hookStatus(for agent: CodingAgent = .claudeCode) -> HookStatus { status(of: agent).hook }
    public func hookStatus() -> HookStatus { hookStatus(for: .claudeCode) }
    public func isClaudeCodeHookInstalled() -> Bool { hookStatus() == .installed }
    public func installClaudeHook() throws { try installHook(for: .claudeCode) }

    public func installHook(for agent: CodingAgent) throws {
        guard Self.isVitruvianSpeakerProgram(executablePath) else { throw IntegrationError.notVitruvianSpeaker(executablePath) }
        switch agent {
        case .claudeCode:
            if claudeCLI.isAvailable {
                let files = try AgentPlugins.claudeMarketplaceFiles(
                    program: executablePath,
                    hookCommand: hookCommand(for: agent)
                )
                for file in files {
                    _ = try writeFileIfChanged(
                        at: claudeMarketplaceDirectory.appendingPathComponent(file.relativePath),
                        data: file.data,
                        isExecutable: file.isExecutable
                    )
                }
                let marketplaceMatches = claudePluginMarketplaceLocation()?.standardizedFileURL.path
                    == claudeMarketplaceDirectory.standardizedFileURL.path
                if !(claudePluginInstalled() && marketplaceMatches) {
                    if claudePluginInstalled() || claudePluginMarketplaceLocation() != nil {
                        _ = try? claudeCLI.run(["plugin", "uninstall", AgentPlugins.claudePluginID])
                        _ = try? claudeCLI.run(["plugin", "marketplace", "remove", AgentPlugins.claudeMarketplaceName])
                    }
                    let addResult = try claudeCLI.run(["plugin", "marketplace", "add", claudeMarketplaceDirectory.path])
                    guard addResult.exitCode == 0 else {
                        throw IntegrationError.claudePluginCommandFailed(
                            Self.claudeFailureMessage(command: "plugin marketplace add", result: addResult)
                        )
                    }
                    let installResult = try claudeCLI.run(["plugin", "install", AgentPlugins.claudePluginID])
                    guard installResult.exitCode == 0 else {
                        throw IntegrationError.claudePluginCommandFailed(
                            Self.claudeFailureMessage(command: "plugin install", result: installResult)
                        )
                    }
                }
                // Remove Speaker's old Stop hook from ~/.claude/settings.json once the plugin
                // is installed so replies are never announced twice.
                if let settings = try? readSettings(.claudeCode),
                   Self.installedHookCommand(in: settings, agent: .claudeCode) != nil {
                    try writeSettings(Self.removeHook(from: settings, agent: .claudeCode), .claudeCode)
                }
                stripBroadcastInstructions(for: .claudeCode)
            } else {
                try writeSettings(Self.mergeHook(into: try readSettings(agent), command: hookCommand(for: agent), agent: agent), agent)
            }
        case .antigravity:
            let folder = agent.settingsURL(home: home)
            for file in try antigravityFiles() {
                _ = try writeFileIfChanged(at: folder.appendingPathComponent(file.relativePath), data: file.data, isExecutable: file.isExecutable)
            }
            stripBroadcastInstructions(for: .antigravity)
        case .opencode:
            _ = try writeFileIfChanged(
                at: agent.settingsURL(home: home),
                data: Data(AgentPlugins.openCodePlugin(program: executablePath).utf8)
            )
            for file in AgentPlugins.openCodeSkillFiles(program: executablePath, home: home) {
                _ = try writeFileIfChanged(at: home.appendingPathComponent(file.relativePath), data: file.data, isExecutable: file.isExecutable)
            }
            stripBroadcastInstructions(for: .opencode)
        }
    }

    public func removeHook(for agent: CodingAgent) throws {
        switch agent {
        case .claudeCode:
            let wasPluginInstalled = claudePluginInstalled()
            let hadMarketplace = claudePluginMarketplaceLocation() != nil
            if (wasPluginInstalled || hadMarketplace) && claudeCLI.isAvailable {
                if wasPluginInstalled {
                    let res = try claudeCLI.run(["plugin", "uninstall", AgentPlugins.claudePluginID])
                    if res.exitCode != 0 && claudePluginInstalled() {
                        throw IntegrationError.claudePluginCommandFailed(
                            Self.claudeFailureMessage(command: "plugin uninstall", result: res)
                        )
                    }
                }
                if hadMarketplace {
                    let res = try claudeCLI.run(["plugin", "marketplace", "remove", AgentPlugins.claudeMarketplaceName])
                    if res.exitCode != 0 && claudePluginMarketplaceLocation() != nil {
                        throw IntegrationError.claudePluginCommandFailed(
                            Self.claudeFailureMessage(command: "plugin marketplace remove", result: res)
                        )
                    }
                }
            }
            if fileManager.fileExists(atPath: claudeMarketplaceDirectory.path) {
                try fileManager.removeItem(at: claudeMarketplaceDirectory)
            }
            if let settings = try? readSettings(.claudeCode),
               Self.installedHookCommand(in: settings, agent: .claudeCode) != nil {
                try writeSettings(Self.removeHook(from: settings, agent: .claudeCode), .claudeCode)
            }
        case .antigravity:
            // Only a plugin this app wrote is removed; a folder of the same
            // name someone else put there is left alone.
            let url = agent.settingsURL(home: home)
            guard installedCommand(agent) != nil else { return }
            try fileManager.removeItem(at: url)
        case .opencode:
            // Only a plugin this app wrote is removed; a file of the same
            // name someone else put there is left alone.
            let url = agent.settingsURL(home: home)
            guard installedCommand(agent) != nil else { return }
            try fileManager.removeItem(at: url)
            let skillFolder = home.appendingPathComponent(AgentPlugins.openCodeSkillFolderRelativePath, isDirectory: true)
            if fileManager.fileExists(atPath: skillFolder.path) {
                try? fileManager.removeItem(at: skillFolder)
            }
        }
    }

    /// The command of the agent's installed Vitruvian Speaker hook, wherever that
    /// agent keeps it; nil when there is none.
    private func installedCommand(_ agent: CodingAgent) -> String? {
        switch agent {
        case .claudeCode:
            if let root = claudePluginMarketplaceRoot() {
                let hooksFile = root.appendingPathComponent("plugins/\(AgentPlugins.name)/hooks/hooks.json")
                if let data = try? Data(contentsOf: hooksFile),
                   let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let cmd = Self.installedHookCommand(in: dict, agent: .claudeCode) {
                    return cmd
                }
            }
            return (try? readSettings(agent)).flatMap { Self.installedHookCommand(in: $0, agent: agent) }
        case .antigravity:
            let file = agent.settingsURL(home: home).appendingPathComponent(AgentPlugins.antigravityHooksFile)
            return (try? Data(contentsOf: file)).flatMap(AgentPlugins.antigravityCommand(inHooks:))
        case .opencode:
            return (try? String(contentsOf: agent.settingsURL(home: home), encoding: .utf8))
                .flatMap(AgentPlugins.openCodeCommand(inPlugin:))
        }
    }

    /// True when the agent's plugin files are exactly what this app would
    /// write now, so an older plugin (or missing skill / leftover settings
    /// hook) shows as needing an update.
    private func pluginIsCurrent(_ agent: CodingAgent) -> Bool {
        switch agent {
        case .claudeCode:
            if let root = claudePluginMarketplaceRoot() {
                guard root.standardizedFileURL.path == claudeMarketplaceDirectory.standardizedFileURL.path,
                      let files = try? AgentPlugins.claudeMarketplaceFiles(
                          program: executablePath,
                          hookCommand: hookCommand(for: .claudeCode)
                      ) else {
                    return false
                }
                guard files.allSatisfy({ isCurrent($0, in: claudeMarketplaceDirectory) }) else { return false }
                let leftoverSettingsHook = (try? readSettings(.claudeCode))
                    .flatMap { Self.installedHookCommand(in: $0, agent: .claudeCode) }
                return leftoverSettingsHook == nil
            }
            return !claudeCLI.isAvailable
        case .antigravity:
            let folder = agent.settingsURL(home: home)
            guard let files = try? antigravityFiles() else { return false }
            return files.allSatisfy { isCurrent($0, in: folder) }
        case .opencode:
            let pluginMatches = (try? Data(contentsOf: agent.settingsURL(home: home)))
                == Data(AgentPlugins.openCodePlugin(program: executablePath).utf8)
            return pluginMatches
                && AgentPlugins.openCodeSkillFiles(program: executablePath, home: home).allSatisfy { isCurrent($0, in: home) }
        }
    }

    /// The Antigravity plugin this app would write now.
    func antigravityFiles() throws -> [AgentPlugins.GeneratedPluginFile] {
        try AgentPlugins.antigravityFiles(
            command: hookCommand(for: .antigravity),
            program: executablePath,
            folder: CodingAgent.antigravity.settingsURL(home: home)
        )
    }

    /// True when `file` is on disk under `folder` with exactly these bytes
    /// and, if it should be, executable.
    private func isCurrent(_ file: AgentPlugins.GeneratedPluginFile, in folder: URL) -> Bool {
        let url = folder.appendingPathComponent(file.relativePath)
        guard (try? Data(contentsOf: url)) == file.data else { return false }
        return !file.isExecutable || fileManager.isExecutableFile(atPath: url.path)
    }

    // MARK: Claude Code plugin files & byte-preserving writer

    private var claudePluginsDirectory: URL {
        home.appendingPathComponent(".claude/plugins", isDirectory: true)
    }

    private func readJSONObject(at url: URL) -> [String: Any]? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    private func claudePluginEnabledInSettings() -> Bool {
        guard let settings = try? readSettings(.claudeCode),
              let enabled = settings["enabledPlugins"] as? [String: Any],
              let value = enabled[AgentPlugins.claudePluginID] as? Bool else {
            return true
        }
        return value
    }

    private func claudePluginInstalled() -> Bool {
        guard claudePluginEnabledInSettings(),
              let installed = readJSONObject(at: claudePluginsDirectory.appendingPathComponent("installed_plugins.json")),
              let plugins = installed["plugins"] as? [String: Any],
              let entries = plugins[AgentPlugins.claudePluginID] as? [[String: Any]] else {
            return false
        }
        return !entries.isEmpty
    }

    private func claudePluginMarketplaceLocation() -> URL? {
        guard let known = readJSONObject(at: claudePluginsDirectory.appendingPathComponent("known_marketplaces.json")),
              let entry = known[AgentPlugins.claudeMarketplaceName] as? [String: Any] else {
            return nil
        }
        if let installLocation = entry["installLocation"] as? String, !installLocation.isEmpty {
            return URL(fileURLWithPath: installLocation, isDirectory: true)
        }
        if let source = entry["source"] as? [String: Any],
           let path = source["path"] as? String, !path.isEmpty {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        return nil
    }

    private func claudePluginMarketplaceRoot() -> URL? {
        guard claudePluginInstalled() else { return nil }
        let root = claudePluginMarketplaceLocation() ?? claudeMarketplaceDirectory
        let hooksFile = root.appendingPathComponent("plugins/\(AgentPlugins.name)/hooks/hooks.json")
        guard fileManager.fileExists(atPath: hooksFile.path) else { return nil }
        return root
    }

    private static func claudeFailureMessage(command: String, result: ClaudeCLI.CommandResult) -> String {
        let stderr = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        let stdout = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        let detail = stderr.isEmpty ? stdout : stderr
        if detail.isEmpty {
            return "`claude \(command)` exited with status \(result.exitCode)"
        }
        return "`claude \(command)` exited with status \(result.exitCode): \(detail)"
    }

    /// Writes `data` to `url` only when its bytes or executable bit differ.
    @discardableResult
    public func writeFileIfChanged(at url: URL, data: Data, isExecutable: Bool = false) throws -> Bool {
        let bytesMatch = (try? Data(contentsOf: url)) == data
        let execMatches = !isExecutable || fileManager.isExecutableFile(atPath: url.path)
        if bytesMatch && execMatches {
            return false
        }
        let dir = url.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: dir.path) {
            try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        if !bytesMatch {
            try data.write(to: url, options: .atomic)
        }
        if isExecutable {
            try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        }
        return true
    }

    public func installClaudeCodeHook() throws { try installHook(for: .claudeCode) }
    public func removeClaudeCodeHook() throws { try removeHook(for: .claudeCode) }

    /// Turns off a rival hook file by renaming it, so the reply stops being
    /// spoken twice. Reversible: the original is left beside it.
    public func disableRivalHook(for agent: CodingAgent) throws {
        guard let url = status(of: agent).rivalHook else { return }
        let disabled = url.deletingLastPathComponent()
            .appendingPathComponent(url.lastPathComponent + ".disabled-by-vitruvian-speaker")
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
        choice: VitruvianSpeakerProfile.Door?
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

    /// Reconciles every coding agent's unified plugin on start-up for the
    /// active door: installs missing plugins (when `installMissing`), updates
    /// stale/moved ones in place, removes plugins whose agent toggle is off,
    /// and strips redundant instruction lines when the plugin carries `SKILL.md`.
    public func syncPlugins(
        config: SpeakerConfig,
        installMissing: Bool,
        extensionProgramExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) },
        choice: VitruvianSpeakerProfile.Door?
    ) {
        guard Self.isVitruvianSpeakerProgram(executablePath),
              !OtherDoorPresence.isInTrash(executablePath),
              !OtherDoorPresence.isOnTemporaryVolume(executablePath) else { return }
        for agent in CodingAgent.allCases where agent.supportsHook {
            let st = status(of: agent)
            guard ownsOrMayTake(st, extensionProgramExists: extensionProgramExists, choice: choice) else { continue }
            if !config.announces(agent) {
                if st.hook != .notInstalled {
                    try? removeHook(for: agent)
                }
                continue
            }
            switch st.hook {
            case .installed:
                if !st.usingSettingsFallback {
                    stripBroadcastInstructions(for: agent)
                }
            case .stale:
                try? installHook(for: agent)
            case .notInstalled:
                if installMissing && st.isInstalled {
                    try? installHook(for: agent)
                }
            }
        }
    }

    private func ownsOrMayTake(
        _ status: AgentStatus,
        extensionProgramExists: (String) -> Bool,
        choice: VitruvianSpeakerProfile.Door?
    ) -> Bool {
        guard let program = status.hookProgram, Self.isVitruvianSpeakerProgram(program) else {
            return true
        }
        if Self.isAppProgram(executablePath), Self.isExtensionProgram(program),
           extensionProgramExists(program), choice != .app {
            return false
        }
        if Self.isExtensionProgram(executablePath), Self.isAppProgram(program),
           !OtherDoorPresence.isInTrash(program),
           !OtherDoorPresence.isOnTemporaryVolume(program),
           fileManager.fileExists(atPath: program),
           choice != .extension {
            return false
        }
        return true
    }

    private func readSettings(_ agent: CodingAgent) throws -> [String: Any] {
        let url = agent.settingsURL(home: home)
        guard fileManager.fileExists(atPath: url.path) else { return [:] }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw IntegrationError.corruptSettingsFile(url.path)
        }
        let trimmed = data.drop(while: { $0 == 0x20 || $0 == 0x09 || $0 == 0x0a || $0 == 0x0d })
        if trimmed.isEmpty { return [:] }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw IntegrationError.corruptSettingsFile(url.path)
        }
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

public typealias AgentIntegrationError = AgentIntegration.IntegrationError

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
