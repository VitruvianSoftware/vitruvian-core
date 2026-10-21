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

import CryptoKit
import Foundation

/// The Claude Code `Stop` hook, built into the app binary so nothing outside
/// the bundle is needed. Claude Code runs `HomeSpeaker --claude-stop-hook`
/// with the hook payload on stdin; this reads the transcript, picks the last
/// assistant reply of the current turn, and speaks a one-to-two-sentence
/// summary on the default speaker.
///
/// It never blocks Claude Code: every failure path is silent and exits 0.
public enum ClaudeStopHook {
    public static let argument = "--claude-stop-hook"
    /// `HomeSpeaker --announce <text>`: the whole announcement, quiet hours
    /// honoured, in a process of its own. See `run` for why.
    public static let announceArgument = "--announce"

    /// One transcript line, reduced to what the hook cares about.
    public struct Entry: Equatable {
        public var role: String
        public var text: String
        public var isPlainUserPrompt: Bool
        public var mentionsBroadcast: Bool

        public init(role: String, text: String = "", isPlainUserPrompt: Bool = false, mentionsBroadcast: Bool = false) {
            self.role = role
            self.text = text
            self.isPlainUserPrompt = isPlainUserPrompt
            self.mentionsBroadcast = mentionsBroadcast
        }
    }

    /// Parses Claude Code's JSONL transcript. Unknown lines are skipped.
    public static func parseTranscript(_ text: String) -> [Entry] {
        var entries: [Entry] = []
        for line in text.split(separator: "\n") {
            guard let data = line.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let msg = obj["message"] as? [String: Any],
                  let role = msg["role"] as? String else { continue }
            var entry = Entry(role: role)
            if let content = msg["content"] as? String {
                entry.text = content
                entry.isPlainUserPrompt = role == "user" && !content.trimmingCharacters(in: .whitespaces).isEmpty
            } else if let blocks = msg["content"] as? [[String: Any]] {
                var hasText = false
                var hasToolResult = false
                for block in blocks {
                    switch block["type"] as? String {
                    case "text":
                        hasText = true
                        if let t = block["text"] as? String { entry.text = t }
                    case "tool_result":
                        hasToolResult = true
                    case "tool_use":
                        if toolBroadcasts(name: block["name"] as? String ?? "", input: block["input"]) {
                            entry.mentionsBroadcast = true
                        }
                    default: break
                    }
                }
                entry.isPlainUserPrompt = role == "user" && hasText && !hasToolResult
            }
            entries.append(entry)
        }
        return entries
    }

    /// True when this `tool_use` block is the agent actually announcing
    /// something on the speakers — the Home MCP broadcast action, the
    /// `speaker-broadcast` CLI, or `HomeSpeaker --say`.
    ///
    /// It deliberately does NOT fire on the mere presence of those words
    /// anywhere in the tool input. A turn that edits or greps this very file
    /// passes `"speaker-broadcast"` through a shell command as *data*, and a
    /// substring match there made the hook think the reply had already been
    /// spoken, so it said nothing at all.
    static func toolBroadcasts(name: String, input: Any?) -> Bool {
        let lowerName = name.lowercased()
        let text = String(describing: input ?? "")
        // A Home MCP action call counts only when it carries the broadcast trait.
        if lowerName.contains("home_actions") || lowerName.contains("home-actions") {
            return text.contains("AssistantBroadcast")
        }
        if lowerName.contains("speaker_broadcast") || lowerName.contains("speaker-broadcast") {
            return true
        }
        guard let dict = input as? [String: Any],
              let command = dict["command"] as? String else { return false }
        return commandBroadcasts(command)
    }

    /// True when `command` *invokes* a broadcaster, rather than merely
    /// containing its name. The tool name has to sit where a command goes:
    /// start of line, or after `;`, `&`, `|`, a backtick or `$(` — never
    /// inside a quoted string.
    static func commandBroadcasts(_ command: String) -> Bool {
        func invokes(_ tool: String) -> Bool {
            let pattern = "(?:^|[\\n;&|`]|\\$\\()[ \\t]*(?:[\\w./-]*/)?\(tool)\\b"
            return command.range(of: pattern, options: [.regularExpression]) != nil
        }
        if invokes("speaker-broadcast") { return true }
        // The app binary does many things; only --say speaks.
        if invokes("HomeSpeaker") && command.range(of: "(?:^|\\s)--say(?:\\s|$)", options: .regularExpression) != nil {
            return true
        }
        return false
    }

    /// The last assistant text of the current turn (everything after the last
    /// real user prompt), or nil when the turn already spoke through a tool
    /// call — otherwise the answer would be read out twice.
    public static func textToSpeak(entries: [Entry]) -> String? {
        let turnStart = entries.lastIndex(where: { $0.isPlainUserPrompt }) ?? 0
        let turn = entries[turnStart...]
        if turn.contains(where: { $0.role == "assistant" && $0.mentionsBroadcast }) { return nil }
        let last = turn.last(where: { $0.role == "assistant" && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
        return last?.text
    }

    /// Lock-file name for de-duplicating the same spoken text.
    ///
    /// Deliberately identical to the name the 1.x python hook
    /// (`stop_broadcast.py`, shipped inside the google-home skill) uses:
    /// `sha256(spoken)[:16]`, prefixed `claude_broadcast_`. A machine that
    /// still has that skill installed runs BOTH hooks on every Stop, and
    /// sharing the lock is what stops the reply being spoken twice.
    public static func dedupeKey(for spoken: String) -> String {
        let digest = SHA256.hash(data: Data(spoken.utf8)).map { String(format: "%02x", $0) }.joined()
        return "claude_broadcast_\(digest.prefix(16)).lock"
    }

    /// Directory the lock lives in. `/tmp` rather than the process's own
    /// TMPDIR, because the python hook writes there and a per-process
    /// temporary directory would never collide with it.
    public static let lockDirectory = URL(fileURLWithPath: "/tmp")

    /// True when the same text was spoken within `window` seconds; records
    /// this attempt either way.
    public static func isDuplicate(spoken: String, window: TimeInterval = 10, directory: URL = ClaudeStopHook.lockDirectory) -> Bool {
        let lock = directory.appendingPathComponent(dedupeKey(for: spoken))
        let now = Date()
        if let attrs = try? FileManager.default.attributesOfItem(atPath: lock.path),
           let mtime = attrs[.modificationDate] as? Date, now.timeIntervalSince(mtime) < window {
            return true
        }
        try? String(now.timeIntervalSince1970).write(to: lock, atomically: true, encoding: .utf8)
        return false
    }

    /// The most of a reply handed to `--announce` for rewording, so the
    /// command line stays small. The rewording reads less than this
    /// (`AnnouncementStylist.inputLimit`).
    static let detachedTextLimit = 6000

    /// Sends one announcement to a speaker; true when it was sent. The real
    /// one is an engine's `GoogleHomeClient.broadcast`; tests pass their own.
    public typealias Broadcaster = @Sendable (
        _ text: String, _ target: SpeakerDevice, _ structureId: String, _ config: SpeakerConfig
    ) async throws -> Bool

    /// `home`'s broadcast: an engine passes its own speakers.
    public static func broadcaster(for home: GoogleHomeClient) -> Broadcaster {
        { text, target, structureId, config in
            try await home.broadcast(text: text, target: target, structureId: structureId, config: config, force: false)
        }
    }

    /// The app's speakers (`HomeSpeakerEngine.app`'s).
    public static let googleHomeBroadcaster: Broadcaster = broadcaster(for: .shared)

    /// Entry point for `HomeSpeaker --claude-stop-hook`. Reads the hook JSON
    /// from `input`, speaks if appropriate, and always returns normally.
    ///
    /// A broadcast it sends itself goes into `history`. One it hands to the
    /// detached `--announce` (`launchDetached`) is recorded by that process,
    /// not here, so it is never listed twice. The de-duplication lock is in
    /// `lockDirectory`.
    public static func run(
        input: Data,
        configManager: ConfigManager? = nil,
        history: BroadcastHistory = .shared,
        lockDirectory: URL = ClaudeStopHook.lockDirectory,
        launchDetached: @Sendable (String) -> Void = { DetachedAnnouncement.launch(text: $0) },
        broadcaster: Broadcaster = ClaudeStopHook.googleHomeBroadcaster
    ) async {
        await run(
            input: input, config: { configManager ?? .shared }, history: history, lockDirectory: lockDirectory,
            launchDetached: launchDetached, broadcaster: broadcaster)
    }

    /// The same, with the settings asked for only once the transcript
    /// reads: reading them can write the default settings file or print a
    /// problem, which a hook run on bad input must not do.
    public static func run(
        input: Data,
        config makeConfig: @MainActor @Sendable () -> ConfigManager,
        history: BroadcastHistory = .shared,
        lockDirectory: URL = ClaudeStopHook.lockDirectory,
        launchDetached: @Sendable (String) -> Void = { DetachedAnnouncement.launch(text: $0) },
        broadcaster: Broadcaster = ClaudeStopHook.googleHomeBroadcaster
    ) async {
        guard let payload = try? JSONSerialization.jsonObject(with: input) as? [String: Any],
              let transcriptPath = payload["transcript_path"] as? String,
              let transcript = try? String(contentsOfFile: transcriptPath, encoding: .utf8) else { return }
        // Only the tail matters and transcripts grow large.
        let tail = transcript.split(separator: "\n").suffix(100).joined(separator: "\n")
        await speakTurn(
            parseTranscript(tail), agent: .claudeCode, config: makeConfig, history: history,
            lockDirectory: lockDirectory, launchDetached: launchDetached, broadcaster: broadcaster)
    }

    /// What every agent's end-of-turn hook does once it has read the turn:
    /// speaks the last reply in `entries` for `agent`, unless the agent's
    /// switch is off, the turn already spoke through a tool, or the same
    /// words were said a moment ago (by any agent's hook).
    public static func speakTurn(
        _ entries: [Entry],
        agent: CodingAgent,
        config makeConfig: @MainActor @Sendable () -> ConfigManager,
        history: BroadcastHistory = .shared,
        lockDirectory: URL = ClaudeStopHook.lockDirectory,
        launchDetached: @Sendable (String) -> Void,
        broadcaster: Broadcaster = ClaudeStopHook.googleHomeBroadcaster
    ) async {
        let config = await MainActor.run { makeConfig().config }
        guard config.enabled, config.announces(agent) else { return }
        let local = config.effectiveSpeakLocal || config.effectiveSpeakPhone
        let homeReady = config.effectiveSpeakHome && config.defaultDevice != nil && !config.structureId.isEmpty
        guard local || homeReady else { return }

        guard let text = textToSpeak(entries: entries) else { return }
        let spoken = GoogleHomeClient.cleanForSpeech(text, length: config.effectiveSpeechLength)
        guard !spoken.isEmpty, !isDuplicate(spoken: spoken, directory: lockDirectory) else { return }

        // The agent stops the hook after 10 s, and this Mac speaking a
        // summary takes longer, as can rewording it in a style (up to
        // `AnnouncementStylist.worstCaseSeconds`). So then a detached copy
        // of this binary makes the whole announcement (both outputs, one
        // media pause, the rewording) and outlives the hook. A reworded
        // reply goes over whole, as written: cut to the speech length first,
        // the model would never see the rest of it.
        if AnnouncementStylist.rewrites(config) {
            launchDetached(String(text.prefix(detachedTextLimit)))
            return
        }
        if local {
            launchDetached(spoken)
            return
        }
        guard let target = config.defaultDevice else { return }
        let sent = (try? await broadcaster(spoken, target, config.structureId, config)) ?? false
        if sent {
            _ = try? history.append(BroadcastLogItem(text: spoken, targetName: target.name, source: agent.displayName))
        }
    }
}

/// Starts `<this program> --announce <text>` in its own session with no
/// terminal, so ending (or killing) the hook's process does not end it.
public enum DetachedAnnouncement {
    /// This process's own program: the app's `HomeSpeaker`, or for the
    /// extension, its `bin/tool`. Either runs `--announce` on its own
    /// engine, so the announcement is made by the side the hook ran for.
    public static var defaultExecutable: String? { Bundle.main.executablePath }

    /// Starts one program, detached: `arguments[0]` is the program itself.
    public typealias Spawner = (_ executable: String, _ arguments: [String]) -> Bool

    /// Starts `executable --announce text`. True when it started. Tests pass
    /// their own `spawn`, so nothing is started.
    @discardableResult
    public static func launch(
        text: String, agent: CodingAgent = .claudeCode, executable: String? = DetachedAnnouncement.defaultExecutable,
        spawn: Spawner = DetachedAnnouncement.spawnDetached
    ) -> Bool {
        guard let executable else { return false }
        return spawn(executable, [executable] + arguments(text: text, agent: agent))
    }

    /// `--announce <text>` for Claude Code (the form every release has
    /// used), `--announce <text> --source <agent>` for the others.
    public static func arguments(text: String, agent: CodingAgent) -> [String] {
        guard agent != .claudeCode else { return [ClaudeStopHook.announceArgument, text] }
        return [ClaudeStopHook.announceArgument, text, BroadcastSource.flag, BroadcastSource.from(agent).rawValue]
    }

    /// `posix_spawn` in a session of its own, with no terminal.
    public static func spawnDetached(_ executable: String, _ strings: [String]) -> Bool {
        var attributes: posix_spawnattr_t?
        posix_spawnattr_init(&attributes)
        defer { posix_spawnattr_destroy(&attributes) }
        posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETSID))

        var actions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&actions)
        defer { posix_spawn_file_actions_destroy(&actions) }
        posix_spawn_file_actions_addopen(&actions, 0, "/dev/null", O_RDONLY, 0)
        posix_spawn_file_actions_addopen(&actions, 1, "/dev/null", O_WRONLY, 0)
        posix_spawn_file_actions_addopen(&actions, 2, "/dev/null", O_WRONLY, 0)

        // Typed explicitly: CI's toolchain (Xcode's Swift) could not infer the
        // element type of `map { strdup($0) } + [nil]` and failed the build;
        // the local Command Line Tools compiler accepted it.
        var argv: [UnsafeMutablePointer<CChar>?] = strings.map { strdup($0) }
        argv.append(nil)
        defer { argv.forEach { free($0) } }
        var pid = pid_t()
        return posix_spawn(&pid, executable, &actions, &attributes, argv, environ) == 0
    }
}
