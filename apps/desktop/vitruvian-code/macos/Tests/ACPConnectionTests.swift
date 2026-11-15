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
final class ACPConnectionTests: XCTestCase {
    private static let defaultSpec = AgentProcessLaunchSpec(
        executable: "/fake/acp-agent",
        arguments: ["acp"],
        environment: [:],
        workingDirectory: "/workspace"
    )

    // MARK: - 1. Initialize capability advertisement

    func testInitializeAdvertisesExactlyThePolicysEnabledFeatures() async throws {
        let cases: [(policy: ACPClientPolicy, read: Bool, write: Bool, terminal: Bool, elicitation: Bool)] = [
            (.none, false, false, false, false),
            (.antigravity(version: "1.4.5"), false, false, false, false),
            (.antigravity(version: "1.4.4"), true, false, false, false),
            (
                ACPClientPolicy(readTextFile: true, writeTextFile: true, terminal: true, elicitation: true),
                true,
                true,
                true,
                true
            ),
        ]

        for item in cases {
            let agent = ScriptedACPAgent()
            let connection = ACPConnection(
                launchSpec: Self.defaultSpec,
                policy: item.policy,
                processFactory: agent.makeProcessFactory()
            )

            let driver = Task {
                try await agent.playSteps([
                    .expectClientRequest(method: "initialize"),
                    .agentSend(
                        .object([
                            "jsonrpc": .string("2.0"),
                            "id": .string("$id"),
                            "result": .object(["protocolVersion": .int(1)]),
                        ])
                    ),
                    .expectClientRequest(method: "session/new"),
                    .agentSend(
                        .object([
                            "jsonrpc": .string("2.0"),
                            "id": .string("$id"),
                            "result": .object(["sessionId": .string("s-cap")]),
                        ])
                    ),
                ])
            }

            let sessionID = try await withACPTestTimeout(seconds: 3.0) {
                try await connection.start(AgentSessionRequest(workingDirectory: "/workspace"))
            }
            try await withACPTestTimeout(seconds: 3.0) { try await driver.value }
            XCTAssertEqual(sessionID, "s-cap")

            let initMsg = try await agent.clientMessage(at: 0)
            let caps = initMsg.objectValue?["params"]?.objectValue?["clientCapabilities"]?.objectValue
            let fsCaps = caps?["fs"]?.objectValue
            XCTAssertEqual(fsCaps?["readTextFile"]?.boolValue, item.read)
            XCTAssertEqual(fsCaps?["writeTextFile"]?.boolValue, item.write)
            XCTAssertEqual(caps?["terminal"]?.boolValue, item.terminal)
            if item.elicitation {
                XCTAssertNotNil(caps?["elicitation"]?.objectValue)
            } else {
                XCTAssertNil(caps?["elicitation"])
            }
            await connection.stop()
        }
    }

    // MARK: - 2. Session setup method chosen strictly by capability

    func testResumeLoadOrNewIsChosenStrictlyByAdvertisedCapability() async throws {
        struct Scenario {
            let name: String
            let resumeID: String?
            let agentCaps: ACPJSONValue
            let expectedMethod: String
            let returnedSessionID: String
        }

        let scenarios: [Scenario] = [
            Scenario(
                name: "resume preferred when both resume and load are advertised",
                resumeID: "prev-1",
                agentCaps: .object([
                    "loadSession": .bool(true),
                    "sessionCapabilities": .object(["resume": .object([:])]),
                ]),
                expectedMethod: "session/resume",
                returnedSessionID: "prev-1"
            ),
            Scenario(
                name: "load chosen when resume is absent and loadSession is true",
                resumeID: "prev-2",
                agentCaps: .object([
                    "loadSession": .bool(true),
                ]),
                expectedMethod: "session/load",
                returnedSessionID: "prev-2"
            ),
            Scenario(
                name: "new chosen when neither resume nor loadSession is advertised",
                resumeID: "prev-3",
                agentCaps: .object([
                    "loadSession": .bool(false),
                ]),
                expectedMethod: "session/new",
                returnedSessionID: "fresh-3"
            ),
            Scenario(
                name: "new chosen when resumeSessionID is nil even if resume is advertised",
                resumeID: nil,
                agentCaps: .object([
                    "loadSession": .bool(true),
                    "sessionCapabilities": .object(["resume": .object([:])]),
                ]),
                expectedMethod: "session/new",
                returnedSessionID: "fresh-4"
            ),
        ]

        for scenario in scenarios {
            let agent = ScriptedACPAgent()
            let connection = ACPConnection(
                launchSpec: Self.defaultSpec,
                policy: .none,
                processFactory: agent.makeProcessFactory()
            )

            let driver = Task {
                try await agent.playSteps([
                    .expectClientRequest(method: "initialize"),
                    .agentSend(
                        .object([
                            "jsonrpc": .string("2.0"),
                            "id": .string("$id"),
                            "result": .object([
                                "protocolVersion": .int(1),
                                "agentCapabilities": scenario.agentCaps,
                            ]),
                        ])
                    ),
                    .expectClientRequest(method: scenario.expectedMethod),
                    .agentSend(
                        .object([
                            "jsonrpc": .string("2.0"),
                            "id": .string("$id"),
                            "result": .object(["sessionId": .string(scenario.returnedSessionID)]),
                        ])
                    ),
                ])
            }

            let sessionID = try await withACPTestTimeout(seconds: 3.0) {
                try await connection.start(
                    AgentSessionRequest(
                        workingDirectory: "/workspace",
                        resumeSessionID: scenario.resumeID
                    )
                )
            }
            try await withACPTestTimeout(seconds: 3.0) { try await driver.value }
            XCTAssertEqual(sessionID, scenario.returnedSessionID, scenario.name)

            let allSent = await agent.allClientMessages()
            XCTAssertEqual(allSent.count, 2, "\(scenario.name): must send initialize + exactly one session setup RPC")
            XCTAssertEqual(allSent[1].objectValue?["method"]?.stringValue, scenario.expectedMethod, scenario.name)
            await connection.stop()
        }
    }

    // MARK: - 3. Every update kind maps to the right AgentEvent (via ndjson fixture) & session/close advertised

    func testEverySessionUpdateKindMapsToAgentEventAndStopSendsCloseWhenAdvertised() async throws {
        let steps = ACPFixtureLoader.loadSteps(named: "turn-all-updates.ndjson")
        let tempStateDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("acp-log-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempStateDir) }

        let agent = ScriptedACPAgent()
        let connection = ACPConnection(
            launchSpec: Self.defaultSpec,
            policy: .none,
            stateFolderURL: tempStateDir,
            processFactory: agent.makeProcessFactory()
        )
        let reader = ACPEventStreamReader(connection.events)

        let driver = Task {
            try await agent.playSteps(steps)
        }

        let sessionID = try await withACPTestTimeout(seconds: 3.0) {
            try await connection.start(AgentSessionRequest(workingDirectory: "/workspace"))
        }
        XCTAssertEqual(sessionID, "sess-fixture-1")
        XCTAssertTrue(connection.capabilities.loadSession)
        XCTAssertTrue(connection.capabilities.resumeSession)
        XCTAssertTrue(connection.capabilities.closeSession)
        XCTAssertTrue(connection.capabilities.images)
        XCTAssertTrue(connection.capabilities.mcpHTTP)
        XCTAssertTrue(connection.capabilities.authMethods)

        let stopReason = try await withACPTestTimeout(seconds: 3.0) {
            try await connection.prompt([.text("Refactor parser")])
        }
        XCTAssertEqual(stopReason, .endTurn)

        let turnEvents = try await reader.collectUntilFinished(timeout: 3.0)

        // Verify each update kind mapped cleanly in order:
        XCTAssertTrue(turnEvents.contains(.slashCommands(["review", "compact"])))
        XCTAssertTrue(turnEvents.contains(.sessionInfo(title: "Refactor parser", updatedAt: "2026-11-12T10:00:00Z")))
        XCTAssertTrue(
            turnEvents.contains(
                .configOptions([
                    AgentConfigOption(id: "mode", name: "Mode", value: .string("code"), options: ["code", "architect"]),
                    AgentConfigOption(id: "fast", name: "Fast mode", value: .bool(false), options: []),
                ])
            )
        )
        XCTAssertTrue(
            turnEvents.contains(
                .configOptions([
                    AgentConfigOption(id: "mode", name: "Mode", value: .string("architect"), options: ["code", "architect"]),
                    AgentConfigOption(id: "fast", name: "Fast mode", value: .bool(false), options: []),
                ])
            )
        )
        XCTAssertTrue(
            turnEvents.contains(
                .planReplaced([
                    PlanEntry(content: "Inspect module", status: .completed, priority: .high),
                    PlanEntry(content: "Write tests", status: .inProgress, priority: .medium),
                ])
            )
        )
        XCTAssertTrue(turnEvents.contains(.thinking("Checking module boundaries...")))
        // `user_message_chunk` must NOT appear in `.text`:
        XCTAssertFalse(turnEvents.contains(.text("Echoed user prompt")))

        let toolSteps: [VitruvianCodeToolStep] = turnEvents.compactMap {
            if case .toolStep(let step) = $0 { return step }
            return nil
        }
        XCTAssertTrue(toolSteps.contains { $0.id == "call-1" && $0.kind == .read && $0.filePath == "/workspace/Sources/App.swift" })
        XCTAssertTrue(
            toolSteps.contains {
                $0.id == "call-2"
                    && $0.kind == .edit
                    && $0.filePath == "/workspace/Sources/App.swift"
                    && $0.diffOld == "let a = 1"
                    && $0.diffNew == "let a = 2"
            }
        )
        XCTAssertTrue(turnEvents.contains(.toolStepResult(id: "call-1", output: "import Foundation", isError: false)))
        XCTAssertTrue(turnEvents.contains(.toolStepResult(id: "call-2", output: nil, isError: false)))

        XCTAssertTrue(
            turnEvents.contains(
                .contextUsage(
                    VitruvianCodeContextUsage(
                        inputTokens: 900,
                        cachedTokens: 150,
                        outputTokens: 300,
                        contextWindow: 200_000
                    )
                )
            )
        )
        XCTAssertTrue(turnEvents.contains(.text("Done ")))
        XCTAssertTrue(turnEvents.contains(.text("refactoring.")))
        XCTAssertEqual(
            turnEvents.last,
            .finished(
                status: "completed",
                response: "Done refactoring.",
                error: nil,
                conversationID: "sess-fixture-1",
                metrics: VitruvianCodeTurnMetrics(inputTokens: 900, outputTokens: 300, cachedTokens: 150)
            )
        )

        // Unknown update kind was logged without failing the turn.
        let logPath = VitruvianCodeSupport.statePaths(
            home: tempStateDir.path,
            defaultStateDirectory: tempStateDir.path
        ).chatLogPath(sessionID: "sess-fixture-1")
        let logText = (try? String(contentsOfFile: logPath, encoding: .utf8)) ?? ""
        XCTAssertTrue(logText.contains("future_custom_update"))

        // `stop()` sends `session/close` because `closeSession` was advertised in the fixture.
        await connection.stop()
        try await withACPTestTimeout(seconds: 3.0) { try await driver.value }
        let allSent = await agent.allClientMessages()
        XCTAssertEqual(allSent.last?.objectValue?["method"]?.stringValue, "session/close")
    }

    func testStopSkipsSessionCloseWhenNotAdvertisedAndTerminatesProcessWithGrace() async throws {
        let agent = ScriptedACPAgent()
        let connection = ACPConnection(
            launchSpec: Self.defaultSpec,
            policy: .none,
            terminationGrace: 0.42,
            processFactory: agent.makeProcessFactory()
        )

        let driver = Task {
            try await agent.playSteps([
                .expectClientRequest(method: "initialize"),
                .agentSend(
                    .object([
                        "jsonrpc": .string("2.0"),
                        "id": .string("$id"),
                        "result": .object(["protocolVersion": .int(1)]),
                    ])
                ),
                .expectClientRequest(method: "session/new"),
                .agentSend(
                    .object([
                        "jsonrpc": .string("2.0"),
                        "id": .string("$id"),
                        "result": .object(["sessionId": .string("s-no-close")]),
                    ])
                ),
            ])
        }

        _ = try await withACPTestTimeout(seconds: 3.0) {
            try await connection.start(AgentSessionRequest(workingDirectory: "/workspace"))
        }
        try await withACPTestTimeout(seconds: 3.0) { try await driver.value }
        XCTAssertFalse(connection.capabilities.closeSession)

        await connection.stop()
        let methods = await agent.allClientMessages().compactMap { $0.objectValue?["method"]?.stringValue }
        XCTAssertFalse(methods.contains("session/close"))
        let terminations = await agent.terminations()
        XCTAssertEqual(terminations, [0.42])
    }

    // MARK: - 4. Replay during session/load is suppressed

    func testReplayedHistoryDuringSessionLoadAndExplicitReplayMetaAreNotEmitted() async throws {
        let steps = ACPFixtureLoader.loadSteps(named: "session-load-replay.ndjson")
        let agent = ScriptedACPAgent()
        let connection = ACPConnection(
            launchSpec: Self.defaultSpec,
            policy: .none,
            processFactory: agent.makeProcessFactory()
        )
        let reader = ACPEventStreamReader(connection.events)

        let driver = Task {
            try await agent.playSteps(steps)
        }

        let sessionID = try await withACPTestTimeout(seconds: 3.0) {
            try await connection.start(
                AgentSessionRequest(
                    workingDirectory: "/workspace",
                    resumeSessionID: "sess-reloaded"
                )
            )
        }
        XCTAssertEqual(sessionID, "sess-reloaded")
        XCTAssertTrue(connection.capabilities.configOptions, "config_option_update during session/load should still populate configState")

        let reason = try await withACPTestTimeout(seconds: 3.0) {
            try await connection.prompt([.text("Next prompt")])
        }
        XCTAssertEqual(reason, .endTurn)
        try await withACPTestTimeout(seconds: 3.0) { try await driver.value }

        let events = try await reader.collectUntilFinished(timeout: 3.0)
        XCTAssertEqual(
            events,
            [
                .text("Fresh reply"),
                .finished(
                    status: "completed",
                    response: "Fresh reply",
                    error: nil,
                    conversationID: "sess-reloaded",
                    metrics: nil
                ),
            ]
        )
        await connection.stop()
    }

    // MARK: - 5. Image prompt block encoding vs resource_link fallback

    func testImageBlockEncodesBase64WhenImagesAdvertisedAndFallsBackToResourceLinkOtherwise() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("acp-img-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let imageURL = tempDir.appendingPathComponent("shot.png")
        let pngBytes = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        try pngBytes.write(to: imageURL)

        for supportsImages in [true, false] {
            let agent = ScriptedACPAgent()
            let connection = ACPConnection(
                launchSpec: Self.defaultSpec,
                policy: .none,
                processFactory: agent.makeProcessFactory()
            )

            let driver = Task {
                try await agent.playSteps([
                    .expectClientRequest(method: "initialize"),
                    .agentSend(
                        .object([
                            "jsonrpc": .string("2.0"),
                            "id": .string("$id"),
                            "result": .object([
                                "protocolVersion": .int(1),
                                "agentCapabilities": .object([
                                    "promptCapabilities": .object(["image": .bool(supportsImages)]),
                                ]),
                            ]),
                        ])
                    ),
                    .expectClientRequest(method: "session/new"),
                    .agentSend(
                        .object([
                            "jsonrpc": .string("2.0"),
                            "id": .string("$id"),
                            "result": .object(["sessionId": .string("s-img")]),
                        ])
                    ),
                    .expectClientRequest(method: "session/prompt"),
                    .agentSend(
                        .object([
                            "jsonrpc": .string("2.0"),
                            "id": .string("$id"),
                            "result": .object(["stopReason": .string("end_turn")]),
                        ])
                    ),
                ])
            }

            _ = try await withACPTestTimeout(seconds: 3.0) {
                try await connection.start(AgentSessionRequest(workingDirectory: tempDir.path))
            }
            _ = try await withACPTestTimeout(seconds: 3.0) {
                try await connection.prompt([.text("Describe"), .image(path: imageURL.path)])
            }
            try await withACPTestTimeout(seconds: 3.0) { try await driver.value }

            let promptMsg = try await agent.clientMessage(at: 2)
            let blocks = promptMsg.objectValue?["params"]?.objectValue?["prompt"]?.arrayValue ?? []
            XCTAssertEqual(blocks.count, 2)
            XCTAssertEqual(blocks[0].objectValue?["type"]?.stringValue, "text")
            if supportsImages {
                XCTAssertEqual(blocks[1].objectValue?["type"]?.stringValue, "image")
                XCTAssertEqual(blocks[1].objectValue?["mimeType"]?.stringValue, "image/png")
                XCTAssertEqual(blocks[1].objectValue?["data"]?.stringValue, pngBytes.base64EncodedString())
            } else {
                XCTAssertEqual(blocks[1].objectValue?["type"]?.stringValue, "resource_link")
                XCTAssertEqual(blocks[1].objectValue?["name"]?.stringValue, "shot.png")
                XCTAssertEqual(blocks[1].objectValue?["mimeType"]?.stringValue, "image/png")
                XCTAssertEqual(blocks[1].objectValue?["uri"]?.stringValue, imageURL.absoluteString)
                XCTAssertEqual(blocks[1].objectValue?["size"]?.intValue, pngBytes.count)
            }
            await connection.stop()
        }
    }

    // MARK: - 6. Cancel sends session/cancel and waits for pending prompt result

    func testCancelSendsSessionCancelNotificationAndWaitsForPromptToReturnCancelled() async throws {
        let agent = ScriptedACPAgent()
        let connection = ACPConnection(
            launchSpec: Self.defaultSpec,
            policy: .none,
            processFactory: agent.makeProcessFactory()
        )
        let reader = ACPEventStreamReader(connection.events)

        let startDriver = Task {
            try await agent.playSteps([
                .expectClientRequest(method: "initialize"),
                .agentSend(
                    .object([
                        "jsonrpc": .string("2.0"),
                        "id": .string("$id"),
                        "result": .object(["protocolVersion": .int(1)]),
                    ])
                ),
                .expectClientRequest(method: "session/new"),
                .agentSend(
                    .object([
                        "jsonrpc": .string("2.0"),
                        "id": .string("$id"),
                        "result": .object(["sessionId": .string("s-cancel")]),
                    ])
                ),
            ])
        }
        _ = try await withACPTestTimeout(seconds: 3.0) {
            try await connection.start(AgentSessionRequest(workingDirectory: "/workspace"))
        }
        try await withACPTestTimeout(seconds: 3.0) { try await startDriver.value }

        let promptTask = Task {
            try await connection.prompt([.text("Long job")])
        }
        let promptMsg = try await agent.clientMessage(at: 2)
        let promptID = promptMsg.objectValue?["id"] ?? .int(3)

        @MainActor
        final class CancelProbe {
            var returned = false
        }
        let probe = CancelProbe()
        let cancelTask = Task { @MainActor in
            await connection.cancel()
            probe.returned = true
        }

        let cancelMsg = try await agent.clientMessage(at: 3)
        XCTAssertEqual(cancelMsg.objectValue?["method"]?.stringValue, "session/cancel")
        XCTAssertNil(cancelMsg.objectValue?["id"], "session/cancel is a notification without id")

        // Verify `cancel()` is still suspended before the scripted prompt result is sent, then returns after.
        try await Task.sleep(nanoseconds: 40_000_000)
        XCTAssertFalse(probe.returned, "cancel() must remain suspended until session/prompt resolves")

        try await agent.sendToClient(
            .object([
                "jsonrpc": .string("2.0"),
                "id": promptID,
                "result": .object(["stopReason": .string("cancelled")]),
            ])
        )

        try await withACPTestTimeout(seconds: 3.0) { await cancelTask.value }
        XCTAssertTrue(probe.returned, "cancel() must return after session/prompt resolves")
        let reason = try await withACPTestTimeout(seconds: 3.0) { try await promptTask.value }
        XCTAssertEqual(reason, .cancelled)

        let events = try await reader.collectUntilFinished(timeout: 3.0)
        XCTAssertEqual(
            events.last,
            .finished(
                status: "cancelled",
                response: nil,
                error: nil,
                conversationID: "s-cancel",
                metrics: nil
            )
        )
        await connection.stop()
    }

    // MARK: - 7. Permissions & Elicitations (via ndjson fixture)

    func testPermissionAutoAllowApprovalAnswerAndFormAndURLElicitations() async throws {
        @MainActor
        final class ModeBox {
            var mode: VitruvianCodeApprovalMode = .standard
        }

        let steps = ACPFixtureLoader.loadSteps(named: "permission-and-elicitation.ndjson")
        let agent = ScriptedACPAgent()
        let modeBox = ModeBox()
        let connection = ACPConnection(
            launchSpec: Self.defaultSpec,
            policy: ACPClientPolicy(elicitation: true),
            modeProvider: { (modeBox.mode, false) },
            processFactory: agent.makeProcessFactory()
        )
        let reader = ACPEventStreamReader(connection.events)

        let driver = Task {
            try await agent.playSteps(steps)
        }

        _ = try await withACPTestTimeout(seconds: 3.0) {
            try await connection.start(AgentSessionRequest(workingDirectory: "/workspace"))
        }

        let promptTask = Task {
            try await connection.prompt([.text("Deploy")])
        }

        // 1. First request in fixture is `read`, which policy auto-allows without emitting `.approval`.
        //    Next emitted event is `.approval` for `execute` (`rm -rf build`).
        let firstEvent = try await reader.next(timeout: 3.0)
        guard case .approval(let approval) = firstEvent else {
            XCTFail("Expected .approval for execute tool call, got \(String(describing: firstEvent))")
            return
        }
        XCTAssertEqual(approval.id, "tc-exec")
        XCTAssertEqual(approval.commandOrPath, "rm -rf build")
        XCTAssertEqual(approval.options.map(\.kind), [.allowOnce, .allowAlways, .rejectOnce])
        try await connection.answer(approval.requestID!, .option("opt-allow-once"))

        // 2. Next event is form elicitation `.question`.
        let secondEvent = try await reader.next(timeout: 3.0)
        guard case .question(let formQuestion) = secondEvent else {
            XCTFail("Expected form .question, got \(String(describing: secondEvent))")
            return
        }
        XCTAssertNil(formQuestion.url)
        XCTAssertEqual(formQuestion.fields.map(\.id), ["branch", "dryRun"])
        try await connection.answer(
            formQuestion.requestID,
            .form(["branch": "main", "dryRun": "true"])
        )

        // 3. Next event is URL elicitation `.question`; switch mode to `.yolo` BEFORE answering so the
        //    subsequent `perm-exec-2` request in the fixture is auto-allowed without restart!
        let thirdEvent = try await reader.next(timeout: 3.0)
        guard case .question(let urlQuestion) = thirdEvent else {
            XCTFail("Expected URL .question, got \(String(describing: thirdEvent))")
            return
        }
        XCTAssertEqual(urlQuestion.url, "https://auth.example.com/device")
        modeBox.mode = .yolo
        try await connection.answer(urlQuestion.requestID, .option("accept"))

        let stopReason = try await withACPTestTimeout(seconds: 3.0) { try await promptTask.value }
        XCTAssertEqual(stopReason, .endTurn)
        try await withACPTestTimeout(seconds: 3.0) { try await driver.value }

        let remaining = try await reader.collectUntilFinished(timeout: 3.0)
        XCTAssertFalse(remaining.contains { if case .approval = $0 { return true }; return false })
        XCTAssertTrue(remaining.contains(.text("Interactive flow complete.")))
        await connection.stop()
    }

    // MARK: - 8. Unexpected exit & stderr redaction + session handling of .connectionFailed

    func testUnexpectedProcessExitEmitsConnectionFailedThenFinishedErrorAndRedactsStderrLogs() async throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("acp-crash-\(UUID().uuidString)", isDirectory: true)
        let customStateDir = tempRoot.appendingPathComponent("custom-state", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let secretToken = "sk-super-secret-token-999"
        let agent = ScriptedACPAgent()
        let connection = ACPConnection(
            launchSpec: Self.defaultSpec,
            policy: .none,
            stateFolderURL: tempRoot,
            stateDirectoryOverride: customStateDir.path,
            redactions: [secretToken],
            processFactory: agent.makeProcessFactory()
        )
        let reader = ACPEventStreamReader(connection.events)

        // Emit a stderr line BEFORE `sessionID` exists to prove early buffering + redaction!
        try await agent.writeStderrLine("booting with token=\(secretToken)")

        let startDriver = Task {
            try await agent.playSteps([
                .expectClientRequest(method: "initialize"),
                .agentSend(
                    .object([
                        "jsonrpc": .string("2.0"),
                        "id": .string("$id"),
                        "result": .object(["protocolVersion": .int(1)]),
                    ])
                ),
                .expectClientRequest(method: "session/new"),
                .agentSend(
                    .object([
                        "jsonrpc": .string("2.0"),
                        "id": .string("$id"),
                        "result": .object(["sessionId": .string("sess-crash")]),
                    ])
                ),
            ])
        }

        let sessionID = try await withACPTestTimeout(seconds: 3.0) {
            try await connection.start(AgentSessionRequest(workingDirectory: "/workspace"))
        }
        XCTAssertEqual(sessionID, "sess-crash")
        try await withACPTestTimeout(seconds: 3.0) { try await startDriver.value }

        let promptTask = Task {
            try await connection.prompt([.text("Trigger crash")])
        }
        _ = try await agent.clientMessage(at: 2)

        // Send a pending permission request, write another secret stderr line, then crash the agent!
        try await agent.sendToClient(
            .object([
                "jsonrpc": .string("2.0"),
                "id": .string("perm-before-crash"),
                "method": .string("session/request_permission"),
                "params": .object([
                    "sessionId": .string("sess-crash"),
                    "toolCall": .object([
                        "toolCallId": .string("tc-1"),
                        "title": .string("Bash"),
                        "kind": .string("execute"),
                    ]),
                    "options": .array([
                        .object(["optionId": .string("allow"), "name": .string("Allow"), "kind": .string("allow_once")]),
                    ]),
                ]),
            ])
        )
        let approvalEvent = try await reader.next(timeout: 3.0)
        guard case .approval(let pendingApproval) = approvalEvent else {
            XCTFail("Expected pending .approval before crash")
            return
        }

        try await agent.writeStderrLine("fatal auth error for \(secretToken)")
        try await Task.sleep(nanoseconds: 25_000_000)
        await agent.simulateExit(AgentProcessExit(exitCode: 137, signal: nil))

        let reason = try await withACPTestTimeout(seconds: 3.0) { try await promptTask.value }
        XCTAssertEqual(reason, .error)

        let rest = try await reader.collectAllUntilEnd(timeout: 3.0)
        XCTAssertEqual(rest.count, 2)
        guard case .connectionFailed(let failure) = rest[0] else {
            XCTFail("Expected .connectionFailed first, got \(rest)")
            return
        }
        XCTAssertEqual(failure.kind, .exited)
        XCTAssertFalse(failure.detail?.contains(secretToken) ?? false)
        XCTAssertTrue(failure.detail?.contains("***") ?? false)

        guard case .finished(let status, _, let errMsg, let convID, _) = rest[1] else {
            XCTFail("Expected .finished(status: error) second, got \(rest)")
            return
        }
        XCTAssertEqual(status, "error")
        XCTAssertEqual(convID, "sess-crash")
        XCTAssertNotNil(errMsg)

        // Pending approval was cancelled on crash, so answering it afterwards throws unknownInteractionRequest.
        do {
            try await connection.answer(pendingApproval.requestID!, .option("allow"))
            XCTFail("Pending approval should have been cancelled and removed on crash")
        } catch let error as ACPConnectionError {
            XCTAssertEqual(error, .unknownInteractionRequest(pendingApproval.requestID!))
        }

        // Verify `--state-dir` override log file has redacted lines and zero raw secrets!
        let logFile = customStateDir.appendingPathComponent("logs/chat-sess-crash.log")
        let logContents = try String(contentsOf: logFile, encoding: .utf8)
        XCTAssertFalse(logContents.contains(secretToken), "Raw secret must never be written to disk")
        XCTAssertTrue(logContents.contains("booting with token=***"))
        XCTAssertTrue(logContents.contains("fatal auth error for ***"))
    }

    func testSetConfigOptionSendsSetConfigOptionOrFallsBackToSetModeForModeOnly() async throws {
        // Case A: Agent advertises `configOptions` -> `session/set_config_option`.
        let agentWithOptions = ScriptedACPAgent()
        let connWithOptions = ACPConnection(
            launchSpec: Self.defaultSpec,
            policy: .none,
            processFactory: agentWithOptions.makeProcessFactory()
        )
        let driverA = Task {
            try await agentWithOptions.playSteps([
                .expectClientRequest(method: "initialize"),
                .agentSend(
                    .object([
                        "jsonrpc": .string("2.0"),
                        "id": .string("$id"),
                        "result": .object(["protocolVersion": .int(1)]),
                    ])
                ),
                .expectClientRequest(method: "session/new"),
                .agentSend(
                    .object([
                        "jsonrpc": .string("2.0"),
                        "id": .string("$id"),
                        "result": .object([
                            "sessionId": .string("s-cfg"),
                            "configOptions": .array([
                                .object([
                                    "id": .string("model"),
                                    "name": .string("Model"),
                                    "category": .string("model"),
                                    "type": .string("select"),
                                    "currentValue": .string("sonnet"),
                                    "options": .array([
                                        .object(["value": .string("sonnet"), "name": .string("Sonnet")]),
                                        .object(["value": .string("opus"), "name": .string("Opus")]),
                                    ]),
                                ]),
                            ]),
                        ]),
                    ])
                ),
                .expectClientRequest(method: "session/set_config_option"),
                .agentSend(
                    .object([
                        "jsonrpc": .string("2.0"),
                        "id": .string("$id"),
                        "result": .object([
                            "configOptions": .array([
                                .object([
                                    "id": .string("model"),
                                    "name": .string("Model"),
                                    "category": .string("model"),
                                    "type": .string("select"),
                                    "currentValue": .string("opus"),
                                    "options": .array([
                                        .object(["value": .string("sonnet"), "name": .string("Sonnet")]),
                                        .object(["value": .string("opus"), "name": .string("Opus")]),
                                    ]),
                                ]),
                            ]),
                        ]),
                    ])
                ),
            ])
        }
        _ = try await withACPTestTimeout(seconds: 3.0) {
            try await connWithOptions.start(AgentSessionRequest(workingDirectory: "/workspace"))
        }
        let updatedA = try await withACPTestTimeout(seconds: 3.0) {
            try await connWithOptions.setConfigOption("model", .string("opus"))
        }
        try await withACPTestTimeout(seconds: 3.0) { try await driverA.value }
        XCTAssertEqual(updatedA, [AgentConfigOption(id: "model", name: "Model", value: .string("opus"), options: ["sonnet", "opus"])])
        await connWithOptions.stop()

        // Case B: Legacy agent without `configOptions` -> `session/set_mode` only for mode.
        let legacyAgent = ScriptedACPAgent()
        let legacyConn = ACPConnection(
            launchSpec: Self.defaultSpec,
            policy: .none,
            processFactory: legacyAgent.makeProcessFactory()
        )
        let driverB = Task {
            try await legacyAgent.playSteps([
                .expectClientRequest(method: "initialize"),
                .agentSend(
                    .object([
                        "jsonrpc": .string("2.0"),
                        "id": .string("$id"),
                        "result": .object(["protocolVersion": .int(1)]),
                    ])
                ),
                .expectClientRequest(method: "session/new"),
                .agentSend(
                    .object([
                        "jsonrpc": .string("2.0"),
                        "id": .string("$id"),
                        "result": .object([
                            "sessionId": .string("s-mode"),
                            "modes": .object([
                                "currentModeId": .string("code"),
                                "availableModes": .array([
                                    .object(["id": .string("code"), "name": .string("Code")]),
                                    .object(["id": .string("plan"), "name": .string("Plan")]),
                                ]),
                            ]),
                        ]),
                    ])
                ),
                .expectClientRequest(method: "session/set_mode"),
                .agentSend(
                    .object([
                        "jsonrpc": .string("2.0"),
                        "id": .string("$id"),
                        "result": .object([:]),
                    ])
                ),
            ])
        }
        _ = try await withACPTestTimeout(seconds: 3.0) {
            try await legacyConn.start(AgentSessionRequest(workingDirectory: "/workspace"))
        }
        let updatedB = try await withACPTestTimeout(seconds: 3.0) {
            try await legacyConn.setConfigOption(ACPSessionConfigState.sessionModeOptionID, .string("plan"))
        }
        try await withACPTestTimeout(seconds: 3.0) { try await driverB.value }
        XCTAssertEqual(
            updatedB,
            [AgentConfigOption(id: ACPSessionConfigState.sessionModeOptionID, name: "Mode", value: .string("plan"), options: ["code", "plan"])]
        )
        await legacyConn.stop()
    }

    func testQuickPromptSessionIgnoresNewEventsAsNoOpsAndEndsTurnOnConnectionFailed() async throws {
        let agent = ScriptedACPAgent()
        let acpConnection = ACPConnection(
            launchSpec: Self.defaultSpec,
            policy: .none,
            processFactory: agent.makeProcessFactory()
        )
        let rig = ComposerRig()
        var environment = rig.environment
        environment.makeConnection = { _ in acpConnection }

        let session = VitruvianCodeQuickPromptSession(environment: environment, host: rig.host)
        session.takeCheckpoint = { _ in nil }
        var notices: [VitruvianCodeTurnNotice] = []
        session.onTurnFinished = { notices.append($0) }

        session.send(
            "check",
            configuration: VitruvianCodeConfiguration(approvalMode: .yolo, activeProvider: .claude),
            agentPath: "/fake/acp"
        )

        // Drive `initialize`, `session/new`, `session/prompt`, emit no-op updates, then simulate unexpected exit.
        try await agent.playSteps([
            .expectClientRequest(method: "initialize"),
            .agentSend(
                .object([
                    "jsonrpc": .string("2.0"),
                    "id": .string("$id"),
                    "result": .object(["protocolVersion": .int(1)]),
                ])
            ),
            .expectClientRequest(method: "session/new"),
            .agentSend(
                .object([
                    "jsonrpc": .string("2.0"),
                    "id": .string("$id"),
                    "result": .object(["sessionId": .string("sess-ui")]),
                ])
            ),
            .expectClientRequest(method: "session/prompt"),
            .agentSend(
                .object([
                    "jsonrpc": .string("2.0"),
                    "method": .string("session/update"),
                    "params": .object([
                        "sessionId": .string("sess-ui"),
                        "update": .object([
                            "sessionUpdate": .string("plan"),
                            "entries": .array([.object(["content": .string("Step 1"), "status": .string("in_progress")])]),
                        ]),
                    ]),
                ])
            ),
            .agentSend(
                .object([
                    "jsonrpc": .string("2.0"),
                    "method": .string("session/update"),
                    "params": .object([
                        "sessionId": .string("sess-ui"),
                        "update": .object([
                            "sessionUpdate": .string("session_info_update"),
                            "title": .string("Session Title"),
                        ]),
                    ]),
                ])
            ),
        ])

        await agent.simulateExit(AgentProcessExit(exitCode: 2, signal: nil))

        try await withACPTestTimeout(seconds: 3.0, description: "QuickPromptSession turn finish") {
            while await MainActor.run(body: { session.isRunning }) {
                try await Task.sleep(nanoseconds: 10_000_000)
            }
        }

        XCTAssertFalse(session.isRunning)
        XCTAssertEqual(notices.last?.failed, true)
        let errorBubbles = session.messages.filter { $0.isError && $0.text.contains("Agent process exited unexpectedly") }
        XCTAssertEqual(errorBubbles.count, 1, ".connectionFailed followed by .finished(error) must produce exactly one error message")
    }

    func testPermissionDenySelectsRejectOnceElseRejectAlwaysElseCancelledWithoutShowingCard() async throws {
        let agent = ScriptedACPAgent()
        let connection = ACPConnection(
            launchSpec: Self.defaultSpec,
            policy: ACPClientPolicy(sandbox: .readOnly),
            modeProvider: { (.acceptEdits, false) },
            processFactory: agent.makeProcessFactory()
        )
        let reader = ACPEventStreamReader(connection.events)

        let startDriver = Task {
            try await agent.playSteps([
                .expectClientRequest(method: "initialize"),
                .agentSend(
                    .object([
                        "jsonrpc": .string("2.0"),
                        "id": .string("$id"),
                        "result": .object(["protocolVersion": .int(1)]),
                    ])
                ),
                .expectClientRequest(method: "session/new"),
                .agentSend(
                    .object([
                        "jsonrpc": .string("2.0"),
                        "id": .string("$id"),
                        "result": .object(["sessionId": .string("sess-deny")]),
                    ])
                ),
            ])
        }
        _ = try await connection.start(AgentSessionRequest(workingDirectory: "/workspace"))
        try await startDriver.value

        let promptTask = Task {
            try await connection.prompt([.text("Run blocked mutations")])
        }
        let promptReq = try await agent.clientMessage(at: 2)
        let promptID = promptReq.objectValue?["id"] ?? .int(3)

        // 1. Offers `reject_always` + `reject_once`: must pick `reject_once`.
        try await agent.sendToClient(
            .object([
                "jsonrpc": .string("2.0"),
                "id": .string("perm-deny-1"),
                "method": .string("session/request_permission"),
                "params": .object([
                    "sessionId": .string("sess-deny"),
                    "toolCall": .object([
                        "toolCallId": .string("tc-d1"),
                        "title": .string("Run"),
                        "kind": .string("execute"),
                    ]),
                    "options": .array([
                        .object(["optionId": .string("allow-1"), "name": .string("Allow"), "kind": .string("allow_once")]),
                        .object(["optionId": .string("rej-always"), "name": .string("Reject Always"), "kind": .string("reject_always")]),
                        .object(["optionId": .string("rej-once"), "name": .string("Reject Once"), "kind": .string("reject_once")]),
                    ]),
                ]),
            ])
        )
        let reply1 = try await agent.clientMessage(at: 3)
        XCTAssertEqual(
            reply1.objectValue?["result"]?.objectValue?["outcome"],
            .object(["outcome": .string("selected"), "optionId": .string("rej-once")])
        )

        // 2. Offers only `allow_once` + `reject_always`: must fall back to `reject_always`.
        try await agent.sendToClient(
            .object([
                "jsonrpc": .string("2.0"),
                "id": .string("perm-deny-2"),
                "method": .string("session/request_permission"),
                "params": .object([
                    "sessionId": .string("sess-deny"),
                    "toolCall": .object([
                        "toolCallId": .string("tc-d2"),
                        "title": .string("Run"),
                        "kind": .string("execute"),
                    ]),
                    "options": .array([
                        .object(["optionId": .string("allow-1"), "name": .string("Allow"), "kind": .string("allow_once")]),
                        .object(["optionId": .string("rej-always"), "name": .string("Reject Always"), "kind": .string("reject_always")]),
                    ]),
                ]),
            ])
        )
        let reply2 = try await agent.clientMessage(at: 4)
        XCTAssertEqual(
            reply2.objectValue?["result"]?.objectValue?["outcome"],
            .object(["outcome": .string("selected"), "optionId": .string("rej-always")])
        )

        // 3. Offers no reject option at all: must fall back to `{"outcome": "cancelled"}`.
        try await agent.sendToClient(
            .object([
                "jsonrpc": .string("2.0"),
                "id": .string("perm-deny-3"),
                "method": .string("session/request_permission"),
                "params": .object([
                    "sessionId": .string("sess-deny"),
                    "toolCall": .object([
                        "toolCallId": .string("tc-d3"),
                        "title": .string("Run"),
                        "kind": .string("execute"),
                    ]),
                    "options": .array([
                        .object(["optionId": .string("allow-1"), "name": .string("Allow"), "kind": .string("allow_once")]),
                    ]),
                ]),
            ])
        )
        let reply3 = try await agent.clientMessage(at: 5)
        XCTAssertEqual(
            reply3.objectValue?["result"]?.objectValue?["outcome"],
            .object(["outcome": .string("cancelled")])
        )

        try await agent.sendToClient(
            .object([
                "jsonrpc": .string("2.0"),
                "id": promptID,
                "result": .object(["stopReason": .string("end_turn")]),
            ])
        )
        let reason = try await promptTask.value
        XCTAssertEqual(reason, .endTurn)

        let turnEvents = try await reader.collectUntilFinished(timeout: 3.0)
        XCTAssertFalse(
            turnEvents.contains { if case .approval = $0 { return true }; return false },
            "Denied permissions must never emit an approval card"
        )
        await connection.stop()
    }

    func testStartupFailureProducesSingleOriginalErrorAndBufferedLogsFlushOnSessionStopAndFailure() async throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("acp-startup-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        // A. Direct `ACPConnection.start` RPC failure + QuickPromptSession startup failure:
        //    must emit ONE error and preserve `failure.message` verbatim, while flushing early buffered logs!
        let stateFail = tempRoot.appendingPathComponent("state-fail", isDirectory: true)
        let failingAgent = ScriptedACPAgent()
        let originalErrorText = "Authentication rejected: token expired for workspace alpha"
        let failingConn = ACPConnection(
            launchSpec: Self.defaultSpec,
            policy: .none,
            stateFolderURL: stateFail,
            processFactory: failingAgent.makeProcessFactory()
        )
        try await failingAgent.writeStderrLine("early-boot-before-failure")

        let rig = ComposerRig()
        var environment = rig.environment
        environment.makeConnection = { _ in failingConn }
        let session = VitruvianCodeQuickPromptSession(environment: environment, host: rig.host)
        session.takeCheckpoint = { _ in nil }
        var notices: [VitruvianCodeTurnNotice] = []
        session.onTurnFinished = { notices.append($0) }

        session.send(
            "hello",
            configuration: VitruvianCodeConfiguration(approvalMode: .yolo, activeProvider: .claude),
            agentPath: "/fake/acp"
        )

        let initReq = try await failingAgent.clientMessage(at: 0)
        let initID = initReq.objectValue?["id"] ?? .int(1)
        try await failingAgent.sendToClient(
            .object([
                "jsonrpc": .string("2.0"),
                "id": initID,
                "error": .object([
                    "code": .int(-32001),
                    "message": .string(originalErrorText),
                ]),
            ])
        )

        try await withACPTestTimeout(seconds: 3.0, description: "QuickPromptSession startup failure") {
            while await MainActor.run(body: { session.isRunning }) {
                try await Task.sleep(nanoseconds: 10_000_000)
            }
        }

        let errorMessages = session.messages.filter(\.isError)
        XCTAssertEqual(errorMessages.count, 1, "Startup failure must produce exactly one error bubble")
        XCTAssertEqual(errorMessages.first?.text, originalErrorText, "failure.message must keep its original text")
        XCTAssertEqual(notices.count, 1)
        XCTAssertEqual(notices.first?.failed, true)
        XCTAssertEqual(notices.first?.failureDetail, originalErrorText)

        let failLogPath = VitruvianCodeSupport.statePaths(
            home: stateFail.path,
            defaultStateDirectory: stateFail.path
        ).chatLogPath(sessionID: "unknown")
        let failLogText = try String(contentsOfFile: failLogPath, encoding: .utf8)
        XCTAssertTrue(failLogText.contains("early-boot-before-failure"), "Buffered logs must flush on startup failure")

        // B. Buffered log lines flush immediately once `sessionID` is established (before `prompt` or `stop`).
        let stateKnown = tempRoot.appendingPathComponent("state-known", isDirectory: true)
        let knownAgent = ScriptedACPAgent()
        let knownConn = ACPConnection(
            launchSpec: Self.defaultSpec,
            policy: .none,
            stateFolderURL: stateKnown,
            processFactory: knownAgent.makeProcessFactory()
        )
        try await knownAgent.writeStderrLine("buffered-before-session-id")
        let startDriver = Task {
            try await knownAgent.playSteps([
                .expectClientRequest(method: "initialize"),
                .agentSend(
                    .object([
                        "jsonrpc": .string("2.0"),
                        "id": .string("$id"),
                        "result": .object(["protocolVersion": .int(1)]),
                    ])
                ),
                .expectClientRequest(method: "session/new"),
                .agentSend(
                    .object([
                        "jsonrpc": .string("2.0"),
                        "id": .string("$id"),
                        "result": .object(["sessionId": .string("sess-flushed")]),
                    ])
                ),
            ])
        }
        let startedID = try await knownConn.start(AgentSessionRequest(workingDirectory: "/workspace"))
        try await startDriver.value
        XCTAssertEqual(startedID, "sess-flushed")

        let knownLogPath = VitruvianCodeSupport.statePaths(
            home: stateKnown.path,
            defaultStateDirectory: stateKnown.path
        ).chatLogPath(sessionID: "sess-flushed")
        let knownLogBeforeStop = try String(contentsOfFile: knownLogPath, encoding: .utf8)
        XCTAssertTrue(knownLogBeforeStop.contains("buffered-before-session-id"))
        await knownConn.stop()

        // C. Buffered log lines flush on `stop()` even when stopped before `sessionID` is known.
        let stateStopped = tempRoot.appendingPathComponent("state-stopped", isDirectory: true)
        let stoppedAgent = ScriptedACPAgent()
        let stoppedConn = ACPConnection(
            launchSpec: Self.defaultSpec,
            policy: .none,
            stateFolderURL: stateStopped,
            processFactory: stoppedAgent.makeProcessFactory()
        )
        let pendingStart = Task {
            try await stoppedConn.start(AgentSessionRequest(workingDirectory: "/workspace"))
        }
        _ = try await stoppedAgent.clientMessage(at: 0)
        try await stoppedAgent.writeStderrLine("buffered-before-manual-stop")
        try await Task.sleep(nanoseconds: 25_000_000)
        await stoppedConn.stop()
        _ = try? await pendingStart.value

        let stoppedLogPath = VitruvianCodeSupport.statePaths(
            home: stateStopped.path,
            defaultStateDirectory: stateStopped.path
        ).chatLogPath(sessionID: "unknown")
        let stoppedLogText = try String(contentsOfFile: stoppedLogPath, encoding: .utf8)
        XCTAssertTrue(stoppedLogText.contains("buffered-before-manual-stop"), "Buffered logs must flush on stop()")
    }

    func testToolCallEmbeddedTerminalContentMapsIntoToolStepOutput() async throws {
        let tempWorkdir = FileManager.default.temporaryDirectory
            .appendingPathComponent("acp-term-tool-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempWorkdir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempWorkdir) }

        let agent = ScriptedACPAgent()
        let connection = ACPConnection(
            launchSpec: Self.defaultSpec,
            policy: ACPClientPolicy(terminal: true),
            processFactory: agent.makeProcessFactory()
        )
        let reader = ACPEventStreamReader(connection.events)

        let startDriver = Task {
            try await agent.playSteps([
                .expectClientRequest(method: "initialize"),
                .agentSend(
                    .object([
                        "jsonrpc": .string("2.0"),
                        "id": .string("$id"),
                        "result": .object(["protocolVersion": .int(1)]),
                    ])
                ),
                .expectClientRequest(method: "session/new"),
                .agentSend(
                    .object([
                        "jsonrpc": .string("2.0"),
                        "id": .string("$id"),
                        "result": .object(["sessionId": .string("sess-term")]),
                    ])
                ),
            ])
        }
        _ = try await connection.start(AgentSessionRequest(workingDirectory: tempWorkdir.path))
        try await startDriver.value

        let promptTask = Task {
            try await connection.prompt([.text("Run command with embedded terminal")])
        }
        let promptReq = try await agent.clientMessage(at: 2)
        let promptID = promptReq.objectValue?["id"] ?? .int(3)

        // Agent creates a client terminal, waits for exit, and releases it before emitting tool_call completion.
        try await agent.sendToClient(
            .object([
                "jsonrpc": .string("2.0"),
                "id": .string("req-term-create"),
                "method": .string("terminal/create"),
                "params": .object([
                    "sessionId": .string("sess-term"),
                    "command": .string("printf 'embedded-terminal-hello'"),
                ]),
            ])
        )
        let createReply = try await agent.clientMessage(at: 3)
        let terminalId = createReply.objectValue?["result"]?.objectValue?["terminalId"]?.stringValue ?? ""
        XCTAssertFalse(terminalId.isEmpty)

        try await agent.sendToClient(
            .object([
                "jsonrpc": .string("2.0"),
                "id": .string("req-term-wait"),
                "method": .string("terminal/wait_for_exit"),
                "params": .object([
                    "sessionId": .string("sess-term"),
                    "terminalId": .string(terminalId),
                ]),
            ])
        )
        _ = try await agent.clientMessage(at: 4)

        try await agent.sendToClient(
            .object([
                "jsonrpc": .string("2.0"),
                "id": .string("req-term-release"),
                "method": .string("terminal/release"),
                "params": .object([
                    "sessionId": .string("sess-term"),
                    "terminalId": .string(terminalId),
                ]),
            ])
        )
        _ = try await agent.clientMessage(at: 5)

        // 1. Completed tool_call referencing the retained `terminalId` maps its output into the tool step!
        try await agent.sendToClient(
            .object([
                "jsonrpc": .string("2.0"),
                "method": .string("session/update"),
                "params": .object([
                    "sessionId": .string("sess-term"),
                    "update": .object([
                        "sessionUpdate": .string("tool_call"),
                        "toolCallId": .string("tc-term-known"),
                        "title": .string("Run printf"),
                        "kind": .string("execute"),
                        "status": .string("completed"),
                        "content": .array([
                            .object([
                                "type": .string("terminal"),
                                "terminalId": .string(terminalId),
                            ]),
                        ]),
                    ]),
                ]),
            ])
        )

        // 2. Unknown terminal ID falls back to `[terminal <id>]` (`clientTerminals.ts:427`).
        try await agent.sendToClient(
            .object([
                "jsonrpc": .string("2.0"),
                "method": .string("session/update"),
                "params": .object([
                    "sessionId": .string("sess-term"),
                    "update": .object([
                        "sessionUpdate": .string("tool_call"),
                        "toolCallId": .string("tc-term-unknown"),
                        "title": .string("Remote terminal"),
                        "kind": .string("execute"),
                        "status": .string("completed"),
                        "content": .array([
                            .object([
                                "type": .string("terminal"),
                                "terminalId": .string("ext-99"),
                            ]),
                        ]),
                    ]),
                ]),
            ])
        )

        try await agent.sendToClient(
            .object([
                "jsonrpc": .string("2.0"),
                "id": promptID,
                "result": .object(["stopReason": .string("end_turn")]),
            ])
        )

        let stopReason = try await promptTask.value
        XCTAssertEqual(stopReason, .endTurn)
        let events = try await reader.collectUntilFinished(timeout: 3.0)

        XCTAssertTrue(
            events.contains(.toolStepResult(id: "tc-term-known", output: "embedded-terminal-hello", isError: false)),
            "Expected retained terminal output in .toolStepResult, got \(events)"
        )
        XCTAssertTrue(
            events.contains(.toolStepResult(id: "tc-term-unknown", output: "[terminal ext-99]", isError: false)),
            "Expected fallback [terminal ext-99] in .toolStepResult, got \(events)"
        )
        await connection.stop()
    }
}
