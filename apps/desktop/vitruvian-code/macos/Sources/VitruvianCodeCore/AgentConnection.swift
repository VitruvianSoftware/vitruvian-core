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
// copyright holder on 2026-10-09 (apps/desktop/vitruvian/UPSTREAM.md).

import Foundation

/// How the app talks to a configured agent: a live ACP or SDK process held
/// across turns, or one command-line run per prompt.
public enum AgentConnectionKind: String, Codable, CaseIterable, Equatable, Sendable {
    case acp
    case claudeSDK
    case claudeACP
    case commandLine
}

/// Optional features an agent connection advertises when its session opens.
/// Every flag defaults to false so a connection opts in only to what its
/// agent and client policy offer.
public struct AgentCapabilities: Equatable, Sendable {
    public var loadSession: Bool
    public var resumeSession: Bool
    public var listSessions: Bool
    public var closeSession: Bool
    public var images: Bool
    public var audio: Bool
    public var embeddedContext: Bool
    public var mcpHTTP: Bool
    public var configOptions: Bool
    public var authMethods: Bool

    public init(
        loadSession: Bool = false,
        resumeSession: Bool = false,
        listSessions: Bool = false,
        closeSession: Bool = false,
        images: Bool = false,
        audio: Bool = false,
        embeddedContext: Bool = false,
        mcpHTTP: Bool = false,
        configOptions: Bool = false,
        authMethods: Bool = false
    ) {
        self.loadSession = loadSession
        self.resumeSession = resumeSession
        self.listSessions = listSessions
        self.closeSession = closeSession
        self.images = images
        self.audio = audio
        self.embeddedContext = embeddedContext
        self.mcpHTTP = mcpHTTP
        self.configOptions = configOptions
        self.authMethods = authMethods
    }
}

/// What a session needs when it starts or reopens: the working folder, any
/// extra folders in the workspace, MCP servers, added system-prompt text,
/// and an optional past session ID to continue.
public struct AgentSessionRequest: Equatable, Sendable {
    /// An MCP server passed to the agent when a session starts.
    public enum MCPServer: Equatable, Sendable, Codable {
        case stdio(name: String, command: String, arguments: [String] = [], environment: [String: String] = [:])
        case http(name: String, url: String, headers: [String: String] = [:])
    }

    public var workingDirectory: String
    public var additionalDirectories: [String]
    public var mcpServers: [MCPServer]
    public var systemPrompt: String?
    public var resumeSessionID: String?

    public init(
        workingDirectory: String,
        additionalDirectories: [String] = [],
        mcpServers: [MCPServer] = [],
        systemPrompt: String? = nil,
        resumeSessionID: String? = nil
    ) {
        self.workingDirectory = workingDirectory
        self.additionalDirectories = additionalDirectories
        self.mcpServers = mcpServers
        self.systemPrompt = systemPrompt
        self.resumeSessionID = resumeSessionID
    }
}

/// One part of a user's prompt: plain text or an attached image on disk.
public enum PromptBlock: Equatable, Sendable {
    case text(String)
    case image(path: String)
}

/// Why a turn ended.
public enum AgentStopReason: String, Codable, Equatable, Sendable {
    case endTurn = "end_turn"
    case maxTokens = "max_tokens"
    case maxTurnRequests = "max_turn_requests"
    case refusal
    case cancelled
    case error
}

/// The user's reply to an approval request or a question form.
public enum AgentAnswer: Equatable, Sendable {
    case option(String)
    case form([String: String])
    case cancelled
}

/// A setting value sent to or reported by an agent's session config options.
public enum AgentConfigValue: Equatable, Sendable, Codable {
    case string(String)
    case bool(Bool)
}

/// One live setting an agent offers for the open session.
public struct AgentConfigOption: Identifiable, Equatable, Sendable, Codable {
    public var id: String
    public var name: String
    public var value: AgentConfigValue
    public var options: [String]

    public init(id: String, name: String, value: AgentConfigValue, options: [String] = []) {
        self.id = id
        self.name = name
        self.value = value
        self.options = options
    }
}

/// The per-turn switches and attachments captured when a prompt is sent.
public struct AgentTurnModes: Equatable, Sendable {
    public var plan: Bool
    public var worktree: Bool
    public var attachments: [VitruvianCodeAttachment]
    public var fork: Bool

    public init(
        plan: Bool = false,
        worktree: Bool = false,
        attachments: [VitruvianCodeAttachment] = [],
        fork: Bool = false
    ) {
        self.plan = plan
        self.worktree = worktree
        self.attachments = attachments
        self.fork = fork
    }
}

/// Which agent connection to build and what its turn needs to run.
public struct AgentConnectionSpec: Equatable, Sendable {
    public var kind: AgentConnectionKind
    public var provider: VitruvianCodeCLIProvider
    public var configuration: VitruvianCodeConfiguration
    public var agentPath: String?
    public var workingDirectory: String
    public var ollamaDefaultModel: String
    public var turnModes: AgentTurnModes
    public var environment: [String: String]

    public var executablePath: String? {
        get { agentPath }
        set { agentPath = newValue }
    }

    public init(
        kind: AgentConnectionKind = .commandLine,
        provider: VitruvianCodeCLIProvider,
        configuration: VitruvianCodeConfiguration = VitruvianCodeConfiguration(),
        agentPath: String? = nil,
        workingDirectory: String,
        ollamaDefaultModel: String = VitruvianCodeSupport.ollamaFallbackModel,
        turnModes: AgentTurnModes = AgentTurnModes(),
        environment: [String: String] = [:]
    ) {
        var resolvedConfiguration = configuration
        resolvedConfiguration.activeProvider = provider
        self.kind = kind
        self.provider = provider
        self.configuration = resolvedConfiguration
        self.agentPath = agentPath
        self.workingDirectory = workingDirectory
        self.ollamaDefaultModel = ollamaDefaultModel
        self.turnModes = turnModes
        self.environment = environment
    }
}

/// Errors thrown by an `AgentConnection` before a transport method is wired up.
public enum AgentConnectionError: Error, Equatable, Sendable {
    case notSupportedYet
}

/// One connection to a coding agent, owned by an open chat. Every connection
/// turns what its agent sends into `AgentEvent` values so the session and UI
/// do not depend on the transport underneath.
@MainActor
public protocol AgentConnection: AnyObject {
    var capabilities: AgentCapabilities { get }
    var events: AsyncStream<AgentEvent> { get }
    func start(_ request: AgentSessionRequest) async throws -> String
    func prompt(_ blocks: [PromptBlock]) async throws -> AgentStopReason
    func cancel() async
    func answer(_ requestID: String, _ choice: AgentAnswer) async throws
    func setConfigOption(_ id: String, _ value: AgentConfigValue) async throws -> [AgentConfigOption]
    func stop() async
}

/// Internal fast-path adopted by `CommandLineConnection` so main-actor callers
/// and synchronous test rigs receive process callbacks inline in order without
/// duplicating any argument, stdin, or parsing logic.
@MainActor
protocol _ImmediateAgentConnection: AgentConnection {
    @discardableResult
    func beginImmediateSession(_ request: AgentSessionRequest) -> String
    func beginImmediatePrompt(
        _ blocks: [PromptBlock],
        onEvent: @escaping (AgentEvent) -> Void,
        onNoise: @escaping (String) -> Void,
        onAgentExit: @escaping (Int32) -> Void,
        onCommandPartial: @escaping (String) -> Void,
        onCommandExit: @escaping (Int32, VitruvianCodeCommandOutcome, String) -> Void
    ) throws
    func sendImmediateAnswer(_ requestID: String, _ choice: AgentAnswer)
    func cancelImmediateTurn()
}
