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

/// The chat's MCP status panel: what each agent loaded, where it is configured, and that it
/// never shows a secret.
@MainActor
final class AgentMCPStatusTests: XCTestCase {
    private var root: URL!
    private var home: URL!
    private var work: URL!
    private var suites: [(UserDefaults, String)] = []

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("agent-mcp-status-\(UUID().uuidString.prefix(8))", isDirectory: true)
        home = root.appendingPathComponent("home", isDirectory: true)
        work = root.appendingPathComponent("work", isDirectory: true)
        for folder in [home!, work!] {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        }
    }

    override func tearDown() {
        for (defaults, name) in suites { defaults.removePersistentDomain(forName: name) }
        suites.removeAll()
        try? FileManager.default.removeItem(at: root)
    }

    private func environment() -> VitruvianCodeEngine.Environment {
        let state = root.appendingPathComponent("state").path
        var live = VitruvianCodeEngine.Environment.live(stateDirectoryOverride: state)
        suites.append((live.defaults, VitruvianCodeSupport.preferencesSuiteName(
            bundleIdentifier: Bundle.main.bundleIdentifier ?? "com.vitruviansoftware.vitruvian-code",
            stateDirectory: state
        )))
        live.home = home.path
        live.processEnvironment = ["PATH": "/usr/bin"]
        return live
    }

    private func status(_ name: String, _ status: String, source: String? = nil, scope: String? = nil,
                        error: String? = nil) -> ClaudeMCPServerStatus {
        ClaudeMCPServerStatus(name: name, status: status, serverInfo: nil, error: error, scope: scope, source: source, tools: nil)
    }

    // MARK: - Claude

    func testClaudesStatusesMapToStatesSourcesAndConfigFiles() {
        let rows = AgentMCPStatusReader.rows(
            fromClaude: [
                status("user-one", "connected", source: "user"),
                status("local-one", "needs-auth", source: "local"),
                status("project-one", "pending", source: "project"),
                status("connector", "connected", source: "claudeai"),
                status("managed-one", "disabled", source: "managed"),
                status("plugin-one", "failed", source: "plugin", error: "  spawn ENOENT  "),
                status("old-claude", "connected", scope: "project"),
                status("odd", "weird", source: "sdk", error: "not failed, so not shown"),
            ],
            workingDirectory: work.path, home: home.path, configDirectory: nil
        )
        let byName = Dictionary(uniqueKeysWithValues: rows.map { ($0.name, $0) })
        let claudeJSON = home.appendingPathComponent(".claude.json").path
        XCTAssertEqual(byName["user-one"], .init(name: "user-one", state: .connected, source: .claudeUser, configPath: claudeJSON))
        XCTAssertEqual(byName["local-one"], .init(name: "local-one", state: .needsSignIn, source: .claudeLocal, configPath: claudeJSON))
        XCTAssertEqual(byName["project-one"], .init(name: "project-one", state: .pending, source: .claudeProject,
                                                    configPath: work.appendingPathComponent(".mcp.json").path))
        XCTAssertEqual(byName["connector"], .init(name: "connector", state: .connected, source: .claudeAI))
        XCTAssertEqual(byName["managed-one"], .init(name: "managed-one", state: .disabled, source: .claudeManaged,
                                                    configPath: AgentMCPStatusReader.claudeManagedConfigPath))
        XCTAssertEqual(byName["plugin-one"], .init(name: "plugin-one", state: .failed, detail: "spawn ENOENT", source: .claudePlugin))
        XCTAssertEqual(byName["old-claude"]?.source, .claudeProject, "scope stands in on an older claude")
        XCTAssertEqual(byName["odd"], .init(name: "odd", state: .unknown, source: .claudeOther))
        XCTAssertEqual(rows.map(\.name), rows.map(\.name).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending })
    }

    func testTheClaudeConfigFolderMovesTheUserConfig() {
        let rows = AgentMCPStatusReader.rows(fromClaude: [status("u", "connected", source: "user")],
                                             workingDirectory: work.path, home: home.path, configDirectory: "/cfg/claude")
        XCTAssertEqual(rows.first?.configPath, "/cfg/claude/.claude.json")
    }

    func testAClaudeStatusWithItsConfigDecodesWithoutIt() throws {
        // The helper drops `config` (with its env and headers); a status that still had it must
        // not carry it into the panel.
        let json = #"{"name":"remote","status":"connected","source":"user","config":{"type":"http","url":"https://h.example/mcp","headers":{"Authorization":"Bearer leak-1"},"env":{"K":"leak-2"}}}"#
        let decoded = try JSONDecoder().decode(ClaudeMCPServerStatus.self, from: Data(json.utf8))
        let rows = AgentMCPStatusReader.rows(fromClaude: [decoded], workingDirectory: work.path, home: home.path, configDirectory: nil)
        let shown = String(describing: rows)
        for secret in ["leak-1", "leak-2", "h.example"] {
            XCTAssertFalse(shown.contains(secret), shown)
        }
    }

    // MARK: - agy

    private static let agyConfig = """
    { "mcpServers": {
        "github": { "command": "docker", "args": ["run", "ghcr.io/github/mcp"], "env": { "GITHUB_TOKEN": "agy-secret-1" } },
        "remote": { "serverUrl": "https://agy-remote.example/mcp", "headers": { "Authorization": "Bearer agy-secret-2" } },
        "Beeper": { "serverUrl": "http://10.0.0.2/mcp", "disabled": true }
    } }
    """

    func testAgysConfigGivesNamesAndOffAndNeverItsSecrets() {
        let rows = AgentMCPStatusReader.rows(fromAgyConfig: Self.agyConfig, path: "/g/mcp_config.json")
        XCTAssertEqual(rows, [
            .init(name: "Beeper", state: .disabled, source: .agySettings, configPath: "/g/mcp_config.json"),
            .init(name: "github", state: .unknown, source: .agySettings, configPath: "/g/mcp_config.json"),
            .init(name: "remote", state: .unknown, source: .agySettings, configPath: "/g/mcp_config.json"),
        ])
        let shown = String(describing: rows)
        for secret in ["agy-secret-1", "agy-secret-2", "docker", "agy-remote.example", "10.0.0.2"] {
            XCTAssertFalse(shown.contains(secret), "\(secret) in \(shown)")
        }
        XCTAssertEqual(AgentMCPStatusReader.rows(fromAgyConfig: "not json", path: "/x"), [])
    }

    func testAgysConfigIsTheFirstFileThereIs() throws {
        let gemini = home.appendingPathComponent(".gemini")
        let second = gemini.appendingPathComponent("config/mcp_config.json")
        try FileManager.default.createDirectory(at: second.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Self.agyConfig.write(to: second, atomically: true, encoding: .utf8)
        let env = environment()
        let rows = AgentMCPStatusReader.agyRows(geminiHome: gemini.path, fileExists: env.fileExists, readFile: env.readFile)
        XCTAssertEqual(rows.first?.configPath, second.path, "antigravity/ is not there, so config/ is read")
        let first = gemini.appendingPathComponent("antigravity/mcp_config.json")
        try FileManager.default.createDirectory(at: first.deletingLastPathComponent(), withIntermediateDirectories: true)
        try #"{"mcpServers":{"only":{"command":"x"}}}"#.write(to: first, atomically: true, encoding: .utf8)
        XCTAssertEqual(AgentMCPStatusReader.agyRows(geminiHome: gemini.path, fileExists: env.fileExists, readFile: env.readFile)
            .map(\.name), ["only"])
    }

    // MARK: - In a chat

    func testTheControlIsOnlyForLiveClaudeAndAgyChats() {
        let session = VitruvianCodeQuickPromptSession(environment: environment(), host: MCPStatusTestHost())
        var agy = VitruvianCodeCLIProvider.antigravity
        var claude = VitruvianCodeCLIProvider.claude
        XCTAssertNil(session.mcpStatusAgent(configuration: VitruvianCodeConfiguration(activeProvider: agy)), "command line by default")
        XCTAssertNil(session.mcpStatusAgent(configuration: VitruvianCodeConfiguration(activeProvider: claude)))
        agy.connection = .commandLine
        XCTAssertNil(session.mcpStatusAgent(configuration: VitruvianCodeConfiguration(activeProvider: agy)))
        agy.connection = .acp
        claude.connection = .claudeSDK
        XCTAssertEqual(session.mcpStatusAgent(configuration: VitruvianCodeConfiguration(activeProvider: agy)), .agy)
        XCTAssertEqual(session.mcpStatusAgent(configuration: VitruvianCodeConfiguration(activeProvider: claude)), .claude)
        claude.connection = .claudeACP
        XCTAssertNil(session.mcpStatusAgent(configuration: VitruvianCodeConfiguration(activeProvider: claude)))
    }

    func testAnAgyChatsPanelReadsAgysConfigAndNeverWritesIt() async throws {
        let file = home.appendingPathComponent(".gemini/antigravity/mcp_config.json")
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Self.agyConfig.write(to: file, atomically: true, encoding: .utf8)
        let before = try FileManager.default.attributesOfItem(atPath: file.path)[.modificationDate] as? Date
        let session = VitruvianCodeQuickPromptSession(environment: environment(), host: MCPStatusTestHost())
        var agy = VitruvianCodeCLIProvider.antigravity
        agy.connection = .acp
        let configuration = VitruvianCodeConfiguration(workingDirectory: work.path, activeProvider: agy)
        await session.openMCPStatus(configuration: configuration)
        let panel = try XCTUnwrap(session.mcpStatusPanel)
        XCTAssertEqual(panel.agent, .agy)
        XCTAssertFalse(panel.isLoading)
        XCTAssertNil(panel.problem)
        XCTAssertEqual(panel.servers.map(\.name), ["Beeper", "github", "remote"])
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), Self.agyConfig, "read only")
        XCTAssertEqual(try FileManager.default.attributesOfItem(atPath: file.path)[.modificationDate] as? Date, before)
        session.closeMCPStatus()
        XCTAssertNil(session.mcpStatusPanel)
    }

    func testAClaudeChatsPanelAsksTheLiveSessionAndFollowsAReconnect() async throws {
        var env = environment()
        var made: [MCPStatusConnection] = []
        env.makeConnection = { _ in
            let connection = MCPStatusConnection()
            made.append(connection)
            return connection
        }
        let session = VitruvianCodeQuickPromptSession(environment: env, host: MCPStatusTestHost())
        session.takeCheckpoint = { _ in nil }
        var claude = VitruvianCodeCLIProvider.claude
        claude.connection = .claudeSDK
        let configuration = VitruvianCodeConfiguration(workingDirectory: work.path, activeProvider: claude)

        await session.openMCPStatus(configuration: configuration)
        XCTAssertEqual(session.mcpStatusPanel?.problem, .notConnected, "no live session yet")

        session.send("hello", configuration: configuration, agentPath: "/fake/claude")
        for _ in 0..<2000 where made.first?.statusCalls ?? 0 == 0 { await Task.yield() }
        XCTAssertGreaterThan(made.first?.statusCalls ?? 0, 0, "an open panel refreshes once the session is live")
        XCTAssertEqual(session.mcpStatusPanel?.servers.map(\.name), ["docs"])
        XCTAssertNil(session.mcpStatusPanel?.problem)

        made.first?.reported = [ClaudeMCPServerStatus(name: "docs", status: "failed", serverInfo: nil, error: "boom",
                                                      scope: nil, source: "project", tools: nil)]
        await session.refreshMCPStatus(configuration: configuration)
        XCTAssertEqual(session.mcpStatusPanel?.servers.first?.state, .failed)
        XCTAssertEqual(session.mcpStatusPanel?.servers.first?.configPath, work.appendingPathComponent(".mcp.json").path)

        made.first?.failure = ACPConnectionError.notStarted
        await session.refreshMCPStatus(configuration: configuration)
        guard case .failed? = session.mcpStatusPanel?.problem else { return XCTFail("a failed read is said") }
        session.stop()
        for connection in made { await connection.stop() }
    }
}

@MainActor
private final class MCPStatusTestHost: VitruvianCodeHost {
    var configuredBotDirectory = ""
    var startsBotAtLaunch = false
    var planMode = false
    var hiddenClaudeSessionIDs: [String] = []
    var chosenProviderID: UUID?
    var savedProviders: [VitruvianCodeCLIProvider] = []
    var promptHistory: [String] = []
    var worktreeMode = false
    var timelineOnLeft = false
    var strings = VitruvianCodeHostStrings()
    func turnNeedsApproval(_ notice: VitruvianCodeTurnNotice) {}
    func turnFinished(_ notice: VitruvianCodeTurnNotice, isChatVisible: Bool) {}
}

/// A live Claude connection that reports MCP status.
@MainActor
private final class MCPStatusConnection: PersistentAgentConnection, AgentMCPStatusReporting {
    let capabilities = AgentCapabilities()
    let events: AsyncStream<AgentEvent>
    private let continuation: AsyncStream<AgentEvent>.Continuation
    var statusCalls = 0
    var reported = [ClaudeMCPServerStatus(name: "docs", status: "connected", serverInfo: nil, error: nil,
                                          scope: "user", source: "user", tools: nil)]
    var failure: (any Error)?

    init() {
        (events, continuation) = AsyncStream.makeStream(of: AgentEvent.self)
    }

    func start(_ request: AgentSessionRequest) async throws -> String { "live-1" }
    func prompt(_ blocks: [PromptBlock]) async throws -> AgentStopReason {
        continuation.yield(.finished(status: "completed", response: "ok", error: nil, conversationID: "live-1"))
        return .endTurn
    }
    func cancel() async {}
    func answer(_ requestID: String, _ choice: AgentAnswer) async throws {}
    func setConfigOption(_ id: String, _ value: AgentConfigValue) async throws -> [AgentConfigOption] { [] }
    func syncPlanMode(_ planSwitch: Bool) async throws {}
    func stop() async { continuation.finish() }

    func mcpStatus() async throws -> [ClaudeMCPServerStatus] {
        statusCalls += 1
        if let failure { throw failure }
        return reported
    }
}
