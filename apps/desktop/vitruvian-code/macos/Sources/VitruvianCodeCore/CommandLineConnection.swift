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

/// Runs an agent as one command-line process per prompt, turning its output
/// into `AgentEvent` values and forwarding stream-json input and termination.
@MainActor
public final class CommandLineConnection: AgentConnection, _ImmediateAgentConnection {
    public let capabilities = AgentCapabilities()
    /// Bounded with `.bufferingNewest(256)` so unread events cannot pile up in memory.
    public let events: AsyncStream<AgentEvent>
    public let spec: AgentConnectionSpec

    private let eventContinuation: AsyncStream<AgentEvent>.Continuation
    private let environment: VitruvianCodeEngine.Environment
    private(set) var sessionRequest: AgentSessionRequest?
    public private(set) var noiseLines: [String] = []
    private var running: VitruvianCodeRunningAgent?
    private var lineBuffer = VitruvianCodeLineBuffer()
    private var commandOutput = Data()
    private var commandErrors = Data()
    private var emittedCommandText = ""
    private var wasCancelled = false
    private var lastFinishedStatus: String?
    private var hadErrorEvent = false

    public init(spec: AgentConnectionSpec, environment: VitruvianCodeEngine.Environment) {
        self.spec = spec
        self.environment = environment
        let (stream, continuation) = AsyncStream.makeStream(
            of: AgentEvent.self,
            bufferingPolicy: .bufferingNewest(256)
        )
        self.events = stream
        self.eventContinuation = continuation
    }

    public convenience init(environment: VitruvianCodeEngine.Environment) {
        self.init(
            spec: AgentConnectionSpec(
                provider: .antigravity,
                workingDirectory: environment.home,
                environment: environment.processEnvironment
            ),
            environment: environment
        )
    }

    public func start(_ request: AgentSessionRequest) async throws -> String {
        beginImmediateSession(request)
    }

    public func prompt(_ blocks: [PromptBlock]) async throws -> AgentStopReason {
        try await withCheckedThrowingContinuation { continuation in
            var didResume = false
            func resumeOnce(_ result: Result<AgentStopReason, any Error>) {
                guard !didResume else { return }
                didResume = true
                continuation.resume(with: result)
            }
            do {
                try beginImmediatePrompt(
                    blocks,
                    onEvent: { _ in },
                    onNoise: { _ in },
                    onAgentExit: { [weak self] status in
                        let reason = self?.stopReasonForAgentExit(status: status)
                            ?? (status == 0 ? .endTurn : .error)
                        // One process per prompt: the turn is over, so the
                        // events stream ends here, after everything buffered.
                        self?.eventContinuation.finish()
                        resumeOnce(.success(reason))
                    },
                    onCommandPartial: { _ in },
                    onCommandExit: { [weak self] status, outcome, _ in
                        let reason = self?.stopReasonForCommandExit(status: status, outcome: outcome)
                            ?? (status == 0 ? .endTurn : .error)
                        self?.eventContinuation.finish()
                        resumeOnce(.success(reason))
                    }
                )
            } catch {
                eventContinuation.finish()
                resumeOnce(.failure(error))
            }
        }
    }

    public func cancel() async {
        cancelImmediateTurn()
    }

    public func answer(_ requestID: String, _ choice: AgentAnswer) async throws {
        sendImmediateAnswer(requestID, choice)
    }

    public func setConfigOption(_ id: String, _ value: AgentConfigValue) async throws -> [AgentConfigOption] {
        throw AgentConnectionError.notSupportedYet
    }

    public func stop() async {
        cancelImmediateTurn()
        eventContinuation.finish()
    }

    // MARK: - Immediate main-actor hooks

    @discardableResult
    func beginImmediateSession(_ request: AgentSessionRequest) -> String {
        sessionRequest = request
        return request.resumeSessionID ?? ""
    }

    func beginImmediatePrompt(
        _ blocks: [PromptBlock],
        onEvent: @escaping (AgentEvent) -> Void,
        onNoise: @escaping (String) -> Void,
        onAgentExit: @escaping (Int32) -> Void,
        onCommandPartial: @escaping (String) -> Void,
        onCommandExit: @escaping (Int32, VitruvianCodeCommandOutcome, String) -> Void
    ) throws {
        wasCancelled = false
        lastFinishedStatus = nil
        hadErrorEvent = false
        noiseLines = []

        var turnConfig = spec.configuration
        turnConfig.activeProvider = spec.provider
        if spec.turnModes.plan {
            turnConfig.approvalMode = .plan
        }

        var baseEnvironment = environment.processEnvironment
        for (key, value) in spec.environment {
            baseEnvironment[key] = value
        }

        let directory = sessionRequest?.workingDirectory ?? spec.workingDirectory
        let resumeID = sessionRequest?.resumeSessionID.flatMap { $0.isEmpty ? nil : $0 }
        let (promptText, attachments) = Self.unpackPromptBlocks(
            blocks,
            fallbackAttachments: spec.turnModes.attachments
        )

        if spec.provider.route == .custom {
            let fullPrompt = VitruvianCodeSupport.promptWithAttachments(promptText, attachments)
            let effectivePrompt = spec.turnModes.plan
                ? VitruvianCodeSupport.planModePrompt(fullPrompt)
                : fullPrompt
            guard let command = VitruvianCodeSupport.providerCommand(
                template: spec.provider.commandTemplate,
                prompt: effectivePrompt,
                model: turnConfig.model
            ), !command.executable.isEmpty else {
                throw CocoaError(.fileNoSuchFile)
            }
            let resolvedPath: String
            if let explicit = spec.agentPath, !explicit.isEmpty {
                resolvedPath = explicit
            } else if let found = VitruvianCodeSupport.executablePath(
                named: command.executable,
                pathVariable: baseEnvironment["PATH"] ?? "",
                isExecutable: environment.isExecutable,
                fileExists: environment.fileExists
            ) {
                resolvedPath = found
            } else {
                throw CocoaError(.fileNoSuchFile)
            }
            try startCommandTurn(
                executablePath: resolvedPath,
                arguments: command.arguments,
                workingDirectory: directory,
                baseEnvironment: baseEnvironment,
                onPartialOutput: onCommandPartial,
                onExit: onCommandExit
            )
            return
        }

        let resolvedAgentPath: String
        if let explicit = spec.agentPath, !explicit.isEmpty {
            resolvedAgentPath = explicit
        } else if let found = VitruvianCodeSupport.locateChatProgram(
            named: spec.provider.executableName,
            environment: baseEnvironment,
            home: environment.home,
            isExecutable: environment.isExecutable,
            fileExists: environment.fileExists
        ) {
            resolvedAgentPath = found
        } else {
            throw CocoaError(.fileNoSuchFile)
        }

        try startAgentTurn(
            prompt: promptText,
            configuration: turnConfig,
            agentPath: resolvedAgentPath,
            workingDirectory: directory,
            conversationID: resumeID,
            planMode: spec.turnModes.plan,
            worktreeMode: spec.turnModes.worktree,
            ollamaDefaultModel: spec.ollamaDefaultModel,
            attachments: attachments,
            forkSession: spec.turnModes.fork,
            baseEnvironment: baseEnvironment,
            onEvent: onEvent,
            onNoise: onNoise,
            onExit: onAgentExit
        )
    }

    func sendImmediateAnswer(_ requestID: String, _ choice: AgentAnswer) {
        let decision = Self.approvalDecision(for: choice)
        let request = VitruvianCodeApprovalRequest(
            toolName: "",
            commandOrPath: "",
            requestID: requestID
        )
        guard let line = VitruvianCodeSupport.approvalResponseJSON(for: request, decision: decision) else {
            return
        }
        sendInput(line)
    }

    func cancelImmediateTurn() {
        wasCancelled = true
        terminate()
    }

    // MARK: - Synchronous session turn hooks

    /// Starts one stream-json turn, feeding parsed events to `events` and to
    /// the session's callbacks in the order the process writes them.
    func startAgentTurn(
        prompt: String,
        configuration: VitruvianCodeConfiguration,
        agentPath: String,
        workingDirectory: String,
        conversationID: String?,
        planMode: Bool,
        worktreeMode: Bool,
        ollamaDefaultModel: String,
        attachments: [VitruvianCodeAttachment] = [],
        forkSession: Bool = false,
        baseEnvironment: [String: String]? = nil,
        onEvent: ((AgentEvent) -> Void)? = nil,
        onNoise: ((String) -> Void)? = nil,
        onExit: @escaping (Int32) -> Void
    ) throws {
        let arguments = VitruvianCodeSupport.agentArguments(
            prompt: prompt,
            configuration: configuration,
            conversationID: conversationID,
            planMode: planMode,
            worktreeMode: worktreeMode,
            ollamaDefaultModel: ollamaDefaultModel,
            attachments: attachments,
            forkSession: forkSession
        )
        let childEnvironment = VitruvianCodeSupport.childEnvironment(
            base: baseEnvironment ?? environment.processEnvironment,
            home: environment.home
        )
        lineBuffer = VitruvianCodeLineBuffer()
        var exited = false
        let handle = try environment.launchAgent(
            agentPath,
            arguments,
            workingDirectory,
            childEnvironment,
            { [weak self] data in
                self?.receiveAgentOutput(data, onEvent: onEvent, onNoise: onNoise)
            },
            { [weak self] status in
                exited = true
                self?.finishAgentTurn(status: status, onEvent: onEvent, onNoise: onNoise, onExit: onExit)
            }
        )
        if !exited {
            running = handle
            if VitruvianCodeSupport.asksOverStandardInput(configuration: configuration, planMode: planMode) {
                let fullPrompt = VitruvianCodeSupport.promptWithAttachments(prompt, attachments)
                sendInput(VitruvianCodeSupport.stdinUserMessage(fullPrompt))
            }
        }
    }

    /// Starts one custom command turn, keeping standard output and standard
    /// error apart and delivering the command's outcome when it exits.
    func startCommandTurn(
        executablePath: String,
        arguments: [String],
        workingDirectory: String,
        baseEnvironment: [String: String]? = nil,
        onPartialOutput: @escaping (String) -> Void,
        onExit: @escaping (Int32, VitruvianCodeCommandOutcome, String) -> Void
    ) throws {
        let childEnvironment = VitruvianCodeSupport.commandEnvironment(
            base: baseEnvironment ?? environment.processEnvironment,
            fileExists: environment.fileExists
        )
        commandOutput = Data()
        commandErrors = Data()
        emittedCommandText = ""
        var exited = false
        let handle = try environment.launchCommand(
            executablePath,
            arguments,
            workingDirectory,
            childEnvironment,
            { [weak self] data in
                guard let self else { return }
                self.commandOutput.append(data)
                if let printed = String(data: self.commandOutput, encoding: .utf8) {
                    if printed.count > self.emittedCommandText.count {
                        let delta = String(printed.dropFirst(self.emittedCommandText.count))
                        self.emittedCommandText = printed
                        self.eventContinuation.yield(.text(delta))
                    }
                    onPartialOutput(printed)
                }
            },
            { [weak self] data in
                self?.commandErrors.append(data)
            },
            { [weak self] status in
                exited = true
                guard let self else { return }
                self.running = nil
                let outcome = VitruvianCodeSupport.commandOutcome(
                    output: self.commandOutput,
                    errors: self.commandErrors,
                    status: status
                )
                let printed = String(data: self.commandOutput, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                self.commandOutput = Data()
                self.commandErrors = Data()
                self.emittedCommandText = ""
                switch outcome {
                case .reply(let text):
                    self.eventContinuation.yield(
                        .finished(status: "end_turn", response: text, error: nil, conversationID: nil)
                    )
                case .failed(_, let errors):
                    self.eventContinuation.yield(
                        .finished(status: "error", response: nil, error: errors.isEmpty ? nil : errors, conversationID: nil)
                    )
                case .noOutput, .stopped:
                    break
                }
                onExit(status, outcome, printed)
            }
        )
        if !exited {
            running = handle
        }
    }

    /// Writes a message or approval response to the running process's standard input.
    func sendInput(_ data: Data) {
        running?.sendInput?(data)
    }

    /// Closes standard input when the turn's result arrives.
    func closeInput() {
        running?.closeInput?()
    }

    /// Terminates the running process, if any.
    func terminate() {
        running?.terminate()
    }

    // MARK: - Private helpers

    private static func approvalDecision(for choice: AgentAnswer) -> VitruvianCodeApprovalRequest.Status {
        switch choice {
        case .option(let optionID):
            let lowered = optionID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if lowered == "deny" || lowered == "reject" || lowered == "reject_once" || lowered == "reject_always" {
                return .denied
            }
            if lowered == "allow_always" || lowered == "session_allowed" {
                return .sessionAllowed
            }
            return .approved
        case .form:
            return .approved
        case .cancelled:
            return .denied
        }
    }

    static func unpackPromptBlocks(
        _ blocks: [PromptBlock],
        fallbackAttachments: [VitruvianCodeAttachment]
    ) -> (prompt: String, attachments: [VitruvianCodeAttachment]) {
        if !fallbackAttachments.isEmpty,
           blocks.count == fallbackAttachments.count + 1,
           case .text(let lastText) = blocks.last {
            let expectedPrefix: [PromptBlock] = fallbackAttachments.map { attachment in
                attachment.isImage ? .image(path: attachment.url.path) : .text("@" + attachment.url.path)
            }
            if Array(blocks.dropLast()) == expectedPrefix {
                return (lastText, fallbackAttachments)
            }
        }

        if fallbackAttachments.isEmpty, blocks.count == 1, case .text(let single) = blocks[0] {
            return (single, [])
        }

        var attachments = fallbackAttachments
        var seenPaths = Set(fallbackAttachments.map { $0.url.standardizedFileURL.path })
        var textParts: [String] = []
        let lastTextIndex = blocks.lastIndex {
            if case .text = $0 { return true }
            return false
        }

        for (index, block) in blocks.enumerated() {
            switch block {
            case .image(let path):
                let url = URL(fileURLWithPath: path)
                if seenPaths.insert(url.standardizedFileURL.path).inserted {
                    attachments.append(VitruvianCodeAttachment(url: url, isImage: true))
                }
            case .text(let value):
                if index != lastTextIndex,
                   value.hasPrefix("@/"),
                   !value.contains(where: \.isNewline) {
                    let path = String(value.dropFirst())
                    let url = URL(fileURLWithPath: path)
                    if seenPaths.insert(url.standardizedFileURL.path).inserted {
                        attachments.append(VitruvianCodeAttachment(url: url, isImage: false))
                    }
                } else {
                    textParts.append(value)
                }
            }
        }
        return (textParts.joined(separator: "\n\n"), attachments)
    }

    private func stopReasonForAgentExit(status: Int32) -> AgentStopReason {
        if wasCancelled || status == 15 || status == 9 {
            return .cancelled
        }
        if hadErrorEvent || status != 0 {
            return .error
        }
        switch lastFinishedStatus {
        case "max_tokens": return .maxTokens
        case "max_turn_requests": return .maxTurnRequests
        case "refusal": return .refusal
        default: return .endTurn
        }
    }

    private func stopReasonForCommandExit(status: Int32, outcome: VitruvianCodeCommandOutcome) -> AgentStopReason {
        if wasCancelled {
            return .cancelled
        }
        switch outcome {
        case .reply:
            return .endTurn
        case .stopped:
            return .cancelled
        case .failed, .noOutput:
            return .error
        }
    }

    private func receiveAgentOutput(
        _ data: Data,
        onEvent: ((AgentEvent) -> Void)?,
        onNoise: ((String) -> Void)?
    ) {
        for line in lineBuffer.append(data) {
            processAgentLine(line, onEvent: onEvent, onNoise: onNoise)
        }
    }

    private func finishAgentTurn(
        status: Int32,
        onEvent: ((AgentEvent) -> Void)?,
        onNoise: ((String) -> Void)?,
        onExit: (Int32) -> Void
    ) {
        if let rest = lineBuffer.finish() {
            processAgentLine(rest, onEvent: onEvent, onNoise: onNoise)
        }
        running = nil
        onExit(status)
    }

    private func processAgentLine(
        _ line: String,
        onEvent: ((AgentEvent) -> Void)?,
        onNoise: ((String) -> Void)?
    ) {
        let parsed = AgentEvent.parseAll(line)
        guard !parsed.isEmpty else {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                noiseLines = Array((noiseLines + [trimmed]).suffix(5))
                onNoise?(trimmed)
            }
            return
        }
        for event in parsed {
            if case .finished(let status, _, let error, _, _) = event {
                lastFinishedStatus = status
                if error != nil {
                    hadErrorEvent = true
                }
                closeInput()
            }
            eventContinuation.yield(event)
            onEvent?(event)
        }
    }
}
