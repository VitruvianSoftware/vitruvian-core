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

    private func XCTUnwrapAsync<T>(_ value: T?, file: StaticString = #filePath, line: UInt = #line) async throws -> T {
        try XCTUnwrap(value, file: file, line: line)
    }
}
