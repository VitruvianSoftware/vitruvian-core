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

/// Ollama (claude) on the Agent SDK connection (`OllamaClaude`): Claude Code through the bundled
/// helper, pointed at the Ollama server, with the chat's model.
@MainActor
final class OllamaClaudeTests: XCTestCase {
    // MARK: - The server's address, from OLLAMA_HOST as the `ollama` program reads it

    func testTheServerAddressIsReadFromOllamaHostAsOllamaReadsIt() {
        let cases: [(String?, String)] = [
            (nil, "http://127.0.0.1:11434"),
            ("", "http://127.0.0.1:11434"),
            ("  ", "http://127.0.0.1:11434"),
            ("0.0.0.0", "http://127.0.0.1:11434"),
            ("0.0.0.0:8080", "http://127.0.0.1:8080"),
            ("gpu.lan", "http://gpu.lan:11434"),
            ("gpu.lan:9999", "http://gpu.lan:9999"),
            ("\"gpu.lan:9999\"", "http://gpu.lan:9999"),
            ("'gpu.lan:9999'", "http://gpu.lan:9999"),
            ("http://gpu.lan", "http://gpu.lan:80"),
            ("https://gpu.lan", "https://gpu.lan:443"),
            ("https://gpu.lan:8443/ollama", "https://gpu.lan:8443/ollama"),
            ("gpu.lan/ollama", "http://gpu.lan:11434/ollama"),
            ("gpu.lan:99999", "http://gpu.lan:11434"),
            ("ollama.com", "https://ollama.com:443"),
            ("::1", "http://[::1]:11434"),
            ("[::1]:8080", "http://[::1]:8080"),
            ("http://[::]:11434", "http://[::1]:11434"),
            ("10.0.0.5", "http://10.0.0.5:11434"),
        ]
        for (host, expected) in cases {
            XCTAssertEqual(OllamaClaude.serverURL(ollamaHost: host), expected, "OLLAMA_HOST=\(host ?? "unset")")
        }
    }

    // MARK: - The model

    func testTheModelIsTheChosenOneOrElseTheOneOllamaListed() {
        XCTAssertEqual(OllamaClaude.model(configured: " qwen3-coder ", ollamaDefaultModel: "llama3.2"), "qwen3-coder")
        XCTAssertEqual(OllamaClaude.model(configured: "", ollamaDefaultModel: "llama3.2"), "llama3.2")
        XCTAssertEqual(OllamaClaude.model(configured: "  ", ollamaDefaultModel: "llama3.2"), "llama3.2")
    }

    // MARK: - The variables

    func testTheVariablesPointClaudeAtOllamaWithTheModelForEveryTier() {
        let base = ["PATH": "/usr/bin", "OLLAMA_HOST": "gpu.lan:9999", "ANTHROPIC_API_KEY": "sk-ant-users-own"]
        let env = OllamaClaude.helperEnvironment(base, model: "qwen3")
        XCTAssertEqual(env["ANTHROPIC_BASE_URL"], "http://gpu.lan:9999")
        XCTAssertEqual(env["ANTHROPIC_AUTH_TOKEN"], "ollama")
        XCTAssertEqual(env["ANTHROPIC_API_KEY"], "", "the user's own Anthropic key is not sent to the Ollama server")
        XCTAssertEqual(env["CLAUDE_CODE_PROVIDER_MANAGED_BY_HOST"], "1")
        for tier in ["ANTHROPIC_DEFAULT_OPUS_MODEL", "ANTHROPIC_DEFAULT_SONNET_MODEL",
                     "ANTHROPIC_DEFAULT_HAIKU_MODEL", "CLAUDE_CODE_SUBAGENT_MODEL"] {
            XCTAssertEqual(env[tier], "qwen3", tier)
        }
        XCTAssertEqual(env["PATH"], "/usr/bin", "the rest of the environment is kept")
    }

    // MARK: - Which providers get the connection

    func testOllamaOffersTheAgentSDKConnectionAndRunsOnItWhenChosen() {
        XCTAssertEqual(VitruvianCodeCLIProvider.ollama.availableConnections, [nil, .commandLine, .claudeSDK])
        var ollama = VitruvianCodeCLIProvider.ollama
        XCTAssertFalse(ollama.runsOnClaudeSDK)
        ollama.connection = .claudeSDK
        XCTAssertTrue(ollama.runsOnClaudeSDK)
        var claude = VitruvianCodeCLIProvider.claude
        claude.connection = .claudeSDK
        XCTAssertTrue(claude.runsOnClaudeSDK)
        var opencode = VitruvianCodeCLIProvider.opencode
        opencode.connection = .claudeSDK
        XCTAssertFalse(opencode.runsOnClaudeSDK, "only Claude Code runs on the helper")
    }

    func testOnlyAnOllamaChatOnTheSDKHasAModelThatDecidesItsConnection() {
        var ollama = VitruvianCodeCLIProvider.ollama
        ollama.connection = .claudeSDK
        var configuration = VitruvianCodeConfiguration(activeProvider: ollama)
        configuration.model = ""
        XCTAssertEqual(VitruvianCodeQuickPromptSession.ollamaSDKModel(
            provider: ollama, configuration: configuration, ollamaDefaultModel: "llama3.2"), "llama3.2")
        configuration.model = "qwen3"
        XCTAssertEqual(VitruvianCodeQuickPromptSession.ollamaSDKModel(
            provider: ollama, configuration: configuration, ollamaDefaultModel: "llama3.2"), "qwen3")
        XCTAssertNil(VitruvianCodeQuickPromptSession.ollamaSDKModel(
            provider: .ollama, configuration: configuration, ollamaDefaultModel: "llama3.2"), "not on the command line")
        var claude = VitruvianCodeCLIProvider.claude
        claude.connection = .claudeSDK
        XCTAssertNil(VitruvianCodeQuickPromptSession.ollamaSDKModel(
            provider: claude, configuration: configuration, ollamaDefaultModel: "llama3.2"), "not for Claude")
    }

    // MARK: - Through the real helper, with a fake `claude`

    private var root: URL!
    private var environment: VitruvianCodeEngine.Environment!
    private var connections: [ClaudeSDKConnection] = []
    private var suiteDomains: [(UserDefaults, String)] = []

    override func setUpWithError() throws {
        let made = FileManager.default.temporaryDirectory
            .appendingPathComponent("ollama-sdk-\(UUID().uuidString.prefix(8))", isDirectory: true)
        try FileManager.default.createDirectory(at: made, withIntermediateDirectories: true)
        var resolved = [CChar](repeating: 0, count: Int(PATH_MAX))
        XCTAssertNotNil(realpath(made.path, &resolved))
        root = URL(fileURLWithPath: String(cString: resolved), isDirectory: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("work"), withIntermediateDirectories: true)
        var live = VitruvianCodeEngine.Environment.live(stateDirectoryOverride: root.path)
        live.home = root.path
        live.processEnvironment = ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "HOME": root.path]
        environment = live
        let name = VitruvianCodeSupport.preferencesSuiteName(
            bundleIdentifier: Bundle.main.bundleIdentifier ?? "com.vitruviansoftware.vitruvian-code",
            stateDirectory: root.path
        )
        suiteDomains.append((live.defaults, name))
    }

    override func tearDown() async throws {
        for connection in connections { await connection.stop() }
        connections.removeAll()
        for (defaults, name) in suiteDomains { defaults.removePersistentDomain(forName: name) }
        suiteDomains.removeAll()
        if let root { try? FileManager.default.removeItem(at: root) }
    }

    private static let recorded = [
        "ANTHROPIC_BASE_URL", "ANTHROPIC_AUTH_TOKEN", "ANTHROPIC_API_KEY",
        "ANTHROPIC_DEFAULT_SONNET_MODEL", "CLAUDE_CODE_SUBAGENT_MODEL",
    ]

    /// A `claude` in `~/.local/bin`, the first place the app looks, that runs the fake on the
    /// bundled Node and logs its arguments and the variables above.
    private func makeFakeClaude(_ bundled: BundledNode) throws -> URL {
        let bin = root.appendingPathComponent(".local/bin", isDirectory: true)
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        let fake = try XCTUnwrap(ClaudeSDKTestSupport.appFile("testdata/claude-sdk/fake-claude.mjs"))
        let script = try XCTUnwrap(ClaudeSDKTestSupport.appFile("testdata/claude-sdk/full-turn.json"))
        let log = root.appendingPathComponent("claude.log")
        let lines = [
            "#!/bin/sh",
            "export FAKE_CLAUDE_SCRIPT='\(script.path)'",
            "export FAKE_CLAUDE_LOG='\(log.path)'",
            "export FAKE_CLAUDE_VERSION='2.1.400'",
            "export FAKE_CLAUDE_VERSION_MODE='ok'",
            "export FAKE_CLAUDE_RECORD_ENV='\(Self.recorded.joined(separator: ","))'",
            "exec '\(bundled.nodeURL.path)' '\(fake.path)' \"$@\"",
        ]
        let wrapper = bin.appendingPathComponent("claude")
        try (lines.joined(separator: "\n") + "\n").write(to: wrapper, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: wrapper.path)
        return log
    }

    private func claudeStart(_ log: URL) throws -> [String: Any] {
        let text = try String(contentsOf: log, encoding: .utf8)
        let entries = text.split(separator: "\n").compactMap {
            (try? JSONSerialization.jsonObject(with: Data($0.utf8))) as? [String: Any]
        }
        return try XCTUnwrap(entries.first { $0["kind"] as? String == "start" }, "claude never started")
    }

    private func flag(_ name: String, in args: [String]) -> String? {
        if let joined = args.first(where: { $0.hasPrefix("\(name)=") }) { return String(joined.dropFirst(name.count + 1)) }
        guard let index = args.firstIndex(of: name), index + 1 < args.count else { return nil }
        return args[index + 1]
    }

    private func startConnection(
        provider: VitruvianCodeCLIProvider,
        model: String,
        ollamaDefaultModel: String = VitruvianCodeSupport.ollamaFallbackModel,
        bundled: BundledNode
    ) async throws -> ClaudeSDKConnection {
        var configuration = VitruvianCodeConfiguration(approvalMode: .standard, activeProvider: provider)
        configuration.model = model
        let spec = AgentConnectionSpec(
            kind: .claudeSDK,
            provider: provider,
            configuration: configuration,
            // The chat's program for Ollama is `ollama`; the connection runs `claude` instead.
            agentPath: provider.route == .ollama ? "/nonexistent/ollama" : root.appendingPathComponent(".local/bin/claude").path,
            workingDirectory: root.appendingPathComponent("work").path,
            ollamaDefaultModel: ollamaDefaultModel,
            environment: environment.processEnvironment.merging([
                "OLLAMA_HOST": "gpu.lan:9999",
                "ANTHROPIC_API_KEY": "sk-ant-users-own",
            ]) { _, new in new }
        )
        let connection = ClaudeSDKConnection(spec: spec, environment: environment, bundledNode: { bundled }, terminationGrace: 1)
        connections.append(connection)
        _ = try await connection.start(AgentSessionRequest(workingDirectory: spec.workingDirectory))
        return connection
    }

    private func requireBundled() throws -> BundledNode {
        guard let bundled = ClaudeSDKTestSupport.locateBundled() else {
            throw XCTSkip("No bundled Node and Claude helper here (CLAUDE_SDK_TEST_NODE and CLAUDE_SDK_TEST_HELPER).")
        }
        return bundled
    }

    func testAnOllamaChatRunsClaudeAgainstTheOllamaServerWithTheChatsModel() async throws {
        let bundled = try requireBundled()
        let log = try makeFakeClaude(bundled)
        var ollama = VitruvianCodeCLIProvider.ollama
        ollama.connection = .claudeSDK
        let connection = try await startConnection(provider: ollama, model: "qwen3", bundled: bundled)

        let start = try claudeStart(log)
        let args = start["args"] as? [String] ?? []
        XCTAssertEqual(flag("--model", in: args), "qwen3", "the chat's model is the SDK's model: \(args)")
        let seen = start["env"] as? [String: Any]
        XCTAssertEqual(seen?["ANTHROPIC_BASE_URL"] as? String, "http://gpu.lan:9999", "from OLLAMA_HOST")
        XCTAssertEqual(seen?["ANTHROPIC_AUTH_TOKEN"] as? String, "ollama")
        XCTAssertEqual(seen?["ANTHROPIC_API_KEY"] as? String, "")
        XCTAssertEqual(seen?["ANTHROPIC_DEFAULT_SONNET_MODEL"] as? String, "qwen3")
        XCTAssertEqual(seen?["CLAUDE_CODE_SUBAGENT_MODEL"] as? String, "qwen3")
        XCTAssertEqual(connection.launchSpecUsed.arguments.last, root.appendingPathComponent(".local/bin/claude").path,
                       "the helper drives claude, not the chat's ollama")
    }

    func testAnOllamaChatWithNoModelChosenUsesTheOneOllamaListed() async throws {
        let bundled = try requireBundled()
        let log = try makeFakeClaude(bundled)
        var ollama = VitruvianCodeCLIProvider.ollama
        ollama.connection = .claudeSDK
        _ = try await startConnection(provider: ollama, model: "", ollamaDefaultModel: "llama3.2", bundled: bundled)

        let args = try claudeStart(log)["args"] as? [String] ?? []
        XCTAssertEqual(flag("--model", in: args), "llama3.2", "\(args)")
    }

    func testAPlainClaudeChatGetsNoneOfIt() async throws {
        let bundled = try requireBundled()
        let log = try makeFakeClaude(bundled)
        var claude = VitruvianCodeCLIProvider.claude
        claude.connection = .claudeSDK
        let connection = try await startConnection(provider: claude, model: "qwen3", bundled: bundled)

        let start = try claudeStart(log)
        let args = start["args"] as? [String] ?? []
        XCTAssertNil(flag("--model", in: args), "Claude opens on its own default: \(args)")
        let seen = start["env"] as? [String: Any]
        XCTAssertTrue(seen?["ANTHROPIC_BASE_URL"] is NSNull)
        XCTAssertTrue(seen?["ANTHROPIC_AUTH_TOKEN"] is NSNull)
        XCTAssertEqual(seen?["ANTHROPIC_API_KEY"] as? String, "sk-ant-users-own", "the user's own key is left alone")
        XCTAssertTrue(seen?["CLAUDE_CODE_SUBAGENT_MODEL"] is NSNull)
        XCTAssertNil(connection.launchSpecUsed.environment["ANTHROPIC_BASE_URL"])
    }

    /// The placeholder is not a secret (Ollama's docs: "required but ignored"), so it sits in
    /// the helper's environment. A real token the user stores for the provider is one: it goes
    /// in `_vitruvian/secrets`, never argv or the helper's environment, and replaces the
    /// placeholder.
    func testAStoredTokenTravelsAsASecretAndReplacesThePlaceholder() async throws {
        let bundled = try requireBundled()
        let log = try makeFakeClaude(bundled)
        var ollama = VitruvianCodeCLIProvider.ollama
        ollama.connection = .claudeSDK
        let token = "ollama-cloud-\(UUID().uuidString)"
        XCTAssertTrue(AgentSecrets(environment: environment).set(token, forKey: "ANTHROPIC_AUTH_TOKEN", provider: ollama.id))
        let connection = try await startConnection(provider: ollama, model: "qwen3", bundled: bundled)

        let start = try claudeStart(log)
        XCTAssertEqual((start["env"] as? [String: Any])?["ANTHROPIC_AUTH_TOKEN"] as? String, token)
        let launch = connection.launchSpecUsed
        XCTAssertEqual(launch.environment["ANTHROPIC_AUTH_TOKEN"], "ollama", "only the placeholder is in the helper's environment")
        XCTAssertFalse(launch.environment.values.contains { $0.contains(token) })
        XCTAssertFalse(launch.arguments.contains { $0.contains(token) })
        let parent = (start["parentCommand"] as? String ?? "") + (start["parentEnvironment"] as? String ?? "")
        XCTAssertFalse(parent.contains(token), "ps shows no token for the running helper")
    }
}
