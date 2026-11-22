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

/// Pure rules and parsers for the Claude helper connection: the `claude --version` check
/// (T3 Code's `ClaudeProvider.ts` and `ClaudeModelCatalog.ts`), the split of secrets out of a
/// session request, the approval-mode mapping, and the helper's `_vitruvian/` messages.
public enum ClaudeSDKSupport {
    /// The newest-enough `claude` the helper works with. It is the helper's own
    /// `MCP_INITIALIZE_MIN_CLAUDE_VERSION` (`claude-helper/src/agent.ts`), the version of Claude
    /// Code the bundled SDK ships; `initialize` reports it too, and a test holds the two equal.
    public static let minimumClaudeVersion = "2.1.326"

    /// `CLAUDE_VERSION_CHECK_TIMEOUT_MS` in T3 Code's `ClaudeProvider.ts`: 20 seconds.
    /// `VitruvianCodeEngine.runProgram` gives a program exactly this long.
    public static let versionCheckTimeout: TimeInterval = 20

    /// Shown when the app carries no Node or helper (a build that is not a release).
    public static let helperMissingMessage =
        "This copy of Vitruvian Code doesn't include the Claude helper. Use the command line for this chat, or install a release build."

    /// Shown when no `claude` can be found.
    public static let claudeNotFoundMessage =
        "Claude Code (`claude`) was not found. Install Claude Code, then try again."

    /// The variable that moves Claude Code's config folder.
    public static let configDirectoryKey = "CLAUDE_CONFIG_DIR"

    public static let secretsMethod = "_vitruvian/secrets"
    public static let forkMethod = "_vitruvian/fork"
    public static let mcpStatusMethod = "_vitruvian/mcpStatus"
    public static let usageLimitMethod = "_vitruvian/usageLimit"

    // MARK: - Version

    /// `\bv?(\d+\.\d+\.\d+...)\b`, T3 Code's `parseCliVersionResult` pattern
    /// (also the helper's `parseClaudeVersion`).
    public static func parseVersion(_ output: String?) -> String? {
        guard let output,
              let regex = try? NSRegularExpression(
                  pattern: #"\bv?(\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?(?:\+[0-9A-Za-z.-]+)?)\b"#
              ),
              let match = regex.firstMatch(in: output, range: NSRange(output.startIndex..., in: output)),
              let range = Range(match.range(at: 1), in: output) else {
            return nil
        }
        return String(output[range])
    }

    /// Compares two `x.y.z` versions numerically; prerelease and build parts are ignored
    /// (the helper's `compareClaudeVersions`).
    public static func compare(_ lhs: String, _ rhs: String) -> Int {
        func parts(_ version: String) -> [Int] {
            let core = version.split(whereSeparator: { $0 == "-" || $0 == "+" }).first.map(String.init) ?? version
            return core.split(separator: ".").map { Int($0) ?? 0 }
        }
        let left = parts(lhs)
        let right = parts(rhs)
        for index in 0..<3 {
            let a = index < left.count ? left[index] : 0
            let b = index < right.count ? right[index] : 0
            if a != b { return a < b ? -1 : 1 }
        }
        return 0
    }

    /// The command that upgrades Claude Code, as T3 Code words it: Homebrew's cask upgrade when
    /// `claude` lives in a cask, otherwise Claude Code's own `claude update`.
    public static func updateCommand(forClaudeAt path: String) -> String {
        let resolved = URL(fileURLWithPath: path).resolvingSymlinksInPath().path
        for candidate in [resolved, path] {
            if candidate.contains("/Caskroom/claude-code@latest/") { return "brew upgrade --cask claude-code@latest" }
            if candidate.contains("/Caskroom/claude-code/") { return "brew upgrade --cask claude-code" }
        }
        return "claude update"
    }

    /// The warning shown when `claude` is older than the helper's minimum. Only MCP servers
    /// that carry secrets need that version (the helper hands them over in `claude`'s first
    /// message, not on its command line), and the helper refuses that case itself. So, as T3
    /// Code does for a version that's merely old, the chat carries on and only warns.
    public static func tooOldMessage(version: String, minimum: String, updateCommand: String) -> String {
        "Claude Code v\(version) is older than v\(minimum). Chats work, but MCP servers that carry "
            + "secrets need v\(minimum) or newer. Upgrade with `\(updateCommand)`."
    }

    // MARK: - Models

    /// One Claude model the app lists and the oldest `claude` that can run it.
    public struct ModelRequirement: Equatable, Sendable {
        public let id: String
        public let aliases: [String]
        public let name: String
        /// Nil for a model every `claude` can run.
        public let minVersion: String?

        public init(id: String, aliases: [String] = [], name: String, minVersion: String?) {
            self.id = id
            self.aliases = aliases
            self.name = name
            self.minVersion = minVersion
        }
    }

    /// `claudeCode.minVersion` per model, copied from T3 Code's `model-manifest.json`
    /// (`apps/server/src/provider/`, read through `ModelManifest.ts`) for the models
    /// `VitruvianCodeSupport.defaultModels(for: .claude)` lists. `sonnet`, `opus` and `haiku` are
    /// those models' aliases there.
    public static let modelRequirements: [ModelRequirement] = [
        ModelRequirement(id: "claude-opus-5-5", aliases: ["opus"], name: "Claude Opus 5.5", minVersion: "2.1.280"),
        ModelRequirement(id: "claude-sonnet-5-5", aliases: ["sonnet"], name: "Claude Sonnet 5.5", minVersion: "2.1.284"),
        ModelRequirement(id: "claude-haiku-5-5", aliases: ["haiku"], name: "Claude Haiku 5.5", minVersion: "2.1.293"),
        ModelRequirement(id: "claude-opus-4-7", name: "Claude Opus 4.7", minVersion: "2.1.111"),
        ModelRequirement(id: "claude-sonnet-4-6", name: "Claude Sonnet 4.6", minVersion: nil),
    ]

    /// The listed models `version` is too old for, the one needing the oldest `claude` first.
    /// None when the version is unknown: an unreadable version blocks nothing.
    public static func unavailableModels(
        version: String?,
        among requirements: [ModelRequirement] = modelRequirements
    ) -> [ModelRequirement] {
        guard let version else { return [] }
        return requirements
            .filter { requirement in
                guard let minimum = requirement.minVersion else { return false }
                return compare(version, minimum) < 0
            }
            .sorted { compare($0.minVersion ?? "0.0.0", $1.minVersion ?? "0.0.0") < 0 }
    }

    /// `models` without those `version` is too old for (their aliases too).
    public static func visibleModels(
        _ models: [VitruvianCodeModelOption],
        version: String?,
        among requirements: [ModelRequirement] = modelRequirements
    ) -> [VitruvianCodeModelOption] {
        let hidden = Set(unavailableModels(version: version, among: requirements).flatMap { [$0.id] + $0.aliases })
        return models.filter { !hidden.contains($0.id) }
    }

    /// T3 Code's `formatClaudeVersionUpgradeMessage`, for the model needing the oldest `claude`
    /// among those that cannot run: nil when none is held back. The ending says "to use it"
    /// where T3 Code says "to access it".
    public static func versionUpgradeMessage(
        version: String?,
        among requirements: [ModelRequirement] = modelRequirements
    ) -> String? {
        guard let version,
              let first = unavailableModels(version: version, among: requirements).first,
              let minimum = first.minVersion else {
            return nil
        }
        return "Claude Code v\(version) is too old for \(first.name). Upgrade to v\(minimum) or newer to use it."
    }

    // MARK: - Modes

    /// The helper's mode ID for the app's approval mode and plan switch (design section 8):
    /// the plan switch wins, then full access, auto-accept edits, and `default` for the rest.
    /// The helper has no `auto` mode, so `.auto` asks like approval required.
    public static func claudeModeID(for mode: VitruvianCodeApprovalMode, planSwitch: Bool) -> String {
        if planSwitch || mode == .plan { return "plan" }
        switch mode {
        case .yolo: return "bypassPermissions"
        case .acceptEdits: return "acceptEdits"
        case .standard, .auto, .plan: return "default"
        }
    }

    // MARK: - Secrets

    /// What goes to the helper in `_vitruvian/secrets`.
    public struct SecretsPlan: Equatable, Sendable {
        /// The request's params, nil when there is nothing to send.
        public let params: ACPJSONValue?
        /// Every secret value, for the log and stderr redaction.
        public let values: [String]
    }

    /// One `_vitruvian/secrets` message for the provider's sensitive environment values and the
    /// MCP servers' secret env and headers (`protocol/examples/client-vitruvian-secrets.json`).
    /// Nothing to send, when there is nothing, is no message at all: the helper starts with no
    /// secrets (`ClaudeHelperAgent.secrets`), so it does not need an empty one.
    public static func secretsPlan(
        environment: [String: String],
        mcpSecrets: [String: AgentSessionRequest.MCPServerSecrets]
    ) -> SecretsPlan {
        var values: [String] = Array(environment.values)
        var servers: [String: ACPJSONValue] = [:]
        for (name, secret) in mcpSecrets {
            var entry: [String: ACPJSONValue] = [:]
            if !secret.environment.isEmpty {
                entry["env"] = .object(secret.environment.mapValues { .string($0) })
                values.append(contentsOf: secret.environment.values)
            }
            if !secret.headers.isEmpty {
                entry["headers"] = .object(secret.headers.mapValues { .string($0) })
                values.append(contentsOf: secret.headers.values)
            }
            if !entry.isEmpty { servers[name] = .object(entry) }
        }
        var params: [String: ACPJSONValue] = [:]
        if !environment.isEmpty {
            params["env"] = .object(environment.mapValues { .string($0) })
        }
        if !servers.isEmpty {
            params["mcpServers"] = .object(servers)
        }
        return SecretsPlan(params: params.isEmpty ? nil : .object(params), values: values.filter { !$0.isEmpty })
    }

    // MARK: - Helper messages

    /// The reset time of a `_vitruvian/usageLimit` notification: nil when it names none.
    public static func usageLimitResetDate(from params: ACPJSONValue?) -> Date? {
        guard let text = params?.objectValue?["resetsAt"]?.stringValue else { return nil }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        if let date = plain.date(from: text) { return date }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: text)
    }

    /// The helper marks a subagent's launch with the `subagent` flag under `_meta` (key "vitruvian") on its `tool_call`
    /// (`protocol/examples/helper-update-tool-call-subagent.json`).
    public static func isSubagentLaunch(_ call: ACPToolCall) -> Bool {
        call._meta?["vitruvian"]?.objectValue?["subagent"]?.boolValue == true
    }

    /// The subagent started by that launch.
    public static func subagent(from call: ACPToolCall, running: Bool) -> VitruvianCodeActiveSubagent {
        let input = call.rawInput?.objectValue
        let title = call.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let description = input?["description"]?.stringValue ?? ""
        let role = title.isEmpty ? (description.isEmpty ? "Subagent" : description) : title
        let prompt = input?["prompt"]?.stringValue ?? description
        return VitruvianCodeActiveSubagent(
            id: call.toolCallId,
            typeName: "subagent",
            role: role,
            prompt: prompt,
            model: "",
            isRunning: running
        )
    }
}

/// One MCP server's status from `_vitruvian/mcpStatus`
/// (`protocol/examples/helper-vitruvian-mcp-status-result.json`).
public struct ClaudeMCPServerStatus: Equatable, Sendable, Codable {
    public struct ServerInfo: Equatable, Sendable, Codable {
        public var name: String
        public var version: String
    }

    public struct Tool: Equatable, Sendable, Codable {
        public struct Annotations: Equatable, Sendable, Codable {
            public var readOnly: Bool?
            public var destructive: Bool?
            public var openWorld: Bool?
        }

        public var name: String
        public var description: String?
        public var annotations: Annotations?
    }

    public var name: String
    /// `connected`, `failed`, `needs-auth`, `pending` or `disabled`.
    public var status: String
    public var serverInfo: ServerInfo?
    public var error: String?
    public var scope: String?
    public var source: String?
    public var tools: [Tool]?
}

/// Why `ClaudeSDKConnection` could not start, in words the chat can show as they are.
public struct ClaudeSDKConnectionError: Error, Equatable, Sendable, LocalizedError {
    public let message: String
    public var errorDescription: String? { message }
}

/// Class-boxed state the connection's hooks read, so they can run on the main actor without
/// holding the connection (the hooks live inside the `ACPConnection` the connection owns).
@MainActor
private final class ClaudeSDKHookState {
    var secretsParams: ACPJSONValue?
    var subagentIDs: Set<String> = []
}

/// Long-lived per-chat connection for Claude on the Agent SDK: the bundled Node runs the bundled
/// helper, which speaks ACP (plus `_vitruvian/` messages) for the user's own `claude`. It is an
/// `ACPConnection` with the helper's rules, structured like `AntigravityACPConnection`.
///
/// Nothing falls back to the command line: a connection that cannot start says why, and the
/// user picks what to do (design section 5).
@MainActor
public final class ClaudeSDKConnection: PersistentAgentConnection {
    public var capabilities: AgentCapabilities { inner.capabilities }
    public var events: AsyncStream<AgentEvent> { inner.events }
    public var isConnected: Bool { inner.isConnected }
    public var initializeResult: ACPInitializeResult? { inner.initializeResult }
    public var launchSpecUsed: AgentProcessLaunchSpec { launchSpec }
    /// The version `claude --version` printed at the first start, nil before it or when it could
    /// not be read.
    public private(set) var installedClaudeVersion: String?

    private let inner: ACPConnection
    private let launchSpec: AgentProcessLaunchSpec
    private let modeProvider: ACPConnection.ModeProvider
    private let hookState: ClaudeSDKHookState
    private let bundled: BundledNode?
    private let claudePath: String?
    private let providerID: UUID
    private let secrets: AgentSecrets?
    private let versionProbe: @Sendable () async -> String?
    private let minimumClaudeVersion: String
    private var preflightDone = false

    public convenience init(
        spec: AgentConnectionSpec,
        environment: VitruvianCodeEngine.Environment,
        bundledNode: @MainActor () -> BundledNode? = { BundledNode.locate() },
        versionProbe: (@Sendable () async -> String?)? = nil,
        minimumClaudeVersion: String = ClaudeSDKSupport.minimumClaudeVersion,
        cancelGraceTimeout: TimeInterval = ACPConnection.defaultCancelGraceTimeout,
        sessionSetupTimeout: TimeInterval = ACPTransport.defaultSessionSetupTimeout,
        terminationGrace: TimeInterval = AgentProcess.defaultTerminationGrace,
        processFactory: @escaping ACPConnection.ProcessFactory = ACPLaunchedProcess.live
    ) {
        let requested = spec.agentPath?.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = (requested?.isEmpty == false ? requested : nil) ?? spec.provider.executableName
        let claudePath: String? = name.hasPrefix("/")
            ? name
            : VitruvianCodeSupport.locateChatProgram(
                named: name,
                environment: spec.environment,
                home: environment.home,
                isExecutable: environment.isExecutable,
                fileExists: environment.fileExists
            )
        var childEnv = VitruvianCodeSupport.childEnvironment(base: spec.environment, home: environment.home)
        if let folder = spec.provider.claudeConfigDirectory?.trimmingCharacters(in: .whitespacesAndNewlines),
           !folder.isEmpty {
            childEnv[ClaudeSDKSupport.configDirectoryKey] = folder
        }
        let node = bundledNode()
        let fallbackMode = spec.configuration.approvalMode
        let fallbackPlan = spec.turnModes.plan
        let liveModeProvider = spec.liveModeProvider ?? { (fallbackMode, fallbackPlan) }
        let probe: @Sendable () async -> String? = versionProbe ?? { [runProgram = environment.runProgram] in
            guard let claudePath else { return nil }
            return await runProgram(claudePath, ["--version"])
        }
        self.init(
            launchSpec: AgentProcessLaunchSpec(
                executable: node?.nodeURL.path ?? "",
                arguments: node.map { [$0.helperURL.path, "--claude-path", claudePath ?? ""] } ?? [],
                environment: childEnv,
                workingDirectory: spec.workingDirectory
            ),
            bundled: node,
            claudePath: claudePath,
            providerID: spec.provider.id,
            secrets: AgentSecrets(environment: environment),
            modeProvider: liveModeProvider,
            stateDirectory: environment.stateDirectory,
            stateDirectoryOverride: environment.stateDirectoryOverride,
            versionProbe: probe,
            minimumClaudeVersion: minimumClaudeVersion,
            cancelGraceTimeout: cancelGraceTimeout,
            sessionSetupTimeout: sessionSetupTimeout,
            terminationGrace: terminationGrace,
            processFactory: processFactory
        )
    }

    public init(
        launchSpec: AgentProcessLaunchSpec,
        bundled: BundledNode?,
        claudePath: String?,
        providerID: UUID,
        secrets: AgentSecrets?,
        modeProvider: @escaping ACPConnection.ModeProvider,
        stateDirectory: String? = nil,
        stateDirectoryOverride: String? = nil,
        versionProbe: @escaping @Sendable () async -> String?,
        minimumClaudeVersion: String = ClaudeSDKSupport.minimumClaudeVersion,
        cancelGraceTimeout: TimeInterval = ACPConnection.defaultCancelGraceTimeout,
        sessionSetupTimeout: TimeInterval = ACPTransport.defaultSessionSetupTimeout,
        terminationGrace: TimeInterval = AgentProcess.defaultTerminationGrace,
        processFactory: @escaping ACPConnection.ProcessFactory = ACPLaunchedProcess.live
    ) {
        self.launchSpec = launchSpec
        self.bundled = bundled
        self.claudePath = claudePath
        self.providerID = providerID
        self.secrets = secrets
        self.modeProvider = modeProvider
        self.versionProbe = versionProbe
        self.minimumClaudeVersion = minimumClaudeVersion
        let state = ClaudeSDKHookState()
        self.hookState = state

        let sessionMetaProvider: @MainActor @Sendable (ACPInitializeResult, String?) -> [String: ACPJSONValue]? = { [modeProvider] _, _ in
            let current = modeProvider()
            let modeID = ClaudeSDKSupport.claudeModeID(for: current.mode, planSwitch: current.planSwitch)
            return ["vitruvian": .object(["modeId": .string(modeID)])]
        }
        let postInitializeRequests: @MainActor @Sendable (ACPInitializeResult) -> [(method: String, params: ACPJSONValue)] = { _ in
            guard let params = state.secretsParams else { return [] }
            return [(ClaudeSDKSupport.secretsMethod, params)]
        }
        let onExtensionNotification: @MainActor @Sendable (String, ACPJSONValue?) -> [AgentEvent] = { method, params in
            guard method == ClaudeSDKSupport.usageLimitMethod else { return [] }
            return [.usageLimit(resetsAt: ClaudeSDKSupport.usageLimitResetDate(from: params))]
        }
        let transformSessionUpdate: @MainActor @Sendable (ACPSessionNotification) -> (notification: ACPSessionNotification?, extraEvents: [AgentEvent]) = { notification in
            switch notification.update {
            case .toolCall(let call) where ClaudeSDKSupport.isSubagentLaunch(call):
                state.subagentIDs.insert(call.toolCallId)
                return (notification, [.subagent(ClaudeSDKSupport.subagent(from: call, running: true), started: true)])
            case .toolCallUpdate(let update)
                where state.subagentIDs.contains(update.toolCallId)
                    && (update.status == "completed" || update.status == "failed"):
                state.subagentIDs.remove(update.toolCallId)
                return (notification, [.subagent(ClaudeSDKSupport.subagent(from: update, running: false), started: false)])
            default:
                return (notification, [])
            }
        }
        let hooks = ACPConnection.Hooks(
            sessionMetaProvider: sessionMetaProvider,
            transformSessionUpdate: transformSessionUpdate,
            finishSubagentsOnTurnEnd: true,
            cancelGraceTimeout: cancelGraceTimeout,
            postInitializeRequests: postInitializeRequests,
            onExtensionNotification: onExtensionNotification
        )
        self.inner = ACPConnection(
            launchSpec: launchSpec,
            policy: .claudeSDK,
            modeProvider: modeProvider,
            hooks: hooks,
            stateFolderURL: stateDirectory.map { URL(fileURLWithPath: $0, isDirectory: true) },
            stateDirectoryOverride: stateDirectoryOverride,
            sessionSetupTimeout: sessionSetupTimeout,
            terminationGrace: terminationGrace,
            processFactory: processFactory
        )
    }

    // MARK: - AgentConnection

    public func start(_ request: AgentSessionRequest) async throws -> String {
        if !preflightDone {
            try await preflight()
            preflightDone = true
        }

        let stored = secrets?.values(for: providerID) ?? [:]
        let plan = ClaudeSDKSupport.secretsPlan(environment: stored, mcpSecrets: request.mcpSecrets)
        hookState.secretsParams = plan.params
        inner.addRedactions(plan.values)

        let sessionID = try await inner.start(request)
        let current = modeProvider()
        try await inner.setSessionMode(ClaudeSDKSupport.claudeModeID(for: current.mode, planSwitch: current.planSwitch))
        return sessionID
    }

    public func prompt(_ blocks: [PromptBlock]) async throws -> AgentStopReason {
        try await inner.prompt(blocks)
    }

    public func cancel() async {
        await inner.cancel()
    }

    public func answer(_ requestID: String, _ choice: AgentAnswer) async throws {
        try await inner.answer(requestID, choice)
    }

    public func setConfigOption(_ id: String, _ value: AgentConfigValue) async throws -> [AgentConfigOption] {
        try await inner.setConfigOption(id, value)
    }

    public func syncPlanMode(_ planSwitch: Bool) async throws {
        let current = modeProvider()
        try await inner.setSessionMode(ClaudeSDKSupport.claudeModeID(for: current.mode, planSwitch: planSwitch))
    }

    public func stop() async {
        await inner.stop()
    }

    // MARK: - `_vitruvian/` requests

    /// Forks the open session with the SDK's `forkSession` and returns the new session's ID.
    public func fork() async throws -> String {
        guard let sessionID = inner.openSessionID else { throw ACPConnectionError.notStarted }
        let result = try await inner.sendExtensionRequest(
            method: ClaudeSDKSupport.forkMethod,
            params: .object(["sessionId": .string(sessionID)])
        )
        guard let forked = result.objectValue?["sessionId"]?.stringValue, !forked.isEmpty else {
            throw ACPConnectionError.missingSessionID
        }
        return forked
    }

    /// Each MCP server's status in the open session.
    public func mcpStatus() async throws -> [ClaudeMCPServerStatus] {
        guard let sessionID = inner.openSessionID else { throw ACPConnectionError.notStarted }
        let result = try await inner.sendExtensionRequest(
            method: ClaudeSDKSupport.mcpStatusMethod,
            params: .object(["sessionId": .string(sessionID)])
        )
        guard let servers = result.objectValue?["servers"] else { return [] }
        return try servers.decode([ClaudeMCPServerStatus].self)
    }

    // MARK: - Before the first session

    /// The checks that come before any process starts: the bundled helper is there, `claude` is
    /// found, and `claude --version` (20 seconds at most) is read. An old version only warns, and
    /// an unreadable one is logged; neither is held against `claude`.
    private func preflight() async throws {
        guard bundled != nil else {
            throw await fail(ClaudeSDKSupport.helperMissingMessage)
        }
        guard let claudePath, !claudePath.isEmpty else {
            throw await fail(ClaudeSDKSupport.claudeNotFoundMessage)
        }
        guard let version = ClaudeSDKSupport.parseVersion(await versionProbe()) else {
            inner.recordHostLog("Could not read the version of Claude Code; carrying on without the version check.")
            return
        }
        installedClaudeVersion = version
        if ClaudeSDKSupport.compare(version, minimumClaudeVersion) < 0 {
            let message = ClaudeSDKSupport.tooOldMessage(
                version: version,
                minimum: minimumClaudeVersion,
                updateCommand: ClaudeSDKSupport.updateCommand(forClaudeAt: claudePath)
            )
            inner.emitHostEvent(.notice(severity: "warning", title: message, detail: nil))
        }
        if let message = ClaudeSDKSupport.versionUpgradeMessage(version: version) {
            inner.emitHostEvent(.notice(severity: "warning", title: message, detail: nil))
        }
    }

    /// Reports a failure that happened before the helper started: one `.connectionFailed`, then
    /// the connection ends.
    private func fail(_ message: String) async -> ClaudeSDKConnectionError {
        inner.emitHostEvent(.connectionFailed(AgentFailure(kind: .startupFailed, message: message)))
        await inner.stop()
        return ClaudeSDKConnectionError(message: message)
    }
}
