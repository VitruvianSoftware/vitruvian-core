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

    func testMinimalAgentConnectionMethodsStoreRequestAndThrowNotSupportedYet() async throws {
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
            _ = try await connection.prompt([.text("hi")])
            XCTFail("expected prompt(_:) to throw notSupportedYet in step 1a")
        } catch let error as AgentConnectionError {
            XCTAssertEqual(error, .notSupportedYet)
        }

        do {
            try await connection.answer("r1", .cancelled)
            XCTFail("expected answer(_:_:) to throw notSupportedYet in step 1a")
        } catch let error as AgentConnectionError {
            XCTAssertEqual(error, .notSupportedYet)
        }

        do {
            _ = try await connection.setConfigOption("model", .string("sonnet"))
            XCTFail("expected setConfigOption(_:_:) to throw notSupportedYet in step 1a")
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
}
