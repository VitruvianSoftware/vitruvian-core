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
final class AntigravityACPTests: XCTestCase {
    private var scratchSuites: [(UserDefaults, String)] = []

    override func tearDown() {
        for (defaults, domain) in scratchSuites {
            defaults.removePersistentDomain(forName: domain)
        }
        scratchSuites.removeAll()
        super.tearDown()
    }
    private static let defaultLaunchSpec = AgentProcessLaunchSpec(
        executable: "/fake/agy",
        arguments: ["acp"],
        environment: [:],
        workingDirectory: "/workspace"
    )

    private static let agyACPProvider = VitruvianCodeCLIProvider(
        id: VitruvianCodeCLIProvider.antigravity.id,
        name: "Antigravity CLI",
        commandTemplate: VitruvianCodeCLIProvider.antigravity.commandTemplate,
        isBuiltIn: true,
        connection: .acp
    )

    private static func agyFixturesDirectoryURL(filePath: StaticString = #filePath) -> URL {
        let relative = "apps/desktop/vitruvian-code/testdata/acp"
        let environment = ProcessInfo.processInfo.environment
        if let runfiles = environment["TEST_SRCDIR"] {
            for workspace in [environment["TEST_WORKSPACE"], "_main"].compactMap({ $0 }) {
                let candidate = URL(fileURLWithPath: "\(runfiles)/\(workspace)/\(relative)", isDirectory: true)
                if FileManager.default.fileExists(atPath: candidate.path) {
                    return candidate
                }
            }
        }
        let testsDir = (String(describing: filePath) as NSString).deletingLastPathComponent
        let appRoot = ((testsDir as NSString).deletingLastPathComponent as NSString).deletingLastPathComponent
        return URL(fileURLWithPath: "\(appRoot)/testdata/acp", isDirectory: true)
    }

    // MARK: - Group 1: Replay Fixtures (`testdata/acp/agy-*.ndjson`)

    func testAllAgyReplayFixturesProduceExpectedFullEventSequences() async throws {
        let fixturesDir = Self.agyFixturesDirectoryURL()
        let fixtureFiles = try FileManager.default.contentsOfDirectory(atPath: fixturesDir.path)
            .filter { $0.hasPrefix("agy-") && $0.hasSuffix(".ndjson") }
            .sorted()
        XCTAssertEqual(
            Set(fixtureFiles),
            [
                "agy-cancel.ndjson",
                "agy-prompt-text-thinking.ndjson",
                "agy-question-synthetic.ndjson",
                "agy-resume.ndjson",
                "agy-tool-permission-synthetic.ndjson",
            ]
        )

        let expectedInitialConfigOptions: [AgentConfigOption] = [
            AgentConfigOption(
                id: "model",
                name: "Model",
                value: .string("gemini-4-carbon"),
                options: [
                    "gemini-4-carbon",
                    "gemini-4-argon",
                    "gemini-4-hydrogen",
                    "gemini-pro-orchestrator",
                    "gemini-pro-orchestrator-argon",
                    "gemini-3.8-flash",
                    "claude-opus-5-5",
                    "claude-sonnet-5-5",
                    "gpt-oss-120b-medium",
                ],
                category: "model"
            ),
            AgentConfigOption(
                id: "thought_level",
                name: "Thinking Level",
                value: .string("medium"),
                options: ["low", "medium", "high"],
                category: "thought_level"
            ),
            AgentConfigOption(
                id: "mode",
                name: "Mode",
                value: .string("default"),
                options: ["default", "accept-edits", "auto", "plan"],
                category: "mode"
            ),
        ]
        let expectedAgyCommands: [VitruvianCodeSlashCommand] = [
            VitruvianCodeSlashCommand(name: "compact", description: "Compact conversation history", isBuiltIn: false),
            VitruvianCodeSlashCommand(name: "clear", description: "Clear conversation context", isBuiltIn: false),
            VitruvianCodeSlashCommand(name: "help", description: "Show help information", isBuiltIn: false),
        ]

        do {
            let events = try await replayFixture(
                named: "agy-prompt-text-thinking.ndjson",
                mode: .standard,
                promptText: "Solve this logic puzzle"
            )
            let expectedTurnUsage = VitruvianCodeContextUsage(inputTokens: 30_944, cachedTokens: 0, outputTokens: 515, contextWindow: 1_048_576)
            XCTAssertEqual(
                events,
                [
                    .configOptions(expectedInitialConfigOptions),
                    .slashCommands(["compact", "clear", "help"]),
                    .availableCommands(expectedAgyCommands),
                    .contextUsage(VitruvianCodeContextUsage(inputTokens: 0, cachedTokens: 0, outputTokens: 0, contextWindow: 1_048_576)),
                    .sessionInfo(title: "Logic Puzzle Fruit Box Solution", updatedAt: nil),
                    .thinking(
                        "Initial hypothesis: The key is that *all* labels are wrong. Therefore, picking from the \"Mixed\" box will reveal the fruit, and this single observation unlocks the entire puzzle. If an apple is picked, the \"Mixed\" box must be apples. \"Oranges\" can't be oranges, therefore must be mixed, and \"Apples\" must be oranges. This pattern applies if an orange is picked as well.\n\n\n"
                    ),
                    .text("1"),
                    .text(". **Determine the \"Mixed\" box:** Every label is wrong, so the box labeled **Mixed** cannot contain mixed"),
                    .text(" fruit—it must contain either all apples or all oranges. Because you pulled an apple from it, it must contain **Apples**.\n2."),
                    .text(" **Determine the \"Oranges\" box:** Its label is wrong, so it cannot contain oranges. Since **Apples** are already accounted for in the"),
                    .text(" first step, the box labeled **Oranges** must contain **Mixed** fruit.\n3. **Determine the \"Apples\""),
                    .text(" box:** Only one option remains, so the box labeled **Apples** must contain **Oranges** (which also keeps"),
                    .text(" its label wrong).\n\n**Final contents:**\n- Labeled **Mixed** → **Apples**\n- Labeled **Oranges**"),
                    .text(" → **Mixed**\n- Labeled **Apples** → **Oranges**"),
                    .contextUsage(VitruvianCodeContextUsage(inputTokens: 31_459, cachedTokens: 0, outputTokens: 0, contextWindow: 1_048_576)),
                    .contextUsage(expectedTurnUsage),
                    .finished(
                        status: "completed",
                        response: "1. **Determine the \"Mixed\" box:** Every label is wrong, so the box labeled **Mixed** cannot contain mixed fruit—it must contain either all apples or all oranges. Because you pulled an apple from it, it must contain **Apples**.\n2. **Determine the \"Oranges\" box:** Its label is wrong, so it cannot contain oranges. Since **Apples** are already accounted for in the first step, the box labeled **Oranges** must contain **Mixed** fruit.\n3. **Determine the \"Apples\" box:** Only one option remains, so the box labeled **Apples** must contain **Oranges** (which also keeps its label wrong).\n\n**Final contents:**\n- Labeled **Mixed** → **Apples**\n- Labeled **Oranges** → **Mixed**\n- Labeled **Apples** → **Oranges**",
                        error: nil,
                        conversationID: "ef176d1c-0065-4775-accd-f99a6645ec5a",
                        metrics: VitruvianCodeTurnMetrics(inputTokens: 30_944, outputTokens: 515, cachedTokens: 0, contextUsage: expectedTurnUsage)
                    ),
                ]
            )
        }

        do {
            let events = try await replayFixture(
                named: "agy-tool-permission-synthetic.ndjson",
                mode: .standard,
                promptText: "Clean temporary build directory.",
                onApproval: { conn, req in
                    try await conn.answer(req.requestID ?? "", .option("allow_once"))
                }
            )
            let expectedTurnUsage = VitruvianCodeContextUsage(inputTokens: 800, cachedTokens: 0, outputTokens: 24, contextWindow: 1_048_576)
            XCTAssertEqual(
                events,
                [
                    .configOptions(expectedInitialConfigOptions),
                    .approval(
                        VitruvianCodeApprovalRequest(
                            id: "call-exec-1",
                            toolName: "Run rm -rf /workspace/build",
                            commandOrPath: "rm -rf /workspace/build",
                            status: .pending,
                            requestID: "perm-1",
                            options: [
                                AgentPermissionOption(id: "allow_once", name: "Allow once", kind: .allowOnce),
                                AgentPermissionOption(id: "allow_always", name: "Allow for this session", kind: .allowAlways),
                                AgentPermissionOption(id: "reject_once", name: "Deny", kind: .rejectOnce),
                            ]
                        )
                    ),
                    .toolStep(
                        VitruvianCodeToolStep(
                            id: "call-exec-1",
                            title: "Run rm -rf /workspace/build",
                            detail: "Run rm -rf /workspace/build",
                            isFinished: false,
                            kind: .bash
                        )
                    ),
                    .toolStepResult(id: "call-exec-1", output: "Cleaned build folder.", isError: false),
                    .text("Done."),
                    .contextUsage(VitruvianCodeContextUsage(inputTokens: 1_024, cachedTokens: 0, outputTokens: 0, contextWindow: 1_048_576)),
                    .contextUsage(expectedTurnUsage),
                    .finished(
                        status: "completed",
                        response: "Done.",
                        error: nil,
                        conversationID: "sess-agy-perm-1",
                        metrics: VitruvianCodeTurnMetrics(inputTokens: 800, outputTokens: 24, cachedTokens: 0, contextUsage: expectedTurnUsage)
                    ),
                ]
            )
        }

        do {
            let events = try await replayFixture(
                named: "agy-question-synthetic.ndjson",
                mode: .yolo,
                promptText: "Ask me which color I prefer.",
                onQuestion: { conn, question in
                    try await conn.answer(question.requestID, .cancelled)
                }
            )
            let expectedTurnUsage = VitruvianCodeContextUsage(inputTokens: 500, cachedTokens: 0, outputTokens: 12, contextWindow: 0)
            XCTAssertEqual(
                events,
                [
                    .configOptions(expectedInitialConfigOptions),
                    .question(
                        AgentQuestion(
                            requestID: "perm-1",
                            title: "Question",
                            message: "Which color do you prefer?",
                            url: nil,
                            fields: [
                                AgentQuestion.Field(
                                    id: "interaction_1",
                                    type: .choice,
                                    label: "Which color do you prefer?",
                                    description: "Question",
                                    required: true,
                                    options: [
                                        AgentQuestion.Option(value: "red", label: "Red", description: "Red"),
                                        AgentQuestion.Option(value: "blue", label: "Blue", description: "Blue"),
                                    ]
                                ),
                            ]
                        )
                    ),
                    .text("No choice made."),
                    .contextUsage(expectedTurnUsage),
                    .finished(
                        status: "completed",
                        response: "No choice made.",
                        error: nil,
                        conversationID: "sess-agy-question-1",
                        metrics: VitruvianCodeTurnMetrics(inputTokens: 500, outputTokens: 12, cachedTokens: 0, contextUsage: expectedTurnUsage)
                    ),
                ]
            )
        }

        do {
            let events = try await replayFixture(
                named: "agy-cancel.ndjson",
                mode: .standard,
                promptText: "Write an essay",
                cancelAfterThinking: true
            )
            let expectedTurnUsage = VitruvianCodeContextUsage(inputTokens: 29_662, cachedTokens: 0, outputTokens: 94, contextWindow: 1_048_576)
            XCTAssertEqual(
                events,
                [
                    .configOptions(expectedInitialConfigOptions),
                    .slashCommands(["compact", "clear", "help"]),
                    .availableCommands(expectedAgyCommands),
                    .contextUsage(VitruvianCodeContextUsage(inputTokens: 0, cachedTokens: 0, outputTokens: 0, contextWindow: 1_048_576)),
                    .sessionInfo(title: "History of Unix Pipes", updatedAt: nil),
                    .thinking(
                        "Initial hypothesis: craft an essay on Unix pipes, adhering to a 300-word count while maintaining accuracy and conciseness. This involves ensuring historical correctness and avoiding extraneous content. Will need to draft the essay and subsequently perform a word count.\n\n\n"
                    ),
                    .contextUsage(VitruvianCodeContextUsage(inputTokens: 29_756, cachedTokens: 0, outputTokens: 0, contextWindow: 1_048_576)),
                    .contextUsage(expectedTurnUsage),
                    .finished(
                        status: "cancelled",
                        response: nil,
                        error: nil,
                        conversationID: "49357a68-16cc-4dd7-a56d-95c68b49db39",
                        metrics: VitruvianCodeTurnMetrics(inputTokens: 29_662, outputTokens: 94, cachedTokens: 0, contextUsage: expectedTurnUsage)
                    ),
                ]
            )
        }

        do {
            let events = try await replayFixture(
                named: "agy-resume.ndjson",
                mode: .standard,
                resumeSessionID: "042662ce-2c7a-4915-bc29-f8a57936f8c5",
                promptText: "What backup number did I tell you?"
            )
            let expectedTurnUsage = VitruvianCodeContextUsage(inputTokens: 31_181, cachedTokens: 0, outputTokens: 37, contextWindow: 1_048_576)
            XCTAssertEqual(
                events,
                [
                    .configOptions(expectedInitialConfigOptions),
                    .slashCommands(["compact", "clear", "help"]),
                    .availableCommands(expectedAgyCommands),
                    .sessionInfo(title: "Math Calculation and Favorite Number", updatedAt: nil),
                    .text("The backup number you told"),
                    .text(" me in your first message was 42."),
                    .contextUsage(VitruvianCodeContextUsage(inputTokens: 31_218, cachedTokens: 0, outputTokens: 0, contextWindow: 1_048_576)),
                    .contextUsage(expectedTurnUsage),
                    .finished(
                        status: "completed",
                        response: "The backup number you told me in your first message was 42.",
                        error: nil,
                        conversationID: "042662ce-2c7a-4915-bc29-f8a57936f8c5",
                        metrics: VitruvianCodeTurnMetrics(inputTokens: 31_181, outputTokens: 37, cachedTokens: 0, contextUsage: expectedTurnUsage)
                    ),
                ]
            )
        }
    }

    // MARK: - Group 2: The agy layer

    func testAgyNeverSendsYoloOrAutoEditAcrossEveryApprovalModeAndPlanSwitch() async throws {
        let modeBox = LockedBox<(VitruvianCodeApprovalMode, Bool)>((.yolo, false))

        for mode in VitruvianCodeApprovalMode.allCases {
            for plan in [false, true] {
                let wireMode = AntigravityACPSupport.cliSessionMode(for: mode, planSwitch: plan)
                XCTAssertTrue(wireMode == "default" || wireMode == "plan", "mode=\(mode) plan=\(plan) -> \(wireMode)")
                XCTAssertNotEqual(wireMode, "yolo")
                XCTAssertNotEqual(wireMode, "auto_edit")
            }
        }
        XCTAssertFalse(AntigravityACPSupport.launchArguments().contains("--dangerously-skip-permissions"))
        XCTAssertEqual(AntigravityACPSupport.sanitizedCliSessionMode("yolo"), "default")
        XCTAssertEqual(AntigravityACPSupport.sanitizedCliSessionMode("auto_edit"), "default")
        XCTAssertEqual(AntigravityACPSupport.sanitizedCliSessionMode("plan"), "plan")

        // Verify live wire messages on AntigravityACPConnection never contain `yolo` or `auto_edit`.
        let agent = ScriptedACPAgent()
        let connection = AntigravityACPConnection(
            launchSpec: Self.defaultLaunchSpec,
            modeProvider: { modeBox.value },
            processFactory: agent.makeProcessFactory()
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
                    "result": .object([
                        "sessionId": .string("sess-safe-mode"),
                        "configOptions": .array([
                            .object([
                                "id": .string("mode"),
                                "name": .string("Mode"),
                                "category": .string("mode"),
                                "type": .string("select"),
                                "currentValue": .string("default"),
                                "options": .array([
                                    .object(["value": .string("default"), "name": .string("Default")]),
                                    .object(["value": .string("plan"), "name": .string("Plan")]),
                                    .object(["value": .string("yolo"), "name": .string("YOLO")]),
                                    .object(["value": .string("auto_edit"), "name": .string("Auto Edit")]),
                                ]),
                            ]),
                        ]),
                    ]),
                ])),
                .expectClientRequest(method: "session/set_config_option"),
                .agentSend(.object(["jsonrpc": .string("2.0"), "id": .string("$id"), "result": .object([:])])),
                .expectClientRequest(method: "session/set_config_option"),
                .agentSend(.object(["jsonrpc": .string("2.0"), "id": .string("$id"), "result": .object([:])])),
            ])
        }

        _ = try await withACPTestTimeout(seconds: 3.0) {
            try await connection.start(AgentSessionRequest(workingDirectory: "/workspace"))
        }
        modeBox.withValue { $0 = (.yolo, true) }
        try await withACPTestTimeout(seconds: 3.0) {
            try await connection.syncPlanMode(true)
        }
        modeBox.withValue { $0 = (.yolo, false) }
        _ = try await withACPTestTimeout(seconds: 3.0) {
            try await connection.setConfigOption("mode", .string("yolo"))
        }
        try await withACPTestTimeout(seconds: 3.0) { try await driver.value }

        let allSent = await agent.allClientMessages()
        for msg in allSent {
            let serialized = msg.serializedJSONString()
            XCTAssertFalse(serialized.contains("\"yolo\""), "must never send yolo: \(serialized)")
            XCTAssertFalse(serialized.contains("\"auto_edit\""), "must never send auto_edit: \(serialized)")
        }
        await connection.stop()
    }

    func testSignInUsesOAuthPersonalWhenRequiredAndAuthFailureEmitsAuthFailureKind() async throws {
        // 1. Auth required on session/new -> authenticate("oauth-personal") -> session/new succeeds
        do {
            let agent = ScriptedACPAgent()
            let connection = AntigravityACPConnection(
                launchSpec: Self.defaultLaunchSpec,
                modeProvider: { (.standard, false) },
                processFactory: agent.makeProcessFactory()
            )
            let driver = Task {
                try await agent.playSteps([
                    .expectClientRequest(method: "initialize"),
                    .agentSend(.object([
                        "jsonrpc": .string("2.0"),
                        "id": .string("$id"),
                        "result": .object([
                            "protocolVersion": .int(1),
                            "authMethods": .array([.object(["id": .string("oauth-personal"), "name": .string("Google")])]),
                        ]),
                    ])),
                    .expectClientRequest(method: "session/new"),
                    .agentSend(.object([
                        "jsonrpc": .string("2.0"),
                        "id": .string("$id"),
                        "error": .object(["code": .int(-32000), "message": .string("Authentication required")]),
                    ])),
                    .expectClientRequest(method: "authenticate"),
                    .agentSend(.object(["jsonrpc": .string("2.0"), "id": .string("$id"), "result": .object([:])])),
                    .expectClientRequest(method: "session/new"),
                    .agentSend(.object([
                        "jsonrpc": .string("2.0"),
                        "id": .string("$id"),
                        "result": .object(["sessionId": .string("sess-authed")]),
                    ])),
                ])
            }
            let sessionID = try await withACPTestTimeout(seconds: 3.0) {
                try await connection.start(AgentSessionRequest(workingDirectory: "/workspace"))
            }
            try await withACPTestTimeout(seconds: 3.0) { try await driver.value }
            XCTAssertEqual(sessionID, "sess-authed")

            let authMsg = try await agent.clientMessage(at: 2)
            XCTAssertEqual(authMsg.objectValue?["method"]?.stringValue, "authenticate")
            XCTAssertEqual(authMsg.objectValue?["params"]?.objectValue?["methodId"]?.stringValue, "oauth-personal")
            await connection.stop()
        }

        // 2. authenticate fails -> .connectionFailed(kind: .auth) telling user to run `agy` once
        do {
            let agent = ScriptedACPAgent()
            let connection = AntigravityACPConnection(
                launchSpec: Self.defaultLaunchSpec,
                modeProvider: { (.standard, false) },
                processFactory: agent.makeProcessFactory()
            )
            let reader = ACPEventStreamReader(connection.events)
            let driver = Task {
                try await agent.playSteps([
                    .expectClientRequest(method: "initialize"),
                    .agentSend(.object([
                        "jsonrpc": .string("2.0"),
                        "id": .string("$id"),
                        "result": .object([
                            "protocolVersion": .int(1),
                            "authMethods": .array([.object(["id": .string("oauth-personal"), "name": .string("Google")])]),
                        ]),
                    ])),
                    .expectClientRequest(method: "session/new"),
                    .agentSend(.object([
                        "jsonrpc": .string("2.0"),
                        "id": .string("$id"),
                        "error": .object(["code": .int(-32000), "message": .string("Authentication required")]),
                    ])),
                    .expectClientRequest(method: "authenticate"),
                    .agentSend(.object([
                        "jsonrpc": .string("2.0"),
                        "id": .string("$id"),
                        "error": .object(["code": .int(-32603), "message": .string("sign in cancelled")]),
                    ])),
                ])
            }
            do {
                _ = try await withACPTestTimeout(seconds: 3.0) {
                    try await connection.start(AgentSessionRequest(workingDirectory: "/workspace"))
                }
                XCTFail("Expected start() to fail after authenticate error")
            } catch {}
            try await withACPTestTimeout(seconds: 3.0) { try await driver.value }

            let events = try await reader.collectAllUntilEnd(timeout: 3.0)
            guard let failureEvent = events.first(where: {
                if case .connectionFailed = $0 { return true }
                return false
            }), case .connectionFailed(let failure) = failureEvent else {
                XCTFail("Expected .connectionFailed event, got \(events)")
                return
            }
            XCTAssertEqual(failure.kind, .auth)
            XCTAssertTrue(failure.message.lowercased().contains("agy"), "Expected message instructing user to run agy once, got: \(failure.message)")
        }
    }

    func testResumePreferredWhenAdvertisedAndChildWorkReportsFinishOnTurnEnd() async throws {
        let agent = ScriptedACPAgent()
        let connection = AntigravityACPConnection(
            launchSpec: Self.defaultLaunchSpec,
            modeProvider: { (.standard, false) },
            processFactory: agent.makeProcessFactory()
        )
        let reader = ACPEventStreamReader(connection.events)

        let driver = Task {
            try await agent.playSteps([
                .expectClientRequest(method: "initialize"),
                .agentSend(.object([
                    "jsonrpc": .string("2.0"),
                    "id": .string("$id"),
                    "result": .object([
                        "protocolVersion": .int(1),
                        "agentCapabilities": .object([
                            "loadSession": .bool(true),
                            "sessionCapabilities": .object(["resume": .object([:])]),
                        ]),
                    ]),
                ])),
                .expectClientRequest(method: "session/resume"),
                .agentSend(.object([
                    "jsonrpc": .string("2.0"),
                    "id": .string("$id"),
                    "result": .object(["sessionId": .string("resumed-1")]),
                ])),
                .expectClientRequest(method: "session/prompt"),
                // Non-MCP child work launches subagent
                .agentSend(.object([
                    "jsonrpc": .string("2.0"),
                    "method": .string("session/update"),
                    "params": .object([
                        "sessionId": .string("resumed-1"),
                        "update": .object([
                            "sessionUpdate": .string("tool_call"),
                            "toolCallId": .string("sub-1"),
                            "title": .string("Running invoke_subagent"),
                            "kind": .string("other"),
                            "status": .string("in_progress"),
                            "rawInput": .object([
                                "Subagents": .array([
                                    .object(["Role": .string("Code Reviewer"), "Prompt": .string("Audit diff")]),
                                ]),
                            ]),
                        ]),
                    ]),
                ])),
                // MCP invoke_subagent call must NOT emit `.subagent`
                .agentSend(.object([
                    "jsonrpc": .string("2.0"),
                    "method": .string("session/update"),
                    "params": .object([
                        "sessionId": .string("resumed-1"),
                        "update": .object([
                            "sessionUpdate": .string("tool_call"),
                            "toolCallId": .string("mcp-1"),
                            "title": .string("Running invoke_subagent"),
                            "kind": .string("other"),
                            "status": .string("in_progress"),
                            "_meta": .object(["is_mcp_tool_call": .bool(true)]),
                        ]),
                    ]),
                ])),
                .agentSend(.object([
                    "jsonrpc": .string("2.0"),
                    "id": .string("$id"),
                    "result": .object(["stopReason": .string("end_turn")]),
                ])),
            ])
        }

        let sid = try await withACPTestTimeout(seconds: 3.0) {
            try await connection.start(AgentSessionRequest(workingDirectory: "/workspace", resumeSessionID: "resumed-1"))
        }
        XCTAssertEqual(sid, "resumed-1")
        let stopReason = try await withACPTestTimeout(seconds: 3.0) {
            try await connection.prompt([.text("Run review")])
        }
        XCTAssertEqual(stopReason, .endTurn)
        try await withACPTestTimeout(seconds: 3.0) { try await driver.value }

        let events = try await reader.collectUntilFinished(timeout: 3.0)
        let subagentEvents = events.compactMap { event -> (VitruvianCodeActiveSubagent, Bool)? in
            if case .subagent(let sub, let started) = event {
                return (sub, started)
            }
            return nil
        }
        XCTAssertEqual(subagentEvents.count, 2, "Expected 1 start and 1 turn-end finish, no MCP subagent")
        XCTAssertEqual(subagentEvents[0].0.id, "sub-1")
        XCTAssertEqual(subagentEvents[0].0.role, "Code Reviewer")
        XCTAssertEqual(subagentEvents[0].0.prompt, "Audit diff")
        XCTAssertTrue(subagentEvents[0].1)
        XCTAssertEqual(subagentEvents[1].0.id, "sub-1")
        XCTAssertFalse(subagentEvents[1].0.isRunning)
        XCTAssertFalse(subagentEvents[1].1)

        await connection.stop()
    }

    func testSessionLogWatchMarksUpstreamErrorAndEmitsNoChatEvents() async throws {
        let tempGemini = FileManager.default.temporaryDirectory
            .appendingPathComponent("agy-outcome-\(UUID().uuidString)", isDirectory: true)
        let convDir = tempGemini.appendingPathComponent("antigravity-acp/conversations", isDirectory: true)
        try FileManager.default.createDirectory(at: convDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempGemini) }

        let sessionID = "sess-watch-1"
        let dbPath = convDir.appendingPathComponent("\(sessionID).db").path
        try createStepsDB(at: dbPath, initialSteps: [
            (0, 14, "Hello"),
            (1, 15, "World"),
        ])

        let agent = ScriptedACPAgent()
        let connection = AntigravityACPConnection(
            launchSpec: Self.defaultLaunchSpec,
            modeProvider: { (.standard, false) },
            geminiHomeDirectory: tempGemini.path,
            processFactory: agent.makeProcessFactory()
        )
        let reader = ACPEventStreamReader(connection.events)

        let initTask = Task {
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
                    "result": .object(["sessionId": .string(sessionID)]),
                ])),
            ])
        }
        _ = try await withACPTestTimeout(seconds: 3.0) {
            try await connection.start(AgentSessionRequest(workingDirectory: "/workspace"))
        }
        try await withACPTestTimeout(seconds: 3.0) { try await initTask.value }

        // Turn 1 ends with QUOTA_EXHAUSTED in SQLite step_type 17 while agent claims `end_turn`
        let turn1Task = Task {
            let promptMsg = try await agent.clientMessage(at: 2)
            XCTAssertEqual(promptMsg.objectValue?["method"]?.stringValue, "session/prompt")
            let rid = promptMsg.objectValue?["id"] ?? .int(3)
            try insertErrorStep(
                at: dbPath,
                idx: 2,
                payload: "Agent execution terminated due to error. reason:QUOTA_EXHAUSTED quotaResetDelay:3600s"
            )
            try await agent.sendToClient(.object([
                "jsonrpc": .string("2.0"),
                "id": rid,
                "result": .object(["stopReason": .string("end_turn")]),
            ]))
        }
        let reason1 = try await withACPTestTimeout(seconds: 5.0) {
            try await connection.prompt([.text("Turn 1")])
        }
        try await withACPTestTimeout(seconds: 3.0) { try await turn1Task.value }
        XCTAssertEqual(reason1, .error)

        let events1 = try await reader.collectUntilFinished(timeout: 3.0)
        // Only the `.finished(status: "error", ...)` event should arrive — no `.text` or `.thinking` from the DB!
        XCTAssertEqual(events1.count, 1)
        if case .finished(let status, let response, let error, _, _) = events1[0] {
            XCTAssertEqual(status, "error")
            XCTAssertNil(response)
            XCTAssertEqual(error, AntigravityTurnOutcome.quotaExhaustedMessage)
        } else {
            XCTFail("Expected .finished error event, got \(events1)")
        }

        // Turn 2 adds an ordinary planner response after the earlier error step -> succeeds cleanly.
        let turn2Task = Task {
            let promptMsg = try await agent.clientMessage(at: 3)
            let rid = promptMsg.objectValue?["id"] ?? .int(4)
            try insertPlannerStep(at: dbPath, idx: 3, payload: "OK now")
            try await agent.sendToClient(.object([
                "jsonrpc": .string("2.0"),
                "id": rid,
                "result": .object(["stopReason": .string("end_turn")]),
            ]))
        }
        let reason2 = try await withACPTestTimeout(seconds: 5.0) {
            try await connection.prompt([.text("Turn 2")])
        }
        try await withACPTestTimeout(seconds: 3.0) { try await turn2Task.value }
        XCTAssertEqual(reason2, .endTurn)

        await connection.stop()
    }

    func testSilentPromptTimerFiresAfterTimeoutAndPausesDuringToolsAndApprovals() async throws {
        // 1. Fires when completely silent
        do {
            let agent = ScriptedACPAgent()
            let connection = AntigravityACPConnection(
                launchSpec: Self.defaultLaunchSpec,
                modeProvider: { (.standard, false) },
                promptInactivityTimeout: 0.06,
                processFactory: agent.makeProcessFactory()
            )
            let reader = ACPEventStreamReader(connection.events)
            let driver = Task {
                try await agent.playSteps([
                    .expectClientRequest(method: "initialize"),
                    .agentSend(.object(["jsonrpc": .string("2.0"), "id": .string("$id"), "result": .object(["protocolVersion": .int(1)])])),
                    .expectClientRequest(method: "session/new"),
                    .agentSend(.object(["jsonrpc": .string("2.0"), "id": .string("$id"), "result": .object(["sessionId": .string("sess-quiet")])])),
                ])
                let promptMsg = try await agent.clientMessage(at: 2)
                let promptID = promptMsg.objectValue?["id"] ?? .int(3)
                let cancelMsg = try await agent.clientMessage(at: 3, timeout: 3.0)
                XCTAssertEqual(cancelMsg.objectValue?["method"]?.stringValue, "session/cancel")
                try await agent.sendToClient(.object([
                    "jsonrpc": .string("2.0"),
                    "id": promptID,
                    "result": .object(["stopReason": .string("cancelled")]),
                ]))
            }
            _ = try await withACPTestTimeout(seconds: 3.0) {
                try await connection.start(AgentSessionRequest(workingDirectory: "/workspace"))
            }
            let reason = try await withACPTestTimeout(seconds: 3.0) {
                try await connection.prompt([.text("Hang silently")])
            }
            try await withACPTestTimeout(seconds: 3.0) { try await driver.value }
            XCTAssertEqual(reason, .error)
            let events = try await reader.collectUntilFinished(timeout: 3.0)
            guard case .finished(let status, _, let error, _, _) = events.last else {
                XCTFail("Expected .finished"); return
            }
            XCTAssertEqual(status, "error")
            XCTAssertNotNil(error)
            await connection.stop()
        }

        // 2. Pauses while a tool is running AND while an approval waits (never auto-denies), then resumes
        do {
            let agent = ScriptedACPAgent()
            let connection = AntigravityACPConnection(
                launchSpec: Self.defaultLaunchSpec,
                modeProvider: { (.standard, false) },
                promptInactivityTimeout: 0.06,
                processFactory: agent.makeProcessFactory()
            )
            let reader = ACPEventStreamReader(connection.events)
            let startTask = Task {
                try await agent.playSteps([
                    .expectClientRequest(method: "initialize"),
                    .agentSend(.object(["jsonrpc": .string("2.0"), "id": .string("$id"), "result": .object(["protocolVersion": .int(1)])])),
                    .expectClientRequest(method: "session/new"),
                    .agentSend(.object(["jsonrpc": .string("2.0"), "id": .string("$id"), "result": .object(["sessionId": .string("sess-pause")])])),
                ])
            }
            _ = try await withACPTestTimeout(seconds: 3.0) {
                try await connection.start(AgentSessionRequest(workingDirectory: "/workspace"))
            }
            try await withACPTestTimeout(seconds: 3.0) { try await startTask.value }

            let promptTask = Task {
                try await connection.prompt([.text("Slow tool then approval")])
            }
            let promptMsg = try await agent.clientMessage(at: 2, timeout: 3.0)
            let promptID = promptMsg.objectValue?["id"] ?? .int(3)

            // Start long tool -> sleep 2.5x timeout -> timer must NOT have fired!
            try await agent.sendToClient(.object([
                "jsonrpc": .string("2.0"),
                "method": .string("session/update"),
                "params": .object([
                    "sessionId": .string("sess-pause"),
                    "update": .object([
                        "sessionUpdate": .string("tool_call"),
                        "toolCallId": .string("t-slow"),
                        "title": .string("Slow build"),
                        "kind": .string("execute"),
                        "status": .string("in_progress"),
                    ]),
                ]),
            ]))
            try await Task.sleep(nanoseconds: 150_000_000)
            let sentDuringTool = await agent.allClientMessages()
            XCTAssertEqual(sentDuringTool.count, 3, "Inactivity timer must pause while tool call runs")

            // Tool completes, then approval arrives -> sleep 2.5x timeout -> timer must pause and NEVER auto-deny
            try await agent.sendToClient(.object([
                "jsonrpc": .string("2.0"),
                "method": .string("session/update"),
                "params": .object([
                    "sessionId": .string("sess-pause"),
                    "update": .object([
                        "sessionUpdate": .string("tool_call_update"),
                        "toolCallId": .string("t-slow"),
                        "status": .string("completed"),
                    ]),
                ]),
            ]))
            try await agent.sendToClient(.object([
                "jsonrpc": .string("2.0"),
                "id": .string("perm-wait"),
                "method": .string("session/request_permission"),
                "params": .object([
                    "sessionId": .string("sess-pause"),
                    "toolCall": .object(["toolCallId": .string("t-exec"), "title": .string("Run rm"), "kind": .string("execute")]),
                    "options": .array([
                        .object(["optionId": .string("allow_once"), "name": .string("Allow"), "kind": .string("allow_once")]),
                        .object(["optionId": .string("reject_once"), "name": .string("Deny"), "kind": .string("reject_once")]),
                    ]),
                ]),
            ]))

            try await Task.sleep(nanoseconds: 150_000_000)
            let sentDuringApproval = await agent.allClientMessages()
            XCTAssertEqual(sentDuringApproval.count, 3, "Timer must pause while approval waits and never auto-deny")

            // User approves -> tool continues -> agent then goes silent -> timer resumes and fires session/cancel!
            try await withACPTestTimeout(seconds: 3.0) {
                try await connection.answer("perm-1", .option("allow_once"))
            }
            let approvalResponse = try await agent.clientMessage(at: 3, timeout: 3.0)
            XCTAssertEqual(
                approvalResponse.objectValue?["result"]?.objectValue?["outcome"]?.objectValue?["optionId"]?.stringValue,
                "allow_once"
            )

            let cancelAfterResume = try await agent.clientMessage(at: 4, timeout: 3.0)
            XCTAssertEqual(cancelAfterResume.objectValue?["method"]?.stringValue, "session/cancel")
            try await agent.sendToClient(.object([
                "jsonrpc": .string("2.0"),
                "id": promptID,
                "result": .object(["stopReason": .string("cancelled")]),
            ]))

            let reason = try await withACPTestTimeout(seconds: 3.0) { try await promptTask.value }
            XCTAssertEqual(reason, .error)
            _ = try await reader.collectUntilFinished(timeout: 3.0)
            await connection.stop()
        }
    }

    func testVersionRulesForQualifiedAndUnqualifiedReleasesIncludingRunWorkflow() {
        // Qualified 1.4.5
        XCTAssertTrue(AntigravityACPSupport.isQualifiedRelease(version: "1.4.5"))
        XCTAssertTrue(AntigravityACPSupport.writesRunWorkflowSkill(version: "1.4.5"))
        XCTAssertEqual(AntigravityACPSupport.disabledTools(version: "1.4.5"), ["run_workflow"])
        XCTAssertTrue(AntigravityACPSupport.appendsSystemPrompt(version: "1.4.5"))
        XCTAssertTrue(AntigravityACPSupport.reportsPerTurnPromptUsage(version: "1.4.5"))
        XCTAssertFalse(AntigravityACPSupport.needsReadRepair(version: "1.4.5"))
        XCTAssertFalse(AntigravityACPSupport.hasOpenModelAccess(version: "1.4.5"))
        XCTAssertEqual(AntigravityACPSupport.clientInfo(version: "1.4.5").name, "zed")
        XCTAssertEqual(
            AntigravityACPSupport.sessionMeta(version: "1.4.5", systemPromptAppend: "Rules"),
            [
                "antigravity": .object([
                    "disabledTools": .array([.string("run_workflow")]),
                    "systemPrompt": .object(["append": .string("Rules")]),
                ]),
            ]
        )

        // Unqualified 1.4.4 (`run_workflow` still disabled, no systemPrompt append unless advertised, needs ReadRepair)
        XCTAssertFalse(AntigravityACPSupport.isQualifiedRelease(version: "1.4.4"))
        XCTAssertTrue(AntigravityACPSupport.writesRunWorkflowSkill(version: "1.4.4"))
        XCTAssertEqual(AntigravityACPSupport.disabledTools(version: "1.4.4"), ["run_workflow"])
        XCTAssertFalse(AntigravityACPSupport.appendsSystemPrompt(version: "1.4.4"))
        XCTAssertTrue(AntigravityACPSupport.needsReadRepair(version: "1.4.4"))

        // Earlier 1.4.1 (no usage, no run_workflow block) and 1.5.10 (open models, reports usage, no run_workflow block)
        XCTAssertFalse(AntigravityACPSupport.writesRunWorkflowSkill(version: "1.4.1"))
        XCTAssertEqual(AntigravityACPSupport.disabledTools(version: "1.4.1"), [])
        XCTAssertFalse(AntigravityACPSupport.reportsPerTurnPromptUsage(version: "1.4.1"))
        XCTAssertEqual(AntigravityACPSupport.supportedModels(version: "1.4.1"), AntigravityACPSupport.allowlistedLegacyModels)

        XCTAssertFalse(AntigravityACPSupport.writesRunWorkflowSkill(version: "1.5.10"))
        XCTAssertTrue(AntigravityACPSupport.hasOpenModelAccess(version: "1.5.10"))
        XCTAssertEqual(AntigravityACPSupport.clientInfo(version: "1.5.10").name, "vitruvian-code")
        XCTAssertTrue(AntigravityACPSupport.reportsPerTurnPromptUsage(version: "1.5.10"))
        XCTAssertEqual(AntigravityACPSupport.supportedModels(version: "1.5.10"), AntigravityACPSupport.openAccessModelFamilies)

        let attachments = AntigravityACPSupport.attachmentsDirectory(stateDirectory: "/tmp/state")
        XCTAssertEqual(attachments, "/tmp/state/attachments")
        XCTAssertEqual(AntigravityACPSupport.additionalDirectories(attachmentsDirectory: attachments), ["/tmp/state/attachments"])
    }

    // MARK: - Group 3: The session

    func testOneConnectionServesTwoTurnsAndModeChangeAppliesWithoutRestart() async throws {
        let connections = LockedBox<[MockPersistentConnection]>([])
        var modeSnapshots: [(VitruvianCodeApprovalMode, Bool)] = []
        let env = makeSessionEnvironment(makeConnection: { spec in
            let conn = MockPersistentConnection(spec: spec)
            connections.withValue { $0.append(conn) }
            return conn
        })
        let host = MockSessionHost()
        let session = VitruvianCodeQuickPromptSession(environment: env, host: host)
        session.takeCheckpoint = { _ in nil }
        let config = VitruvianCodeConfiguration(approvalMode: .standard, activeProvider: Self.agyACPProvider)

        // Turn 1
        session.send("Turn one", configuration: config, agentPath: "/fake/agy")
        try await waitUntil("turn 1 prompt arrives") {
            connections.value.first?.promptCalls.count == 1
        }
        let conn = try XCTUnwrap(connections.value.first)
        if let provider = conn.spec.liveModeProvider {
            modeSnapshots.append(provider())
        }
        conn.emit(.text("Reply 1"))
        conn.emit(.finished(status: "completed", response: "Reply 1", error: nil, conversationID: "conv-persistent"))
        conn.finishPrompt(with: .endTurn)
        try await waitUntil("turn 1 ends") { !session.isRunning }
        XCTAssertEqual(session.conversationID, "conv-persistent")
        XCTAssertEqual(conn.startCalls.count, 1)

        // Change approval mode + toggle plan switch between turns -> applies with zero restart
        session.chatApprovalMode = .yolo
        session.planMode = true
        if let provider = conn.spec.liveModeProvider {
            modeSnapshots.append(provider())
        }

        // Turn 2
        session.send("Turn two", configuration: config, agentPath: "/fake/agy")
        try await waitUntil("turn 2 prompt arrives") {
            conn.promptCalls.count == 2
        }
        XCTAssertEqual(connections.value.count, 1, "must reuse single connection")
        XCTAssertEqual(conn.startCalls.count, 1, "mode change must not restart connection")
        XCTAssertEqual(conn.syncedPlanModes, [false, true])
        XCTAssertEqual(modeSnapshots[0].0, .standard)
        XCTAssertEqual(modeSnapshots[0].1, false)
        XCTAssertEqual(modeSnapshots[1].0, .yolo)
        XCTAssertEqual(modeSnapshots[1].1, true)

        conn.emit(.text("Reply 2"))
        conn.emit(.finished(status: "completed", response: "Reply 2", error: nil, conversationID: "conv-persistent"))
        conn.finishPrompt(with: .endTurn)
        try await waitUntil("turn 2 ends") { !session.isRunning }
        XCTAssertEqual(conn.stopCount, 0)
    }

    func testStopCancelsTurnWithoutClosingAndNewChatOrSwitchChatStopsConnection() async throws {
        let connections = LockedBox<[MockPersistentConnection]>([])
        let env = makeSessionEnvironment(makeConnection: { spec in
            let conn = MockPersistentConnection(spec: spec)
            connections.withValue { $0.append(conn) }
            return conn
        })
        let session = VitruvianCodeQuickPromptSession(environment: env, host: MockSessionHost())
        session.takeCheckpoint = { _ in nil }
        let config = VitruvianCodeConfiguration(approvalMode: .standard, activeProvider: Self.agyACPProvider)

        session.send("Long run", configuration: config, agentPath: "/fake/agy")
        try await waitUntil("prompt 1 started") { connections.value.first?.promptCalls.count == 1 }
        let conn = try XCTUnwrap(connections.value.first)

        session.stop()
        try await waitUntil("cancel called") { conn.cancelCount == 1 }
        XCTAssertEqual(conn.stopCount, 0, "Stop button must cancel, keeping connection open")
        conn.emit(.finished(status: "cancelled", response: nil, error: nil, conversationID: "sess-1"))
        conn.finishPrompt(with: .cancelled)
        try await waitUntil("turn finished after stop") { !session.isRunning }

        // Next prompt reuses the same open connection
        session.send("Follow-up", configuration: config, agentPath: "/fake/agy")
        try await waitUntil("prompt 2 started") { conn.promptCalls.count == 2 }
        XCTAssertEqual(connections.value.count, 1)
        conn.emit(.finished(status: "completed", response: "OK", error: nil, conversationID: "sess-1"))
        conn.finishPrompt(with: .endTurn)
        try await waitUntil("turn 2 finished") { !session.isRunning }

        // New chat stops the connection
        session.newChat()
        try await waitUntil("stop called on newChat") { conn.stopCount == 1 }

        // Start a second connection, then switching chat (`resume`) stops it too
        session.send("Chat B", configuration: config, agentPath: "/fake/agy")
        try await waitUntil("second connection started") { connections.value.count == 2 && connections.value[1].promptCalls.count == 1 }
        let connB = connections.value[1]
        connB.emit(.finished(status: "completed", response: "B", error: nil, conversationID: "sess-b"))
        connB.finishPrompt(with: .endTurn)
        try await waitUntil("chat B done") { !session.isRunning }

        session.resume(VitruvianCodeSessionSummary(id: "sess-other", title: "Other", preview: "Hi", steps: 1, modified: nil), configuration: config)
        try await waitUntil("stop called on resume") { connB.stopCount == 1 }
    }

    func testIdleShutdownStopsConnectionAndNextPromptRestartsWithResumeID() async throws {
        let connections = LockedBox<[MockPersistentConnection]>([])
        let env = makeSessionEnvironment(makeConnection: { spec in
            let conn = MockPersistentConnection(spec: spec)
            connections.withValue { $0.append(conn) }
            return conn
        })
        let session = VitruvianCodeQuickPromptSession(environment: env, host: MockSessionHost())
        session.takeCheckpoint = { _ in nil }
        session.idleConnectionTimeout = 0.06
        let config = VitruvianCodeConfiguration(approvalMode: .standard, activeProvider: Self.agyACPProvider)

        session.send("First", configuration: config, agentPath: "/fake/agy")
        try await waitUntil("turn 1 started") { connections.value.first?.promptCalls.count == 1 }
        let conn1 = connections.value[0]
        conn1.emit(.started(conversationID: "conv-idle-42"))
        conn1.emit(.finished(status: "completed", response: "Done", error: nil, conversationID: "conv-idle-42"))
        conn1.finishPrompt(with: .endTurn)
        try await waitUntil("idle shutdown stops conn1") { conn1.stopCount == 1 }

        session.send("After idle", configuration: config, agentPath: "/fake/agy")
        try await waitUntil("conn2 starts") { connections.value.count == 2 && connections.value[1].startCalls.count == 1 }
        let conn2 = connections.value[1]
        XCTAssertEqual(conn2.startCalls.first?.resumeSessionID, "conv-idle-42")
        conn2.emit(.finished(status: "completed", response: "Resumed", error: nil, conversationID: "conv-idle-42"))
        conn2.finishPrompt(with: .endTurn)
        try await waitUntil("turn 2 done") { !session.isRunning }
    }

    func testCrashRecoveryRestartsAndStopsRetryingAfterThreeFailedRestarts() async throws {
        let connections = LockedBox<[MockPersistentConnection]>([])
        var failStarts = false
        let env = makeSessionEnvironment(makeConnection: { spec in
            let conn = MockPersistentConnection(spec: spec, failStart: failStarts)
            connections.withValue { $0.append(conn) }
            return conn
        })
        let session = VitruvianCodeQuickPromptSession(environment: env, host: MockSessionHost())
        session.takeCheckpoint = { _ in nil }
        let config = VitruvianCodeConfiguration(approvalMode: .standard, activeProvider: Self.agyACPProvider)

        // Initial turn has pending approval when process crashes
        session.send("Start", configuration: config, agentPath: "/fake/agy")
        try await waitUntil("turn 1 prompt") { connections.value.first?.promptCalls.count == 1 }
        let conn1 = connections.value[0]
        conn1.emit(.started(conversationID: "conv-crash"))
        conn1.emit(.approval(VitruvianCodeApprovalRequest(id: "p1", toolName: "bash", commandOrPath: "ls", requestID: "req-1")))
        try await waitUntil("approval pending") { session.hasPendingApproval }

        // Simulate crash
        conn1.emit(.connectionFailed(AgentFailure(kind: .exited, message: "Process crashed")))
        conn1.emit(.finished(status: "error", response: nil, error: "Process crashed", conversationID: "conv-crash"))
        conn1.simulateStreamEndAndPromptError()
        try await waitUntil("crash handled and approval cancelled") { !session.isRunning && !session.hasPendingApproval }

        // Now force restarts to fail 3 times in a row
        failStarts = true
        for attempt in 1...3 {
            session.send("Retry \(attempt)", configuration: config, agentPath: "/fake/agy")
            try await waitUntil("failed attempt \(attempt)") {
                session.consecutiveRestartFailures == attempt && !session.isRunning
            }
        }
        XCTAssertTrue(session.isConnectionLockedAfterFailures)
        let countAtLockout = connections.value.count

        // 4th attempt must NOT spawn another connection or call start()
        session.send("Blocked 4th", configuration: config, agentPath: "/fake/agy")
        XCTAssertEqual(connections.value.count, countAtLockout)
        XCTAssertEqual(session.messages.last?.isError, true)

        // New chat resets lockout
        failStarts = false
        session.newChat()
        XCTAssertFalse(session.isConnectionLockedAfterFailures)
        session.send("Fresh after newChat", configuration: config, agentPath: "/fake/agy")
        try await waitUntil("fresh turn restarts") { connections.value.count == countAtLockout + 1 && !session.isRunning == false }
        let fresh = try XCTUnwrap(connections.value.last)
        fresh.emit(.finished(status: "completed", response: "OK", error: nil, conversationID: "fresh-id"))
        fresh.finishPrompt(with: .endTurn)
        try await waitUntil("fresh done") { !session.isRunning }
    }

    func testInterimApprovalOptionMappingQuestionHandlingSubagentFollowerAndMakeConnection() async throws {
        // 1. Approval option mapping (full options, fallback in same direction, missing direction, legacy empty)
        let fullOptions = [
            AgentPermissionOption(id: "opt-once", name: "Once", kind: .allowOnce),
            AgentPermissionOption(id: "opt-always", name: "Always", kind: .allowAlways),
            AgentPermissionOption(id: "opt-deny", name: "Deny", kind: .rejectOnce),
        ]
        XCTAssertEqual(VitruvianCodeQuickPromptSession.approvalAnswer(for: fullOptions, decision: .approved), .option("opt-once"))
        XCTAssertEqual(VitruvianCodeQuickPromptSession.approvalAnswer(for: fullOptions, decision: .sessionAllowed), .option("opt-always"))
        XCTAssertEqual(VitruvianCodeQuickPromptSession.approvalAnswer(for: fullOptions, decision: .denied), .option("opt-deny"))

        let fallbackOptions = [
            AgentPermissionOption(id: "opt-always-only", name: "Always", kind: .allowAlways),
            AgentPermissionOption(id: "opt-reject-always", name: "Reject always", kind: .rejectAlways),
        ]
        XCTAssertEqual(VitruvianCodeQuickPromptSession.approvalAnswer(for: fallbackOptions, decision: .approved), .option("opt-always-only"))
        XCTAssertEqual(VitruvianCodeQuickPromptSession.approvalAnswer(for: fallbackOptions, decision: .denied), .option("opt-reject-always"))
        XCTAssertEqual(VitruvianCodeQuickPromptSession.approvalAnswer(for: [], decision: .approved), .option("allow"))
        XCTAssertEqual(VitruvianCodeQuickPromptSession.approvalAnswer(for: [], decision: .denied), .cancelled)

        // End-to-end approval buttons + `.question` form handling through session
        let connections = LockedBox<[MockPersistentConnection]>([])
        let env = makeSessionEnvironment(makeConnection: { spec in
            let conn = MockPersistentConnection(spec: spec)
            connections.withValue { $0.append(conn) }
            return conn
        })
        let sessionHost = MockSessionHost()
        let session = VitruvianCodeQuickPromptSession(environment: env, host: sessionHost)
        session.takeCheckpoint = { _ in nil }
        let config = VitruvianCodeConfiguration(approvalMode: .standard, activeProvider: Self.agyACPProvider)

        session.send("Ask and run", configuration: config, agentPath: "/fake/agy")
        try await waitUntil("prompt started") { connections.value.first?.promptCalls.count == 1 }
        let conn = connections.value[0]

        conn.emit(.question(AgentQuestion(
            requestID: "q-1",
            title: "Question",
            message: "Pick a branch",
            fields: [AgentQuestion.Field(id: "f1", type: .choice, label: "Pick a branch", options: [.init(value: "main", label: "main")])]
        )))
        try await waitUntil("question card visible") {
            session.hasPendingApproval && session.messages.contains { $0.question?.requestID == "q-1" && $0.questionStatus == .pending }
        }
        XCTAssertTrue(conn.answers.isEmpty)
        let qMsg = try XCTUnwrap(session.messages.first(where: { $0.question?.requestID == "q-1" }))
        session.answerQuestion(messageID: qMsg.id, answers: ["f1": "main"])
        try await waitUntil("question answer sent") {
            conn.answers.contains(where: { $0.0 == "q-1" && $0.1 == .form(["f1": "main"]) })
        }
        XCTAssertFalse(session.hasPendingApproval)

        conn.emit(.approval(VitruvianCodeApprovalRequest(id: "a1", toolName: "bash", commandOrPath: "ls", requestID: "p-1", options: fullOptions)))
        try await waitUntil("approval card visible") { session.hasPendingApproval }
        XCTAssertEqual(sessionHost.approvals.count, 2)
        let cardMsg = try XCTUnwrap(session.messages.first(where: { $0.approvalRequest?.requestID == "p-1" }))
        session.decideApproval(messageID: cardMsg.id, decision: .sessionAllowed)
        try await waitUntil("allow_always answer sent") {
            conn.answers.contains(where: { $0.0 == "p-1" && $0.1 == .option("opt-always") })
        }
        conn.emit(.finished(status: "completed", response: "OK", error: nil, conversationID: "sess-q"))
        conn.finishPrompt(with: .endTurn)
        try await waitUntil("done") { !session.isRunning }

        // 2. Transcript follower in `.subagentsOnly` mode updates activeSubagents and adds no messages
        var loadableTranscript: [VitruvianCodeChatMessage]?
        let fakeTranscriptPath = "/tmp/nonexistent-follower-\(UUID().uuidString).jsonl"
        let followerEnv = makeSessionEnvironment(
            makeConnection: { MockPersistentConnection(spec: $0) },
            transcriptPath: { _, _ in fakeTranscriptPath },
            readTranscriptRaw: { _, _ in
                #"{"type":"PLANNER_RESPONSE","tool_calls":[{"name":"invoke_subagent","args":{"Subagents":[{"Role":"Helper","Prompt":"Help"}]}}]}"#
            },
            readTranscript: { _, _ in loadableTranscript }
        )
        let followerSession = VitruvianCodeQuickPromptSession(environment: followerEnv, host: MockSessionHost())
        followerSession.resume(
            VitruvianCodeSessionSummary(id: "conv-follower", title: "Follower", preview: "Hi", steps: 1, modified: nil),
            configuration: config
        )
        XCTAssertEqual(followerSession.transcriptFollowerMode, .subagentsOnly)
        let beforeMessages = followerSession.messages
        loadableTranscript = beforeMessages + [VitruvianCodeChatMessage(role: .agent, text: "SHOULD_NOT_BE_ADDED")]
        followerSession.checkTranscriptUpdates()
        XCTAssertEqual(followerSession.messages, beforeMessages, "subagentsOnly mode must add zero chat messages")
        XCTAssertEqual(followerSession.activeSubagents.map(\.role), ["Helper"])
        followerSession.stopTranscriptFollower()

        // 3. `Environment.makeConnection` picks AntigravityACPConnection iff agy + .acp
        let defaultEnv = VitruvianCodeEngine.Environment.live
        let agyACPSpec = AgentConnectionSpec(provider: Self.agyACPProvider, workingDirectory: "/workspace")
        XCTAssertTrue(defaultEnv.makeConnection(agyACPSpec) is AntigravityACPConnection)

        let agyNilProvider = VitruvianCodeCLIProvider.antigravity
        XCTAssertTrue(defaultEnv.makeConnection(AgentConnectionSpec(provider: agyNilProvider, workingDirectory: "/workspace")) is CommandLineConnection)

        var agyCLIProvider = VitruvianCodeCLIProvider.antigravity
        agyCLIProvider.connection = .commandLine
        XCTAssertTrue(defaultEnv.makeConnection(AgentConnectionSpec(provider: agyCLIProvider, workingDirectory: "/workspace")) is CommandLineConnection)
        XCTAssertTrue(defaultEnv.makeConnection(AgentConnectionSpec(provider: .claude, workingDirectory: "/workspace")) is CommandLineConnection)
    }

    func testAClaudeSDKChatDoesNotFollowItsTranscriptAndOtherClaudeChatsStillDo() throws {
        let env = makeSessionEnvironment(
            makeConnection: { MockPersistentConnection(spec: $0) },
            transcriptPath: { _, _ in "/tmp/nonexistent-follower-\(UUID().uuidString).jsonl" },
            readTranscriptRaw: { _, _ in "{}" }
        )
        let summary = VitruvianCodeSessionSummary(id: "conv-sdk", title: "SDK", preview: "Hi", steps: 1, modified: nil)

        var sdk = VitruvianCodeCLIProvider.claude
        sdk.connection = .claudeSDK
        let sdkSession = VitruvianCodeQuickPromptSession(environment: env, host: MockSessionHost())
        sdkSession.resume(summary, configuration: VitruvianCodeConfiguration(activeProvider: sdk))
        XCTAssertFalse(sdkSession.isFollowerActive, "the SDK's events are the chat; its transcript would show each message twice")
        sdkSession.startTranscriptFollower(provider: sdk)
        XCTAssertFalse(sdkSession.isFollowerActive, "starting it again does not start it")

        // Nothing changes for a Claude chat on the command line.
        let cliSession = VitruvianCodeQuickPromptSession(environment: env, host: MockSessionHost())
        cliSession.resume(summary, configuration: VitruvianCodeConfiguration(activeProvider: .claude))
        XCTAssertTrue(cliSession.isFollowerActive)
        XCTAssertEqual(cliSession.transcriptFollowerMode, .full)
        cliSession.stopTranscriptFollower()
    }

    // MARK: - Group 4: Round 1 QA defect fixes

    func testWorktreeModeCreatesWorktreeFirstAndLaunchesAgyWithWorktreeAsProcessAndSessionCwd() async throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("agy-worktree-first-\(UUID().uuidString)", isDirectory: true)
        let repoDir = tempRoot.appendingPathComponent("repo", isDirectory: true)
        try FileManager.default.createDirectory(at: repoDir.appendingPathComponent(".git"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let expectedWorktree = tempRoot.appendingPathComponent("repo-worktrees/antigravity-cli-chat-1", isDirectory: true).path
        let order = LockedBox<[String]>([])
        let createdConnections = LockedBox<[AntigravityACPConnection]>([])
        let agents = LockedBox<[ScriptedACPAgent]>([])

        let env = makeSessionEnvironment(
            makeConnection: { spec in
                order.withValue { $0.append("makeConnection:\(spec.workingDirectory)") }
                let agent = ScriptedACPAgent()
                agents.withValue { $0.append(agent) }
                let conn = AntigravityACPConnection(
                    launchSpec: AgentProcessLaunchSpec(
                        executable: "/fake/agy",
                        arguments: ["acp"],
                        environment: spec.environment,
                        workingDirectory: spec.workingDirectory
                    ),
                    modeProvider: spec.liveModeProvider ?? { (.standard, false) },
                    processFactory: agent.makeProcessFactory()
                )
                createdConnections.withValue { $0.append(conn) }
                return conn
            },
            runProgram: { name, args in
                if name == "git", args.contains("worktree"), args.contains("add"), let pathArg = args.drop(while: { $0 != expectedWorktree }).first {
                    try? FileManager.default.createDirectory(atPath: pathArg, withIntermediateDirectories: true)
                    order.withValue { $0.append("createWorktree:\(pathArg)") }
                    return ""
                }
                return nil
            }
        )

        let session = VitruvianCodeQuickPromptSession(environment: env, host: MockSessionHost())
        session.takeCheckpoint = { _ in nil }
        session.worktreeMode = true
        let config = VitruvianCodeConfiguration(
            workingDirectory: repoDir.path,
            approvalMode: .standard,
            activeProvider: Self.agyACPProvider
        )

        session.send("Inspect worktree", configuration: config, agentPath: "/fake/agy")
        try await waitUntil("worktree created and ACP connection started") {
            createdConnections.value.count == 1 && agents.value.count == 1
        }
        let agent = agents.value[0]
        let conn = createdConnections.value[0]

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
                    "result": .object(["sessionId": .string("sess-wt-1")]),
                ])),
                .expectClientRequest(method: "session/prompt"),
                .agentSend(.object([
                    "jsonrpc": .string("2.0"),
                    "id": .string("$id"),
                    "result": .object(["stopReason": .string("end_turn")]),
                ])),
            ])
        }

        try await withACPTestTimeout(seconds: 3.0) { try await driver.value }
        try await waitUntil("turn ends") { !session.isRunning }

        XCTAssertEqual(
            order.value,
            ["createWorktree:\(expectedWorktree)", "makeConnection:\(expectedWorktree)"],
            "worktree must be created BEFORE makeConnection so process cwd uses the worktree"
        )
        let launchSpec = await agent.launchSpec()
        XCTAssertEqual(launchSpec?.workingDirectory, expectedWorktree, "process cwd must be the worktree")
        XCTAssertEqual(conn.launchSpecUsed.workingDirectory, expectedWorktree)
        let newReq = try await agent.clientMessage(at: 1)
        XCTAssertEqual(newReq.objectValue?["method"]?.stringValue, "session/new")
        XCTAssertEqual(
            newReq.objectValue?["params"]?.objectValue?["cwd"]?.stringValue,
            expectedWorktree,
            "session/new cwd must also be the worktree"
        )
        await session.stopAll()
    }

    func testWorktreePreservedAcrossIdleShutdownAndCrashRestartAndClearedOnNewOrSwitchedChat() async throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("agy-worktree-keep-\(UUID().uuidString)", isDirectory: true)
        let repoDir = tempRoot.appendingPathComponent("repo", isDirectory: true)
        try FileManager.default.createDirectory(at: repoDir.appendingPathComponent(".git"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let expectedWorktree = tempRoot.appendingPathComponent("repo-worktrees/antigravity-cli-chat-1", isDirectory: true).path
        let gitWorktreeAddCount = LockedBox(0)
        let connections = LockedBox<[MockPersistentConnection]>([])

        let env = makeSessionEnvironment(
            makeConnection: { spec in
                let conn = MockPersistentConnection(spec: spec)
                connections.withValue { $0.append(conn) }
                return conn
            },
            runProgram: { name, args in
                if name == "git", args.contains("worktree"), args.contains("add") {
                    gitWorktreeAddCount.withValue { $0 += 1 }
                    if let pathArg = args.last(where: { $0.contains("repo-worktrees") }) {
                        try? FileManager.default.createDirectory(atPath: pathArg, withIntermediateDirectories: true)
                    }
                    return ""
                }
                return nil
            }
        )

        let session = VitruvianCodeQuickPromptSession(environment: env, host: MockSessionHost())
        session.takeCheckpoint = { _ in nil }
        session.idleConnectionTimeout = 0.05
        session.worktreeMode = true
        let config = VitruvianCodeConfiguration(
            workingDirectory: repoDir.path,
            approvalMode: .standard,
            activeProvider: Self.agyACPProvider
        )

        // Turn 1 creates worktree and finishes -> idle shutdown stops conn1 but keeps liveWorktreePath
        session.send("Turn 1", configuration: config, agentPath: "/fake/agy")
        try await waitUntil("conn1 prompt") { connections.value.first?.promptCalls.count == 1 }
        let conn1 = connections.value[0]
        XCTAssertEqual(conn1.spec.workingDirectory, expectedWorktree)
        XCTAssertEqual(conn1.startCalls.first?.workingDirectory, expectedWorktree)
        conn1.emit(.started(conversationID: "wt-conv-1"))
        conn1.emit(.finished(status: "completed", response: "OK 1", error: nil, conversationID: "wt-conv-1"))
        conn1.finishPrompt(with: .endTurn)
        try await waitUntil("idle shutdown stops conn1") { conn1.stopCount == 1 }
        XCTAssertEqual(session.liveWorktreePath, expectedWorktree, "idle shutdown must keep liveWorktreePath")

        // Turn 2 after idle shutdown reuses the SAME worktree without creating a new one
        session.send("Turn 2 after idle", configuration: config, agentPath: "/fake/agy")
        try await waitUntil("conn2 prompt") { connections.value.count == 2 && connections.value[1].promptCalls.count == 1 }
        let conn2 = connections.value[1]
        XCTAssertEqual(gitWorktreeAddCount.value, 1)
        XCTAssertEqual(conn2.spec.workingDirectory, expectedWorktree)
        XCTAssertEqual(conn2.startCalls.first?.workingDirectory, expectedWorktree)

        // Simulate crash on conn2 -> liveWorktreePath stays for restart
        conn2.emit(.connectionFailed(AgentFailure(kind: .exited, message: "crashed")))
        conn2.emit(.finished(status: "error", response: nil, error: "crashed", conversationID: "wt-conv-1"))
        conn2.simulateStreamEndAndPromptError()
        try await waitUntil("crash handled") { !session.isRunning }
        XCTAssertEqual(session.liveWorktreePath, expectedWorktree, "crash must keep liveWorktreePath for restart")

        // Turn 3 after crash still runs in the SAME worktree
        session.send("Turn 3 after crash", configuration: config, agentPath: "/fake/agy")
        try await waitUntil("conn3 prompt") { connections.value.count == 3 && connections.value[2].promptCalls.count == 1 }
        let conn3 = connections.value[2]
        XCTAssertEqual(gitWorktreeAddCount.value, 1)
        XCTAssertEqual(conn3.spec.workingDirectory, expectedWorktree)
        conn3.emit(.finished(status: "completed", response: "OK 3", error: nil, conversationID: "wt-conv-1"))
        conn3.finishPrompt(with: .endTurn)
        try await waitUntil("turn 3 done") { !session.isRunning }

        // Switching chat clears worktree
        session.resume(VitruvianCodeSessionSummary(id: "other-chat", title: "Other", preview: "Hi", steps: 1, modified: nil), configuration: config)
        XCTAssertNil(session.liveWorktreePath)

        // New chat clears worktree
        session.send("Turn on other", configuration: config, agentPath: "/fake/agy")
        try await waitUntil("conn4 prompt") { connections.value.count == 4 && connections.value[3].promptCalls.count == 1 }
        XCTAssertNotNil(session.liveWorktreePath)
        let conn4 = connections.value[3]
        conn4.emit(.finished(status: "completed", response: "OK 4", error: nil, conversationID: "other-chat"))
        conn4.finishPrompt(with: .endTurn)
        try await waitUntil("turn 4 done") { !session.isRunning }
        session.newChat()
        XCTAssertNil(session.liveWorktreePath)

        // Chat ending (`stopConnection()`) clears worktree even if connection had already idled out
        session.send("Turn 5", configuration: config, agentPath: "/fake/agy")
        try await waitUntil("conn5 prompt") { connections.value.count == 5 && connections.value[4].promptCalls.count == 1 }
        let conn5 = connections.value[4]
        conn5.emit(.finished(status: "completed", response: "OK 5", error: nil, conversationID: "wt-conv-5"))
        conn5.finishPrompt(with: .endTurn)
        try await waitUntil("idle stops conn5") { conn5.stopCount == 1 }
        XCTAssertNotNil(session.liveWorktreePath)
        session.stopConnection()
        XCTAssertNil(session.liveWorktreePath)
    }

    func testVersionRuleClientInfoWiredIntoInitialize() async throws {
        // 1. Pre-1.5.1 release sends allowlisted "zed"
        do {
            let agent = ScriptedACPAgent()
            let conn = AntigravityACPConnection(
                launchSpec: Self.defaultLaunchSpec,
                modeProvider: { (.standard, false) },
                runtimeVersion: "1.4.5",
                processFactory: agent.makeProcessFactory()
            )
            let driver = Task {
                try await agent.playSteps([
                    .expectClientRequest(method: "initialize"),
                    .agentSend(.object([
                        "jsonrpc": .string("2.0"),
                        "id": .string("$id"),
                        "result": .object([
                            "protocolVersion": .int(1),
                            "agentInfo": .object(["name": .string("Antigravity ACP Server"), "version": .string("1.4.5")]),
                        ]),
                    ])),
                    .expectClientRequest(method: "session/new"),
                    .agentSend(.object(["jsonrpc": .string("2.0"), "id": .string("$id"), "result": .object(["sessionId": .string("s-145")])])),
                ])
            }
            _ = try await withACPTestTimeout(seconds: 3.0) {
                try await conn.start(AgentSessionRequest(workingDirectory: "/workspace"))
            }
            try await withACPTestTimeout(seconds: 3.0) { try await driver.value }
            let initReq = try await agent.clientMessage(at: 0)
            XCTAssertEqual(initReq.objectValue?["params"]?.objectValue?["clientInfo"]?.objectValue?["name"]?.stringValue, "zed")
            await conn.stop()
        }

        // 2. Probed 1.5.10 release via Environment.runProgram sends "vitruvian-code"
        do {
            let agent = ScriptedACPAgent()
            let env = makeSessionEnvironment(
                makeConnection: { _ in MockPersistentConnection(spec: AgentConnectionSpec(provider: Self.agyACPProvider, workingDirectory: "/workspace")) },
                runProgram: { _, args in args == ["--version"] ? "1.5.10\n" : nil }
            )
            let spec = AgentConnectionSpec(provider: Self.agyACPProvider, agentPath: "/fake/agy", workingDirectory: "/workspace")
            let conn = AntigravityACPConnection(
                spec: spec,
                environment: env,
                processFactory: agent.makeProcessFactory()
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
                    .agentSend(.object(["jsonrpc": .string("2.0"), "id": .string("$id"), "result": .object(["sessionId": .string("s-1510")])])),
                ])
            }
            _ = try await withACPTestTimeout(seconds: 3.0) {
                try await conn.start(AgentSessionRequest(workingDirectory: "/workspace"))
            }
            try await withACPTestTimeout(seconds: 3.0) { try await driver.value }
            let initReq = try await agent.clientMessage(at: 0)
            XCTAssertEqual(initReq.objectValue?["params"]?.objectValue?["clientInfo"]?.objectValue?["name"]?.stringValue, "vitruvian-code")
            await conn.stop()
        }
    }

    func testVersionRulePerTurnPromptUsageWiredIntoContextUsage() async throws {
        // 1. 1.4.1 does NOT report per-turn prompt usage -> no .contextUsage from result.usage
        do {
            let agent = ScriptedACPAgent()
            let conn = AntigravityACPConnection(
                launchSpec: Self.defaultLaunchSpec,
                modeProvider: { (.standard, false) },
                runtimeVersion: "1.4.1",
                processFactory: agent.makeProcessFactory()
            )
            let reader = ACPEventStreamReader(conn.events)
            let driver = Task {
                try await agent.playSteps([
                    .expectClientRequest(method: "initialize"),
                    .agentSend(.object([
                        "jsonrpc": .string("2.0"),
                        "id": .string("$id"),
                        "result": .object([
                            "protocolVersion": .int(1),
                            "agentInfo": .object(["name": .string("Antigravity ACP Server"), "version": .string("1.4.1")]),
                        ]),
                    ])),
                    .expectClientRequest(method: "session/new"),
                    .agentSend(.object(["jsonrpc": .string("2.0"), "id": .string("$id"), "result": .object(["sessionId": .string("s-u141")])])),
                    .expectClientRequest(method: "session/prompt"),
                    .agentSend(.object([
                        "jsonrpc": .string("2.0"),
                        "id": .string("$id"),
                        "result": .object([
                            "stopReason": .string("end_turn"),
                            "usage": .object(["inputTokens": .int(900), "outputTokens": .int(100)]),
                        ]),
                    ])),
                ])
            }
            _ = try await withACPTestTimeout(seconds: 3.0) {
                try await conn.start(AgentSessionRequest(workingDirectory: "/workspace"))
            }
            _ = try await withACPTestTimeout(seconds: 3.0) {
                try await conn.prompt([.text("hi")])
            }
            try await withACPTestTimeout(seconds: 3.0) { try await driver.value }
            let events = try await reader.collectUntilFinished(timeout: 3.0)
            XCTAssertFalse(events.contains { if case .contextUsage = $0 { return true }; return false })
            if case .finished(_, _, _, _, let metrics)? = events.last {
                XCTAssertNil(metrics?.contextUsage)
            } else {
                XCTFail("Expected .finished")
            }
            await conn.stop()
        }

        // 2. 1.5.10 reports per-turn Gemini usage -> emitted as .contextUsage with uncached input split
        do {
            let agent = ScriptedACPAgent()
            let conn = AntigravityACPConnection(
                launchSpec: Self.defaultLaunchSpec,
                modeProvider: { (.standard, false) },
                runtimeVersion: "1.5.10",
                processFactory: agent.makeProcessFactory()
            )
            let reader = ACPEventStreamReader(conn.events)
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
                    .agentSend(.object(["jsonrpc": .string("2.0"), "id": .string("$id"), "result": .object(["sessionId": .string("s-u1510")])])),
                    .expectClientRequest(method: "session/prompt"),
                    .agentSend(.object([
                        "jsonrpc": .string("2.0"),
                        "id": .string("$id"),
                        "result": .object([
                            "stopReason": .string("end_turn"),
                            "usage": .object([
                                "inputTokens": .int(1000),
                                "cachedReadTokens": .int(400),
                                "outputTokens": .int(200),
                                "totalTokens": .int(1200),
                            ]),
                        ]),
                    ])),
                ])
            }
            _ = try await withACPTestTimeout(seconds: 3.0) {
                try await conn.start(AgentSessionRequest(workingDirectory: "/workspace"))
            }
            _ = try await withACPTestTimeout(seconds: 3.0) {
                try await conn.prompt([.text("hi")])
            }
            try await withACPTestTimeout(seconds: 3.0) { try await driver.value }
            let events = try await reader.collectUntilFinished(timeout: 3.0)
            let expected = VitruvianCodeContextUsage(inputTokens: 600, cachedTokens: 400, outputTokens: 200, contextWindow: 0)
            XCTAssertEqual(
                events,
                [
                    .contextUsage(expected),
                    .finished(
                        status: "completed",
                        response: nil,
                        error: nil,
                        conversationID: "s-u1510",
                        metrics: VitruvianCodeTurnMetrics(inputTokens: 1000, outputTokens: 200, cachedTokens: 400, contextUsage: expected)
                    ),
                ]
            )
            await conn.stop()
        }
    }

    func testVersionRuleNeedsReadRepairWiredIntoReadTextFileReplies() async throws {
        let workspace = FileManager.default.temporaryDirectory
            .appendingPathComponent("agy-read-repair-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workspace) }
        let sampleFile = workspace.appendingPathComponent("note.txt")
        try "hello repair\n".write(to: sampleFile, atomically: true, encoding: .utf8)

        // 1. 1.5.10 (`needsReadRepair == true`): serving `fs/read_text_file` immediately completes `Running client_view_file`
        //    and repairs a later bogus `failed` update from the agent.
        do {
            let agent = ScriptedACPAgent()
            let conn = AntigravityACPConnection(
                launchSpec: AgentProcessLaunchSpec(executable: "/fake/agy", arguments: ["acp"], workingDirectory: workspace.path),
                modeProvider: { (.yolo, false) },
                runtimeVersion: "1.5.10",
                processFactory: agent.makeProcessFactory()
            )
            let reader = ACPEventStreamReader(conn.events)
            let startDriver = Task {
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
                    .agentSend(.object(["jsonrpc": .string("2.0"), "id": .string("$id"), "result": .object(["sessionId": .string("s-rr")])])),
                ])
            }
            _ = try await withACPTestTimeout(seconds: 3.0) {
                try await conn.start(AgentSessionRequest(workingDirectory: workspace.path))
            }
            try await withACPTestTimeout(seconds: 3.0) { try await startDriver.value }

            let promptTask = Task {
                try await conn.prompt([.text("Read note")])
            }
            let promptMsg = try await agent.clientMessage(at: 2, timeout: 3.0)
            let promptID = promptMsg.objectValue?["id"] ?? .int(3)

            // Agent announces open `client_view_file` then sends `fs/read_text_file`
            try await agent.sendToClient(.object([
                "jsonrpc": .string("2.0"),
                "method": .string("session/update"),
                "params": .object([
                    "sessionId": .string("s-rr"),
                    "update": .object([
                        "sessionUpdate": .string("tool_call"),
                        "toolCallId": .string("read-1"),
                        "title": .string("Running client_view_file"),
                        "kind": .string("read"),
                        "status": .string("in_progress"),
                        "locations": .array([.object(["path": .string(sampleFile.path)])]),
                    ]),
                ]),
            ]))
            try await agent.sendToClient(.object([
                "jsonrpc": .string("2.0"),
                "id": .string("fs-1"),
                "method": .string("fs/read_text_file"),
                "params": .object([
                    "sessionId": .string("s-rr"),
                    "path": .string(sampleFile.path),
                ]),
            ]))
            let fsReply = try await agent.clientMessage(at: 3, timeout: 3.0)
            XCTAssertEqual(fsReply.objectValue?["result"]?.objectValue?["content"]?.stringValue, "hello repair\n")

            // Agent later sends a bogus failed update with an unrelated step error
            try await agent.sendToClient(.object([
                "jsonrpc": .string("2.0"),
                "method": .string("session/update"),
                "params": .object([
                    "sessionId": .string("s-rr"),
                    "update": .object([
                        "sessionUpdate": .string("tool_call_update"),
                        "toolCallId": .string("read-1"),
                        "status": .string("failed"),
                        "rawOutput": .string("unrelated step error"),
                    ]),
                ]),
            ]))
            try await agent.sendToClient(.object([
                "jsonrpc": .string("2.0"),
                "id": promptID,
                "result": .object(["stopReason": .string("end_turn")]),
            ]))

            _ = try await withACPTestTimeout(seconds: 3.0) { try await promptTask.value }
            let events = try await reader.collectUntilFinished(timeout: 3.0)
            let results = events.compactMap { event -> (id: String, output: String?, isError: Bool)? in
                if case .toolStepResult(let id, let output, let isError) = event {
                    return (id, output, isError)
                }
                return nil
            }
            XCTAssertGreaterThanOrEqual(results.count, 1)
            XCTAssertTrue(results.allSatisfy { $0.id == "read-1" && !$0.isError && $0.output == nil }, "Served read must repair failed update to non-error completed: \(results)")
            await conn.stop()
        }

        // 2. 1.4.5 (`needsReadRepair == false`): failed update is NOT repaired to completed
        do {
            let agent = ScriptedACPAgent()
            let conn = AntigravityACPConnection(
                launchSpec: AgentProcessLaunchSpec(executable: "/fake/agy", arguments: ["acp"], workingDirectory: workspace.path),
                modeProvider: { (.yolo, false) },
                runtimeVersion: "1.4.5",
                processFactory: agent.makeProcessFactory()
            )
            let reader = ACPEventStreamReader(conn.events)
            let startDriver = Task {
                try await agent.playSteps([
                    .expectClientRequest(method: "initialize"),
                    .agentSend(.object([
                        "jsonrpc": .string("2.0"),
                        "id": .string("$id"),
                        "result": .object([
                            "protocolVersion": .int(1),
                            "agentInfo": .object(["name": .string("Antigravity ACP Server"), "version": .string("1.4.5")]),
                        ]),
                    ])),
                    .expectClientRequest(method: "session/new"),
                    .agentSend(.object(["jsonrpc": .string("2.0"), "id": .string("$id"), "result": .object(["sessionId": .string("s-no-rr")])])),
                ])
            }
            _ = try await withACPTestTimeout(seconds: 3.0) {
                try await conn.start(AgentSessionRequest(workingDirectory: workspace.path))
            }
            try await withACPTestTimeout(seconds: 3.0) { try await startDriver.value }

            let promptTask = Task {
                try await conn.prompt([.text("Read note")])
            }
            let promptMsg = try await agent.clientMessage(at: 2, timeout: 3.0)
            let promptID = promptMsg.objectValue?["id"] ?? .int(3)
            try await agent.sendToClient(.object([
                "jsonrpc": .string("2.0"),
                "method": .string("session/update"),
                "params": .object([
                    "sessionId": .string("s-no-rr"),
                    "update": .object([
                        "sessionUpdate": .string("tool_call"),
                        "toolCallId": .string("read-145"),
                        "title": .string("Running client_view_file"),
                        "kind": .string("read"),
                        "status": .string("in_progress"),
                        "locations": .array([.object(["path": .string(sampleFile.path)])]),
                    ]),
                ]),
            ]))
            try await agent.sendToClient(.object([
                "jsonrpc": .string("2.0"),
                "method": .string("session/update"),
                "params": .object([
                    "sessionId": .string("s-no-rr"),
                    "update": .object([
                        "sessionUpdate": .string("tool_call_update"),
                        "toolCallId": .string("read-145"),
                        "status": .string("failed"),
                        "rawOutput": .string("actual failure"),
                    ]),
                ]),
            ]))
            try await agent.sendToClient(.object([
                "jsonrpc": .string("2.0"),
                "id": promptID,
                "result": .object(["stopReason": .string("end_turn")]),
            ]))
            _ = try await withACPTestTimeout(seconds: 3.0) { try await promptTask.value }
            let events = try await reader.collectUntilFinished(timeout: 3.0)
            XCTAssertTrue(events.contains(.toolStepResult(id: "read-145", output: "actual failure", isError: true)))
            await conn.stop()
        }
    }

    func testSilentPromptTimerStopsProcessGroupWhenAgentIgnoresCancelAndNextTurnResumes() async throws {
        let connections = LockedBox<[AntigravityACPConnection]>([])
        let agents = LockedBox<[ScriptedACPAgent]>([])

        let env = makeSessionEnvironment(makeConnection: { spec in
            let agent = ScriptedACPAgent()
            agents.withValue { $0.append(agent) }
            let conn = AntigravityACPConnection(
                launchSpec: AgentProcessLaunchSpec(executable: "/fake/agy", arguments: ["acp"], workingDirectory: spec.workingDirectory),
                modeProvider: spec.liveModeProvider ?? { (.standard, false) },
                promptInactivityTimeout: 0.05,
                cancelGraceTimeout: 0.05,
                processFactory: agent.makeProcessFactory()
            )
            connections.withValue { $0.append(conn) }
            return conn
        })

        let session = VitruvianCodeQuickPromptSession(environment: env, host: MockSessionHost())
        session.takeCheckpoint = { _ in nil }
        let config = VitruvianCodeConfiguration(workingDirectory: "/workspace", approvalMode: .standard, activeProvider: Self.agyACPProvider)

        // Turn 1: agent accepts prompt, receives session/cancel after inactivity, and IGNORES cancel!
        session.send("Hang forever", configuration: config, agentPath: "/fake/agy")
        try await waitUntil("agent1 launched") { agents.value.count == 1 }
        let agent1 = agents.value[0]
        let driver1 = Task {
            try await agent1.playSteps([
                .expectClientRequest(method: "initialize"),
                .agentSend(.object(["jsonrpc": .string("2.0"), "id": .string("$id"), "result": .object(["protocolVersion": .int(1)])])),
                .expectClientRequest(method: "session/new"),
                .agentSend(.object(["jsonrpc": .string("2.0"), "id": .string("$id"), "result": .object(["sessionId": .string("sess-wedged-1")])])),
                .expectClientRequest(method: "session/prompt"),
                .expectClientRequest(method: "session/cancel"),
                // Deliberately send NO response to session/prompt!
            ])
        }
        try await withACPTestTimeout(seconds: 3.0) { try await driver1.value }
        try await waitUntil("turn 1 fails after cancel grace expires", timeout: 3.0) { !session.isRunning }

        let terms = await agent1.terminations()
        XCTAssertFalse(terms.isEmpty, "Cancel grace expiry must terminate the wedged process group")
        XCTAssertFalse(connections.value[0].isConnected)
        XCTAssertEqual(session.conversationID, "sess-wedged-1")
        XCTAssertEqual(session.messages.last?.isError, true)
        XCTAssertEqual(session.messages.last?.text, "Agent stopped responding during the turn and was cancelled.")

        // Turn 2: next prompt spawns a fresh connection and resumes the saved session
        session.send("Resume cleanly", configuration: config, agentPath: "/fake/agy")
        try await waitUntil("agent2 launched") { agents.value.count == 2 }
        let agent2 = agents.value[1]
        let driver2 = Task {
            try await agent2.playSteps([
                .expectClientRequest(method: "initialize"),
                .agentSend(.object([
                    "jsonrpc": .string("2.0"),
                    "id": .string("$id"),
                    "result": .object([
                        "protocolVersion": .int(1),
                        "agentCapabilities": .object(["sessionCapabilities": .object(["resume": .object([:])])]),
                    ]),
                ])),
                .expectClientRequest(method: "session/resume"),
                .agentSend(.object(["jsonrpc": .string("2.0"), "id": .string("$id"), "result": .object(["sessionId": .string("sess-wedged-1")])])),
                .expectClientRequest(method: "session/prompt"),
                .agentSend(.object(["jsonrpc": .string("2.0"), "id": .string("$id"), "result": .object(["stopReason": .string("end_turn")])])),
            ])
        }
        try await withACPTestTimeout(seconds: 3.0) { try await driver2.value }
        try await waitUntil("turn 2 done") { !session.isRunning }
        let resumeMsg = try await agent2.clientMessage(at: 1)
        XCTAssertEqual(resumeMsg.objectValue?["method"]?.stringValue, "session/resume")
        XCTAssertEqual(resumeMsg.objectValue?["params"]?.objectValue?["sessionId"]?.stringValue, "sess-wedged-1")
        await session.stopAll()
    }

    func testEngineStopAllAwaitsEveryConnectionsStopBeforeReturning() async throws {
        let connections = LockedBox<[MockPersistentConnection]>([])
        let env = makeSessionEnvironment(makeConnection: { spec in
            let conn = MockPersistentConnection(spec: spec, stopDelayNanoseconds: 120_000_000)
            connections.withValue { $0.append(conn) }
            return conn
        })
        let engine = VitruvianCodeEngine(environment: env, host: MockSessionHost())
        engine.session.takeCheckpoint = { _ in nil }
        let config = VitruvianCodeConfiguration(workingDirectory: "/workspace", approvalMode: .standard, activeProvider: Self.agyACPProvider)

        engine.session.send("Turn 1", configuration: config, agentPath: "/fake/agy")
        try await waitUntil("conn1 prompt active") { connections.value.first?.promptCalls.count == 1 }
        let conn1 = try XCTUnwrap(connections.value.first)

        // Start a second connection while conn1's slow stop() is still in flight in `pendingConnectionStops`.
        engine.session.newChat()
        engine.session.send("Turn 2", configuration: config, agentPath: "/fake/agy")
        try await waitUntil("conn2 prompt active") { connections.value.count == 2 && connections.value[1].promptCalls.count == 1 }
        let conn2 = connections.value[1]

        try await withACPTestTimeout(seconds: 3.0) {
            await engine.stopAll()
        }
        XCTAssertEqual(conn1.stopCount, 1)
        XCTAssertTrue(conn1.stopCompleted, "engine.stopAll() must await in-flight stops before returning")
        XCTAssertEqual(conn2.stopCount, 1)
        XCTAssertTrue(conn2.stopCompleted, "engine.stopAll() must await every live connection's stop() before returning")
    }

    func testEngineStopAllWithTimeoutReturnsWithinBoundWhenOneStopHangsAndStillStopsTheOthers() async throws {
        let connections = LockedBox<[MockPersistentConnection]>([])
        let env = makeSessionEnvironment(makeConnection: { spec in
            let conn = MockPersistentConnection(spec: spec)
            connections.withValue { $0.append(conn) }
            return conn
        })
        let engine = VitruvianCodeEngine(environment: env, host: MockSessionHost())
        engine.session.takeCheckpoint = { _ in nil }
        let config = VitruvianCodeConfiguration(workingDirectory: "/workspace", approvalMode: .standard, activeProvider: Self.agyACPProvider)

        engine.session.send("Turn 1", configuration: config, agentPath: "/fake/agy")
        try await waitUntil("conn1 prompt active") { connections.value.first?.promptCalls.count == 1 }
        let hung = try XCTUnwrap(connections.value.first)
        hung.stopHangs = true

        // New chat starts stopping the first connection; its stop never returns.
        engine.session.newChat()
        try await waitUntil("hung stop started") { hung.stopCount == 1 }
        engine.session.send("Turn 2", configuration: config, agentPath: "/fake/agy")
        try await waitUntil("conn2 prompt active") { connections.value.count == 2 && connections.value[1].promptCalls.count == 1 }
        let healthy = connections.value[1]

        let started = ProcessInfo.processInfo.systemUptime
        try await withACPTestTimeout(seconds: 3.0) {
            await engine.stopAll(timeout: 0.5)
        }
        let elapsed = ProcessInfo.processInfo.systemUptime - started
        XCTAssertLessThan(elapsed, 2.0, "stopAll(timeout:) must return within its bound even when a stop hangs")
        XCTAssertGreaterThanOrEqual(elapsed, 0.4, "the bound, not a quick return, ended the wait for the hung stop")
        XCTAssertFalse(hung.stopCompleted)
        XCTAssertEqual(healthy.stopCount, 1)
        XCTAssertTrue(healthy.stopCompleted, "a hung stop must not keep the other connections from being stopped")
        hung.releaseStop()
        await session(of: engine).stopAll()
    }

    private func session(of engine: VitruvianCodeEngine) -> VitruvianCodeQuickPromptSession { engine.session }

    func testBatchOfSubagentsAllStartAndAllFinishOnTurnEnd() async throws {
        let agents = LockedBox<[ScriptedACPAgent]>([])
        let connections = LockedBox<[AntigravityACPConnection]>([])
        let env = makeSessionEnvironment(makeConnection: { spec in
            let agent = ScriptedACPAgent()
            agents.withValue { $0.append(agent) }
            let conn = AntigravityACPConnection(
                launchSpec: AgentProcessLaunchSpec(executable: "/fake/agy", arguments: ["acp"], workingDirectory: spec.workingDirectory),
                modeProvider: spec.liveModeProvider ?? { (.standard, false) },
                processFactory: agent.makeProcessFactory()
            )
            connections.withValue { $0.append(conn) }
            return conn
        })

        let session = VitruvianCodeQuickPromptSession(environment: env, host: MockSessionHost())
        session.takeCheckpoint = { _ in nil }
        let config = VitruvianCodeConfiguration(workingDirectory: "/workspace", approvalMode: .standard, activeProvider: Self.agyACPProvider)

        session.send("Launch subagent batch", configuration: config, agentPath: "/fake/agy")
        try await waitUntil("agent started") { agents.value.count == 1 && connections.value.count == 1 }
        let agent = agents.value[0]

        let startTask = Task {
            try await agent.playSteps([
                .expectClientRequest(method: "initialize"),
                .agentSend(.object(["jsonrpc": .string("2.0"), "id": .string("$id"), "result": .object(["protocolVersion": .int(1)])])),
                .expectClientRequest(method: "session/new"),
                .agentSend(.object(["jsonrpc": .string("2.0"), "id": .string("$id"), "result": .object(["sessionId": .string("sess-batch")])])),
                .expectClientRequest(method: "session/prompt"),
            ])
        }
        try await withACPTestTimeout(seconds: 3.0) { try await startTask.value }
        let promptID = (try await agent.clientMessage(at: 2)).objectValue?["id"] ?? .int(3)

        for (id, toolTitle, roles) in [
            ("sub-1", "Running invoke_subagent", [("Architect", "Design"), ("Auditor", "Audit")]),
            ("sub-2", "Running invoke_subagent", [("Tester", "Verify")]),
            ("sub-3", "Running start_subagent", [("Docs", "Document")]),
        ] {
            let entries: [ACPJSONValue] = roles.map { .object(["Role": .string($0.0), "Prompt": .string($0.1)]) }
            try await agent.sendToClient(.object([
                "jsonrpc": .string("2.0"),
                "method": .string("session/update"),
                "params": .object([
                    "sessionId": .string("sess-batch"),
                    "update": .object([
                        "sessionUpdate": .string("tool_call"),
                        "toolCallId": .string(id),
                        "title": .string(toolTitle),
                        "kind": .string("other"),
                        "status": .string("in_progress"),
                        "rawInput": .object(["Subagents": .array(entries)]),
                    ]),
                ]),
            ]))
        }

        try await waitUntil("all 3 subagent launches active") { session.activeSubagents.count == 3 }
        XCTAssertEqual(session.activeSubagents.map(\.id), ["sub-1", "sub-2", "sub-3"])
        XCTAssertEqual(session.activeSubagents.map(\.role), ["Architect, Auditor", "Tester", "Docs"])
        XCTAssertTrue(session.activeSubagents.allSatisfy(\.isRunning))

        // Prompt ends without closing any subagent updates -> all 3 must finish on turn end
        try await agent.sendToClient(.object([
            "jsonrpc": .string("2.0"),
            "id": promptID,
            "result": .object(["stopReason": .string("end_turn")]),
        ]))
        try await waitUntil("all subagents cleared at turn end") {
            !session.isRunning && session.activeSubagents.isEmpty
        }
        await session.stopAll()
    }

    func testSessionApprovalButtonsSendExactOptionIDsToRealFakeAgent() async throws {
        let agents = LockedBox<[ScriptedACPAgent]>([])
        let env = makeSessionEnvironment(makeConnection: { spec in
            let agent = ScriptedACPAgent()
            agents.withValue { $0.append(agent) }
            return AntigravityACPConnection(
                launchSpec: AgentProcessLaunchSpec(executable: "/fake/agy", arguments: ["acp"], workingDirectory: spec.workingDirectory),
                modeProvider: spec.liveModeProvider ?? { (.standard, false) },
                processFactory: agent.makeProcessFactory()
            )
        })

        let session = VitruvianCodeQuickPromptSession(environment: env, host: MockSessionHost())
        session.takeCheckpoint = { _ in nil }
        let config = VitruvianCodeConfiguration(workingDirectory: "/workspace", approvalMode: .standard, activeProvider: Self.agyACPProvider)

        session.send("Run 3 gated steps", configuration: config, agentPath: "/fake/agy")
        try await waitUntil("agent started") { agents.value.count == 1 }
        let agent = agents.value[0]

        let setupTask = Task {
            try await agent.playSteps([
                .expectClientRequest(method: "initialize"),
                .agentSend(.object(["jsonrpc": .string("2.0"), "id": .string("$id"), "result": .object(["protocolVersion": .int(1)])])),
                .expectClientRequest(method: "session/new"),
                .agentSend(.object(["jsonrpc": .string("2.0"), "id": .string("$id"), "result": .object(["sessionId": .string("sess-btn")])])),
                .expectClientRequest(method: "session/prompt"),
            ])
        }
        try await withACPTestTimeout(seconds: 3.0) { try await setupTask.value }
        let promptID = (try await agent.clientMessage(at: 2)).objectValue?["id"] ?? .int(3)

        let cases: [(rpcID: String, callID: String, optPrefix: String, decision: VitruvianCodeApprovalRequest.Status, expectedOpt: String)] = [
            ("rpc-btn-1", "call-1", "opt-1", .approved, "opt-1-once"),
            ("rpc-btn-2", "call-2", "opt-2", .sessionAllowed, "opt-2-always"),
            ("rpc-btn-3", "call-3", "opt-3", .denied, "opt-3-deny"),
        ]

        var nextMsgIndex = 3
        for item in cases {
            try await agent.sendToClient(.object([
                "jsonrpc": .string("2.0"),
                "id": .string(item.rpcID),
                "method": .string("session/request_permission"),
                "params": .object([
                    "sessionId": .string("sess-btn"),
                    "toolCall": .object([
                        "toolCallId": .string(item.callID),
                        "title": .string("Run \(item.callID)"),
                        "kind": .string("execute"),
                    ]),
                    "options": .array([
                        .object(["optionId": .string("\(item.optPrefix)-once"), "name": .string("Approve"), "kind": .string("allow_once")]),
                        .object(["optionId": .string("\(item.optPrefix)-always"), "name": .string("Always"), "kind": .string("allow_always")]),
                        .object(["optionId": .string("\(item.optPrefix)-deny"), "name": .string("Deny"), "kind": .string("reject_once")]),
                    ]),
                ]),
            ]))
            try await waitUntil("card \(item.callID) pending") {
                session.messages.contains { $0.approvalRequest?.id == item.callID && $0.approvalRequest?.status == .pending }
            }
            let cardMsg = try XCTUnwrap(session.messages.first { $0.approvalRequest?.id == item.callID })
            session.decideApproval(messageID: cardMsg.id, decision: item.decision)

            let reply = try await agent.clientMessage(at: nextMsgIndex, timeout: 3.0)
            nextMsgIndex += 1
            XCTAssertEqual(reply.objectValue?["id"]?.stringValue, item.rpcID)
            XCTAssertEqual(
                reply.objectValue?["result"]?.objectValue?["outcome"]?.objectValue?["optionId"]?.stringValue,
                item.expectedOpt
            )
        }

        try await agent.sendToClient(.object([
            "jsonrpc": .string("2.0"),
            "id": promptID,
            "result": .object(["stopReason": .string("end_turn")]),
        ]))
        try await waitUntil("turn completed") { !session.isRunning }
        await session.stopAll()
    }

    func testRealFakeAgentPromptErrorStopReasonAndUnexpectedProcessExit() async throws {
        let agents = LockedBox<[ScriptedACPAgent]>([])
        let env = makeSessionEnvironment(makeConnection: { spec in
            let agent = ScriptedACPAgent()
            agents.withValue { $0.append(agent) }
            return AntigravityACPConnection(
                launchSpec: AgentProcessLaunchSpec(executable: "/fake/agy", arguments: ["acp"], workingDirectory: spec.workingDirectory),
                modeProvider: spec.liveModeProvider ?? { (.standard, false) },
                processFactory: agent.makeProcessFactory()
            )
        })

        let session = VitruvianCodeQuickPromptSession(environment: env, host: MockSessionHost())
        session.takeCheckpoint = { _ in nil }
        let config = VitruvianCodeConfiguration(workingDirectory: "/workspace", approvalMode: .standard, activeProvider: Self.agyACPProvider)

        // Part A: real fake agent responds with stopReason "error"
        session.send("Error turn", configuration: config, agentPath: "/fake/agy")
        try await waitUntil("agent1 started") { agents.value.count == 1 }
        let agent1 = agents.value[0]
        let driver1 = Task {
            try await agent1.playSteps([
                .expectClientRequest(method: "initialize"),
                .agentSend(.object([
                    "jsonrpc": .string("2.0"),
                    "id": .string("$id"),
                    "result": .object([
                        "protocolVersion": .int(1),
                        "agentCapabilities": .object(["sessionCapabilities": .object(["resume": .object([:])])]),
                    ]),
                ])),
                .expectClientRequest(method: "session/new"),
                .agentSend(.object(["jsonrpc": .string("2.0"), "id": .string("$id"), "result": .object(["sessionId": .string("sess-err-1")])])),
                .expectClientRequest(method: "session/prompt"),
                .agentSend(.object(["jsonrpc": .string("2.0"), "id": .string("$id"), "result": .object(["stopReason": .string("error")])])),
            ])
        }
        try await withACPTestTimeout(seconds: 3.0) { try await driver1.value }
        try await waitUntil("turn 1 finishes failed") { !session.isRunning }
        XCTAssertTrue(session.messages.contains { $0.isError })
        XCTAssertEqual(session.messages.filter(\.isError).count, 1, "an error stop reason shows exactly one error bubble")
        XCTAssertEqual(session.lastFailedPrompt, "Error turn")
        let errorsBeforeCrash = session.messages.filter(\.isError).count

        // Part B: fake agent process exits mid-turn while an approval card is pending
        session.send("Crash turn", configuration: config, agentPath: "/fake/agy")
        _ = try await agent1.clientMessage(at: 3, timeout: 3.0)
        try await agent1.sendToClient(.object([
            "jsonrpc": .string("2.0"),
            "id": .string("perm-crash"),
            "method": .string("session/request_permission"),
            "params": .object([
                "sessionId": .string("sess-err-1"),
                "toolCall": .object(["toolCallId": .string("call-c1"), "title": .string("Run touch"), "kind": .string("execute")]),
                "options": .array([.object(["optionId": .string("allow_once"), "name": .string("Allow"), "kind": .string("allow_once")])]),
            ]),
        ]))
        try await waitUntil("approval pending before crash") { session.hasPendingApproval }

        await agent1.simulateExit(AgentProcessExit(exitCode: nil, signal: SIGKILL))
        try await waitUntil("process exit ends turn and cancels approval") {
            !session.isRunning && !session.hasPendingApproval
        }
        XCTAssertEqual(session.messages.last?.isError, true)
        XCTAssertEqual(
            session.messages.filter(\.isError).count - errorsBeforeCrash, 1,
            "a process exit mid-turn shows exactly one new error bubble")

        // Part C: next prompt spawns fresh connection and resumes cleanly
        session.send("Recover after real exit", configuration: config, agentPath: "/fake/agy")
        try await waitUntil("agent2 started") { agents.value.count == 2 }
        let agent2 = agents.value[1]
        let driver2 = Task {
            try await agent2.playSteps([
                .expectClientRequest(method: "initialize"),
                .agentSend(.object([
                    "jsonrpc": .string("2.0"),
                    "id": .string("$id"),
                    "result": .object([
                        "protocolVersion": .int(1),
                        "agentCapabilities": .object(["sessionCapabilities": .object(["resume": .object([:])])]),
                    ]),
                ])),
                .expectClientRequest(method: "session/resume"),
                .agentSend(.object(["jsonrpc": .string("2.0"), "id": .string("$id"), "result": .object(["sessionId": .string("sess-err-1")])])),
                .expectClientRequest(method: "session/prompt"),
                .agentSend(.object(["jsonrpc": .string("2.0"), "id": .string("$id"), "result": .object(["stopReason": .string("end_turn")])])),
            ])
        }
        try await withACPTestTimeout(seconds: 3.0) { try await driver2.value }
        try await waitUntil("recovery turn finishes") { !session.isRunning }
        XCTAssertNil(session.lastFailedPrompt)
        await session.stopAll()
    }

    /// The session shows one error bubble however many failure events arrive (it keeps the first), so the
    /// bubble count alone cannot prove each event is sent. This pins the exact events agy's connection emits.
    func testAgyConnectionEmitsExactFailureEventsForErrorStopReasonAndProcessExit() async throws {
        func startedConnection(_ agent: ScriptedACPAgent, session: String) async throws -> (AntigravityACPConnection, ACPEventStreamReader) {
            let connection = AntigravityACPConnection(
                launchSpec: Self.defaultLaunchSpec,
                modeProvider: { (.standard, false) },
                sessionSetupTimeout: 0.5,
                processFactory: agent.makeProcessFactory()
            )
            let reader = ACPEventStreamReader(connection.events)
            let driver = Task {
                try await agent.playSteps([
                    .expectClientRequest(method: "initialize"),
                    .agentSend(.object(["jsonrpc": .string("2.0"), "id": .string("$id"), "result": .object(["protocolVersion": .int(1)])])),
                    .expectClientRequest(method: "session/new"),
                    .agentSend(.object(["jsonrpc": .string("2.0"), "id": .string("$id"), "result": .object(["sessionId": .string(session)])])),
                    .expectClientRequest(method: "session/prompt"),
                ])
            }
            _ = try await withACPTestTimeout(seconds: 3.0) {
                try await connection.start(AgentSessionRequest(workingDirectory: "/workspace"))
            }
            _ = driver
            return (connection, reader)
        }

        // Error stop reason: exactly one `.finished(error)` and no `.connectionFailed`.
        let agentA = ScriptedACPAgent()
        let (connA, readerA) = try await startedConnection(agentA, session: "sess-ev-a")
        let promptA = Task { try await connA.prompt([.text("go")]) }
        _ = try await agentA.clientMessage(at: 2, timeout: 3.0)
        let promptIDA = (try await agentA.clientMessage(at: 2)).objectValue?["id"] ?? .int(3)
        try await agentA.sendToClient(.object(["jsonrpc": .string("2.0"), "id": promptIDA, "result": .object(["stopReason": .string("error")])]))
        let reasonA = try await withACPTestTimeout(seconds: 3.0) { try await promptA.value }
        XCTAssertEqual(reasonA, .error)
        await connA.stop()
        let eventsA = try await readerA.collectAllUntilEnd(timeout: 3.0)
        let finishedA = eventsA.filter { if case .finished = $0 { return true } else { return false } }
        XCTAssertEqual(finishedA.count, 1)
        if case .finished(let status, _, let error, _, _)? = finishedA.first {
            XCTAssertEqual(status, "error")
            XCTAssertNotNil(error)
        }
        XCTAssertFalse(eventsA.contains { if case .connectionFailed = $0 { return true } else { return false } })

        // Process exit mid-turn: `.connectionFailed(.exited)` then `.finished(error)`, nothing else of either kind.
        let agentB = ScriptedACPAgent()
        let (connB, readerB) = try await startedConnection(agentB, session: "sess-ev-b")
        let promptB = Task { try await connB.prompt([.text("crash")]) }
        _ = try await agentB.clientMessage(at: 2, timeout: 3.0)
        await agentB.simulateExit(AgentProcessExit(exitCode: nil, signal: SIGKILL))
        _ = try await withACPTestTimeout(seconds: 3.0) { try await promptB.value }
        let eventsB = try await readerB.collectAllUntilEnd(timeout: 3.0)
        let failures = eventsB.filter { if case .connectionFailed = $0 { return true } else { return false } }
        let finishes = eventsB.filter { if case .finished = $0 { return true } else { return false } }
        XCTAssertEqual(failures.count, 1, "process exit must emit .connectionFailed once")
        XCTAssertEqual(finishes.count, 1, "process exit must emit .finished(error) once")
        if case .connectionFailed(let failure)? = failures.first { XCTAssertEqual(failure.kind, .exited) }
        if case .finished(let status, _, _, _, _)? = finishes.first { XCTAssertEqual(status, "error") }
        let failureIndex = eventsB.firstIndex { if case .connectionFailed = $0 { return true } else { return false } }
        let finishIndex = eventsB.firstIndex { if case .finished = $0 { return true } else { return false } }
        if let failureIndex, let finishIndex { XCTAssertLessThan(failureIndex, finishIndex) }
    }

    func testCommandLineAntigravityTranscriptLookupReadsAntigravityCLIDirectory() throws {
        let fakeHome = FileManager.default.temporaryDirectory
            .appendingPathComponent("agy-cli-transcript-home-\(UUID().uuidString)", isDirectory: true)
        let sessionID = "cli-conv-1"
        let logsDir = fakeHome.appendingPathComponent(".gemini/antigravity-cli/brain/\(sessionID)/.system_generated/logs", isDirectory: true)
        try FileManager.default.createDirectory(at: logsDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: fakeHome) }

        let transcriptFile = logsDir.appendingPathComponent("transcript.jsonl")
        let content = """
        {"type":"USER_INPUT","content":"Ping from CLI"}
        {"type":"PLANNER_RESPONSE","content":"PONG from CLI"}
        """
        try content.write(to: transcriptFile, atomically: true, encoding: .utf8)

        let resolvedPath = VitruvianCodeEngine.transcriptPath(
            home: fakeHome.path,
            conversationID: sessionID,
            provider: .antigravity
        )
        XCTAssertEqual(resolvedPath, transcriptFile.path)

        let parsed = try XCTUnwrap(
            VitruvianCodeEngine.readTranscript(
                home: fakeHome.path,
                conversationID: sessionID,
                provider: .antigravity
            )
        )
        XCTAssertEqual(parsed.map(\.text), ["Ping from CLI", "PONG from CLI"])
        XCTAssertEqual(parsed.map(\.role), [.user, .agent])
    }

    func testCommandLineAntigravityTranscriptLookupFindsOldDesktopFolderAndNewCLIFolder() throws {
        let fakeHome = FileManager.default.temporaryDirectory
            .appendingPathComponent("agy-transcript-both-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: fakeHome) }
        func write(_ base: String, _ id: String, _ reply: String) throws -> String {
            let dir = fakeHome.appendingPathComponent("\(base)/brain/\(id)/.system_generated/logs", isDirectory: true)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let file = dir.appendingPathComponent("transcript.jsonl")
            try "{\"type\":\"USER_INPUT\",\"content\":\"hi\"}\n{\"type\":\"PLANNER_RESPONSE\",\"content\":\"\(reply)\"}"
                .write(to: file, atomically: true, encoding: .utf8)
            return file.path
        }
        XCTAssertEqual(
            VitruvianCodeSessionSummary.antigravityDataDirectories,
            [".gemini/antigravity", ".gemini/antigravity-cli"],
            "lookup order: older installs' folder first, then the CLI's own"
        )
        let oldPath = try write(".gemini/antigravity", "old-only", "from old")
        let newPath = try write(".gemini/antigravity-cli", "new-only", "from new")
        let bothOld = try write(".gemini/antigravity", "both", "old copy")
        _ = try write(".gemini/antigravity-cli", "both", "new copy")

        for (id, path, reply) in [("old-only", oldPath, "from old"), ("new-only", newPath, "from new"), ("both", bothOld, "old copy")] {
            XCTAssertEqual(
                VitruvianCodeEngine.transcriptPath(home: fakeHome.path, conversationID: id, provider: .antigravity), path, id)
            let parsed = try XCTUnwrap(
                VitruvianCodeEngine.readTranscript(home: fakeHome.path, conversationID: id, provider: .antigravity), id)
            XCTAssertEqual(parsed.map(\.text), ["hi", reply], id)
        }
    }

    // MARK: - Helpers

    private func replayFixture(
        named fixtureName: String,
        mode: VitruvianCodeApprovalMode,
        resumeSessionID: String? = nil,
        promptText: String,
        cancelAfterThinking: Bool = false,
        onApproval: (@MainActor (AntigravityACPConnection, VitruvianCodeApprovalRequest) async throws -> Void)? = nil,
        onQuestion: (@MainActor (AntigravityACPConnection, AgentQuestion) async throws -> Void)? = nil
    ) async throws -> [AgentEvent] {
        let steps = ACPFixtureLoader.loadSteps(named: fixtureName)
        let agent = ScriptedACPAgent()
        let connection = AntigravityACPConnection(
            launchSpec: Self.defaultLaunchSpec,
            modeProvider: { (mode, false) },
            sessionSetupTimeout: 0.5,
            processFactory: agent.makeProcessFactory()
        )
        let reader = ACPEventStreamReader(connection.events)
        let driver = Task {
            try await agent.playSteps(steps)
        }
        _ = try await withACPTestTimeout(seconds: 3.0) {
            try await connection.start(AgentSessionRequest(workingDirectory: "/workspace", resumeSessionID: resumeSessionID))
        }

        let promptTask = Task {
            try await connection.prompt([.text(promptText)])
        }

        var collected: [AgentEvent] = []
        while let event = try await reader.next(timeout: 3.0) {
            collected.append(event)
            switch event {
            case .thinking where cancelAfterThinking:
                await connection.cancel()
            case .approval(let req):
                try await onApproval?(connection, req)
            case .question(let question):
                try await onQuestion?(connection, question)
            case .finished:
                _ = try await withACPTestTimeout(seconds: 3.0) { try await promptTask.value }
                try await withACPTestTimeout(seconds: 3.0) { try await driver.value }
                await connection.stop()
                return collected
            default:
                break
            }
        }
        XCTFail("Fixture stream \(fixtureName) ended before .finished")
        await connection.stop()
        return collected
    }

    private func waitUntil(
        _ description: String,
        timeout: TimeInterval = 3.0,
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
        transcriptPath: @escaping (String, VitruvianCodeCLIProvider) -> String? = { _, _ in nil },
        readTranscriptRaw: @escaping (String, VitruvianCodeCLIProvider) -> String? = { _, _ in nil },
        readTranscript: @escaping (String, VitruvianCodeCLIProvider) -> [VitruvianCodeChatMessage]? = { _, _ in nil },
        runProgram: @escaping @Sendable (String, [String]) async -> String? = { _, _ in nil }
    ) -> VitruvianCodeEngine.Environment {
        let domain = "com.vitruviansoftware.vitruvian-code.tests.agy-acp.\(UUID().uuidString)"
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
            readTranscript: readTranscript,
            transcriptPath: transcriptPath,
            readTranscriptRaw: readTranscriptRaw,
            runProgram: runProgram
        )
    }

    private func createStepsDB(at dbPath: String, initialSteps: [(Int, Int, String)]) throws {
        var stmts = ["CREATE TABLE IF NOT EXISTS steps (idx INTEGER PRIMARY KEY, step_type INTEGER, step_payload BLOB);"]
        for (idx, stepType, text) in initialSteps {
            let hex = Data(text.utf8).map { String(format: "%02x", $0) }.joined()
            stmts.append("INSERT INTO steps (idx, step_type, step_payload) VALUES (\(idx), \(stepType), X'\(hex)');")
        }
        try runSqlite(dbPath: dbPath, sql: stmts.joined(separator: "\n"))
    }

    private func insertErrorStep(at dbPath: String, idx: Int, payload: String) throws {
        let hex = Data(payload.utf8).map { String(format: "%02x", $0) }.joined()
        try runSqlite(
            dbPath: dbPath,
            sql: "INSERT INTO steps (idx, step_type, step_payload) VALUES (\(idx), \(AntigravityTurnOutcome.errorStepType), X'\(hex)');"
        )
    }

    private func insertPlannerStep(at dbPath: String, idx: Int, payload: String) throws {
        let hex = Data(payload.utf8).map { String(format: "%02x", $0) }.joined()
        try runSqlite(dbPath: dbPath, sql: "INSERT INTO steps (idx, step_type, step_payload) VALUES (\(idx), 15, X'\(hex)');")
    }

    private func runSqlite(dbPath: String, sql: String) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = [dbPath, sql]
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
    }
}

private final class LockedBox<Value>: @unchecked Sendable {
    // Safe because every read and write acquires `lock`.
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
private final class MockPersistentConnection: PersistentAgentConnection {
    let spec: AgentConnectionSpec
    let failStart: Bool
    let stopDelayNanoseconds: UInt64
    var capabilities = AgentCapabilities(resumeSession: true, closeSession: true)
    let events: AsyncStream<AgentEvent>
    private let continuation: AsyncStream<AgentEvent>.Continuation

    private(set) var startCalls: [AgentSessionRequest] = []
    private(set) var promptCalls: [[PromptBlock]] = []
    private(set) var answers: [(String, AgentAnswer)] = []
    private(set) var syncedPlanModes: [Bool] = []
    private(set) var cancelCount = 0
    private(set) var stopCount = 0
    private(set) var stopCompleted = false
    private(set) var isStopped = false
    /// When true, `stop()` does not return until `releaseStop()` (a connection whose process will not die).
    var stopHangs = false
    private var stopRelease: CheckedContinuation<Void, Never>?
    private var stopReleased = false
    var isConnected: Bool { !isStopped }
    private var promptContinuation: CheckedContinuation<AgentStopReason, any Error>?

    init(spec: AgentConnectionSpec, failStart: Bool = false, stopDelayNanoseconds: UInt64 = 0) {
        self.spec = spec
        self.failStart = failStart
        self.stopDelayNanoseconds = stopDelayNanoseconds
        var captured: AsyncStream<AgentEvent>.Continuation!
        self.events = AsyncStream { captured = $0 }
        self.continuation = captured
    }

    func start(_ request: AgentSessionRequest) async throws -> String {
        startCalls.append(request)
        if failStart {
            throw ACPConnectionError.notStarted
        }
        return request.resumeSessionID ?? "mock-session-1"
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

    func answer(_ requestID: String, _ choice: AgentAnswer) async throws {
        answers.append((requestID, choice))
    }

    func setConfigOption(_ id: String, _ value: AgentConfigValue) async throws -> [AgentConfigOption] {
        []
    }

    func syncPlanMode(_ planSwitch: Bool) async throws {
        syncedPlanModes.append(planSwitch)
    }

    func stop() async {
        stopCount += 1
        isStopped = true
        if stopHangs && !stopReleased {
            await withCheckedContinuation { stopRelease = $0 }
        }
        if stopDelayNanoseconds > 0 {
            try? await Task.sleep(nanoseconds: stopDelayNanoseconds)
        }
        stopCompleted = true
        continuation.finish()
    }

    func releaseStop() {
        stopReleased = true
        stopRelease?.resume()
        stopRelease = nil
    }

    func emit(_ event: AgentEvent) {
        continuation.yield(event)
    }

    func finishPrompt(with reason: AgentStopReason) {
        let cont = promptContinuation
        promptContinuation = nil
        cont?.resume(returning: reason)
    }

    func simulateStreamEndAndPromptError() {
        isStopped = true
        continuation.finish()
        let cont = promptContinuation
        promptContinuation = nil
        cont?.resume(throwing: ACPTransportError.connectionClosed("crashed"))
    }
}

@MainActor
private final class MockSessionHost: VitruvianCodeHost {
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
    var strings = VitruvianCodeHostStrings()
    var approvals: [VitruvianCodeTurnNotice] = []

    func turnNeedsApproval(_ notice: VitruvianCodeTurnNotice) {
        approvals.append(notice)
    }
    func turnFinished(_ notice: VitruvianCodeTurnNotice, isChatVisible: Bool) {}
}
