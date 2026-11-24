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

/// One MCP server in the app's own list. Only what is safe to keep in plain settings is here:
/// its environment values and headers are secrets, kept in `AgentSecrets` under the server's
/// `id`, and only their names are ever shown.
public struct AgentMCPServer: Codable, Equatable, Identifiable, Sendable {
    /// How the agent reaches the server. SSE is left out: the MCP spec deprecates it
    /// (docs/designs/vitruvian-code-acp.md, "Limited or not used").
    public enum Transport: String, Codable, CaseIterable, Equatable, Sendable {
        case stdio
        case http
    }

    /// Where the entry came from.
    public enum Source: String, Codable, Equatable, Sendable {
        /// Imported from `mcpServers` in `~/.claude.json` on first use.
        case claudeCode
        /// Added by the user in Settings.
        case user
    }

    public var id: UUID
    public var name: String
    public var transport: Transport
    /// The program a stdio server runs.
    public var command: String
    /// Its arguments.
    public var arguments: [String]
    /// An HTTP server's URL.
    public var url: String
    public var isEnabled: Bool
    public var source: Source

    public init(
        id: UUID = UUID(),
        name: String,
        transport: Transport,
        command: String = "",
        arguments: [String] = [],
        url: String = "",
        isEnabled: Bool = true,
        source: Source = .user
    ) {
        self.id = id
        self.name = name
        self.transport = transport
        self.command = command
        self.arguments = arguments
        self.url = url
        self.isEnabled = isEnabled
        self.source = source
    }

    /// One line for a list row: "stdio · npx -y server" or "HTTP · https://…".
    public var summary: String {
        switch transport {
        case .stdio:
            return (["stdio ·", command] + [AgentMCPServers.joinArguments(arguments)])
                .filter { !$0.isEmpty }.joined(separator: " ")
        case .http:
            return "HTTP · \(url)"
        }
    }
}

/// The app's MCP settings, kept through the host (`VitruvianCodeHost.mcpSettings`).
public struct AgentMCPSettings: Codable, Equatable, Sendable {
    /// The user's servers, in the order shown.
    public var servers: [AgentMCPServer]
    /// True once `~/.claude.json` has been read, so a server the user removed is not imported
    /// again.
    public var importedClaudeCode: Bool
    /// Registry agents the user allowed to receive these servers, by agent ID. Off for every
    /// agent until the user turns it on (design section 2). Read by `AgentMCPTarget.registry`.
    public var registryAgentsAllowed: [String: Bool]

    public init(
        servers: [AgentMCPServer] = [],
        importedClaudeCode: Bool = false,
        registryAgentsAllowed: [String: Bool] = [:]
    ) {
        self.servers = servers
        self.importedClaudeCode = importedClaudeCode
        self.registryAgentsAllowed = registryAgentsAllowed
    }

    /// Every key may be missing, as in a file a later version reads.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        servers = try container.decodeIfPresent([AgentMCPServer].self, forKey: .servers) ?? []
        importedClaudeCode = try container.decodeIfPresent(Bool.self, forKey: .importedClaudeCode) ?? false
        registryAgentsAllowed = try container.decodeIfPresent([String: Bool].self, forKey: .registryAgentsAllowed) ?? [:]
    }

    private enum CodingKeys: String, CodingKey { case servers, importedClaudeCode, registryAgentsAllowed }

    /// Whether the user turned MCP servers on for this registry agent. False unless they did.
    public func allowsServers(forRegistryAgent agentID: String) -> Bool {
        registryAgentsAllowed[agentID] == true
    }
}

/// Who a session is for, which decides whether it gets the user's servers.
public enum AgentMCPTarget: Equatable, Sendable {
    /// agy over ACP and Claude on the Agent SDK: they get the list with no extra step.
    case builtIn
    /// A registry agent (the Claude ACP adapter, OpenCode, an agent from the ACP registry): it gets
    /// the list only when the user allowed it (`AgentMCPSettings.allowsServers`).
    case registry(agentID: String)
    /// A command-line run: its MCP servers come from the agent's own configuration.
    case none

    /// The target for a provider on a connection.
    public static func of(_ provider: VitruvianCodeCLIProvider, kind: AgentConnectionKind?) -> AgentMCPTarget {
        switch (provider.route, kind) {
        case (.antigravity, .acp?), (.claude, .claudeSDK?):
            return .builtIn
        case (_, .commandLine?), (_, nil):
            return .none
        default:
            return .registry(agentID: provider.id.uuidString)
        }
    }
}

/// A server as a config file describes it, secrets included: what `~/.claude.json` and a
/// project's `.mcp.json` hold under `mcpServers`.
public struct AgentMCPConfigEntry: Equatable, Sendable {
    public var name: String
    public var transport: AgentMCPServer.Transport
    public var command: String
    public var arguments: [String]
    public var url: String
    public var environment: [String: String]
    public var headers: [String: String]

    public init(
        name: String,
        transport: AgentMCPServer.Transport,
        command: String = "",
        arguments: [String] = [],
        url: String = "",
        environment: [String: String] = [:],
        headers: [String: String] = [:]
    ) {
        self.name = name
        self.transport = transport
        self.command = command
        self.arguments = arguments
        self.url = url
        self.environment = environment
        self.headers = headers
    }
}

public extension AgentSessionRequest.MCPServer {
    /// The server's name, whatever its transport.
    var name: String {
        switch self {
        case .stdio(let name, _, _, _), .http(let name, _, _): return name
        }
    }
}

/// The app's MCP server list: importing it, merging the project's servers in, and handing the
/// result to a session (docs/designs/vitruvian-code-acp.md, Step 5).
///
/// Every environment value and header of every server is treated as a secret. A session request
/// carries the servers without them in `mcpServers` and the values in `mcpSecrets`, so a
/// connection that has a channel for secrets (the Claude helper's `_vitruvian/secrets`) uses it,
/// and one that has none (ACP's `session/new`) puts them in the request body and redacts them
/// from its logs. None of them is ever put in a command line or a process environment.
public enum AgentMCPServers {
    /// The user-scope Claude Code configuration.
    public static func claudeUserConfigPath(home: String) -> String {
        (home as NSString).appendingPathComponent(".claude.json")
    }

    /// A project's shared MCP configuration.
    public static func projectConfigPath(workingDirectory: String) -> String {
        (workingDirectory as NSString).appendingPathComponent(".mcp.json")
    }

    // MARK: - Reading config files

    /// The servers under the top-level `mcpServers` of a Claude Code config file, sorted by
    /// name. An entry with no `type` is stdio, as Claude Code reads it. SSE entries, entries of
    /// a type this app does not know, and entries missing their command or URL are skipped.
    /// Text that is not a JSON object gives none.
    public static func entries(fromConfigJSON text: String) -> [AgentMCPConfigEntry] {
        guard let data = text.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let servers = root["mcpServers"] as? [String: Any] else { return [] }
        return servers.keys.sorted().compactMap { name in
            guard !name.isEmpty, let entry = servers[name] as? [String: Any] else { return nil }
            return parseEntry(name: name, entry)
        }
    }

    private static func parseEntry(name: String, _ entry: [String: Any]) -> AgentMCPConfigEntry? {
        let type = (entry["type"] as? String)?.lowercased()
        switch type {
        case nil, "stdio":
            guard let command = entry["command"] as? String, !command.isEmpty else { return nil }
            return AgentMCPConfigEntry(
                name: name,
                transport: .stdio,
                command: command,
                arguments: (entry["args"] as? [Any])?.compactMap { $0 as? String } ?? [],
                environment: stringMap(entry["env"])
            )
        case "http":
            guard let url = entry["url"] as? String, !url.isEmpty else { return nil }
            return AgentMCPConfigEntry(name: name, transport: .http, url: url, headers: stringMap(entry["headers"]))
        default:
            // "sse" is deprecated by the MCP spec; anything else is unknown here.
            return nil
        }
    }

    private static func stringMap(_ value: Any?) -> [String: String] {
        guard let object = value as? [String: Any] else { return [:] }
        var result: [String: String] = [:]
        for (key, value) in object {
            if let text = value as? String {
                result[key] = text
            } else if let number = value as? NSNumber {
                result[key] = number.stringValue
            }
        }
        return result
    }

    // MARK: - Importing on first use

    /// Imports `mcpServers` from `~/.claude.json` once: each server becomes an enabled entry
    /// from Claude Code, its environment values and headers go to `secrets`. Does nothing when
    /// the import already ran, or when there is no file yet (a later first use imports it). A
    /// name already in the list is not imported twice. Returns true when `settings` changed.
    @MainActor
    @discardableResult
    public static func importClaudeCodeServers(
        into settings: inout AgentMCPSettings,
        secrets: AgentSecrets,
        home: String,
        readFile: (String) -> String?
    ) -> Bool {
        guard !settings.importedClaudeCode,
              let text = readFile(claudeUserConfigPath(home: home)) else { return false }
        settings.importedClaudeCode = true
        let known = Set(settings.servers.map(\.name))
        for entry in entries(fromConfigJSON: text) where !known.contains(entry.name) {
            let server = AgentMCPServer(
                name: entry.name,
                transport: entry.transport,
                command: entry.command,
                arguments: entry.arguments,
                url: entry.url,
                isEnabled: true,
                source: .claudeCode
            )
            let stored = secrets.setMCPSecrets(
                AgentSessionRequest.MCPServerSecrets(environment: entry.environment, headers: entry.headers),
                for: server.id
            )
            // A server whose secrets could not be kept would start without them; it is left out
            // rather than added broken.
            if stored { settings.servers.append(server) }
        }
        return true
    }

    /// The host's list, after the first-use import. Nil when the host keeps no MCP list.
    @MainActor
    public static func settings(host: any VitruvianCodeHost, environment: VitruvianCodeEngine.Environment) -> AgentMCPSettings? {
        guard var settings = host.mcpSettings else { return nil }
        if importClaudeCodeServers(into: &settings, secrets: AgentSecrets(environment: environment),
                                   home: environment.home, readFile: environment.readFile) {
            host.mcpSettings = settings
        }
        return settings
    }

    // MARK: - What a session gets

    /// The servers a session starts with, and their secrets by server name.
    public struct SessionServers: Equatable, Sendable {
        public var servers: [AgentSessionRequest.MCPServer]
        public var secrets: [String: AgentSessionRequest.MCPServerSecrets]

        public init(servers: [AgentSessionRequest.MCPServer] = [], secrets: [String: AgentSessionRequest.MCPServerSecrets] = [:]) {
            self.servers = servers
            self.secrets = secrets
        }
    }

    /// The enabled servers of the app's list, then the project's `.mcp.json`; a project server
    /// replaces an app server of the same name, as project scope overrides user scope in Claude
    /// Code. A disabled app server is not passed. `${VAR}` and `${VAR:-default}` in a command,
    /// argument, URL, environment value or header are filled in from `processEnvironment`, as
    /// Claude Code does. A registry agent the user has not allowed, and a command-line run, get
    /// nothing.
    public static func sessionServers(
        settings: AgentMCPSettings,
        secrets: (UUID) -> AgentSessionRequest.MCPServerSecrets,
        projectConfig: String?,
        target: AgentMCPTarget,
        processEnvironment: [String: String]
    ) -> SessionServers {
        switch target {
        case .none:
            return SessionServers()
        case .registry(let agentID):
            guard settings.allowsServers(forRegistryAgent: agentID) else { return SessionServers() }
        case .builtIn:
            break
        }
        var ordered: [AgentMCPConfigEntry] = []
        for server in settings.servers where server.isEnabled && !server.name.isEmpty {
            guard !ordered.contains(where: { $0.name == server.name }) else { continue }
            let secret = secrets(server.id)
            ordered.append(AgentMCPConfigEntry(
                name: server.name,
                transport: server.transport,
                command: server.command,
                arguments: server.arguments,
                url: server.url,
                environment: secret.environment,
                headers: secret.headers
            ))
        }
        for entry in entries(fromConfigJSON: projectConfig ?? "") {
            if let index = ordered.firstIndex(where: { $0.name == entry.name }) {
                ordered[index] = entry
            } else {
                ordered.append(entry)
            }
        }
        var result = SessionServers()
        for entry in ordered {
            let fill = { (text: String) in expand(text, environment: processEnvironment) }
            switch entry.transport {
            case .stdio:
                result.servers.append(.stdio(name: entry.name, command: fill(entry.command),
                                             arguments: entry.arguments.map(fill)))
            case .http:
                result.servers.append(.http(name: entry.name, url: fill(entry.url)))
            }
            let secret = AgentSessionRequest.MCPServerSecrets(
                environment: entry.environment.mapValues(fill),
                headers: entry.headers.mapValues(fill)
            )
            if !secret.environment.isEmpty || !secret.headers.isEmpty {
                result.secrets[entry.name] = secret
            }
        }
        return result
    }

    /// `sessionServers` for a session in `workingDirectory`, read through the host and the
    /// environment: the host's list (imported on first use), the stored secrets, and the
    /// project's `.mcp.json`.
    @MainActor
    public static func sessionServers(
        host: any VitruvianCodeHost,
        environment: VitruvianCodeEngine.Environment,
        workingDirectory: String,
        target: AgentMCPTarget
    ) -> SessionServers {
        guard target != .none, let settings = settings(host: host, environment: environment) else {
            return SessionServers()
        }
        let secrets = AgentSecrets(environment: environment)
        let projectPath = projectConfigPath(workingDirectory: workingDirectory)
        return sessionServers(
            settings: settings,
            secrets: { secrets.mcpSecrets(for: $0) },
            projectConfig: environment.fileExists(projectPath) ? environment.readFile(projectPath) : nil,
            target: target,
            processEnvironment: environment.processEnvironment
        )
    }

    /// Fills in `${VAR}` and `${VAR:-default}` from `environment`. A variable that is not set
    /// and has no default is left as written, so the server's own error names it.
    public static func expand(_ text: String, environment: [String: String]) -> String {
        guard text.contains("${") else { return text }
        var output = ""
        var rest = Substring(text)
        while let start = rest.range(of: "${") {
            output += rest[rest.startIndex..<start.lowerBound]
            let afterOpen = rest[start.upperBound...]
            guard let close = afterOpen.firstIndex(of: "}") else {
                output += rest[start.lowerBound...]
                return output
            }
            let body = String(afterOpen[afterOpen.startIndex..<close])
            let name: String
            let fallback: String?
            if let separator = body.range(of: ":-") {
                name = String(body[body.startIndex..<separator.lowerBound])
                fallback = String(body[separator.upperBound...])
            } else {
                name = body
                fallback = nil
            }
            if let value = environment[name] {
                output += value
            } else if let fallback {
                output += fallback
            } else {
                output += "${\(body)}"
            }
            rest = afterOpen[afterOpen.index(after: close)...]
        }
        output += rest
        return output
    }

    // MARK: - Arguments as one line

    /// Splits a line of arguments at spaces, keeping text in single or double quotes together.
    public static func splitArguments(_ line: String) -> [String] {
        var result: [String] = []
        var current = ""
        var quote: Character?
        var hasToken = false
        for character in line {
            if let open = quote {
                if character == open { quote = nil } else { current.append(character) }
            } else if character == "\"" || character == "'" {
                quote = character
                hasToken = true
            } else if character == " " || character == "\t" || character == "\n" {
                if hasToken { result.append(current) }
                current = ""
                hasToken = false
            } else {
                current.append(character)
                hasToken = true
            }
        }
        if hasToken { result.append(current) }
        return result
    }

    /// The arguments as one line that `splitArguments` reads back.
    public static func joinArguments(_ arguments: [String]) -> String {
        arguments.map { argument in
            if argument.isEmpty { return "\"\"" }
            guard argument.contains(where: { $0 == " " || $0 == "\t" || $0 == "\"" || $0 == "'" }) else { return argument }
            return argument.contains("\"") ? "'\(argument)'" : "\"\(argument)\""
        }.joined(separator: " ")
    }
}

/// A server as the user is editing it in Settings, with its checks. Both settings screens (the
/// standalone app's and the Vitruvian extension's) edit through this, so they check the same way.
public struct AgentMCPServerDraft: Equatable, Sendable {
    /// Why a draft cannot be saved.
    public enum Problem: Equatable, Sendable {
        case emptyName
        case duplicateName
        case missingCommand
        case invalidURL
        case invalidSecretName
    }

    /// The server being edited, or nil for a new one.
    public var id: UUID?
    public var name: String
    public var transport: AgentMCPServer.Transport
    public var command: String
    public var argumentsLine: String
    public var url: String
    public var isEnabled: Bool
    /// The secrets to keep: environment values for stdio, headers for HTTP. Nil leaves the
    /// stored ones as they are.
    public var secrets: [String: String]?

    public init(
        id: UUID? = nil,
        name: String = "",
        transport: AgentMCPServer.Transport = .stdio,
        command: String = "",
        argumentsLine: String = "",
        url: String = "",
        isEnabled: Bool = true,
        secrets: [String: String]? = nil
    ) {
        self.id = id
        self.name = name
        self.transport = transport
        self.command = command
        self.argumentsLine = argumentsLine
        self.url = url
        self.isEnabled = isEnabled
        self.secrets = secrets
    }

    /// A draft of an existing server; its secrets are left as stored until changed.
    public init(_ server: AgentMCPServer) {
        self.init(
            id: server.id,
            name: server.name,
            transport: server.transport,
            command: server.command,
            argumentsLine: AgentMCPServers.joinArguments(server.arguments),
            url: server.url,
            isEnabled: server.isEnabled
        )
    }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// What stops the draft being saved into `settings`, or nil.
    public func problem(in settings: AgentMCPSettings) -> Problem? {
        if trimmedName.isEmpty { return .emptyName }
        if settings.servers.contains(where: { $0.name == trimmedName && $0.id != id }) { return .duplicateName }
        switch transport {
        case .stdio:
            if command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return .missingCommand }
        case .http:
            let text = url.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let parsed = URL(string: text), let scheme = parsed.scheme?.lowercased(),
                  scheme == "http" || scheme == "https", parsed.host != nil else { return .invalidURL }
        }
        if let secrets, !secrets.keys.allSatisfy(AgentSecrets.isValidMCPKey) { return .invalidSecretName }
        return nil
    }

    /// Saves the draft into `settings`, and its secrets (when changed) into `store`. Returns the
    /// saved server, or nil when the draft has a problem or the secrets could not be written (the
    /// settings are then left as they were).
    @MainActor
    @discardableResult
    public func save(into settings: inout AgentMCPSettings, secrets store: AgentSecrets) -> AgentMCPServer? {
        guard problem(in: settings) == nil else { return nil }
        let existing = id.flatMap { id in settings.servers.firstIndex { $0.id == id } }
        var server = existing.map { settings.servers[$0] } ?? AgentMCPServer(name: trimmedName, transport: transport)
        server.name = trimmedName
        server.transport = transport
        server.isEnabled = isEnabled
        switch transport {
        case .stdio:
            server.command = command.trimmingCharacters(in: .whitespacesAndNewlines)
            server.arguments = AgentMCPServers.splitArguments(argumentsLine)
            server.url = ""
        case .http:
            server.url = url.trimmingCharacters(in: .whitespacesAndNewlines)
            server.command = ""
            server.arguments = []
        }
        let transportChanged = existing.map { settings.servers[$0].transport != transport } ?? false
        if let secrets {
            let value = transport == .stdio
                ? AgentSessionRequest.MCPServerSecrets(environment: secrets)
                : AgentSessionRequest.MCPServerSecrets(headers: secrets)
            guard store.setMCPSecrets(value, for: server.id) else { return nil }
        } else if transportChanged {
            // Environment values mean nothing to an HTTP server, nor headers to a stdio one.
            guard store.removeMCPSecrets(for: server.id) else { return nil }
        }
        if let existing {
            settings.servers[existing] = server
        } else {
            settings.servers.append(server)
        }
        return server
    }

    /// Removes the server with `id` and its secrets.
    @MainActor
    public static func remove(_ id: UUID, from settings: inout AgentMCPSettings, secrets store: AgentSecrets) {
        settings.servers.removeAll { $0.id == id }
        store.removeMCPSecrets(for: id)
    }
}
