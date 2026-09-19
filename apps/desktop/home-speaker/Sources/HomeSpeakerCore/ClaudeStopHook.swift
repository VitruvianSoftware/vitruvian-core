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

    /// Entry point for `HomeSpeaker --claude-stop-hook`. Reads the hook JSON
    /// from `input`, speaks if appropriate, and always returns normally.
    public static func run(input: Data, configManager: ConfigManager? = nil) async {
        guard let payload = try? JSONSerialization.jsonObject(with: input) as? [String: Any],
              let transcriptPath = payload["transcript_path"] as? String,
              let transcript = try? String(contentsOfFile: transcriptPath, encoding: .utf8) else { return }

        let config = await MainActor.run { (configManager ?? ConfigManager.shared).config }
        guard config.enabled, let target = config.defaultDevice, !config.structureId.isEmpty else { return }

        // Only the tail matters and transcripts grow large.
        let tail = transcript.split(separator: "\n").suffix(100).joined(separator: "\n")
        guard let text = textToSpeak(entries: parseTranscript(tail)) else { return }
        let spoken = GoogleHomeClient.cleanForSpeech(text, length: config.effectiveSpeechLength)
        guard !spoken.isEmpty, !isDuplicate(spoken: spoken) else { return }

        _ = try? await GoogleHomeClient.shared.broadcast(
            text: spoken, target: target, structureId: config.structureId, config: config, force: false)
    }
}
