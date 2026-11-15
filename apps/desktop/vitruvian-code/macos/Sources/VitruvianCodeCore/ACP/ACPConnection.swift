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
        }
    }
}

/// Live `AgentConnection` speaking Agent Client Protocol (ACP) v1 over newline-delimited JSON-RPC 2.0.
@MainActor
public final class ACPConnection: AgentConnection {
    public typealias ProcessFactory = @Sendable (AgentProcessLaunchSpec) throws -> ACPLaunchedProcess
    public typealias ModeProvider = @MainActor () -> (mode: VitruvianCodeApprovalMode, planSwitch: Bool)

    public private(set) var capabilities = AgentCapabilities()
    public private(set) var authMethods: [ACPAuthMethod] = []
    public let events: AsyncStream<AgentEvent>

    private let launchSpec: AgentProcessLaunchSpec
    private let policy: ACPClientPolicy
    private let processFactory: ProcessFactory
    private let modeProvider: ModeProvider
    private let redactions: [String]
    private let statePaths: VitruvianCodeStatePaths?
    private let sessionSetupTimeout: TimeInterval
    private let terminationGrace: TimeInterval
    private let maxLineBytes: Int
    private let clientInfo: ACPImplementation

    private let eventsContinuation: AsyncStream<AgentEvent>.Continuation
    private let clientTerminals: ACPClientTerminals

    private var launchedProcess: ACPLaunchedProcess?
    private var transport: ACPTransport?
    private var exitMonitorTask: Task<Void, Never>?
    private var stderrDrainTask: Task<Void, Never>?

    private var sessionID = ""
    private var clientFiles: ACPClientFiles?
    private var configState = ACPSessionConfigState()
    private var isLoadingSessionReplay = false
    private var isStopping = false
    private var isStopped = false
    private var hasEmittedTerminalFailure = false

    // Active prompt tracking
    private var isPromptActive = false
    private var activePromptCancelled = false
    private var activePromptCollectedText = ""
    private var activePromptCompletionWaiters: [CheckedContinuation<Void, Never>] = []
    private var trackedToolCalls: [String: ACPToolCall] = [:]

    // Pending interactive requests from agent
    private var nextInteractionNumber = 1
    private var pendingPermissions: [String: CheckedContinuation<ACPRequestPermissionResult, Never>] = [:]
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
        guard !isStopped else {
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

        do {
            let launched = try processFactory(effectiveSpec)
            self.launchedProcess = launched
            self.clientFiles = ACPClientFiles(
                workingDirectory: request.workingDirectory,
                additionalDirectories: request.additionalDirectories
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

            let initParams = ACPInitializeParams(
                protocolVersion: ACPInitializeParams.v1ProtocolVersion,
                clientInfo: clientInfo,
                clientCapabilities: policy.clientCapabilities
            )
            let initResult: ACPInitializeResult = try await acpTransport.request(
                method: "initialize",
                params: initParams,
                timeout: sessionSetupTimeout
            )

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

            let mcpServers = Self.encodeMCPServers(request.mcpServers, allowHTTP: resolvedCapabilities.mcpHTTP)
            let extraDirs = request.additionalDirectories.isEmpty ? nil : request.additionalDirectories
            let meta: [String: ACPJSONValue]? = {
                guard let append = request.systemPrompt?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !append.isEmpty else {
                    return nil
                }
                return ["systemPrompt": .object(["append": .string(append)])]
            }()

            let setupResult: ACPSessionSetupResult
            let fallbackSessionID: String?

            if let resumeID = request.resumeSessionID?.trimmingCharacters(in: .whitespacesAndNewlines),
               !resumeID.isEmpty {
                if resolvedCapabilities.resumeSession {
                    let resumeParams = ACPSessionResumeParams(
                        sessionId: resumeID,
                        cwd: request.workingDirectory,
                        mcpServers: mcpServers,
                        additionalDirectories: extraDirs,
                        _meta: meta
                    )
                    setupResult = try await acpTransport.request(
                        method: "session/resume",
                        params: resumeParams,
                        timeout: sessionSetupTimeout
                    )
                    fallbackSessionID = resumeID
                } else if resolvedCapabilities.loadSession {
                    isLoadingSessionReplay = true
                    defer { isLoadingSessionReplay = false }
                    let loadParams = ACPSessionLoadParams(
                        sessionId: resumeID,
                        cwd: request.workingDirectory,
                        mcpServers: mcpServers,
                        additionalDirectories: extraDirs,
                        _meta: meta
                    )
                    setupResult = try await acpTransport.request(
                        method: "session/load",
                        params: loadParams,
                        timeout: sessionSetupTimeout
                    )
                    fallbackSessionID = resumeID
                } else {
                    let newParams = ACPSessionNewParams(
                        cwd: request.workingDirectory,
                        mcpServers: mcpServers,
                        additionalDirectories: extraDirs,
                        _meta: meta
                    )
                    setupResult = try await acpTransport.request(
                        method: "session/new",
                        params: newParams,
                        timeout: sessionSetupTimeout
                    )
                    fallbackSessionID = nil
                }
            } else {
                let newParams = ACPSessionNewParams(
                    cwd: request.workingDirectory,
                    mcpServers: mcpServers,
                    additionalDirectories: extraDirs,
                    _meta: meta
                )
                setupResult = try await acpTransport.request(
                    method: "session/new",
                    params: newParams,
                    timeout: sessionSetupTimeout
                )
                fallbackSessionID = nil
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
            resolvedCapabilities.configOptions = configState.hasConfigOptions
            self.capabilities = resolvedCapabilities

            self.sessionID = establishedID
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
                let failure = Self.makeStartupFailure(from: error, detail: recentStderrDetail())
                recordLogLine("[acp] startup failed: \(failure.message)")
                emitTerminalPromptFailure(failure)
            }
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
            throw error
        }
    }

    public func prompt(_ blocks: [PromptBlock]) async throws -> AgentStopReason {
        guard let acpTransport = transport, !sessionID.isEmpty else {
            throw ACPConnectionError.notStarted
        }
        guard !isStopped else {
            throw ACPConnectionError.alreadyStopped
        }

        let contentBlocks = blocks.map { block in
            Self.encodePromptBlock(block, supportsImages: capabilities.images)
        }
        let params = ACPPromptParams(sessionId: sessionID, prompt: contentBlocks)

        isPromptActive = true
        activePromptCancelled = false
        activePromptCollectedText = ""
        trackedToolCalls.removeAll()

        defer {
            isPromptActive = false
            let waiters = activePromptCompletionWaiters
            activePromptCompletionWaiters.removeAll()
            for waiter in waiters {
                waiter.resume()
            }
        }

        do {
            // `session/prompt` has no request timeout (`AcpSessionRuntime.ts` / `BRIEF.md`).
            let result: ACPPromptResult = try await acpTransport.request(
                method: "session/prompt",
                params: params,
                timeout: nil
            )

            let mapped = Self.mapStopReason(
                result.stopReason,
                wasCancelled: activePromptCancelled
            )
            let metrics = Self.makeTurnMetrics(from: result.usage)
            let collected = activePromptCollectedText.isEmpty ? nil : activePromptCollectedText
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
                return .cancelled
            }

            // Give the exit monitor a brief turn to observe process termination if the pipe closed first.
            if !hasEmittedTerminalFailure, let launchedProcess {
                for _ in 0..<20 where !hasEmittedTerminalFailure && !isStopping {
                    await Task.yield()
                    try? await Task.sleep(nanoseconds: 5_000_000)
                }
                if !hasEmittedTerminalFailure && !isStopping {
                    let detail = recentStderrDetail()
                    let failure = AgentFailure(
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
        guard isPromptActive, let acpTransport = transport, !sessionID.isEmpty else {
            return
        }
        activePromptCancelled = true
        cancelAllPendingInteractions()
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
            let outcome: ACPPermissionOutcome
            switch choice {
            case .option(let optionId):
                outcome = .selected(optionId: optionId)
            case .cancelled, .form:
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

        cancelAllPendingInteractions()

        if capabilities.closeSession, !sessionID.isEmpty, let acpTransport = transport {
            _ = try? await acpTransport.request(
                method: "session/close",
                params: ACPSessionCloseParams(sessionId: sessionID),
                timeout: min(5.0, sessionSetupTimeout),
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

    // MARK: - Incoming Notifications (`session/update`)

    private func handleIncomingNotification(method: String, params: ACPJSONValue?) async {
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

        switch notification.update {
        case .agentMessageChunk(let block):
            guard isPromptActive, let text = block.textContent, !text.isEmpty else { return }
            activePromptCollectedText += text
            emit(.text(text))

        case .agentThoughtChunk(let block):
            guard isPromptActive, let text = block.textContent, !text.isEmpty else { return }
            emit(.thinking(text))

        case .userMessageChunk:
            // User message echoes / history replay chunks are never emitted as assistant output.
            break

        case .toolCall(let call):
            let merged = mergeToolCall(call)
            let terminalOutputs = await collectTerminalOutputs(for: merged, sessionId: notification.sessionId)
            let step = Self.makeToolStep(from: merged, terminalOutputs: terminalOutputs)
            emit(.toolStep(step))
            if Self.isTerminalToolStatus(merged.status) {
                trackedToolCalls.removeValue(forKey: merged.toolCallId)
                emit(
                    .toolStepResult(
                        id: merged.toolCallId,
                        output: VitruvianCodeToolStep.truncatedOutput(
                            Self.extractToolOutput(from: merged, terminalOutputs: terminalOutputs)
                        ),
                        isError: merged.status == "failed"
                    )
                )
            }

        case .toolCallUpdate(let update):
            let hadPrior = trackedToolCalls[update.toolCallId] != nil
            let merged = mergeToolCall(update)
            let terminalOutputs = await collectTerminalOutputs(for: merged, sessionId: notification.sessionId)
            if Self.isTerminalToolStatus(merged.status) {
                if !hadPrior || Self.hasStepDetails(update) {
                    emit(.toolStep(Self.makeToolStep(from: merged, terminalOutputs: terminalOutputs)))
                }
                trackedToolCalls.removeValue(forKey: merged.toolCallId)
                emit(
                    .toolStepResult(
                        id: merged.toolCallId,
                        output: VitruvianCodeToolStep.truncatedOutput(
                            Self.extractToolOutput(from: merged, terminalOutputs: terminalOutputs)
                        ),
                        isError: merged.status == "failed"
                    )
                )
            } else {
                emit(.toolStep(Self.makeToolStep(from: merged, terminalOutputs: terminalOutputs)))
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
            let names = commands.compactMap { cmd -> String? in
                let raw = cmd.name.trimmingCharacters(in: .whitespacesAndNewlines)
                let stripped = raw.hasPrefix("/") ? String(raw.dropFirst()) : raw
                return stripped.isEmpty ? nil : stripped
            }
            emit(.slashCommands(names))

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
            let result = try files.readTextFile(decoded, policy: policy)
            return try ACPJSONValue.fromEncodable(result)

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
            return ACPRequestPermissionResult(outcome: automaticOutcome)
        }

        let interactionID = "perm-\(nextInteractionNumber)"
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

        return await withCheckedContinuation { continuation in
            if isStopping || isStopped {
                continuation.resume(returning: ACPRequestPermissionResult(outcome: .cancelled))
                return
            }
            pendingPermissions[interactionID] = continuation
            emit(.approval(approvalRequest))
        }
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

        return await withCheckedContinuation { continuation in
            if isStopping || isStopped {
                continuation.resume(returning: ACPElicitationCreateResult(action: .cancel))
                return
            }
            pendingElicitations[interactionID] = (parsed, continuation)
            emit(.question(parsed.question))
        }
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
        let message = "Agent process exited unexpectedly (\(statusDesc))."
        recordLogLine("[acp] \(message)")
        let failure = AgentFailure(
            kind: .exited,
            message: message,
            detail: recentStderrDetail()
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

    private func emitTerminalPromptFailure(_ failure: AgentFailure) {
        guard !hasEmittedTerminalFailure else { return }
        hasEmittedTerminalFailure = true
        hasFinalizedLogTarget = true
        cancelAllPendingInteractions()
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
        guard var previous = trackedToolCalls[incoming.toolCallId] else {
            trackedToolCalls[incoming.toolCallId] = incoming
            return incoming
        }
        if let title = incoming.title { previous.title = title }
        if let kind = incoming.kind { previous.kind = kind }
        if let status = incoming.status { previous.status = status }
        if let content = incoming.content { previous.content = content }
        if let locations = incoming.locations { previous.locations = locations }
        if let rawInput = incoming.rawInput { previous.rawInput = rawInput }
        if let rawOutput = incoming.rawOutput { previous.rawOutput = rawOutput }
        if let meta = incoming._meta { previous._meta = meta }
        trackedToolCalls[incoming.toolCallId] = previous
        return previous
    }

    private static func isTerminalToolStatus(_ status: String?) -> Bool {
        status == "completed" || status == "failed"
    }

    private static func hasStepDetails(_ update: ACPToolCall) -> Bool {
        if update.locations != nil || update.rawInput != nil {
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

    private static func makeToolStep(
        from call: ACPToolCall,
        terminalOutputs: [String: String] = [:]
    ) -> VitruvianCodeToolStep {
        let name = nonEmpty(call.title) ?? nonEmpty(call.kind) ?? "tool"
        let inputDict = call.rawInput?.objectValue?.mapValues(\.foundationObject)
        var step = VitruvianCodeToolStep.from(
            id: call.toolCallId,
            name: name,
            input: inputDict,
            isFinished: isTerminalToolStatus(call.status),
            output: extractToolOutput(from: call, terminalOutputs: terminalOutputs),
            isError: call.status == "failed"
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

        if let firstLocation = call.locations?.first?.path, !firstLocation.isEmpty {
            step.filePath = firstLocation
        }

        if let contents = call.content {
            for item in contents {
                if case .diff(let path, let oldText, let newText) = item {
                    if step.filePath == nil && !path.isEmpty {
                        step.filePath = path
                    }
                    step.diffOld = oldText
                    step.diffNew = newText
                    if step.kind == .other {
                        step.kind = .edit
                    }
                    break
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

    private static func encodePromptBlock(
        _ block: PromptBlock,
        supportsImages: Bool
    ) -> ACPContentBlock {
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
        }
    }

    private static func mimeType(forExtension ext: String) -> String {
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
