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

/// Injectable process handle used by `ACPConnection`, backed by `AgentProcess` in production
/// and by in-memory byte streams in unit tests.
public struct ACPLaunchedProcess: Sendable {
    public let stdout: AsyncStream<Data>
    public let stderr: AsyncStream<Data>
    public let writeStdin: @Sendable (Data) throws -> Void
    public let closeStdin: @Sendable () -> Void
    public let waitForExit: @Sendable () async -> AgentProcessExit
    public let terminate: @Sendable (TimeInterval) async -> Void

    public init(
        stdout: AsyncStream<Data>,
        stderr: AsyncStream<Data>,
        writeStdin: @escaping @Sendable (Data) throws -> Void,
        closeStdin: @escaping @Sendable () -> Void,
        waitForExit: @escaping @Sendable () async -> AgentProcessExit,
        terminate: @escaping @Sendable (TimeInterval) async -> Void
    ) {
        self.stdout = stdout
        self.stderr = stderr
        self.writeStdin = writeStdin
        self.closeStdin = closeStdin
        self.waitForExit = waitForExit
        self.terminate = terminate
    }

    public static func live(_ spec: AgentProcessLaunchSpec) throws -> ACPLaunchedProcess {
        let process = try AgentProcess(spec)
        return ACPLaunchedProcess(
            stdout: process.stdout,
            stderr: process.stderr,
            writeStdin: { data in try process.write(data) },
            closeStdin: { process.closeInput() },
            waitForExit: {
                while !Task.isCancelled {
                    if let exit = try? await process.waitForExit(timeout: AgentProcess.defaultWaitTimeout) {
                        return exit
                    }
                    if let exit = process.currentExit {
                        return exit
                    }
                }
                return process.currentExit ?? AgentProcessExit(exitCode: -1, signal: nil)
            },
            terminate: { grace in await process.terminate(grace: grace) }
        )
    }
}

/// Errors thrown directly by `ACPConnection` methods.
public enum ACPConnectionError: Error, Equatable, Sendable, LocalizedError {
    case notStarted
    case alreadyStopped
    case unknownInteractionRequest(String)
    case missingSessionID
    case sessionListNotAdvertised

    public var errorDescription: String? {
        switch self {
        case .notStarted:
            return "ACP connection has not been started."
        case .alreadyStopped:
            return "ACP connection has already been stopped."
        case .unknownInteractionRequest(let id):
            return "No pending ACP permission or question request matches '\(id)'."
        case .missingSessionID:
            return "ACP agent returned an empty session identifier."
        case .sessionListNotAdvertised:
            return "ACP agent does not advertise session/list support."
        }
    }
}

private struct ACPAuthFailureError: Error, Sendable {
    let message: String
}

/// Live `AgentConnection` speaking Agent Client Protocol (ACP) v1 over newline-delimited JSON-RPC 2.0.
@MainActor
public final class ACPConnection: PersistentAgentConnection {
    public typealias ProcessFactory = @Sendable (AgentProcessLaunchSpec) throws -> ACPLaunchedProcess
    public typealias ModeProvider = @MainActor () -> (mode: VitruvianCodeApprovalMode, planSwitch: Bool)

    /// Extension points used by provider-specific layers such as `AntigravityACP`.
    /// Every hook defaults to `nil` / empty so base ACP behavior is unchanged.
    public struct Hooks: Sendable {
        public var initializeMeta: [String: ACPJSONValue]?
        public var prepareInitialize: (@MainActor @Sendable () async -> (clientInfo: ACPImplementation, policy: ACPClientPolicy)?)?
        public var onInitialized: (@MainActor @Sendable (ACPInitializeResult) -> ACPClientPolicy?)?
        public var authMethodID: String?
        public var authFailureMessage: String?
        public var additionalDirectories: [String]
        public var sessionMetaProvider: (@MainActor @Sendable (ACPInitializeResult, String?) -> [String: ACPJSONValue]?)?
        public var permissionInterceptor: (@MainActor @Sendable (ACPRequestPermissionParams, String) -> AgentQuestion?)?
        public var onClientFileRead: (@MainActor @Sendable (_ path: String, _ served: Bool) -> [ACPSessionNotification])?
        public var transformSessionUpdate: (@MainActor @Sendable (ACPSessionNotification) -> (notification: ACPSessionNotification?, extraEvents: [AgentEvent]))?
        public var onPromptStarted: (@MainActor @Sendable () -> Void)?
        public var finishSubagentsOnTurnEnd: Bool
        public var promptOutcomeWatcher: (@Sendable (_ sessionID: String) async -> (@Sendable (_ stopReason: String) async -> String?)?)?
        public var promptContextUsageProvider: (@MainActor @Sendable (_ initResult: ACPInitializeResult?, _ usage: ACPUsage?, _ contextWindow: Int) -> VitruvianCodeContextUsage?)?
        public var promptInactivityTimeout: TimeInterval?
        public var cancelGraceTimeout: TimeInterval
        /// Extra requests sent right after `initialize` succeeds and before the session opens
        /// (the Claude helper's `_vitruvian/secrets`). Each one waits for its reply.
        public var postInitializeRequests: (@MainActor @Sendable (ACPInitializeResult) -> [(method: String, params: ACPJSONValue)])?
        /// Notifications other than `session/update` (the helper's `_vitruvian/usageLimit`),
        /// turned into events. Returns nothing for a notification it does not know.
        public var onExtensionNotification: (@MainActor @Sendable (_ method: String, _ params: ACPJSONValue?) -> [AgentEvent])?
        /// Custom failure builder when the launched process exits unexpectedly.
        public var onUnexpectedExitFailure: (@MainActor @Sendable (_ exit: AgentProcessExit, _ stderr: String?) -> AgentFailure)?
        /// The sign-in methods a sign-in failure offers, in place of the ones built from the
        /// agent's `authMethods` (`ACPAuth.signInMethods`). The Claude helper advertises none and
        /// offers `claude auth login` instead.
        public var signInMethods: (@MainActor @Sendable (_ advertised: [ACPAuthMethod]) -> [AgentSignInMethod])?
        /// An agent sign-in method the user picked: sent as `authenticate` right after
        /// `initialize`, before the session opens, as T3 Code does
        /// (`packages/provider-acp-registry/src/server/auth.ts`).
        public var authenticateMethodID: String?
        /// False for an agent whose modes are its own (a registry agent: OpenCode's are
        /// "build" and "plan"): the chat's approval mode is then not sent as a session mode.
        /// T3 Code sets a mode only from its Antigravity driver, never for registry agents.
        public var syncsApprovalMode: Bool

        public init(
            initializeMeta: [String: ACPJSONValue]? = nil,
            prepareInitialize: (@MainActor @Sendable () async -> (clientInfo: ACPImplementation, policy: ACPClientPolicy)?)? = nil,
            onInitialized: (@MainActor @Sendable (ACPInitializeResult) -> ACPClientPolicy?)? = nil,
            authMethodID: String? = nil,
            authFailureMessage: String? = nil,
            additionalDirectories: [String] = [],
            sessionMetaProvider: (@MainActor @Sendable (ACPInitializeResult, String?) -> [String: ACPJSONValue]?)? = nil,
            permissionInterceptor: (@MainActor @Sendable (ACPRequestPermissionParams, String) -> AgentQuestion?)? = nil,
            onClientFileRead: (@MainActor @Sendable (_ path: String, _ served: Bool) -> [ACPSessionNotification])? = nil,
            transformSessionUpdate: (@MainActor @Sendable (ACPSessionNotification) -> (notification: ACPSessionNotification?, extraEvents: [AgentEvent]))? = nil,
            onPromptStarted: (@MainActor @Sendable () -> Void)? = nil,
            finishSubagentsOnTurnEnd: Bool = false,
            promptOutcomeWatcher: (@Sendable (_ sessionID: String) async -> (@Sendable (_ stopReason: String) async -> String?)?)? = nil,
            promptContextUsageProvider: (@MainActor @Sendable (_ initResult: ACPInitializeResult?, _ usage: ACPUsage?, _ contextWindow: Int) -> VitruvianCodeContextUsage?)? = nil,
            promptInactivityTimeout: TimeInterval? = nil,
            cancelGraceTimeout: TimeInterval = ACPConnection.defaultCancelGraceTimeout,
            postInitializeRequests: (@MainActor @Sendable (ACPInitializeResult) -> [(method: String, params: ACPJSONValue)])? = nil,
            onExtensionNotification: (@MainActor @Sendable (_ method: String, _ params: ACPJSONValue?) -> [AgentEvent])? = nil,
            onUnexpectedExitFailure: (@MainActor @Sendable (_ exit: AgentProcessExit, _ stderr: String?) -> AgentFailure)? = nil,
            signInMethods: (@MainActor @Sendable (_ advertised: [ACPAuthMethod]) -> [AgentSignInMethod])? = nil,
            authenticateMethodID: String? = nil,
            syncsApprovalMode: Bool = true
        ) {
            self.syncsApprovalMode = syncsApprovalMode
            self.signInMethods = signInMethods
            self.authenticateMethodID = authenticateMethodID
            self.postInitializeRequests = postInitializeRequests
            self.onExtensionNotification = onExtensionNotification
            self.onUnexpectedExitFailure = onUnexpectedExitFailure
            self.initializeMeta = initializeMeta
            self.prepareInitialize = prepareInitialize
            self.onInitialized = onInitialized
            self.authMethodID = authMethodID
            self.authFailureMessage = authFailureMessage
            self.additionalDirectories = additionalDirectories
            self.sessionMetaProvider = sessionMetaProvider
            self.permissionInterceptor = permissionInterceptor
            self.onClientFileRead = onClientFileRead
            self.transformSessionUpdate = transformSessionUpdate
            self.onPromptStarted = onPromptStarted
            self.finishSubagentsOnTurnEnd = finishSubagentsOnTurnEnd
            self.promptOutcomeWatcher = promptOutcomeWatcher
            self.promptContextUsageProvider = promptContextUsageProvider
            self.promptInactivityTimeout = promptInactivityTimeout
            self.cancelGraceTimeout = cancelGraceTimeout
        }
    }

    /// Bounded grace after `session/cancel` copied from `AcpSessionRuntime.ts:83` (`defaultCancelTimeout = Duration.seconds(15)`).
    public nonisolated static let defaultCancelGraceTimeout: TimeInterval = 15.0
    /// How long `stop()` waits for a polite `session/close` before ending the process group anyway.
    /// Kept short so the whole stop (close + SIGTERM grace + SIGKILL) fits inside the app's quit bound
    /// (`VitruvianCodeEngine.quitStopTimeout`) and agy cannot outlive the app.
    public nonisolated static let sessionCloseTimeout: TimeInterval = 1.0

    public private(set) var capabilities = AgentCapabilities()
    public private(set) var authMethods: [ACPAuthMethod] = []
    public private(set) var initializeResult: ACPInitializeResult?
    public private(set) var agentVersion: String?
    public var currentSessionModeID: String? { configState.modeState?.currentModeId }
    public var isConnected: Bool { !isStopping && !isStopped }
    public let events: AsyncStream<AgentEvent>

    private let launchSpec: AgentProcessLaunchSpec
    private var policy: ACPClientPolicy
    private let processFactory: ProcessFactory
    private let modeProvider: ModeProvider
    private let hooks: Hooks
    private var redactions: [String]
    private let statePaths: VitruvianCodeStatePaths?
    private let sessionSetupTimeout: TimeInterval
    private let terminationGrace: TimeInterval
    private let maxLineBytes: Int
    private var clientInfo: ACPImplementation

    private let eventsContinuation: AsyncStream<AgentEvent>.Continuation
    private let clientTerminals: ACPClientTerminals

    private var launchedProcess: ACPLaunchedProcess?
    private var transport: ACPTransport?
    private var exitMonitorTask: Task<Void, Never>?
    private var stderrDrainTask: Task<Void, Never>?

    private var sessionID = ""
    private var lastKnownModeID: String?
    private var lastKnownContextWindow: Int = 0
    private var clientFiles: ACPClientFiles?
    private var configState = ACPSessionConfigState()
    private var isLoadingSessionReplay = false
    private var isStarting = false
    private var isStopping = false
    private var isStopped = false
    private var hasEmittedTerminalFailure = false

    // Active prompt tracking
    private var isPromptActive = false
    private var activePromptCancelled = false
    private var activePromptInactivityTimedOut = false
    private var activePromptCollectedText = ""
    private var activePromptCompletionWaiters: [CheckedContinuation<Void, Never>] = []
    private var trackedToolCalls: [String: ACPToolCall] = [:]
    private var deniedToolCallIDs: Set<String> = []
    private var activeSubagentOrder: [String] = []
    private var activeSubagentsByID: [String: VitruvianCodeActiveSubagent] = [:]
    private var inactivityTimerTask: Task<Void, Never>?
    private var cancelGraceTask: Task<Void, Never>?

    // Pending interactive requests from agent
    private var nextInteractionNumber = 1
    private var pendingPermissions: [String: CheckedContinuation<ACPRequestPermissionResult, Never>] = [:]
    private var pendingQuestionToolCallIDs: [String: String] = [:]
    private var pendingElicitations: [
        String: (
            form: ACPElicitationForm,
            continuation: CheckedContinuation<ACPElicitationCreateResult, Never>
        )
    ] = [:]

    // Redacted logging state
    private var fallbackLogSessionID = "unknown"
    private var hasFinalizedLogTarget = false
    private var bufferedLogLines: [String] = []
    private var recentStderrLines: [String] = []

    public init(
        launchSpec: AgentProcessLaunchSpec,
        policy: ACPClientPolicy = .none,
        modeProvider: @escaping ModeProvider = { (.standard, false) },
        hooks: Hooks = Hooks(),
        stateFolderURL: URL? = nil,
        stateDirectoryOverride: String? = nil,
        redactions: [String] = [],
        sessionSetupTimeout: TimeInterval = ACPTransport.defaultSessionSetupTimeout,
        terminationGrace: TimeInterval = AgentProcess.defaultTerminationGrace,
        maxLineBytes: Int = ACPTransport.defaultMaxLineBytes,
        clientInfo: ACPImplementation = ACPImplementation(
            name: "vitruvian-code",
            title: "Vitruvian Code",
            version: "1.0.0"
        ),
        processFactory: @escaping ProcessFactory = ACPLaunchedProcess.live
    ) {
        self.launchSpec = launchSpec
        self.policy = policy
        self.modeProvider = modeProvider
        self.hooks = hooks
        self.redactions = redactions
            .filter { !$0.isEmpty }
            .sorted { $0.count > $1.count }
        if let stateFolderURL {
            self.statePaths = VitruvianCodeSupport.statePaths(
                home: stateFolderURL.path,
                defaultStateDirectory: stateFolderURL.path,
                stateDirectoryOverride: stateDirectoryOverride
            )
        } else if let stateDirectoryOverride {
            self.statePaths = VitruvianCodeSupport.statePaths(
                home: launchSpec.workingDirectory ?? NSHomeDirectory(),
                stateDirectoryOverride: stateDirectoryOverride
            )
        } else {
            self.statePaths = nil
        }
        self.sessionSetupTimeout = sessionSetupTimeout
        self.terminationGrace = terminationGrace
        self.maxLineBytes = maxLineBytes
        self.clientInfo = clientInfo
        self.processFactory = processFactory
        self.clientTerminals = ACPClientTerminals(
            baseEnvironment: launchSpec.environment,
            killGrace: terminationGrace
        )

        var captured: AsyncStream<AgentEvent>.Continuation!
        self.events = AsyncStream { continuation in
            captured = continuation
        }
        self.eventsContinuation = captured
    }

    // MARK: - AgentConnection

    public func start(_ request: AgentSessionRequest) async throws -> String {
        guard !isStopped, !isStopping else {
            throw ACPConnectionError.alreadyStopped
        }
        if !sessionID.isEmpty, transport != nil {
            return sessionID
        }
        if let resumeID = request.resumeSessionID?.trimmingCharacters(in: .whitespacesAndNewlines),
           !resumeID.isEmpty {
            fallbackLogSessionID = resumeID
        }

        let effectiveSpec: AgentProcessLaunchSpec = {
            var copy = launchSpec
            if copy.workingDirectory == nil || copy.workingDirectory?.isEmpty == true {
                copy.workingDirectory = request.workingDirectory
            }
            return copy
        }()

        isStarting = true
        defer { isStarting = false }

        do {
            let initialAdditionalDirs = Self.mergedDirectories(
                request.additionalDirectories,
                hooks.additionalDirectories
            )
            let launched = try processFactory(effectiveSpec)
            self.launchedProcess = launched
            self.clientFiles = ACPClientFiles(
                workingDirectory: request.workingDirectory,
                additionalDirectories: initialAdditionalDirs
            )

            startStderrDrain(launched.stderr)
            startExitMonitor(launched.waitForExit)

            let acpTransport = ACPTransport(
                incoming: launched.stdout,
                outgoing: launched.writeStdin,
                closeOutgoing: launched.closeStdin,
                maxLineBytes: maxLineBytes,
                onRequest: { [weak self] method, params in
                    guard let self else {
                        throw ACPRPCError(code: ACPRPCError.internalError, message: "Connection deallocated")
                    }
                    return try await self.handleIncomingRequest(method: method, params: params)
                },
                onNotification: { [weak self] method, params in
                    guard let self else { return }
                    await self.handleIncomingNotification(method: method, params: params)
                },
                onFailure: { [weak self] error in
                    guard let self else { return }
                    await self.handleTransportFailure(error)
                },
                onLog: { [weak self] message in
                    Task { @MainActor [weak self] in
                        self?.recordLogLine("[acp] \(message)")
                    }
                }
            )
            self.transport = acpTransport
            await acpTransport.start()

            if let prepared = await hooks.prepareInitialize?() {
                self.clientInfo = prepared.clientInfo
                self.policy = prepared.policy
            }
            guard !isStopping, !isStopped else {
                throw ACPConnectionError.alreadyStopped
            }

            let initParams = ACPInitializeParams(
                protocolVersion: ACPInitializeParams.v1ProtocolVersion,
                clientInfo: clientInfo,
                clientCapabilities: policy.clientCapabilities,
                _meta: hooks.initializeMeta
            )
            let initResult: ACPInitializeResult = try await acpTransport.request(
                method: "initialize",
                params: initParams,
                timeout: sessionSetupTimeout
            )
            guard !isStopping, !isStopped else {
                throw ACPConnectionError.alreadyStopped
            }

            self.initializeResult = initResult
            self.agentVersion = initResult.agentInfo?.version
            if let updatedPolicy = hooks.onInitialized?(initResult) {
                self.policy = updatedPolicy
            }

            let agentCaps = initResult.agentCapabilities
            let advertisedAuthMethods = initResult.authMethods ?? []
            self.authMethods = advertisedAuthMethods
            var resolvedCapabilities = AgentCapabilities(
                loadSession: agentCaps?.loadSession == true,
                resumeSession: agentCaps?.sessionCapabilities?.supportsResume == true,
                listSessions: agentCaps?.sessionCapabilities?.supportsList == true,
                closeSession: agentCaps?.sessionCapabilities?.supportsClose == true,
                images: agentCaps?.promptCapabilities?.image == true,
                audio: agentCaps?.promptCapabilities?.audio == true,
                embeddedContext: agentCaps?.promptCapabilities?.embeddedContext == true,
                mcpHTTP: agentCaps?.mcpCapabilities?.http == true,
                configOptions: false,
                authMethods: !advertisedAuthMethods.isEmpty
            )
            self.capabilities = resolvedCapabilities

            for request in hooks.postInitializeRequests?(initResult) ?? [] {
                let _: ACPJSONValue = try await acpTransport.request(
                    method: request.method,
                    params: request.params,
                    timeout: sessionSetupTimeout
                )
            }
            guard !isStopping, !isStopped else {
                throw ACPConnectionError.alreadyStopped
            }

            if let methodID = hooks.authenticateMethodID?.trimmingCharacters(in: .whitespacesAndNewlines),
               !methodID.isEmpty {
                // Only an agent method is sent: ACP forbids `authenticate` for a terminal method,
                // and an `env_var` method's ID is never sent (T3 Code, `auth.ts`).
                let offered = advertisedAuthMethods.first { $0.id == methodID }
                let type = offered?.type?.lowercased()
                guard offered != nil, type == nil || type == "agent" || type == "" else {
                    throw ACPAuthFailureError(message: Self.signInMethodGoneMessage)
                }
                do {
                    let _: ACPJSONValue = try await acpTransport.request(
                        method: "authenticate",
                        params: ACPAuthenticateParams(methodId: methodID),
                        timeout: sessionSetupTimeout
                    )
                } catch {
                    throw ACPAuthFailureError(
                        message: hooks.authFailureMessage ?? Self.errorDescription(error)
                    )
                }
                guard !isStopping, !isStopped else {
                    throw ACPConnectionError.alreadyStopped
                }
            }

            let mcpServers = Self.encodeMCPServers(request.mcpServers, allowHTTP: resolvedCapabilities.mcpHTTP)
            let supportsAdditionalDirs = agentCaps?.sessionCapabilities?.supportsAdditionalDirectories == true
            let extraDirsSource: [String] = supportsAdditionalDirs
                ? initialAdditionalDirs
                : request.additionalDirectories
            let extraDirs = extraDirsSource.isEmpty ? nil : extraDirsSource

            let meta: [String: ACPJSONValue]? = {
                if let customMeta = hooks.sessionMetaProvider?(initResult, request.systemPrompt) {
                    return customMeta.isEmpty ? nil : customMeta
                }
                guard let append = request.systemPrompt?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !append.isEmpty else {
                    return nil
                }
                return ["systemPrompt": .object(["append": .string(append)])]
            }()

            let resumeID = request.resumeSessionID?.trimmingCharacters(in: .whitespacesAndNewlines)
            let normalizedResumeID = (resumeID?.isEmpty == false) ? resumeID : nil

            let openAttempt: () async throws -> (ACPSessionSetupResult, String?) = {
                if let resumeID = normalizedResumeID {
                    if resolvedCapabilities.resumeSession {
                        let resumeParams = ACPSessionResumeParams(
                            sessionId: resumeID,
                            cwd: request.workingDirectory,
                            mcpServers: mcpServers,
                            additionalDirectories: extraDirs,
                            _meta: meta
                        )
                        let res: ACPSessionSetupResult = try await acpTransport.request(
                            method: "session/resume",
                            params: resumeParams,
                            timeout: self.sessionSetupTimeout
                        )
                        return (res, resumeID)
                    } else if resolvedCapabilities.loadSession {
                        self.isLoadingSessionReplay = true
                        defer { self.isLoadingSessionReplay = false }
                        let loadParams = ACPSessionLoadParams(
                            sessionId: resumeID,
                            cwd: request.workingDirectory,
                            mcpServers: mcpServers,
                            additionalDirectories: extraDirs,
                            _meta: meta
                        )
                        let res: ACPSessionSetupResult = try await acpTransport.request(
                            method: "session/load",
                            params: loadParams,
                            timeout: self.sessionSetupTimeout
                        )
                        return (res, resumeID)
                    }
                }
                let newParams = ACPSessionNewParams(
                    cwd: request.workingDirectory,
                    mcpServers: mcpServers,
                    additionalDirectories: extraDirs,
                    _meta: meta
                )
                let res: ACPSessionSetupResult = try await acpTransport.request(
                    method: "session/new",
                    params: newParams,
                    timeout: self.sessionSetupTimeout
                )
                return (res, nil)
            }

            let setupResult: ACPSessionSetupResult
            let fallbackSessionID: String?
            do {
                (setupResult, fallbackSessionID) = try await openAttempt()
            } catch {
                guard Self.isAuthRequiredError(error) else {
                    throw error
                }
                guard let authMethodID = hooks.authMethodID,
                      advertisedAuthMethods.isEmpty || advertisedAuthMethods.contains(where: { $0.id == authMethodID }) else {
                    throw ACPAuthFailureError(
                        message: hooks.authFailureMessage ?? Self.errorDescription(error)
                    )
                }
                do {
                    let _: ACPJSONValue = try await acpTransport.request(
                        method: "authenticate",
                        params: ACPAuthenticateParams(methodId: authMethodID),
                        timeout: sessionSetupTimeout
                    )
                } catch {
                    throw ACPAuthFailureError(
                        message: hooks.authFailureMessage ?? Self.errorDescription(error)
                    )
                }
                do {
                    (setupResult, fallbackSessionID) = try await openAttempt()
                } catch {
                    if Self.isAuthRequiredError(error) {
                        throw ACPAuthFailureError(
                            message: hooks.authFailureMessage ?? Self.errorDescription(error)
                        )
                    }
                    throw error
                }
            }

            guard !isStopping, !isStopped else {
                throw ACPConnectionError.alreadyStopped
            }

            let establishedID = (setupResult.sessionId ?? fallbackSessionID ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !establishedID.isEmpty else {
                throw ACPConnectionError.missingSessionID
            }

            // Preserve any `config_option_update` received during `session/load` if setup omitted `configOptions`
            // (`AcpSessionRuntime.ts:2020-2025`).
            let mergedSetup: ACPSessionSetupResult
            if setupResult.configOptions == nil && !configState.configOptions.isEmpty {
                var copy = setupResult
                copy.configOptions = configState.configOptions
                mergedSetup = copy
            } else {
                mergedSetup = setupResult
            }
            self.configState = ACPSessionConfigState(setupResult: mergedSetup)
            self.lastKnownModeID = configState.modeState?.currentModeId ?? "default"
            resolvedCapabilities.configOptions = configState.hasConfigOptions
            self.capabilities = resolvedCapabilities

            self.sessionID = establishedID
            let initialOptions = configState.agentConfigOptions
            if !initialOptions.isEmpty {
                emit(.configOptions(initialOptions))
            }
            flushBufferedLogs()
            return establishedID
        } catch {
            for _ in 0..<5 {
                await Task.yield()
            }
            if !isStopping, !hasEmittedTerminalFailure,
               case ACPTransportError.connectionClosed = error,
               launchedProcess != nil {
                for _ in 0..<10 where !hasEmittedTerminalFailure && !isStopping {
                    await Task.yield()
                    try? await Task.sleep(nanoseconds: 5_000_000)
                }
            }
            if !isStopping, !hasEmittedTerminalFailure {
                let failure = withSignInMethods(Self.makeStartupFailure(from: error, detail: recentStderrDetail()))
                recordLogLine("[acp] startup failed: \(failure.message)")
                emitTerminalPromptFailure(failure)
            }
            if !isStopped {
                isStopping = true
                isStopped = true
                hasFinalizedLogTarget = true
                await clientTerminals.closeAll()
                // End the process group before closing the transport: an outgoing
                // write blocked on a full stdin pipe holds the transport actor, so
                // closing it first would wait forever. The group's exit fails that
                // write and frees the actor.
                if let launchedProcess {
                    await launchedProcess.terminate(terminationGrace)
                }
                if let acpTransport = transport {
                    await acpTransport.close(reason: "ACP startup failed")
                }
                for _ in 0..<5 {
                    await Task.yield()
                }
                flushBufferedLogs(allowFallbackSessionID: true)
                exitMonitorTask?.cancel()
                exitMonitorTask = nil
                stderrDrainTask?.cancel()
                stderrDrainTask = nil
                eventsContinuation.finish()
            }
            throw error
        }
    }

    /// One page of the agent's own past sessions (`session/list`), asked over this
    /// already-open connection for the chat's "Recent sessions" list. It never
    /// starts the agent: a connection with no process throws `notStarted`.
    /// Throws `sessionListNotAdvertised` when the agent does not offer it. agy
    /// answers `session/list` only after `authenticate` (seen on 1.5.16), and a
    /// chat opened with `session/new` may never have sent it; so on "needs
    /// sign-in" it sends the same headless `authenticate` with the saved login
    /// that `start` sends, once, and asks again. No sign-in UI is shown; any
    /// failure is thrown for the caller to fall back on.
    public func listSessions(cwd: String?, cursor: String?) async throws -> ACPSessionListResult {
        guard !isStopped, !isStopping else {
            throw ACPConnectionError.alreadyStopped
        }
        guard let acpTransport = transport else {
            throw ACPConnectionError.notStarted
        }
        guard capabilities.listSessions else {
            throw ACPConnectionError.sessionListNotAdvertised
        }
        let params = ACPSessionListParams(cwd: cwd, cursor: cursor)
        do {
            return try await acpTransport.request(
                method: "session/list",
                params: params,
                timeout: sessionSetupTimeout
            )
        } catch {
            guard Self.isAuthRequiredError(error), let authMethodID = hooks.authMethodID,
                  authMethods.isEmpty || authMethods.contains(where: { $0.id == authMethodID }) else {
                throw error
            }
            let _: ACPJSONValue = try await acpTransport.request(
                method: "authenticate",
                params: ACPAuthenticateParams(methodId: authMethodID),
                timeout: sessionSetupTimeout
            )
            return try await acpTransport.request(
                method: "session/list",
                params: params,
                timeout: sessionSetupTimeout
            )
        }
    }

    public func prompt(_ blocks: [PromptBlock]) async throws -> AgentStopReason {
        guard let acpTransport = transport, !sessionID.isEmpty else {
            throw ACPConnectionError.notStarted
        }
        guard !isStopped else {
            throw ACPConnectionError.alreadyStopped
        }

        let supportsImages = capabilities.images
        let supportsEmbeddedContext = capabilities.embeddedContext
        let workdir = clientFiles?.workingDirectory ?? launchSpec.workingDirectory
        let contentBlocks = await Task.detached(priority: .userInitiated) {
            Self.encodePromptBlocks(
                blocks,
                supportsImages: supportsImages,
                supportsEmbeddedContext: supportsEmbeddedContext,
                workingDirectory: workdir
            )
        }.value
        guard !isStopped else {
            throw ACPConnectionError.alreadyStopped
        }
        let params = ACPPromptParams(sessionId: sessionID, prompt: contentBlocks)

        isPromptActive = true
        activePromptCancelled = false
        activePromptInactivityTimedOut = false
        activePromptCollectedText = ""
        trackedToolCalls.removeAll()
        deniedToolCallIDs.removeAll()
        hooks.onPromptStarted?()
        let outcomeChecker = await hooks.promptOutcomeWatcher?(sessionID)
        resetPromptInactivityTimer()

        defer {
            inactivityTimerTask?.cancel()
            inactivityTimerTask = nil
            cancelGraceTask?.cancel()
            cancelGraceTask = nil
            isPromptActive = false
            let waiters = activePromptCompletionWaiters
            activePromptCompletionWaiters.removeAll()
            for waiter in waiters {
                waiter.resume()
            }
            if isStopping && !isStopped {
                finalizeStoppedConnection()
            }
        }

        do {
            // `session/prompt` has no request timeout (`AcpSessionRuntime.ts` / `BRIEF.md`).
            let result: ACPPromptResult = try await acpTransport.request(
                method: "session/prompt",
                params: params,
                timeout: nil
            )
            inactivityTimerTask?.cancel()
            inactivityTimerTask = nil
            cancelGraceTask?.cancel()
            cancelGraceTask = nil

            let collected = activePromptCollectedText.isEmpty ? nil : activePromptCollectedText
            var metrics = Self.makeTurnMetrics(from: result.usage)
            let turnContextUsage = hooks.promptContextUsageProvider?(
                initializeResult,
                result.usage,
                lastKnownContextWindow
            )
            if let turnContextUsage {
                if metrics == nil {
                    metrics = VitruvianCodeTurnMetrics()
                }
                metrics?.contextUsage = turnContextUsage
            }
            if hooks.finishSubagentsOnTurnEnd {
                finishRemainingSubagents()
            }

            if activePromptInactivityTimedOut {
                let message = Self.inactivityFailureMessage(timeout: hooks.promptInactivityTimeout)
                emit(
                    .finished(
                        status: "error",
                        response: collected,
                        error: message,
                        conversationID: sessionID,
                        metrics: metrics
                    )
                )
                return .error
            }

            if let turnContextUsage {
                emit(.contextUsage(turnContextUsage))
            }

            let watchedError = activePromptCancelled ? nil : (await outcomeChecker?(result.stopReason))
            if let watchedError {
                emit(
                    .finished(
                        status: "error",
                        response: collected,
                        error: watchedError,
                        conversationID: sessionID,
                        metrics: metrics
                    )
                )
                return .error
            }

            let mapped = Self.mapStopReason(
                result.stopReason,
                wasCancelled: activePromptCancelled
            )
            let errorMessage: String? = mapped.status == "error"
                ? "ACP prompt ended with error stop reason: \(result.stopReason)"
                : nil

            emit(
                .finished(
                    status: mapped.status,
                    response: collected,
                    error: errorMessage,
                    conversationID: sessionID,
                    metrics: metrics
                )
            )
            return mapped.reason
        } catch {
            inactivityTimerTask?.cancel()
            inactivityTimerTask = nil
            cancelGraceTask?.cancel()
            cancelGraceTask = nil
            if hooks.finishSubagentsOnTurnEnd {
                finishRemainingSubagents()
            }
            if activePromptInactivityTimedOut {
                let collected = activePromptCollectedText.isEmpty ? nil : activePromptCollectedText
                let message = Self.inactivityFailureMessage(timeout: hooks.promptInactivityTimeout)
                emit(
                    .finished(
                        status: "error",
                        response: collected,
                        error: message,
                        conversationID: sessionID,
                        metrics: nil
                    )
                )
                if isStopping && !isStopped {
                    finalizeStoppedConnection()
                }
                return .error
            }
            if activePromptCancelled && isStopping {
                let collected = activePromptCollectedText.isEmpty ? nil : activePromptCollectedText
                emit(
                    .finished(
                        status: "cancelled",
                        response: collected,
                        error: nil,
                        conversationID: sessionID,
                        metrics: nil
                    )
                )
                if !isStopped {
                    finalizeStoppedConnection()
                }
                return .cancelled
            }

            // The agent wants sign-in mid-chat (the Claude helper answers a prompt this way when
            // Claude Code is logged out): a sign-in failure, so the card offers the methods.
            if Self.isPromptAuthRequiredError(error), !hasEmittedTerminalFailure {
                emitTerminalPromptFailure(AgentFailure(
                    kind: .auth,
                    message: hooks.authFailureMessage ?? Self.errorDescription(error),
                    detail: recentStderrDetail(),
                    signInMethods: currentSignInMethods()
                ))
                // The session is no good until the user signs in; the next turn starts afresh.
                Task { @MainActor [weak self] in await self?.stop() }
                return .error
            }

            if case ACPTransportError.rpcError = error {
                throw error
            }

            // Give the exit monitor a brief turn to observe process termination if the pipe closed first.
            if !hasEmittedTerminalFailure, let launchedProcess {
                for _ in 0..<20 where !hasEmittedTerminalFailure && !isStopping {
                    await Task.yield()
                    try? await Task.sleep(nanoseconds: 5_000_000)
                }
                if !hasEmittedTerminalFailure && !isStopping {
                    let detail = recentStderrDetail()
                    let syntheticExit = AgentProcessExit(exitCode: -1, signal: nil)
                    let failure = hooks.onUnexpectedExitFailure?(syntheticExit, detail) ?? AgentFailure(
                        kind: .exited,
                        message: "Agent process exited unexpectedly.",
                        detail: detail
                    )
                    emitTerminalPromptFailure(failure)
                    _ = launchedProcess
                    return .error
                }
            }

            if hasEmittedTerminalFailure {
                return .error
            }
            throw error
        }
    }

    public func cancel() async {
        if isStarting {
            await stop()
            return
        }
        guard isPromptActive, let acpTransport = transport, !sessionID.isEmpty else {
            return
        }
        activePromptCancelled = true
        cancelAllPendingInteractions()
        scheduleCancelGraceTimeout(
            reason: "The ACP agent did not finish cancellation. Its process was stopped."
        )
        try? await acpTransport.notify(
            method: "session/cancel",
            params: ACPSessionCancelParams(sessionId: sessionID)
        )
        if isPromptActive {
            await withCheckedContinuation { continuation in
                if isPromptActive {
                    activePromptCompletionWaiters.append(continuation)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    public func answer(_ requestID: String, _ choice: AgentAnswer) async throws {
        if let permissionContinuation = pendingPermissions.removeValue(forKey: requestID) {
            let questionToolCallID = pendingQuestionToolCallIDs.removeValue(forKey: requestID)
            let outcome: ACPPermissionOutcome
            switch choice {
            case .option(let optionId):
                outcome = .selected(optionId: optionId)
            case .form(let answers):
                if let toolID = questionToolCallID,
                   let selected = answers[toolID] ?? answers.values.first,
                   !selected.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    outcome = .selected(optionId: selected)
                } else {
                    outcome = .cancelled
                }
            case .cancelled:
                outcome = .cancelled
            }
            permissionContinuation.resume(returning: ACPRequestPermissionResult(outcome: outcome))
            return
        }

        if let pendingElicitation = pendingElicitations.removeValue(forKey: requestID) {
            let result = pendingElicitation.form.resolve(answer: choice)
            pendingElicitation.continuation.resume(returning: result)
            return
        }

        throw ACPConnectionError.unknownInteractionRequest(requestID)
    }

    /// Switches the session's active mode (`session/set_config_option` or legacy `session/set_mode`)
    /// without restarting the agent process.
    public func setSessionMode(_ modeID: String) async throws {
        guard let acpTransport = transport, !sessionID.isEmpty else {
            throw ACPConnectionError.notStarted
        }
        if (configState.modeState?.currentModeId ?? lastKnownModeID) == modeID {
            return
        }
        if configState.hasConfigOptions || configState.modeState != nil {
            _ = try await setConfigOption(ACPSessionConfigState.sessionModeOptionID, .string(modeID))
        } else {
            let _: ACPEmptyObject = try await acpTransport.request(
                method: "session/set_mode",
                params: ACPSetSessionModeParams(sessionId: sessionID, modeId: modeID),
                timeout: sessionSetupTimeout
            )
            configState.applyCurrentModeUpdate(modeID)
        }
        lastKnownModeID = modeID
    }

    public func syncMode(approvalMode: VitruvianCodeApprovalMode, planSwitch: Bool) async throws {
        // Asking OpenCode for "default" failed every turn before its prompt was sent.
        guard hooks.syncsApprovalMode else { return }
        let target = (planSwitch || approvalMode == .plan) ? "plan" : "default"
        try await setSessionMode(target)
    }

    public func syncPlanMode(_ planSwitch: Bool) async throws {
        let current = modeProvider()
        try await syncMode(approvalMode: current.mode, planSwitch: planSwitch)
    }

    public func setConfigOption(
        _ id: String,
        _ value: AgentConfigValue
    ) async throws -> [AgentConfigOption] {
        guard let acpTransport = transport, !sessionID.isEmpty else {
            throw ACPConnectionError.notStarted
        }

        let action = try configState.planUpdate(id: id, value: value)
        switch action {
        case .setConfigOption(let configId, let acpValue):
            let result: ACPSetSessionConfigOptionResult = try await acpTransport.request(
                method: "session/set_config_option",
                params: ACPSetSessionConfigOptionParams(
                    sessionId: sessionID,
                    configId: configId,
                    value: acpValue
                ),
                timeout: sessionSetupTimeout
            )
            if let updated = result.configOptions {
                configState.applyConfigOptions(updated)
            } else {
                var manual = configState.configOptions
                if let idx = manual.firstIndex(where: { $0.id == configId }) {
                    manual[idx].currentValue = acpValue
                    configState.applyConfigOptions(manual)
                }
            }
            var caps = capabilities
            caps.configOptions = configState.hasConfigOptions
            capabilities = caps
            return configState.agentConfigOptions

        case .setMode(let modeId):
            let _: ACPEmptyObject = try await acpTransport.request(
                method: "session/set_mode",
                params: ACPSetSessionModeParams(sessionId: sessionID, modeId: modeId),
                timeout: sessionSetupTimeout
            )
            configState.applyCurrentModeUpdate(modeId)
            return configState.agentConfigOptions
        }
    }

    public func stop() async {
        guard !isStopped else { return }
        isStopping = true
        isStopped = true
        hasFinalizedLogTarget = true

        inactivityTimerTask?.cancel()
        inactivityTimerTask = nil
        cancelGraceTask?.cancel()
        cancelGraceTask = nil
        cancelAllPendingInteractions()
        deniedToolCallIDs.removeAll()

        if capabilities.closeSession, !sessionID.isEmpty, let acpTransport = transport {
            _ = try? await acpTransport.request(
                method: "session/close",
                params: ACPSessionCloseParams(sessionId: sessionID),
                timeout: min(Self.sessionCloseTimeout, sessionSetupTimeout),
                as: ACPEmptyObject.self
            )
        }

        await clientTerminals.closeAll()
        // End the process group before closing the transport: an outgoing
        // write blocked on a full stdin pipe holds the transport actor, so
        // closing it first would wait forever. The group's exit fails that
        // write and frees the actor.
        if let launchedProcess {
            await launchedProcess.terminate(terminationGrace)
        }
        if let acpTransport = transport {
            await acpTransport.close(reason: "ACP connection stopped")
        }

        for _ in 0..<5 {
            await Task.yield()
        }
        flushBufferedLogs(allowFallbackSessionID: true)

        exitMonitorTask?.cancel()
        exitMonitorTask = nil
        stderrDrainTask?.cancel()
        stderrDrainTask = nil
        eventsContinuation.finish()
    }

    // MARK: - Host extensions

    /// Sends an `_vitruvian/` extension request (`_vitruvian/fork`, `_vitruvian/mcpStatus`) and
    /// returns its raw result. Any other method is refused, so this is not a way to reach
    /// methods the app does not use.
    public func sendExtensionRequest(method: String, params: ACPJSONValue) async throws -> ACPJSONValue {
        guard method.hasPrefix("_vitruvian/") else {
            throw ACPRPCError(code: ACPRPCError.methodNotFound, message: "Not an extension method: \(method)")
        }
        guard let acpTransport = transport, !sessionID.isEmpty, !isStopped else {
            throw ACPConnectionError.notStarted
        }
        return try await acpTransport.request(
            method: method,
            params: params,
            timeout: sessionSetupTimeout
        )
    }

    /// The open session's ID, or nil before `start` returns.
    public var openSessionID: String? { sessionID.isEmpty ? nil : sessionID }

    /// Values (secrets) the chat log and stderr lines must never show, replaced with `***`.
    public func addRedactions(_ values: [String]) {
        let merged = Set(redactions).union(values.filter { !$0.isEmpty })
        redactions = merged.sorted { $0.count > $1.count }
    }

    /// Writes one line the host wants in the chat's log, redacted like the rest.
    public func recordHostLog(_ line: String) {
        recordLogLine("[host] \(line)")
    }

    /// Puts an event of the host's own on this connection's stream (a notice raised before the
    /// session opens). Dropped once the connection has stopped.
    public func emitHostEvent(_ event: AgentEvent) {
        emit(event)
    }

    // MARK: - Incoming Notifications (`session/update`)

    private func handleIncomingNotification(method: String, params: ACPJSONValue?) async {
        if method != "session/update", let hook = hooks.onExtensionNotification {
            let events = hook(method, params)
            if !events.isEmpty {
                for event in events { emit(event) }
                return
            }
        }
        guard method == "session/update", let params else {
            recordLogLine("[acp] ignored notification \(method)")
            return
        }
        guard let notification = try? params.decode(ACPSessionNotification.self) else {
            recordLogLine("[acp] failed to decode session/update: \(params.serializedJSONString())")
            return
        }

        // Suppress replayed history during `session/load` or when marked as replay
        // (`AcpSessionRuntime.ts:1720-1766`).
        if Self.isExplicitReplay(notification) {
            return
        }
        if isLoadingSessionReplay {
            if case .configOptionUpdate(let options) = notification.update {
                configState.applyConfigOptions(options)
            } else if case .currentModeUpdate(let modeId) = notification.update {
                configState.applyCurrentModeUpdate(modeId)
            }
            return
        }
        if !sessionID.isEmpty && notification.sessionId != sessionID {
            return
        }

        await handleSessionNotification(notification)
    }

    private func handleSessionNotification(
        _ incomingNotification: ACPSessionNotification,
        skipTransform: Bool = false
    ) async {
        let activeNotification: ACPSessionNotification
        if !skipTransform, let transformSessionUpdate = hooks.transformSessionUpdate {
            let transformed = transformSessionUpdate(incomingNotification)
            for extra in transformed.extraEvents {
                emitTrackedEvent(extra)
            }
            guard let nextNotification = transformed.notification else {
                resetPromptInactivityTimer()
                return
            }
            activeNotification = nextNotification
        } else {
            activeNotification = incomingNotification
        }

        switch activeNotification.update {
        case .agentMessageChunk(let block):
            guard isPromptActive, let text = block.textContent, !text.isEmpty else { break }
            activePromptCollectedText += text
            emit(.text(text))

        case .agentThoughtChunk(let block):
            guard isPromptActive, let text = block.textContent, !text.isEmpty else { break }
            emit(.thinking(text))

        case .userMessageChunk:
            // User message echoes / history replay chunks are never emitted as assistant output.
            break

        case .toolCall(let call):
            let merged = mergeToolCall(call)
            let terminalOutputs = await collectTerminalOutputs(for: merged, sessionId: activeNotification.sessionId)
            let wasDenied = deniedToolCallIDs.contains(merged.toolCallId)
            let isError = Self.isErrorToolStatus(merged.status) || wasDenied
            let step = Self.makeToolStep(from: merged, terminalOutputs: terminalOutputs, forceError: wasDenied)
            emit(.toolStep(step))
            if Self.isTerminalToolStatus(merged.status) {
                trackedToolCalls.removeValue(forKey: merged.toolCallId)
                deniedToolCallIDs.remove(merged.toolCallId)
                emit(
                    .toolStepResult(
                        id: merged.toolCallId,
                        output: VitruvianCodeToolStep.truncatedOutput(
                            Self.extractToolOutput(from: merged, terminalOutputs: terminalOutputs)
                        ),
                        isError: isError
                    )
                )
            }

        case .toolCallUpdate(let update):
            let hadPrior = trackedToolCalls[update.toolCallId] != nil
            let merged = mergeToolCall(update)
            let terminalOutputs = await collectTerminalOutputs(for: merged, sessionId: activeNotification.sessionId)
            let wasDenied = deniedToolCallIDs.contains(merged.toolCallId)
            let isError = Self.isErrorToolStatus(merged.status) || wasDenied
            if Self.isTerminalToolStatus(merged.status) {
                if !hadPrior || Self.hasStepDetails(update) || wasDenied {
                    emit(.toolStep(Self.makeToolStep(from: merged, terminalOutputs: terminalOutputs, forceError: wasDenied)))
                }
                trackedToolCalls.removeValue(forKey: merged.toolCallId)
                deniedToolCallIDs.remove(merged.toolCallId)
                emit(
                    .toolStepResult(
                        id: merged.toolCallId,
                        output: VitruvianCodeToolStep.truncatedOutput(
                            Self.extractToolOutput(from: merged, terminalOutputs: terminalOutputs)
                        ),
                        isError: isError
                    )
                )
            } else {
                emit(.toolStep(Self.makeToolStep(from: merged, terminalOutputs: terminalOutputs, forceError: wasDenied)))
            }

        case .plan(let entries):
            let mapped = entries.map { entry in
                PlanEntry(
                    content: entry.content,
                    status: PlanEntry.Status(acpRawValue: entry.status),
                    priority: entry.priority.flatMap(PlanEntry.Priority.init(rawValue:))
                )
            }
            emit(.planReplaced(mapped))

        case .availableCommandsUpdate(let commands):
            let mapped = Self.mapAvailableCommands(commands)
            emit(.slashCommands(mapped.map(\.name)))
            emit(.availableCommands(mapped))

        case .currentModeUpdate(let modeId):
            configState.applyCurrentModeUpdate(modeId)
            let projected = configState.agentConfigOptions
            if !projected.isEmpty {
                emit(.configOptions(projected))
            }

        case .configOptionUpdate(let options):
            configState.applyConfigOptions(options)
            var caps = capabilities
            caps.configOptions = configState.hasConfigOptions
            capabilities = caps
            emit(.configOptions(configState.agentConfigOptions))

        case .sessionInfoUpdate(let info):
            emit(.sessionInfo(title: info.title, updatedAt: info.updatedAt))

        case .usageUpdate(let usage):
            let input = usage.inputTokens ?? usage.used ?? 0
            let cached = usage.cachedTokens ?? 0
            let output = usage.outputTokens ?? 0
            let window = usage.size ?? 0
            if window > 0 {
                lastKnownContextWindow = window
            }
            emit(
                .contextUsage(
                    VitruvianCodeContextUsage(
                        inputTokens: input,
                        cachedTokens: cached,
                        outputTokens: output,
                        contextWindow: window
                    )
                )
            )

        case .unknown(let kind, let rawJSON):
            if kind == "compaction_update", let obj = rawJSON.objectValue {
                let id = obj["compactionId"]?.stringValue ?? obj["id"]?.stringValue ?? ""
                let status = obj["status"]?.stringValue ?? "completed"
                let summary = obj["summary"]?.stringValue
                emit(.compaction(id: id, status: status, summary: summary))
            } else if kind == "notice", let obj = rawJSON.objectValue {
                let severity = obj["severity"]?.stringValue ?? "info"
                let title = obj["title"]?.stringValue ?? obj["message"]?.stringValue ?? ""
                let detail = obj["detail"]?.stringValue
                emit(.notice(severity: severity, title: title, detail: detail))
            } else {
                recordLogLine("[acp] unknown session/update '\(kind)': \(rawJSON.serializedJSONString())")
            }
        }

        resetPromptInactivityTimer()
    }

    // MARK: - Incoming Agent Requests

    private func handleIncomingRequest(method: String, params: ACPJSONValue?) async throws -> ACPJSONValue {
        switch method {
        case "session/request_permission":
            guard let params,
                  let decoded = try? params.decode(ACPRequestPermissionParams.self) else {
                throw ACPRPCError(code: ACPRPCError.invalidParams, message: "Invalid session/request_permission params")
            }
            let result = await handlePermissionRequest(decoded)
            return try ACPJSONValue.fromEncodable(result)

        case "elicitation/create":
            guard policy.elicitation else {
                throw ACPRPCError(code: ACPRPCError.methodNotFound, message: "Method not found: elicitation/create")
            }
            guard let params,
                  let decoded = try? params.decode(ACPElicitationCreateParams.self) else {
                throw ACPRPCError(code: ACPRPCError.invalidParams, message: "Invalid elicitation/create params")
            }
            // The agent may only use the elicitation modes the client offered at `initialize`.
            if (decoded.mode == "url" || decoded.url != nil) && !policy.elicitationURLMode {
                throw ACPRPCError(
                    code: ACPRPCError.invalidParams,
                    message: "URL elicitation is not supported: this client offers forms only"
                )
            }
            let result = await handleElicitationRequest(decoded)
            return try ACPJSONValue.fromEncodable(result)

        case "fs/read_text_file":
            guard let files = clientFiles else {
                throw ACPRPCError(code: ACPRPCError.internalError, message: "Session files not initialized")
            }
            guard let params,
                  let decoded = try? params.decode(ACPReadTextFileParams.self) else {
                throw ACPRPCError(code: ACPRPCError.invalidParams, message: "Invalid fs/read_text_file params")
            }
            resetPromptInactivityTimer()
            do {
                let result = try files.readTextFile(decoded, policy: policy)
                let synthesized = hooks.onClientFileRead?(decoded.path, true) ?? []
                for note in synthesized {
                    await handleSessionNotification(note, skipTransform: true)
                }
                return try ACPJSONValue.fromEncodable(result)
            } catch {
                let synthesized = hooks.onClientFileRead?(decoded.path, false) ?? []
                for note in synthesized {
                    await handleSessionNotification(note, skipTransform: true)
                }
                throw error
            }

        case "fs/write_text_file":
            guard let files = clientFiles else {
                throw ACPRPCError(code: ACPRPCError.internalError, message: "Session files not initialized")
            }
            guard let params,
                  let decoded = try? params.decode(ACPWriteTextFileParams.self) else {
                throw ACPRPCError(code: ACPRPCError.invalidParams, message: "Invalid fs/write_text_file params")
            }
            let result = try files.writeTextFile(decoded, policy: policy)
            return try ACPJSONValue.fromEncodable(result)

        case "terminal/create":
            guard let files = clientFiles else {
                throw ACPRPCError(code: ACPRPCError.internalError, message: "Session files not initialized")
            }
            guard let params,
                  let decoded = try? params.decode(ACPTerminalCreateParams.self) else {
                throw ACPRPCError(code: ACPRPCError.invalidParams, message: "Invalid terminal/create params")
            }
            let result = try await clientTerminals.create(
                decoded,
                policy: policy,
                files: files,
                expectedSessionID: sessionID
            )
            return try ACPJSONValue.fromEncodable(result)

        case "terminal/output":
            guard let params,
                  let decoded = try? params.decode(ACPTerminalOutputParams.self) else {
                throw ACPRPCError(code: ACPRPCError.invalidParams, message: "Invalid terminal/output params")
            }
            let result = try await clientTerminals.output(
                decoded,
                policy: policy,
                expectedSessionID: sessionID
            )
            return try ACPJSONValue.fromEncodable(result)

        case "terminal/wait_for_exit":
            guard let params,
                  let decoded = try? params.decode(ACPTerminalWaitForExitParams.self) else {
                throw ACPRPCError(code: ACPRPCError.invalidParams, message: "Invalid terminal/wait_for_exit params")
            }
            let result = try await clientTerminals.waitForExit(
                decoded,
                policy: policy,
                expectedSessionID: sessionID
            )
            return try ACPJSONValue.fromEncodable(result)

        case "terminal/kill":
            guard let params,
                  let decoded = try? params.decode(ACPTerminalKillParams.self) else {
                throw ACPRPCError(code: ACPRPCError.invalidParams, message: "Invalid terminal/kill params")
            }
            let result = try await clientTerminals.kill(
                decoded,
                policy: policy,
                expectedSessionID: sessionID
            )
            return try ACPJSONValue.fromEncodable(result)

        case "terminal/release":
            guard let params,
                  let decoded = try? params.decode(ACPTerminalReleaseParams.self) else {
                throw ACPRPCError(code: ACPRPCError.invalidParams, message: "Invalid terminal/release params")
            }
            let result = try await clientTerminals.release(
                decoded,
                policy: policy,
                expectedSessionID: sessionID
            )
            return try ACPJSONValue.fromEncodable(result)

        default:
            throw ACPRPCError(code: ACPRPCError.methodNotFound, message: "Method not found: \(method)")
        }
    }

    private func handlePermissionRequest(
        _ request: ACPRequestPermissionParams
    ) async -> ACPRequestPermissionResult {
        if isStopping || isStopped {
            return ACPRequestPermissionResult(outcome: .cancelled)
        }

        let interactionID = "perm-\(nextInteractionNumber)"
        // Questions arrive inside `session/request_permission` before permission policy runs
        // so full-access mode never silently answers a question (`AntigravityProtocol.ts:80`).
        if let question = hooks.permissionInterceptor?(request, interactionID) {
            nextInteractionNumber += 1
            pendingQuestionToolCallIDs[interactionID] = request.toolCall.toolCallId
            inactivityTimerTask?.cancel()
            inactivityTimerTask = nil
            let result = await withCheckedContinuation { continuation in
                if isStopping || isStopped {
                    continuation.resume(returning: ACPRequestPermissionResult(outcome: .cancelled))
                    return
                }
                pendingPermissions[interactionID] = continuation
                emit(.question(question))
            }
            pendingQuestionToolCallIDs.removeValue(forKey: interactionID)
            resetPromptInactivityTimer()
            return result
        }

        let mappedOptions = request.options.map { option in
            AgentPermissionOption(
                id: option.optionId,
                name: option.name,
                kind: Self.mapOptionKind(option.kind)
            )
        }

        let current = modeProvider()
        let sessionCwd = clientFiles?.workingDirectory ?? launchSpec.workingDirectory
        if let automaticOutcome = policy.resolvePermissionOutcome(
            mode: current.mode,
            planSwitch: current.planSwitch,
            toolKind: request.toolCall.kind,
            sandbox: policy.sandbox,
            locations: request.toolCall.locations,
            cwd: sessionCwd,
            approvalPolicy: policy.approvalPolicy,
            options: mappedOptions
        ) {
            if Self.isDeniedPermissionOutcome(automaticOutcome, options: mappedOptions) {
                deniedToolCallIDs.insert(request.toolCall.toolCallId)
            }
            resetPromptInactivityTimer()
            return ACPRequestPermissionResult(outcome: automaticOutcome)
        }

        nextInteractionNumber += 1

        let toolName = Self.nonEmpty(request.toolCall.title)
            ?? Self.nonEmpty(request.toolCall.kind)
            ?? "tool"
        let commandOrPath = Self.extractCommandOrPath(from: request.toolCall)
        let approvalRequest = VitruvianCodeApprovalRequest(
            id: request.toolCall.toolCallId,
            toolName: toolName,
            commandOrPath: commandOrPath,
            status: .pending,
            requestID: interactionID,
            options: mappedOptions
        )

        inactivityTimerTask?.cancel()
        inactivityTimerTask = nil
        let result = await withCheckedContinuation { continuation in
            if isStopping || isStopped {
                continuation.resume(returning: ACPRequestPermissionResult(outcome: .cancelled))
                return
            }
            pendingPermissions[interactionID] = continuation
            emit(.approval(approvalRequest))
        }
        if Self.isDeniedPermissionOutcome(result.outcome, options: mappedOptions) {
            deniedToolCallIDs.insert(request.toolCall.toolCallId)
        }
        resetPromptInactivityTimer()
        return result
    }

    private func handleElicitationRequest(
        _ request: ACPElicitationCreateParams
    ) async -> ACPElicitationCreateResult {
        if isStopping || isStopped {
            return ACPElicitationCreateResult(action: .cancel)
        }

        let interactionID = "elicitation-\(nextInteractionNumber)"
        nextInteractionNumber += 1

        guard let parsed = ACPElicitationForm.parse(requestID: interactionID, params: request) else {
            return ACPElicitationCreateResult(action: .decline)
        }

        inactivityTimerTask?.cancel()
        inactivityTimerTask = nil
        let result = await withCheckedContinuation { continuation in
            if isStopping || isStopped {
                continuation.resume(returning: ACPElicitationCreateResult(action: .cancel))
                return
            }
            pendingElicitations[interactionID] = (parsed, continuation)
            emit(.question(parsed.question))
        }
        resetPromptInactivityTimer()
        return result
    }

    // MARK: - Unexpected Exit, Transport Failure & Logging

    private func startExitMonitor(_ waitForExit: @escaping @Sendable () async -> AgentProcessExit) {
        exitMonitorTask = Task { @MainActor [weak self] in
            let exit = await waitForExit()
            guard let self, !Task.isCancelled, !self.isStopping else { return }
            await self.handleUnexpectedExit(exit)
        }
    }

    private func handleUnexpectedExit(_ exit: AgentProcessExit) async {
        guard !isStopping, !hasEmittedTerminalFailure else { return }
        // Allow buffered stderr lines a moment to arrive before building the failure detail.
        try? await Task.sleep(nanoseconds: 15_000_000)
        guard !isStopping, !hasEmittedTerminalFailure else { return }

        let statusDesc: String
        if let signalName = exit.signalName {
            statusDesc = "signal \(signalName)"
        } else if let code = exit.exitCode {
            statusDesc = "exit code \(code)"
        } else {
            statusDesc = "status \(exit.terminationStatus)"
        }
        let stderr = recentStderrDetail()
        let message = "Agent process exited unexpectedly (\(statusDesc))."
        recordLogLine("[acp] \(message)")
        let failure = hooks.onUnexpectedExitFailure?(exit, stderr) ?? AgentFailure(
            kind: .exited,
            message: message,
            detail: stderr
        )
        emitTerminalPromptFailure(failure)
        if let acpTransport = transport {
            await acpTransport.close(reason: message)
        }
    }

    private func handleTransportFailure(_ error: ACPTransportError) async {
        guard !isStopping, !hasEmittedTerminalFailure else { return }
        let kind: AgentFailure.Kind
        switch error {
        case .requestTimedOut:
            kind = .timedOut
        case .tooManyMalformedLines, .decodingFailed, .encodingFailed, .rpcError:
            kind = .protocolError
        case .connectionClosed:
            kind = .exited
        }
        let message = error.errorDescription ?? "ACP transport failed."
        let failure = AgentFailure(kind: kind, message: message, detail: recentStderrDetail())
        emitTerminalPromptFailure(failure)
    }

    private static func makeStartupFailure(from error: any Error, detail: String?) -> AgentFailure {
        if let authError = error as? ACPAuthFailureError {
            return AgentFailure(kind: .auth, message: authError.message, detail: detail)
        }
        if let transportError = error as? ACPTransportError {
            switch transportError {
            case .rpcError(let rpc):
                return AgentFailure(kind: .startupFailed, message: rpc.message, detail: detail)
            case .requestTimedOut:
                return AgentFailure(
                    kind: .timedOut,
                    message: transportError.errorDescription ?? error.localizedDescription,
                    detail: detail
                )
            case .tooManyMalformedLines, .decodingFailed, .encodingFailed:
                return AgentFailure(
                    kind: .protocolError,
                    message: transportError.errorDescription ?? error.localizedDescription,
                    detail: detail
                )
            case .connectionClosed(let reason):
                return AgentFailure(kind: .startupFailed, message: reason, detail: detail)
            }
        }
        let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        return AgentFailure(kind: .startupFailed, message: message, detail: detail)
    }

    func emitExternalTerminalFailure(_ failure: AgentFailure, duringPrompt: Bool) {
        guard !hasEmittedTerminalFailure else { return }
        if duringPrompt && !isPromptActive {
            isPromptActive = true
            defer { isPromptActive = false }
            emitTerminalPromptFailure(failure)
        } else {
            emitTerminalPromptFailure(failure)
        }
    }

    private func emitTerminalPromptFailure(_ failure: AgentFailure) {
        guard !hasEmittedTerminalFailure else { return }
        hasEmittedTerminalFailure = true
        hasFinalizedLogTarget = true
        inactivityTimerTask?.cancel()
        inactivityTimerTask = nil
        cancelAllPendingInteractions()
        if hooks.finishSubagentsOnTurnEnd {
            finishRemainingSubagents()
        }
        emit(.connectionFailed(failure))
        if isPromptActive {
            let collected = activePromptCollectedText.isEmpty ? nil : activePromptCollectedText
            emit(
                .finished(
                    status: "error",
                    response: collected,
                    error: failure.message,
                    conversationID: sessionID.isEmpty ? nil : sessionID,
                    metrics: nil
                )
            )
        }
        flushBufferedLogs(allowFallbackSessionID: true)
        eventsContinuation.finish()
    }

    private func cancelAllPendingInteractions() {
        pendingQuestionToolCallIDs.removeAll()
        let permissions = pendingPermissions
        pendingPermissions.removeAll()
        for (_, continuation) in permissions {
            continuation.resume(returning: ACPRequestPermissionResult(outcome: .cancelled))
        }

        let elicitations = pendingElicitations
        pendingElicitations.removeAll()
        for (_, pending) in elicitations {
            pending.continuation.resume(returning: ACPElicitationCreateResult(action: .cancel))
        }
    }

    private var isPromptInactivityPaused: Bool {
        !trackedToolCalls.isEmpty
            || !pendingPermissions.isEmpty
            || !pendingElicitations.isEmpty
    }

    private func resetPromptInactivityTimer() {
        inactivityTimerTask?.cancel()
        inactivityTimerTask = nil
        guard isPromptActive,
              !isStopping,
              !isStopped,
              !hasEmittedTerminalFailure,
              !activePromptCancelled,
              !activePromptInactivityTimedOut,
              !isPromptInactivityPaused,
              let timeout = hooks.promptInactivityTimeout,
              timeout > 0 else {
            return
        }
        let nanos = UInt64(max(1_000_000, timeout * 1_000_000_000))
        inactivityTimerTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: nanos)
            guard !Task.isCancelled, let self else { return }
            self.handlePromptInactivityTimeout()
        }
    }

    private func handlePromptInactivityTimeout() {
        guard isPromptActive,
              !isStopping,
              !isStopped,
              !hasEmittedTerminalFailure,
              !activePromptCancelled,
              !activePromptInactivityTimedOut,
              !isPromptInactivityPaused,
              let acpTransport = transport,
              !sessionID.isEmpty else {
            return
        }
        activePromptInactivityTimedOut = true
        recordLogLine("[acp] prompt inactivity timeout reached; cancelling turn")
        cancelAllPendingInteractions()
        scheduleCancelGraceTimeout(
            reason: "The ACP agent did not finish cancellation after prompt inactivity timeout. Its process was stopped."
        )
        Task { @MainActor in
            try? await acpTransport.notify(
                method: "session/cancel",
                params: ACPSessionCancelParams(sessionId: sessionID)
            )
        }
    }

    /// Bounds the wait after `session/cancel`, stopping the process group if the agent ignores cancel
    /// (`AcpSessionRuntime.ts:83, 2386-2407`).
    private func scheduleCancelGraceTimeout(reason: String) {
        cancelGraceTask?.cancel()
        let grace = hooks.cancelGraceTimeout
        guard grace > 0 else { return }
        let nanos = UInt64(max(1_000_000, grace * 1_000_000_000))
        cancelGraceTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: nanos)
            guard !Task.isCancelled,
                  let self,
                  self.isPromptActive,
                  !self.isStopping,
                  !self.isStopped else {
                return
            }
            await self.forceStopAfterIgnoredCancel(reason: reason)
        }
    }

    private func forceStopAfterIgnoredCancel(reason: String) async {
        guard !isStopping, !isStopped else { return }
        isStopping = true
        hasFinalizedLogTarget = true
        inactivityTimerTask?.cancel()
        inactivityTimerTask = nil
        cancelGraceTask?.cancel()
        cancelGraceTask = nil
        cancelAllPendingInteractions()
        deniedToolCallIDs.removeAll()
        recordLogLine("[acp] \(reason)")

        await clientTerminals.closeAll()
        if let launchedProcess {
            await launchedProcess.terminate(terminationGrace)
        }
        if let acpTransport = transport {
            await acpTransport.close(reason: reason)
        }
    }

    private func finalizeStoppedConnection() {
        guard !isStopped else { return }
        isStopped = true
        flushBufferedLogs(allowFallbackSessionID: true)
        exitMonitorTask?.cancel()
        exitMonitorTask = nil
        stderrDrainTask?.cancel()
        stderrDrainTask = nil
        eventsContinuation.finish()
    }

    private func emitTrackedEvent(_ event: AgentEvent) {
        if case .subagent(let subagent, let started) = event {
            if started {
                if activeSubagentsByID[subagent.id] == nil {
                    activeSubagentOrder.append(subagent.id)
                }
                activeSubagentsByID[subagent.id] = subagent
            } else {
                activeSubagentsByID.removeValue(forKey: subagent.id)
                activeSubagentOrder.removeAll { $0 == subagent.id }
            }
        }
        emit(event)
    }

    private func finishRemainingSubagents() {
        guard !activeSubagentOrder.isEmpty else { return }
        let order = activeSubagentOrder
        activeSubagentOrder.removeAll()
        for id in order {
            guard let running = activeSubagentsByID.removeValue(forKey: id) else { continue }
            let completed = VitruvianCodeActiveSubagent(
                id: running.id,
                typeName: running.typeName,
                role: running.role,
                prompt: running.prompt,
                model: running.model,
                isRunning: false
            )
            emit(.subagent(completed, started: false))
        }
    }

    private static func mergedDirectories(_ first: [String], _ second: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for entry in first + second {
            let trimmed = entry.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, seen.insert(trimmed).inserted else { continue }
            result.append(trimmed)
        }
        return result
    }

    /// Shown when the picked agent sign-in method is no longer in the agent's `authMethods`.
    public nonisolated static let signInMethodGoneMessage = "The agent no longer offers this sign-in method."

    /// The sign-in methods for a sign-in failure on this connection.
    private func currentSignInMethods() -> [AgentSignInMethod] {
        if let custom = hooks.signInMethods {
            return custom(authMethods)
        }
        var spec = launchSpec
        if spec.workingDirectory?.isEmpty ?? true {
            spec.workingDirectory = clientFiles?.workingDirectory
        }
        return ACPAuth.signInMethods(
            advertised: authMethods,
            launchSpec: spec,
            terminalAdvertised: policy.authTerminal
        )
    }

    private func withSignInMethods(_ failure: AgentFailure) -> AgentFailure {
        guard failure.kind == .auth, failure.signInMethods.isEmpty else { return failure }
        return AgentFailure(
            kind: .auth,
            message: failure.message,
            detail: failure.detail,
            signInMethods: currentSignInMethods()
        )
    }

    /// A prompt failed because the agent needs sign-in: ACP's `auth_required` error (-32000), or
    /// its reason in the error data. Narrower than at start-up, so a tool's own "unauthorized"
    /// during a turn is not taken for a logged-out agent.
    private static func isPromptAuthRequiredError(_ error: any Error) -> Bool {
        guard case ACPTransportError.rpcError(let rpc) = error else { return false }
        if rpc.code == -32000 { return true }
        return (rpc.data?.serializedJSONString() ?? "").lowercased().contains("auth_required")
    }

    private static func isAuthRequiredError(_ error: any Error) -> Bool {
        if error is ACPAuthFailureError {
            return true
        }
        if case ACPTransportError.rpcError(let rpc) = error {
            if rpc.code == -32000 {
                return true
            }
            let lower = (rpc.message + " " + (rpc.data?.serializedJSONString() ?? "")).lowercased()
            return lower.contains("auth_required")
                || lower.contains("authentication required")
                || lower.contains("unauthenticated")
                || lower.contains("unauthorized")
                || lower.contains("not authenticated")
                || lower.contains("not logged in")
                || lower.contains("login required")
                || lower.contains("sign in")
        }
        return false
    }

    private static func errorDescription(_ error: any Error) -> String {
        if case ACPTransportError.rpcError(let rpc) = error {
            return rpc.message
        }
        return (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }

    private static func inactivityFailureMessage(timeout: TimeInterval?) -> String {
        guard let timeout, timeout >= 60 else {
            return "Agent stopped responding during the turn and was cancelled."
        }
        let minutes = Int((timeout / 60).rounded())
        return "Antigravity stopped responding after \(minutes) minute\(minutes == 1 ? "" : "s") without activity and was cancelled."
    }

    private func startStderrDrain(_ stderrStream: AsyncStream<Data>) {
        let lines = AgentProcess.lines(from: stderrStream)
        stderrDrainTask = Task { @MainActor [weak self] in
            for await line in lines {
                guard let self, !Task.isCancelled else { break }
                let redacted = self.redact(line)
                if !redacted.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    self.recentStderrLines.append(redacted)
                    if self.recentStderrLines.count > 20 {
                        self.recentStderrLines.removeFirst(self.recentStderrLines.count - 20)
                    }
                }
                self.recordLogLine("[stderr] \(redacted)", alreadyRedacted: true)
            }
        }
    }

    public func redact(_ text: String) -> String {
        guard !redactions.isEmpty, !text.isEmpty else { return text }
        var output = text
        for secret in redactions where !secret.isEmpty {
            output = output.replacingOccurrences(of: secret, with: "***")
        }
        return output
    }

    private func recordLogLine(_ line: String, alreadyRedacted: Bool = false) {
        guard statePaths != nil else { return }
        let safeLine = alreadyRedacted ? line : redact(line)
        if sessionID.isEmpty && !hasFinalizedLogTarget {
            bufferedLogLines.append(safeLine)
            return
        }
        let targetSessionID = sessionID.isEmpty ? fallbackLogSessionID : sessionID
        flushBufferedLogs(allowFallbackSessionID: hasFinalizedLogTarget)
        appendLineToChatLog(safeLine, targetSessionID: targetSessionID)
    }

    private func flushBufferedLogs(allowFallbackSessionID: Bool = false) {
        guard !bufferedLogLines.isEmpty else { return }
        let targetSessionID: String
        if !sessionID.isEmpty {
            targetSessionID = sessionID
        } else if allowFallbackSessionID {
            targetSessionID = fallbackLogSessionID
        } else {
            return
        }
        let pending = bufferedLogLines
        bufferedLogLines.removeAll()
        for line in pending {
            appendLineToChatLog(line, targetSessionID: targetSessionID)
        }
    }

    private func appendLineToChatLog(_ line: String, targetSessionID: String) {
        guard let statePaths, !targetSessionID.isEmpty else { return }
        let directory = statePaths.chatLogsDirectory
        let filePath = statePaths.chatLogPath(sessionID: targetSessionID)
        try? FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        let payload = Data((line + "\n").utf8)
        if FileManager.default.fileExists(atPath: filePath),
           let handle = FileHandle(forWritingAtPath: filePath) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: payload)
        } else {
            try? payload.write(to: URL(fileURLWithPath: filePath))
        }
    }

    private func recentStderrDetail() -> String? {
        guard !recentStderrLines.isEmpty else { return nil }
        return recentStderrLines.joined(separator: "\n")
    }

    private func emit(_ event: AgentEvent) {
        guard !isStopped else { return }
        eventsContinuation.yield(event)
    }

    // MARK: - Pure Mapping Helpers

    private func mergeToolCall(_ incoming: ACPToolCall) -> ACPToolCall {
        guard let previous = trackedToolCalls[incoming.toolCallId] else {
            trackedToolCalls[incoming.toolCallId] = incoming
            return incoming
        }
        let merged = Self.mergeToolCall(previous: previous, incoming: incoming)
        trackedToolCalls[incoming.toolCallId] = merged
        return merged
    }

    /// Merges an incoming ACP tool call update onto a previously tracked call without wiping
    /// earlier locations or diffs when a subsequent update omits them.
    static func mergeToolCall(previous: ACPToolCall, incoming: ACPToolCall) -> ACPToolCall {
        var merged = previous
        if let title = incoming.title { merged.title = title }
        if let kind = incoming.kind { merged.kind = kind }
        if let status = incoming.status { merged.status = status }
        if let incomingContent = incoming.content, !incomingContent.isEmpty {
            let incomingHasDiff = incomingContent.contains {
                if case .diff = $0 { return true }
                return false
            }
            if incomingHasDiff {
                merged.content = incomingContent
            } else {
                let priorDiffs = (previous.content ?? []).filter {
                    if case .diff = $0 { return true }
                    return false
                }
                merged.content = priorDiffs + incomingContent
            }
        }
        if let locations = incoming.locations, !locations.isEmpty {
            merged.locations = locations
        }
        if let rawInput = incoming.rawInput { merged.rawInput = rawInput }
        if let rawOutput = incoming.rawOutput { merged.rawOutput = rawOutput }
        if let meta = incoming._meta { merged._meta = meta }
        return merged
    }

    static func isDeniedPermissionOutcome(
        _ outcome: ACPPermissionOutcome,
        options: [AgentPermissionOption]
    ) -> Bool {
        switch outcome {
        case .cancelled:
            return true
        case .selected(let optionId):
            guard let chosen = options.first(where: { $0.id == optionId }) else {
                return false
            }
            return chosen.kind == .rejectOnce || chosen.kind == .rejectAlways
        }
    }

    private static func isErrorToolStatus(_ status: String?) -> Bool {
        switch status {
        case "failed", "cancelled", "canceled", "denied", "rejected":
            return true
        default:
            return false
        }
    }

    private static func isTerminalToolStatus(_ status: String?) -> Bool {
        guard let status else { return false }
        return status == "completed" || isErrorToolStatus(status)
    }

    private static func hasStepDetails(_ update: ACPToolCall) -> Bool {
        if let locations = update.locations, !locations.isEmpty {
            return true
        }
        if update.rawInput != nil {
            return true
        }
        if let content = update.content {
            return content.contains { item in
                if case .diff = item { return true }
                return false
            }
        }
        return false
    }

    private func collectTerminalOutputs(
        for call: ACPToolCall,
        sessionId: String
    ) async -> [String: String] {
        guard let contents = call.content else { return [:] }
        var outputs: [String: String] = [:]
        for item in contents {
            if case .terminal(let terminalId) = item,
               let snapshot = await clientTerminals.readOutputSnapshot(sessionId: sessionId, terminalId: terminalId) {
                outputs[terminalId] = snapshot.output
            }
        }
        return outputs
    }

    static func makeToolStep(
        from call: ACPToolCall,
        terminalOutputs: [String: String] = [:],
        forceError: Bool = false
    ) -> VitruvianCodeToolStep {
        let name = nonEmpty(call.title) ?? nonEmpty(call.kind) ?? "tool"
        let inputDict = call.rawInput?.objectValue?.mapValues(\.foundationObject)
        var step = VitruvianCodeToolStep.from(
            id: call.toolCallId,
            name: name,
            input: inputDict,
            isFinished: isTerminalToolStatus(call.status),
            output: extractToolOutput(from: call, terminalOutputs: terminalOutputs),
            isError: forceError || isErrorToolStatus(call.status)
        )

        if let acpKind = call.kind {
            switch acpKind {
            case "edit", "delete", "move":
                step.kind = .edit
            case "read":
                step.kind = .read
            case "search":
                step.kind = .search
            case "execute":
                step.kind = .bash
            default:
                break
            }
        }

        let mappedLocations: [VitruvianCodeToolStep.Location] = (call.locations ?? []).compactMap { location in
            let trimmed = location.path.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            return VitruvianCodeToolStep.Location(path: location.path, line: location.line)
        }
        if !mappedLocations.isEmpty {
            step.locations = mappedLocations
            step.filePath = mappedLocations[0].path
        }

        if let contents = call.content {
            var mappedDiffs: [VitruvianCodeToolStep.Diff] = []
            for item in contents {
                if case .diff(let path, let oldText, let newText) = item {
                    mappedDiffs.append(VitruvianCodeToolStep.Diff(path: path, oldText: oldText, newText: newText))
                }
            }
            if !mappedDiffs.isEmpty {
                step.diffs = mappedDiffs
                step.diffOld = mappedDiffs[0].oldText
                step.diffNew = mappedDiffs[0].newText
                if step.filePath == nil,
                   let firstDiffPath = mappedDiffs.first(where: { !$0.path.isEmpty })?.path {
                    step.filePath = firstDiffPath
                }
                if step.kind == .other {
                    step.kind = .edit
                }
            }
        }

        return step
    }

    private static func extractToolOutput(
        from call: ACPToolCall,
        terminalOutputs: [String: String] = [:]
    ) -> String? {
        if let contents = call.content {
            let textParts: [String] = contents.compactMap { item in
                switch item {
                case .content(let block):
                    return block.textContent
                case .terminal(let terminalId):
                    // Matches `resolveEmbeddedTerminalContent` (`clientTerminals.ts:408-432`).
                    return terminalOutputs[terminalId] ?? "[terminal \(terminalId)]"
                case .diff, .unknown:
                    return nil
                }
            }
            if !textParts.isEmpty {
                return textParts.joined(separator: "\n")
            }
        }
        if let rawOutput = call.rawOutput {
            if let str = rawOutput.stringValue {
                return str
            }
            if rawOutput != .null {
                return rawOutput.serializedJSONString()
            }
        }
        return nil
    }

    private static func extractCommandOrPath(from call: ACPToolCall) -> String {
        if let path = call.locations?.first?.path, !path.isEmpty {
            return path
        }
        if let contents = call.content {
            for item in contents {
                if case .diff(let path, _, _) = item, !path.isEmpty {
                    return path
                }
            }
        }
        if let obj = call.rawInput?.objectValue {
            for key in ["command", "cmd", "CommandLine", "path", "file_path", "filePath", "TargetFile", "url"] {
                if let val = obj[key]?.stringValue, !val.isEmpty {
                    return val
                }
            }
        }
        return nonEmpty(call.title) ?? ""
    }

    static func mapAvailableCommands(_ commands: [ACPAvailableCommand]) -> [VitruvianCodeSlashCommand] {
        func normalizedPlainText(_ value: String?) -> String {
            guard let value else { return "" }
            return value
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
                .joined(separator: " ")
        }
        return commands.compactMap { cmd -> VitruvianCodeSlashCommand? in
            let raw = cmd.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let stripped = raw.hasPrefix("/") ? String(raw.dropFirst()) : raw
            guard !stripped.isEmpty else { return nil }
            let description = normalizedPlainText(cmd.description)
            let rawHint = normalizedPlainText(cmd.input?.hint)
            return VitruvianCodeSlashCommand(
                name: stripped,
                description: description,
                argumentHint: rawHint.isEmpty ? nil : rawHint,
                isBuiltIn: false
            )
        }
    }

    nonisolated static func encodePromptBlocks(
        _ blocks: [PromptBlock],
        supportsImages: Bool,
        supportsEmbeddedContext: Bool,
        workingDirectory: String?,
        maxResourceBytes: Int = VitruvianCodeDiffParser.maxMentionFileBytes
    ) -> [ACPContentBlock] {
        blocks.compactMap { block in
            encodePromptBlock(
                block,
                supportsImages: supportsImages,
                supportsEmbeddedContext: supportsEmbeddedContext,
                workingDirectory: workingDirectory,
                maxResourceBytes: maxResourceBytes
            )
        }
    }

    private nonisolated static func encodePromptBlock(
        _ block: PromptBlock,
        supportsImages: Bool,
        supportsEmbeddedContext: Bool,
        workingDirectory: String?,
        maxResourceBytes: Int
    ) -> ACPContentBlock? {
        switch block {
        case .text(let text):
            return .text(text)

        case .image(let path):
            let fileURL = URL(fileURLWithPath: path)
            let mime = mimeType(forExtension: fileURL.pathExtension)
            if supportsImages, let imageData = try? Data(contentsOf: fileURL) {
                return .image(
                    data: imageData.base64EncodedString(),
                    mimeType: mime
                )
            }
            let size = (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? NSNumber)?.intValue
            return .resourceLink(
                uri: fileURL.absoluteString,
                name: fileURL.lastPathComponent,
                mimeType: mime,
                size: size
            )

        case .resource(let path):
            let outcome = VitruvianCodeDiffParser.readSafeWorkingDirectoryFileResult(
                path: path,
                workingDirectory: workingDirectory,
                maxBytes: maxResourceBytes,
                readContent: supportsEmbeddedContext
            )
            switch outcome {
            case .text(let resolvedPath, let content, _):
                let fileURL = URL(fileURLWithPath: resolvedPath)
                return .resource(
                    ACPEmbeddedResource(
                        uri: fileURL.absoluteString,
                        mimeType: textMimeType(forExtension: fileURL.pathExtension),
                        text: content
                    )
                )
            case .nonTextOrOversize(let resolvedPath, let byteCount):
                let fileURL = URL(fileURLWithPath: resolvedPath)
                return .resourceLink(
                    uri: fileURL.absoluteString,
                    name: fileURL.lastPathComponent,
                    mimeType: resourceLinkMimeType(forExtension: fileURL.pathExtension),
                    size: byteCount
                )
            case .outsideWorkingDirectory, .notRegularFileOrMissing:
                return nil
            }
        }
    }

    private nonisolated static func textMimeType(forExtension ext: String) -> String {
        switch ext.lowercased() {
        case "md", "markdown": return "text/markdown"
        case "json", "jsonc", "json5": return "application/json"
        case "swift": return "text/x-swift"
        case "ts", "tsx": return "text/typescript"
        case "js", "jsx", "mjs", "cjs": return "text/javascript"
        case "py": return "text/x-python"
        case "rs": return "text/x-rust"
        case "go": return "text/x-go"
        case "yaml", "yml": return "text/yaml"
        case "toml": return "text/toml"
        case "html", "htm": return "text/html"
        case "css": return "text/css"
        case "xml": return "application/xml"
        case "sh", "bash", "zsh": return "text/x-shellscript"
        default: return "text/plain"
        }
    }

    private nonisolated static func resourceLinkMimeType(forExtension ext: String) -> String {
        let lower = ext.lowercased()
        let imageMime = mimeType(forExtension: lower)
        if imageMime != "application/octet-stream" {
            return imageMime
        }
        let textMime = textMimeType(forExtension: lower)
        if textMime != "text/plain" || ["txt", "log", "csv", "tsv", "env", "ini", "cfg", "conf"].contains(lower) {
            return textMime
        }
        return "application/octet-stream"
    }

    private nonisolated static func mimeType(forExtension ext: String) -> String {
        switch ext.lowercased() {
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "gif": return "image/gif"
        case "webp": return "image/webp"
        case "heic": return "image/heic"
        case "svg": return "image/svg+xml"
        case "bmp": return "image/bmp"
        case "tif", "tiff": return "image/tiff"
        default: return "application/octet-stream"
        }
    }

    private static func mapStopReason(
        _ rawStopReason: String,
        wasCancelled: Bool
    ) -> (reason: AgentStopReason, status: String) {
        if rawStopReason == "cancelled" || wasCancelled {
            return (.cancelled, "cancelled")
        }
        switch rawStopReason {
        case "end_turn":
            return (.endTurn, "completed")
        case "max_tokens":
            return (.maxTokens, "completed")
        case "max_turn_requests":
            return (.maxTurnRequests, "completed")
        case "refusal":
            return (.refusal, "completed")
        default:
            return (.error, "error")
        }
    }

    private static func makeTurnMetrics(from usage: ACPUsage?) -> VitruvianCodeTurnMetrics? {
        guard let usage else { return nil }
        let hasAny = usage.inputTokens != nil || usage.outputTokens != nil || usage.cachedReadTokens != nil
        guard hasAny else { return nil }
        return VitruvianCodeTurnMetrics(
            inputTokens: usage.inputTokens,
            outputTokens: usage.outputTokens,
            cachedTokens: (usage.cachedReadTokens ?? 0) + (usage.cachedWriteTokens ?? 0)
        )
    }

    private static func mapOptionKind(_ kind: ACPPermissionOptionKind) -> AgentPermissionOption.Kind {
        switch kind {
        case .allowOnce: return .allowOnce
        case .allowAlways: return .allowAlways
        case .rejectOnce: return .rejectOnce
        case .rejectAlways: return .rejectAlways
        }
    }

    private static func encodeMCPServers(
        _ servers: [AgentSessionRequest.MCPServer],
        allowHTTP: Bool
    ) -> [ACPMCPServer] {
        servers.compactMap { (server: AgentSessionRequest.MCPServer) -> ACPMCPServer? in
            if case .http = server, !allowHTTP {
                return nil
            }
            return ACPMCPServer(from: server)
        }
    }

    private static func isExplicitReplay(_ notification: ACPSessionNotification) -> Bool {
        if notification._meta?["isReplay"]?.boolValue == true
            || notification._meta?["replay"]?.boolValue == true {
            return true
        }
        return false
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }
}
