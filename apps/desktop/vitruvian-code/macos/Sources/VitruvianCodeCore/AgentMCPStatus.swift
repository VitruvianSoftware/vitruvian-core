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
// Shared by the standalone Vitruvian Code app and the Code feature of the
// Vitruvian desktop app. Written for Vitruvian and released under MIT by its
// copyright holder on 2026-10-09 (apps/desktop/vitruvian-atrium/UPSTREAM.md).

import Foundation

/// One MCP server a live chat's agent has loaded, as the chat's MCP status panel shows it.
///
/// Each agent owns its MCP configuration: the app passes it no servers, as T3 Code passes none
/// (`mcpServers: []` for agy in `apps/server/src/provider/Drivers/AntigravityDriver.ts`; Claude
/// loads its own settings in `orchestration-v2/Adapters/ClaudeAdapterV2.ts`). The panel only
/// shows what each agent loaded and where it is configured; T3 Code has no such panel.
///
/// Nothing secret is kept here: no command, environment value, header or URL, only the name,
/// the state, the agent's own error text and where the server is configured.
public struct AgentMCPServerStatus: Equatable, Identifiable, Sendable {
    public enum State: String, Equatable, Sendable {
        case connected
        case failed
        case needsSignIn
        case pending
        case disabled
        /// The agent does not report status (agy): the server is configured and switched on.
        case unknown
    }

    /// Where the server is configured.
    public enum Source: Equatable, Sendable {
        /// Claude Code's user settings (`~/.claude.json`, or the Claude config folder's).
        case claudeUser
        /// Claude Code's settings for this project only (also in `~/.claude.json`).
        case claudeLocal
        /// The project's `.mcp.json`.
        case claudeProject
        /// A claude.ai connector.
        case claudeAI
        /// Managed by an organization (`managed-mcp.json`).
        case claudeManaged
        /// A Claude Code plugin.
        case claudePlugin
        /// An agent definition.
        case claudeAgent
        /// Claude Code, where the SDK did not say which part.
        case claudeOther
        /// agy's own settings (`mcp_config.json`).
        case agySettings
    }

    public var name: String
    public var state: State
    /// The agent's error text, for a failed server.
    public var detail: String?
    public var source: Source
    /// The file the server is configured in, to reveal; nil where there is none to show.
    public var configPath: String?

    public var id: String { name }

    public init(name: String, state: State, detail: String? = nil, source: Source, configPath: String? = nil) {
        self.name = name
        self.state = state
        self.detail = detail
        self.source = source
        self.configPath = configPath
    }
}

/// Which agent a chat's panel reads, or none (a command-line chat has no panel).
public enum AgentMCPStatusAgent: Equatable, Sendable {
    case claude
    case agy

    /// The agent for a provider on a connection: Claude on the Agent SDK and agy over ACP. Other
    /// connections report nothing the panel can read.
    public static func of(_ provider: VitruvianCodeCLIProvider, kind: AgentConnectionKind?) -> AgentMCPStatusAgent? {
        switch (provider.route, kind) {
        case (.claude, .claudeSDK?): return .claude
        case (.antigravity, .acp?): return .agy
        default: return nil
        }
    }
}

/// What the chat's MCP status panel shows.
public struct AgentMCPStatusPanel: Equatable, Sendable {
    public enum Problem: Equatable, Sendable {
        /// Claude reports status only for a live session: send a message first.
        case notConnected
        /// Asking failed.
        case failed(String)
    }

    public var agent: AgentMCPStatusAgent
    public var servers: [AgentMCPServerStatus]
    public var isLoading: Bool
    public var problem: Problem?

    public init(agent: AgentMCPStatusAgent, servers: [AgentMCPServerStatus] = [], isLoading: Bool = false,
                problem: Problem? = nil) {
        self.agent = agent
        self.servers = servers
        self.isLoading = isLoading
        self.problem = problem
    }
}

/// Reads each agent's MCP status into panel rows.
public enum AgentMCPStatusReader {
    /// Claude Code's user config: `.claude.json` in the Claude config folder when one is set,
    /// otherwise in the home folder.
    public static func claudeUserConfigPath(home: String, configDirectory: String?) -> String {
        if let folder = configDirectory?.trimmingCharacters(in: .whitespacesAndNewlines), !folder.isEmpty {
            return (folder as NSString).appendingPathComponent(".claude.json")
        }
        return (home as NSString).appendingPathComponent(".claude.json")
    }

    /// Where Claude Code reads an organization's managed MCP config on macOS.
    public static let claudeManagedConfigPath = "/Library/Application Support/ClaudeCode/managed-mcp.json"

    /// Rows from the helper's `_vitruvian/mcpStatus` (the SDK's `mcpServerStatus()`). The source
    /// is the SDK's `source`, or its `scope` on a `claude` too old to send `source`.
    public static func rows(
        fromClaude statuses: [ClaudeMCPServerStatus],
        workingDirectory: String,
        home: String,
        configDirectory: String?
    ) -> [AgentMCPServerStatus] {
        let userConfig = claudeUserConfigPath(home: home, configDirectory: configDirectory)
        return statuses.map { status in
            let state: AgentMCPServerStatus.State
            switch status.status {
            case "connected": state = .connected
            case "failed": state = .failed
            case "needs-auth": state = .needsSignIn
            case "pending": state = .pending
            case "disabled": state = .disabled
            default: state = .unknown
            }
            let source: AgentMCPServerStatus.Source
            let path: String?
            switch (status.source ?? status.scope ?? "").lowercased() {
            case "user":
                (source, path) = (.claudeUser, userConfig)
            case "local":
                (source, path) = (.claudeLocal, userConfig)
            case "project":
                (source, path) = (.claudeProject, (workingDirectory as NSString).appendingPathComponent(".mcp.json"))
            case "claudeai":
                (source, path) = (.claudeAI, nil)
            case "managed", "enterprise":
                (source, path) = (.claudeManaged, claudeManagedConfigPath)
            case "plugin":
                (source, path) = (.claudePlugin, nil)
            case "agent":
                (source, path) = (.claudeAgent, nil)
            default:
                (source, path) = (.claudeOther, nil)
            }
            let error = status.error?.trimmingCharacters(in: .whitespacesAndNewlines)
            return AgentMCPServerStatus(name: status.name, state: state,
                                        detail: state == .failed && error?.isEmpty == false ? error : nil,
                                        source: source, configPath: path)
        }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// agy's MCP config, as `agy mcp list` reads it. agy reports no status over ACP, so the panel
    /// reads this file, read-only, and never writes it.
    public static func agyConfigCandidates(geminiHome: String) -> [String] {
        [
            (geminiHome as NSString).appendingPathComponent("antigravity/mcp_config.json"),
            (geminiHome as NSString).appendingPathComponent("config/mcp_config.json"),
        ]
    }

    /// Rows from agy's `mcp_config.json`: each server's name, and off when it says `disabled`.
    /// Everything else in an entry (command, arguments, environment, headers, URL) is not read.
    public static func rows(fromAgyConfig text: String, path: String) -> [AgentMCPServerStatus] {
        guard let data = text.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let servers = root["mcpServers"] as? [String: Any] else { return [] }
        return servers.keys.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }.compactMap { name in
            guard !name.isEmpty, let entry = servers[name] as? [String: Any] else { return nil }
            let disabled = entry["disabled"] as? Bool == true
            return AgentMCPServerStatus(name: name, state: disabled ? .disabled : .unknown,
                                        source: .agySettings, configPath: path)
        }
    }

    /// agy's rows, read from the first config file there is. Empty when there is none.
    public static func agyRows(
        geminiHome: String,
        fileExists: (String) -> Bool,
        readFile: (String) -> String?
    ) -> [AgentMCPServerStatus] {
        for path in agyConfigCandidates(geminiHome: geminiHome) where fileExists(path) {
            if let text = readFile(path) { return rows(fromAgyConfig: text, path: path) }
        }
        return []
    }
}

/// A live connection that can report its MCP servers' status (Claude on the Agent SDK).
@MainActor
public protocol AgentMCPStatusReporting: AnyObject {
    func mcpStatus() async throws -> [ClaudeMCPServerStatus]
}

extension ClaudeSDKConnection: AgentMCPStatusReporting {}
