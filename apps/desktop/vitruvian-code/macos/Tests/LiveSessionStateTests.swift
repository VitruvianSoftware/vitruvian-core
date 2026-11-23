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
final class LiveSessionStateTests: XCTestCase {
    private var scratchSuites: [(defaults: UserDefaults, name: String)] = []

    override func tearDown() async throws {
        for suite in scratchSuites {
            suite.defaults.removePersistentDomain(forName: suite.name)
        }
        scratchSuites.removeAll()
    }

    private static var agyACPProvider: VitruvianCodeCLIProvider {
        var provider = VitruvianCodeCLIProvider.antigravity
        provider.connection = .acp
        return provider
    }

    private static var claudeSDKProvider: VitruvianCodeCLIProvider {
        var provider = VitruvianCodeCLIProvider.claude
        provider.connection = .claudeSDK
        return provider
    }

    // MARK: - 1. Approval Downgrade

    func testApprovalDowngradeSyncsClaudeSDKModeBeforePrompt() async throws {
        let agent = ScriptedACPAgent()
        let createdSpecs = LiveStateLockedBox<[AgentConnectionSpec]>([])
        let env = makeSessionEnvironment(makeConnection: { spec in
            createdSpecs.withValue { $0.append(spec) }
            let bundled = BundledNode(
                nodeURL: URL(fileURLWithPath: "/usr/bin/true"),
                helperURL: URL(fileURLWithPath: "/usr/bin/true")
            )
            return ClaudeSDKConnection(
                spec: spec,
                environment: VitruvianCodeEngine.Environment.live,
                bundledNode: { bundled },
                versionProbe: { "2.1.400" },
                processFactory: agent.makeProcessFactory()
            )
        })

        let session = VitruvianCodeQuickPromptSession(environment: env, host: LiveStateMockHost())
        session.takeCheckpoint = { _ in nil }
        let yoloConfig = VitruvianCodeConfiguration(
            workingDirectory: "/tmp",
            approvalMode: .yolo,
            activeProvider: Self.claudeSDKProvider
        )

        let driver = Task {
            try await agent.playSteps([
                .expectClientRequest(method: "initialize"),
                .agentSend(.object([
                    "jsonrpc": .string("2.0"),
                    "id": .string("$id"),
                    "result": .object(["protocolVersion": .int(1)]),
                ])),
                .expectClientRequest(method: "session/new"),
                .agentSend(.object([
                    "jsonrpc": .string("2.0"),
                    "id": .string("$id"),
                    "result": .object([
                        "sessionId": .string("claude-sess-1"),
                        "modes": .object([
                            "currentModeId": .string("bypassPermissions"),
                            "availableModes": .array([
                                .object(["id": .string("default"), "name": .string("Default")]),
                                .object(["id": .string("acceptEdits"), "name": .string("Accept Edits")]),
                                .object(["id": .string("plan"), "name": .string("Plan")]),
                                .object(["id": .string("bypassPermissions"), "name": .string("Bypass")]),
                            ]),
                        ]),
                        "configOptions": .array([
                            .object([
                                "id": .string("mode"),
                                "name": .string("Mode"),
                                "category": .string("mode"),
                                "type": .string("select"),
                                "currentValue": .string("bypassPermissions"),
                                "options": .array([
                                    .object(["value": .string("default"), "name": .string("Default")]),
                                    .object(["value": .string("acceptEdits"), "name": .string("Accept Edits")]),
                                    .object(["value": .string("plan"), "name": .string("Plan")]),
                                    .object(["value": .string("bypassPermissions"), "name": .string("Bypass")]),
                                ]),
                            ]),
                        ]),
                    ]),
                ])),
                .expectClientRequest(method: "session/prompt"),
                .agentSend(.object([
                    "jsonrpc": .string("2.0"),
                    "id": .string("$id"),
                    "result": .object(["stopReason": .string("end_turn")]),
                ])),
                // Turn 2: downgraded from Bypass (.yolo) to Ask (.standard) -> must sync mode BEFORE prompt.
                .expectClientRequest(method: "session/set_config_option"),
                .agentSend(.object([
                    "jsonrpc": .string("2.0"),
                    "id": .string("$id"),
                    "result": .object([
                        "configOptions": .array([
                            .object([
                                "id": .string("mode"),
                                "name": .string("Mode"),
                                "category": .string("mode"),
                                "type": .string("select"),
                                "currentValue": .string("default"),
                                "options": .array([
                                    .object(["value": .string("default"), "name": .string("Default")]),
                                    .object(["value": .string("acceptEdits"), "name": .string("Accept Edits")]),
                                    .object(["value": .string("plan"), "name": .string("Plan")]),
                                    .object(["value": .string("bypassPermissions"), "name": .string("Bypass")]),
                                ]),
                            ]),
                        ]),
                    ]),
                ])),
                .expectClientRequest(method: "session/prompt"),
                .agentSend(.object([
                    "jsonrpc": .string("2.0"),
                    "id": .string("$id"),
                    "result": .object(["stopReason": .string("end_turn")]),
                ])),
            ], timeout: 5.0)
        }

        session.send("Turn 1 in bypass", configuration: yoloConfig, agentPath: "/usr/bin/true")
        try await waitUntil("turn 1 finishes") { !session.isRunning }

        // Downgrade Bypass -> Ask (standard) on the live chat without toggling plan mode.
        session.chatApprovalMode = .standard
        session.send("Turn 2 in ask", configuration: yoloConfig, agentPath: "/usr/bin/true")
        try await waitUntil("turn 2 finishes") { !session.isRunning }

        try await withACPTestTimeout(seconds: 5.0) { try await driver.value }
        let clientMessages = await agent.allClientMessages()
        let methods = clientMessages.compactMap { $0.objectValue?["method"]?.stringValue }
        XCTAssertEqual(
            methods,
            ["initialize", "session/new", "session/prompt", "session/set_config_option", "session/prompt"]
        )
        let modeSyncParams = clientMessages[3].objectValue?["params"]?.objectValue
        XCTAssertEqual(modeSyncParams?["configId"]?.stringValue, "mode")
        XCTAssertEqual(modeSyncParams?["value"]?.stringValue, "default")
        XCTAssertEqual(createdSpecs.value.count, 1, "live connection must be reused")
        XCTAssertEqual(createdSpecs.value.first?.liveModeProvider?().mode, .standard)
        await session.stopAll()
    }

    func testApprovalDowngradeUpdatesAgyLiveModeProviderAndSyncsPlanToAsk() async throws {
        let agent = ScriptedACPAgent()
        let createdSpecs = LiveStateLockedBox<[AgentConnectionSpec]>([])
        let env = makeSessionEnvironment(makeConnection: { spec in
            createdSpecs.withValue { $0.append(spec) }
            return AntigravityACPConnection(
                launchSpec: AgentProcessLaunchSpec(
                    executable: "/fake/agy",
                    arguments: ["acp"],
                    environment: spec.environment,
                    workingDirectory: spec.workingDirectory
                ),
                modeProvider: spec.liveModeProvider ?? { (.standard, false) },
                runtimeVersion: "1.5.10",
                processFactory: agent.makeProcessFactory()
            )
        })

        let session = VitruvianCodeQuickPromptSession(environment: env, host: LiveStateMockHost())
        session.takeCheckpoint = { _ in nil }
        let yoloConfig = VitruvianCodeConfiguration(
            workingDirectory: "/tmp",
            approvalMode: .yolo,
            activeProvider: Self.agyACPProvider
        )
        let askConfig = VitruvianCodeConfiguration(
            workingDirectory: "/tmp",
            approvalMode: .standard,
            activeProvider: Self.agyACPProvider
        )

        let driver = Task {
            try await agent.playSteps([
                .expectClientRequest(method: "initialize"),
                .agentSend(.object([
                    "jsonrpc": .string("2.0"),
                    "id": .string("$id"),
                    "result": .object([
                        "protocolVersion": .int(1),
                        "agentInfo": .object(["name": .string("Antigravity ACP Server"), "version": .string("1.5.10")]),
                    ]),
                ])),
                .expectClientRequest(method: "session/new"),
                .agentSend(.object([
                    "jsonrpc": .string("2.0"),
                    "id": .string("$id"),
                    "result": .object(["sessionId": .string("agy-sess-1")]),
                ])),
                // Turn 1: .yolo auto-allows edit permission without asking the user.
                .expectClientRequest(method: "session/prompt"),
                .agentSend(.object([
                    "jsonrpc": .string("2.0"),
                    "id": .string("perm-1"),
                    "method": .string("session/request_permission"),
                    "params": .object([
                        "sessionId": .string("agy-sess-1"),
                        "toolCall": .object([
                            "toolCallId": .string("tc-1"),
                            "title": .string("Edit a.swift"),
                            "kind": .string("edit"),
                        ]),
                        "options": .array([
                            .object(["optionId": .string("allow_once"), "name": .string("Allow"), "kind": .string("allow_once")]),
                            .object(["optionId": .string("reject_once"), "name": .string("Deny"), "kind": .string("reject_once")]),
                        ]),
                    ]),
                ])),
                .expectClientResponse(id: .string("perm-1")),
                .agentSend(.object([
                    "jsonrpc": .string("2.0"),
                    "id": .string("$id"),
                    "result": .object(["stopReason": .string("end_turn")]),
                ])),
                // Turn 2: downgraded to .standard (via configuration) -> must ASK user instead of auto-allowing.
                .expectClientRequest(method: "session/prompt"),
                .agentSend(.object([
                    "jsonrpc": .string("2.0"),
                    "id": .string("perm-2"),
                    "method": .string("session/request_permission"),
                    "params": .object([
                        "sessionId": .string("agy-sess-1"),
                        "toolCall": .object([
                            "toolCallId": .string("tc-2"),
                            "title": .string("Edit b.swift"),
                            "kind": .string("edit"),
                        ]),
                        "options": .array([
                            .object(["optionId": .string("allow_once"), "name": .string("Allow"), "kind": .string("allow_once")]),
                            .object(["optionId": .string("reject_once"), "name": .string("Deny"), "kind": .string("reject_once")]),
                        ]),
                    ]),
                ])),
            ], timeout: 5.0)
        }

        session.send("Edit 1", configuration: yoloConfig, agentPath: "/fake/agy")
        try await waitUntil("turn 1 ends") { !session.isRunning }
        XCTAssertFalse(session.messages.contains { $0.approvalRequest != nil }, "yolo must auto-approve")

        // Downgrade to .standard without setting chatApprovalMode (engine is nil) -> liveModeProvider must reflect askConfig.
        session.send("Edit 2", configuration: askConfig, agentPath: "/fake/agy")
        try await waitUntil("turn 2 shows approval card") { session.hasPendingApproval }
        XCTAssertEqual(createdSpecs.value.first?.liveModeProvider?().mode, .standard)
        let cardMsg = try XCTUnwrap(session.messages.last { $0.approvalRequest?.status == .pending })
        session.decideApproval(messageID: cardMsg.id, decision: .approved)

        let perm2Resp = try await agent.clientMessage(at: 5, timeout: 3.0)
        XCTAssertEqual(perm2Resp.objectValue?["id"]?.stringValue, "perm-2")
        let prompt2Msg = try await agent.clientMessage(at: 4, timeout: 3.0)
        try await agent.sendToClient(.object([
            "jsonrpc": .string("2.0"),
            "id": prompt2Msg.objectValue?["id"] ?? .int(4),
            "result": .object(["stopReason": .string("end_turn")]),
        ]))
        try await waitUntil("turn 2 finishes") { !session.isRunning }
        try await withACPTestTimeout(seconds: 5.0) { try await driver.value }

        // Turn 3 -> Plan on -> Turn 4 -> Plan off
        session.chatPlanMode = true
        session.send("Plan turn", configuration: askConfig, agentPath: "/fake/agy")
        let setPlanMsg = try await agent.clientMessage(at: 6, timeout: 3.0)
        XCTAssertEqual(setPlanMsg.objectValue?["method"]?.stringValue, "session/set_mode")
        XCTAssertEqual(setPlanMsg.objectValue?["params"]?.objectValue?["modeId"]?.stringValue, "plan")
        try await agent.sendToClient(.object([
            "jsonrpc": .string("2.0"),
            "id": setPlanMsg.objectValue?["id"] ?? .int(6),
            "result": .object([:]),
        ]))
        let prompt3Msg = try await agent.clientMessage(at: 7, timeout: 3.0)
        XCTAssertEqual(prompt3Msg.objectValue?["method"]?.stringValue, "session/prompt")
        try await agent.sendToClient(.object([
            "jsonrpc": .string("2.0"),
            "id": prompt3Msg.objectValue?["id"] ?? .int(7),
            "result": .object(["stopReason": .string("end_turn")]),
        ]))
        try await waitUntil("turn 3 finishes") { !session.isRunning }

        session.chatPlanMode = false
        session.send("Ask turn after plan", configuration: askConfig, agentPath: "/fake/agy")
        let setDefaultMsg = try await agent.clientMessage(at: 8, timeout: 3.0)
        XCTAssertEqual(setDefaultMsg.objectValue?["method"]?.stringValue, "session/set_mode")
        XCTAssertEqual(setDefaultMsg.objectValue?["params"]?.objectValue?["modeId"]?.stringValue, "default")
        try await agent.sendToClient(.object([
            "jsonrpc": .string("2.0"),
            "id": setDefaultMsg.objectValue?["id"] ?? .int(8),
            "result": .object([:]),
        ]))
        let prompt4Msg = try await agent.clientMessage(at: 9, timeout: 3.0)
        XCTAssertEqual(prompt4Msg.objectValue?["method"]?.stringValue, "session/prompt")
        try await agent.sendToClient(.object([
            "jsonrpc": .string("2.0"),
            "id": prompt4Msg.objectValue?["id"] ?? .int(9),
            "result": .object(["stopReason": .string("end_turn")]),
        ]))
        try await waitUntil("turn 4 finishes") { !session.isRunning }
        await session.stopAll()
    }

    func testApprovalSyncFailureFailsClosedWithoutSendingPrompt() async throws {
        let connections = LiveStateLockedBox<[LiveStateMockConnection]>([])
        var failFreshOnSecond = false
        let env = makeSessionEnvironment(makeConnection: { spec in
            let conn = LiveStateMockConnection(spec: spec)
            conn.failSyncMode = failFreshOnSecond
            failFreshOnSecond = false
            connections.withValue { $0.append(conn) }
            return conn
        })

        let session = VitruvianCodeQuickPromptSession(environment: env, host: LiveStateMockHost())
        session.takeCheckpoint = { _ in nil }
        let yoloConfig = VitruvianCodeConfiguration(approvalMode: .yolo, activeProvider: Self.agyACPProvider)

        // Turn 1 starts in .yolo and calls syncMode before prompt
        session.send("Turn 1", configuration: yoloConfig, agentPath: "/fake/agy")
        try await waitUntil("conn1 prompt 1") { connections.value.first?.promptCalls.count == 1 }
        let conn1 = connections.value[0]
        XCTAssertEqual(conn1.syncedModes.count, 1)
        XCTAssertEqual(conn1.syncedModes.first?.0, .yolo)
        XCTAssertEqual(conn1.syncedModes.first?.1, false)
        conn1.emit(.finished(status: "completed", response: "OK", error: nil, conversationID: "s-sync-fail"))
        conn1.finishPrompt(with: .endTurn)
        try await waitUntil("turn 1 done") { !session.isRunning }

        // Turn 2 (reused path) downgrades to .standard, syncMode throws -> prompt must NOT be sent, conn1 discarded & stopped
        conn1.failSyncMode = true
        session.chatApprovalMode = .standard
        session.send("Turn 2 must fail closed", configuration: yoloConfig, agentPath: "/fake/agy")
        try await waitUntil("turn 2 fails") { !session.isRunning }

        XCTAssertEqual(conn1.syncedModes.count, 2)
        XCTAssertEqual(conn1.syncedModes.last?.0, .standard)
        XCTAssertEqual(conn1.syncedModes.last?.1, false)
        XCTAssertEqual(conn1.promptCalls.count, 1, "prompt must NOT be sent when reused-connection mode sync fails")
        XCTAssertEqual(conn1.stopCount, 1)
        XCTAssertNotNil(session.lastFailedPrompt)
        XCTAssertTrue(session.messages.contains { $0.role == .agent && $0.isError })

        // Turn 3 (fresh path) syncMode throws -> prompt must NOT be sent, conn2 discarded & stopped
        failFreshOnSecond = true
        session.send("Turn 3 fresh fail closed", configuration: yoloConfig, agentPath: "/fake/agy")
        try await waitUntil("turn 3 fails") {
            connections.value.count == 2 && !session.isRunning
        }
        let conn2 = connections.value[1]
        XCTAssertEqual(conn2.syncedModes.count, 1)
        XCTAssertEqual(conn2.promptCalls.count, 0, "prompt must NOT be sent when fresh-connection mode sync fails")
        XCTAssertEqual(conn2.stopCount, 1)

        // Turn 4 starts a clean fresh connection
        session.send("Turn 4", configuration: yoloConfig, agentPath: "/fake/agy")
        try await waitUntil("conn3 starts and prompts") {
            connections.value.count == 3 && connections.value[2].promptCalls.count == 1
        }
        let conn3 = connections.value[2]
        conn3.emit(.finished(status: "completed", response: "Recovered", error: nil, conversationID: "s-sync-fail"))
        conn3.finishPrompt(with: .endTurn)
        try await waitUntil("turn 4 done") { !session.isRunning }
        await session.stopAll()
    }

    func testPermissionRaceDuringStartupSyncsBackToAskBeforePrompt() async throws {
        let agent = ScriptedACPAgent()
        let env = makeSessionEnvironment(makeConnection: { spec in
            let bundled = BundledNode(
                nodeURL: URL(fileURLWithPath: "/usr/bin/true"),
                helperURL: URL(fileURLWithPath: "/usr/bin/true")
            )
            return ClaudeSDKConnection(
                spec: spec,
                environment: VitruvianCodeEngine.Environment.live,
                bundledNode: { bundled },
                versionProbe: { "2.1.400" },
                processFactory: agent.makeProcessFactory()
            )
        })

        let session = VitruvianCodeQuickPromptSession(environment: env, host: LiveStateMockHost())
        session.takeCheckpoint = { _ in nil }
        let askConfig = VitruvianCodeConfiguration(
            workingDirectory: "/tmp",
            approvalMode: .standard,
            activeProvider: Self.claudeSDKProvider
        )

        // 1. Send Turn 1 in Ask (.standard)
        session.send("Turn 1 sent in Ask", configuration: askConfig, agentPath: "/usr/bin/true")
        let initReq = try await agent.clientMessage(at: 0, timeout: 3.0)
        XCTAssertEqual(initReq.objectValue?["method"]?.stringValue, "initialize")

        // 2. Switch to Bypass (.yolo) while startup is in flight
        session.chatApprovalMode = .yolo
        try await agent.sendToClient(.object([
            "jsonrpc": .string("2.0"),
            "id": initReq.objectValue?["id"] ?? .int(0),
            "result": .object(["protocolVersion": .int(1)]),
        ]))

        // start() applies the LIVE mode (bypassPermissions) during session/new
        let newReq = try await agent.clientMessage(at: 1, timeout: 3.0)
        XCTAssertEqual(newReq.objectValue?["method"]?.stringValue, "session/new")
        let newMetaMode = newReq.objectValue?["params"]?.objectValue?["_meta"]?.objectValue?["vitruvian"]?.objectValue?["modeId"]?.stringValue
        XCTAssertEqual(newMetaMode, "bypassPermissions")
        try await agent.sendToClient(.object([
            "jsonrpc": .string("2.0"),
            "id": newReq.objectValue?["id"] ?? .int(1),
            "result": .object([
                "sessionId": .string("claude-race-1"),
                "modes": .object([
                    "currentModeId": .string("bypassPermissions"),
                    "availableModes": .array([
                        .object(["id": .string("default"), "name": .string("Default")]),
                        .object(["id": .string("acceptEdits"), "name": .string("Accept Edits")]),
                        .object(["id": .string("plan"), "name": .string("Plan")]),
                        .object(["id": .string("bypassPermissions"), "name": .string("Bypass")]),
                    ]),
                ]),
                "configOptions": .array([
                    .object([
                        "id": .string("mode"),
                        "name": .string("Mode"),
                        "category": .string("mode"),
                        "type": .string("select"),
                        "currentValue": .string("bypassPermissions"),
                        "options": .array([
                            .object(["value": .string("default"), "name": .string("Default")]),
                            .object(["value": .string("acceptEdits"), "name": .string("Accept Edits")]),
                            .object(["value": .string("plan"), "name": .string("Plan")]),
                            .object(["value": .string("bypassPermissions"), "name": .string("Bypass")]),
                        ]),
                    ]),
                ]),
            ]),
        ]))

        // 3. Before Turn 1's prompt, syncMode MUST sync back to Ask ("default")
        let setModeReq = try await agent.clientMessage(at: 2, timeout: 3.0)
        XCTAssertEqual(setModeReq.objectValue?["method"]?.stringValue, "session/set_config_option")
        XCTAssertEqual(setModeReq.objectValue?["params"]?.objectValue?["value"]?.stringValue, "default")
        try await agent.sendToClient(.object([
            "jsonrpc": .string("2.0"),
            "id": setModeReq.objectValue?["id"] ?? .int(2),
            "result": .object([
                "configOptions": .array([
                    .object([
                        "id": .string("mode"),
                        "name": .string("Mode"),
                        "category": .string("mode"),
                        "type": .string("select"),
                        "currentValue": .string("default"),
                        "options": .array([
                            .object(["value": .string("default"), "name": .string("Default")]),
                            .object(["value": .string("acceptEdits"), "name": .string("Accept Edits")]),
                            .object(["value": .string("plan"), "name": .string("Plan")]),
                            .object(["value": .string("bypassPermissions"), "name": .string("Bypass")]),
                        ]),
                    ]),
                ]),
            ]),
        ]))

        let prompt1Req = try await agent.clientMessage(at: 3, timeout: 3.0)
        XCTAssertEqual(prompt1Req.objectValue?["method"]?.stringValue, "session/prompt")
        try await agent.sendToClient(.object([
            "jsonrpc": .string("2.0"),
            "id": prompt1Req.objectValue?["id"] ?? .int(3),
            "result": .object(["stopReason": .string("end_turn")]),
        ]))
        try await waitUntil("turn 1 finishes") { !session.isRunning }

        // 4. Switch back to Ask and send Turn 2 on the reused connection
        session.chatApprovalMode = .standard
        session.send("Turn 2 in Ask", configuration: askConfig, agentPath: "/usr/bin/true")
        let prompt2Req = try await agent.clientMessage(at: 4, timeout: 3.0)
        XCTAssertEqual(prompt2Req.objectValue?["method"]?.stringValue, "session/prompt")
        try await agent.sendToClient(.object([
            "jsonrpc": .string("2.0"),
            "id": prompt2Req.objectValue?["id"] ?? .int(4),
            "result": .object(["stopReason": .string("end_turn")]),
        ]))
        try await waitUntil("turn 2 finishes") { !session.isRunning }

        let allMessages = await agent.allClientMessages()
        let setModes = allMessages.filter { $0.objectValue?["method"]?.stringValue == "session/set_config_option" }
        XCTAssertEqual(setModes.last?.objectValue?["params"]?.objectValue?["value"]?.stringValue, "default")
        await session.stopAll()

        // Also confirm syncMode runs unconditionally on every turn (no lastSyncedMode cache)
        let mockConnections = LiveStateLockedBox<[LiveStateMockConnection]>([])
        let mockEnv = makeSessionEnvironment(makeConnection: { spec in
            let conn = LiveStateMockConnection(spec: spec)
            mockConnections.withValue { $0.append(conn) }
            return conn
        })
        let mockSession = VitruvianCodeQuickPromptSession(environment: mockEnv, host: LiveStateMockHost())
        mockSession.takeCheckpoint = { _ in nil }
        let agyAsk = VitruvianCodeConfiguration(approvalMode: .standard, activeProvider: Self.agyACPProvider)

        mockSession.send("Mock 1", configuration: agyAsk, agentPath: "/fake/agy")
        try await waitUntil("mock 1 prompts") { mockConnections.value.first?.promptCalls.count == 1 }
        let mockConn = mockConnections.value[0]
        mockConn.emit(.finished(status: "completed", response: "OK 1", error: nil, conversationID: "s-uncond"))
        mockConn.finishPrompt(with: .endTurn)
        try await waitUntil("mock 1 done") { !mockSession.isRunning }

        mockSession.send("Mock 2", configuration: agyAsk, agentPath: "/fake/agy")
        try await waitUntil("mock 2 prompts") { mockConn.promptCalls.count == 2 }
        mockConn.emit(.finished(status: "completed", response: "OK 2", error: nil, conversationID: "s-uncond"))
        mockConn.finishPrompt(with: .endTurn)
        try await waitUntil("mock 2 done") { !mockSession.isRunning }

        XCTAssertEqual(mockConn.syncedModes.count, 2)
        XCTAssertEqual(mockConn.syncedModes[0].0, .standard)
        XCTAssertEqual(mockConn.syncedModes[0].1, false)
        XCTAssertEqual(mockConn.syncedModes[1].0, .standard)
        XCTAssertEqual(mockConn.syncedModes[1].1, false)
        await mockSession.stopAll()
    }

    // MARK: - 2. Stop During Startup

    func testACPConnectionCancelDuringStartupAbortsCleanlyWithoutFailureEvent() async throws {
        let agent = ScriptedACPAgent()
        let conn = ACPConnection(
            launchSpec: AgentProcessLaunchSpec(executable: "/fake/agy", arguments: ["acp"], workingDirectory: "/tmp"),
            policy: .antigravity(version: "1.5.10"),
            processFactory: agent.makeProcessFactory()
        )
        let reader = ACPEventStreamReader(conn.events)
        let startTask = Task {
            try await conn.start(AgentSessionRequest(workingDirectory: "/tmp"))
        }

        _ = try await agent.clientMessage(at: 0, timeout: 3.0) // initialize sent, held open
        try await withACPTestTimeout(seconds: 3.0) {
            await conn.cancel()
        }

        do {
            _ = try await startTask.value
            XCTFail("start() must abort when cancelled during startup")
        } catch {
            // Expected cancellation / connectionClosed / alreadyStopped error.
        }
        let events = try await reader.collectAllUntilEnd(timeout: 3.0)
        XCTAssertFalse(
            events.contains { if case .connectionFailed = $0 { return true }; return false },
            "cancelling startup must not emit .connectionFailed: \(events)"
        )
        XCTAssertFalse(conn.isConnected)
    }

    func testStopDuringStartupNeverSendsPromptAndNextPromptWorks() async throws {
        let agents = LiveStateLockedBox<[ScriptedACPAgent]>([])
        let env = makeSessionEnvironment(makeConnection: { spec in
            let agent = ScriptedACPAgent()
            agents.withValue { $0.append(agent) }
            return AntigravityACPConnection(
                launchSpec: AgentProcessLaunchSpec(
                    executable: "/fake/agy",
                    arguments: ["acp"],
                    environment: spec.environment,
                    workingDirectory: spec.workingDirectory
                ),
                modeProvider: spec.liveModeProvider ?? { (.standard, false) },
                runtimeVersion: "1.5.10",
                processFactory: agent.makeProcessFactory()
            )
        })

        let session = VitruvianCodeQuickPromptSession(environment: env, host: LiveStateMockHost())
        session.takeCheckpoint = { _ in nil }
        let config = VitruvianCodeConfiguration(
            workingDirectory: "/tmp",
            approvalMode: .standard,
            activeProvider: Self.agyACPProvider
        )

        session.send("Startup stop test", configuration: config, agentPath: "/fake/agy")
        try await waitUntil("agent 1 created") { agents.value.count == 1 }
        let agent1 = agents.value[0]
        _ = try await agent1.clientMessage(at: 0, timeout: 3.0) // initialize in flight

        session.stop()
        try await waitUntil("turn 1 ends as stopped") { !session.isRunning }

        let msgs1 = await agent1.allClientMessages()
        let methods1 = msgs1.compactMap { $0.objectValue?["method"]?.stringValue }
        XCTAssertFalse(methods1.contains("session/prompt"), "prompt must NEVER be sent after Stop during startup")
        XCTAssertEqual(session.consecutiveRestartFailures, 0, "user Stop during startup must not count as a crash")
        XCTAssertEqual(session.messages.last?.text, VitruvianCodeHostStrings().replyStopped)
        XCTAssertEqual(session.messages.last?.isError, false)

        // Next prompt starts a fresh connection and works normally
        session.send("Second prompt", configuration: config, agentPath: "/fake/agy")
        try await waitUntil("agent 2 created") { agents.value.count == 2 }
        let agent2 = agents.value[1]
        let driver2 = Task {
            try await agent2.playSteps([
                .expectClientRequest(method: "initialize"),
                .agentSend(.object([
                    "jsonrpc": .string("2.0"),
                    "id": .string("$id"),
                    "result": .object([
                        "protocolVersion": .int(1),
                        "agentInfo": .object(["name": .string("Antigravity ACP Server"), "version": .string("1.5.10")]),
                    ]),
                ])),
                .expectClientRequest(method: "session/new"),
                .agentSend(.object([
                    "jsonrpc": .string("2.0"),
                    "id": .string("$id"),
                    "result": .object(["sessionId": .string("sess-after-stop")]),
                ])),
                .expectClientRequest(method: "session/prompt"),
                .agentSend(.object([
                    "jsonrpc": .string("2.0"),
                    "id": .string("$id"),
                    "result": .object(["stopReason": .string("end_turn")]),
                ])),
            ], timeout: 5.0)
        }
        try await withACPTestTimeout(seconds: 5.0) { try await driver2.value }
        try await waitUntil("turn 2 ends cleanly") { !session.isRunning }
        await session.stopAll()
    }

    func testStopWhileStartOrModeSyncSuspendsNeverSendsPromptAndNextPromptWorks() async throws {
        let connections = LiveStateLockedBox<[LiveStateMockConnection]>([])
        let env = makeSessionEnvironment(makeConnection: { spec in
            let conn = LiveStateMockConnection(spec: spec)
            if connections.value.isEmpty {
                conn.holdStart = true
            }
            connections.withValue { $0.append(conn) }
            return conn
        })

        let session = VitruvianCodeQuickPromptSession(environment: env, host: LiveStateMockHost())
        session.takeCheckpoint = { _ in nil }
        let config = VitruvianCodeConfiguration(approvalMode: .yolo, activeProvider: Self.agyACPProvider)

        // 1. Stop while start() is suspended, and start() later returns normally (or via cancel)
        session.send("First", configuration: config, agentPath: "/fake/agy")
        try await waitUntil("conn1 start called") { connections.value.first?.startCalls.count == 1 }
        let conn1 = connections.value[0]
        session.stop()
        try await waitUntil("cancel called during start") { conn1.cancelCount == 1 }
        conn1.releaseStart(sessionID: "sess-held-start")
        try await waitUntil("turn 1 ends stopped") { !session.isRunning }

        XCTAssertTrue(conn1.promptCalls.isEmpty, "prompt must NEVER be sent if Stop happened before start returned")
        XCTAssertEqual(session.messages.last?.text, VitruvianCodeHostStrings().replyStopped)

        // 2. Next prompt works (either reusing conn1 or starting a clean connection) and then test Stop during syncMode
        session.send("Second", configuration: config, agentPath: "/fake/agy")
        try await waitUntil("prompt 2 completes start") {
            let active = connections.value.last!
            return active.promptCalls.count == 1
        }
        let activeConn = try XCTUnwrap(connections.value.last)
        activeConn.emit(.finished(status: "completed", response: "OK 2", error: nil, conversationID: "sess-2"))
        activeConn.finishPrompt(with: .endTurn)
        try await waitUntil("turn 2 finishes") { !session.isRunning }

        // Downgrade mode so turn 3 enters syncMode, then Stop while syncMode is suspended
        activeConn.holdSyncMode = true
        session.chatApprovalMode = .standard
        session.send("Third", configuration: config, agentPath: "/fake/agy")
        try await waitUntil("syncMode entered") { activeConn.syncedModes.count == 2 }
        session.stop()
        activeConn.releaseSyncMode()
        try await waitUntil("turn 3 ends stopped") { !session.isRunning }
        XCTAssertEqual(activeConn.promptCalls.count, 1, "prompt must NEVER be sent if Stop happened during syncMode")

        // Next prompt still works
        activeConn.holdSyncMode = false
        session.send("Fourth", configuration: config, agentPath: "/fake/agy")
        try await waitUntil("turn 4 prompts") { connections.value.last?.promptCalls.count == 2 || connections.value.count > 1 }
        let fourthConn = try XCTUnwrap(connections.value.last)
        fourthConn.emit(.finished(status: "completed", response: "OK 4", error: nil, conversationID: "sess-2"))
        fourthConn.finishPrompt(with: .endTurn)
        try await waitUntil("turn 4 ends") { !session.isRunning }
        await session.stopAll()
    }

    // MARK: - 3. Worktree Isolation

    func testRunProgramCheckedReturnsNilOnNonZeroExitWhileRunProgramUnchanged() async {
        let uncheckedFail = await VitruvianCodeEngine.runProgram(named: "/usr/bin/false", arguments: [])
        XCTAssertNotNil(uncheckedFail, "existing runProgram preserves non-nil output on non-zero exit")

        let checkedFail = await VitruvianCodeEngine.runProgram(
            named: "/usr/bin/false",
            arguments: [],
            requireZeroExit: true
        )
        XCTAssertNil(checkedFail, "requireZeroExit must return nil on non-zero exit")

        let checkedOK = await VitruvianCodeEngine.runProgram(
            named: "/bin/echo",
            arguments: ["ok"],
            requireZeroExit: true
        )
        XCTAssertEqual(checkedOK, "ok\n")
    }

    func testWorktreeManagerWithStrictRunnerHandlesFailureSetupRemoveAndList() async throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("wt-strict-\(UUID().uuidString)", isDirectory: true)
        let repoDir = tempRoot.appendingPathComponent("repo", isDirectory: true)
        try FileManager.default.createDirectory(at: repoDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let initOut = await VitruvianCodeEngine.runProgram(named: "git", arguments: ["-C", repoDir.path, "init"], requireZeroExit: true)
        let emailOut = await VitruvianCodeEngine.runProgram(named: "git", arguments: ["-C", repoDir.path, "config", "user.email", "test@example.com"], requireZeroExit: true)
        let nameOut = await VitruvianCodeEngine.runProgram(named: "git", arguments: ["-C", repoDir.path, "config", "user.name", "Test"], requireZeroExit: true)
        let commitOut = await VitruvianCodeEngine.runProgram(named: "git", arguments: ["-C", repoDir.path, "commit", "--allow-empty", "-m", "init"], requireZeroExit: true)
        XCTAssertNotNil(initOut)
        XCTAssertNotNil(emailOut)
        XCTAssertNotNil(nameOut)
        XCTAssertNotNil(commitOut)

        let strictRunner: VitruvianCodeWorktreeManager.ProgramRunner = { name, args in
            await VitruvianCodeEngine.runProgram(named: name, arguments: args, requireZeroExit: true)
        }
        let manager = VitruvianCodeWorktreeManager()

        // 1. Failed `git worktree add` (bad baseRef) must produce .failed, NOT .ready
        let badRef = await manager.createWorktree(
            taskName: "bad-ref",
            baseRepositoryPath: repoDir.path,
            baseRef: "refs/heads/does-not-exist",
            worktreesRoot: tempRoot.appendingPathComponent("wts").path,
            provider: Self.agyACPProvider,
            runGit: strictRunner
        )
        if case .failed = badRef.setupStatus {
            // expected
        } else {
            XCTFail("Expected .failed on bad git worktree add, got \(badRef.setupStatus)")
        }

        // 2. Failing setup command must produce .failed and clean up automatically
        let badSetup = await manager.createWorktree(
            taskName: "bad-setup",
            baseRepositoryPath: repoDir.path,
            worktreesRoot: tempRoot.appendingPathComponent("wts").path,
            provider: Self.agyACPProvider,
            config: VitruvianCodeWorktreeConfig(setup: ["exit 1"]),
            runGit: strictRunner
        )
        XCTAssertEqual(badSetup.setupStatus, .failed("Setup command failed: exit 1"))
        let removedFailed = await manager.removeWorktree(id: badSetup.id, force: true, deleteBranch: true, runGit: strictRunner)
        XCTAssertFalse(removedFailed, "failed setup worktree must already be removed")

        // 3. Valid worktree + passing setup -> .ready, listed in porcelain, and cleanly removed
        let good = await manager.createWorktree(
            taskName: "good-wt",
            baseRepositoryPath: repoDir.path,
            worktreesRoot: tempRoot.appendingPathComponent("wts").path,
            provider: Self.agyACPProvider,
            config: VitruvianCodeWorktreeConfig(setup: ["true"]),
            runGit: strictRunner
        )
        XCTAssertEqual(good.setupStatus, .ready)
        let listed = await manager.listPorcelainWorktrees(baseRepositoryPath: repoDir.path, runGit: strictRunner)
        let canonicalGood = URL(fileURLWithPath: good.worktreePath).resolvingSymlinksInPath().path
        XCTAssertTrue(
            listed.contains { URL(fileURLWithPath: $0.worktreePath).resolvingSymlinksInPath().path == canonicalGood }
        )

        let removed = await manager.removeWorktree(id: good.id, force: true, deleteBranch: true, runGit: strictRunner)
        XCTAssertTrue(removed)
        let removedAgain = await manager.removeWorktree(id: good.id, force: true, deleteBranch: true, runGit: strictRunner)
        XCTAssertFalse(removedAgain)
    }

    func testWorktreeCreationFailureOnLiveConnectionFailsVisiblyWithoutRunningInBaseRepo() async throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("wt-fail-qps-\(UUID().uuidString)", isDirectory: true)
        let repoDir = tempRoot.appendingPathComponent("repo", isDirectory: true)
        try FileManager.default.createDirectory(at: repoDir.appendingPathComponent(".git"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let connectionAttempts = LiveStateLockedBox(0)
        let env = makeSessionEnvironment(
            makeConnection: { spec in
                connectionAttempts.withValue { $0 += 1 }
                return LiveStateMockConnection(spec: spec)
            },
            runProgram: { _, _ in "" }, // legacy runner would lie; checked runner returns nil
            runProgramChecked: { _, _ in nil }
        )

        let session = VitruvianCodeQuickPromptSession(environment: env, host: LiveStateMockHost())
        session.takeCheckpoint = { _ in nil }
        session.worktreeMode = true
        let config = VitruvianCodeConfiguration(
            workingDirectory: repoDir.path,
            approvalMode: .standard,
            activeProvider: Self.agyACPProvider
        )

        session.send("Do work in worktree", configuration: config, agentPath: "/fake/agy")
        try await waitUntil("turn fails") { !session.isRunning }

        XCTAssertEqual(connectionAttempts.value, 0, "agent must NEVER launch in base repo when worktree creation fails")
        XCTAssertNil(session.liveWorktreePath)
        XCTAssertNotNil(session.lastFailedPrompt)
        let errorMsg = try XCTUnwrap(session.messages.last { $0.role == .agent && $0.isError })
        XCTAssertTrue(errorMsg.text.contains(VitruvianCodeHostStrings().worktreeCreationFailed))
    }

    func testMidChatWorktreeToggleStartsNewConnectionInWorktreeWithFreshSession() async throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("wt-toggle-\(UUID().uuidString)", isDirectory: true)
        let repoDir = tempRoot.appendingPathComponent("repo", isDirectory: true)
        try FileManager.default.createDirectory(at: repoDir.appendingPathComponent(".git"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let expectedWorktree = tempRoot.appendingPathComponent("repo-worktrees/antigravity-cli-chat-2", isDirectory: true).path
        let connections = LiveStateLockedBox<[LiveStateMockConnection]>([])
        let env = makeSessionEnvironment(
            makeConnection: { spec in
                let conn = LiveStateMockConnection(spec: spec)
                connections.withValue { $0.append(conn) }
                return conn
            },
            runProgramChecked: { name, args in
                if name == "git", args.contains("worktree"), args.contains("add"),
                   let pathArg = args.last(where: { $0.contains("repo-worktrees") }) {
                    try? FileManager.default.createDirectory(atPath: pathArg, withIntermediateDirectories: true)
                    return ""
                }
                return nil
            }
        )

        let session = VitruvianCodeQuickPromptSession(environment: env, host: LiveStateMockHost())
        session.takeCheckpoint = { _ in nil }
        let config = VitruvianCodeConfiguration(
            workingDirectory: repoDir.path,
            approvalMode: .standard,
            activeProvider: Self.agyACPProvider
        )

        // Turn 1: worktree OFF -> runs in base repo
        session.send("Turn 1 base", configuration: config, agentPath: "/fake/agy")
        try await waitUntil("conn1 prompts") { connections.value.first?.promptCalls.count == 1 }
        let conn1 = connections.value[0]
        XCTAssertEqual(conn1.spec.workingDirectory, repoDir.path)
        conn1.emit(.started(conversationID: "base-sess-1"))
        conn1.emit(.finished(status: "completed", response: "OK 1", error: nil, conversationID: "base-sess-1"))
        conn1.finishPrompt(with: .endTurn)
        try await waitUntil("turn 1 done") { !session.isRunning }

        // Turn 2: toggle worktree ON mid-chat -> must NOT reuse conn1; retires conn1 and starts conn2 in worktree
        session.worktreeMode = true
        session.send("Turn 2 worktree", configuration: config, agentPath: "/fake/agy")
        try await waitUntil("conn2 prompts") { connections.value.count == 2 && connections.value[1].promptCalls.count == 1 }
        let conn2 = connections.value[1]
        XCTAssertEqual(conn1.promptCalls.count, 1, "conn1 must not be reused after worktree toggled on")
        try await waitUntil("conn1 stopped") { conn1.stopCount == 1 }
        XCTAssertEqual(session.liveWorktreePath, expectedWorktree)
        XCTAssertEqual(conn2.spec.workingDirectory, expectedWorktree)
        XCTAssertEqual(conn2.startCalls.first?.workingDirectory, expectedWorktree)
        XCTAssertNil(conn2.startCalls.first?.resumeSessionID, "fresh session when switching into worktree")
        conn2.emit(.started(conversationID: "wt-sess-2"))
        conn2.emit(.finished(status: "completed", response: "OK 2", error: nil, conversationID: "wt-sess-2"))
        conn2.finishPrompt(with: .endTurn)
        try await waitUntil("turn 2 done") { !session.isRunning }

        // Turn 3: toggle worktree OFF mid-chat -> retires conn2 and starts conn3 back in base repo with fresh session
        session.worktreeMode = false
        session.send("Turn 3 back to base", configuration: config, agentPath: "/fake/agy")
        try await waitUntil("conn3 prompts") { connections.value.count == 3 && connections.value[2].promptCalls.count == 1 }
        let conn3 = connections.value[2]
        try await waitUntil("conn2 stopped") { conn2.stopCount == 1 }
        XCTAssertNil(session.liveWorktreePath)
        XCTAssertEqual(conn3.spec.workingDirectory, repoDir.path)
        XCTAssertNil(conn3.startCalls.first?.resumeSessionID, "fresh session when leaving worktree")
        conn3.emit(.finished(status: "completed", response: "OK 3", error: nil, conversationID: "base-sess-3"))
        conn3.finishPrompt(with: .endTurn)
        try await waitUntil("turn 3 done") { !session.isRunning }
        await session.stopAll()
    }

    // MARK: - 4. Slash Commands Cleared

    func testSlashCommandsClearedOnNewChatResumeAndConnectionChange() async throws {
        let connections = LiveStateLockedBox<[LiveStateMockConnection]>([])
        let env = makeSessionEnvironment(makeConnection: { spec in
            let conn = LiveStateMockConnection(spec: spec)
            connections.withValue { $0.append(conn) }
            return conn
        })
        let session = VitruvianCodeQuickPromptSession(environment: env, host: LiveStateMockHost())
        session.takeCheckpoint = { _ in nil }
        let config = VitruvianCodeConfiguration(approvalMode: .standard, activeProvider: Self.agyACPProvider)

        session.send("Turn 1", configuration: config, agentPath: "/fake/agy")
        try await waitUntil("conn1 prompts") { connections.value.first?.promptCalls.count == 1 }
        let conn1 = connections.value[0]
        conn1.emit(.slashCommands(["review", "compact"]))
        try await waitUntil("slash commands set") { session.cliSlashCommands == ["review", "compact"] }
        conn1.emit(.finished(status: "completed", response: "OK", error: nil, conversationID: "s-slash-1"))
        conn1.finishPrompt(with: .endTurn)
        try await waitUntil("turn 1 done") { !session.isRunning }

        // 1. Cleared on newChat()
        session.newChat()
        XCTAssertEqual(session.cliSlashCommands, [])

        // 2. Cleared on resume(...)
        session.send("Turn 2", configuration: config, agentPath: "/fake/agy")
        try await waitUntil("conn2 prompts") { connections.value.count == 2 && connections.value[1].promptCalls.count == 1 }
        let conn2 = connections.value[1]
        conn2.emit(.slashCommands(["deploy"]))
        try await waitUntil("slash commands set 2") { session.cliSlashCommands == ["deploy"] }
        conn2.emit(.finished(status: "completed", response: "OK", error: nil, conversationID: "s-slash-2"))
        conn2.finishPrompt(with: .endTurn)
        try await waitUntil("turn 2 done") { !session.isRunning }

        session.resume(VitruvianCodeSessionSummary(id: "other", title: "Other", preview: "Hi", steps: 1, modified: nil), configuration: config)
        XCTAssertEqual(session.cliSlashCommands, [])

        // 3. Cleared when provider or connection kind changes (`clearingSlashCommands: true`)
        session.send("Turn 3", configuration: config, agentPath: "/fake/agy")
        try await waitUntil("conn3 prompts") { connections.value.count == 3 && connections.value[2].promptCalls.count == 1 }
        let conn3 = connections.value[2]
        conn3.emit(.slashCommands(["help"]))
        try await waitUntil("slash commands set 3") { session.cliSlashCommands == ["help"] }
        conn3.emit(.finished(status: "completed", response: "OK", error: nil, conversationID: "other"))
        conn3.finishPrompt(with: .endTurn)
        try await waitUntil("turn 3 done") { !session.isRunning }

        session.resetLiveConnectionState(keepingWorktree: true, clearingSlashCommands: true)
        XCTAssertEqual(session.cliSlashCommands, [])
        await session.stopAll()
    }

    func testSlashCommandsKeptOnIdleShutdownAndCrashClearedOnChatOrProviderChange() async throws {
        let connections = LiveStateLockedBox<[LiveStateMockConnection]>([])
        let env = makeSessionEnvironment(makeConnection: { spec in
            let conn = LiveStateMockConnection(spec: spec)
            connections.withValue { $0.append(conn) }
            return conn
        })
        let session = VitruvianCodeQuickPromptSession(environment: env, host: LiveStateMockHost())
        session.takeCheckpoint = { _ in nil }
        session.idleConnectionTimeout = 0.05
        let agyConfig = VitruvianCodeConfiguration(approvalMode: .standard, activeProvider: Self.agyACPProvider)

        session.send("Turn 1", configuration: agyConfig, agentPath: "/fake/agy")
        try await waitUntil("conn1 prompts") { connections.value.first?.promptCalls.count == 1 }
        let conn1 = connections.value[0]
        conn1.emit(.slashCommands(["review", "compact"]))
        try await waitUntil("slash commands received") { session.cliSlashCommands == ["review", "compact"] }
        conn1.emit(.finished(status: "completed", response: "OK", error: nil, conversationID: "s-keep-slash"))
        conn1.finishPrompt(with: .endTurn)
        try await waitUntil("idle shutdown stops conn1") { !session.isRunning && conn1.stopCount == 1 }

        XCTAssertEqual(session.cliSlashCommands, ["review", "compact"], "idle shutdown must keep slash commands")

        // Next turn restarts same provider & connection kind, then crashes -> slash commands still remain
        session.send("Turn 2", configuration: agyConfig, agentPath: "/fake/agy")
        try await waitUntil("conn2 prompts") { connections.value.count == 2 && connections.value[1].promptCalls.count == 1 }
        let conn2 = connections.value[1]
        conn2.emit(.connectionFailed(AgentFailure(kind: .exited, message: "crashed")))
        conn2.finishPrompt(with: .error)
        await conn2.stop()
        try await waitUntil("turn 2 crash handled") { !session.isRunning }

        XCTAssertEqual(session.cliSlashCommands, ["review", "compact"], "connection crash must keep slash commands")

        // Switching provider/connection kind clears slash commands
        let claudeConfig = VitruvianCodeConfiguration(approvalMode: .standard, activeProvider: Self.claudeSDKProvider)
        session.send("Turn 3 different provider", configuration: claudeConfig, agentPath: "/usr/bin/true")
        try await waitUntil("conn3 starts") { connections.value.count == 3 }
        XCTAssertEqual(session.cliSlashCommands, [], "changing provider/connection kind must clear slash commands")
        let conn3 = connections.value[2]
        conn3.emit(.finished(status: "completed", response: "OK", error: nil, conversationID: "s-keep-slash-2"))
        conn3.finishPrompt(with: .endTurn)
        try await waitUntil("turn 3 done") { !session.isRunning }
        await session.stopAll()
    }

    func testForcedFreshSessionInWorktreeShowsTranscriptNoticeAndResetsLiveState() async throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("wt-fresh-notice-\(UUID().uuidString)", isDirectory: true)
        let repoDir = tempRoot.appendingPathComponent("repo", isDirectory: true)
        try FileManager.default.createDirectory(at: repoDir.appendingPathComponent(".git"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let connections = LiveStateLockedBox<[LiveStateMockConnection]>([])
        let env = makeSessionEnvironment(
            makeConnection: { spec in
                let conn = LiveStateMockConnection(spec: spec)
                connections.withValue { $0.append(conn) }
                return conn
            },
            runProgramChecked: { name, args in
                if name == "git", args.contains("worktree"), args.contains("add"),
                   let pathArg = args.last(where: { $0.contains("repo-worktrees") }) {
                    try? FileManager.default.createDirectory(atPath: pathArg, withIntermediateDirectories: true)
                    return ""
                }
                return nil
            }
        )

        let expectedNotice = VitruvianCodeHostStrings().worktreeFreshSessionNotice
        let session = VitruvianCodeQuickPromptSession(environment: env, host: LiveStateMockHost())
        session.takeCheckpoint = { _ in nil }
        let config = VitruvianCodeConfiguration(
            workingDirectory: repoDir.path,
            approvalMode: .standard,
            activeProvider: Self.agyACPProvider
        )

        // Case A: Mid-chat worktree toggle ON forces fresh session, resets liveState, and adds visible transcript notice
        session.send("Turn 1 base", configuration: config, agentPath: "/fake/agy")
        try await waitUntil("conn1 prompts") { connections.value.first?.promptCalls.count == 1 }
        let conn1 = connections.value[0]
        conn1.emit(.planReplaced([PlanEntry(content: "Base plan", status: .inProgress)]))
        conn1.emit(.notice(severity: "info", title: "Base notice", detail: nil))
        conn1.emit(.started(conversationID: "base-sess-1"))
        conn1.emit(.finished(status: "completed", response: "OK 1", error: nil, conversationID: "base-sess-1"))
        conn1.finishPrompt(with: .endTurn)
        try await waitUntil("turn 1 done with liveState") {
            !session.isRunning && session.liveState.notices.count == 1
        }

        session.worktreeMode = true
        session.send("Turn 2 in worktree", configuration: config, agentPath: "/fake/agy")
        try await waitUntil("conn2 starts") { connections.value.count == 2 && connections.value[1].startCalls.count == 1 }
        let conn2 = connections.value[1]
        XCTAssertNil(conn2.startCalls.first?.resumeSessionID)
        XCTAssertEqual(session.liveState, AgentLiveState(), "forced fresh session must reset liveState")

        let noticeIdx = try XCTUnwrap(session.messages.firstIndex { $0.role == .agent && !$0.isError && $0.text == expectedNotice })
        let baseReplyIdx = try XCTUnwrap(session.messages.firstIndex { $0.text == "OK 1" })
        let turn2UserIdx = try XCTUnwrap(session.messages.firstIndex { $0.role == .user && $0.text == "Turn 2 in worktree" })
        XCTAssertGreaterThan(noticeIdx, baseReplyIdx)
        XCTAssertLessThan(noticeIdx, turn2UserIdx)

        conn2.emit(.finished(status: "completed", response: "OK 2", error: nil, conversationID: "wt-sess-2"))
        conn2.finishPrompt(with: .endTurn)
        try await waitUntil("turn 2 done") { !session.isRunning }
        await session.stopAll()

        // Case B: Opening a saved chat with worktree ON and sending a prompt forces fresh session + shows notice
        let resumedSession = VitruvianCodeQuickPromptSession(environment: env, host: LiveStateMockHost())
        resumedSession.takeCheckpoint = { _ in nil }
        resumedSession.worktreeMode = true
        resumedSession.resume(
            VitruvianCodeSessionSummary(id: "saved-chat-99", title: "Saved Chat", preview: "Earlier message", steps: 2, modified: nil),
            configuration: config
        )
        XCTAssertEqual(resumedSession.conversationID, "saved-chat-99")
        let resumedMsgCount = resumedSession.messages.count
        XCTAssertGreaterThan(resumedMsgCount, 0)

        resumedSession.send("Continue in worktree", configuration: config, agentPath: "/fake/agy")
        try await waitUntil("conn3 starts") { connections.value.count == 3 && connections.value[2].startCalls.count == 1 }
        let conn3 = connections.value[2]
        XCTAssertNil(conn3.startCalls.first?.resumeSessionID, "reopened chat with worktree ON must start a fresh session")
        XCTAssertEqual(resumedSession.liveState, AgentLiveState())
        let resumedNoticeIdx = try XCTUnwrap(
            resumedSession.messages.firstIndex { $0.role == .agent && !$0.isError && $0.text == expectedNotice }
        )
        let resumedTurnUserIdx = try XCTUnwrap(
            resumedSession.messages.firstIndex { $0.role == .user && $0.text == "Continue in worktree" }
        )
        XCTAssertGreaterThanOrEqual(resumedNoticeIdx, resumedMsgCount)
        XCTAssertLessThan(resumedNoticeIdx, resumedTurnUserIdx)

        conn3.emit(.finished(status: "completed", response: "OK 3", error: nil, conversationID: "wt-sess-3"))
        conn3.finishPrompt(with: .endTurn)
        try await waitUntil("turn 3 done") { !resumedSession.isRunning }
        await resumedSession.stopAll()
    }

    func testFailedWorktreeSetupRemovesOnlyCreatedWorktreeAndBranch() async throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("wt-setup-clean-\(UUID().uuidString)", isDirectory: true)
        let repoDir = tempRoot.appendingPathComponent("repo", isDirectory: true)
        let wtsDir = tempRoot.appendingPathComponent("wts", isDirectory: true)
        try FileManager.default.createDirectory(at: repoDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let initOut = await VitruvianCodeEngine.runProgram(named: "git", arguments: ["-C", repoDir.path, "init"], requireZeroExit: true)
        let emailOut = await VitruvianCodeEngine.runProgram(named: "git", arguments: ["-C", repoDir.path, "config", "user.email", "test@example.com"], requireZeroExit: true)
        let nameOut = await VitruvianCodeEngine.runProgram(named: "git", arguments: ["-C", repoDir.path, "config", "user.name", "Test"], requireZeroExit: true)
        let commitOut = await VitruvianCodeEngine.runProgram(named: "git", arguments: ["-C", repoDir.path, "commit", "--allow-empty", "-m", "init"], requireZeroExit: true)
        XCTAssertNotNil(initOut)
        XCTAssertNotNil(emailOut)
        XCTAssertNotNil(nameOut)
        XCTAssertNotNil(commitOut)

        let strictRunner: VitruvianCodeWorktreeManager.ProgramRunner = { name, args in
            await VitruvianCodeEngine.runProgram(named: name, arguments: args, requireZeroExit: true)
        }
        let manager = VitruvianCodeWorktreeManager()

        let keeper = await manager.createWorktree(
            taskName: "keeper",
            baseRepositoryPath: repoDir.path,
            worktreesRoot: wtsDir.path,
            provider: Self.agyACPProvider,
            runGit: strictRunner
        )
        XCTAssertEqual(keeper.setupStatus, .ready)
        XCTAssertTrue(FileManager.default.fileExists(atPath: keeper.worktreePath))

        let broken = await manager.createWorktree(
            taskName: "broken-setup",
            baseRepositoryPath: repoDir.path,
            worktreesRoot: wtsDir.path,
            provider: Self.agyACPProvider,
            config: VitruvianCodeWorktreeConfig(setup: ["exit 1"]),
            runGit: strictRunner
        )
        XCTAssertEqual(broken.setupStatus, .failed("Setup command failed: exit 1"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: broken.worktreePath), "failed setup worktree dir must be removed")
        let brokenBranchOut = await VitruvianCodeEngine.runProgram(
            named: "git",
            arguments: ["-C", repoDir.path, "branch", "--list", broken.branchName],
            requireZeroExit: true
        )
        XCTAssertEqual(brokenBranchOut?.trimmingCharacters(in: .whitespacesAndNewlines), "", "failed setup branch must be deleted")

        let listed = await manager.listPorcelainWorktrees(baseRepositoryPath: repoDir.path, runGit: strictRunner)
        let canonicalBroken = URL(fileURLWithPath: broken.worktreePath).resolvingSymlinksInPath().path
        XCTAssertFalse(listed.contains { URL(fileURLWithPath: $0.worktreePath).resolvingSymlinksInPath().path == canonicalBroken })
        XCTAssertEqual(manager.worktrees.map(\.id), [keeper.id])

        // Existing keeper worktree and its branch must remain untouched
        XCTAssertTrue(FileManager.default.fileExists(atPath: keeper.worktreePath))
        let keeperBranchOut = await VitruvianCodeEngine.runProgram(
            named: "git",
            arguments: ["-C", repoDir.path, "branch", "--list", keeper.branchName],
            requireZeroExit: true
        )
        XCTAssertTrue(keeperBranchOut?.contains(keeper.branchName) == true)
    }

    func testStopDuringWorktreeCreationRemovesOnlyCreatedWorktreeAndBranch() async throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("wt-stop-clean-\(UUID().uuidString)", isDirectory: true)
        let repoDir = tempRoot.appendingPathComponent("repo", isDirectory: true)
        try FileManager.default.createDirectory(at: repoDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let initOut = await VitruvianCodeEngine.runProgram(named: "git", arguments: ["-C", repoDir.path, "init"], requireZeroExit: true)
        let emailOut = await VitruvianCodeEngine.runProgram(named: "git", arguments: ["-C", repoDir.path, "config", "user.email", "test@example.com"], requireZeroExit: true)
        let nameOut = await VitruvianCodeEngine.runProgram(named: "git", arguments: ["-C", repoDir.path, "config", "user.name", "Test"], requireZeroExit: true)
        let commitOut = await VitruvianCodeEngine.runProgram(named: "git", arguments: ["-C", repoDir.path, "commit", "--allow-empty", "-m", "init"], requireZeroExit: true)
        XCTAssertNotNil(initOut)
        XCTAssertNotNil(emailOut)
        XCTAssertNotNil(nameOut)
        XCTAssertNotNil(commitOut)

        let strictRunner: VitruvianCodeWorktreeManager.ProgramRunner = { name, args in
            await VitruvianCodeEngine.runProgram(named: name, arguments: args, requireZeroExit: true)
        }

        let gate = LiveStateWorktreeGate()
        let connectionAttempts = LiveStateLockedBox(0)
        let createdPathBox = LiveStateLockedBox<String?>(nil)
        let env = makeSessionEnvironment(
            makeConnection: { spec in
                connectionAttempts.withValue { $0 += 1 }
                return LiveStateMockConnection(spec: spec)
            },
            runProgramChecked: { name, args in
                let result = await VitruvianCodeEngine.runProgram(named: name, arguments: args, requireZeroExit: true)
                if name == "git", args.contains("worktree"), args.contains("add"),
                   let pathArg = args.first(where: { $0.contains("repo-worktrees") }) {
                    createdPathBox.withValue { $0 = pathArg }
                    await gate.enterAndWaitForRelease()
                }
                return result
            }
        )

        let session = VitruvianCodeQuickPromptSession(environment: env, host: LiveStateMockHost())
        session.takeCheckpoint = { _ in nil }
        let keeper = await session.worktreeManager.createWorktree(
            taskName: "keeper",
            baseRepositoryPath: repoDir.path,
            provider: Self.agyACPProvider,
            runGit: strictRunner
        )
        XCTAssertEqual(keeper.setupStatus, .ready)
        XCTAssertTrue(FileManager.default.fileExists(atPath: keeper.worktreePath))

        session.worktreeMode = true
        let config = VitruvianCodeConfiguration(
            workingDirectory: repoDir.path,
            approvalMode: .standard,
            activeProvider: Self.agyACPProvider
        )
        session.send("Start in worktree", configuration: config, agentPath: "/fake/agy")

        await gate.waitUntilEntered()
        let createdPath = try XCTUnwrap(createdPathBox.value)
        XCTAssertTrue(FileManager.default.fileExists(atPath: createdPath), "git worktree add must have created the directory on disk")

        session.stop()
        try await waitUntil("turn stopped") { !session.isRunning }
        XCTAssertNil(session.liveWorktreePath)

        await gate.release()
        try await waitUntil("just-created worktree removed on stop") {
            session.worktreeManager.worktrees.map(\.id) == [keeper.id]
                && !FileManager.default.fileExists(atPath: createdPath)
        }

        XCTAssertEqual(connectionAttempts.value, 0)
        let removedBranchOut = await VitruvianCodeEngine.runProgram(
            named: "git",
            arguments: ["-C", repoDir.path, "branch", "--list", "nexus/antigravity-cli/chat-1"],
            requireZeroExit: true
        )
        XCTAssertEqual(removedBranchOut?.trimmingCharacters(in: .whitespacesAndNewlines), "", "created worktree branch must be deleted")

        // Keeper worktree and its branch must remain untouched
        XCTAssertTrue(FileManager.default.fileExists(atPath: keeper.worktreePath))
        let keeperBranchOut = await VitruvianCodeEngine.runProgram(
            named: "git",
            arguments: ["-C", repoDir.path, "branch", "--list", keeper.branchName],
            requireZeroExit: true
        )
        XCTAssertTrue(keeperBranchOut?.contains(keeper.branchName) == true)
    }

    // MARK: - 5. AgentLiveState

    func testAgentLiveStateAppliesEveryEventCapsNoticesAndResets() {
        var state = AgentLiveState(maxNotices: 3)

        let plan = [PlanEntry(content: "Inspect files", status: .inProgress, priority: .high)]
        state.apply(.planReplaced(plan))
        XCTAssertEqual(state.plan, plan)

        let options = [AgentConfigOption(id: "model", name: "Model", value: .string("opus"), options: ["opus", "sonnet"])]
        state.apply(.configOptions(options))
        XCTAssertEqual(state.configOptions, options)

        state.apply(.compaction(id: "cmp-1", status: "completed", summary: "Compacted 12 messages"))
        XCTAssertEqual(state.compaction, AgentLiveState.Compaction(id: "cmp-1", status: "completed", summary: "Compacted 12 messages"))

        state.apply(.notice(severity: "info", title: "N1", detail: nil))
        state.apply(.notice(severity: "warning", title: "N2", detail: "D2"))
        state.apply(.notice(severity: "error", title: "N3", detail: nil))
        state.apply(.notice(severity: "info", title: "N4", detail: "D4"))
        XCTAssertEqual(state.notices.map(\.title), ["N2", "N3", "N4"])
        XCTAssertEqual(state.notices.map(\.id), [2, 3, 4])
        XCTAssertEqual(state.notices.first?.detail, "D2")

        state.apply(.sessionInfo(title: "Live Session Title", updatedAt: nil))
        state.apply(.sessionInfo(title: nil, updatedAt: "2026-11-23T08:00:00Z"))
        XCTAssertEqual(
            state.sessionInfo,
            AgentLiveState.SessionInfo(title: "Live Session Title", updatedAt: "2026-11-23T08:00:00Z")
        )

        let resetDate = Date(timeIntervalSince1970: 1_800_000_000)
        state.apply(.usageLimit(resetsAt: resetDate))
        XCTAssertEqual(state.usageLimit, AgentLiveState.UsageLimit(resetsAt: resetDate))
        state.apply(.usageLimit(resetsAt: nil))
        XCTAssertEqual(state.usageLimit, AgentLiveState.UsageLimit(resetsAt: nil))

        // Unrelated events must leave state untouched
        let snapshot = state
        state.apply(.text("hello"))
        state.apply(.thinking("ponder"))
        XCTAssertEqual(state, snapshot)

        state.reset()
        XCTAssertEqual(state, AgentLiveState(maxNotices: 3))
        XCTAssertTrue(state.plan.isEmpty)
        XCTAssertTrue(state.configOptions.isEmpty)
        XCTAssertNil(state.compaction)
        XCTAssertTrue(state.notices.isEmpty)
        XCTAssertNil(state.sessionInfo)
        XCTAssertNil(state.usageLimit)
    }

    func testSessionLiveStateUpdatesFromEventsAndResetsWhenChatChanges() async throws {
        let connections = LiveStateLockedBox<[LiveStateMockConnection]>([])
        let env = makeSessionEnvironment(makeConnection: { spec in
            let conn = LiveStateMockConnection(spec: spec)
            connections.withValue { $0.append(conn) }
            return conn
        })
        let session = VitruvianCodeQuickPromptSession(environment: env, host: LiveStateMockHost())
        session.takeCheckpoint = { _ in nil }
        let config = VitruvianCodeConfiguration(approvalMode: .standard, activeProvider: Self.agyACPProvider)

        let resetDate = Date(timeIntervalSince1970: 1_800_000_123)
        session.send("Run with live events", configuration: config, agentPath: "/fake/agy")
        try await waitUntil("conn1 prompts") { connections.value.first?.promptCalls.count == 1 }
        let conn1 = connections.value[0]
        conn1.emit(.planReplaced([PlanEntry(content: "Step 1", status: .completed)]))
        conn1.emit(.configOptions([AgentConfigOption(id: "mode", name: "Mode", value: .string("default"), options: ["default"])]))
        conn1.emit(.compaction(id: "c-1", status: "running", summary: nil))
        conn1.emit(.notice(severity: "warning", title: "Heads up", detail: "Rate near limit"))
        conn1.emit(.sessionInfo(title: "Chat A", updatedAt: "2026-11-23T08:10:00Z"))
        conn1.emit(.usageLimit(resetsAt: resetDate))
        conn1.emit(.finished(status: "completed", response: "Done", error: nil, conversationID: "s-live-1"))
        conn1.finishPrompt(with: .endTurn)
        try await waitUntil("turn 1 done and liveState updated") {
            !session.isRunning && session.liveState.usageLimit?.resetsAt == resetDate
        }

        XCTAssertEqual(session.liveState.plan.map(\.content), ["Step 1"])
        XCTAssertEqual(session.liveState.configOptions.map(\.id), ["mode"])
        XCTAssertEqual(session.liveState.compaction?.id, "c-1")
        XCTAssertEqual(session.liveState.notices.map(\.title), ["Heads up"])
        XCTAssertEqual(session.liveState.sessionInfo?.title, "Chat A")

        session.newChat()
        XCTAssertEqual(session.liveState, AgentLiveState())

        // Also resets on resume(...)
        session.send("Second chat", configuration: config, agentPath: "/fake/agy")
        try await waitUntil("conn2 prompts") { connections.value.count == 2 && connections.value[1].promptCalls.count == 1 }
        let conn2 = connections.value[1]
        conn2.emit(.notice(severity: "info", title: "Chat B notice", detail: nil))
        conn2.emit(.finished(status: "completed", response: "Done", error: nil, conversationID: "s-live-2"))
        conn2.finishPrompt(with: .endTurn)
        try await waitUntil("turn 2 done and notice set") {
            !session.isRunning && session.liveState.notices.count == 1
        }

        session.resume(VitruvianCodeSessionSummary(id: "s-live-1", title: "Chat A", preview: "Hi", steps: 1, modified: nil), configuration: config)
        XCTAssertEqual(session.liveState, AgentLiveState())
        await session.stopAll()
    }

    // MARK: - Helpers

    private func waitUntil(
        _ description: String,
        timeout: TimeInterval = 4.0,
        condition: @escaping @MainActor () -> Bool
    ) async throws {
        try await withACPTestTimeout(seconds: timeout, description: description) { @MainActor in
            while !condition() {
                try? await Task.sleep(nanoseconds: 5_000_000)
            }
        }
    }

    private func makeSessionEnvironment(
        makeConnection: @escaping (AgentConnectionSpec) -> any AgentConnection,
        runProgram: @escaping @Sendable (String, [String]) async -> String? = { _, _ in nil },
        runProgramChecked: (@Sendable (String, [String]) async -> String?)? = nil
    ) -> VitruvianCodeEngine.Environment {
        let domain = "com.vitruviansoftware.vitruvian-code.tests.live-state.\(UUID().uuidString)"
        let defaults = ScratchDefaults.suite(named: domain)!
        defaults.removePersistentDomain(forName: domain)
        scratchSuites.append((defaults, domain))
        return VitruvianCodeEngine.Environment(
            defaults: defaults,
            home: "/tmp",
            processEnvironment: [:],
            stateDirectory: "/tmp/vitruvian-code-test-state",
            isExecutable: { _ in true },
            fileExists: { _ in true },
            readFile: { _ in nil },
            readTail: { _, _ in nil },
            writePrivateFile: { _, _ in true },
            removeFile: { _ in },
            isBotProcess: { _ in false },
            signal: { _, _ in },
            launchBot: { _, _, _, _, _ in 1 },
            schedule: { _, _ in },
            openFile: { _ in },
            launchAgent: { _, _, _, _, _, _ in throw CocoaError(.featureUnsupported) },
            makeConnection: makeConnection,
            runProgram: runProgram,
            runProgramChecked: runProgramChecked
        )
    }
}

private actor LiveStateWorktreeGate {
    private var entered = false
    private var enterContinuation: CheckedContinuation<Void, Never>?
    private var releaseContinuation: CheckedContinuation<Void, Never>?

    func waitUntilEntered() async {
        if entered { return }
        await withCheckedContinuation { enterContinuation = $0 }
    }

    func enterAndWaitForRelease() async {
        entered = true
        let enter = enterContinuation
        enterContinuation = nil
        enter?.resume()
        await withCheckedContinuation { releaseContinuation = $0 }
    }

    func release() {
        let cont = releaseContinuation
        releaseContinuation = nil
        cont?.resume()
    }
}

private final class LiveStateLockedBox<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var rawValue: Value

    init(_ initial: Value) {
        self.rawValue = initial
    }

    var value: Value {
        lock.withLock { rawValue }
    }

    func withValue(_ body: (inout Value) -> Void) {
        lock.withLock { body(&rawValue) }
    }
}

@MainActor
private final class LiveStateMockConnection: PersistentAgentConnection {
    let spec: AgentConnectionSpec
    var capabilities = AgentCapabilities(resumeSession: true, closeSession: true)
    let events: AsyncStream<AgentEvent>
    private let continuation: AsyncStream<AgentEvent>.Continuation

    private(set) var startCalls: [AgentSessionRequest] = []
    private(set) var promptCalls: [[PromptBlock]] = []
    private(set) var syncedModes: [(VitruvianCodeApprovalMode, Bool)] = []
    private(set) var cancelCount = 0
    private(set) var stopCount = 0
    private(set) var isStopped = false
    var failSyncMode = false
    var holdStart = false
    var holdSyncMode = false
    var isConnected: Bool { !isStopped }

    private var startContinuation: CheckedContinuation<String, any Error>?
    private var syncContinuation: CheckedContinuation<Void, any Error>?
    private var promptContinuation: CheckedContinuation<AgentStopReason, any Error>?

    init(spec: AgentConnectionSpec) {
        self.spec = spec
        var captured: AsyncStream<AgentEvent>.Continuation!
        self.events = AsyncStream { captured = $0 }
        self.continuation = captured
    }

    func start(_ request: AgentSessionRequest) async throws -> String {
        startCalls.append(request)
        if holdStart {
            return try await withCheckedThrowingContinuation { cont in
                self.startContinuation = cont
            }
        }
        return request.resumeSessionID ?? "mock-live-1"
    }

    func releaseStart(sessionID: String) {
        let cont = startContinuation
        startContinuation = nil
        cont?.resume(returning: sessionID)
    }

    func syncPlanMode(_ planSwitch: Bool) async throws {
        try await syncMode(approvalMode: .standard, planSwitch: planSwitch)
    }

    func syncMode(approvalMode: VitruvianCodeApprovalMode, planSwitch: Bool) async throws {
        syncedModes.append((approvalMode, planSwitch))
        if failSyncMode {
            throw ACPConnectionError.notStarted
        }
        if holdSyncMode {
            try await withCheckedThrowingContinuation { cont in
                self.syncContinuation = cont
            }
        }
    }

    func releaseSyncMode() {
        let cont = syncContinuation
        syncContinuation = nil
        cont?.resume()
    }

    func prompt(_ blocks: [PromptBlock]) async throws -> AgentStopReason {
        promptCalls.append(blocks)
        return try await withCheckedThrowingContinuation { cont in
            self.promptContinuation = cont
        }
    }

    func cancel() async {
        cancelCount += 1
    }

    func answer(_ requestID: String, _ choice: AgentAnswer) async throws {}

    func setConfigOption(_ id: String, _ value: AgentConfigValue) async throws -> [AgentConfigOption] { [] }

    func stop() async {
        stopCount += 1
        isStopped = true
        continuation.finish()
    }

    func emit(_ event: AgentEvent) {
        continuation.yield(event)
    }

    func finishPrompt(with reason: AgentStopReason) {
        let cont = promptContinuation
        promptContinuation = nil
        cont?.resume(returning: reason)
    }
}

@MainActor
private final class LiveStateMockHost: VitruvianCodeHost {
    var configuredBotDirectory = ""
    var startsBotAtLaunch = false
    var planMode = false
    var hiddenClaudeSessionIDs: [String] = []
    var chosenProviderID: UUID? = VitruvianCodeCLIProvider.antigravity.id
    var chosenModels: [UUID: String] = [:]
    var savedProviders: [VitruvianCodeCLIProvider] = []
    var promptHistory: [String] = []
    var worktreeMode = false
    var timelineOnLeft = true
    var sessionPreferences = VitruvianCodeSessionPreferences()
    var chatModes: [String: String] = [:]
    var showsConnectionSetting = false
    var strings = VitruvianCodeHostStrings()

    func turnNeedsApproval(_ notice: VitruvianCodeTurnNotice) {}
    func turnFinished(_ notice: VitruvianCodeTurnNotice, isChatVisible: Bool) {}
}
