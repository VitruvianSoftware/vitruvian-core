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
//
// Shared by the standalone Nexus Agent app and the Nexus Agent feature of the
// Vitruvian desktop app. Written for Vitruvian and released under MIT by its
// copyright holder on 2026-10-08 (apps/desktop/vitruvian/UPSTREAM.md).

import Foundation

/// How much the agent may do without asking, as the bot's `AGY_APPROVAL_MODE`
/// spells it. The raw values are what the bot reads.
public enum NexusAgentApprovalMode: String, CaseIterable, Identifiable {
    case yolo
    case acceptEdits = "accept-edits"
    case plan
    case standard = "default"

    public var id: String { rawValue }

    /// The bot's own reading: an absent key means yolo, the retired Gemini
    /// name and the underscore spelling mean accept-edits, and anything it
    /// does not know (an empty value included) asks agy for its default.
    public static func parse(_ raw: String?) -> NexusAgentApprovalMode {
        guard let raw else { return .yolo }
        switch raw.trimmingCharacters(in: .whitespaces).lowercased() {
        case "yolo": return .yolo
        case "auto_edit", "accept-edits", "accept_edits": return .acceptEdits
        case "plan": return .plan
        default: return .standard
        }
    }

    /// The agy flags for the mode, exactly as the bot passes them.
    public var agyArguments: [String] {
        switch self {
        case .yolo: return ["--dangerously-skip-permissions"]
        case .acceptEdits: return ["--mode", "accept-edits"]
        case .plan: return ["--mode", "plan"]
        case .standard: return []
        }
    }

    /// The Claude Code permission mode corresponding to this approval mode.
    public var claudePermissionMode: String {
        switch self {
        case .yolo: return "bypassPermissions"
        case .acceptEdits: return "acceptEdits"
        case .plan: return "plan"
        case .standard: return "default"
        }
    }
}

/// agy's `--effort`; `automatic` leaves the choice to agy.
public enum NexusAgentEffort: String, CaseIterable, Identifiable {
    case automatic = ""
    case low, medium, high

    public var id: String { rawValue }

    public static func parse(_ raw: String?) -> NexusAgentEffort {
        NexusAgentEffort(rawValue: (raw ?? "").trimmingCharacters(in: .whitespaces).lowercased())
            ?? .automatic
    }
}

/// Represents a CLI backend that can handle prompts in Quick Prompt.
public struct NexusAgentCLIProvider: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var commandTemplate: String
    public var isBuiltIn: Bool

    public init(id: UUID, name: String, commandTemplate: String, isBuiltIn: Bool = true) {
        self.id = id
        self.name = name
        self.commandTemplate = commandTemplate
        self.isBuiltIn = isBuiltIn
    }

    public static let antigravity = NexusAgentCLIProvider(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
        name: "Antigravity CLI",
        commandTemplate: "agy -p \"{prompt}\" --output-format stream-json --dangerously-skip-permissions"
    )

    public static let claude = NexusAgentCLIProvider(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!,
        name: "Claude Code",
        commandTemplate: "claude -p \"{prompt}\""
    )

    public static let ollama = NexusAgentCLIProvider(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
        name: "Ollama (claude)",
        commandTemplate: "ollama launch claude --model {model} -- -p \"{prompt}\""
    )

    public static let builtIns: [NexusAgentCLIProvider] = [.antigravity, .claude, .ollama]

    public var executableName: String {
        if id == Self.claude.id { return "claude" }
        if id == Self.ollama.id { return "ollama" }
        return "agy"
    }
}

/// The part of the bot's `.env` the Settings page edits. Everything else in
/// the file (the timeout, a custom provider, comments) is left as it was.
public struct NexusAgentConfiguration: Equatable {
    public var botToken: String
    public var allowedUserIDs: String
    public var workingDirectory: String
    public var approvalMode: NexusAgentApprovalMode
    public var model: String
    public var effort: NexusAgentEffort
    public var activeProvider: NexusAgentCLIProvider

    public init(botToken: String = "",
                 allowedUserIDs: String = "",
                 workingDirectory: String = "",
                 approvalMode: NexusAgentApprovalMode = .yolo,
                 model: String = "",
                 effort: NexusAgentEffort = .automatic,
                 activeProvider: NexusAgentCLIProvider = .antigravity) {
        self.botToken = botToken
        self.allowedUserIDs = allowedUserIDs
        self.workingDirectory = workingDirectory
        self.approvalMode = approvalMode
        self.model = model
        self.effort = effort
        self.activeProvider = activeProvider
    }

    /// The placeholder the bot's example file ships with.
    public static let placeholderToken = "your_bot_token_here"

    /// The bot refuses to start without a real token.
    public var isConfigured: Bool {
        let token = botToken.trimmingCharacters(in: .whitespaces)
        return !token.isEmpty && token != Self.placeholderToken
    }

    /// The user ids the bot will answer, in order and without blanks. Empty
    /// means the bot answers anyone who finds it.
    public var allowedUserIDList: [String] {
        allowedUserIDs.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}

/// Reads and writes the bot's `.env` the way its `dotenv` loader reads it.
public enum NexusAgentEnvFile {
    public static let tokenKey = "TELEGRAM_BOT_TOKEN"
    public static let allowedUsersKey = "ALLOWED_USER_IDS"
    public static let workingDirectoryKey = "AGY_WORKING_DIR"
    public static let approvalModeKey = "AGY_APPROVAL_MODE"
    public static let modelKey = "AGY_MODEL"
    public static let effortKey = "AGY_EFFORT"

    /// Pre-migration names the bot still honours when the AGY_ one is absent.
    /// Writing the file supersedes them, so they are dropped then: left in
    /// place, `GEMINI_THINKING=true` would keep forcing high effort after the
    /// page said otherwise.
    public static let legacyKeys = ["GEMINI_WORKING_DIR", "GEMINI_APPROVAL_MODE",
                                     "GEMINI_MODEL", "GEMINI_THINKING"]

    /// The keys the page owns, in the order a new file lists them.
    public static let managedKeys = [tokenKey, allowedUsersKey, workingDirectoryKey,
                                      approvalModeKey, modelKey, effortKey]

    /// Every `KEY=value` pair, later lines winning as they do for dotenv.
    public static func values(in content: String) -> [String: String] {
        var values: [String: String] = [:]
        for line in content.components(separatedBy: .newlines) {
            if let pair = assignment(in: line) {
                values[pair.key] = pair.value
            }
        }
        return values
    }

    public static func parse(_ content: String) -> NexusAgentConfiguration {
        let values = values(in: content)
        func compat(_ name: String) -> String? {
            values["AGY_\(name)"] ?? values["GEMINI_\(name)"]
        }
        var effort = NexusAgentEffort.parse(values[effortKey])
        if effort == .automatic, values["GEMINI_THINKING"]?.lowercased() == "true" {
            effort = .high
        }
        return NexusAgentConfiguration(
            botToken: values[tokenKey] ?? "",
            allowedUserIDs: values[allowedUsersKey] ?? "",
            workingDirectory: compat("WORKING_DIR") ?? "",
            approvalMode: .parse(compat("APPROVAL_MODE")),
            model: compat("MODEL") ?? "",
            effort: effort)
    }

    /// The file with the page's values written in. An existing file keeps its
    /// comments, its order and every key the page does not own; a key it
    /// lacks is added at the end. With no file yet, the bot's template is
    /// written, so the result matches what the standalone app produced.
    public static func render(_ configuration: NexusAgentConfiguration, over existing: String?) -> String {
        let wanted = assignments(for: configuration)
        guard let existing, !existing.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return template(wanted)
        }
        var lines = existing.components(separatedBy: "\n")
        // A trailing newline splits into one empty last element; keep it last.
        let endsWithNewline = lines.last == ""
        if endsWithNewline { lines.removeLast() }
        var written: Set<String> = []
        var output: [String] = []
        for line in lines {
            guard let key = assignment(in: line)?.key else {
                output.append(line)
                continue
            }
            if legacyKeys.contains(key) { continue }
            if let value = wanted[key] {
                // Every copy gets the new value: dotenv reads the last one.
                output.append("\(key)=\(encoded(value))")
                written.insert(key)
            } else {
                output.append(line)
            }
        }
        let missing = managedKeys.filter { !written.contains($0) }
        if !missing.isEmpty {
            if output.last.map({ !$0.trimmingCharacters(in: .whitespaces).isEmpty }) ?? false {
                output.append("")
            }
            for key in missing {
                output.append("\(key)=\(encoded(wanted[key] ?? ""))")
            }
        }
        return output.joined(separator: "\n") + "\n"
    }

    // MARK: - Lines

    /// `KEY=value` with dotenv's reading of the value: an optional `export`,
    /// surrounding quotes removed, and an unquoted value ending at ` #`.
    public static func assignment(in line: String) -> (key: String, value: String)? {
        var text = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !text.hasPrefix("#") else { return nil }
        if text.hasPrefix("export ") {
            text = String(text.dropFirst("export ".count)).trimmingCharacters(in: .whitespaces)
        }
        guard let equals = text.firstIndex(of: "=") else { return nil }
        let key = text[..<equals].trimmingCharacters(in: .whitespaces)
        guard !key.isEmpty, key.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" || $0 == "." || $0 == "-" })
        else { return nil }
        var value = text[text.index(after: equals)...].trimmingCharacters(in: .whitespaces)
        if let quote = value.first, quote == "\"" || quote == "'" || quote == "`",
           value.count >= 2, let close = value.dropFirst().firstIndex(of: quote) {
            value = String(value[value.index(after: value.startIndex)..<close])
        } else if let comment = value.range(of: " #") {
            value = value[..<comment.lowerBound].trimmingCharacters(in: .whitespaces)
        }
        return (key, value)
    }

    /// A value as it can be written on one line. Line breaks are removed so a
    /// pasted value can never smuggle in a second assignment, and a value
    /// dotenv would otherwise cut or trim is quoted.
    public static func encoded(_ value: String) -> String {
        let flat = value.components(separatedBy: .newlines).joined()
        let needsQuotes = flat.contains("#") || flat.first == "\"" || flat.first == "'" || flat.first == "`"
            || flat != flat.trimmingCharacters(in: .whitespaces)
        guard needsQuotes else { return flat }
        // Single quotes are taken literally by dotenv; a value that holds one
        // falls back to double quotes, which it only expands for \n.
        return flat.contains("'") ? "\"\(flat)\"" : "'\(flat)'"
    }

    private static func assignments(for configuration: NexusAgentConfiguration) -> [String: String] {
        [
            tokenKey: configuration.botToken.trimmingCharacters(in: .whitespaces),
            allowedUsersKey: configuration.allowedUserIDList.joined(separator: ","),
            workingDirectoryKey: configuration.workingDirectory.trimmingCharacters(in: .whitespaces),
            approvalModeKey: configuration.approvalMode.rawValue,
            modelKey: configuration.model.trimmingCharacters(in: .whitespaces),
            effortKey: configuration.effort.rawValue,
        ]
    }

    private static func template(_ values: [String: String]) -> String {
        func value(_ key: String) -> String { encoded(values[key] ?? "") }
        return """
        # Telegram Bot Token (get from @BotFather on Telegram)
        \(tokenKey)=\(value(tokenKey))

        # Comma-separated list of allowed Telegram user IDs
        \(allowedUsersKey)=\(value(allowedUsersKey))

        # Working directory for the Antigravity CLI (agy)
        \(workingDirectoryKey)=\(value(workingDirectoryKey))

        # Max execution time per prompt in milliseconds
        AGY_TIMEOUT_MS=300000

        # Approval mode: yolo, accept-edits, plan, default
        \(approvalModeKey)=\(value(approvalModeKey))

        # Model (optional; `agy models` lists them)
        \(modelKey)=\(value(modelKey))

        # Reasoning effort: low, medium, high (empty = agy default)
        \(effortKey)=\(value(effortKey))

        # AI backend provider: agy or custom
        CLI_PROVIDER=agy

        # Command template for custom provider ({prompt} and {model} are substituted at runtime)
        CLI_COMMAND_TEMPLATE=

        """
    }
}

/// Where the bot and the agent CLI live, and how the agent is asked.
public enum NexusAgentSupport {
    /// The bot's standard home, shared with the standalone app.
    public static func defaultBotDirectory(home: String) -> String {
        (home as NSString).appendingPathComponent(".config/nexus-agent")
    }

    /// A configured folder, with `~` expanded, or the standard home.
    public static func botDirectory(configured: String, home: String) -> String {
        let trimmed = configured.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return defaultBotDirectory(home: home) }
        if trimmed == "~" { return home }
        if trimmed.hasPrefix("~/") {
            return (home as NSString).appendingPathComponent(String(trimmed.dropFirst(2)))
        }
        return trimmed
    }

    /// The bot's entry point inside its folder.
    public static let botEntryPoint = "src/bot.js"

    /// Install locations an app launched from Finder does not have on its
    /// PATH, in the order they are tried.
    public static func searchDirectories(home: String) -> [String] {
        [(home as NSString).appendingPathComponent(".local/bin"), "/opt/homebrew/bin", "/usr/local/bin"]
    }

    /// `AGY_BIN` or named executable first, then the usual install locations. Nil when none is
    /// executable, so the page can say so instead of failing at run time.
    public static func locateAgent(named binary: String = "agy", environment: [String: String], home: String,
                                    isExecutable: (String) -> Bool) -> String? {
        if binary == "agy", let explicit = environment["AGY_BIN"]?.trimmingCharacters(in: .whitespaces),
           !explicit.isEmpty, isExecutable(explicit) {
            return explicit
        }
        return searchDirectories(home: home)
            .map { ($0 as NSString).appendingPathComponent(binary) }
            .first(where: isExecutable)
    }

    /// Node from Homebrew or the official installer. macOS ships none.
    public static func locateNode(home: String, isExecutable: (String) -> Bool) -> String? {
        ["/opt/homebrew/bin/node", "/usr/local/bin/node",
         (home as NSString).appendingPathComponent(".local/bin/node")]
            .first(where: isExecutable)
    }

    /// The child's environment: the app's own, the install locations put in
    /// front of PATH, and colour codes off so logs stay readable.
    public static func childEnvironment(base: [String: String], home: String) -> [String: String] {
        var environment = base
        let current = base["PATH"].flatMap { $0.isEmpty ? nil : $0 } ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        let existing = Set(current.split(separator: ":").map(String.init))
        let extra = searchDirectories(home: home).filter { !existing.contains($0) }
        environment["PATH"] = (extra + [current]).joined(separator: ":")
        environment["NO_COLOR"] = "1"
        return environment
    }

    /// Check whether a folder contains a .git directory.
    public static func isGitRepo(at url: URL) -> Bool {
        let gitDir = url.appendingPathComponent(".git")
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: gitDir.path, isDirectory: &isDirectory)
    }

    /// One Quick Prompt turn: formatted per active provider.
    public static func agentArguments(prompt: String, configuration: NexusAgentConfiguration,
                                       conversationID: String?,
                                       planMode: Bool = false,
                                       worktreeMode: Bool = false) -> [String] {
        if configuration.activeProvider.id == NexusAgentCLIProvider.claude.id {
            var args = ["-p", prompt, "--output-format", "stream-json", "--include-partial-messages", "--verbose"]
            if planMode {
                args += ["--permission-mode", "plan",
                         "--append-system-prompt", "You are in PLAN MODE. Do NOT create, edit, modify, or delete any files. Do NOT run any shell commands. ONLY explain what you would do as a detailed numbered plan. Wait for explicit user approval before taking any action."]
            } else {
                args += ["--permission-mode", configuration.approvalMode.claudePermissionMode]
                if configuration.approvalMode == .yolo {
                    args += ["--dangerously-skip-permissions"]
                }
            }
            if worktreeMode {
                args += ["-w"]
            }
            let model = configuration.model.trimmingCharacters(in: .whitespaces)
            if !model.isEmpty { args += ["--model", model] }
            if let conversationID, !conversationID.isEmpty {
                args += ["--resume", conversationID]
            }
            return args
        }
        if configuration.activeProvider.id == NexusAgentCLIProvider.ollama.id {
            let model = configuration.model.trimmingCharacters(in: .whitespaces)
            let args = ["launch", "claude", "--model", model.isEmpty ? "default" : model]
            var innerArgs = ["-p", prompt, "--output-format", "stream-json", "--include-partial-messages", "--verbose"]
            if planMode {
                innerArgs += ["--permission-mode", "plan",
                              "--append-system-prompt", "You are in PLAN MODE. Do NOT create, edit, modify, or delete any files. Do NOT run any shell commands. ONLY explain what you would do as a detailed numbered plan. Wait for explicit user approval before taking any action."]
            } else {
                innerArgs += ["--permission-mode", configuration.approvalMode.claudePermissionMode]
                if configuration.approvalMode == .yolo {
                    innerArgs += ["--dangerously-skip-permissions"]
                }
            }
            if worktreeMode {
                innerArgs += ["-w"]
            }
            if let conversationID, !conversationID.isEmpty {
                innerArgs += ["--resume", conversationID]
            }
            return args + ["--"] + innerArgs
        }
        var arguments = ["-p", prompt, "--output-format", "stream-json"]
        if planMode {
            arguments += ["--mode", "plan"]
        } else {
            arguments += configuration.approvalMode.agyArguments
        }
        let model = configuration.model.trimmingCharacters(in: .whitespaces)
        if !model.isEmpty { arguments += ["--model", model] }
        if configuration.effort != .automatic { arguments += ["--effort", configuration.effort.rawValue] }
        if let conversationID, !conversationID.isEmpty { arguments += ["--conversation", conversationID] }
        return arguments
    }

    /// The last `count` non-empty lines of a log.
    public static func tail(_ text: String, count: Int = 20) -> [String] {
        guard count > 0 else { return [] }
        return Array(text.components(separatedBy: .newlines).filter { !$0.isEmpty }.suffix(count))
    }

    /// A PID file's process id, or nil when it holds anything else.
    public static func processID(fromPIDFile text: String) -> Int32? {
        guard let pid = Int32(text.trimmingCharacters(in: .whitespacesAndNewlines)), pid > 0 else { return nil }
        return pid
    }

    /// `agy models` prints a "Fetching…" line, then `id<TAB>name` rows.
    public static func parseModels(_ raw: String) -> [(id: String, name: String)] {
        raw.split(separator: "\n").compactMap { line in
            let text = line.trimmingCharacters(in: .whitespaces)
            guard !text.isEmpty, !text.lowercased().hasPrefix("fetching") else { return nil }
            let parts = text.split(separator: "\t", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            guard let id = parts.first, !id.isEmpty else { return nil }
            return (id, parts.count > 1 && !parts[1].isEmpty ? parts[1] : id)
        }
    }
}

/// An interactive tool execution approval request.
public struct NexusAgentApprovalRequest: Identifiable, Equatable, Sendable {
    public let id: String
    public let toolName: String
    public let commandOrPath: String
    public var status: Status

    public enum Status: String, Sendable, Equatable {
        case pending
        case approved
        case denied
        case sessionAllowed = "session_allowed"
    }

    public init(
        id: String = UUID().uuidString,
        toolName: String,
        commandOrPath: String,
        status: Status = .pending
    ) {
        self.id = id
        self.toolName = toolName
        self.commandOrPath = commandOrPath
        self.status = status
    }
}

public struct NexusAgentTurnMetrics: Equatable {
    public var durationMs: Int?
    public var inputTokens: Int?
    public var outputTokens: Int?
    public var cachedTokens: Int?
    public var numTurns: Int?
    public var toolCalls: Int?
    public var totalCostUSD: Double?

    public init(
        durationMs: Int? = nil,
        inputTokens: Int? = nil,
        outputTokens: Int? = nil,
        cachedTokens: Int? = nil,
        numTurns: Int? = nil,
        toolCalls: Int? = nil,
        totalCostUSD: Double? = nil
    ) {
        self.durationMs = durationMs
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.cachedTokens = cachedTokens
        self.numTurns = numTurns
        self.toolCalls = toolCalls
        self.totalCostUSD = totalCostUSD
    }
}

/// One line of `agy --output-format stream-json` or Claude Code stream-json, reduced to what the Quick
/// Prompt shows.
public enum NexusAgentStreamEvent: Equatable {
    case started(conversationID: String?)
    case text(String)
    case tool(name: String, finished: Bool)
    case approval(NexusAgentApprovalRequest)
    case finished(status: String, response: String?, error: String?, conversationID: String?, metrics: NexusAgentTurnMetrics? = nil)

    /// Nil for blank lines, non-JSON noise and events the prompt ignores.
    public static func parse(_ line: String) -> NexusAgentStreamEvent? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8),
              let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else { return nil }

        // Format 1: Antigravity stream-json (keyed by "event")
        if let event = json["event"] as? String {
            switch event {
            case "init":
                return .started(conversationID: nonEmpty(json["conversation_id"]))
            case "step_update":
                guard let step = json["step_update"] as? [String: Any] else { return nil }
                switch step["step_type"] as? String {
                case "agent_response":
                    guard let delta = step["text_delta"] as? String, !delta.isEmpty else { return nil }
                    return .text(delta)
                case "tool":
                    let name = nonEmpty(step["tool_name"]) ?? "tool"
                    return .tool(name: name, finished: (step["state"] as? String)?.uppercased() == "DONE")
                default:
                    return nil
                }
            case "result":
                guard let result = json["result"] as? [String: Any] else { return nil }
                var m = NexusAgentTurnMetrics()
                var hasMetrics = false
                if let secs = result["duration_seconds"] as? NSNumber {
                    m.durationMs = Int(secs.doubleValue * 1000)
                    hasMetrics = true
                } else if let ms = result["duration_ms"] as? NSNumber {
                    m.durationMs = ms.intValue
                    hasMetrics = true
                }
                if let usage = result["usage"] as? [String: Any] {
                    if let t = usage["input_tokens"] as? NSNumber { m.inputTokens = t.intValue; hasMetrics = true }
                    if let t = usage["output_tokens"] as? NSNumber { m.outputTokens = t.intValue; hasMetrics = true }
                    if let t = usage["cache_read_tokens"] as? NSNumber { m.cachedTokens = t.intValue; hasMetrics = true }
                }
                if let t = result["input_tokens"] as? NSNumber { m.inputTokens = t.intValue; hasMetrics = true }
                if let t = result["output_tokens"] as? NSNumber { m.outputTokens = t.intValue; hasMetrics = true }
                if let t = result["cached_tokens"] as? NSNumber { m.cachedTokens = t.intValue; hasMetrics = true }
                if let turns = result["num_turns"] as? NSNumber { m.numTurns = turns.intValue; hasMetrics = true }
                if let tools = result["tool_calls"] as? NSNumber { m.toolCalls = tools.intValue; hasMetrics = true }
                return .finished(status: (result["status"] as? String) ?? "",
                                 response: nonEmpty(result["response"]),
                                 error: nonEmpty(result["error"]),
                                 conversationID: nonEmpty(result["conversation_id"]),
                                 metrics: hasMetrics ? m : nil)
            default:
                return nil
            }
        }

        // Format 2: Claude Code stream-json (keyed by "type")
        guard let type = json["type"] as? String else { return nil }
        switch type {
        case "system":
            if let sid = nonEmpty(json["session_id"]) {
                return .started(conversationID: sid)
            }
            return nil
        case "stream_event":
            guard let innerEvent = json["event"] as? [String: Any],
                  let innerType = innerEvent["type"] as? String else { return nil }
            switch innerType {
            case "content_block_delta":
                guard let delta = innerEvent["delta"] as? [String: Any],
                      let deltaType = delta["type"] as? String, deltaType == "text_delta",
                      let text = delta["text"] as? String, !text.isEmpty else { return nil }
                return .text(text)
            case "content_block_start":
                guard let block = innerEvent["content_block"] as? [String: Any],
                      let blockType = block["type"] as? String, blockType == "tool_use",
                      let name = nonEmpty(block["name"]) else { return nil }
                let toolInput = block["input"] as? [String: Any]
                let toolId = (block["id"] as? String) ?? UUID().uuidString
                let preview: String
                if name == "Bash" {
                    preview = (toolInput?["command"] as? String) ?? ""
                } else if name == "Edit" || name == "Write" || name == "Read" {
                    preview = (toolInput?["file_path"] as? String) ?? ""
                } else {
                    preview = (toolInput?["description"] as? String) ?? ""
                }
                return .approval(NexusAgentApprovalRequest(id: toolId, toolName: name, commandOrPath: preview, status: .pending))
            default:
                return nil
            }
        case "result":
            var m = NexusAgentTurnMetrics()
            var hasMetrics = false
            if let ms = json["duration_ms"] as? NSNumber {
                m.durationMs = ms.intValue
                hasMetrics = true
            }
            if let cost = json["total_cost_usd"] as? NSNumber {
                m.totalCostUSD = cost.doubleValue
                hasMetrics = true
            }
            if let usage = json["usage"] as? [String: Any] {
                if let t = usage["input_tokens"] as? NSNumber { m.inputTokens = t.intValue; hasMetrics = true }
                if let t = usage["output_tokens"] as? NSNumber { m.outputTokens = t.intValue; hasMetrics = true }
                if let t = usage["cache_read_input_tokens"] as? NSNumber { m.cachedTokens = t.intValue; hasMetrics = true }
                else if let t = usage["cache_read_tokens"] as? NSNumber { m.cachedTokens = t.intValue; hasMetrics = true }
            }
            if let turns = json["num_turns"] as? NSNumber { m.numTurns = turns.intValue; hasMetrics = true }
            let isError = (json["is_error"] as? Bool) ?? false
            let resultText = json["result"] as? String
            return .finished(
                status: (json["stop_reason"] as? String) ?? (isError ? "error" : "completed"),
                response: resultText,
                error: isError ? (resultText ?? "Error") : nil,
                conversationID: nonEmpty(json["session_id"]),
                metrics: hasMetrics ? m : nil
            )
        default:
            return nil
        }
    }

    private static func nonEmpty(_ value: Any?) -> String? {
        guard let text = value as? String, !text.isEmpty else { return nil }
        return text
    }
}

/// Splits a byte stream into complete lines, holding a partial last line
/// (and a UTF-8 sequence cut between reads) until the rest arrives.
public struct NexusAgentLineBuffer {
    private var pending = Data()

    public init() {}

    public mutating func append(_ data: Data) -> [String] {
        pending.append(data)
        var lines: [String] = []
        while let newline = pending.firstIndex(of: 0x0A) {
            let line = pending[pending.startIndex..<newline]
            lines.append(String(decoding: line, as: UTF8.self))
            pending = Data(pending[pending.index(after: newline)...])
        }
        return lines
    }

    /// What is left once the stream has ended.
    public mutating func finish() -> String? {
        defer { pending = Data() }
        guard !pending.isEmpty else { return nil }
        return String(decoding: pending, as: UTF8.self)
    }
}

/// An active subagent executing in the current session.
public struct NexusAgentActiveSubagent: Identifiable, Equatable, Sendable {
    public let id: String
    public let typeName: String
    public let role: String
    public let prompt: String
    public let model: String
    public let isRunning: Bool

    public init(
        id: String,
        typeName: String,
        role: String,
        prompt: String,
        model: String,
        isRunning: Bool = true
    ) {
        self.id = id
        self.typeName = typeName
        self.role = role
        self.prompt = prompt
        self.model = model
        self.isRunning = isRunning
    }
}

/// A tool execution step within an agent response.
public struct NexusAgentToolStep: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let detail: String?
    public let isFinished: Bool

    public init(
        id: String = UUID().uuidString,
        title: String,
        detail: String? = nil,
        isFinished: Bool = true
    ) {
        self.id = id
        self.title = title
        self.detail = detail
        self.isFinished = isFinished
    }
}
