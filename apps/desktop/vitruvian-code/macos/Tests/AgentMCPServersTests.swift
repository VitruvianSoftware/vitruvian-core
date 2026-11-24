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

/// The app's MCP server list (`AgentMCPServers`): the first-use import from `~/.claude.json`,
/// the project's `.mcp.json` merged in, what each agent gets, and where the secrets go.
@MainActor
final class AgentMCPServersTests: XCTestCase {
    private var root: URL!
    private var home: URL!
    private var work: URL!
    private var suites: [(UserDefaults, String)] = []

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("agent-mcp-\(UUID().uuidString.prefix(8))", isDirectory: true)
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

    /// The live environment, with its state folder and home inside this test's folder.
    private func environment() -> VitruvianCodeEngine.Environment {
        let state = root.appendingPathComponent("state").path
        var live = VitruvianCodeEngine.Environment.live(stateDirectoryOverride: state)
        suites.append((live.defaults, VitruvianCodeSupport.preferencesSuiteName(
            bundleIdentifier: Bundle.main.bundleIdentifier ?? "com.vitruviansoftware.vitruvian-code",
            stateDirectory: state
        )))
        live.home = home.path
        live.processEnvironment = ["PATH": "/usr/bin", "DOCS_HOME": "/srv/docs"]
        return live
    }

    // A `~/.claude.json` as Claude Code writes it: user-scope servers at the top, a project's
    // own under `projects` (not the user's list), one SSE server (deprecated, skipped) and one
    // with no command (broken, skipped).
    private static let claudeJSON = """
    {
      "numStartups": 12,
      "mcpServers": {
        "docs": { "type": "stdio", "command": "npx", "args": ["-y", "docs-mcp", "${DOCS_HOME}"],
                  "env": { "DOCS_TOKEN": "docs-secret-111" } },
        "remote": { "type": "http", "url": "https://mcp.example.com/v1",
                    "headers": { "Authorization": "Bearer remote-secret-222" } },
        "plain": { "command": "/usr/local/bin/plain-mcp" },
        "old-sse": { "type": "sse", "url": "https://sse.example.com" },
        "broken": { "type": "stdio" }
      },
      "projects": {
        "/somewhere": { "mcpServers": { "project-only": { "command": "nope" } } }
      }
    }
    """

    private func writeClaudeJSON(_ text: String = claudeJSON) throws {
        try text.write(to: home.appendingPathComponent(".claude.json"), atomically: true, encoding: .utf8)
    }

    // MARK: - Import

    func testFirstUseImportsTheUserServersFromClaudeJSONWithTheirSecretsInThePrivateFile() throws {
        try writeClaudeJSON()
        let env = environment()
        let host = MCPTestHost()
        let settings = try XCTUnwrap(AgentMCPServers.settings(host: host, environment: env))

        XCTAssertEqual(settings.servers.map(\.name), ["docs", "plain", "remote"], "user scope only; SSE and broken skipped")
        XCTAssertTrue(settings.servers.allSatisfy { $0.source == .claudeCode && $0.isEnabled })
        XCTAssertTrue(settings.importedClaudeCode)
        XCTAssertEqual(host.mcpSettings, settings, "kept through the host")
        let docs = try XCTUnwrap(settings.servers.first { $0.name == "docs" })
        XCTAssertEqual(docs.transport, .stdio)
        XCTAssertEqual(docs.command, "npx")
        XCTAssertEqual(docs.arguments, ["-y", "docs-mcp", "${DOCS_HOME}"])
        let remote = try XCTUnwrap(settings.servers.first { $0.name == "remote" })
        XCTAssertEqual(remote.transport, .http)
        XCTAssertEqual(remote.url, "https://mcp.example.com/v1")

        // The secrets are in the private file, and not in what the host saves.
        let secrets = AgentSecrets(environment: env)
        XCTAssertEqual(secrets.mcpSecrets(for: docs.id).environment, ["DOCS_TOKEN": "docs-secret-111"])
        XCTAssertEqual(secrets.mcpSecrets(for: remote.id).headers, ["Authorization": "Bearer remote-secret-222"])
        let saved = String(decoding: try JSONEncoder().encode(settings), as: UTF8.self)
        XCTAssertFalse(saved.contains("docs-secret-111") || saved.contains("remote-secret-222"), saved)
        let mode = try FileManager.default.attributesOfItem(atPath: secrets.path)[.posixPermissions] as? NSNumber
        XCTAssertEqual(mode?.intValue, 0o600)
    }

    func testTheImportRunsOnceSoARemovedServerStaysRemoved() throws {
        try writeClaudeJSON()
        let env = environment()
        let host = MCPTestHost()
        var settings = try XCTUnwrap(AgentMCPServers.settings(host: host, environment: env))
        let docs = try XCTUnwrap(settings.servers.first { $0.name == "docs" })
        AgentMCPServerDraft.remove(docs.id, from: &settings, secrets: AgentSecrets(environment: env))
        host.mcpSettings = settings

        let again = try XCTUnwrap(AgentMCPServers.settings(host: host, environment: env))
        XCTAssertEqual(again.servers.map(\.name), ["plain", "remote"])
        XCTAssertEqual(AgentSecrets(environment: env).mcpSecrets(for: docs.id), .init(), "its secrets went with it")
    }

    func testNoClaudeJSONYetImportsLater() throws {
        let env = environment()
        let host = MCPTestHost()
        XCTAssertEqual(AgentMCPServers.settings(host: host, environment: env)?.servers, [])
        XCTAssertEqual(host.mcpSettings?.importedClaudeCode, false, "nothing read, so a later first use still imports")
        try writeClaudeJSON()
        XCTAssertEqual(AgentMCPServers.settings(host: host, environment: env)?.servers.count, 3)
    }

    func testAHostThatKeepsNoListGetsNoServersAndNothingIsImported() throws {
        try writeClaudeJSON()
        let env = environment()
        let host = MCPTestHost(keepsList: false)
        XCTAssertNil(AgentMCPServers.settings(host: host, environment: env))
        let got = AgentMCPServers.sessionServers(host: host, environment: env, workingDirectory: work.path, target: .builtIn)
        XCTAssertEqual(got, .init())
        XCTAssertFalse(FileManager.default.fileExists(atPath: AgentSecrets(environment: env).path), "no secrets written")
    }

    // MARK: - Merge

    func testTheProjectsMCPJSONIsAddedAndWinsOnANameClash() throws {
        let app = AgentMCPServer(name: "docs", transport: .stdio, command: "app-docs")
        let other = AgentMCPServer(name: "other", transport: .http, url: "https://other.example.com")
        let project = """
        { "mcpServers": {
            "docs": { "command": "project-docs", "args": ["--ro"], "env": { "PROJECT_KEY": "p-333" } },
            "extra": { "type": "http", "url": "https://extra.example.com", "headers": { "X-Key": "x-444" } }
        } }
        """
        let got = AgentMCPServers.sessionServers(
            settings: AgentMCPSettings(servers: [app, other]),
            secrets: { $0 == app.id ? .init(environment: ["APP_KEY": "a-555"]) : .init() },
            projectConfig: project,
            target: .builtIn,
            processEnvironment: [:]
        )
        XCTAssertEqual(got.servers, [
            .stdio(name: "docs", command: "project-docs", arguments: ["--ro"]),
            .http(name: "other", url: "https://other.example.com"),
            .http(name: "extra", url: "https://extra.example.com"),
        ])
        XCTAssertEqual(got.secrets, [
            "docs": .init(environment: ["PROJECT_KEY": "p-333"]),
            "extra": .init(headers: ["X-Key": "x-444"]),
        ], "the project's docs replaced the app's, secrets and all")
    }

    func testDisabledServersAreNotPassed() {
        let on = AgentMCPServer(name: "on", transport: .stdio, command: "on-mcp")
        let off = AgentMCPServer(name: "off", transport: .stdio, command: "off-mcp", isEnabled: false)
        let got = AgentMCPServers.sessionServers(
            settings: AgentMCPSettings(servers: [on, off]),
            secrets: { $0 == off.id ? .init(environment: ["OFF_KEY": "off-666"]) : .init() },
            projectConfig: nil,
            target: .builtIn,
            processEnvironment: [:]
        )
        XCTAssertEqual(got.servers, [.stdio(name: "on", command: "on-mcp")])
        XCTAssertEqual(got.secrets, [:], "nor its secrets")
    }

    func testVariablesAreFilledInFromTheEnvironment() {
        let server = AgentMCPServer(name: "s", transport: .stdio, command: "${BIN:-/usr/bin}/s", arguments: ["${ROOT}", "${MISSING}"])
        let got = AgentMCPServers.sessionServers(
            settings: AgentMCPSettings(servers: [server]),
            secrets: { _ in .init(environment: ["TOKEN": "${TOKEN_SOURCE}"]) },
            projectConfig: nil,
            target: .builtIn,
            processEnvironment: ["ROOT": "/r", "TOKEN_SOURCE": "t-777"]
        )
        XCTAssertEqual(got.servers, [.stdio(name: "s", command: "/usr/bin/s", arguments: ["/r", "${MISSING}"])])
        XCTAssertEqual(got.secrets["s"], .init(environment: ["TOKEN": "t-777"]))
    }

    // MARK: - Who gets them

    func testARegistryAgentWithoutConsentGetsNoServers() {
        let server = AgentMCPServer(name: "docs", transport: .stdio, command: "docs-mcp")
        let project = #"{ "mcpServers": { "p": { "command": "p-mcp" } } }"#
        var settings = AgentMCPSettings(servers: [server])
        let ask = { (settings: AgentMCPSettings, target: AgentMCPTarget) in
            AgentMCPServers.sessionServers(settings: settings, secrets: { _ in .init(environment: ["K": "v-888"]) },
                                           projectConfig: project, target: target, processEnvironment: [:])
        }
        XCTAssertFalse(settings.allowsServers(forRegistryAgent: "opencode"), "off by default")
        XCTAssertEqual(ask(settings, .registry(agentID: "opencode")), .init(), "not even the project's")
        XCTAssertEqual(ask(settings, .none), .init(), "a command-line run reads its agent's own config")

        settings.registryAgentsAllowed["opencode"] = true
        XCTAssertEqual(ask(settings, .registry(agentID: "opencode")).servers.map(\.name), ["docs", "p"])
        XCTAssertEqual(ask(settings, .registry(agentID: "someone-else")), .init(), "consent is per agent")
    }

    func testTheTargetOfEachConnection() {
        var agy = VitruvianCodeCLIProvider.antigravity
        var claude = VitruvianCodeCLIProvider.claude
        XCTAssertEqual(AgentMCPTarget.of(agy, kind: .acp), .builtIn)
        XCTAssertEqual(AgentMCPTarget.of(claude, kind: .claudeSDK), .builtIn)
        XCTAssertEqual(AgentMCPTarget.of(claude, kind: .claudeACP), .registry(agentID: claude.id.uuidString),
                       "the Claude ACP adapter is a registry agent")
        XCTAssertEqual(AgentMCPTarget.of(agy, kind: .commandLine), AgentMCPTarget.none)
        XCTAssertEqual(AgentMCPTarget.of(claude, kind: nil), AgentMCPTarget.none)
        agy.connection = .acp
        claude.connection = .claudeSDK
        XCTAssertEqual(AgentMCPTarget.of(agy, kind: agy.connection), .builtIn)
    }

    // MARK: - Secrets in a session request

    func testASessionRequestCarriesNoSecretInItsServersOnlyInItsSecrets() throws {
        try writeClaudeJSON()
        let env = environment()
        let host = MCPTestHost()
        let got = AgentMCPServers.sessionServers(host: host, environment: env, workingDirectory: work.path, target: .builtIn)
        XCTAssertEqual(got.servers, [
            .stdio(name: "docs", command: "npx", arguments: ["-y", "docs-mcp", "/srv/docs"]),
            .stdio(name: "plain", command: "/usr/local/bin/plain-mcp"),
            .http(name: "remote", url: "https://mcp.example.com/v1"),
        ])
        let described = String(describing: got.servers)
        XCTAssertFalse(described.contains("docs-secret-111") || described.contains("remote-secret-222"))
        XCTAssertEqual(got.secrets, [
            "docs": .init(environment: ["DOCS_TOKEN": "docs-secret-111"]),
            "remote": .init(headers: ["Authorization": "Bearer remote-secret-222"]),
        ])
    }

    func testALiveAgyChatStartsWithTheMergedList() async throws {
        try writeClaudeJSON()
        try #"{ "mcpServers": { "docs": { "command": "project-docs" } } }"#
            .write(to: work.appendingPathComponent(".mcp.json"), atomically: true, encoding: .utf8)
        var env = environment()
        var made: [MCPRecordingConnection] = []
        env.makeConnection = { _ in
            let connection = MCPRecordingConnection()
            made.append(connection)
            return connection
        }
        let host = MCPTestHost()
        let session = VitruvianCodeQuickPromptSession(environment: env, host: host)
        session.takeCheckpoint = { _ in nil }
        var agy = VitruvianCodeCLIProvider.antigravity
        agy.connection = .acp
        let configuration = VitruvianCodeConfiguration(workingDirectory: work.path, activeProvider: agy)
        session.send("hello", configuration: configuration, agentPath: "/fake/agy")

        for _ in 0..<2000 where made.first?.starts.isEmpty ?? true { await Task.yield() }
        let request = try XCTUnwrap(made.first?.starts.first)
        XCTAssertEqual(request.mcpServers, [
            .stdio(name: "docs", command: "project-docs"),
            .stdio(name: "plain", command: "/usr/local/bin/plain-mcp"),
            .http(name: "remote", url: "https://mcp.example.com/v1"),
        ])
        XCTAssertEqual(request.mcpSecrets, ["remote": .init(headers: ["Authorization": "Bearer remote-secret-222"])])
        session.stop()
        for connection in made { await connection.stop() }
    }

    // MARK: - Editing

    func testADraftIsCheckedThenSavedWithItsSecretsInThePrivateFile() throws {
        let env = environment()
        let store = AgentSecrets(environment: env)
        var settings = AgentMCPSettings(servers: [AgentMCPServer(name: "taken", transport: .stdio, command: "x")])

        XCTAssertEqual(AgentMCPServerDraft(name: " ").problem(in: settings), .emptyName)
        XCTAssertEqual(AgentMCPServerDraft(name: "taken", command: "y").problem(in: settings), .duplicateName)
        XCTAssertEqual(AgentMCPServerDraft(name: "n").problem(in: settings), .missingCommand)
        XCTAssertEqual(AgentMCPServerDraft(name: "n", transport: .http, url: "ftp://x").problem(in: settings), .invalidURL)
        XCTAssertEqual(AgentMCPServerDraft(name: "n", command: "c", secrets: ["A=B": "v"]).problem(in: settings), .invalidSecretName)

        var draft = AgentMCPServerDraft(name: "fs", command: "npx", argumentsLine: #"-y "my server" ."#,
                                        secrets: ["FS_TOKEN": "fs-999"])
        let saved = try XCTUnwrap(draft.save(into: &settings, secrets: store))
        XCTAssertEqual(saved.arguments, ["-y", "my server", "."])
        XCTAssertEqual(saved.source, .user)
        XCTAssertEqual(store.mcpSecrets(for: saved.id).environment, ["FS_TOKEN": "fs-999"])
        XCTAssertEqual(AgentMCPServerDraft(saved).argumentsLine, #"-y "my server" ."#, "reads back as written")

        // Editing without touching the secrets keeps them; switching transport drops them.
        draft = AgentMCPServerDraft(saved)
        draft.isEnabled = false
        XCTAssertNotNil(draft.save(into: &settings, secrets: store))
        XCTAssertEqual(store.mcpSecrets(for: saved.id).environment, ["FS_TOKEN": "fs-999"])
        XCTAssertEqual(settings.servers.count, 2)
        draft.transport = .http
        draft.url = "https://fs.example.com"
        XCTAssertNotNil(draft.save(into: &settings, secrets: store))
        XCTAssertEqual(store.mcpSecrets(for: saved.id), .init())
    }

    func testASecretsFileFromBeforeMCPIsStillRead() throws {
        let env = environment()
        let store = AgentSecrets(environment: env)
        let provider = UUID()
        XCTAssertTrue(env.writePrivateFile(store.path, #"{"version":1,"providers":{"\#(provider.uuidString)":{"K":"v"}}}"#))
        XCTAssertNil(store.problem)
        XCTAssertEqual(store.values(for: provider), ["K": "v"])
        XCTAssertTrue(store.setMCPSecrets(.init(headers: ["H": "h"]), for: provider))
        XCTAssertEqual(store.values(for: provider), ["K": "v"], "the provider's values are kept")
    }
}

/// A host that keeps an MCP list in memory, or none.
@MainActor
private final class MCPTestHost: VitruvianCodeHost {
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
    var mcpSettings: AgentMCPSettings?

    init(keepsList: Bool = true) {
        mcpSettings = keepsList ? AgentMCPSettings() : nil
    }

    func turnNeedsApproval(_ notice: VitruvianCodeTurnNotice) {}
    func turnFinished(_ notice: VitruvianCodeTurnNotice, isChatVisible: Bool) {}
}

/// A live connection that keeps what each start was asked for.
@MainActor
private final class MCPRecordingConnection: PersistentAgentConnection {
    let capabilities = AgentCapabilities()
    let events: AsyncStream<AgentEvent>
    private let continuation: AsyncStream<AgentEvent>.Continuation
    var starts: [AgentSessionRequest] = []

    init() {
        (events, continuation) = AsyncStream.makeStream(of: AgentEvent.self)
    }

    func start(_ request: AgentSessionRequest) async throws -> String {
        starts.append(request)
        return "live-1"
    }

    func prompt(_ blocks: [PromptBlock]) async throws -> AgentStopReason { .endTurn }
    func cancel() async {}
    func answer(_ requestID: String, _ choice: AgentAnswer) async throws {}
    func setConfigOption(_ id: String, _ value: AgentConfigValue) async throws -> [AgentConfigOption] { [] }
    func syncPlanMode(_ planSwitch: Bool) async throws {}
    func stop() async { continuation.finish() }
}
