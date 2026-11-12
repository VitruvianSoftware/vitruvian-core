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

/// Runs an agent as one command-line process per prompt, turning its output
/// into `AgentEvent` values and forwarding stream-json input and termination.
@MainActor
public final class CommandLineConnection: AgentConnection {
    public let capabilities = AgentCapabilities()
    /// Bounded with `.bufferingNewest(256)` so events nobody reads yet in
    /// step 1a cannot pile up in memory.
    public let events: AsyncStream<AgentEvent>

    private let eventContinuation: AsyncStream<AgentEvent>.Continuation
    private let environment: VitruvianCodeEngine.Environment
    private(set) var sessionRequest: AgentSessionRequest?
    private var running: VitruvianCodeRunningAgent?
    private var lineBuffer = VitruvianCodeLineBuffer()
    private var commandOutput = Data()
    private var commandErrors = Data()

    public init(environment: VitruvianCodeEngine.Environment) {
        self.environment = environment
        // Step 1a still delivers events through the session's callbacks, so bound
        // the stream with `.bufferingNewest(256)` so events nobody reads cannot pile up.
        let (stream, continuation) = AsyncStream.makeStream(
            of: AgentEvent.self,
            bufferingPolicy: .bufferingNewest(256)
        )
        self.events = stream
        self.eventContinuation = continuation
    }

    public func start(_ request: AgentSessionRequest) async throws -> String {
        sessionRequest = request
        return request.resumeSessionID ?? ""
    }

    public func prompt(_ blocks: [PromptBlock]) async throws -> AgentStopReason {
        throw AgentConnectionError.notSupportedYet
    }

    public func cancel() async {
        terminate()
    }

    public func answer(_ requestID: String, _ choice: AgentAnswer) async throws {
        throw AgentConnectionError.notSupportedYet
    }

    public func setConfigOption(_ id: String, _ value: AgentConfigValue) async throws -> [AgentConfigOption] {
        throw AgentConnectionError.notSupportedYet
    }

    public func stop() async {
        terminate()
        eventContinuation.finish()
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
            base: environment.processEnvironment,
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
        onPartialOutput: @escaping (String) -> Void,
        onExit: @escaping (Int32, VitruvianCodeCommandOutcome, String) -> Void
    ) throws {
        let childEnvironment = VitruvianCodeSupport.commandEnvironment(
            base: environment.processEnvironment,
            fileExists: environment.fileExists
        )
        commandOutput = Data()
        commandErrors = Data()
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
                onNoise?(trimmed)
            }
            return
        }
        for event in parsed {
            eventContinuation.yield(event)
            onEvent?(event)
        }
    }
}
