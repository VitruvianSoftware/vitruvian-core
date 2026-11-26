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

/// The Claude ACP adapter (`claude-acp` in the ACP registry, `claude-agent-acp`), as T3 Code
/// runs it (`packages/provider-acp-registry/src/server/claudeAcp.ts` and the `isClaude`
/// options in `adapter.ts`, commit d6e5f2e0):
/// * it starts with `CLAUDE_AGENT_ACP_EXPERIMENTAL_V2=1` unless that is already set;
/// * its Agent and Task tool calls are subagents, once their input names a prompt (before
///   that they are provisional and shown as nothing);
/// * a subagent asked to run in the background, or one Claude reports as async, stays running
///   after its tool call completes;
/// * `subagent_update` (a child session's state) and `session_message` (a delegation whose id
///   is the Agent call's tool-use id) move that subagent on.
///
/// Recorded from claude-acp 0.112.0 (`testdata/acp/claude-acp-subagent.ndjson`): the call comes
/// as a `tool_call` titled "Task" with `_meta.claudeCode.toolName` "Agent", its input arrives
/// over several `tool_call_update`s, and it ends `completed`.
public enum ClaudeACPAdapter {
    public static let registryAgentID = "claude-acp"
    public static let experimentalV2Key = "CLAUDE_AGENT_ACP_EXPERIMENTAL_V2"

    /// The adapter's environment: `base`, with T3 Code's V2 switch on unless `base` says
    /// otherwise, and `CLAUDE_CONFIG_DIR` when the provider names a Claude config folder.
    public static func environment(base: [String: String], configDirectory: String?) -> [String: String] {
        var environment = base
        if environment[experimentalV2Key] == nil { environment[experimentalV2Key] = "1" }
        if let folder = configDirectory?.trimmingCharacters(in: .whitespacesAndNewlines), !folder.isEmpty {
            environment[ClaudeSDKSupport.configDirectoryKey] = folder
        }
        return environment
    }

    /// The tool's name as Claude gives it (`_meta.claudeCode.toolName`), else its title.
    static func toolName(meta: [String: ACPJSONValue]?, title: String?) -> String? {
        meta?["claudeCode"]?.objectValue?["toolName"]?.stringValue ?? meta?["toolName"]?.stringValue ?? title
    }
}

/// Follows one Claude chat's tool calls and turns its subagents into `AgentEvent.subagent`.
/// Tool calls arrive in pieces, so each is put together here before it is judged.
@MainActor
public final class ClaudeSubagentTracker {
    private struct Call {
        var name: String?
        var title: String?
        var status: String?
        var input: [String: ACPJSONValue] = [:]
        var meta: [String: ACPJSONValue] = [:]
    }

    private var calls: [String: Call] = [:]
    /// Subagents already shown, by tool call id: the last one sent for each.
    private var shown: [String: VitruvianCodeActiveSubagent] = [:]
    /// Child sessions, to the Agent call that started them (`session_message` gives the link).
    private var childToCall: [String: String] = [:]

    public init() {}

    /// The subagent event this update makes, if any.
    public func event(for notification: ACPSessionNotification) -> AgentEvent? {
        switch notification.update {
        case .toolCall(let call), .toolCallUpdate(let call):
            return merge(call)
        case .unknown(let kind, let raw):
            return childEvent(kind: kind, raw: raw, sessionID: notification.sessionId)
        default:
            return nil
        }
    }

    private func merge(_ update: ACPToolCall) -> AgentEvent? {
        var call = calls[update.toolCallId] ?? Call()
        if let meta = update._meta {
            call.meta.merge(meta) { _, new in new }
            if let name = ClaudeACPAdapter.toolName(meta: meta, title: nil) { call.name = name }
        }
        if let title = update.title { call.title = title }
        if call.name == nil { call.name = update.title }
        if let status = update.status { call.status = status }
        if let input = update.rawInput?.objectValue { call.input.merge(input) { _, new in new } }
        calls[update.toolCallId] = call

        guard call.name == "Agent" || call.name == "Task" else { return nil }
        // Provisional until the input names a prompt (`isClaudeProvisionalSubagentTool`).
        guard let prompt = call.input["prompt"]?.stringValue else { return nil }
        let background = call.input["run_in_background"]?.boolValue == true
            || call.meta["claudeCode"]?.objectValue?["toolResponse"]?.objectValue?["isAsync"]?.boolValue == true
        let running: Bool
        switch call.status {
        case "failed": running = false
        case "completed": running = background
        default: running = true
        }
        let subagent = VitruvianCodeActiveSubagent(
            id: update.toolCallId,
            typeName: "subagent",
            role: call.input["description"]?.stringValue ?? call.title ?? "Agent",
            prompt: prompt,
            model: call.input["model"]?.stringValue ?? "",
            isRunning: running
        )
        return show(subagent)
    }

    /// `subagent_update` and `session_message` (`extractClaudeSubagentSessionEvent`).
    private func childEvent(kind: String, raw: ACPJSONValue, sessionID: String) -> AgentEvent? {
        guard let object = raw.objectValue else { return nil }
        switch kind {
        case "session_message":
            // A delegation into a child session: its id is the Agent call's tool-use id.
            guard let callID = object["messageId"]?.stringValue else { return nil }
            childToCall[sessionID] = callID
            return nil
        case "subagent_update":
            guard let child = object["sessionId"]?.stringValue,
                  let state = object["state"]?.objectValue,
                  let stateName = state["state"]?.stringValue,
                  let callID = childToCall[child],
                  let current = shown[callID] else { return nil }
            let running = stateName == "running" || stateName == "requires_action"
            let updated = VitruvianCodeActiveSubagent(id: current.id, typeName: current.typeName, role: current.role,
                                                      prompt: current.prompt, model: current.model, isRunning: running)
            return show(updated)
        default:
            return nil
        }
    }

    private func show(_ subagent: VitruvianCodeActiveSubagent) -> AgentEvent? {
        guard shown[subagent.id] != subagent else { return nil }
        shown[subagent.id] = subagent
        return .subagent(subagent, started: subagent.isRunning)
    }
}
