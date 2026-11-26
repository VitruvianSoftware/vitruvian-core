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

/// Registry agents as providers (design step 5e, second half): the saved provider, the chat
/// connection that runs the installed copy, and the Settings list that adds, updates and
/// removes them. Downloads are fakes that hand back a ready-made executable; nothing real installs.
@MainActor
final class ACPRegistryAgentsTests: XCTestCase {
    private var scratch: String!
    private var state: String { (scratch as NSString).appendingPathComponent("state") }

    override func setUpWithError() throws {
        scratch = (NSTemporaryDirectory() as NSString).appendingPathComponent("acp-agents-\(UUID().uuidString)")
        try FileManager.default.createDirectory(atPath: scratch, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(atPath: scratch)
    }

    final class Downloads: @unchecked Sendable {
        private let lock = NSLock()
        private var _count = 0
        var count: Int { lock.lock(); defer { lock.unlock() }; return _count }
        func add() { lock.lock(); _count += 1; lock.unlock() }
    }

    /// A host whose download is a raw executable (no archive), so an install needs no network or tar.
    private func host(downloads: Downloads, failDownload: Bool = false, programs: [String: String] = [:]) -> ACPRegistryHost {
        ACPRegistryHost(
            fetch: { _, _, _ in throw URLError(.notConnectedToInternet) },
            download: { _, destination, _, _ in
                downloads.add()
                if failDownload { throw URLError(.cannotConnectToHost) }
                try "#!/bin/sh\necho agent\n".write(toFile: destination, atomically: true, encoding: .utf8)
                chmod(destination, 0o755)
                return "unchecked"
            },
            run: { _, _, _, _, _ in .init(status: 127, stdout: "") },
            findProgram: { name, _ in programs[name] }
        )
    }

    private func installer(_ host: ACPRegistryHost) -> ACPRegistryInstaller {
        ACPRegistryInstaller(stateDirectory: state, host: host, environment: ["PATH": "/usr/bin:/bin"],
                             platformTarget: "darwin-aarch64")
    }

    private func agent(_ id: String = "opencode", version: String = "2.4.1", binary: Bool = true,
                       uvx: String? = nil) -> ACPRegistry.Agent {
        ACPRegistry.Agent(
            id: id, name: id == "opencode" ? "OpenCode" : id.capitalized, version: version, description: "",
            authors: [], license: nil, website: nil, repository: nil, icon: nil,
            distribution: .init(
                binary: binary ? ["darwin-aarch64": .init(archive: "https://example.test/\(id)", cmd: "./\(id)",
                                                           sha256: nil, args: ["acp"], env: ["AGENT_MODE": "acp"])] : [:],
                npx: nil, uvx: uvx.map { .init(package: $0, args: [], env: [:]) }))
    }

    private func registryProvider(_ id: String = "opencode", version: String = "2.4.1") -> VitruvianCodeCLIProvider {
        VitruvianCodeCLIProvider(id: UUID(), name: "OpenCode", commandTemplate: "", isBuiltIn: false, connection: .acp,
                                 registryAgent: .init(agentID: id, version: version))
    }

    // MARK: The provider

    func testARegistryProviderRunsOverACPOnly() {
        let provider = registryProvider()
        XCTAssertEqual(provider.route, .registry)
        XCTAssertEqual(provider.availableConnections, [.acp])
        XCTAssertFalse(provider.supportsWorktree)
        XCTAssertEqual(VitruvianCodeSupport.defaultModels(for: .registry), [])
        XCTAssertFalse(VitruvianCodeHibernationEvaluator.supportsSessionResume(.registry))

        // A built-in provider is never routed as a registry agent, whatever it carries.
        var builtIn = VitruvianCodeCLIProvider.opencode
        builtIn.registryAgent = .init(agentID: "opencode", version: "2.4.1")
        XCTAssertEqual(builtIn.route, .opencode)
    }

    func testRegistryProviderIsSavedAndReadBack() throws {
        let provider = registryProvider()
        let decoded = try JSONDecoder().decode(VitruvianCodeCLIProvider.self, from: try JSONEncoder().encode(provider))
        XCTAssertEqual(decoded, provider)
        XCTAssertEqual(decoded.registryAgent, .init(agentID: "opencode", version: "2.4.1"))

        // A provider saved before registry agents existed reads as it did.
        let old = #"{"id":"\#(UUID().uuidString)","name":"Aider","commandTemplate":"aider {prompt}","isBuiltIn":false}"#
        let legacy = try JSONDecoder().decode(VitruvianCodeCLIProvider.self, from: Data(old.utf8))
        XCTAssertNil(legacy.registryAgent)
        XCTAssertEqual(legacy.route, .custom)
    }

    func testMissingInstallIsNamedPlainly() {
        let strings = VitruvianCodeHostStrings()
        XCTAssertEqual(strings.missingProgram(of: registryProvider()),
                       "OpenCode is not installed. Add it again in Settings, under Providers.")
    }

    // MARK: The chat connection

    func testChatRunsTheInstalledCopyAndNeverInstalls() async throws {
        let downloads = Downloads()
        let registry = installer(host(downloads: downloads))
        let provider = registryProvider()
        let spec = AgentConnectionSpec(
            provider: provider,
            configuration: VitruvianCodeConfiguration(approvalMode: .auto, model: "", effort: .high, activeProvider: provider),
            agentPath: nil, workingDirectory: "/work/project", ollamaDefaultModel: "",
            turnModes: AgentTurnModes(plan: false, worktree: false, attachments: [], fork: false),
            environment: ["PATH": "/usr/bin:/bin", "HOME": scratch])

        XCTAssertNil(ACPRegistryConnection.launchSpec(spec: spec, stateDirectory: state, home: scratch),
                     "with nothing installed a chat has nothing to run")
        XCTAssertEqual(downloads.count, 0)

        let install = try await registry.install(agent())
        let launch = try XCTUnwrap(ACPRegistryConnection.launchSpec(spec: spec, stateDirectory: state, home: scratch))
        XCTAssertEqual(launch.executable, install.executablePath)
        XCTAssertEqual(launch.arguments, ["acp"])
        XCTAssertEqual(launch.environment["AGENT_MODE"], "acp")
        XCTAssertEqual(launch.workingDirectory, "/work/project")
        XCTAssertEqual(downloads.count, 1)

        // Another version than the one installed is not run.
        var other = spec
        other.provider = registryProvider(version: "2.5.0")
        XCTAssertNil(ACPRegistryConnection.launchSpec(spec: other, stateDirectory: state, home: scratch))
    }

    func testEngineGivesARegistryProviderTheACPConnection() {
        var environment = VitruvianCodeEngine.Environment.live(stateDirectoryOverride: state)
        environment.makeConnection = environment.makeConnection // the default factory
        let provider = registryProvider()
        let spec = AgentConnectionSpec(
            provider: provider,
            configuration: VitruvianCodeConfiguration(approvalMode: .auto, model: "", effort: .high, activeProvider: provider),
            agentPath: nil, workingDirectory: scratch, ollamaDefaultModel: "",
            turnModes: AgentTurnModes(plan: false, worktree: false, attachments: [], fork: false),
            environment: [:])
        XCTAssertTrue(environment.makeConnection(spec) is ACPConnection)
    }

    // MARK: The Settings list

    func testStatusOfEachAgent() async throws {
        let list = ACPRegistryAgentList(installer: installer(host(downloads: Downloads())))
        XCTAssertEqual(list.status(of: agent(), providers: []), .available)
        XCTAssertEqual(list.status(of: agent("tool", binary: false, uvx: "tool==1.0.0"), providers: []), .needsRunner("uv"))
        XCTAssertEqual(list.status(of: agent("linux-only", binary: false), providers: []), .noBuildForThisMac)
        XCTAssertEqual(list.status(of: agent(), providers: [registryProvider()]), .added(version: "2.4.1"))
        XCTAssertEqual(list.status(of: agent(version: "2.5.0"), providers: [registryProvider()]),
                       .updateAvailable(installed: "2.4.1", latest: "2.5.0"))
    }

    func testAddInstallsAndGivesAnACPProvider() async throws {
        let downloads = Downloads()
        let list = ACPRegistryAgentList(installer: installer(host(downloads: downloads)))
        let provider = try await XCTUnwrapAsync(await list.add(agent()))
        XCTAssertEqual(provider.name, "OpenCode")
        XCTAssertFalse(provider.isBuiltIn)
        XCTAssertEqual(provider.connection, .acp)
        XCTAssertEqual(provider.registryAgent, .init(agentID: "opencode", version: "2.4.1"))
        XCTAssertEqual(downloads.count, 1)
        XCTAssertNotNil(ACPRegistryInstaller.installedReceipt(stateDirectory: state, agentID: "opencode", version: "2.4.1"))
    }

    /// The built-in OpenCode and OpenCode from the registry were both called "OpenCode" in the
    /// provider list and its menu (seen in the test copy on 2026-11-25).
    func testAddedAgentIsNamedApartFromAProviderWithItsName() async throws {
        let list = ACPRegistryAgentList(installer: installer(host(downloads: Downloads())))
        let added = try await XCTUnwrapAsync(await list.add(agent(), existing: [.antigravity, .claude, .opencode]))
        XCTAssertEqual(added.name, "OpenCode (ACP)")
        try await registryInstallerReset()
        let alone = try await XCTUnwrapAsync(await list.add(agent(), existing: [.antigravity, .claude]))
        XCTAssertEqual(alone.name, "OpenCode")
    }

    private func registryInstallerReset() async throws {
        try? FileManager.default.removeItem(atPath: state + "/agents")
    }

    func testFailedAddSavesNothingAndSaysWhy() async {
        let list = ACPRegistryAgentList(installer: installer(host(downloads: Downloads(), failDownload: true)))
        let provider = await list.add(agent())
        XCTAssertNil(provider)
        XCTAssertNotNil(list.errors["opencode"])
        XCTAssertEqual(list.status(of: agent(), providers: []), .available, "a failed add can be tried again")
    }

    func testUpdateMovesToTheNewVersionAndRemovesTheOld() async throws {
        let list = ACPRegistryAgentList(installer: installer(host(downloads: Downloads())))
        let first = try await XCTUnwrapAsync(await list.add(agent()))
        let moved = try await XCTUnwrapAsync(await list.update(first, to: agent(version: "2.5.0"), others: [first]))
        XCTAssertEqual(moved.id, first.id, "the same provider, so chats keep it")
        XCTAssertEqual(moved.registryAgent?.version, "2.5.0")
        XCTAssertNotNil(ACPRegistryInstaller.installedReceipt(stateDirectory: state, agentID: "opencode", version: "2.5.0"))
        XCTAssertNil(ACPRegistryInstaller.installedReceipt(stateDirectory: state, agentID: "opencode", version: "2.4.1"))
    }

    func testRemovingKeepsACopyAnotherProviderStillRuns() async throws {
        let list = ACPRegistryAgentList(installer: installer(host(downloads: Downloads())))
        let first = try await XCTUnwrapAsync(await list.add(agent()))
        var second = first
        second.id = UUID()

        await list.removed(first, remaining: [second])
        XCTAssertNotNil(ACPRegistryInstaller.installedReceipt(stateDirectory: state, agentID: "opencode", version: "2.4.1"))

        await list.removed(second, remaining: [])
        XCTAssertNil(ACPRegistryInstaller.installedReceipt(stateDirectory: state, agentID: "opencode", version: "2.4.1"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: state + "/agents/opencode"))
    }

    func testOpeningTheListInstallsNothing() async {
        let downloads = Downloads()
        let list = ACPRegistryAgentList(installer: installer(host(downloads: downloads)))
        await list.load()
        XCTAssertNotNil(list.loadError, "offline with no saved copy says so")
        for candidate in [agent(), agent("tool", binary: false, uvx: "tool==1.0.0")] {
            _ = list.status(of: candidate, providers: [])
        }
        XCTAssertEqual(downloads.count, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: state + "/agents"))
    }

    // MARK: What a failed turn says

    /// A chat with a registry agent, over the real ACP client, talking to a scripted agent.
    private func chatWithScriptedAgent(_ agent: ScriptedACPAgent) -> VitruvianCodeQuickPromptSession {
        let rig = ComposerRig()
        var environment = rig.environment
        environment.makeConnection = { _ in
            ACPConnection(launchSpec: AgentProcessLaunchSpec(executable: "/fake/opencode", arguments: ["acp"]),
                          policy: .none, processFactory: agent.makeProcessFactory())
        }
        let session = VitruvianCodeQuickPromptSession(environment: environment, host: rig.host)
        session.takeCheckpoint = { _ in nil }
        return session
    }

    private static func ok(_ fields: [String: ACPJSONValue]) -> ACPJSONValue {
        .object(["jsonrpc": .string("2.0"), "id": .string("$id"), "result": .object(fields)])
    }

    private static func refused(_ code: Int, _ message: String) -> ACPJSONValue {
        .object(["jsonrpc": .string("2.0"), "id": .string("$id"),
                 "error": .object(["code": .int(code), "message": .string(message)])])
    }

    /// OpenCode refused a turn with "Model is unavailable." and the chat said only "The agent
    /// stopped with an error." (test copy, 2026-11-25). The agent's own words must reach the chat.
    func testAnAgentRefusingTheTurnIsShownInItsOwnWords() async throws {
        let agent = ScriptedACPAgent()
        let session = chatWithScriptedAgent(agent)
        let driver = Task {
            try await agent.playSteps([
                .expectClientRequest(method: "initialize"),
                .agentSend(Self.ok(["protocolVersion": .int(1)])),
                .expectClientRequest(method: "session/new"),
                .agentSend(Self.ok(["sessionId": .string("ses_1")])),
                .expectClientRequest(method: "session/prompt"),
                .agentSend(Self.refused(-32603, "Internal error: Upstream request failed: Model is unavailable.")),
            ])
        }
        let provider = registryProvider()
        session.send("hello", configuration: VitruvianCodeConfiguration(approvalMode: .yolo, activeProvider: provider),
                     agentPath: "/fake/opencode")
        try await withACPTestTimeout(seconds: 5) { try await driver.value }
        for _ in 0..<2000 where session.isRunning { await Task.yield() }
        let shown = (session.messages.filter(\.isError).map(\.text) + [session.lastLiveFailure?.message ?? ""])
        XCTAssertTrue(shown.contains { $0.contains("Model is unavailable.") }, "\(shown)")
    }

    /// OpenCode's modes are "build" and "plan". The chat sent its approval mode as the session's
    /// "default" mode before every turn, OpenCode has none by that name, and no prompt was ever
    /// sent (wire log from the test copy, 2026-11-25). With plan off, a registry agent's chat
    /// sends no mode, whatever the approval mode, as T3 Code's ACP adapter does.
    func testARegistryAgentsChatSendsNoModeChange() async throws {
        let agent = ScriptedACPAgent()
        let provider = registryProvider()
        let spec = AgentConnectionSpec(
            provider: provider,
            configuration: VitruvianCodeConfiguration(approvalMode: .yolo, model: "", effort: .high, activeProvider: provider),
            agentPath: nil, workingDirectory: "/w", ollamaDefaultModel: "",
            turnModes: AgentTurnModes(plan: false, worktree: false, attachments: [], fork: false),
            environment: [:])
        let connection = ACPRegistryConnection.make(spec: spec, environment: .live(stateDirectoryOverride: state),
                                                    processFactory: agent.makeProcessFactory())
        func select(_ id: String, _ category: String, _ current: String, _ values: [String]) -> ACPJSONValue {
            .object(["id": .string(id), "name": .string(id), "category": .string(category), "type": .string("select"),
                     "currentValue": .string(current),
                     "options": .array(values.map { .object(["value": .string($0), "name": .string($0)]) })])
        }
        let driver = Task {
            try await agent.playSteps([
                .expectClientRequest(method: "initialize"),
                .agentSend(Self.ok(["protocolVersion": .int(1)])),
                .expectClientRequest(method: "session/new"),
                .agentSend(Self.ok(["sessionId": .string("ses_1"), "configOptions": .array([
                    select("model", "model", "opencode/free", ["opencode/free"]),
                    select("mode", "mode", "build", ["build", "plan"]),
                ])])),
                .expectClientRequest(method: "session/prompt"),
                .agentSend(Self.ok(["stopReason": .string("end_turn")])),
            ])
        }
        _ = try await withACPTestTimeout(seconds: 3) { try await connection.start(AgentSessionRequest(workingDirectory: "/w")) }
        for mode in VitruvianCodeApprovalMode.allCases where mode != .plan {
            try await connection.syncMode(approvalMode: mode, planSwitch: false)
        }
        let stop = try await withACPTestTimeout(seconds: 3) { try await connection.prompt([.text("hello")]) }
        try await withACPTestTimeout(seconds: 3) { try await driver.value }
        XCTAssertEqual(stop, .endTurn)
        let methods = await agent.allClientMessages().compactMap { $0.objectValue?["method"]?.stringValue }
        XCTAssertEqual(methods, ["initialize", "session/new", "session/prompt"])
        await connection.stop()
    }

    private func registryConnection(_ agent: ScriptedACPAgent) -> ACPConnection {
        let provider = registryProvider()
        let spec = AgentConnectionSpec(
            provider: provider,
            configuration: VitruvianCodeConfiguration(approvalMode: .yolo, model: "", effort: .high, activeProvider: provider),
            agentPath: nil, workingDirectory: "/w", ollamaDefaultModel: "",
            turnModes: AgentTurnModes(plan: false, worktree: false, attachments: [], fork: false),
            environment: [:])
        return ACPRegistryConnection.make(spec: spec, environment: .live(stateDirectoryOverride: state),
                                          processFactory: agent.makeProcessFactory())
    }

    /// Plan on a registry agent uses the agent's own plan mode and plan off puts its own mode back,
    /// as T3 Code's ACP adapter does (`configureSession`). OpenCode offers its modes as a session
    /// option with values "build" and "plan".
    func testPlanSwitchesARegistryAgentToItsOwnPlanModeAndBack() async throws {
        let agent = ScriptedACPAgent()
        let connection = registryConnection(agent)
        let mode: ACPJSONValue = .object([
            "id": .string("mode"), "name": .string("Mode"), "category": .string("mode"), "type": .string("select"),
            "currentValue": .string("build"),
            "options": .array([.object(["value": .string("build"), "name": .string("Build")]),
                               .object(["value": .string("plan"), "name": .string("Plan")])]),
        ])
        let driver = Task {
            try await agent.playSteps([
                .expectClientRequest(method: "initialize"),
                .agentSend(Self.ok(["protocolVersion": .int(1)])),
                .expectClientRequest(method: "session/new"),
                .agentSend(Self.ok(["sessionId": .string("ses_1"), "configOptions": .array([mode])])),
                .expectClientRequest(method: "session/set_config_option"),
                .agentSend(Self.ok([:])),
                .expectClientRequest(method: "session/set_config_option"),
                .agentSend(Self.ok([:])),
            ])
        }
        _ = try await withACPTestTimeout(seconds: 3) { try await connection.start(AgentSessionRequest(workingDirectory: "/w")) }
        try await connection.syncMode(approvalMode: .yolo, planSwitch: true)
        try await connection.syncMode(approvalMode: .yolo, planSwitch: true)
        try await connection.syncMode(approvalMode: .yolo, planSwitch: false)
        try await connection.syncMode(approvalMode: .standard, planSwitch: false)
        try await withACPTestTimeout(seconds: 3) { try await driver.value }
        let sets = await agent.allClientMessages()
            .filter { $0.objectValue?["method"]?.stringValue == "session/set_config_option" }
            .compactMap { $0.objectValue?["params"]?.objectValue }
        XCTAssertEqual(sets.map { $0["configId"]?.stringValue }, ["mode", "mode"])
        XCTAssertEqual(sets.map { $0["value"]?.stringValue }, ["plan", "build"], "plan, then the agent's own mode back")
        await connection.stop()
    }

    /// An agent that offers its modes the older way (`modes`, set with `session/set_mode`) gets the
    /// same: its plan mode with plan on, its own mode back with plan off.
    func testPlanUsesSetModeForAnAgentWithOnlyModes() async throws {
        let agent = ScriptedACPAgent()
        let connection = registryConnection(agent)
        let modes: ACPJSONValue = .object([
            "currentModeId": .string("code"),
            "availableModes": .array([.object(["id": .string("code"), "name": .string("Code")]),
                                      .object(["id": .string("architect"), "name": .string("Architect")])]),
        ])
        let driver = Task {
            try await agent.playSteps([
                .expectClientRequest(method: "initialize"),
                .agentSend(Self.ok(["protocolVersion": .int(1)])),
                .expectClientRequest(method: "session/new"),
                .agentSend(Self.ok(["sessionId": .string("ses_1"), "modes": modes])),
                .expectClientRequest(method: "session/set_mode"),
                .agentSend(Self.ok([:])),
                .expectClientRequest(method: "session/set_mode"),
                .agentSend(Self.ok([:])),
            ])
        }
        _ = try await withACPTestTimeout(seconds: 3) { try await connection.start(AgentSessionRequest(workingDirectory: "/w")) }
        try await connection.syncMode(approvalMode: .plan, planSwitch: false)
        try await connection.syncMode(approvalMode: .acceptEdits, planSwitch: false)
        try await withACPTestTimeout(seconds: 3) { try await driver.value }
        let sets = await agent.allClientMessages()
            .filter { $0.objectValue?["method"]?.stringValue == "session/set_mode" }
            .compactMap { $0.objectValue?["params"]?.objectValue?["modeId"]?.stringValue }
        XCTAssertEqual(sets, ["architect", "code"])
        await connection.stop()
    }

    func testPlanModeIDsAreRecognised() {
        for id in ["plan", "architect", "https://agentclientprotocol.com/protocol/session-modes#plan"] {
            XCTAssertTrue(ACPConnection.isPlanModeID(id), id)
        }
        for id in ["build", "default", "code", "planner", "#build"] {
            XCTAssertFalse(ACPConnection.isPlanModeID(id), id)
        }
    }

    /// Retry resumed a session the agent no longer had, and the chat again said only the generic
    /// sentence. The agent's reason must reach the chat here too.
    func testAFailedResumeIsShownInTheAgentsOwnWords() async throws {
        let agent = ScriptedACPAgent()
        let session = chatWithScriptedAgent(agent)
        session.resume(VitruvianCodeSessionSummary(id: "ses_gone", title: "Old", steps: 1, modified: nil),
                       configuration: VitruvianCodeConfiguration(approvalMode: .yolo, activeProvider: registryProvider()))
        let driver = Task {
            try await agent.playSteps([
                .expectClientRequest(method: "initialize"),
                .agentSend(Self.ok(["protocolVersion": .int(1),
                                    "agentCapabilities": .object(["sessionCapabilities": .object(["resume": .object([:])])])])),
                .expectClientRequest(method: "session/resume"),
                .agentSend(Self.refused(-32602, "Invalid params: session not found: ses_gone")),
            ])
        }
        let provider = registryProvider()
        session.send("hello", configuration: VitruvianCodeConfiguration(approvalMode: .yolo, activeProvider: provider),
                     agentPath: "/fake/opencode")
        try await withACPTestTimeout(seconds: 5) { try await driver.value }
        for _ in 0..<2000 where session.isRunning { await Task.yield() }
        let shown = (session.messages.filter(\.isError).map(\.text) + [session.lastLiveFailure?.message ?? ""])
        XCTAssertTrue(shown.contains { $0.contains("session not found") }, "\(shown)")
    }

    /// The registry sheet in Settings once opened as an empty box: its list was made in the same
    /// tap that opened it, and the sheet, built with the value from before the tap, drew nothing.
    /// The app cannot be linked into a test (it has `@main`), so its source is read: the list must
    /// exist with the view, and the sheet must show the picker with no condition on the list.
    func testRegistrySheetNeverWaitsOnAListMadeByTheTap() throws {
        let settings = try XCTUnwrap(appSource("SettingsView.swift"), "could not find SettingsView.swift")
        XCTAssertTrue(settings.contains("@StateObject private var registryList: ACPRegistryAgentList"),
                      "the list is made with the view")
        let sheet = try XCTUnwrap(settings.range(of: ".sheet(isPresented: $showRegistryPicker) {"), "the sheet is there")
        let body = String(settings[sheet.upperBound...].prefix(200))
        let picker = try XCTUnwrap(body.range(of: "RegistryAgentPicker(list: registryList"), body)
        XCTAssertFalse(body[..<picker.lowerBound].contains("if "), "nothing gates the picker: \(body)")
        XCTAssertFalse(settings.contains(" registryList = "), "the list is never made later, in a tap")
    }

    /// Deleting the last provider in Settings crashed the app (seen in the test copy on
    /// 2026-11-25): the delete read the row's provider after removing it, past the list's end.
    /// After the removal, the delete must use only what it read before.
    func testDeletingAProviderReadsTheRowOnlyBeforeRemovingIt() throws {
        let settings = try XCTUnwrap(appSource("SettingsView.swift"), "could not find SettingsView.swift")
        let start = try XCTUnwrap(settings.range(of: "onDelete: provider.isBuiltIn ? nil : {"), "the delete is there")
        let body = String(settings[start.upperBound...].prefix(900))
        let removal = try XCTUnwrap(body.range(of: "configManager.providers.removeAll"), body)
        let afterRemoval = body[removal.lowerBound...]
        let end = afterRemoval.range(of: "\n                            }\n")?.lowerBound ?? afterRemoval.endIndex
        let rest = afterRemoval[..<end]
        XCTAssertFalse(rest.contains("provider."), "nothing reads the removed row after the removal: \(rest)")
    }

    private func appSource(_ name: String) -> String? {
        let relative = "apps/desktop/vitruvian-code/macos/Sources/VitruvianCode/\(name)"
        var candidates: [String] = []
        let environment = ProcessInfo.processInfo.environment
        if let runfiles = environment["TEST_SRCDIR"] {
            for workspace in [environment["TEST_WORKSPACE"], "_main"].compactMap({ $0 }) {
                candidates.append("\(runfiles)/\(workspace)/\(relative)")
            }
        }
        let here = (#filePath as NSString).deletingLastPathComponent
        candidates.append((here as NSString).deletingLastPathComponent + "/Sources/VitruvianCode/\(name)")
        guard let path = candidates.first(where: { FileManager.default.fileExists(atPath: $0) }) else { return nil }
        return try? String(contentsOfFile: path, encoding: .utf8)
    }

    private func XCTUnwrapAsync<T>(_ value: T?, file: StaticString = #filePath, line: UInt = #line) async throws -> T {
        try XCTUnwrap(value, file: file, line: line)
    }
}
