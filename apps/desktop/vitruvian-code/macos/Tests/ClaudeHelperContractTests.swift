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

/// The helper's written contract (`macos/claude-helper/protocol/examples`) against the Swift side.
/// The helper's own tests hold the examples to the JSON Schema; these two checks hold the Swift
/// ACP client to the same files:
///
/// - every message the helper sends decodes into the Swift ACP types, and encoding it again gives
///   the example back, so nothing in it is left unread;
/// - every message the Swift side sends has the shape of its example: the same keys and kinds
///   of value, nested the same way.
@MainActor
final class ClaudeHelperContractTests: XCTestCase {
    private var root: URL!
    private var suites: [(UserDefaults, String)] = []

    override func setUpWithError() throws {
        let base = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
        root = base.appendingPathComponent("claude-contract-\(UUID().uuidString.prefix(8))", isDirectory: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("work"), withIntermediateDirectories: true)
    }

    override func tearDown() {
        for (defaults, name) in suites { defaults.removePersistentDomain(forName: name) }
        suites.removeAll()
        try? FileManager.default.removeItem(at: root)
    }

    // MARK: - Examples

    nonisolated private static func examplesDirectory() throws -> URL {
        try XCTUnwrap(
            ClaudeSDKTestSupport.appFile("macos/claude-helper/protocol/examples"),
            "macos/claude-helper/protocol/examples is missing"
        )
    }

    nonisolated private static func example(_ name: String) throws -> [String: ACPJSONValue] {
        let url = try examplesDirectory().appendingPathComponent("\(name).json")
        let data = try Data(contentsOf: url)
        return try XCTUnwrap(try JSONDecoder().decode(ACPJSONValue.self, from: data).objectValue, name)
    }

    nonisolated private static func exampleNames(prefix: String) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: examplesDirectory().path)
            .filter { $0.hasPrefix(prefix) && $0.hasSuffix(".json") }
            .map { String($0.dropLast(".json".count)) }
            .sorted()
    }

    /// Decodes `value` as `Type`, encodes it again and requires the very same JSON.
    private func assertRoundTrips<T: Codable>(
        _ type: T.Type,
        _ value: ACPJSONValue,
        _ name: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        do {
            let decoded = try value.decode(T.self)
            let again = try ACPJSONValue.fromEncodable(decoded)
            XCTAssertEqual(again, value, "\(name): the Swift \(T.self) does not keep everything the helper sends", file: file, line: line)
        } catch {
            XCTFail("\(name): does not decode into \(T.self): \(error)", file: file, line: line)
        }
    }

    // MARK: - Helper messages decode with nothing left over

    func testEveryHelperExampleDecodesIntoTheSwiftTypesWithNothingLeftOver() throws {
        let names = try Self.exampleNames(prefix: "helper-")
        XCTAssertGreaterThan(names.count, 20, "the examples folder is not empty")
        var covered: Set<String> = []
        for name in names {
            let message = try Self.example(name)
            switch name {
            case "helper-initialize-result", "helper-initialize-result-null-version":
                assertRoundTrips(ACPInitializeResult.self, try XCTUnwrap(message["result"]), name)
            case "helper-session-new-result", "helper-session-resume-result":
                assertRoundTrips(ACPSessionSetupResult.self, try XCTUnwrap(message["result"]), name)
            case "helper-session-prompt-result":
                assertRoundTrips(ACPPromptResult.self, try XCTUnwrap(message["result"]), name)
            case "helper-session-set-config-option-result":
                assertRoundTrips(ACPSetSessionConfigOptionResult.self, try XCTUnwrap(message["result"]), name)
            case "helper-session-set-mode-result", "helper-session-close-result", "helper-vitruvian-secrets-result":
                assertRoundTrips(ACPEmptyObject.self, try XCTUnwrap(message["result"]), name)
            case "helper-request-permission":
                assertRoundTrips(ACPRequestPermissionParams.self, try XCTUnwrap(message["params"]), name)
            case "helper-elicitation-create":
                assertRoundTrips(ACPElicitationCreateParams.self, try XCTUnwrap(message["params"]), name)
            case "helper-auth-required-error":
                assertRoundTrips(ACPRPCError.self, try XCTUnwrap(message["error"]), name)
            case "helper-vitruvian-fork-result":
                struct Forked: Codable { var sessionId: String }
                assertRoundTrips(Forked.self, try XCTUnwrap(message["result"]), name)
            case "helper-vitruvian-mcp-status-result":
                struct Status: Codable { var servers: [ClaudeMCPServerStatus] }
                assertRoundTrips(Status.self, try XCTUnwrap(message["result"]), name)
            case "helper-vitruvian-usage-limit", "helper-vitruvian-usage-limit-no-reset":
                let params = try XCTUnwrap(message["params"]?.objectValue)
                XCTAssertEqual(Set(params.keys), ["sessionId", "resetsAt", "message"], name)
                XCTAssertEqual(message["method"]?.stringValue, ClaudeSDKSupport.usageLimitMethod)
                let reset = ClaudeSDKSupport.usageLimitResetDate(from: message["params"])
                XCTAssertEqual(reset != nil, name == "helper-vitruvian-usage-limit", name)
            default:
                guard name.hasPrefix("helper-update-") else {
                    XCTFail("\(name) is an example this test does not know: add it, so it is held to the Swift types")
                    continue
                }
                assertRoundTrips(ACPSessionNotification.self, try XCTUnwrap(message["params"]), name)
                XCTAssertEqual(message["method"]?.stringValue, "session/update", name)
            }
            covered.insert(name)
        }
        XCTAssertEqual(covered, Set(names))
    }

    // MARK: - Swift messages have the examples' shape

    /// Kinds and nesting without the values: `{a:string,b:[number]}`.
    private func shape(_ value: ACPJSONValue) -> String {
        switch value {
        case .null: return "null"
        case .bool: return "bool"
        case .int, .double: return "number"
        case .string: return "string"
        case .array(let items): return "[" + items.map(shape).joined(separator: ",") + "]"
        case .object(let fields):
            return "{" + fields.keys.sorted().map { "\($0):\(shape(fields[$0] ?? .null))" }.joined(separator: ",") + "}"
        }
    }

    private func assertSameShape(
        _ actual: ACPJSONValue?,
        _ expected: ACPJSONValue?,
        _ what: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard let actual, let expected else {
            XCTFail("\(what): missing (\(String(describing: actual)) vs \(String(describing: expected)))", file: file, line: line)
            return
        }
        XCTAssertEqual(shape(actual), shape(expected), what, file: file, line: line)
    }

    private func without(_ key: String, in value: ACPJSONValue?) -> ACPJSONValue? {
        guard case .object(var fields)? = value else { return value }
        fields.removeValue(forKey: key)
        return .object(fields)
    }

    /// Plays the helper from its examples over in-memory pipes: it answers each request with the
    /// example's result, and walks a prompt through a permission request, a form and every
    /// `session/update` example before it ends the turn.
    private func playHelper(
        _ agent: ScriptedACPAgent,
        withoutConfigOptions: Bool = false
    ) -> Task<Void, Never> {
        Task { @MainActor in
            do {
                let results: [String: String] = [
                    "initialize": "helper-initialize-result",
                    ClaudeSDKSupport.secretsMethod: "helper-vitruvian-secrets-result",
                    "session/new": "helper-session-new-result",
                    "session/resume": "helper-session-resume-result",
                    "session/set_config_option": "helper-session-set-config-option-result",
                    "session/set_mode": "helper-session-set-mode-result",
                    "session/close": "helper-session-close-result",
                    ClaudeSDKSupport.forkMethod: "helper-vitruvian-fork-result",
                    ClaudeSDKSupport.mcpStatusMethod: "helper-vitruvian-mcp-status-result",
                ]
                let updates = try Self.exampleNames(prefix: "helper-update-")
                var seen = 0
                var promptCount = 0
                var pendingPrompt: ACPJSONValue?
                func reply(_ id: ACPJSONValue, to name: String) async throws {
                    var result = try XCTUnwrap(try Self.example(name)["result"])
                    if withoutConfigOptions, case .object(var fields) = result {
                        fields.removeValue(forKey: "configOptions")
                        result = .object(fields)
                    }
                    try await agent.sendToClient(.object(["jsonrpc": .string("2.0"), "id": id, "result": result]))
                }
                func finishPrompt(_ stopReason: String) async throws {
                    guard let id = pendingPrompt else { return }
                    pendingPrompt = nil
                    try await agent.sendToClient(.object([
                        "jsonrpc": .string("2.0"), "id": id,
                        "result": .object(["stopReason": .string(stopReason)]),
                    ]))
                }
                while !Task.isCancelled {
                    let all = await agent.allClientMessages()
                    while seen < all.count {
                        let message = all[seen].objectValue ?? [:]
                        seen += 1
                        if let method = message["method"]?.stringValue, let id = message["id"] {
                            if method == "session/prompt" {
                                promptCount += 1
                                pendingPrompt = id
                                if promptCount == 1 {
                                    var request = try Self.example("helper-request-permission")
                                    request["id"] = .string("perm-1")
                                    try await agent.sendToClient(.object(request))
                                }
                            } else if let name = results[method] {
                                try await reply(id, to: name)
                            }
                        } else if message["method"]?.stringValue == "session/cancel" {
                            try await finishPrompt("cancelled")
                        } else if let id = message["id"]?.stringValue {
                            if id == "perm-1" {
                                var request = try Self.example("helper-elicitation-create")
                                request["id"] = .string("elic-1")
                                try await agent.sendToClient(.object(request))
                            } else if id == "elic-1" {
                                for name in updates {
                                    try await agent.sendToClient(.object(try Self.example(name)))
                                }
                                try await finishPrompt("end_turn")
                            }
                        }
                    }
                    try await Task.sleep(nanoseconds: 5_000_000)
                }
            } catch {
                // The test ended and the pipes closed.
            }
        }
    }

    private func makeConnection(
        agent: ScriptedACPAgent,
        providerSecrets: [String: String] = [:],
        clientVersion: String? = nil
    ) -> ClaudeSDKConnection {
        var live = VitruvianCodeEngine.Environment.live(stateDirectoryOverride: root.path)
        live.home = root.path
        live.processEnvironment = ["PATH": "/usr/bin:/bin"]
        suites.append((live.defaults, VitruvianCodeSupport.preferencesSuiteName(
            bundleIdentifier: Bundle.main.bundleIdentifier ?? "com.vitruviansoftware.vitruvian-code",
            stateDirectory: root.path
        )))
        var provider = VitruvianCodeCLIProvider.claude
        provider.connection = .claudeSDK
        let store = AgentSecrets(environment: live)
        for (key, value) in providerSecrets {
            XCTAssertTrue(store.set(value, forKey: key, provider: provider.id))
        }
        let spec = AgentConnectionSpec(
            kind: .claudeSDK,
            provider: provider,
            configuration: VitruvianCodeConfiguration(approvalMode: .standard, activeProvider: provider),
            agentPath: "/opt/claude/bin/claude",
            workingDirectory: root.appendingPathComponent("work").path,
            environment: live.processEnvironment
        )
        return ClaudeSDKConnection(
            spec: spec,
            environment: live,
            bundledNode: {
                BundledNode(nodeURL: URL(fileURLWithPath: "/bundled/node"), helperURL: URL(fileURLWithPath: "/bundled/claude-helper.mjs"))
            },
            versionProbe: { "2.1.400 (Claude Code)" },
            clientVersion: clientVersion,
            processFactory: agent.makeProcessFactory()
        )
    }

    private func requests(_ messages: [ACPJSONValue], method: String) -> [[String: ACPJSONValue]] {
        messages.compactMap { $0.objectValue }.filter { $0["method"]?.stringValue == method }
    }

    /// Claude's MCP secrets go to the helper in `_vitruvian/secrets` alone: `session/new`
    /// carries the servers without them.
    func testClaudesMCPSecretsAreOnlyInTheSecretsMessage() async throws {
        let agent = ScriptedACPAgent()
        let peer = playHelper(agent)
        defer { peer.cancel() }
        let connection = makeConnection(agent: agent, providerSecrets: [:])
        let work = root.appendingPathComponent("work").path
        let docsSecret = "docs-\(UUID().uuidString)"
        let bearer = "Bearer tok-\(UUID().uuidString)"
        _ = try await connection.start(
            AgentSessionRequest(
                workingDirectory: work,
                mcpServers: [
                    .stdio(name: "local-docs", command: "/usr/local/bin/docs-mcp", arguments: ["--stdio"]),
                    .http(name: "remote-mcp", url: "https://mcp.example.com/v1"),
                ],
                mcpSecrets: [
                    "local-docs": .init(environment: ["DOCS_ACCESS_KEY": docsSecret]),
                    "remote-mcp": .init(headers: ["Authorization": bearer]),
                ]
            )
        )
        let sent = await agent.allClientMessages()
        let secrets = try XCTUnwrap(requests(sent, method: ClaudeSDKSupport.secretsMethod).first)
        let secretsText = ACPJSONValue.object(secrets).serializedJSONString()
        XCTAssertTrue(secretsText.contains(docsSecret) && secretsText.contains(bearer), "the helper gets them")
        let sessionNew = try XCTUnwrap(requests(sent, method: "session/new").first)
        XCTAssertEqual(sessionNew["params"]?.objectValue?["mcpServers"]?.arrayValue?.count, 2, "the servers are there")
        for message in sent where message.objectValue?["method"]?.stringValue != ClaudeSDKSupport.secretsMethod {
            let text = message.serializedJSONString()
            XCTAssertFalse(text.contains(docsSecret) || text.contains(bearer), text)
        }
        await connection.stop()
    }

    func testEveryMessageTheSwiftSideSendsHasTheShapeOfItsExample() async throws {
        let agent = ScriptedACPAgent()
        let peer = playHelper(agent)
        defer { peer.cancel() }
        let connection = makeConnection(
            agent: agent,
            providerSecrets: ["ANTHROPIC_API_KEY": "k1", "CUSTOM_GATEWAY_TOKEN": "k2"]
        )
        let recorder = ClaudeEventRecorder(connection.events)

        // session/new, with the example's two MCP servers and secrets.
        let work = root.appendingPathComponent("work").path
        let sessionID = try await connection.start(
            AgentSessionRequest(
                workingDirectory: work,
                mcpServers: [
                    .stdio(name: "local-docs", command: "/usr/local/bin/docs-mcp", arguments: ["--stdio"], environment: ["DOCS_ROOT": work]),
                    .http(name: "remote-mcp", url: "https://mcp.example.com/v1", headers: ["X-Workspace": "default"]),
                ],
                mcpSecrets: [
                    "local-docs": .init(environment: ["DOCS_ACCESS_KEY": "k3"]),
                    "remote-mcp": .init(headers: ["Authorization": "Bearer k4"]),
                ]
            )
        )

        // session/set_config_option
        _ = try await connection.setConfigOption("model", .string("claude-opus-4-1"))

        // session/prompt: text and an image, then the permission request and the form.
        let png = root.appendingPathComponent("shot.png")
        let exampleBlocks = try XCTUnwrap(
            try Self.example("client-session-prompt")["params"]?.objectValue?["prompt"]?.arrayValue
        )
        let pngBase64 = try XCTUnwrap(exampleBlocks.compactMap { $0.objectValue?["data"]?.stringValue }.first)
        try XCTUnwrap(Data(base64Encoded: pngBase64)).write(to: png)
        let prompt = Task { @MainActor in
            try await connection.prompt([.text("Review the screenshot and README changes."), .image(path: png.path)])
        }
        let approval = await recorder.wait("the example's permission request") { event in
            if case .approval = event { return true }
            return false
        }
        guard case .approval(let card)? = approval, let approvalID = card.requestID else {
            prompt.cancel()
            return XCTFail("no approval card")
        }
        try await connection.answer(approvalID, .option("allow_once"))
        let asked = await recorder.wait("the example's form") { event in
            if case .question = event { return true }
            return false
        }
        guard case .question(let form)? = asked else {
            prompt.cancel()
            return XCTFail("no form")
        }
        try await connection.answer(form.requestID, .form(["q_0": "PostgreSQL", "q_1": "TypeScript,Swift"]))
        let stop = try await withACPTestTimeout(seconds: 30, description: "the prompt") { try await prompt.value }
        XCTAssertEqual(stop, .endTurn)

        // The helper's updates reached the events the chat reads.
        XCTAssertTrue(recorder.events.contains { if case .planReplaced(let plan) = $0 { return plan.count == 3 } else { return false } })
        XCTAssertTrue(recorder.events.contains { if case .toolStep(let step) = $0 { return step.id == "toolu_01EditReadme" } else { return false } })
        XCTAssertTrue(recorder.events.contains { if case .slashCommands(let names) = $0 { return names == ["compact", "review"] } else { return false } })

        // _vitruvian/fork and _vitruvian/mcpStatus
        let forked = try await connection.fork()
        XCTAssertEqual(forked, "7c9e6679-7425-40de-944b-e07fc1f90ae7")
        let status = try await connection.mcpStatus()
        XCTAssertEqual(status.map(\.name), ["local-docs", "remote-mcp"])

        // session/cancel: a second prompt, stopped.
        let second = Task { @MainActor in try await connection.prompt([.text("again")]) }
        try await Task.sleep(nanoseconds: 200_000_000)
        await connection.cancel()
        let secondStop = try await withACPTestTimeout(seconds: 30, description: "the second prompt") { try await second.value }
        XCTAssertEqual(secondStop, .cancelled)

        // session/close
        await connection.stop()

        let sent = await agent.allClientMessages()

        // initialize
        let initialize = try XCTUnwrap(requests(sent, method: "initialize").first)
        assertSameShape(initialize["params"], try Self.example("client-initialize")["params"], "initialize params")
        XCTAssertEqual(initialize["params"]?.objectValue?["protocolVersion"]?.intValue, 1)

        // _vitruvian/secrets, sent before the session opens
        let secrets = try XCTUnwrap(requests(sent, method: ClaudeSDKSupport.secretsMethod).first)
        assertSameShape(secrets["params"], try Self.example("client-vitruvian-secrets")["params"], "secrets params")
        let methods = sent.compactMap { $0.objectValue?["method"]?.stringValue }
        XCTAssertLessThan(
            try XCTUnwrap(methods.firstIndex(of: ClaudeSDKSupport.secretsMethod)),
            try XCTUnwrap(methods.firstIndex(of: "session/new")),
            "the secrets go before the session opens"
        )
        XCTAssertGreaterThan(
            try XCTUnwrap(methods.firstIndex(of: ClaudeSDKSupport.secretsMethod)),
            try XCTUnwrap(methods.firstIndex(of: "initialize"))
        )

        // session/new: the example's shape, and the one thing it adds, the mode the chat opens in.
        let new = try XCTUnwrap(requests(sent, method: "session/new").first)
        assertSameShape(without("_meta", in: new["params"]), try Self.example("client-session-new")["params"], "session/new params")
        XCTAssertEqual(
            new["params"]?.objectValue?["_meta"]?.objectValue?["vitruvian"]?.objectValue?["modeId"]?.stringValue,
            "default"
        )

        // session/set_config_option, session/prompt, session/cancel, session/close, fork, mcpStatus
        assertSameShape(
            requests(sent, method: "session/set_config_option").first?["params"],
            try Self.example("client-session-set-config-option")["params"],
            "set_config_option params"
        )
        let promptParams = try XCTUnwrap(requests(sent, method: "session/prompt").first?["params"])
        XCTAssertEqual(promptParams.objectValue?["sessionId"]?.stringValue, sessionID)
        let sentBlocks = try XCTUnwrap(promptParams.objectValue?["prompt"]?.arrayValue)
        XCTAssertEqual(sentBlocks.count, 2)
        for block in sentBlocks {
            let type = try XCTUnwrap(block.objectValue?["type"]?.stringValue)
            let match = try XCTUnwrap(exampleBlocks.first { $0.objectValue?["type"]?.stringValue == type }, type)
            assertSameShape(block, match, "prompt block \(type)")
        }
        assertSameShape(
            requests(sent, method: "session/cancel").first?["params"],
            try Self.example("client-session-cancel")["params"],
            "session/cancel params"
        )
        assertSameShape(
            requests(sent, method: "session/close").first?["params"],
            try Self.example("client-session-close")["params"],
            "session/close params"
        )
        assertSameShape(
            requests(sent, method: ClaudeSDKSupport.forkMethod).first?["params"],
            try Self.example("client-vitruvian-fork")["params"],
            "fork params"
        )
        assertSameShape(
            requests(sent, method: ClaudeSDKSupport.mcpStatusMethod).first?["params"],
            try Self.example("client-vitruvian-mcp-status")["params"],
            "mcpStatus params"
        )

        // The answers to the helper's requests.
        let responses = sent.compactMap { $0.objectValue }.filter { $0["method"] == nil }
        let permission = try XCTUnwrap(responses.first { $0["id"]?.stringValue == "perm-1" })
        assertSameShape(permission["result"], try Self.example("client-request-permission-result")["result"], "permission result")
        let elicitation = try XCTUnwrap(responses.first { $0["id"]?.stringValue == "elic-1" })
        assertSameShape(elicitation["result"], try Self.example("client-elicitation-create-result")["result"], "elicitation result")
        XCTAssertEqual(
            elicitation["result"]?.objectValue?["content"]?.objectValue?["q_1"],
            .array([.string("TypeScript"), .string("Swift")])
        )
    }

    func testReopeningASessionSendsTheResumeExample() async throws {
        let agent = ScriptedACPAgent()
        let peer = playHelper(agent)
        defer { peer.cancel() }
        let connection = makeConnection(agent: agent)
        let sessionID = "550e8400-e29b-41d4-a716-446655440000"

        let reopened = try await connection.start(
            AgentSessionRequest(workingDirectory: root.appendingPathComponent("work").path, resumeSessionID: sessionID)
        )
        await connection.stop()

        XCTAssertEqual(reopened, sessionID)
        let sent = await agent.allClientMessages()
        let resume = try XCTUnwrap(requests(sent, method: "session/resume").first)
        assertSameShape(without("_meta", in: resume["params"]), try Self.example("client-session-resume")["params"], "session/resume params")
        XCTAssertEqual(resume["params"]?.objectValue?["sessionId"]?.stringValue, sessionID)
        XCTAssertTrue(requests(sent, method: "session/new").isEmpty)
        XCTAssertTrue(
            requests(sent, method: ClaudeSDKSupport.secretsMethod).isEmpty,
            "with no secrets the helper is sent none, which it does not need"
        )
    }

    func testAModeChangeOnAHelperWithoutConfigOptionsSendsTheSetModeExample() async throws {
        let agent = ScriptedACPAgent()
        let peer = playHelper(agent, withoutConfigOptions: true)
        defer { peer.cancel() }
        let connection = makeConnection(agent: agent)
        _ = try await connection.start(AgentSessionRequest(workingDirectory: root.appendingPathComponent("work").path))

        try await connection.syncPlanMode(true)
        await connection.stop()

        let sent = await agent.allClientMessages()
        let setMode = try XCTUnwrap(requests(sent, method: "session/set_mode").first)
        assertSameShape(setMode["params"], try Self.example("client-session-set-mode")["params"], "session/set_mode params")
        XCTAssertEqual(setMode["params"]?.objectValue?["modeId"]?.stringValue, "plan")
    }

    // MARK: - The client's own identity

    func testInitializeCarriesTheAppsRealNameAndVersion() async throws {
        let agent = ScriptedACPAgent()
        let peer = playHelper(agent)
        defer { peer.cancel() }
        let connection = makeConnection(agent: agent, clientVersion: "9.8.7")
        _ = try await connection.start(AgentSessionRequest(workingDirectory: root.appendingPathComponent("work").path))
        await connection.stop()

        let sent = await agent.allClientMessages()
        let info = try XCTUnwrap(requests(sent, method: "initialize").first?["params"]?.objectValue?["clientInfo"]?.objectValue)
        XCTAssertEqual(info["name"]?.stringValue, "vitruvian-code")
        XCTAssertEqual(info["title"]?.stringValue, "Vitruvian Code")
        XCTAssertEqual(info["version"]?.stringValue, "9.8.7")
    }

    func testWithNoVersionGivenTheBundlesIsUsed() {
        let info = ClaudeSDKSupport.clientInfo()
        XCTAssertEqual(info.name, "vitruvian-code")
        XCTAssertEqual(info.version, Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0")
        XCTAssertEqual(ClaudeSDKSupport.clientInfo(appVersion: "2.0.0").version, "2.0.0")
    }

    // MARK: - Elicitation modes the client did not offer

    /// The helper takes forms only, and says so at `initialize`; an agent that sends a URL-mode
    /// request anyway is refused with an error, not shown a page to open.
    func testAURLModeElicitationIsRefusedWhenTheClientOffersFormsOnly() async throws {
        let agent = ScriptedACPAgent()
        let peer = playHelper(agent)
        defer { peer.cancel() }
        let connection = makeConnection(agent: agent)
        let recorder = ClaudeEventRecorder(connection.events)
        let sessionID = try await connection.start(AgentSessionRequest(workingDirectory: root.appendingPathComponent("work").path))

        for (id, params) in [
            ("url-1", ["mode": "url", "url": "https://example.com/consent", "elicitationId": "e1"]),
            ("url-2", ["url": "https://example.com/consent", "elicitationId": "e2"]),
        ] {
            var body: [String: ACPJSONValue] = ["sessionId": .string(sessionID), "message": .string("Open this page")]
            for (key, value) in params { body[key] = .string(value) }
            try await agent.sendToClient(.object([
                "jsonrpc": .string("2.0"), "id": .string(id), "method": .string("elicitation/create"), "params": .object(body),
            ]))
            var reply: [String: ACPJSONValue]?
            for _ in 0..<200 where reply == nil {
                reply = await agent.allClientMessages().compactMap { $0.objectValue }.first { $0["id"]?.stringValue == id }
                if reply == nil { try await Task.sleep(nanoseconds: 10_000_000) }
            }
            let answer = try XCTUnwrap(reply, id)
            XCTAssertNotNil(answer["error"], "\(id) is answered with an error")
            XCTAssertNil(answer["result"], id)
        }
        XCTAssertFalse(
            recorder.events.contains { if case .question = $0 { return true } else { return false } },
            "no question card is shown for a URL the client never offered"
        )
        await connection.stop()
    }

    func testAgysPolicyKeepsItsBehaviour() {
        let agy = ACPClientPolicy.antigravity(version: "1.5.1")
        XCTAssertFalse(agy.elicitation, "agy gets no elicitation, so none of its requests reach the URL check")
        XCTAssertTrue(agy.elicitationURLMode, "and the flag's default is the one it always had")
        XCTAssertTrue(ACPClientPolicy(elicitation: true).elicitationURLMode)
        XCTAssertFalse(ACPClientPolicy.claudeSDK.elicitationURLMode)
    }
}
