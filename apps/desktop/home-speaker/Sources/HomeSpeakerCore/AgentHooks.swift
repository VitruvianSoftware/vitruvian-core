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

/// The Antigravity `Stop` hook. Antigravity (agy 1.4) runs every enabled
/// plugin's `hooks.json`; ours, at `~/.gemini/config/plugins/home-speaker/`,
/// runs `HomeSpeaker --antigravity-hook` with the hook payload on stdin
/// (camelCase protojson: `transcriptPath`, `terminationReason`, `fullyIdle`).
/// Antigravity waits for the hook and expects a JSON answer, so this always
/// answers `{}` and leaves anything slow to the detached `--announce`.
public enum AntigravityHook {
    public static let argument = "--antigravity-hook"

    /// The most of the transcript read from its end. A turn's steps sit at
    /// the end, and a long conversation's file runs to tens of megabytes.
    static let tailBytes = 4 << 20

    /// Parses Antigravity's `transcript.jsonl`: `USER_INPUT` steps are the
    /// person, `PLANNER_RESPONSE` steps the model (its `content` is the
    /// reply, its `tool_calls` what it ran). Every other step is skipped.
    public static func parseTranscript(_ text: String) -> [ClaudeStopHook.Entry] {
        var entries: [ClaudeStopHook.Entry] = []
        for line in text.split(separator: "\n") {
            guard let data = line.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let type = obj["type"] as? String else { continue }
            switch type {
            case "USER_INPUT":
                let content = obj["content"] as? String ?? ""
                entries.append(.init(
                    role: "user", text: content,
                    isPlainUserPrompt: ClaudeStopHook.isHumanUserText(content),
                    mentionsBroadcast: ClaudeStopHook.isSilentUnlessExplicitPrompt(content)))
            case "PLANNER_RESPONSE":
                let calls = (obj["tool_calls"] as? [[String: Any]]) ?? []
                entries.append(.init(
                    role: "assistant", text: obj["content"] as? String ?? "",
                    mentionsBroadcast: calls.contains(where: callBroadcasts)))
            default:
                continue
            }
        }
        return entries
    }

    /// True when one of Antigravity's tool calls announces something:
    /// `run_command` running a broadcaster, or a Home MCP action carrying
    /// the broadcast trait. Antigravity writes each argument as a JSON
    /// value inside a string (`"CommandLine": "\"speaker-broadcast …\""`).
    static func callBroadcasts(_ call: [String: Any]) -> Bool {
        let name = call["name"] as? String ?? ""
        let args = ((call["args"] as? [String: Any]) ?? [:]).mapValues(decoded)
        if name == "run_command" {
            return (args["CommandLine"] as? String).map(ClaudeStopHook.commandBroadcasts) ?? false
        }
        if name == "call_mcp_tool" {
            return ClaudeStopHook.toolBroadcasts(name: args["ToolName"] as? String ?? "", input: args["Arguments"])
        }
        return ClaudeStopHook.toolBroadcasts(name: name, input: args)
    }

    /// A string argument with its JSON encoding taken off, when it has one.
    static func decoded(_ value: Any) -> Any {
        guard let string = value as? String, let data = string.data(using: .utf8),
              let inner = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else { return value }
        return inner
    }

    /// The transcript to read for `path`: `transcript.jsonl` cuts long
    /// steps short, so the `transcript_full.jsonl` beside it wins when there.
    static func transcriptURL(_ path: String) -> URL {
        let url = URL(fileURLWithPath: path)
        let full = url.deletingLastPathComponent().appendingPathComponent("transcript_full.jsonl")
        return FileManager.default.fileExists(atPath: full.path) ? full : url
    }

    /// True when the payload is a finished turn: the model stopped of its
    /// own accord and nothing is still running in the background (a
    /// background task wakes the model again, and that turn's own `Stop`
    /// speaks its end).
    public static func isTurnEnd(_ payload: [String: Any]) -> Bool {
        let reason = payload["terminationReason"] as? String ?? "NO_TOOL_CALL"
        let idle = payload["fullyIdle"] as? Bool ?? true
        return reason == "NO_TOOL_CALL" && idle
    }

    /// True when `path` belongs to an Antigravity subagent conversation:
    /// Antigravity records every subagent in its parent conversation's
    /// `<brain>/<parent>/.system_generated/subagents/<id>.json`.
    public static func isSubagentTranscript(_ path: String) -> Bool {
        let logsDir = URL(fileURLWithPath: path).standardizedFileURL.deletingLastPathComponent()
        let sysGenDir = logsDir.deletingLastPathComponent()
        guard logsDir.lastPathComponent == "logs",
              sysGenDir.lastPathComponent == ".system_generated" else { return false }
        let convDir = sysGenDir.deletingLastPathComponent()
        let convID = convDir.lastPathComponent
        guard !convID.isEmpty else { return false }
        let brainDir = convDir.deletingLastPathComponent()
        guard let siblings = try? FileManager.default.contentsOfDirectory(
            at: brainDir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else { return false }
        let markerRelPath = ".system_generated/subagents/\(convID).json"
        return siblings.contains { folder in
            FileManager.default.fileExists(atPath: folder.appendingPathComponent(markerRelPath).path)
        }
    }

    /// Entry point for `HomeSpeaker --antigravity-hook`.
    public static func run(
        input: Data,
        config makeConfig: @MainActor @Sendable () -> ConfigManager,
        history: BroadcastHistory = .shared,
        lockDirectory: URL = ClaudeStopHook.lockDirectory,
        speechLockURL: URL? = nil,
        launchDetached: @Sendable (String) -> Void = { DetachedAnnouncement.launch(text: $0, agent: .antigravity) },
        broadcaster: ClaudeStopHook.Broadcaster = ClaudeStopHook.googleHomeBroadcaster
    ) async {
        guard let payload = try? JSONSerialization.jsonObject(with: input) as? [String: Any], isTurnEnd(payload),
              let path = (payload["transcriptPath"] ?? payload["transcript_path"]) as? String,
              !isSubagentTranscript(path) else { return }
        let resolvedURL = transcriptURL(path)
        guard let tail = readTailWithTruncation(of: resolvedURL, bytes: tailBytes) else { return }
        var entries = parseTranscript(tail.text)
        if tail.wasTruncated, !entries.contains(where: \.isPlainUserPrompt) {
            let headURL = FileManager.default.fileExists(atPath: path) ? URL(fileURLWithPath: path) : resolvedURL
            if let head = readHead(of: headURL), parseTranscript(head).contains(where: \.isPlainUserPrompt) {
                entries.insert(.init(role: "user", isPlainUserPrompt: true), at: 0)
            }
        }
        await ClaudeStopHook.speakTurn(
            entries, agent: .antigravity, config: makeConfig, history: history,
            lockDirectory: lockDirectory, speechLockURL: speechLockURL,
            launchDetached: launchDetached, broadcaster: broadcaster)
    }

    /// The last `bytes` of a file as whole lines; nil when it cannot be read.
    static func readTail(of url: URL, bytes: Int) -> String? {
        readTailWithTruncation(of: url, bytes: bytes)?.text
    }

    /// The last `bytes` of a file as whole lines, plus whether earlier bytes
    /// were skipped (`wasTruncated == true`).
    static func readTailWithTruncation(of url: URL, bytes: Int) -> (text: String, wasTruncated: Bool)? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let size = try? handle.seekToEnd() else { return nil }
        let start = size > UInt64(bytes) ? size - UInt64(bytes) : 0
        guard (try? handle.seek(toOffset: start)) != nil, let data = try? handle.readToEnd() else { return nil }
        var text = String(decoding: data, as: UTF8.self)
        // Started mid-line: drop the part line.
        if start > 0, let newline = text.firstIndex(of: "\n") { text = String(text[text.index(after: newline)...]) }
        return (text, start > 0)
    }

    /// The first `bytes` of a file as whole lines; nil when it cannot be read.
    static func readHead(of url: URL, bytes: Int = 64 << 10) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: bytes) else { return nil }
        var text = String(decoding: data, as: UTF8.self)
        if data.count == bytes, let newline = text.lastIndex(of: "\n") {
            text = String(text[..<newline])
        }
        return text
    }
}

/// The OpenCode end-of-turn hook. OpenCode (2.x) loads every file in
/// `~/.config/opencode/plugins/`; ours, `home-speaker.ts`, waits for
/// `session.idle`, reads the session's latest messages through
/// `ctx.session.context({ sessionID })` and pipes them to
/// `HomeSpeaker --opencode-hook` as `{"sessionID": …, "messages": [...]}`.
/// Supports both OpenCode 2.x (`Session.Message.Info` from `session.context`,
/// with top-level `type` and `content`) and 1.x (`info.role` and `parts`).
public enum OpenCodeHook {
    public static let argument = "--opencode-hook"

    /// One entry per message: the person's messages are the turn starts,
    /// an assistant's last `text` part is its reply and its `tool` parts
    /// are what it ran (`shell`/`bash` with `input.command`, or an MCP tool).
    public static func parseMessages(_ messages: [[String: Any]]) -> [ClaudeStopHook.Entry] {
        messages.compactMap { message in
            if let type = message["type"] as? String {
                switch type {
                case "user":
                    let text = (message["text"] as? String) ?? ""
                    return ClaudeStopHook.Entry(
                        role: "user", text: text,
                        isPlainUserPrompt: ClaudeStopHook.isHumanUserText(text),
                        mentionsBroadcast: ClaudeStopHook.isSilentUnlessExplicitPrompt(text))
                case "assistant":
                    let content = (message["content"] as? [[String: Any]]) ?? []
                    var entry = ClaudeStopHook.Entry(role: "assistant")
                    for part in content {
                        switch part["type"] as? String {
                        case "text":
                            guard part["synthetic"] as? Bool != true, let text = part["text"] as? String else { continue }
                            entry.text = text
                        case "tool":
                            let state = part["state"] as? [String: Any] ?? [:]
                            let name = (part["name"] ?? part["tool"]) as? String ?? ""
                            if ClaudeStopHook.toolBroadcasts(name: name, input: state["input"] ?? part["input"]) {
                                entry.mentionsBroadcast = true
                            }
                        default:
                            break
                        }
                    }
                    return entry
                case "shell":
                    guard let command = message["command"] as? String,
                          ClaudeStopHook.commandBroadcasts(command) else { return nil }
                    return ClaudeStopHook.Entry(role: "assistant", mentionsBroadcast: true)
                default:
                    return nil
                }
            }

            let info = message["info"] as? [String: Any] ?? [:]
            guard let role = info["role"] as? String else { return nil }
            let parts = (message["parts"] as? [[String: Any]]) ?? []
            var entry = ClaudeStopHook.Entry(role: role)
            var hasText = false
            for part in parts {
                switch part["type"] as? String {
                case "text":
                    guard part["synthetic"] as? Bool != true, let text = part["text"] as? String else { continue }
                    hasText = true
                    entry.text = text
                case "tool":
                    let state = part["state"] as? [String: Any] ?? [:]
                    let name = (part["name"] ?? part["tool"]) as? String ?? ""
                    if ClaudeStopHook.toolBroadcasts(name: name, input: state["input"] ?? part["input"]) {
                        entry.mentionsBroadcast = true
                    }
                default:
                    break
                }
            }
            entry.isPlainUserPrompt = role == "user" && hasText && ClaudeStopHook.isHumanUserText(entry.text)
            if role == "user" && hasText && ClaudeStopHook.isSilentUnlessExplicitPrompt(entry.text) {
                entry.mentionsBroadcast = true
            }
            return entry
        }
    }

    /// Entry point for `HomeSpeaker --opencode-hook`.
    public static func run(
        input: Data,
        config makeConfig: @MainActor @Sendable () -> ConfigManager,
        history: BroadcastHistory = .shared,
        lockDirectory: URL = ClaudeStopHook.lockDirectory,
        speechLockURL: URL? = nil,
        launchDetached: @Sendable (String) -> Void = { DetachedAnnouncement.launch(text: $0, agent: .opencode) },
        broadcaster: ClaudeStopHook.Broadcaster = ClaudeStopHook.googleHomeBroadcaster
    ) async {
        guard let payload = try? JSONSerialization.jsonObject(with: input) as? [String: Any],
              let messages = payload["messages"] as? [[String: Any]] else { return }
        await ClaudeStopHook.speakTurn(
            parseMessages(messages), agent: .opencode, config: makeConfig, history: history,
            lockDirectory: lockDirectory, speechLockURL: speechLockURL,
            launchDetached: launchDetached, broadcaster: broadcaster)
    }
}
