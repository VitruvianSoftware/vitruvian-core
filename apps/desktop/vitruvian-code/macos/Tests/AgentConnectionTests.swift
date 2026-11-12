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
@testable import VitruvianCodeCore
import XCTest

@MainActor
final class AgentConnectionTests: XCTestCase {
    /// Every stream sample exercised by `StreamParityTests`, grouped by fixture.
    private static let streamParityFixtures: [(name: String, lines: [String])] = [
        ("claude-tool-starting", [
            #"{"type":"stream_event","event":{"type":"content_block_start","index":1,"content_block":{"type":"tool_use","id":"toolu_1","name":"Read","input":{}}}}"#,
        ]),
        ("claude-assistant-tool-use-and-usage", [
            #"{"type":"assistant","message":{"model":"claude-haiku-5-5","content":[{"type":"tool_use","id":"toolu_1","name":"Edit","input":{"file_path":"/r/a.swift","old_string":"a","new_string":"b"}},{"type":"tool_use","id":"toolu_2","name":"Bash","input":{"command":"ls -la\nmore"}}],"usage":{"input_tokens":2,"cache_read_input_tokens":10,"output_tokens":5}}}"#,
        ]),
        ("claude-assistant-no-duplicate-text", [
            #"{"type":"assistant","message":{"content":[{"type":"text","text":"banana"},{"type":"thinking","thinking":"hm"}]}}"#,
        ]),
        ("claude-tool-results", [
            #"{"type":"user","message":{"role":"user","content":[{"tool_use_id":"toolu_1","type":"tool_result","content":"1\tbanana split\n"}]},"parent_tool_use_id":null}"#,
            #"{"type":"user","message":{"content":[{"tool_use_id":"t2","type":"tool_result","is_error":true,"content":[{"type":"text","text":"no"},{"type":"text","text":"such file"}]}]}}"#,
        ]),
        ("claude-subagent-filtered", [
            #"{"type":"assistant","parent_tool_use_id":"toolu_agent","message":{"content":[{"type":"tool_use","id":"inner","name":"Read","input":{}}],"usage":{"input_tokens":2,"output_tokens":1}}}"#,
        ]),
        ("claude-init-and-commands-changed", [
            #"{"type":"system","subtype":"init","cwd":"/r","session_id":"s1","slash_commands":["compact","review","antigravity:delegate"]}"#,
            #"{"type":"system","subtype":"commands_changed","commands":[{"name":"bitwarden","description":"x","argumentHint":""}],"session_id":"s1"}"#,
        ]),
        ("claude-thinking-deltas-and-tokens", [
            #"{"type":"stream_event","event":{"type":"content_block_delta","index":0,"delta":{"type":"thinking_delta","thinking":"Let me see"}}}"#,
            #"{"type":"stream_event","event":{"type":"content_block_delta","index":0,"delta":{"type":"thinking_delta","thinking":"","estimated_tokens":50}}}"#,
            #"{"type":"system","subtype":"thinking_tokens","estimated_tokens":216,"estimated_tokens_delta":166,"session_id":"s1"}"#,
            #"{"type":"result","stop_reason":"end_turn","session_id":"s1","result":"ok","usage":{"input_tokens":4,"output_tokens":174,"output_tokens_details":{"thinking_tokens":105}}}"#,
        ]),
        ("claude-permission-and-control-requests", [
            #"{"type":"permission_request","id":"p1","tool_name":"Bash","input":{"command":"rm -rf build"}}"#,
            #"{"type":"control_request","request_id":"r1","request":{"subtype":"can_use_tool","tool_name":"Write","input":{"file_path":"/r/x"},"tool_use_id":"t9"}}"#,
        ]),
        ("claude-error-result", [
            #"{"type":"result","is_error":true,"stop_reason":"error","session_id":"s1","result":"API Error: Overloaded"}"#,
        ]),
        ("agy-tool-step-and-result", [
            #"{"event":"step_update","step_update":{"conversation_id":"c","step_index":4,"state":"ACTIVE","step_type":"tool","tool_name":"read_file","tool_info":{"name":"read_file","parameters":{"Path":"/tmp/x.txt"}}}}"#,
            #"{"event":"step_update","step_update":{"conversation_id":"c","step_index":4,"state":"DONE","step_type":"tool","tool_name":"read_file","tool_info":{"name":"read_file","parameters":{"Path":"/tmp/x.txt"},"output":"1 lines, 13 bytes"}}}"#,
        ]),
        ("opencode-tool-part", [
            #"{"type":"tool_use","sessionID":"ses","part":{"tool":"bash","callID":"call_1","state":{"status":"completed","input":{"command":"pwd"},"output":"/r\n"}}}"#,
        ]),
    ]

    /// Bounded wait for `rig.agentOutput` so a stalled launch fails fast instead of hanging.
    private func waitForAgentOutput(
        _ rig: ComposerRig,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async -> (@MainActor @Sendable (Data) -> Void)? {
        for _ in 0..<1000 {
            if let output = rig.agentOutput {
                return output
            }
            await Task.yield()
        }
        XCTFail("Timed out waiting for agent launch", file: file, line: line)
        return nil
    }

    // MARK: - (a) Stream parity through CommandLineConnection

    func testCommandLineConnectionProducesSameEventsAsParseAllForEveryFixture() async throws {
        for fixture in Self.streamParityFixtures {
            let rig = ComposerRig()
            let connection = CommandLineConnection(environment: rig.environment)
            XCTAssertEqual(connection.capabilities, AgentCapabilities(), "every capability defaults to false")

            var callbackEvents: [AgentEvent] = []
            var exitStatuses: [Int32] = []
            try connection.startAgentTurn(
                prompt: "run",
                configuration: VitruvianCodeConfiguration(approvalMode: .yolo, activeProvider: .claude),
                agentPath: "/fake/agent",
                workingDirectory: "/Users/rig",
                conversationID: nil,
                planMode: false,
                worktreeMode: false,
                ollamaDefaultModel: VitruvianCodeSupport.ollamaFallbackModel,
                onEvent: { callbackEvents.append($0) },
                onExit: { exitStatuses.append($0) }
            )
            guard let sendOutput = await waitForAgentOutput(rig) else { return }

            for line in fixture.lines {
                sendOutput(Data((line + "\n").utf8))
            }
            rig.finishCleanly()
            XCTAssertEqual(exitStatuses, [0], fixture.name)

            await connection.stop()

            var collected: [AgentEvent] = []
            for await event in connection.events {
                collected.append(event)
            }
            let expected = fixture.lines.flatMap(AgentEvent.parseAll)
            XCTAssertEqual(callbackEvents, expected, fixture.name)
            XCTAssertEqual(collected, expected, fixture.name)
        }
    }

    // MARK: - Line buffering across chunks and at EOF

    func testSplitJSONLineAcrossTwoOutputChunksProducesSameEvents() async throws {
        let line = #"{"type":"assistant","message":{"model":"claude-haiku-5-5","content":[{"type":"tool_use","id":"toolu_1","name":"Edit","input":{"file_path":"/r/a.swift","old_string":"a","new_string":"b"}},{"type":"tool_use","id":"toolu_2","name":"Bash","input":{"command":"ls -la\nmore"}}],"usage":{"input_tokens":2,"cache_read_input_tokens":10,"output_tokens":5}}}"#
        let expected = AgentEvent.parseAll(line)
        XCTAssertFalse(expected.isEmpty)

        let rig = ComposerRig()
        let connection = CommandLineConnection(environment: rig.environment)
        var callbackEvents: [AgentEvent] = []
        try connection.startAgentTurn(
            prompt: "split",
            configuration: VitruvianCodeConfiguration(approvalMode: .yolo, activeProvider: .claude),
            agentPath: "/fake/claude",
            workingDirectory: "/Users/rig",
            conversationID: nil,
            planMode: false,
            worktreeMode: false,
            ollamaDefaultModel: VitruvianCodeSupport.ollamaFallbackModel,
            onEvent: { callbackEvents.append($0) },
            onExit: { _ in }
        )
        guard let sendOutput = await waitForAgentOutput(rig) else { return }

        let bytes = Array((line + "\n").utf8)
        let midpoint = bytes.count / 2
        sendOutput(Data(bytes[..<midpoint]))
        XCTAssertTrue(callbackEvents.isEmpty, "half a JSON line waits in the buffer until its newline arrives")
        sendOutput(Data(bytes[midpoint...]))
        rig.finishCleanly()
        await connection.stop()

        var streamEvents: [AgentEvent] = []
        for await event in connection.events {
            streamEvents.append(event)
        }
        XCTAssertEqual(callbackEvents, expected)
        XCTAssertEqual(streamEvents, expected)
    }

    func testFinalLineWithNoTrailingNewlineIsDeliveredOnExit() async throws {
        let line = #"{"type":"result","stop_reason":"end_turn","session_id":"s1","result":"ok","usage":{"input_tokens":4,"output_tokens":174,"output_tokens_details":{"thinking_tokens":105}}}"#
        let expected = AgentEvent.parseAll(line)
        XCTAssertFalse(expected.isEmpty)

        let rig = ComposerRig()
        let connection = CommandLineConnection(environment: rig.environment)
        var callbackEvents: [AgentEvent] = []
        try connection.startAgentTurn(
            prompt: "no-newline",
            configuration: VitruvianCodeConfiguration(approvalMode: .yolo, activeProvider: .claude),
            agentPath: "/fake/claude",
            workingDirectory: "/Users/rig",
            conversationID: nil,
            planMode: false,
            worktreeMode: false,
            ollamaDefaultModel: VitruvianCodeSupport.ollamaFallbackModel,
            onEvent: { callbackEvents.append($0) },
            onExit: { _ in }
        )
        guard let sendOutput = await waitForAgentOutput(rig) else { return }

        sendOutput(Data(line.utf8))
        XCTAssertTrue(callbackEvents.isEmpty, "without a trailing newline the line stays buffered until exit")

        rig.finishCleanly()
        await connection.stop()

        var streamEvents: [AgentEvent] = []
        for await event in connection.events {
            streamEvents.append(event)
        }
        XCTAssertEqual(callbackEvents, expected)
        XCTAssertEqual(streamEvents, expected)
    }

    // MARK: - (b) Cancellation, input closing and minimal step-1a protocol stubs

    func testCancelTerminatesTheFakeProcessAndCloseInputForwardsEveryCall() async throws {
        let rig = ComposerRig()
        let connection = CommandLineConnection(environment: rig.environment)

        var exitStatuses: [Int32] = []
        try connection.startAgentTurn(
            prompt: "long turn",
            configuration: VitruvianCodeConfiguration(approvalMode: .yolo, activeProvider: .claude),
            agentPath: "/fake/claude",
            workingDirectory: "/Users/rig",
            conversationID: nil,
            planMode: false,
            worktreeMode: false,
            ollamaDefaultModel: VitruvianCodeSupport.ollamaFallbackModel,
            onExit: { exitStatuses.append($0) }
        )
        guard await waitForAgentOutput(rig) != nil else { return }
        XCTAssertEqual(rig.terminations, 0)

        connection.closeInput()
        connection.closeInput()
        XCTAssertEqual(rig.inputCloses, 2, "closeInput forwards directly without a once-per-turn guard")

        await connection.cancel()
        XCTAssertEqual(rig.terminations, 1, "cancel() terminates the underlying process")

        rig.agentExit?(15)
        XCTAssertEqual(exitStatuses, [15])
        await connection.stop()
    }

    func testStartStoresTheRequestAndSetConfigOptionIsNotSupportedYet() async throws {
        let rig = ComposerRig()
        let connection = CommandLineConnection(environment: rig.environment)

        let freshRequest = AgentSessionRequest(workingDirectory: "/Users/rig")
        let freshID = try await connection.start(freshRequest)
        XCTAssertEqual(freshID, "")
        XCTAssertEqual(connection.sessionRequest, freshRequest)

        let resumeRequest = AgentSessionRequest(workingDirectory: "/Users/rig", resumeSessionID: "conv-42")
        let resumedID = try await connection.start(resumeRequest)
        XCTAssertEqual(resumedID, "conv-42")
        XCTAssertEqual(connection.sessionRequest, resumeRequest)

        do {
            _ = try await connection.setConfigOption("model", .string("sonnet"))
            XCTFail("expected setConfigOption(_:_:) to throw notSupportedYet")
        } catch let error as AgentConnectionError {
            XCTAssertEqual(error, .notSupportedYet)
        }

        await connection.stop()
    }

    // MARK: - (c) Saved connection survives available(saved:) and store/reload

    func testSavedConnectionChoiceSurvivesAvailableAndStoreReloadRoundTrip() throws {
        var claude = VitruvianCodeCLIProvider.claude
        claude.connection = .claudeSDK

        let custom = VitruvianCodeCLIProvider(
            id: UUID(uuidString: "8F2B6C1E-5D0A-4E7B-9C3F-1A2B3C4D5E6F")!,
            name: "Custom ACP",
            commandTemplate: "/usr/local/bin/custom-agent {prompt}",
            isBuiltIn: false,
            connection: .acp
        )

        let listedDirect = VitruvianCodeCLIProvider.available(saved: [claude, custom])
        XCTAssertEqual(listedDirect.first(where: { $0.id == VitruvianCodeCLIProvider.claude.id })?.connection, .claudeSDK)
        XCTAssertEqual(listedDirect.first(where: { $0.id == custom.id })?.connection, .acp)
        XCTAssertNil(listedDirect.first(where: { $0.id == VitruvianCodeCLIProvider.antigravity.id })?.connection)

        // Store and reload round trip through StoredLists + JSON + saved(builtIn:custom:) + available(saved:),
        // and verify saving only custom providers over previousBuiltIn also keeps the built-in's connection.
        let initialLists = VitruvianCodeCLIProvider.storedLists(saving: [claude, custom], over: [])
        let builtInData = try JSONEncoder().encode(initialLists.builtIn)
        let customData = try JSONEncoder().encode(initialLists.custom)

        let reloaded = VitruvianCodeCLIProvider.available(
            saved: VitruvianCodeCLIProvider.saved(builtIn: builtInData, custom: customData)
        )
        XCTAssertEqual(reloaded.first(where: { $0.id == VitruvianCodeCLIProvider.claude.id })?.connection, .claudeSDK)
        XCTAssertEqual(reloaded.first(where: { $0.id == custom.id })?.connection, .acp)

        let preservedLists = VitruvianCodeCLIProvider.storedLists(
            saving: [custom],
            over: VitruvianCodeCLIProvider.stored(builtInData)
        )
        XCTAssertEqual(
            preservedLists.builtIn.first(where: { $0.id == VitruvianCodeCLIProvider.claude.id })?.connection,
            .claudeSDK,
            "saving custom providers over stored built-ins preserves a built-in's connection choice"
        )
    }

    // MARK: - (d) Old-format JSON without a connection key and unknown future connection kinds

    func testOldSavedJSONWithoutConnectionKeyDecodesAsNilAndKeepsProviders() {
        // Old-format stored blobs copied from StandaloneSettingsTests (no "connection" key).
        let storedBuiltIns = #"""
        [{"id":"00000000-0000-0000-0000-000000000001","name":"Antigravity CLI","commandTemplate":"agy -p \"{prompt}\" --output-format stream-json --dangerously-skip-permissions","isBuiltIn":true},{"id":"00000000-0000-0000-0000-000000000003","name":"Claude Code","commandTemplate":"\/opt\/bin\/claude -p \"{prompt}\" --model {model}","isBuiltIn":true},{"id":"00000000-0000-0000-0000-000000000002","name":"Ollama (claude)","commandTemplate":"ollama launch claude --model {model} -- -p \"{prompt}\"","isBuiltIn":true}]
        """#
        let storedCustom = #"""
        [{"id":"8F2B6C1E-5D0A-4E7B-9C3F-1A2B3C4D5E6F","name":"Aider","commandTemplate":"\/usr\/local\/bin\/aider --message \"{prompt}\"","isBuiltIn":false}]
        """#

        let saved = VitruvianCodeCLIProvider.saved(
            builtIn: Data(storedBuiltIns.utf8),
            custom: Data(storedCustom.utf8)
        )
        let listed = VitruvianCodeCLIProvider.available(saved: saved)

        XCTAssertEqual(listed.count, 5, "all four built-ins plus the user's custom provider are kept")
        for provider in listed {
            XCTAssertNil(provider.connection, "\(provider.name) without a connection key decodes as nil")
        }
        XCTAssertEqual(
            listed.first(where: { $0.id == VitruvianCodeCLIProvider.claude.id })?.commandTemplate,
            "/opt/bin/claude -p \"{prompt}\" --model {model}"
        )
        XCTAssertEqual(listed.last?.name, "Aider")
        XCTAssertEqual(listed.last?.commandTemplate, "/usr/local/bin/aider --message \"{prompt}\"")
        XCTAssertEqual(listed.last?.isBuiltIn, false)
    }

    func testStoredListWithUnknownFutureConnectionKindDecodesAsNilAndKeepsProviders() {
        let storedBuiltIns = #"""
        [{"id":"00000000-0000-0000-0000-000000000001","name":"Antigravity CLI","commandTemplate":"agy -p \"{prompt}\"","isBuiltIn":true,"connection":"acp"},{"id":"00000000-0000-0000-0000-000000000003","name":"Claude Code","commandTemplate":"\/opt\/bin\/claude -p \"{prompt}\"","isBuiltIn":true,"connection":"someFutureKind"}]
        """#
        let storedCustom = #"""
        [{"id":"8F2B6C1E-5D0A-4E7B-9C3F-1A2B3C4D5E6F","name":"Future Custom","commandTemplate":"\/usr\/local\/bin\/future \"{prompt}\"","isBuiltIn":false,"connection":"someFutureKind"},{"id":"9A3C7D2F-6E1B-4F8C-AD40-2B3C4D5E6F70","name":"Aider","commandTemplate":"\/usr\/local\/bin\/aider --message \"{prompt}\"","isBuiltIn":false,"connection":"commandLine"}]
        """#

        let saved = VitruvianCodeCLIProvider.saved(
            builtIn: Data(storedBuiltIns.utf8),
            custom: Data(storedCustom.utf8)
        )
        let listed = VitruvianCodeCLIProvider.available(saved: saved)

        XCTAssertEqual(listed.count, 6, "all four built-ins plus both custom providers stay intact")
        XCTAssertEqual(listed.first(where: { $0.id == VitruvianCodeCLIProvider.antigravity.id })?.connection, .acp)
        let claude = listed.first(where: { $0.id == VitruvianCodeCLIProvider.claude.id })
        XCTAssertNil(claude?.connection, "unknown connection kind on a built-in decodes as nil")
        XCTAssertEqual(claude?.commandTemplate, "/opt/bin/claude -p \"{prompt}\"")

        let futureCustom = listed.first(where: { $0.name == "Future Custom" })
        XCTAssertNotNil(futureCustom)
        XCTAssertNil(futureCustom?.connection, "unknown connection kind on a custom provider decodes as nil")
        XCTAssertEqual(futureCustom?.commandTemplate, "/usr/local/bin/future \"{prompt}\"")

        let aider = listed.first(where: { $0.name == "Aider" })
        XCTAssertEqual(aider?.connection, .commandLine)
    }

    // MARK: - (e) Step 1b: CommandLineConnection.prompt, answer, cancel and session wiring

    func testCommandLineConnectionPromptMatchesArgumentsEnvironmentAndFirstStdinMessage() async throws {
        let imageAttachment = VitruvianCodeAttachment(url: URL(fileURLWithPath: "/tmp/screen.png"), isImage: true)
        let fileAttachment = VitruvianCodeAttachment(url: URL(fileURLWithPath: "/tmp/notes.md"), isImage: false)
        let attachments = [imageAttachment, fileAttachment]
        let blocks = VitruvianCodeQuickPromptSession.promptBlocks(text: "inspect files", attachments: attachments)
        let baseEnv = ["PATH": "/usr/bin:/bin", "CUSTOM_FLAG": "yes"]

        // 1. agy: same arguments & childEnvironment, no stdin user message, closes input on .finished, collects noise.
        do {
            let rig = LaunchCaptureRig(baseEnvironment: baseEnv)
            let config = VitruvianCodeConfiguration(
                approvalMode: .auto,
                model: "gemini-4-argon-high",
                effort: .high,
                activeProvider: .antigravity
            )
            let spec = AgentConnectionSpec(
                provider: .antigravity,
                configuration: config,
                agentPath: "/fake/agy",
                workingDirectory: "/Users/rig/project",
                ollamaDefaultModel: VitruvianCodeSupport.ollamaFallbackModel,
                turnModes: AgentTurnModes(plan: false, worktree: false, attachments: attachments, fork: false),
                environment: baseEnv
            )
            let connection = CommandLineConnection(spec: spec, environment: rig.environment)
            let started = try await connection.start(
                AgentSessionRequest(workingDirectory: "/Users/rig/project", resumeSessionID: "agy-conv-1")
            )
            XCTAssertEqual(started, "agy-conv-1")

            let promptTask = Task { try await connection.prompt(blocks) }
            guard await rig.waitForAgentLaunch() else {
                XCTFail("Timed out waiting for agy launch")
                return
            }

            let expectedArguments = VitruvianCodeSupport.agentArguments(
                prompt: "inspect files",
                configuration: config,
                conversationID: "agy-conv-1",
                planMode: false,
                worktreeMode: false,
                ollamaDefaultModel: VitruvianCodeSupport.ollamaFallbackModel,
                attachments: attachments,
                forkSession: false
            )
            let expectedEnv = VitruvianCodeSupport.childEnvironment(base: baseEnv, home: "/Users/rig")
            XCTAssertEqual(rig.agentPath, "/fake/agy")
            XCTAssertEqual(rig.agentDirectory, "/Users/rig/project")
            XCTAssertEqual(rig.agentArguments, expectedArguments)
            XCTAssertEqual(rig.agentEnvironment, expectedEnv)
            XCTAssertTrue(rig.inputs.isEmpty, "agy does not receive a stream-json user message on stdin")

            rig.agentOutput?(Data("agy warning: transient retry\n".utf8))
            rig.agentOutput?(Data(#"{"type":"result","stop_reason":"end_turn","session_id":"agy-conv-1","result":"done"}"#.utf8 + Data("\n".utf8)))
            XCTAssertEqual(rig.inputCloses, 1, "stdin closes when .finished arrives")
            rig.agentExit?(0)

            let stopReason = try await promptTask.value
            XCTAssertEqual(stopReason, .endTurn)
            XCTAssertEqual(connection.noiseLines, ["agy warning: transient retry"])
            await connection.stop()
        }

        // 2. Claude with stream-json approvals (.standard, .acceptEdits, .auto): same arguments, environment and first stdin message.
        for mode in [VitruvianCodeApprovalMode.standard, .acceptEdits, .auto] {
            let rig = LaunchCaptureRig(baseEnvironment: baseEnv)
            let config = VitruvianCodeConfiguration(
                approvalMode: mode,
                model: "claude-sonnet-4-6",
                effort: .medium,
                activeProvider: .claude
            )
            let spec = AgentConnectionSpec(
                provider: .claude,
                configuration: config,
                agentPath: "/fake/claude",
                workingDirectory: "/Users/rig/claude-repo",
                ollamaDefaultModel: VitruvianCodeSupport.ollamaFallbackModel,
                turnModes: AgentTurnModes(plan: false, worktree: true, attachments: attachments, fork: true),
                environment: baseEnv
            )
            let connection = CommandLineConnection(spec: spec, environment: rig.environment)
            _ = try await connection.start(
                AgentSessionRequest(workingDirectory: "/Users/rig/claude-repo", resumeSessionID: "claude-conv-9")
            )
            let promptTask = Task { try await connection.prompt(blocks) }
            guard await rig.waitForAgentLaunch() else {
                XCTFail("Timed out waiting for Claude launch in mode \(mode)")
                return
            }

            let expectedArguments = VitruvianCodeSupport.agentArguments(
                prompt: "inspect files",
                configuration: config,
                conversationID: "claude-conv-9",
                planMode: false,
                worktreeMode: true,
                ollamaDefaultModel: VitruvianCodeSupport.ollamaFallbackModel,
                attachments: attachments,
                forkSession: true
            )
            let expectedStdin = VitruvianCodeSupport.stdinUserMessage(
                VitruvianCodeSupport.promptWithAttachments("inspect files", attachments)
            )
            XCTAssertEqual(rig.agentArguments, expectedArguments, "mode=\(mode)")
            XCTAssertEqual(rig.agentEnvironment, VitruvianCodeSupport.childEnvironment(base: baseEnv, home: "/Users/rig"))
            XCTAssertEqual(rig.inputs, [expectedStdin], "first stdin message matches stdinUserMessage in mode \(mode)")

            rig.agentOutput?(Data(#"{"type":"result","stop_reason":"end_turn","session_id":"claude-conv-9","result":"ok"}"#.utf8 + Data("\n".utf8)))
            XCTAssertEqual(rig.inputCloses, 1, "stdin closes on .finished in mode \(mode)")
            rig.agentExit?(0)
            let reason = try await promptTask.value
            XCTAssertEqual(reason, .endTurn)
            await connection.stop()
        }

        // 3. Custom command: launchCommand path, commandEnvironment, stdout reply and stderr failure outcome.
        let customProvider = VitruvianCodeCLIProvider(
            id: UUID(uuidString: "77777777-0000-0000-0000-000000000001")!,
            name: "Custom Runner",
            commandTemplate: "/usr/local/bin/custom-runner --model {model} \"{prompt}\"",
            isBuiltIn: false
        )
        do {
            let rig = LaunchCaptureRig(baseEnvironment: baseEnv, existingFiles: ["/usr/local/bin/custom-runner"])
            let config = VitruvianCodeConfiguration(model: "custom-v1", activeProvider: customProvider)
            let spec = AgentConnectionSpec(
                provider: customProvider,
                configuration: config,
                agentPath: "/usr/local/bin/custom-runner",
                workingDirectory: "/Users/rig/custom",
                turnModes: AgentTurnModes(plan: false, worktree: false, attachments: [], fork: false),
                environment: baseEnv
            )
            let connection = CommandLineConnection(spec: spec, environment: rig.environment)
            _ = try await connection.start(AgentSessionRequest(workingDirectory: "/Users/rig/custom"))
            let promptTask = Task { try await connection.prompt([.text("hello custom")]) }
            guard await rig.waitForCommandLaunch() else {
                XCTFail("Timed out waiting for custom command launch")
                return
            }

            let expectedCommand = try XCTUnwrap(
                VitruvianCodeSupport.providerCommand(
                    template: customProvider.commandTemplate,
                    prompt: "hello custom",
                    model: "custom-v1"
                )
            )
            let expectedEnv = VitruvianCodeSupport.commandEnvironment(
                base: baseEnv,
                fileExists: { path in path == "/usr/local/bin/custom-runner" }
            )
            XCTAssertEqual(rig.commandPath, "/usr/local/bin/custom-runner")
            XCTAssertEqual(rig.commandArguments, expectedCommand.arguments)
            XCTAssertEqual(rig.commandEnvironment, expectedEnv)

            rig.commandOutput?(Data("custom answer\n".utf8))
            rig.commandExit?(0)
            let reason = try await promptTask.value
            XCTAssertEqual(reason, .endTurn)
            await connection.stop()

            var streamed: [AgentEvent] = []
            for await event in connection.events {
                streamed.append(event)
            }
            XCTAssertEqual(streamed, [
                .text("custom answer\n"),
                .finished(status: "end_turn", response: "custom answer", error: nil, conversationID: nil),
            ])
        }

        do {
            let rig = LaunchCaptureRig(baseEnvironment: baseEnv, existingFiles: ["/usr/local/bin/custom-runner"])
            let config = VitruvianCodeConfiguration(model: "custom-v1", activeProvider: customProvider)
            let spec = AgentConnectionSpec(
                provider: customProvider,
                configuration: config,
                agentPath: "/usr/local/bin/custom-runner",
                workingDirectory: "/Users/rig/custom",
                environment: baseEnv
            )
            let connection = CommandLineConnection(spec: spec, environment: rig.environment)
            _ = try await connection.start(AgentSessionRequest(workingDirectory: "/Users/rig/custom"))
            let promptTask = Task { try await connection.prompt([.text("boom")]) }
            guard await rig.waitForCommandLaunch() else {
                XCTFail("Timed out waiting for failing custom command launch")
                return
            }
            rig.commandErrors?(Data("fatal custom failure\n".utf8))
            rig.commandExit?(2)
            let reason = try await promptTask.value
            XCTAssertEqual(reason, .error)
            await connection.stop()

            var streamed: [AgentEvent] = []
            for await event in connection.events {
                streamed.append(event)
            }
            XCTAssertEqual(streamed, [
                .finished(status: "error", response: nil, error: "fatal custom failure", conversationID: nil),
            ])
        }
    }

    func testCommandLineConnectionAnswerWritesSameApprovalJSON() async throws {
        let rig = LaunchCaptureRig(baseEnvironment: ["PATH": "/usr/bin"])
        let config = VitruvianCodeConfiguration(approvalMode: .standard, activeProvider: .claude)
        let spec = AgentConnectionSpec(
            provider: .claude,
            configuration: config,
            agentPath: "/fake/claude",
            workingDirectory: "/Users/rig",
            environment: ["PATH": "/usr/bin"]
        )
        let connection = CommandLineConnection(spec: spec, environment: rig.environment)
        _ = try await connection.start(AgentSessionRequest(workingDirectory: "/Users/rig"))
        let promptTask = Task { try await connection.prompt([.text("run tool")]) }
        guard await rig.waitForAgentLaunch() else {
            XCTFail("Timed out waiting for Claude launch")
            return
        }
        rig.inputs.removeAll()

        let cases: [(id: String, choice: AgentAnswer, status: VitruvianCodeApprovalRequest.Status)] = [
            ("req-allow", .option("allow"), .approved),
            ("req-session", .option("allow_always"), .sessionAllowed),
            ("req-deny", .option("deny"), .denied),
            ("req-cancel", .cancelled, .denied),
        ]
        for entry in cases {
            try await connection.answer(entry.id, entry.choice)
            let expected = try XCTUnwrap(
                VitruvianCodeSupport.approvalResponseJSON(
                    for: VitruvianCodeApprovalRequest(toolName: "Bash", commandOrPath: "ls", requestID: entry.id),
                    decision: entry.status
                )
            )
            XCTAssertEqual(rig.inputs.last, expected, "mismatch for \(entry.id)")
        }

        rig.agentExit?(0)
        _ = try await promptTask.value
        await connection.stop()
    }

    func testCommandLineConnectionCancelTerminatesProcessAndPromptReturnsCancelled() async throws {
        let rig = LaunchCaptureRig(baseEnvironment: ["PATH": "/usr/bin"])
        let config = VitruvianCodeConfiguration(approvalMode: .yolo, activeProvider: .claude)
        let spec = AgentConnectionSpec(
            provider: .claude,
            configuration: config,
            agentPath: "/fake/claude",
            workingDirectory: "/Users/rig",
            environment: ["PATH": "/usr/bin"]
        )
        let connection = CommandLineConnection(spec: spec, environment: rig.environment)
        _ = try await connection.start(AgentSessionRequest(workingDirectory: "/Users/rig"))
        let promptTask = Task { try await connection.prompt([.text("long work")]) }
        guard await rig.waitForAgentLaunch() else {
            XCTFail("Timed out waiting for launch before cancel")
            return
        }
        XCTAssertEqual(rig.terminations, 0)

        await connection.cancel()
        XCTAssertEqual(rig.terminations, 1)

        rig.agentExit?(15)
        let reason = try await promptTask.value
        XCTAssertEqual(reason, .cancelled)
        await connection.stop()
    }

    func testSessionDrivesFakeAgentConnectionThroughMakeConnection() async throws {
        let rig = ComposerRig()
        var capturedSpecs: [AgentConnectionSpec] = []
        var createdConnections: [FakeAgentConnection] = []

        var env = rig.environment
        env.makeConnection = { spec in
            capturedSpecs.append(spec)
            let fake = FakeAgentConnection()
            createdConnections.append(fake)
            return fake
        }

        let session = VitruvianCodeQuickPromptSession(environment: env, host: rig.host)
        session.takeCheckpoint = { _ in nil }

        let imageAttachment = VitruvianCodeAttachment(url: URL(fileURLWithPath: "/tmp/shot.png"), isImage: true)
        let fileAttachment = VitruvianCodeAttachment(url: URL(fileURLWithPath: "/tmp/doc.txt"), isImage: false)
        session.attachments = [imageAttachment, fileAttachment]

        let config = VitruvianCodeConfiguration(approvalMode: .auto, model: "claude-sonnet-4-6", activeProvider: .claude)
        session.send("explain both", configuration: config, agentPath: "/fake/claude")

        XCTAssertEqual(capturedSpecs.count, 1)
        let firstSpec = try XCTUnwrap(capturedSpecs.first)
        XCTAssertEqual(firstSpec.provider, .claude)
        XCTAssertEqual(firstSpec.configuration.approvalMode, .auto)
        XCTAssertEqual(firstSpec.agentPath, "/fake/claude")
        XCTAssertEqual(firstSpec.workingDirectory, "/Users/rig")
        XCTAssertEqual(firstSpec.turnModes.attachments, [imageAttachment, fileAttachment])

        let fake1 = try XCTUnwrap(createdConnections.first)
        for _ in 0..<1000 where fake1.promptBlocks.isEmpty {
            await Task.yield()
        }
        XCTAssertEqual(fake1.startRequests, [AgentSessionRequest(workingDirectory: "/Users/rig", resumeSessionID: nil)])
        XCTAssertEqual(fake1.promptBlocks, [[
            .image(path: "/tmp/shot.png"),
            .text("@/tmp/doc.txt"),
            .text("explain both"),
        ]])

        fake1.emit(.started(conversationID: "fake-conv-77"))
        fake1.emit(.approval(VitruvianCodeApprovalRequest(
            toolName: "Bash",
            commandOrPath: "git status",
            requestID: "perm-77"
        )))
        for _ in 0..<1000 where !session.hasPendingApproval {
            await Task.yield()
        }
        XCTAssertEqual(session.conversationID, "fake-conv-77")
        XCTAssertTrue(session.hasPendingApproval)

        let approvalMsg = try XCTUnwrap(session.messages.first { $0.approvalRequest?.requestID == "perm-77" })
        session.decideApproval(messageID: approvalMsg.id, decision: .approved)
        for _ in 0..<1000 where fake1.answers.isEmpty {
            await Task.yield()
        }
        XCTAssertEqual(fake1.answers.count, 1)
        XCTAssertEqual(fake1.answers.first?.0, "perm-77")
        XCTAssertEqual(fake1.answers.first?.1, .option("allow"))

        fake1.emit(.text("Reply through AgentConnection"))
        fake1.emit(.finished(
            status: "end_turn",
            response: "Reply through AgentConnection",
            error: nil,
            conversationID: "fake-conv-77"
        ))
        fake1.finishPrompt(with: .endTurn)
        for _ in 0..<1000 where session.isRunning {
            await Task.yield()
        }
        XCTAssertFalse(session.isRunning)
        XCTAssertEqual(session.messages.last?.text, "Reply through AgentConnection")
        XCTAssertEqual(session.messages.last?.isError, false)

        // Second turn resumes the conversation ID and `stop()` calls `cancel()`.
        session.send("second turn", configuration: config, agentPath: "/fake/claude")
        XCTAssertEqual(createdConnections.count, 2)
        let fake2 = createdConnections[1]
        for _ in 0..<1000 where fake2.promptBlocks.isEmpty {
            await Task.yield()
        }
        XCTAssertEqual(
            fake2.startRequests,
            [AgentSessionRequest(workingDirectory: "/Users/rig", resumeSessionID: "fake-conv-77")]
        )
        session.stop()
        for _ in 0..<1000 where fake2.cancelCount == 0 {
            await Task.yield()
        }
        XCTAssertEqual(fake2.cancelCount, 1)
        fake2.finishPrompt(with: .cancelled)
        for _ in 0..<1000 where session.isRunning {
            await Task.yield()
        }
    }

    // MARK: - The plain-protocol path completes deterministically

    /// What the chat shows and tells the app when a turn ends.
    private struct Observed: Equatable {
        var lastText: String?
        var lastIsError: Bool?
        var messageCount: Int
        var failed: Bool?
        var endedCleanly: Bool?
        var failureDetail: String?
        var noticeText: String?
        var running: Bool
    }

    private func observe(_ session: VitruvianCodeQuickPromptSession, _ notices: [VitruvianCodeTurnNotice]) -> Observed {
        Observed(
            lastText: session.messages.last?.text,
            lastIsError: session.messages.last?.isError,
            messageCount: session.messages.count,
            failed: notices.last?.failed,
            endedCleanly: notices.last?.endedCleanly,
            failureDetail: notices.last?.failureDetail,
            noticeText: notices.last?.text,
            running: session.isRunning
        )
    }

    /// One turn of a built-in agent as a command-line process: the lines it
    /// prints, then its exit.
    private func commandLineTurn(lines: [String], exit status: Int32,
                                 launchFails: Bool = false) -> Observed {
        let rig = ComposerRig()
        var environment = rig.environment
        if launchFails {
            environment.launchAgent = { _, _, _, _, _, _ in throw CocoaError(.fileNoSuchFile) }
        }
        let session = VitruvianCodeQuickPromptSession(environment: environment, host: rig.host)
        session.takeCheckpoint = { _ in nil }
        var notices: [VitruvianCodeTurnNotice] = []
        session.onTurnFinished = { notices.append($0) }
        session.send("go", configuration: VitruvianCodeConfiguration(approvalMode: .yolo, activeProvider: .claude),
                     agentPath: "/fake/claude")
        for line in lines { rig.agentOutput?(Data((line + "\n").utf8)) }
        if !launchFails { rig.agentExit?(status) }
        return observe(session, notices)
    }

    /// The same turn through a fake connection: the events it sends, then
    /// how `prompt` ends. Everything is sent back to back, with no pause
    /// between the last event and the end of the turn.
    private func fakeTurn(events: [AgentEvent], reason: AgentStopReason = .endTurn,
                          throwing error: (any Error)? = nil,
                          trailing: [AgentEvent] = [],
                          onCompletion: ((VitruvianCodeQuickPromptSession) -> Void)? = nil) async -> Observed {
        let rig = ComposerRig()
        var environment = rig.environment
        let fake = FakeAgentConnection()
        fake.promptError = error
        environment.makeConnection = { _ in fake }
        let session = VitruvianCodeQuickPromptSession(environment: environment, host: rig.host)
        session.takeCheckpoint = { _ in nil }
        var notices: [VitruvianCodeTurnNotice] = []
        session.onTurnFinished = { notice in
            notices.append(notice)
            onCompletion?(session)
        }
        session.send("go", configuration: VitruvianCodeConfiguration(approvalMode: .yolo, activeProvider: .claude),
                     agentPath: "/fake/claude")
        for _ in 0..<1000 where fake.promptBlocks.isEmpty { await Task.yield() }
        if error == nil {
            for event in events { fake.emit(event) }
            if trailing.isEmpty {
                fake.finishPrompt(with: reason)
            } else {
                fake.finishPromptThenStreamEnds(with: reason, trailing: trailing, afterYields: 25)
            }
        }
        for _ in 0..<1000 where session.isRunning { await Task.yield() }
        return observe(session, notices)
    }

    func testEventsSentBeforePromptReturnsAreAllHandledInOrderAndFinishedComesFirst() async throws {
        // Many events sent back to back with the end of the turn: a consumer
        // that is stopped after a pause would lose the tail of them.
        let pieces = (0..<400).map { String($0 % 10) }
        var events: [AgentEvent] = pieces.map { .text($0) }
        events.append(.finished(status: "end_turn", response: nil, error: nil, conversationID: "c-1"))
        var atCompletion: (reply: String?, stopReason: String?)?
        let seen = await fakeTurn(
            events: events,
            onCompletion: { session in
                atCompletion = (session.messages.last?.text, session.messages.last?.stopReason)
            }
        )
        let expected = pieces.joined()
        XCTAssertEqual(seen.lastText, expected, "every event, in the order sent")
        XCTAssertEqual(atCompletion?.reply, expected, "all of it was shown before the turn completed")
        XCTAssertEqual(atCompletion?.stopReason, "end_turn", ".finished was handled before the turn completed")
        XCTAssertEqual(seen.noticeText, expected)
        XCTAssertFalse(seen.running)
    }

    func testEventsStillOnTheirWayWhenPromptReturnsAreHandledBeforeTheTurnCompletes() async throws {
        var atCompletion: (reply: String?, stopReason: String?)?
        let seen = await fakeTurn(
            events: [.text("early ")],
            trailing: [
                .text("late"),
                .finished(status: "end_turn", response: nil, error: nil, conversationID: "c-2"),
            ],
            onCompletion: { session in
                atCompletion = (session.messages.last?.text, session.messages.last?.stopReason)
            }
        )
        XCTAssertEqual(atCompletion?.reply, "early late", "the turn waited for the end of the stream")
        XCTAssertEqual(atCompletion?.stopReason, "end_turn")
        XCTAssertEqual(seen.lastText, "early late")
        XCTAssertEqual(seen.failed, false)
    }

    func testEveryStopReasonShowsWhatTheCommandLineCaseShows() async throws {
        let refusal = #"{"type":"result","stop_reason":"refusal","session_id":"s1","result":"I cannot help with that"}"#
        let apiError = #"{"type":"result","is_error":true,"stop_reason":"error","session_id":"s1","result":"API Error: Overloaded"}"#
        let ok = #"{"type":"result","stop_reason":"end_turn","session_id":"s1","result":"all done"}"#

        // end_turn
        let okEvents = AgentEvent.parseAll(ok)
        XCTAssertFalse(okEvents.isEmpty)
        let endTurnFake = await fakeTurn(events: okEvents, reason: .endTurn)
        XCTAssertEqual(endTurnFake, commandLineTurn(lines: [ok], exit: 0))
        XCTAssertEqual(endTurnFake.lastText, "all done")
        XCTAssertEqual(endTurnFake.failed, false)

        // refusal: the agent ended its turn, as exit 0 does for a command line.
        let refusalFake = await fakeTurn(events: AgentEvent.parseAll(refusal), reason: .refusal)
        XCTAssertEqual(refusalFake, commandLineTurn(lines: [refusal], exit: 0))
        XCTAssertEqual(refusalFake.lastText, "I cannot help with that")
        XCTAssertEqual(refusalFake.failed, false)

        // error, with the agent saying what went wrong.
        let errorFake = await fakeTurn(events: AgentEvent.parseAll(apiError), reason: .error)
        XCTAssertEqual(errorFake, commandLineTurn(lines: [apiError], exit: 0))
        XCTAssertEqual(errorFake.failed, true)
        XCTAssertEqual(errorFake.failureDetail, "API Error: Overloaded")

        // error with nothing printed: a bad exit, with the shared words.
        let silentFake = await fakeTurn(events: [], reason: .error)
        XCTAssertEqual(silentFake, commandLineTurn(lines: [], exit: 1))
        XCTAssertEqual(silentFake.failed, true)
        XCTAssertEqual(silentFake.lastIsError, true)
        XCTAssertEqual(silentFake.lastText, VitruvianCodeHostStrings().agentFailed)
    }

    func testAPromptThatThrowsShowsWhatACommandThatCannotStartShows() async throws {
        let thrown = await fakeTurn(events: [], throwing: CocoaError(.fileNoSuchFile))
        let launchFailed = commandLineTurn(lines: [], exit: 0, launchFails: true)
        XCTAssertEqual(thrown, launchFailed)
        XCTAssertEqual(thrown.lastIsError, true)
        XCTAssertEqual(thrown.lastText, VitruvianCodeHostStrings().agentFailed)
        XCTAssertEqual(thrown.failed, true)
        XCTAssertFalse(thrown.running)
    }

    // A custom command on the plain-protocol path ends as its own kind of turn.
    private func customTurn(viaFake events: [AgentEvent]?, reason: AgentStopReason = .endTurn,
                            stdout: String = "", stderr: String = "", exit status: Int32 = 0) async -> Observed {
        let provider = VitruvianCodeCLIProvider(
            id: UUID(uuidString: "77777777-0000-0000-0000-000000000009")!,
            name: "Custom Runner",
            commandTemplate: "/usr/local/bin/custom-runner \"{prompt}\"",
            isBuiltIn: false
        )
        let rig = LaunchCaptureRig(baseEnvironment: ["PATH": "/usr/local/bin:/usr/bin"],
                                   existingFiles: ["/usr/local/bin/custom-runner"])
        var environment = rig.environment
        let fake = FakeAgentConnection()
        if events != nil { environment.makeConnection = { _ in fake } }
        let session = VitruvianCodeQuickPromptSession(environment: environment, host: ComposerQuietHost())
        session.takeCheckpoint = { _ in nil }
        var notices: [VitruvianCodeTurnNotice] = []
        session.onTurnFinished = { notices.append($0) }
        session.send("go", configuration: VitruvianCodeConfiguration(activeProvider: provider), agentPath: nil)
        if let events {
            for _ in 0..<1000 where fake.promptBlocks.isEmpty { await Task.yield() }
            for event in events { fake.emit(event) }
            fake.finishPrompt(with: reason)
        } else {
            for _ in 0..<1000 where rig.commandOutput == nil { await Task.yield() }
            if !stdout.isEmpty { rig.commandOutput?(Data(stdout.utf8)) }
            if !stderr.isEmpty { rig.commandErrors?(Data(stderr.utf8)) }
            rig.commandExit?(status)
        }
        for _ in 0..<1000 where session.isRunning { await Task.yield() }
        return observe(session, notices)
    }

    func testACustomCommandOnTheProtocolPathCompletesLikeACommandDoes() async throws {
        // It printed an answer.
        let replyFake = await customTurn(viaFake: [
            .text("hello "), .text("there\n"),
            .finished(status: "end_turn", response: "hello there", error: nil, conversationID: nil),
        ])
        let replyCommand = await customTurn(viaFake: nil, stdout: "hello there\n")
        XCTAssertEqual(replyFake, replyCommand)
        XCTAssertEqual(replyFake.lastText, "hello there")
        XCTAssertEqual(replyFake.endedCleanly, true)

        // It failed and said why on standard error.
        let failedFake = await customTurn(viaFake: [
            .finished(status: "error", response: nil, error: "no such model", conversationID: nil),
        ], reason: .error)
        let failedCommand = await customTurn(viaFake: nil, stderr: "no such model\n", exit: 2)
        XCTAssertEqual(failedFake.lastText, failedCommand.lastText)
        XCTAssertEqual(failedFake.lastIsError, true)
        XCTAssertEqual(failedFake.failed, true)
        XCTAssertEqual(failedFake.failureDetail, "no such model")
        XCTAssertEqual(failedFake.messageCount, failedCommand.messageCount)

        // It printed nothing.
        let silentFake = await customTurn(viaFake: [], reason: .endTurn)
        let silentCommand = await customTurn(viaFake: nil)
        XCTAssertEqual(silentFake, silentCommand)
        XCTAssertEqual(silentFake.lastText, VitruvianCodeHostStrings().commandNoOutput)
    }

    /// Events of a turn that has since been replaced (here by New chat) must not
    /// reach the screen, the same rule the callback path has.
    func testSessionDropsEventsOfAReplacedTurnFromAFakeConnection() async throws {
        let rig = ComposerRig()
        var created: [FakeAgentConnection] = []
        var env = rig.environment
        env.makeConnection = { _ in
            let fake = FakeAgentConnection()
            created.append(fake)
            return fake
        }
        let session = VitruvianCodeQuickPromptSession(environment: env, host: rig.host)
        session.takeCheckpoint = { _ in nil }
        let config = VitruvianCodeConfiguration(approvalMode: .yolo, activeProvider: .claude)
        session.send("first", configuration: config, agentPath: "/fake/claude")
        let stale = try XCTUnwrap(created.first)
        for _ in 0..<1000 where stale.promptBlocks.isEmpty {
            await Task.yield()
        }
        XCTAssertTrue(session.isRunning)

        session.newChat()
        XCTAssertTrue(session.messages.isEmpty)

        stale.emit(.started(conversationID: "stale-conv"))
        stale.emit(.text("stale words"))
        stale.emit(.finished(status: "end_turn", response: "stale words", error: nil, conversationID: "stale-conv"))
        stale.finishPrompt(with: .endTurn)
        for _ in 0..<50 {
            await Task.yield()
        }
        XCTAssertTrue(session.messages.isEmpty, "a replaced turn's events are dropped")
        XCTAssertNil(session.conversationID)
        XCTAssertFalse(session.isRunning)
    }
}

@MainActor
private final class LaunchCaptureRig {
    let defaults: UserDefaults
    let baseEnvironment: [String: String]
    let existingFiles: Set<String>

    var agentPath: String?
    var agentArguments: [String] = []
    var agentDirectory: String?
    var agentEnvironment: [String: String] = [:]
    var agentOutput: (@MainActor @Sendable (Data) -> Void)?
    var agentExit: (@MainActor @Sendable (Int32) -> Void)?

    var commandPath: String?
    var commandArguments: [String] = []
    var commandDirectory: String?
    var commandEnvironment: [String: String] = [:]
    var commandOutput: (@MainActor @Sendable (Data) -> Void)?
    var commandErrors: (@MainActor @Sendable (Data) -> Void)?
    var commandExit: (@MainActor @Sendable (Int32) -> Void)?

    var inputs: [Data] = []
    var inputCloses = 0
    var terminations = 0

    init(baseEnvironment: [String: String], existingFiles: Set<String> = []) {
        let suite = "com.vitruviansoftware.vitruvian-code.tests.launch-capture.\(UUID().uuidString)"
        defaults = ScratchDefaults.suite(named: suite)!
        defaults.removePersistentDomain(forName: suite)
        self.baseEnvironment = baseEnvironment
        self.existingFiles = existingFiles
    }

    var environment: VitruvianCodeEngine.Environment {
        VitruvianCodeEngine.Environment(
            defaults: defaults,
            home: "/Users/rig",
            processEnvironment: baseEnvironment,
            stateDirectory: "/Users/rig/state",
            isExecutable: { [existingFiles] path in existingFiles.contains(path) },
            fileExists: { [existingFiles] path in existingFiles.contains(path) },
            readFile: { _ in nil },
            readTail: { _, _ in nil },
            writePrivateFile: { _, _ in false },
            removeFile: { _ in },
            isBotProcess: { _ in false },
            signal: { _, _ in },
            launchBot: { _, _, _, _, _ in throw CocoaError(.fileWriteUnknown) },
            schedule: { _, _ in },
            openFile: { _ in },
            launchAgent: { [unowned self] path, arguments, directory, env, onOutput, onExit in
                agentPath = path
                agentArguments = arguments
                agentDirectory = directory
                agentEnvironment = env
                agentOutput = onOutput
                agentExit = onExit
                return VitruvianCodeRunningAgent(
                    terminate: { [unowned self] in terminations += 1 },
                    sendInput: { [unowned self] data in inputs.append(data) },
                    closeInput: { [unowned self] in inputCloses += 1 }
                )
            },
            launchCommand: { [unowned self] path, arguments, directory, env, onOutput, onErrors, onExit in
                commandPath = path
                commandArguments = arguments
                commandDirectory = directory
                commandEnvironment = env
                commandOutput = onOutput
                commandErrors = onErrors
                commandExit = onExit
                return VitruvianCodeRunningAgent(
                    terminate: { [unowned self] in terminations += 1 }
                )
            }
        )
    }

    func waitForAgentLaunch() async -> Bool {
        for _ in 0..<1000 {
            if agentOutput != nil { return true }
            await Task.yield()
        }
        return false
    }

    func waitForCommandLaunch() async -> Bool {
        for _ in 0..<1000 {
            if commandOutput != nil { return true }
            await Task.yield()
        }
        return false
    }
}

@MainActor
private final class FakeAgentConnection: AgentConnection {
    let capabilities = AgentCapabilities(resumeSession: true, images: true)
    let events: AsyncStream<AgentEvent>
    private let eventContinuation: AsyncStream<AgentEvent>.Continuation
    private var promptContinuation: CheckedContinuation<AgentStopReason, any Error>?

    var startRequests: [AgentSessionRequest] = []
    var promptBlocks: [[PromptBlock]] = []
    var answers: [(String, AgentAnswer)] = []
    var cancelCount = 0
    var stopCount = 0
    var promptError: (any Error)?

    init() {
        let (stream, continuation) = AsyncStream.makeStream(of: AgentEvent.self)
        self.events = stream
        self.eventContinuation = continuation
    }

    func start(_ request: AgentSessionRequest) async throws -> String {
        startRequests.append(request)
        return request.resumeSessionID ?? ""
    }

    func prompt(_ blocks: [PromptBlock]) async throws -> AgentStopReason {
        promptBlocks.append(blocks)
        if let promptError {
            eventContinuation.finish()
            throw promptError
        }
        return try await withCheckedThrowingContinuation { continuation in
            self.promptContinuation = continuation
        }
    }

    func cancel() async {
        cancelCount += 1
    }

    func answer(_ requestID: String, _ choice: AgentAnswer) async throws {
        answers.append((requestID, choice))
    }

    func setConfigOption(_ id: String, _ value: AgentConfigValue) async throws -> [AgentConfigOption] {
        throw AgentConnectionError.notSupportedYet
    }

    func stop() async {
        stopCount += 1
        eventContinuation.finish()
    }

    func emit(_ event: AgentEvent) {
        eventContinuation.yield(event)
    }

    /// Ends the turn, then sends `trailing` a little later and ends the stream:
    /// what a connection whose last events are still on their way when its
    /// prompt returns does.
    func finishPromptThenStreamEnds(with reason: AgentStopReason, trailing: [AgentEvent], afterYields: Int) {
        promptContinuation?.resume(returning: reason)
        promptContinuation = nil
        Task { @MainActor in
            for _ in 0..<afterYields { await Task.yield() }
            for event in trailing { eventContinuation.yield(event) }
            eventContinuation.finish()
        }
    }

    /// Ends the turn: the stream ends too, after what was sent, as a
    /// per-turn connection does.
    func finishPrompt(with reason: AgentStopReason) {
        eventContinuation.finish()
        promptContinuation?.resume(returning: reason)
        promptContinuation = nil
    }
}
