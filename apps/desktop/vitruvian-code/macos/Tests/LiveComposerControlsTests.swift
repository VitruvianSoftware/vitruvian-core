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
@testable import VitruvianCodeUI
import XCTest

@MainActor
final class LiveComposerControlsTests: XCTestCase {

    private static var liveACPProvider: VitruvianCodeCLIProvider {
        var provider = VitruvianCodeCLIProvider.antigravity
        provider.connection = .acp
        return provider
    }

    private static var commandLineProvider: VitruvianCodeCLIProvider {
        var provider = VitruvianCodeCLIProvider.antigravity
        provider.connection = .commandLine
        return provider
    }

    // MARK: - 1. Settings bar option filtering

    func testSettingsBarExcludesModeOptionsAndEmptyChoiceOptions() {
        let input: [AgentConfigOption] = [
            AgentConfigOption(
                id: ACPSessionConfigState.sessionModeOptionID,
                name: "Session Mode",
                value: .string("default"),
                options: ["default", "plan"],
                category: nil
            ),
            AgentConfigOption(
                id: "permission_policy",
                name: "Permission Policy",
                value: .string("acceptEdits"),
                options: ["default", "acceptEdits", "bypassPermissions"],
                category: "mode"
            ),
            AgentConfigOption(
                id: "mode",
                name: "Mode",
                value: .string("code"),
                options: ["code", "plan"],
                category: nil
            ),
            AgentConfigOption(
                id: "thinking",
                name: "Thinking",
                value: .bool(true),
                options: [],
                category: nil
            ),
            AgentConfigOption(
                id: "model",
                name: "Model",
                value: .string("claude-sonnet-4-5"),
                options: ["claude-sonnet-4-5", "claude-opus-4-1"],
                category: "model"
            ),
            AgentConfigOption(
                id: "effort",
                name: "Effort",
                value: .string("medium"),
                options: ["low", "medium", "high"],
                category: "thought_level"
            ),
        ]

        let visible = AgentSettingsBarLogic.visibleOptions(from: input)
        XCTAssertEqual(visible.map(\.id), ["model", "effort"])
        XCTAssertTrue(AgentSettingsBarLogic.isModeOption(input[0]))
        XCTAssertTrue(AgentSettingsBarLogic.isModeOption(input[1]))
        XCTAssertTrue(AgentSettingsBarLogic.isModeOption(input[2]))
        XCTAssertFalse(AgentSettingsBarLogic.isModeOption(input[4]))
    }

    // MARK: - 2. Confirm-only updates, failure preservation, disabled during turn

    func testLiveConfigOptionUpdatesOnlyAfterConfirmationPreservesOnFailureAndRefusesDuringTurn() async throws {
        let connections = ComposerControlBox<[ComposerControlMockConnection]>([])
        let rig = ComposerRig()
        var env = rig.environment
        env.makeConnection = { spec in
            let conn = ComposerControlMockConnection(spec: spec)
            connections.withValue { $0.append(conn) }
            return conn
        }
        let session = VitruvianCodeQuickPromptSession(environment: env, host: rig.host)
        session.takeCheckpoint = { _ in nil }
        let config = VitruvianCodeConfiguration(approvalMode: .standard, activeProvider: Self.liveACPProvider)

        // Before first prompt: no connection started early, changing option does not spawn one.
        let beforeConnect = await session.setLiveConfigOption(id: "model", value: .string("opus"))
        XCTAssertFalse(beforeConnect)
        XCTAssertTrue(connections.value.isEmpty, "setting config option must not start connection early")
        XCTAssertNotNil(session.liveConfigOptionError)

        // Start turn 1 and confirm initial configOptions.
        session.send("Hello", configuration: config, agentPath: "/fake/agy")
        try await waitUntil("prompt 1") { connections.value.first?.promptCalls.count == 1 }
        let conn = try XCTUnwrap(connections.value.first)
        let initialOptions: [AgentConfigOption] = [
            AgentConfigOption(id: "mode", name: "Mode", value: .string("default"), options: ["default", "plan"], category: "mode"),
            AgentConfigOption(id: "model", name: "Model", value: .string("sonnet"), options: ["sonnet", "opus"], category: "model"),
            AgentConfigOption(id: "effort", name: "Effort", value: .string("medium"), options: ["low", "medium", "high"], category: "thought_level"),
        ]
        conn.emit(.configOptions(initialOptions))
        try await waitUntil("initial configOptions received") {
            session.liveState.configOptions.count == 3
        }

        // While a turn is running, setLiveConfigOption is disabled / refused.
        let duringTurn = await session.setLiveConfigOption(id: "model", value: .string("opus"))
        XCTAssertFalse(duringTurn)
        XCTAssertTrue(conn.setConfigCalls.isEmpty)

        // Finish turn 1.
        conn.emit(.finished(status: "completed", response: "Hi", error: nil, conversationID: "s-cfg-1"))
        conn.finishPrompt(with: .endTurn)
        try await waitUntil("turn 1 done") { !session.isRunning }

        // Mode options cannot be changed through setLiveConfigOption.
        let rejectedMode = await session.setLiveConfigOption(id: "mode", value: .string("plan"))
        XCTAssertFalse(rejectedMode)
        XCTAssertTrue(conn.setConfigCalls.isEmpty)

        // Confirm-only change: suspend setConfigOption and verify value does NOT change optimistically.
        conn.holdSetConfigOption = true
        let updateTask = Task { @MainActor in
            await session.setLiveConfigOption(id: "model", value: .string("opus"))
        }
        try await waitUntil("setConfigOption in flight") { conn.setConfigCalls.count == 1 }
        XCTAssertEqual(
            session.liveState.configOptions.first(where: { $0.id == "model" })?.value,
            .string("sonnet"),
            "value must not change optimistically before agent confirms"
        )

        // Agent confirms the change.
        let updatedOptions: [AgentConfigOption] = [
            AgentConfigOption(id: "mode", name: "Mode", value: .string("default"), options: ["default", "plan"], category: "mode"),
            AgentConfigOption(id: "model", name: "Model", value: .string("opus"), options: ["sonnet", "opus"], category: "model"),
            AgentConfigOption(id: "effort", name: "Effort", value: .string("medium"), options: ["low", "medium", "high"], category: "thought_level"),
        ]
        conn.releaseSetConfigOption(returning: .success(updatedOptions))
        let succeeded = await updateTask.value
        XCTAssertTrue(succeeded)
        XCTAssertEqual(
            session.liveState.configOptions.first(where: { $0.id == "model" })?.value,
            .string("opus")
        )
        XCTAssertNil(session.liveConfigOptionError)

        // Failure keeps old value and sets inline error.
        conn.holdSetConfigOption = false
        conn.failSetConfigOption = true
        let failed = await session.setLiveConfigOption(id: "effort", value: .string("high"))
        XCTAssertFalse(failed)
        XCTAssertEqual(
            session.liveState.configOptions.first(where: { $0.id == "effort" })?.value,
            .string("medium"),
            "failure must keep old value"
        )
        XCTAssertNotNil(session.liveConfigOptionError)

        // Next change clears the inline error on success.
        conn.failSetConfigOption = false
        conn.nextSetConfigResult = [
            AgentConfigOption(id: "mode", name: "Mode", value: .string("default"), options: ["default", "plan"], category: "mode"),
            AgentConfigOption(id: "model", name: "Model", value: .string("opus"), options: ["sonnet", "opus"], category: "model"),
            AgentConfigOption(id: "effort", name: "Effort", value: .string("high"), options: ["low", "medium", "high"], category: "thought_level"),
        ]
        let recovered = await session.setLiveConfigOption(id: "effort", value: .string("high"))
        XCTAssertTrue(recovered)
        XCTAssertNil(session.liveConfigOptionError)
        XCTAssertEqual(
            session.liveState.configOptions.first(where: { $0.id == "effort" })?.value,
            .string("high")
        )

        await session.stopAll()
    }

    // MARK: - 3. Per-chat mode on live connections vs command-line chats

    func testPerChatModeLeavesGlobalUnchangedAndReachesAgentBeforeNextPrompt() async throws {
        let connections = ComposerControlBox<[ComposerControlMockConnection]>([])
        let rig = ComposerRig()
        var env = rig.environment
        env.makeConnection = { spec in
            let conn = ComposerControlMockConnection(spec: spec)
            connections.withValue { $0.append(conn) }
            return conn
        }
        let engine = VitruvianCodeEngine(environment: env, host: rig.host)
        var initial = engine.configuration
        initial.approvalMode = .yolo
        initial.activeProvider = Self.liveACPProvider
        engine.updateChatConfiguration(initial)

        let session = engine.session
        session.takeCheckpoint = { _ in nil }

        // Start turn 1 with global .yolo; chat has no override so it follows global.
        session.send("Turn 1", configuration: engine.configuration, agentPath: "/fake/agy")
        try await waitUntil("prompt 1") { connections.value.first?.promptCalls.count == 1 }
        let conn = try XCTUnwrap(connections.value.first)
        XCTAssertEqual(conn.syncedModes.first?.0, .yolo)
        conn.emit(.finished(status: "completed", response: "OK", error: nil, conversationID: "live-chat-1"))
        conn.finishPrompt(with: .endTurn)
        try await waitUntil("turn 1 done") { !session.isRunning }

        // Picking mode in ChatApprovalModeBadge sets chatApprovalMode only and keeps global .yolo.
        ChatApprovalModeBadge.applySelection(.acceptEdits, session: session, engine: engine)
        XCTAssertEqual(session.chatApprovalMode, .acceptEdits)
        XCTAssertEqual(engine.configuration.approvalMode, .yolo, "global default must remain untouched")
        XCTAssertEqual(rig.host.chatModes["live-chat-1"], "accept-edits")

        // Next prompt syncs .acceptEdits to the live agent before sending the prompt.
        session.send("Turn 2", configuration: engine.configuration, agentPath: "/fake/agy")
        try await waitUntil("prompt 2") { conn.promptCalls.count == 2 }
        XCTAssertEqual(conn.syncedModes.count, 2)
        XCTAssertEqual(conn.syncedModes.last?.0, .acceptEdits)
        XCTAssertEqual(conn.syncedModes.last?.1, false)
        conn.emit(.finished(status: "completed", response: "OK", error: nil, conversationID: "live-chat-1"))
        conn.finishPrompt(with: .endTurn)
        try await waitUntil("turn 2 done") { !session.isRunning }

        // A new chat without an override follows the global setting.
        session.newChat()
        XCTAssertNil(session.chatApprovalMode)
        XCTAssertEqual(session.effectiveApprovalMode(for: engine.configuration), .yolo)
        var updatedGlobal = engine.configuration
        updatedGlobal.approvalMode = .standard
        engine.updateChatConfiguration(updatedGlobal)
        XCTAssertEqual(session.effectiveApprovalMode(for: engine.configuration), .standard)

        // Command-line chats keep today's behavior (writing global approvalMode).
        var cliConfig = engine.configuration
        cliConfig.activeProvider = Self.commandLineProvider
        cliConfig.approvalMode = .yolo
        engine.updateChatConfiguration(cliConfig)
        ChatApprovalModeBadge.applySelection(.acceptEdits, session: session, engine: engine)
        XCTAssertNil(session.chatApprovalMode)
        XCTAssertEqual(engine.configuration.approvalMode, .acceptEdits)

        await session.stopAll()
    }

    /// Design section 8: Auto (Claude decides for itself what is safe to run) is offered per chat on
    /// the Claude SDK connection only, and never becomes the global default.
    func testAutoIsOfferedForAClaudeSDKChatOnlyAndNeverBecomesTheGlobalDefault() {
        XCTAssertEqual(ChatApprovalModeBadge.choices(connection: .claudeSDK), [.yolo, .auto, .acceptEdits, .standard, .plan])
        for connection: AgentConnectionKind? in [.acp, .claudeACP, .commandLine, nil] {
            XCTAssertFalse(ChatApprovalModeBadge.choices(connection: connection).contains(.auto),
                           "Auto is Claude SDK only, not \(String(describing: connection))")
        }

        let rig = ComposerRig()
        let engine = VitruvianCodeEngine(environment: rig.environment, host: rig.host)
        func choose(_ provider: VitruvianCodeCLIProvider) {
            rig.host.savedProviders = [provider]
            rig.host.chosenProviderID = provider.id
            var config = engine.configuration
            config.approvalMode = .standard
            engine.updateChatConfiguration(config)
            XCTAssertEqual(engine.session.effectiveConnectionKind(for: engine.configuration.activeProvider), provider.connection)
        }
        var sdk = VitruvianCodeCLIProvider.claude
        sdk.connection = .claudeSDK
        choose(sdk)

        ChatApprovalModeBadge.applySelection(.auto, session: engine.session, engine: engine)
        XCTAssertEqual(engine.session.chatApprovalMode, .auto, "Auto is this chat's own mode")
        XCTAssertEqual(engine.configuration.approvalMode, .standard, "the global default is untouched")
        XCTAssertFalse(VitruvianCodeApprovalMode.globalChoices.contains(.auto))

        // On another connection the choice does nothing: never the chat's, never the global one.
        for other in [Self.liveACPProvider, Self.commandLineProvider] {
            engine.session.newChat()
            choose(other)
            ChatApprovalModeBadge.applySelection(.auto, session: engine.session, engine: engine)
            XCTAssertNil(engine.session.chatApprovalMode)
            XCTAssertEqual(engine.configuration.approvalMode, .standard)
        }
    }

    // MARK: - 4. Slash command metadata mapping

    func testSlashCommandMetadataMappingPreservesDescriptionsHintsAndPlainText() async throws {
        let agent = ScriptedACPAgent()
        let connection = ACPConnection(
            launchSpec: AgentProcessLaunchSpec(executable: "/bin/echo"),
            policy: .none,
            processFactory: agent.makeProcessFactory()
        )
        let reader = ACPEventStreamReader(connection.events)

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
                        "result": .object(["sessionId": .string("s-slash-meta")]),
                    ])
                ),
                .expectClientRequest(method: "session/prompt"),
                .agentSend(
                    .object([
                        "jsonrpc": .string("2.0"),
                        "method": .string("session/update"),
                        "params": .object([
                            "sessionId": .string("s-slash-meta"),
                            "update": .object([
                                "sessionUpdate": .string("available_commands_update"),
                                "availableCommands": .array([
                                    .object([
                                        "name": .string("/review"),
                                        "description": .string("Review **changes** [click](https://evil.example)"),
                                        "input": .object(["hint": .string("Optional focus area")]),
                                    ]),
                                    .object([
                                        "name": .string("compact"),
                                        "description": .string("Compact conversation history"),
                                    ]),
                                ]),
                            ]),
                        ]),
                    ])
                ),
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
            try await connection.start(AgentSessionRequest(workingDirectory: "/workspace"))
        }
        _ = try await withACPTestTimeout(seconds: 3.0) {
            try await connection.prompt([.text("Hi")])
        }
        try await withACPTestTimeout(seconds: 3.0) { try await driver.value }
        let events = try await reader.collectUntilFinished(timeout: 3.0)

        XCTAssertTrue(events.contains(.slashCommands(["review", "compact"])))
        let expectedReview = VitruvianCodeSlashCommand(
            name: "review",
            description: "Review **changes** [click](https://evil.example)",
            argumentHint: "Optional focus area",
            isBuiltIn: false
        )
        let expectedCompact = VitruvianCodeSlashCommand(
            name: "compact",
            description: "Compact conversation history",
            argumentHint: nil,
            isBuiltIn: false
        )
        XCTAssertTrue(events.contains(.availableCommands([expectedReview, expectedCompact])))
        await connection.stop()

        // Verify session merges descriptions and hints and inserts identically on selection.
        let rig = ComposerRig()
        let acpConn = ComposerControlMockConnection(
            spec: AgentConnectionSpec(provider: Self.liveACPProvider, workingDirectory: "/workspace")
        )
        var env = rig.environment
        env.makeConnection = { _ in acpConn }
        let liveSession = VitruvianCodeQuickPromptSession(environment: env, host: rig.host)
        liveSession.takeCheckpoint = { _ in nil }
        let config = VitruvianCodeConfiguration(approvalMode: .standard, activeProvider: Self.liveACPProvider)

        liveSession.send("Hi", configuration: config, agentPath: "/fake/agy")
        try await waitUntil("prompt sent") { acpConn.promptCalls.count == 1 }
        acpConn.emit(.availableCommands([expectedReview, expectedCompact]))
        try await waitUntil("agent commands updated") { !liveSession.agentSlashCommands.isEmpty }
        acpConn.emit(.finished(status: "completed", response: "OK", error: nil, conversationID: "s-slash-meta"))
        acpConn.finishPrompt(with: .endTurn)
        try await waitUntil("turn finished") { !liveSession.isRunning }

        let reviewCmd = try XCTUnwrap(liveSession.slashCommands.first(where: { $0.name == "review" }))
        XCTAssertEqual(reviewCmd.description, "Review **changes** [click](https://evil.example)")
        XCTAssertEqual(reviewCmd.argumentHint, "Optional focus area")
        XCTAssertFalse(reviewCmd.isBuiltIn)

        liveSession.completeSlashCommand(reviewCmd)
        XCTAssertEqual(liveSession.draft, "/review ")
        liveSession.completeSlashCommand(expectedCompact)
        XCTAssertEqual(liveSession.draft, "/compact")
        await liveSession.stopAll()
    }

    // MARK: - 5. @-mention encoding & safety

    func testMentionEncodingEmbeddedContextOnOffOverCapBinaryAndEscapes() async throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("acp-mentions-\(UUID().uuidString)", isDirectory: true)
        let workdir = tempRoot.appendingPathComponent("work", isDirectory: true)
        let outsideDir = tempRoot.appendingPathComponent("outside", isDirectory: true)
        try FileManager.default.createDirectory(at: workdir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outsideDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let textFile = workdir.appendingPathComponent("notes.md")
        try "# Hello\nBody\n".write(to: textFile, atomically: true, encoding: .utf8)

        let overCapFile = workdir.appendingPathComponent("huge.txt")
        let overCapData = Data(repeating: 0x61, count: VitruvianCodeDiffParser.maxMentionFileBytes + 1)
        try overCapData.write(to: overCapFile)

        let binaryFile = workdir.appendingPathComponent("blob.bin")
        try Data([0x00, 0xFF, 0xFE, 0x01]).write(to: binaryFile)

        let secretFile = outsideDir.appendingPathComponent("secret.txt")
        try "TOP_SECRET".write(to: secretFile, atomically: true, encoding: .utf8)

        let symlinkEscape = workdir.appendingPathComponent("escape.txt")
        try FileManager.default.createSymbolicLink(atPath: symlinkEscape.path, withDestinationPath: secretFile.path)

        let canonicalWorkdir = URL(fileURLWithPath: Self.canonicalPath(workdir.path))
        let canonicalTextURI = canonicalWorkdir.appendingPathComponent("notes.md").absoluteString
        let canonicalHugeURI = canonicalWorkdir.appendingPathComponent("huge.txt").absoluteString
        let canonicalBinaryURI = canonicalWorkdir.appendingPathComponent("blob.bin").absoluteString

        // 1. embeddedContext = true: regular UTF-8 -> resource; over-cap & binary -> resource_link; escapes -> omitted.
        let embeddedBlocks = ACPConnection.encodePromptBlocks(
            [
                .text("Check @notes.md @huge.txt @blob.bin @escape.txt @../outside/secret.txt"),
                .resource(path: textFile.path),
                .resource(path: overCapFile.path),
                .resource(path: binaryFile.path),
                .resource(path: symlinkEscape.path),
                .resource(path: secretFile.path),
            ],
            supportsImages: false,
            supportsEmbeddedContext: true,
            workingDirectory: workdir.path
        )
        XCTAssertEqual(embeddedBlocks.count, 4, "escapes and outside paths must not be sent at all")
        XCTAssertEqual(embeddedBlocks[0], .text("Check @notes.md @huge.txt @blob.bin @escape.txt @../outside/secret.txt"))
        XCTAssertEqual(
            embeddedBlocks[1],
            .resource(ACPEmbeddedResource(uri: canonicalTextURI, mimeType: "text/markdown", text: "# Hello\nBody\n"))
        )
        XCTAssertEqual(
            embeddedBlocks[2],
            .resourceLink(
                uri: canonicalHugeURI,
                name: "huge.txt",
                mimeType: "text/plain",
                size: overCapData.count
            )
        )
        XCTAssertEqual(
            embeddedBlocks[3],
            .resourceLink(
                uri: canonicalBinaryURI,
                name: "blob.bin",
                mimeType: "application/octet-stream",
                size: 4
            )
        )

        // 2. embeddedContext = false: regular UTF-8 falls back to resource_link; escapes still omitted.
        let linkOnlyBlocks = ACPConnection.encodePromptBlocks(
            [
                .text("Check @notes.md"),
                .resource(path: textFile.path),
                .resource(path: symlinkEscape.path),
                .resource(path: secretFile.path),
            ],
            supportsImages: false,
            supportsEmbeddedContext: false,
            workingDirectory: workdir.path
        )
        XCTAssertEqual(linkOnlyBlocks.count, 2)
        XCTAssertEqual(
            linkOnlyBlocks[1],
            .resourceLink(
                uri: canonicalTextURI,
                name: "notes.md",
                mimeType: "text/markdown",
                size: "# Hello\nBody\n".utf8.count
            )
        )
    }

    func testLiveSessionResolvesMentionsWarnsOnOutsidePathsAndKeepsCommandLinePlainText() async throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("session-mentions-\(UUID().uuidString)", isDirectory: true)
        let workdir = tempRoot.appendingPathComponent("work", isDirectory: true)
        let outsideDir = tempRoot.appendingPathComponent("outside", isDirectory: true)
        try FileManager.default.createDirectory(at: workdir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outsideDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let insideFile = workdir.appendingPathComponent("README.md")
        try "# Repo\n".write(to: insideFile, atomically: true, encoding: .utf8)
        let outsideFile = outsideDir.appendingPathComponent("secret.txt")
        try "secret".write(to: outsideFile, atomically: true, encoding: .utf8)
        let escapeLink = workdir.appendingPathComponent("escape-link.txt")
        try FileManager.default.createSymbolicLink(atPath: escapeLink.path, withDestinationPath: outsideFile.path)

        let connections = ComposerControlBox<[ComposerControlMockConnection]>([])
        let rig = ComposerRig()
        var env = rig.environment
        env.fileExists = { path in FileManager.default.fileExists(atPath: path) }
        env.makeConnection = { spec in
            let conn = ComposerControlMockConnection(spec: spec)
            connections.withValue { $0.append(conn) }
            return conn
        }
        let session = VitruvianCodeQuickPromptSession(environment: env, host: rig.host)
        session.takeCheckpoint = { _ in nil }

        let liveConfig = VitruvianCodeConfiguration(
            workingDirectory: workdir.path,
            approvalMode: .standard,
            activeProvider: Self.liveACPProvider
        )

        session.draft = "Inspect @README"
        session.completeMention(with: "README.md")
        XCTAssertEqual(session.draft, "Inspect @README.md ")
        session.draft += "and @"
        session.completeMention(with: "escape-link.txt")
        session.draft += "and @"
        session.completeMention(with: outsideFile.path)
        session.draft += "with @alice"
        let submitted = session.draft.trimmingCharacters(in: .whitespacesAndNewlines)

        session.send(submitted, configuration: liveConfig, agentPath: "/fake/agy")
        try await waitUntil("live prompt sent") { connections.value.first?.promptCalls.count == 1 }
        let conn = try XCTUnwrap(connections.value.first)
        let sentBlocks = try XCTUnwrap(conn.promptCalls.first)

        let canonicalInside = Self.canonicalPath(insideFile.path)
        XCTAssertEqual(sentBlocks, [.text(submitted), .resource(path: canonicalInside)])
        XCTAssertEqual(
            session.messages.first(where: { $0.role == .user })?.text,
            submitted,
            "visible @path must stay in the user message"
        )
        XCTAssertTrue(
            session.messages.contains { $0.role == .agent && $0.text.contains("escape-link.txt") },
            "user must see why symlink escape was not sent"
        )
        XCTAssertTrue(
            session.messages.contains { $0.role == .agent && $0.text.contains(outsideFile.path) },
            "user must see why outside path was not sent"
        )
        XCTAssertFalse(
            session.messages.contains { $0.role == .agent && $0.text.contains("alice") },
            "bare @handle must not trigger outside-workspace notice"
        )

        conn.emit(.finished(status: "completed", response: "Done", error: nil, conversationID: "s-mentions"))
        conn.finishPrompt(with: .endTurn)
        try await waitUntil("turn finished") { !session.isRunning }

        // Command-line chats keep today's plain text and emit no mention notices.
        let cliRig = ComposerRig()
        var cliEnv = cliRig.environment
        cliEnv.fileExists = { path in FileManager.default.fileExists(atPath: path) }
        let cliSession = VitruvianCodeQuickPromptSession(environment: cliEnv, host: cliRig.host)
        cliSession.takeCheckpoint = { _ in nil }
        let cliConfig = VitruvianCodeConfiguration(
            workingDirectory: workdir.path,
            approvalMode: .standard,
            activeProvider: Self.commandLineProvider
        )
        cliSession.send("Explain @README.md @\(outsideFile.path)", configuration: cliConfig, agentPath: "/fake/agy")
        XCTAssertEqual(cliRig.launches.count, 1)
        XCTAssertFalse(cliSession.messages.contains { $0.role == .agent && $0.text.contains("outside") })
        cliRig.finishCleanly()

        await session.stopAll()
    }

    func testPastedMentionOfSecretFileIsNeverEmbedded() async throws {
        let workdir = FileManager.default.temporaryDirectory
            .appendingPathComponent("pasted-mention-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workdir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workdir) }
        let secret = "DOTENV_CONTENTS_MARKER"
        try secret.write(to: workdir.appendingPathComponent(".env"), atomically: true, encoding: .utf8)
        try "# Repo\n".write(to: workdir.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)

        // The extractor itself: typed or pasted paths are plain text.
        XCTAssertEqual(VitruvianCodeMention.extractCandidates(in: "see @.env and @src/a.swift"), [])
        XCTAssertEqual(
            VitruvianCodeMention.extractCandidates(in: "see @README.md and @.env", pickedMentions: ["README.md"]),
            ["README.md"]
        )

        let connections = ComposerControlBox<[ComposerControlMockConnection]>([])
        let rig = ComposerRig()
        var env = rig.environment
        env.fileExists = { path in FileManager.default.fileExists(atPath: path) }
        env.makeConnection = { spec in
            let conn = ComposerControlMockConnection(spec: spec)
            connections.withValue { $0.append(conn) }
            return conn
        }
        let session = VitruvianCodeQuickPromptSession(environment: env, host: rig.host)
        session.takeCheckpoint = { _ in nil }
        let config = VitruvianCodeConfiguration(
            workingDirectory: workdir.path,
            approvalMode: .standard,
            activeProvider: Self.liveACPProvider
        )

        let pasted = "Please look at @.env and tell me what is wrong"
        session.send(pasted, configuration: config, agentPath: "/fake/agy")
        try await waitUntil("prompt sent") { connections.value.first?.promptCalls.count == 1 }
        let conn = try XCTUnwrap(connections.value.first)
        let sent = try XCTUnwrap(conn.promptCalls.first)
        XCTAssertEqual(sent, [.text(pasted)], "a pasted @path must not become a resource block")
        XCTAssertFalse(String(describing: sent).contains(secret))

        conn.emit(.finished(status: "completed", response: "ok", error: nil, conversationID: "s-pasted"))
        conn.finishPrompt(with: .endTurn)
        try await waitUntil("turn finished") { !session.isRunning }
        await session.stopAll()
    }

    // MARK: - Remembered choices survive a reconnect

    private static func modelOptions(_ models: [String], current: String) -> [AgentConfigOption] {
        [AgentConfigOption(id: "model", name: "Model", value: .string(current), options: models, category: "model")]
    }

    private struct ReconnectRig {
        let session: VitruvianCodeQuickPromptSession
        let connections: ComposerControlBox<[ComposerControlMockConnection]>
        let config: VitruvianCodeConfiguration
    }

    /// Chat with `sonnet`/`opus`; the user picks `opus`; the connection idles out.
    private func chatThatPickedOpusThenIdled(
        secondConnection: @escaping @MainActor (ComposerControlMockConnection) -> Void
    ) async throws -> ReconnectRig {
        let connections = ComposerControlBox<[ComposerControlMockConnection]>([])
        let rig = ComposerRig()
        var env = rig.environment
        env.makeConnection = { spec in
            let conn = ComposerControlMockConnection(spec: spec)
            if connections.value.isEmpty {
                conn.optionsOnStart = Self.modelOptions(["sonnet", "opus"], current: "sonnet")
                conn.nextSetConfigResult = Self.modelOptions(["sonnet", "opus"], current: "opus")
            } else {
                secondConnection(conn)
            }
            connections.withValue { $0.append(conn) }
            return conn
        }
        let session = VitruvianCodeQuickPromptSession(environment: env, host: rig.host)
        session.takeCheckpoint = { _ in nil }
        session.idleConnectionTimeout = 0.05
        let config = VitruvianCodeConfiguration(approvalMode: .standard, activeProvider: Self.liveACPProvider)

        session.send("one", configuration: config, agentPath: "/fake/agy")
        try await waitUntil("prompt 1") { connections.value.first?.promptCalls.count == 1 }
        let first = try XCTUnwrap(connections.value.first)
        try await waitUntil("options") { !session.liveState.configOptions.isEmpty }
        first.emit(.finished(status: "completed", response: "ok", error: nil, conversationID: "s-re"))
        first.finishPrompt(with: .endTurn)
        try await waitUntil("turn 1 done") { !session.isRunning }
        let picked = await session.setLiveConfigOption(id: "model", value: .string("opus"))
        XCTAssertTrue(picked)
        try await waitUntil("idle shutdown") { first.isStopped }
        return ReconnectRig(session: session, connections: connections, config: config)
    }

    func testChosenModelIsReappliedBeforeFirstPromptOnNewConnection() async throws {
        let r = try await chatThatPickedOpusThenIdled { conn in
            conn.optionsOnStart = Self.modelOptions(["sonnet", "opus"], current: "sonnet")
            conn.nextSetConfigResult = Self.modelOptions(["sonnet", "opus"], current: "opus")
        }
        r.session.send("two", configuration: r.config, agentPath: "/fake/agy")
        try await waitUntil("prompt 2") { r.connections.value.count == 2 && r.connections.value[1].promptCalls.count == 1 }
        let second = r.connections.value[1]
        XCTAssertEqual(second.callLog, ["set:model=string(\"opus\")", "prompt"], "set_config_option must come before the prompt")
        XCTAssertEqual(r.session.liveState.configOptions.first?.value, .string("opus"))
        second.emit(.finished(status: "completed", response: "ok", error: nil, conversationID: "s-re"))
        second.finishPrompt(with: .endTurn)
        try await waitUntil("turn 2 done") { !r.session.isRunning }
        await r.session.stopAll()
    }

    func testChoiceTheAgentNoLongerOffersIsDroppedAndPromptStillSent() async throws {
        let r = try await chatThatPickedOpusThenIdled { conn in
            conn.optionsOnStart = Self.modelOptions(["sonnet", "haiku"], current: "sonnet")
        }
        r.session.send("two", configuration: r.config, agentPath: "/fake/agy")
        try await waitUntil("prompt 2") { r.connections.value.count == 2 && r.connections.value[1].promptCalls.count == 1 }
        let second = r.connections.value[1]
        XCTAssertEqual(second.callLog, ["prompt"], "an option no longer offered is not re-applied")
        second.emit(.finished(status: "completed", response: "ok", error: nil, conversationID: "s-re"))
        second.finishPrompt(with: .endTurn)
        try await waitUntil("turn 2 done") { !r.session.isRunning }
        await r.session.stopAll()
    }

    func testFailedReapplySendsNoPrompt() async throws {
        let r = try await chatThatPickedOpusThenIdled { conn in
            conn.optionsOnStart = Self.modelOptions(["sonnet", "opus"], current: "sonnet")
            conn.failSetConfigOption = true
        }
        r.session.send("two", configuration: r.config, agentPath: "/fake/agy")
        try await waitUntil("turn 2 failed") { r.connections.value.count == 2 && !r.session.isRunning }
        let second = r.connections.value[1]
        XCTAssertEqual(second.callLog, ["set:model=string(\"opus\")"])
        XCTAssertTrue(second.promptCalls.isEmpty, "no prompt may go out on a different model")
        XCTAssertEqual(r.session.messages.last?.isError, true)
        await r.session.stopAll()
    }

    func testNewChatForgetsRememberedChoices() async throws {
        let r = try await chatThatPickedOpusThenIdled { conn in
            conn.optionsOnStart = Self.modelOptions(["sonnet", "opus"], current: "sonnet")
        }
        r.session.newChat()
        r.session.send("fresh", configuration: r.config, agentPath: "/fake/agy")
        try await waitUntil("fresh prompt") { r.connections.value.count == 2 && r.connections.value[1].promptCalls.count == 1 }
        XCTAssertEqual(r.connections.value[1].callLog, ["prompt"], "a new chat starts on the agent's defaults")
        r.connections.value[1].emit(.finished(status: "completed", response: "ok", error: nil, conversationID: "s-new"))
        r.connections.value[1].finishPrompt(with: .endTurn)
        try await waitUntil("fresh done") { !r.session.isRunning }
        await r.session.stopAll()
    }

    // MARK: - Helpers

    private static func canonicalPath(_ path: String) -> String {
        guard let ptr = Darwin.realpath(path, nil) else { return path }
        defer { free(ptr) }
        return String(cString: ptr)
    }

    private func waitUntil(
        _ label: String,
        timeoutSeconds: TimeInterval = 3.0,
        condition: @MainActor () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while !condition() {
            if Date() > deadline {
                XCTFail("Timed out waiting for: \(label)")
                return
            }
            await Task.yield()
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
    }
}

private final class ComposerControlBox<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: Value

    init(_ initial: Value) {
        self.storage = initial
    }

    var value: Value {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func withValue<T>(_ body: (inout Value) -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body(&storage)
    }
}

@MainActor
private final class ComposerControlMockConnection: PersistentAgentConnection {
    let spec: AgentConnectionSpec
    let capabilities = AgentCapabilities(embeddedContext: true, configOptions: true)
    let events: AsyncStream<AgentEvent>
    private let continuation: AsyncStream<AgentEvent>.Continuation

    private(set) var startCalls: [AgentSessionRequest] = []
    private(set) var promptCalls: [[PromptBlock]] = []
    private(set) var syncedModes: [(VitruvianCodeApprovalMode, Bool)] = []
    private(set) var setConfigCalls: [(String, AgentConfigValue)] = []
    private(set) var isStopped = false
    var isConnected: Bool { !isStopped }

    var holdSetConfigOption = false
    var failSetConfigOption = false
    /// Offered on `start`, as a real agent does with its new session.
    var optionsOnStart: [AgentConfigOption] = []
    /// Every protocol call in order: "set:<id>=<value>" and "prompt".
    private(set) var callLog: [String] = []
    var nextSetConfigResult: [AgentConfigOption] = []

    private var promptContinuation: CheckedContinuation<AgentStopReason, any Error>?
    private var setConfigContinuation: CheckedContinuation<[AgentConfigOption], any Error>?

    init(spec: AgentConnectionSpec) {
        self.spec = spec
        var captured: AsyncStream<AgentEvent>.Continuation!
        self.events = AsyncStream { captured = $0 }
        self.continuation = captured
    }

    func start(_ request: AgentSessionRequest) async throws -> String {
        startCalls.append(request)
        if !optionsOnStart.isEmpty { continuation.yield(.configOptions(optionsOnStart)) }
        return request.resumeSessionID ?? "mock-composer-1"
    }

    func syncPlanMode(_ planSwitch: Bool) async throws {
        try await syncMode(approvalMode: .standard, planSwitch: planSwitch)
    }

    func syncMode(approvalMode: VitruvianCodeApprovalMode, planSwitch: Bool) async throws {
        syncedModes.append((approvalMode, planSwitch))
    }

    func prompt(_ blocks: [PromptBlock]) async throws -> AgentStopReason {
        promptCalls.append(blocks)
        callLog.append("prompt")
        return try await withCheckedThrowingContinuation { cont in
            self.promptContinuation = cont
        }
    }

    func cancel() async {}

    func answer(_ requestID: String, _ choice: AgentAnswer) async throws {}

    func setConfigOption(_ id: String, _ value: AgentConfigValue) async throws -> [AgentConfigOption] {
        setConfigCalls.append((id, value))
        callLog.append("set:\(id)=\(value)")
        if holdSetConfigOption {
            return try await withCheckedThrowingContinuation { cont in
                self.setConfigContinuation = cont
            }
        }
        if failSetConfigOption {
            throw ACPConnectionError.notStarted
        }
        return nextSetConfigResult
    }

    func releaseSetConfigOption(returning result: Result<[AgentConfigOption], any Error>) {
        let cont = setConfigContinuation
        setConfigContinuation = nil
        cont?.resume(with: result)
    }

    func stop() async {
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
