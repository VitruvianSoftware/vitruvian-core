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

import Combine
import Foundation

// MARK: - 27-Agent CLI Harness Catalog & Stream Parsers

/// The wire format emitted by an agent CLI's non-interactive or streaming mode.
public enum NexusAgentStreamDialect: String, CaseIterable, Codable, Equatable, Sendable {
    case antigravityJSON
    case claudeStreamJSON
    case codexJSONL
    case geminiStreamJSON
    case opencodeJSON
    case cursorAgentJSON
    case plainText
}

/// A catalog preset describing one of the supported coding agent CLIs.
public struct NexusAgentCatalogPreset: Identifiable, Equatable, Sendable, Codable {
    public var id: String
    public var name: String
    public var executableName: String
    public var commandTemplate: String
    public var defaultModels: [String]
    public var streamDialect: NexusAgentStreamDialect
    public var supportsResumeFlag: String?
    public var websiteURL: String

    public init(
        id: String,
        name: String,
        executableName: String,
        commandTemplate: String,
        defaultModels: [String] = [],
        streamDialect: NexusAgentStreamDialect = .plainText,
        supportsResumeFlag: String? = nil,
        websiteURL: String = ""
    ) {
        self.id = id
        self.name = name
        self.executableName = executableName
        self.commandTemplate = commandTemplate
        self.defaultModels = defaultModels
        self.streamDialect = streamDialect
        self.supportsResumeFlag = supportsResumeFlag
        self.websiteURL = websiteURL
    }
}

/// Normalized event decoded from a Codex JSONL or Gemini stream-json line.
public struct NexusAgentParsedEvent: Equatable, Sendable {
    public enum Kind: String, Equatable, Sendable, Codable {
        case started
        case text
        case thinking
        case toolUse
        case toolResult
        case finished
        case error
    }

    public var kind: Kind
    public var sessionID: String?
    public var text: String?
    public var toolName: String?
    public var toolCallID: String?
    public var isError: Bool
    public var inputTokens: Int?
    public var outputTokens: Int?

    public init(
        kind: Kind,
        sessionID: String? = nil,
        text: String? = nil,
        toolName: String? = nil,
        toolCallID: String? = nil,
        isError: Bool = false,
        inputTokens: Int? = nil,
        outputTokens: Int? = nil
    ) {
        self.kind = kind
        self.sessionID = sessionID
        self.text = text
        self.toolName = toolName
        self.toolCallID = toolCallID
        self.isError = isError
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
    }

    /// Converts the parsed event into the shared `NexusAgentStreamEvent` representation.
    public var streamEvent: NexusAgentStreamEvent {
        switch kind {
        case .started:
            return .started(conversationID: sessionID)
        case .text:
            return .text(text ?? "")
        case .thinking:
            return .thinking(text ?? "")
        case .toolUse:
            return .tool(name: toolName ?? "tool", finished: false)
        case .toolResult:
            if let callID = toolCallID, !callID.isEmpty {
                return .toolStepResult(id: callID, output: text, isError: isError)
            }
            return .tool(name: toolName ?? "tool", finished: true)
        case .finished:
            let metrics: NexusAgentTurnMetrics?
            if inputTokens != nil || outputTokens != nil {
                metrics = NexusAgentTurnMetrics(inputTokens: inputTokens, outputTokens: outputTokens)
            } else {
                metrics = nil
            }
            return .finished(
                status: "completed",
                response: text,
                error: nil,
                conversationID: sessionID,
                metrics: metrics
            )
        case .error:
            return .finished(
                status: "error",
                response: nil,
                error: text ?? "Error",
                conversationID: sessionID,
                metrics: nil
            )
        }
    }
}

/// Catalog of all Orca-supported coding agent CLIs and their stream parsers.
public enum NexusAgentCatalog {
    public static let allPresets: [NexusAgentCatalogPreset] = [
        NexusAgentCatalogPreset(
            id: "claude-code",
            name: "Claude Code",
            executableName: "claude",
            commandTemplate: "claude -p \"{prompt}\"",
            defaultModels: ["claude-opus-5-5", "claude-sonnet-5-5", "claude-haiku-5-5"],
            streamDialect: .claudeStreamJSON,
            supportsResumeFlag: "--resume",
            websiteURL: "https://docs.anthropic.com/en/docs/claude-code"
        ),
        NexusAgentCatalogPreset(
            id: "codex",
            name: "Codex",
            executableName: "codex",
            commandTemplate: "codex exec --json \"{prompt}\"",
            defaultModels: ["gpt-5.3-codex", "gpt-5.4", "o4-mini"],
            streamDialect: .codexJSONL,
            supportsResumeFlag: "resume",
            websiteURL: "https://github.com/openai/codex"
        ),
        NexusAgentCatalogPreset(
            id: "grok-cli",
            name: "Grok CLI",
            executableName: "grok",
            commandTemplate: "grok -p \"{prompt}\"",
            defaultModels: ["grok-4", "grok-3-mini"],
            streamDialect: .plainText,
            supportsResumeFlag: "--resume",
            websiteURL: "https://x.ai"
        ),
        NexusAgentCatalogPreset(
            id: "gemini-cli",
            name: "Gemini CLI",
            executableName: "gemini",
            commandTemplate: "gemini -p \"{prompt}\" --output-format stream-json",
            defaultModels: ["gemini-2.5-pro", "gemini-2.5-flash"],
            streamDialect: .geminiStreamJSON,
            supportsResumeFlag: "--resume",
            websiteURL: "https://github.com/google-gemini/gemini-cli"
        ),
        NexusAgentCatalogPreset(
            id: "cursor-cli",
            name: "Cursor CLI",
            executableName: "cursor-agent",
            commandTemplate: "cursor-agent -p \"{prompt}\" --output-format stream-json",
            defaultModels: ["claude-sonnet-5-5", "gpt-5.4"],
            streamDialect: .cursorAgentJSON,
            supportsResumeFlag: "--resume",
            websiteURL: "https://cursor.com"
        ),
        NexusAgentCatalogPreset(
            id: "github-copilot-cli",
            name: "GitHub Copilot CLI",
            executableName: "copilot",
            commandTemplate: "copilot -p \"{prompt}\"",
            defaultModels: ["claude-sonnet-5-5", "gpt-5.4"],
            streamDialect: .plainText,
            supportsResumeFlag: "--resume",
            websiteURL: "https://github.com/features/copilot/cli"
        ),
        NexusAgentCatalogPreset(
            id: "opencode",
            name: "OpenCode",
            executableName: "opencode",
            commandTemplate: "opencode run --format json \"{prompt}\"",
            defaultModels: ["anthropic/claude-opus-5-5", "anthropic/claude-sonnet-5-5", "openai/gpt-5.4"],
            streamDialect: .opencodeJSON,
            supportsResumeFlag: "--session",
            websiteURL: "https://opencode.ai"
        ),
        NexusAgentCatalogPreset(
            id: "amp",
            name: "Amp",
            executableName: "amp",
            commandTemplate: "amp -x \"{prompt}\" --stream-json",
            defaultModels: ["claude-sonnet-5-5", "claude-opus-5-5"],
            streamDialect: .claudeStreamJSON,
            supportsResumeFlag: "threads continue",
            websiteURL: "https://ampcode.com"
        ),
        NexusAgentCatalogPreset(
            id: "openclaude",
            name: "OpenClaude",
            executableName: "openclaude",
            commandTemplate: "openclaude -p \"{prompt}\"",
            defaultModels: ["claude-sonnet-5-5"],
            streamDialect: .claudeStreamJSON,
            supportsResumeFlag: "--resume",
            websiteURL: "https://github.com/openclaude/openclaude"
        ),
        NexusAgentCatalogPreset(
            id: "antigravity",
            name: "Antigravity",
            executableName: "agy",
            commandTemplate: "agy -p \"{prompt}\" --output-format stream-json --dangerously-skip-permissions",
            defaultModels: ["gemini-4-argon-high", "claude-opus-5-5-high"],
            streamDialect: .antigravityJSON,
            supportsResumeFlag: "--conversation",
            websiteURL: "https://antigravity.google"
        ),
        NexusAgentCatalogPreset(
            id: "pi",
            name: "Pi",
            executableName: "pi",
            commandTemplate: "pi -p \"{prompt}\"",
            defaultModels: ["claude-sonnet-5-5", "gpt-5.4"],
            streamDialect: .plainText,
            supportsResumeFlag: "--resume",
            websiteURL: "https://buildwithpi.ai"
        ),
        NexusAgentCatalogPreset(
            id: "oh-my-pi",
            name: "oh-my-pi",
            executableName: "omp",
            commandTemplate: "omp -p \"{prompt}\"",
            defaultModels: ["claude-sonnet-5-5"],
            streamDialect: .plainText,
            supportsResumeFlag: "--resume",
            websiteURL: "https://github.com/oh-my-pi/omp"
        ),
        NexusAgentCatalogPreset(
            id: "hermes-agent",
            name: "Hermes Agent",
            executableName: "hermes",
            commandTemplate: "hermes run \"{prompt}\"",
            defaultModels: ["hermes-4-70b", "claude-sonnet-5-5"],
            streamDialect: .plainText,
            supportsResumeFlag: "--resume",
            websiteURL: "https://nousresearch.com"
        ),
        NexusAgentCatalogPreset(
            id: "devin-cli",
            name: "Devin CLI",
            executableName: "devin",
            commandTemplate: "devin run \"{prompt}\"",
            defaultModels: ["devin-2"],
            streamDialect: .plainText,
            supportsResumeFlag: "--resume",
            websiteURL: "https://devin.ai"
        ),
        NexusAgentCatalogPreset(
            id: "goose",
            name: "Goose",
            executableName: "goose",
            commandTemplate: "goose run -t \"{prompt}\"",
            defaultModels: ["claude-sonnet-5-5", "gpt-5.4"],
            streamDialect: .plainText,
            supportsResumeFlag: "session --resume",
            websiteURL: "https://block.github.io/goose"
        ),
        NexusAgentCatalogPreset(
            id: "auggie",
            name: "Auggie",
            executableName: "auggie",
            commandTemplate: "auggie --print \"{prompt}\"",
            defaultModels: ["augment-agent"],
            streamDialect: .plainText,
            supportsResumeFlag: "--resume",
            websiteURL: "https://augmentcode.com"
        ),
        NexusAgentCatalogPreset(
            id: "autohand-code",
            name: "Autohand Code",
            executableName: "autohand",
            commandTemplate: "autohand -p \"{prompt}\"",
            defaultModels: ["claude-sonnet-5-5"],
            streamDialect: .plainText,
            supportsResumeFlag: nil,
            websiteURL: "https://autohand.ai"
        ),
        NexusAgentCatalogPreset(
            id: "charm-crush",
            name: "Charm Crush",
            executableName: "crush",
            commandTemplate: "crush run \"{prompt}\"",
            defaultModels: ["claude-sonnet-5-5", "gpt-5.4"],
            streamDialect: .plainText,
            supportsResumeFlag: nil,
            websiteURL: "https://charm.sh/crush"
        ),
        NexusAgentCatalogPreset(
            id: "cline-cli",
            name: "Cline CLI",
            executableName: "cline",
            commandTemplate: "cline -p \"{prompt}\"",
            defaultModels: ["claude-sonnet-5-5"],
            streamDialect: .plainText,
            supportsResumeFlag: "--resume",
            websiteURL: "https://cline.bot"
        ),
        NexusAgentCatalogPreset(
            id: "codebuddy",
            name: "CodeBuddy",
            executableName: "codebuddy",
            commandTemplate: "codebuddy -p \"{prompt}\"",
            defaultModels: ["claude-sonnet-5-5"],
            streamDialect: .plainText,
            supportsResumeFlag: nil,
            websiteURL: "https://codebuddy.ai"
        ),
        NexusAgentCatalogPreset(
            id: "codebuff",
            name: "Codebuff",
            executableName: "codebuff",
            commandTemplate: "codebuff \"{prompt}\"",
            defaultModels: ["claude-sonnet-5-5"],
            streamDialect: .plainText,
            supportsResumeFlag: nil,
            websiteURL: "https://codebuff.com"
        ),
        NexusAgentCatalogPreset(
            id: "freebuff",
            name: "Freebuff",
            executableName: "freebuff",
            commandTemplate: "freebuff \"{prompt}\"",
            defaultModels: ["deepseek-v3"],
            streamDialect: .plainText,
            supportsResumeFlag: nil,
            websiteURL: "https://codebuff.com"
        ),
        NexusAgentCatalogPreset(
            id: "command-code",
            name: "Command Code",
            executableName: "cmdcode",
            commandTemplate: "cmdcode -p \"{prompt}\"",
            defaultModels: ["command-a-code"],
            streamDialect: .plainText,
            supportsResumeFlag: nil,
            websiteURL: "https://cohere.com"
        ),
        NexusAgentCatalogPreset(
            id: "continue-cli",
            name: "Continue CLI",
            executableName: "cn",
            commandTemplate: "cn -p \"{prompt}\"",
            defaultModels: ["claude-sonnet-5-5", "gpt-5.4"],
            streamDialect: .plainText,
            supportsResumeFlag: "--resume",
            websiteURL: "https://continue.dev"
        ),
        NexusAgentCatalogPreset(
            id: "droid",
            name: "Droid",
            executableName: "droid",
            commandTemplate: "droid exec \"{prompt}\"",
            defaultModels: ["factory-droid-1"],
            streamDialect: .plainText,
            supportsResumeFlag: "--resume",
            websiteURL: "https://factory.ai"
        ),
        NexusAgentCatalogPreset(
            id: "kilocode",
            name: "Kilocode",
            executableName: "kilocode",
            commandTemplate: "kilocode -p \"{prompt}\"",
            defaultModels: ["claude-sonnet-5-5"],
            streamDialect: .plainText,
            supportsResumeFlag: "--resume",
            websiteURL: "https://kilocode.ai"
        ),
        NexusAgentCatalogPreset(
            id: "kimi-cli",
            name: "Kimi CLI",
            executableName: "kimi",
            commandTemplate: "kimi -p \"{prompt}\"",
            defaultModels: ["kimi-k2"],
            streamDialect: .plainText,
            supportsResumeFlag: "--resume",
            websiteURL: "https://kimi.ai"
        ),
        NexusAgentCatalogPreset(
            id: "kiro-cli",
            name: "Kiro CLI",
            executableName: "kiro-cli",
            commandTemplate: "kiro-cli chat --no-interactive \"{prompt}\"",
            defaultModels: ["claude-sonnet-5-5"],
            streamDialect: .plainText,
            supportsResumeFlag: "--resume",
            websiteURL: "https://kiro.dev"
        ),
        NexusAgentCatalogPreset(
            id: "mistral-vibe",
            name: "Mistral Vibe",
            executableName: "vibe",
            commandTemplate: "vibe -p \"{prompt}\"",
            defaultModels: ["codestral-latest", "devstral-medium"],
            streamDialect: .plainText,
            supportsResumeFlag: nil,
            websiteURL: "https://mistral.ai"
        ),
        NexusAgentCatalogPreset(
            id: "qwen-code",
            name: "Qwen Code",
            executableName: "qwen",
            commandTemplate: "qwen -p \"{prompt}\" --output-format stream-json",
            defaultModels: ["qwen3-coder-plus"],
            streamDialect: .geminiStreamJSON,
            supportsResumeFlag: "--resume",
            websiteURL: "https://github.com/QwenLM/qwen-code"
        ),
        NexusAgentCatalogPreset(
            id: "rovo-dev",
            name: "Rovo Dev",
            executableName: "acli",
            commandTemplate: "acli rovodev run \"{prompt}\"",
            defaultModels: ["rovodev-default"],
            streamDialect: .plainText,
            supportsResumeFlag: nil,
            websiteURL: "https://atlassian.com/software/rovo"
        ),
    ]

    /// Returns all catalog presets whose executable is found on the machine.
    public static func installedPresets(
        pathVariable: String,
        home: String,
        isExecutable: (String) -> Bool,
        fileExists: (String) -> Bool
    ) -> [NexusAgentCatalogPreset] {
        allPresets.filter { preset in
            NexusAgentSupport.locateChatProgram(
                named: preset.executableName,
                environment: ["PATH": pathVariable],
                home: home,
                isExecutable: isExecutable,
                fileExists: fileExists
            ) != nil
        }
    }

    /// Converts a catalog preset into a `NexusAgentCLIProvider`.
    public static func toCLIProvider(_ preset: NexusAgentCatalogPreset) -> NexusAgentCLIProvider {
        switch preset.id {
        case "antigravity":
            return .antigravity
        case "claude-code":
            return .claude
        case "opencode":
            return .opencode
        default:
            return NexusAgentCLIProvider(
                id: deterministicUUID(for: preset.id),
                name: preset.name,
                commandTemplate: preset.commandTemplate,
                isBuiltIn: false
            )
        }
    }

    private static func deterministicUUID(for seed: String) -> UUID {
        var bytes = [UInt8](repeating: 0, count: 16)
        let utf8 = Array(seed.utf8)
        for (index, byte) in utf8.enumerated() {
            bytes[index % 16] = bytes[index % 16] ^ byte &+ UInt8((index * 31) & 0xFF)
        }
        bytes[6] = (bytes[6] & 0x0F) | 0x50
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }

    /// Parses one line of `codex exec --json` JSONL output.
    public static func parseCodexEventLine(_ line: String) -> NexusAgentParsedEvent? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let data = trimmed.data(using: .utf8),
              let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let type = json["type"] as? String else {
            return nil
        }

        switch type {
        case "thread.started", "session.created", "init":
            let threadID = nonEmpty(json["thread_id"]) ?? nonEmpty(json["session_id"]) ?? nonEmpty(json["id"])
            return NexusAgentParsedEvent(kind: .started, sessionID: threadID)

        case "message.delta", "agent_message":
            guard let text = nonEmpty(json["delta"]) ?? nonEmpty(json["text"]) else { return nil }
            return NexusAgentParsedEvent(kind: .text, text: text)

        case "item.started", "item.updated", "item.completed":
            guard let item = json["item"] as? [String: Any],
                  let itemType = item["type"] as? String else { return nil }
            let itemID = nonEmpty(item["id"])
            switch itemType {
            case "agent_message", "message":
                guard let text = nonEmpty(item["text"]) ?? nonEmpty(item["content"]) else { return nil }
                return NexusAgentParsedEvent(kind: .text, text: text)
            case "reasoning", "thinking":
                guard let text = nonEmpty(item["text"]) ?? nonEmpty(item["summary"]) else { return nil }
                return NexusAgentParsedEvent(kind: .thinking, text: text)
            case "command_execution", "tool_call", "mcp_tool_call":
                let name = nonEmpty(item["tool_name"]) ?? nonEmpty(item["name"]) ?? nonEmpty(item["command"]) ?? "command"
                if type == "item.completed" {
                    let output = nonEmpty(item["aggregated_output"]) ?? nonEmpty(item["output"])
                    let exitCode = (item["exit_code"] as? NSNumber)?.intValue ?? 0
                    return NexusAgentParsedEvent(
                        kind: .toolResult,
                        text: output,
                        toolName: name,
                        toolCallID: itemID,
                        isError: exitCode != 0
                    )
                }
                return NexusAgentParsedEvent(kind: .toolUse, toolName: name, toolCallID: itemID)
            default:
                return nil
            }

        case "turn.completed", "result":
            let usage = json["usage"] as? [String: Any]
            let input = (usage?["input_tokens"] as? NSNumber)?.intValue
            let output = (usage?["output_tokens"] as? NSNumber)?.intValue
            let response = nonEmpty(json["response"]) ?? nonEmpty(json["text"])
            let threadID = nonEmpty(json["thread_id"]) ?? nonEmpty(json["session_id"])
            return NexusAgentParsedEvent(
                kind: .finished,
                sessionID: threadID,
                text: response,
                inputTokens: input,
                outputTokens: output
            )

        case "turn.failed", "error":
            let nested = json["error"] as? [String: Any]
            let message = nonEmpty(json["message"]) ?? nonEmpty(nested?["message"]) ?? nonEmpty(json["error"]) ?? "Codex error"
            return NexusAgentParsedEvent(kind: .error, text: message, isError: true)

        default:
            return nil
        }
    }

    /// Parses one line of `gemini --output-format stream-json` or `qwen --output-format stream-json`.
    public static func parseGeminiEventLine(_ line: String) -> NexusAgentParsedEvent? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let data = trimmed.data(using: .utf8),
              let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let type = (json["type"] as? String) ?? (json["event"] as? String) else {
            return nil
        }

        let sessionID = nonEmpty(json["session_id"]) ?? nonEmpty(json["conversation_id"])
        switch type {
        case "init", "session_start":
            return NexusAgentParsedEvent(kind: .started, sessionID: sessionID)

        case "message", "content_delta", "text":
            let role = (json["role"] as? String)?.lowercased() ?? "assistant"
            if role == "user" { return nil }
            guard let content = nonEmpty(json["content"]) ?? nonEmpty(json["text"]) ?? nonEmpty(json["delta"]) else {
                return nil
            }
            return NexusAgentParsedEvent(kind: .text, sessionID: sessionID, text: content)

        case "thought", "thinking":
            guard let thought = nonEmpty(json["thought"]) ?? nonEmpty(json["text"]) ?? nonEmpty(json["content"]) else {
                return nil
            }
            return NexusAgentParsedEvent(kind: .thinking, sessionID: sessionID, text: thought)

        case "tool_use", "tool_call":
            let name = nonEmpty(json["name"]) ?? nonEmpty(json["tool_name"]) ?? "tool"
            let callID = nonEmpty(json["id"]) ?? nonEmpty(json["call_id"]) ?? nonEmpty(json["tool_id"])
            return NexusAgentParsedEvent(kind: .toolUse, sessionID: sessionID, toolName: name, toolCallID: callID)

        case "tool_result":
            let callID = nonEmpty(json["id"]) ?? nonEmpty(json["call_id"]) ?? nonEmpty(json["tool_id"])
            let output = nonEmpty(json["output"]) ?? nonEmpty(json["result"]) ?? nonEmpty(json["error"])
            let isError = (json["is_error"] as? Bool) ?? ((json["status"] as? String)?.lowercased() == "error")
            return NexusAgentParsedEvent(
                kind: .toolResult,
                sessionID: sessionID,
                text: output,
                toolName: nonEmpty(json["name"]) ?? nonEmpty(json["tool_name"]),
                toolCallID: callID,
                isError: isError
            )

        case "result", "done":
            let status = (json["status"] as? String)?.lowercased() ?? "success"
            if status == "error" || status == "failed" {
                let err = nonEmpty(json["error"]) ?? nonEmpty(json["message"]) ?? "Gemini CLI error"
                return NexusAgentParsedEvent(kind: .error, sessionID: sessionID, text: err, isError: true)
            }
            let stats = (json["stats"] as? [String: Any]) ?? (json["usage"] as? [String: Any])
            let input = (stats?["input_tokens"] as? NSNumber)?.intValue
            let output = (stats?["output_tokens"] as? NSNumber)?.intValue
            let response = nonEmpty(json["response"]) ?? nonEmpty(json["result"])
            return NexusAgentParsedEvent(
                kind: .finished,
                sessionID: sessionID,
                text: response,
                inputTokens: input,
                outputTokens: output
            )

        case "error":
            let nested = json["error"] as? [String: Any]
            let message = nonEmpty(json["error"]) ?? nonEmpty(nested?["message"]) ?? nonEmpty(json["message"]) ?? "Gemini CLI error"
            return NexusAgentParsedEvent(kind: .error, sessionID: sessionID, text: message, isError: true)

        default:
            return nil
        }
    }

    private static func nonEmpty(_ value: Any?) -> String? {
        guard let text = value as? String, !text.isEmpty else { return nil }
        return text
    }
}

// MARK: - Multi-Account Switcher & 5h/7d Dual Quota

/// Tracks both the 5-hour burst window and 7-day rolling usage window for an agent account.
public struct NexusAgentDualQuotaWindow: Equatable, Sendable, Codable {
    public var fiveHourUsedPercent: Double
    public var fiveHourResetsAt: Date?
    public var sevenDayUsedPercent: Double
    public var sevenDayResetsAt: Date?
    public var planTier: String?

    public init(
        fiveHourUsedPercent: Double,
        fiveHourResetsAt: Date? = nil,
        sevenDayUsedPercent: Double,
        sevenDayResetsAt: Date? = nil,
        planTier: String? = nil
    ) {
        self.fiveHourUsedPercent = min(100, max(0, fiveHourUsedPercent))
        self.fiveHourResetsAt = fiveHourResetsAt
        self.sevenDayUsedPercent = min(100, max(0, sevenDayUsedPercent))
        self.sevenDayResetsAt = sevenDayResetsAt
        self.planTier = planTier
    }

    public var isNearLimit: Bool {
        fiveHourUsedPercent >= 80.0 || sevenDayUsedPercent >= 80.0
    }

    public func fiveHourResetCountdown(from now: Date = Date()) -> String {
        Self.formatCountdown(until: fiveHourResetsAt, from: now)
    }

    public func sevenDayResetCountdown(from now: Date = Date()) -> String {
        Self.formatCountdown(until: sevenDayResetsAt, from: now)
    }

    private static func formatCountdown(until target: Date?, from now: Date) -> String {
        guard let target else { return "—" }
        let remaining = Int(target.timeIntervalSince(now))
        guard remaining > 0 else { return "now" }
        let days = remaining / 86_400
        let hours = (remaining % 86_400) / 3_600
        let minutes = (remaining % 3_600) / 60
        if days > 0 { return "\(days)d \(hours)h" }
        if hours > 0 { return "\(hours)h \(minutes)m" }
        return "\(max(1, minutes))m"
    }
}

/// A saved account credential profile for a CLI provider.
public struct NexusAgentAccountProfile: Identifiable, Equatable, Sendable, Codable {
    public var id: UUID
    public var providerName: String
    public var accountLabel: String
    public var emailOrHandle: String
    public var credentialFilePath: String
    public var isActive: Bool
    public var quota: NexusAgentDualQuotaWindow?

    public init(
        id: UUID = UUID(),
        providerName: String,
        accountLabel: String,
        emailOrHandle: String,
        credentialFilePath: String,
        isActive: Bool = false,
        quota: NexusAgentDualQuotaWindow? = nil
    ) {
        self.id = id
        self.providerName = providerName
        self.accountLabel = accountLabel
        self.emailOrHandle = emailOrHandle
        self.credentialFilePath = credentialFilePath
        self.isActive = isActive
        self.quota = quota
    }
}

/// Manages multi-account credential profiles and 5h/7d usage windows in `stateDirectory`.
@MainActor
public final class NexusAgentAccountManager: ObservableObject {
    @Published public private(set) var profiles: [NexusAgentAccountProfile] = []
    @Published public var targetCredentialPaths: [String: String]

    public let stateDirectory: String
    private let readFile: (String) -> String?
    private let writePrivateFile: (String, String) -> Bool

    public var profilesFilePath: String {
        (stateDirectory as NSString).appendingPathComponent("accounts.json")
    }

    public init(
        stateDirectory: String,
        targetCredentialPaths: [String: String] = [:],
        readFile: @escaping (String) -> String?,
        writePrivateFile: @escaping (String, String) -> Bool
    ) {
        self.stateDirectory = stateDirectory
        self.targetCredentialPaths = targetCredentialPaths
        self.readFile = readFile
        self.writePrivateFile = writePrivateFile
        load()
    }

    public func load() {
        guard let raw = readFile(profilesFilePath),
              let data = raw.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([NexusAgentAccountProfile].self, from: data) else {
            profiles = []
            return
        }
        profiles = decoded
    }

    @discardableResult
    public func save() -> Bool {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(profiles),
              let text = String(data: data, encoding: .utf8) else {
            return false
        }
        return writePrivateFile(profilesFilePath, text)
    }

    @discardableResult
    public func addProfile(_ profile: NexusAgentAccountProfile) -> Bool {
        var next = profile
        let hasActiveForProvider = profiles.contains {
            $0.providerName.caseInsensitiveCompare(profile.providerName) == .orderedSame && $0.isActive
        }
        if !hasActiveForProvider {
            next.isActive = true
        } else if next.isActive {
            for index in profiles.indices where profiles[index].providerName.caseInsensitiveCompare(profile.providerName) == .orderedSame {
                profiles[index].isActive = false
            }
        }
        if let existingIndex = profiles.firstIndex(where: { $0.id == next.id }) {
            profiles[existingIndex] = next
        } else {
            profiles.append(next)
        }
        return save()
    }

    @discardableResult
    public func removeProfile(id: UUID) -> Bool {
        profiles.removeAll { $0.id == id }
        return save()
    }

    /// Switches the active profile for its provider by copying its credential snapshot into the target config path.
    @discardableResult
    public func switchAccount(id: UUID) -> Bool {
        guard let targetIndex = profiles.firstIndex(where: { $0.id == id }) else {
            return false
        }
        let selected = profiles[targetIndex]
        guard let snapshot = readFile(selected.credentialFilePath) else {
            return false
        }
        let destination = resolvedTargetCredentialPath(for: selected.providerName)
        guard writePrivateFile(destination, snapshot) else {
            return false
        }
        for index in profiles.indices where profiles[index].providerName.caseInsensitiveCompare(selected.providerName) == .orderedSame {
            profiles[index].isActive = (profiles[index].id == id)
        }
        return save()
    }

    @discardableResult
    public func updateQuota(id: UUID, quota: NexusAgentDualQuotaWindow) -> Bool {
        guard let index = profiles.firstIndex(where: { $0.id == id }) else {
            return false
        }
        profiles[index].quota = quota
        return save()
    }

    public func activeProfile(for providerName: String) -> NexusAgentAccountProfile? {
        profiles.first {
            $0.providerName.caseInsensitiveCompare(providerName) == .orderedSame && $0.isActive
        }
    }

    public func resolvedTargetCredentialPath(for providerName: String) -> String {
        if let configured = targetCredentialPaths[providerName], !configured.isEmpty {
            return configured
        }
        let slug = providerName.lowercased()
            .replacingOccurrences(of: " ", with: "-")
        return (stateDirectory as NSString).appendingPathComponent("active-credentials-\(slug).json")
    }
}

// MARK: - Unified Agent Inbox & Telemetry

/// An actionable notification item in the Unified Agent Inbox.
public struct NexusAgentInboxEntry: Identifiable, Equatable, Sendable, Codable {
    public enum Category: String, CaseIterable, Equatable, Sendable, Codable {
        case needsApproval
        case waitingForInput
        case completed
        case failed
    }

    public var id: UUID
    public var sessionID: String?
    public var worktreeName: String?
    public var providerName: String
    public var title: String
    public var summary: String
    public var category: Category
    public var timestamp: Date
    public var isRead: Bool

    public init(
        id: UUID = UUID(),
        sessionID: String? = nil,
        worktreeName: String? = nil,
        providerName: String,
        title: String,
        summary: String,
        category: Category,
        timestamp: Date = Date(),
        isRead: Bool = false
    ) {
        self.id = id
        self.sessionID = sessionID
        self.worktreeName = worktreeName
        self.providerName = providerName
        self.title = title
        self.summary = summary
        self.category = category
        self.timestamp = timestamp
        self.isRead = isRead
    }
}

/// Aggregate fleet telemetry displayed in the Unified Inbox header.
public struct NexusAgentFleetStats: Equatable, Sendable, Codable {
    public var agentsSpawned: Int
    public var totalAgentSeconds: Int
    public var prsCreated: Int
    public var activeWorktrees: Int

    public init(
        agentsSpawned: Int = 0,
        totalAgentSeconds: Int = 0,
        prsCreated: Int = 0,
        activeWorktrees: Int = 0
    ) {
        self.agentsSpawned = max(0, agentsSpawned)
        self.totalAgentSeconds = max(0, totalAgentSeconds)
        self.prsCreated = max(0, prsCreated)
        self.activeWorktrees = max(0, activeWorktrees)
    }

    public var formattedAgentTime: String {
        let hours = totalAgentSeconds / 3_600
        let minutes = (totalAgentSeconds % 3_600) / 60
        let seconds = totalAgentSeconds % 60
        if hours > 0 { return "\(hours)h \(minutes)m" }
        if minutes > 0 { return "\(minutes)m \(seconds)s" }
        return "\(seconds)s"
    }
}

/// Collects agent turn completions, failures, and approval requests across all active worktrees.
@MainActor
public final class NexusAgentInboxCenter: ObservableObject {
    @Published public private(set) var entries: [NexusAgentInboxEntry]
    @Published public var stats: NexusAgentFleetStats

    public var unreadCount: Int {
        entries.filter { !$0.isRead }.count
    }

    public init(
        entries: [NexusAgentInboxEntry] = [],
        stats: NexusAgentFleetStats = NexusAgentFleetStats()
    ) {
        self.entries = entries
        self.stats = stats
    }

    public func recordTurnNotice(
        _ notice: NexusAgentTurnNotice,
        sessionID: String?,
        worktreeName: String?,
        durationSeconds: Int
    ) {
        stats.agentsSpawned += 1
        stats.totalAgentSeconds += max(0, durationSeconds)

        let category: NexusAgentInboxEntry.Category = notice.failed ? .failed : .completed
        let title = notice.failed
            ? "\(notice.providerName) — Failed"
            : "\(notice.providerName) — Completed"
        let rawSummary = notice.failed
            ? (notice.failureSummary ?? notice.text)
            : notice.text
        let summary = rawSummary.trimmingCharacters(in: .whitespacesAndNewlines)

        let entry = NexusAgentInboxEntry(
            sessionID: sessionID,
            worktreeName: worktreeName,
            providerName: notice.providerName,
            title: title,
            summary: summary.isEmpty ? (notice.failed ? "Agent turn failed." : "Agent turn completed.") : summary,
            category: category
        )
        entries.insert(entry, at: 0)
    }

    public func recordApprovalNeeded(
        _ notice: NexusAgentTurnNotice,
        sessionID: String?,
        worktreeName: String?
    ) {
        let summary = notice.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let entry = NexusAgentInboxEntry(
            sessionID: sessionID,
            worktreeName: worktreeName,
            providerName: notice.providerName,
            title: "\(notice.providerName) — Approval Required",
            summary: summary.isEmpty ? "Waiting for tool permission approval." : summary,
            category: .needsApproval
        )
        entries.insert(entry, at: 0)
    }

    public func recordWaitingForInput(
        providerName: String,
        prompt: String,
        sessionID: String?,
        worktreeName: String?
    ) {
        let entry = NexusAgentInboxEntry(
            sessionID: sessionID,
            worktreeName: worktreeName,
            providerName: providerName,
            title: "\(providerName) — Waiting for Input",
            summary: prompt,
            category: .waitingForInput
        )
        entries.insert(entry, at: 0)
    }

    public func markRead(id: UUID) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[index].isRead = true
    }

    public func markAllRead() {
        for index in entries.indices {
            entries[index].isRead = true
        }
    }

    public func clearResolved() {
        entries.removeAll { entry in
            entry.category == .completed || entry.category == .failed || entry.isRead
        }
    }
}

// MARK: - GitHub & Linear Tasks Drawer

/// A pull request, GitHub issue, or Linear issue that can spawn a dedicated worktree agent.
public struct NexusAgentTaskItem: Identifiable, Equatable, Sendable, Codable {
    public enum Source: String, CaseIterable, Equatable, Sendable, Codable {
        case githubPR
        case githubIssue
        case linearIssue
    }

    public var id: String
    public var source: Source
    public var numberOrKey: String
    public var title: String
    public var branchName: String
    public var url: String?
    public var statusLabel: String
    public var ciPassing: Bool?
    public var authorOrAssignee: String?

    public init(
        id: String,
        source: Source,
        numberOrKey: String,
        title: String,
        branchName: String,
        url: String? = nil,
        statusLabel: String,
        ciPassing: Bool? = nil,
        authorOrAssignee: String? = nil
    ) {
        self.id = id
        self.source = source
        self.numberOrKey = numberOrKey
        self.title = title
        self.branchName = branchName
        self.url = url
        self.statusLabel = statusLabel
        self.ciPassing = ciPassing
        self.authorOrAssignee = authorOrAssignee
    }
}

/// Parses `gh pr list`, `gh issue list`, and Linear issue payloads and builds worktree launch prompts.
public enum NexusAgentTaskService {
    /// Parses `gh pr list --json number,title,headRefName,url,state,statusCheckRollup,author`.
    public static func parseGitHubPRs(json: String) -> [NexusAgentTaskItem] {
        guard let data = json.data(using: .utf8),
              let array = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] else {
            return []
        }
        return array.compactMap { row in
            let number: String
            if let n = (row["number"] as? NSNumber)?.intValue {
                number = "#\(n)"
            } else if let str = row["number"] as? String, !str.isEmpty {
                number = str.hasPrefix("#") ? str : "#\(str)"
            } else {
                return nil
            }
            guard let title = row["title"] as? String, !title.isEmpty else { return nil }
            let branch = (row["headRefName"] as? String) ?? ""
            let url = row["url"] as? String
            let state = (row["state"] as? String) ?? "OPEN"
            let author = (row["author"] as? [String: Any])?["login"] as? String
            let ciPassing = evaluateStatusCheckRollup(row["statusCheckRollup"])
            var item = NexusAgentTaskItem(
                id: "gh-pr-\(number)",
                source: .githubPR,
                numberOrKey: number,
                title: title,
                branchName: branch,
                url: url,
                statusLabel: state,
                ciPassing: ciPassing,
                authorOrAssignee: author
            )
            if item.branchName.isEmpty {
                item.branchName = suggestedBranchName(for: item)
            }
            return item
        }
    }

    /// Parses `gh issue list --json number,title,url,state,author`.
    public static func parseGitHubIssues(json: String) -> [NexusAgentTaskItem] {
        guard let data = json.data(using: .utf8),
              let array = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] else {
            return []
        }
        return array.compactMap { row in
            let number: String
            if let n = (row["number"] as? NSNumber)?.intValue {
                number = "#\(n)"
            } else if let str = row["number"] as? String, !str.isEmpty {
                number = str.hasPrefix("#") ? str : "#\(str)"
            } else {
                return nil
            }
            guard let title = row["title"] as? String, !title.isEmpty else { return nil }
            let url = row["url"] as? String
            let state = (row["state"] as? String) ?? "OPEN"
            let author = (row["author"] as? [String: Any])?["login"] as? String
            var item = NexusAgentTaskItem(
                id: "gh-issue-\(number)",
                source: .githubIssue,
                numberOrKey: number,
                title: title,
                branchName: "",
                url: url,
                statusLabel: state,
                ciPassing: nil,
                authorOrAssignee: author
            )
            item.branchName = suggestedBranchName(for: item)
            return item
        }
    }

    /// Parses Linear issues JSON array (`identifier`, `title`, `branchName`, `url`, `state`, `assignee`).
    public static func parseLinearIssues(json: String) -> [NexusAgentTaskItem] {
        guard let data = json.data(using: .utf8),
              let array = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] else {
            return []
        }
        return array.compactMap { row in
            guard let key = (row["identifier"] as? String) ?? (row["key"] as? String),
                  !key.isEmpty,
                  let title = row["title"] as? String,
                  !title.isEmpty else {
                return nil
            }
            let branch = (row["branchName"] as? String) ?? ""
            let url = row["url"] as? String
            let state = ((row["state"] as? [String: Any])?["name"] as? String)
                ?? (row["status"] as? String)
                ?? "Todo"
            let assignee = ((row["assignee"] as? [String: Any])?["name"] as? String)
                ?? (row["assignee"] as? String)
            var item = NexusAgentTaskItem(
                id: "linear-\(key)",
                source: .linearIssue,
                numberOrKey: key,
                title: title,
                branchName: branch,
                url: url,
                statusLabel: state,
                ciPassing: nil,
                authorOrAssignee: assignee
            )
            if item.branchName.isEmpty {
                item.branchName = suggestedBranchName(for: item)
            }
            return item
        }
    }

    public static func suggestedBranchName(for item: NexusAgentTaskItem) -> String {
        let trimmedExisting = item.branchName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedExisting.isEmpty { return trimmedExisting }

        let keySlug = item.numberOrKey
            .trimmingCharacters(in: CharacterSet(charactersIn: "# "))
            .lowercased()
        let titleWords = item.title
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .prefix(5)
            .joined(separator: "-")
        let prefix: String
        switch item.source {
        case .githubPR: prefix = "pr"
        case .githubIssue: prefix = "issue"
        case .linearIssue: prefix = "feat"
        }
        if titleWords.isEmpty {
            return "\(prefix)/\(keySlug)"
        }
        return "\(prefix)/\(keySlug)-\(titleWords)"
    }

    public static func worktreePrompt(for item: NexusAgentTaskItem) -> String {
        let branch = suggestedBranchName(for: item)
        let sourceLabel: String
        switch item.source {
        case .githubPR: sourceLabel = "GitHub Pull Request"
        case .githubIssue: sourceLabel = "GitHub Issue"
        case .linearIssue: sourceLabel = "Linear Issue"
        }
        var lines = [
            "Work on \(sourceLabel) \(item.numberOrKey): \(item.title)",
            "Branch: \(branch)",
        ]
        if let url = item.url, !url.isEmpty {
            lines.append("Reference URL: \(url)")
        }
        if let ci = item.ciPassing, !ci {
            lines.append("Note: CI checks are currently failing on this branch. Inspect the failing checks and fix the root cause.")
        }
        return lines.joined(separator: "\n")
    }

    private static func evaluateStatusCheckRollup(_ raw: Any?) -> Bool? {
        guard let checks = raw as? [[String: Any]], !checks.isEmpty else { return nil }
        for check in checks {
            let conclusion = ((check["conclusion"] as? String) ?? (check["state"] as? String) ?? "").uppercased()
            if ["FAILURE", "ERROR", "TIMED_OUT", "CANCELLED", "ACTION_REQUIRED"].contains(conclusion) {
                return false
            }
        }
        return true
    }
}

// MARK: - ⌘K Jump Palette

/// A unified destination in the `⌘K` Spotlight Jump Palette.
public struct NexusAgentJumpTarget: Identifiable, Equatable, Sendable, Codable {
    public enum Kind: String, CaseIterable, Equatable, Sendable, Codable {
        case session
        case worktree
        case slashCommand
        case agentPreset
        case account
        case task
        case file
    }

    public var id: String
    public var kind: Kind
    public var title: String
    public var subtitle: String
    public var badge: String?
    public var payload: String

    public init(
        id: String,
        kind: Kind,
        title: String,
        subtitle: String,
        badge: String? = nil,
        payload: String
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.subtitle = subtitle
        self.badge = badge
        self.payload = payload
    }
}

/// Fuzzy search and ranking engine for the `⌘K` Jump Palette.
public enum NexusAgentJumpSearch {
    public static func filter(
        query: String,
        targets: [NexusAgentJumpTarget],
        limit: Int = 15
    ) -> [NexusAgentJumpTarget] {
        guard limit > 0 else { return [] }
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return Array(targets.prefix(limit))
        }

        let scored: [(target: NexusAgentJumpTarget, score: Int, index: Int)] = targets.enumerated().compactMap { index, target in
            guard let points = score(query: trimmed, target: target) else { return nil }
            return (target, points, index)
        }

        return scored
            .sorted { lhs, rhs in
                if lhs.score != rhs.score { return lhs.score > rhs.score }
                return lhs.index < rhs.index
            }
            .prefix(limit)
            .map(\.target)
    }

    public static func score(query: String, target: NexusAgentJumpTarget) -> Int? {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return 0 }

        let titleScore = matchScore(query: q, candidate: target.title.lowercased(), weight: 3)
        let badgeScore = target.badge.flatMap { matchScore(query: q, candidate: $0.lowercased(), weight: 2) }
        let subtitleScore = matchScore(query: q, candidate: target.subtitle.lowercased(), weight: 1)

        let best = [titleScore, badgeScore, subtitleScore].compactMap { $0 }.max()
        return best
    }

    private static func matchScore(query: String, candidate: String, weight: Int) -> Int? {
        guard !candidate.isEmpty else { return nil }
        if candidate == query {
            return 1_000 * weight
        }
        if candidate.hasPrefix(query) {
            return (800 - min(100, candidate.count)) * weight
        }
        if let boundaryRange = candidate.range(of: query),
           boundaryRange.lowerBound == candidate.startIndex || !candidate[candidate.index(before: boundaryRange.lowerBound)].isLetter {
            let offset = candidate.distance(from: candidate.startIndex, to: boundaryRange.lowerBound)
            return (650 - min(150, offset * 4)) * weight
        }
        if let containsRange = candidate.range(of: query) {
            let offset = candidate.distance(from: candidate.startIndex, to: containsRange.lowerBound)
            return (450 - min(150, offset * 4)) * weight
        }
        if isSubsequence(query, of: candidate) {
            return max(50, (250 - min(150, candidate.count))) * weight
        }
        return nil
    }

    private static func isSubsequence(_ query: String, of candidate: String) -> Bool {
        var queryIndex = query.startIndex
        for char in candidate {
            if char == query[queryIndex] {
                query.formIndex(after: &queryIndex)
                if queryIndex == query.endIndex { return true }
            }
        }
        return false
    }
}
