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

import Darwin
import Foundation
@testable import VitruvianCodeCore
import XCTest

/// Where the tests find the bundled Node and helper, and the fake `claude` they run it against.
///
/// - Under Bazel the rule hands over the two files (`CLAUDE_SDK_TEST_NODE`, `CLAUDE_SDK_TEST_HELPER`,
///   runfiles paths). Only tests read these; the app's own lookup (`BundledNode.locate`) is what
///   ships and is not changed.
/// - Under SwiftPM (the mirror) the packaged app the mirror test builds holds them
///   (`VITRUVIAN_CODE_PACKAGED_APP`).
/// - With neither, the live tests skip, saying why.
enum ClaudeSDKTestSupport {
    static func locateBundled() -> BundledNode? {
        let environment = ProcessInfo.processInfo.environment
        if let node = environment["CLAUDE_SDK_TEST_NODE"].flatMap(resolve),
           let helper = environment["CLAUDE_SDK_TEST_HELPER"].flatMap(resolve) {
            return BundledNode(nodeURL: node, helperURL: helper)
        }
        if let app = environment["VITRUVIAN_CODE_PACKAGED_APP"], !app.isEmpty,
           let bundle = Bundle(url: URL(fileURLWithPath: app)) {
            return BundledNode.locate(in: bundle)
        }
        return nil
    }

    /// An absolute path, or one relative to Bazel's runfiles.
    private static func resolve(_ path: String) -> URL? {
        if path.hasPrefix("/") {
            return FileManager.default.fileExists(atPath: path) ? URL(fileURLWithPath: path) : nil
        }
        let environment = ProcessInfo.processInfo.environment
        guard let runfiles = environment["TEST_SRCDIR"] else { return nil }
        let candidate = "\(runfiles)/\(path)"
        return FileManager.default.fileExists(atPath: candidate) ? URL(fileURLWithPath: candidate) : nil
    }

    /// `apps/desktop/vitruvian-code/<relative>`, under Bazel's runfiles or beside the sources.
    static func appFile(_ relative: String, filePath: String = #filePath) -> URL? {
        let environment = ProcessInfo.processInfo.environment
        var candidates: [String] = []
        if let runfiles = environment["TEST_SRCDIR"] {
            for workspace in [environment["TEST_WORKSPACE"], "_main"].compactMap({ $0 }) {
                candidates.append("\(runfiles)/\(workspace)/apps/desktop/vitruvian-code/\(relative)")
            }
        }
        // macos/Tests/<this file>: the app folder is two levels up. The mirror build lays its
        // copy out the same way (macos/ and testdata/ side by side).
        let testsDir = (filePath as NSString).deletingLastPathComponent
        let macosDir = (testsDir as NSString).deletingLastPathComponent
        let appDir = (macosDir as NSString).deletingLastPathComponent
        candidates.append("\(appDir)/\(relative)")
        return candidates.first { FileManager.default.fileExists(atPath: $0) }.map { URL(fileURLWithPath: $0) }
    }
}

/// A value shared with `@Sendable` closures (a process factory counting launches).
final class ClaudeLockedBox<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var raw: Value

    init(_ initial: Value) { raw = initial }

    var value: Value { lock.withLock { raw } }

    func update(_ change: (inout Value) -> Void) { lock.withLock { change(&raw) } }
}

/// Collects an `AgentConnection`'s events as they arrive and lets a test wait for one.
@MainActor
final class ClaudeEventRecorder {
    private(set) var events: [AgentEvent] = []
    /// True once the connection has ended its stream.
    private(set) var isFinished = false
    private var task: Task<Void, Never>?

    init(_ stream: AsyncStream<AgentEvent>) {
        task = Task { @MainActor [weak self] in
            for await event in stream {
                self?.events.append(event)
            }
            self?.isFinished = true
        }
    }

    deinit {
        task?.cancel()
    }

    /// The first event, from the start, that `predicate` accepts; fails the test when none
    /// arrives in time.
    @discardableResult
    func wait(
        _ description: String,
        timeout: TimeInterval = 30,
        file: StaticString = #filePath,
        line: UInt = #line,
        where predicate: (AgentEvent) -> Bool
    ) async -> AgentEvent? {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let hit = events.first(where: predicate) { return hit }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTFail("No event: \(description). Saw: \(events.map { String(describing: $0).prefix(120) })", file: file, line: line)
        return nil
    }

    /// Waits for the connection to end its stream; fails the test, rather than hanging it, when it does not.
    func finish(
        timeout: TimeInterval = 10,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !isFinished, Date() < deadline {
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertTrue(isFinished, "the connection's event stream did not end", file: file, line: line)
    }

    var text: String {
        events.compactMap { event -> String? in
            if case .text(let piece) = event { return piece }
            return nil
        }.joined()
    }
}

@MainActor
final class ClaudeSDKConnectionTests: XCTestCase {
    private var root: URL!
    private var work: URL!
    private var configDirectory: URL!
    private var environment: VitruvianCodeEngine.Environment!
    private var provider: VitruvianCodeCLIProvider!
    private var connections: [ClaudeSDKConnection] = []
    private var suiteDomains: [(UserDefaults, String)] = []

    override func setUpWithError() throws {
        // The temp folder's real path (`/private/var/...`, which Foundation's own
        // `resolvingSymlinksInPath` shortens back to `/var/...`): Claude names its project
        // folders after it.
        let made = FileManager.default.temporaryDirectory
            .appendingPathComponent("claude-sdk-\(UUID().uuidString.prefix(8))", isDirectory: true)
        try FileManager.default.createDirectory(at: made, withIntermediateDirectories: true)
        var resolved = [CChar](repeating: 0, count: Int(PATH_MAX))
        XCTAssertNotNil(realpath(made.path, &resolved))
        root = URL(fileURLWithPath: String(cString: resolved), isDirectory: true)
        work = root.appendingPathComponent("work", isDirectory: true)
        configDirectory = root.appendingPathComponent("claude-config", isDirectory: true)
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: configDirectory, withIntermediateDirectories: true)

        var live = VitruvianCodeEngine.Environment.live(stateDirectoryOverride: root.path)
        live.home = root.path
        live.processEnvironment = ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "HOME": root.path]
        environment = live
        let name = VitruvianCodeSupport.preferencesSuiteName(
            bundleIdentifier: Bundle.main.bundleIdentifier ?? "com.vitruviansoftware.vitruvian-code",
            stateDirectory: root.path
        )
        suiteDomains.append((live.defaults, name))

        var claude = VitruvianCodeCLIProvider.claude
        claude.connection = .claudeSDK
        claude.claudeConfigDirectory = configDirectory.path
        provider = claude
    }

    override func tearDown() async throws {
        for connection in connections {
            await connection.stop()
        }
        connections.removeAll()
        for (defaults, name) in suiteDomains {
            defaults.removePersistentDomain(forName: name)
        }
        suiteDomains.removeAll()
        if let root { try? FileManager.default.removeItem(at: root) }
    }

    // MARK: - Rig

    private func requireBundled() throws -> BundledNode {
        guard let bundled = ClaudeSDKTestSupport.locateBundled() else {
            throw XCTSkip("No bundled Node and Claude helper here: Bazel passes them (CLAUDE_SDK_TEST_NODE and CLAUDE_SDK_TEST_HELPER), and the mirror build packages them (VITRUVIAN_CODE_PACKAGED_APP).")
        }
        return bundled
    }

    private func fakeClaudeScript() throws -> URL {
        try XCTUnwrap(
            ClaudeSDKTestSupport.appFile("testdata/claude-sdk/fake-claude.mjs"),
            "testdata/claude-sdk/fake-claude.mjs is missing"
        )
    }

    private func script(_ name: String) throws -> URL {
        try XCTUnwrap(
            ClaudeSDKTestSupport.appFile("testdata/claude-sdk/\(name).json"),
            "testdata/claude-sdk/\(name).json is missing"
        )
    }

    private struct FakeClaude {
        let path: String
        let log: URL

        /// What the fake wrote about itself, one object per line.
        func entries() -> [[String: Any]] {
            guard let text = try? String(contentsOf: log, encoding: .utf8) else { return [] }
            return text.split(separator: "\n").compactMap { line in
                (try? JSONSerialization.jsonObject(with: Data(line.utf8))) as? [String: Any]
            }
        }

        func entries(kind: String) -> [[String: Any]] {
            entries().filter { $0["kind"] as? String == kind }
        }
    }

    /// Writes an executable `claude` that runs the fake on the bundled Node.
    private func makeFakeClaude(
        _ bundled: BundledNode,
        script scriptName: String? = "full-turn",
        version: String = "2.1.400",
        versionMode: String = "ok",
        recordEnvironment: [String] = [],
        ignoreTerm: Bool = false,
        name: String = "claude"
    ) throws -> FakeClaude {
        let bin = root.appendingPathComponent("bin-\(name)", isDirectory: true)
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        let wrapper = bin.appendingPathComponent("claude")
        let log = root.appendingPathComponent("\(name).log")
        var lines = ["#!/bin/sh"]
        if let scriptName {
            lines.append("export FAKE_CLAUDE_SCRIPT='\(try script(scriptName).path)'")
        }
        lines.append("export FAKE_CLAUDE_LOG='\(log.path)'")
        lines.append("export FAKE_CLAUDE_VERSION='\(version)'")
        lines.append("export FAKE_CLAUDE_VERSION_MODE='\(versionMode)'")
        lines.append("export FAKE_CLAUDE_RECORD_ENV='\(recordEnvironment.joined(separator: ","))'")
        if ignoreTerm { lines.append("export FAKE_CLAUDE_IGNORE_TERM=1") }
        lines.append("exec '\(bundled.nodeURL.path)' '\(try fakeClaudeScript().path)' \"$@\"")
        try (lines.joined(separator: "\n") + "\n").write(to: wrapper, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: wrapper.path)
        return FakeClaude(path: wrapper.path, log: log)
    }

    private func makeConnection(
        claude: String?,
        bundled: BundledNode?,
        approval: VitruvianCodeApprovalMode = .standard,
        plan: Bool = false,
        minimumClaudeVersion: String = ClaudeSDKSupport.minimumClaudeVersion,
        versionProbe: (@Sendable () async -> String?)? = nil,
        terminationGrace: TimeInterval = 1,
        processFactory: @escaping ACPConnection.ProcessFactory = ACPLaunchedProcess.live
    ) -> ClaudeSDKConnection {
        let spec = AgentConnectionSpec(
            kind: .claudeSDK,
            provider: provider,
            configuration: VitruvianCodeConfiguration(approvalMode: approval, activeProvider: provider),
            agentPath: claude,
            workingDirectory: work.path,
            turnModes: AgentTurnModes(plan: plan),
            environment: environment.processEnvironment
        )
        let connection = ClaudeSDKConnection(
            spec: spec,
            environment: environment,
            bundledNode: { bundled },
            versionProbe: versionProbe,
            minimumClaudeVersion: minimumClaudeVersion,
            terminationGrace: terminationGrace,
            processFactory: processFactory
        )
        connections.append(connection)
        return connection
    }

    private func request(resume: String? = nil) -> AgentSessionRequest {
        AgentSessionRequest(workingDirectory: work.path, resumeSessionID: resume)
    }

    /// A prompt's result, failing the test (instead of hanging it) when the turn never ends.
    private func finish(_ prompt: Task<AgentStopReason, Error>) async throws -> AgentStopReason {
        try await withACPTestTimeout(seconds: 30, description: "the turn to end") { try await prompt.value }
    }

    private func alive(_ pid: Int) -> Bool {
        kill(pid_t(pid), 0) == 0
    }

    // MARK: - A full turn

    func testAFullTurnRunsThroughTheRealHelper() async throws {
        let bundled = try requireBundled()
        let claude = try makeFakeClaude(bundled, recordEnvironment: ["CLAUDE_CONFIG_DIR"])
        let connection = makeConnection(claude: claude.path, bundled: bundled)
        let recorder = ClaudeEventRecorder(connection.events)

        let sessionID = try await connection.start(request())
        XCTAssertFalse(sessionID.isEmpty)
        let stop = try await connection.prompt([.text("hi")])

        XCTAssertEqual(stop, .endTurn)
        XCTAssertEqual(recorder.text, "Let me look at the folder.There are two entries.")
        await recorder.wait("the Bash tool step") { event in
            if case .toolStep(let step) = event { return step.id == "toolu_01Ls" }
            return false
        }
        await recorder.wait("the tool's result") { event in
            if case .toolStepResult(let id, let output, let isError) = event {
                return id == "toolu_01Ls" && output == "README.md\nSources" && !isError
            }
            return false
        }
        await recorder.wait("a finished turn") { event in
            if case .finished(let status, let response, _, let conversationID, _) = event {
                return status == "completed"
                    && response == "Let me look at the folder.There are two entries."
                    && conversationID == sessionID
            }
            return false
        }
        await recorder.wait("a context usage update") { event in
            if case .contextUsage(let usage) = event { return usage.contextWindow == 200_000 }
            return false
        }
        XCTAssertEqual(
            claude.entries(kind: "user_message").first?["content"] as? [[String: String]],
            [["type": "text", "text": "hi"]]
        )
    }

    func testTheHelperReportsTheMinimumClaudeTheAppChecksAgainst() async throws {
        let bundled = try requireBundled()
        let claude = try makeFakeClaude(bundled)
        let connection = makeConnection(claude: claude.path, bundled: bundled)
        _ = try await connection.start(request())

        let reported = connection.initializeResult?._meta?["vitruvian"]?.objectValue
        XCTAssertEqual(
            reported?["minClaudeVersionForMcpSecrets"]?.stringValue,
            ClaudeSDKSupport.minimumClaudeVersion,
            "the app's constant must be the helper's MCP_INITIALIZE_MIN_CLAUDE_VERSION"
        )
        XCTAssertEqual(reported?["claudeVersion"]?.stringValue, "2.1.400")
    }

    // MARK: - Approvals and questions

    private func approvalTurn(
        answer: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws -> (claude: FakeClaude, recorder: ClaudeEventRecorder, stop: AgentStopReason) {
        let bundled = try requireBundled()
        let claude = try makeFakeClaude(bundled, script: "approval")
        let connection = makeConnection(claude: claude.path, bundled: bundled, approval: .standard)
        let recorder = ClaudeEventRecorder(connection.events)
        _ = try await connection.start(request())

        let prompt = Task { @MainActor in try await connection.prompt([.text("clean up")]) }
        let asked = await recorder.wait("an approval request", file: file, line: line) { event in
            if case .approval = event { return true }
            return false
        }
        guard case .approval(let approval)? = asked else {
            prompt.cancel()
            throw XCTSkip("no approval arrived")
        }
        XCTAssertEqual(approval.toolName, "Run Bash: rm -rf build")
        XCTAssertEqual(approval.commandOrPath, "rm -rf build")
        XCTAssertEqual(approval.options.map(\.id), ["allow_once", "allow_always", "reject_once"])
        let requestID = try XCTUnwrap(approval.requestID)
        try await connection.answer(requestID, .option(answer))
        let stop = try await finish(prompt)
        return (claude, recorder, stop)
    }

    func testAnApprovalCardAnsweredAllowLetsClaudeRunTheTool() async throws {
        let (claude, recorder, stop) = try await approvalTurn(answer: "allow_once")
        XCTAssertEqual(stop, .endTurn)
        XCTAssertEqual(recorder.text, "Removed it.")
        let answer = try XCTUnwrap(claude.entries(kind: "can_use_tool_answer").first)
        let response = (answer["response"] as? [String: Any])?["response"] as? [String: Any]
        XCTAssertEqual(response?["behavior"] as? String, "allow")
    }

    func testAnApprovalCardAnsweredRejectStopsClaudeRunningTheTool() async throws {
        let (claude, recorder, stop) = try await approvalTurn(answer: "reject_once")
        XCTAssertEqual(stop, .endTurn)
        XCTAssertEqual(recorder.text, "Understood, leaving it.")
        let answer = try XCTUnwrap(claude.entries(kind: "can_use_tool_answer").first)
        let response = (answer["response"] as? [String: Any])?["response"] as? [String: Any]
        XCTAssertEqual(response?["behavior"] as? String, "deny")
    }

    func testAnAskUserQuestionFormRoundTrips() async throws {
        let bundled = try requireBundled()
        let claude = try makeFakeClaude(bundled, script: "question")
        let connection = makeConnection(claude: claude.path, bundled: bundled, approval: .standard)
        let recorder = ClaudeEventRecorder(connection.events)
        _ = try await connection.start(request())

        let prompt = Task { @MainActor in try await connection.prompt([.text("set up the database")]) }
        let asked = await recorder.wait("a question form") { event in
            if case .question = event { return true }
            return false
        }
        guard case .question(let question)? = asked else {
            prompt.cancel()
            return
        }
        let field = try XCTUnwrap(question.fields.first)
        XCTAssertEqual(field.label, "Database")
        XCTAssertEqual(field.options.map(\.value), ["PostgreSQL", "SQLite"])
        try await connection.answer(question.requestID, .form([field.id: "SQLite"]))
        let stop = try await finish(prompt)

        XCTAssertEqual(stop, .endTurn)
        XCTAssertEqual(recorder.text, "Going with that.")
        let answer = try XCTUnwrap(claude.entries(kind: "can_use_tool_answer").first)
        let response = (answer["response"] as? [String: Any])?["response"] as? [String: Any]
        XCTAssertEqual(response?["behavior"] as? String, "allow")
        let answers = (response?["updatedInput"] as? [String: Any])?["answers"] as? [String: String]
        XCTAssertEqual(answers, ["Which database should we use?": "SQLite"])
    }

    // MARK: - Cancel, resume, stop

    func testCancelEndsTheTurnAsCancelledAndInterruptsClaude() async throws {
        let bundled = try requireBundled()
        let claude = try makeFakeClaude(bundled, script: "cancel")
        let connection = makeConnection(claude: claude.path, bundled: bundled)
        let recorder = ClaudeEventRecorder(connection.events)
        _ = try await connection.start(request())

        let prompt = Task { @MainActor in try await connection.prompt([.text("take your time")]) }
        await recorder.wait("some text") { event in
            if case .text = event { return true }
            return false
        }
        await connection.cancel()
        let stop = try await finish(prompt)

        XCTAssertEqual(stop, .cancelled)
        await recorder.wait("a cancelled finish") { event in
            if case .finished(let status, _, _, _, _) = event { return status == "cancelled" }
            return false
        }
        XCTAssertFalse(claude.entries(kind: "control_request").filter { $0["subtype"] as? String == "interrupt" }.isEmpty)
    }

    func testAChatReopensItsSessionWithResume() async throws {
        let bundled = try requireBundled()
        let claude = try makeFakeClaude(bundled, name: "first")
        let first = makeConnection(claude: claude.path, bundled: bundled)
        let sessionID = try await first.start(request())
        _ = try await first.prompt([.text("hi")])
        await first.stop()

        let second = makeConnection(claude: claude.path, bundled: bundled)
        let recorder = ClaudeEventRecorder(second.events)
        let reopened = try await second.start(request(resume: sessionID))
        let stop = try await second.prompt([.text("hello again")])

        XCTAssertEqual(reopened, sessionID)
        XCTAssertEqual(stop, .endTurn)
        XCTAssertFalse(recorder.text.isEmpty)
        let starts = claude.entries(kind: "start")
        XCTAssertEqual(starts.count, 2)
        let secondArgs = starts.last?["args"] as? [String] ?? []
        XCTAssertTrue(secondArgs.contains("--resume=\(sessionID)"), "\(secondArgs)")
        let firstArgs = starts.first?["args"] as? [String] ?? []
        XCTAssertTrue(firstArgs.contains("--session-id=\(sessionID)"), "\(firstArgs)")
    }

    func testStopEndsTheHelperAndClaudeEvenWhenClaudeIgnoresTheFirstSignal() async throws {
        let bundled = try requireBundled()
        let claude = try makeFakeClaude(bundled, script: "hang", ignoreTerm: true)
        let connection = makeConnection(claude: claude.path, bundled: bundled, terminationGrace: 0.5)
        let recorder = ClaudeEventRecorder(connection.events)
        _ = try await connection.start(request())
        let prompt = Task { @MainActor in try? await connection.prompt([.text("never ends")]) }
        await recorder.wait("the turn to start") { event in
            if case .slashCommands = event { return true }
            return false
        }

        let start = try XCTUnwrap(claude.entries(kind: "start").first)
        let claudePID = try XCTUnwrap(start["pid"] as? Int)
        let helperPID = try XCTUnwrap(start["ppid"] as? Int)
        XCTAssertTrue(alive(claudePID) && alive(helperPID), "both run before the stop")

        await connection.stop()
        _ = try await withACPTestTimeout(seconds: 20, description: "the stopped prompt to return") { await prompt.value }

        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline, alive(claudePID) || alive(helperPID) {
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTAssertFalse(alive(helperPID), "the helper is gone")
        XCTAssertFalse(alive(claudePID), "claude is gone")
    }

    // MARK: - Secrets

    func testSecretsReachTheHelperAndAppearNowhereTheyShouldNot() async throws {
        let bundled = try requireBundled()
        let apiKey = "sk-test-\(UUID().uuidString)"
        let gatewayToken = "gw-\(UUID().uuidString)"
        let docsSecret = "docs-\(UUID().uuidString)"
        let bearer = "Bearer tok-\(UUID().uuidString)"
        let claude = try makeFakeClaude(bundled, recordEnvironment: ["ANTHROPIC_API_KEY", "CUSTOM_GATEWAY_TOKEN"])
        let secrets = AgentSecrets(environment: environment)
        XCTAssertTrue(secrets.set(apiKey, forKey: "ANTHROPIC_API_KEY", provider: provider.id))
        XCTAssertTrue(secrets.set(gatewayToken, forKey: "CUSTOM_GATEWAY_TOKEN", provider: provider.id))

        let captured = ClaudeLockedBox<[AgentProcessLaunchSpec]>([])
        let connection = makeConnection(
            claude: claude.path,
            bundled: bundled,
            processFactory: { spec in
                captured.update { $0.append(spec) }
                return try ACPLaunchedProcess.live(spec)
            }
        )
        let recorder = ClaudeEventRecorder(connection.events)
        _ = try await connection.start(
            AgentSessionRequest(
                workingDirectory: work.path,
                mcpServers: [
                    .stdio(name: "local-docs", command: "/usr/bin/true", arguments: ["--stdio"], environment: ["DOCS_ROOT": work.path]),
                    .http(name: "remote-mcp", url: "https://mcp.example.com/v1", headers: ["X-Workspace": "default"]),
                ],
                mcpSecrets: [
                    "local-docs": .init(environment: ["DOCS_ACCESS_KEY": docsSecret]),
                    "remote-mcp": .init(headers: ["Authorization": bearer]),
                ]
            )
        )
        _ = try await connection.prompt([.text("hi")])

        // They reached the helper: Claude's own process got the environment ones...
        let start = try XCTUnwrap(claude.entries(kind: "start").first)
        let claudeEnvironment = start["env"] as? [String: Any]
        XCTAssertEqual(claudeEnvironment?["ANTHROPIC_API_KEY"] as? String, apiKey)
        XCTAssertEqual(claudeEnvironment?["CUSTOM_GATEWAY_TOKEN"] as? String, gatewayToken)
        // ...and the MCP ones, in the `initialize` request, merged with the non-secret values.
        let initialize = try XCTUnwrap(claude.entries(kind: "initialize").first)
        let servers = try XCTUnwrap(initialize["mcpServers"] as? [String: [String: Any]])
        XCTAssertEqual((servers["local-docs"]?["env"] as? [String: String])?["DOCS_ACCESS_KEY"], docsSecret)
        XCTAssertEqual((servers["local-docs"]?["env"] as? [String: String])?["DOCS_ROOT"], work.path)
        XCTAssertEqual((servers["remote-mcp"]?["headers"] as? [String: String])?["Authorization"], bearer)

        // They are in no command line and no environment: not the helper's launch, not its
        // process as the system sees it, not Claude's command line.
        let all = [apiKey, gatewayToken, docsSecret, bearer]
        // The system's view of the helper (`ps`, read by the fake) shows it: if it did not, the
        // checks below would pass for nothing.
        XCTAssertTrue((start["parentCommand"] as? String ?? "").contains(bundled.helperURL.path), "ps shows the helper's command line")
        XCTAssertTrue((start["parentEnvironment"] as? String ?? "").contains("CLAUDE_CONFIG_DIR=\(configDirectory.path)"), "ps shows the helper's environment")
        let launched = try XCTUnwrap(captured.value.first)
        for secret in all {
            XCTAssertFalse(launched.arguments.joined(separator: " ").contains(secret), "launch arguments")
            XCTAssertFalse(launched.environment.values.contains { $0.contains(secret) }, "launch environment")
            XCTAssertFalse((start["args"] as? [String] ?? []).joined(separator: " ").contains(secret), "claude's arguments")
            XCTAssertFalse((start["parentCommand"] as? String ?? "").contains(secret), "the helper's command line")
            XCTAssertFalse((start["parentEnvironment"] as? String ?? "").contains(secret), "the helper's environment")
        }
        XCTAssertEqual(launched.arguments.first, bundled.helperURL.path)
        XCTAssertEqual(launched.executable, bundled.nodeURL.path)

        // And in no event and no log.
        let seen = recorder.events.map { String(describing: $0) }.joined(separator: "\n")
        let logs = (try? FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("logs").path)) ?? []
        let logText = logs.compactMap {
            try? String(contentsOfFile: root.appendingPathComponent("logs/\($0)").path, encoding: .utf8)
        }.joined(separator: "\n")
        for secret in all {
            XCTAssertFalse(seen.contains(secret), "events")
            XCTAssertFalse(logText.contains(secret), "the chat log")
        }

        // The file is the only place the environment ones sit, readable by the user alone.
        let attributes = try FileManager.default.attributesOfItem(atPath: secrets.path)
        XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
    }

    func testNothingToSendIsNoSecretsMessage() throws {
        let plan = ClaudeSDKSupport.secretsPlan(environment: [:], mcpSecrets: [:])
        XCTAssertNil(plan.params)
        XCTAssertEqual(plan.values, [])
    }

    // MARK: - The launch: config folder and modes

    func testTheConfigFolderAndTheBaseEnvironmentReachClaude() async throws {
        let bundled = try requireBundled()
        let claude = try makeFakeClaude(bundled, recordEnvironment: ["CLAUDE_CONFIG_DIR", "HOME", "NO_COLOR"])
        let connection = makeConnection(claude: claude.path, bundled: bundled)
        _ = try await connection.start(request())

        let start = try XCTUnwrap(claude.entries(kind: "start").first)
        let seen = start["env"] as? [String: Any]
        XCTAssertEqual(seen?["CLAUDE_CONFIG_DIR"] as? String, configDirectory.path)
        XCTAssertEqual(seen?["HOME"] as? String, root.path)
        XCTAssertEqual(seen?["NO_COLOR"] as? String, "1", "the command-line runner's base environment")
        let launch = connection.launchSpecUsed.environment
        XCTAssertEqual(launch["CLAUDE_CONFIG_DIR"], configDirectory.path)
        XCTAssertTrue((launch["PATH"] ?? "").hasPrefix(root.appendingPathComponent(".local/bin").path))
    }

    func testTheApprovalModeAndPlanSwitchDecideHowTheSessionOpens() async throws {
        let bundled = try requireBundled()
        let cases: [(VitruvianCodeApprovalMode, Bool, String)] = [
            (.yolo, false, "bypassPermissions"),
            (.acceptEdits, false, "acceptEdits"),
            (.standard, false, "default"),
            (.standard, true, "plan"),
        ]
        for (mode, plan, expected) in cases {
            let claude = try makeFakeClaude(bundled, name: "mode-\(expected)-\(plan)")
            let connection = makeConnection(claude: claude.path, bundled: bundled, approval: mode, plan: plan)
            _ = try await connection.start(request())
            let args = try XCTUnwrap(claude.entries(kind: "start").first?["args"] as? [String])
            XCTAssertTrue(args.contains("--permission-mode=\(expected)"), "\(mode) plan=\(plan): \(args)")
            XCTAssertEqual(
                args.contains("--allow-dangerously-skip-permissions"),
                expected == "bypassPermissions",
                "\(mode) plan=\(plan)"
            )
            await connection.stop()
        }
    }

    func testTurningThePlanSwitchOnMidChatChangesClaudesMode() async throws {
        let bundled = try requireBundled()
        let claude = try makeFakeClaude(bundled)
        let connection = makeConnection(claude: claude.path, bundled: bundled, approval: .standard)
        _ = try await connection.start(request())

        try await connection.syncPlanMode(true)

        let subtypes = claude.entries(kind: "control_request").compactMap { $0["subtype"] as? String }
        XCTAssertTrue(subtypes.contains("set_permission_mode"), "\(subtypes)")
    }

    // MARK: - The version check

    func testAClaudeOlderThanTheMinimumStillStartsAndWarns() async throws {
        let bundled = try requireBundled()
        let claude = try makeFakeClaude(bundled, version: "2.1.200")
        let connection = makeConnection(claude: claude.path, bundled: bundled)
        let recorder = ClaudeEventRecorder(connection.events)

        let sessionID = try await connection.start(request())
        XCTAssertFalse(sessionID.isEmpty, "an old claude must not block the chat")
        XCTAssertEqual(connection.installedClaudeVersion, "2.1.200")
        await recorder.wait("a warning naming the installed version and the minimum") { event in
            if case .notice(let severity, let title, _) = event {
                return severity == "warning" && title.contains("v2.1.200") && title.contains("v2.1.326")
            }
            return false
        }
        await connection.stop()
        await recorder.finish()
    }

    func testAVersionThatCannotBeReadDoesNotBlockAndIsLogged() async throws {
        let bundled = try requireBundled()
        for mode in ["garbage", "fail"] {
            let claude = try makeFakeClaude(bundled, versionMode: mode, name: "unreadable-\(mode)")
            let connection = makeConnection(claude: claude.path, bundled: bundled)
            let sessionID = try await connection.start(request())
            XCTAssertNil(connection.installedClaudeVersion, mode)
            let stop = try await connection.prompt([.text("hi")])
            XCTAssertEqual(stop, .endTurn, mode)
            await connection.stop()

            let logPath = environment.stateDirectoryOverride.map { _ in
                root.appendingPathComponent("logs/chat-\(sessionID).log").path
            } ?? ""
            let log = (try? String(contentsOfFile: logPath, encoding: .utf8)) ?? ""
            XCTAssertTrue(log.contains("Could not read the version of Claude Code"), "\(mode): \(log)")
        }
    }

    func testAModelTheInstalledClaudeCannotRunGetsOneNotice() async throws {
        let bundled = try requireBundled()
        let claude = try makeFakeClaude(bundled, version: "2.1.200")
        // The floor lowered, so a claude the models are held back on still starts.
        let connection = makeConnection(claude: claude.path, bundled: bundled, minimumClaudeVersion: "2.1.100")
        let recorder = ClaudeEventRecorder(connection.events)
        _ = try await connection.start(request())
        _ = try await connection.prompt([.text("hi")])

        let notices = recorder.events.compactMap { event -> String? in
            if case .notice(let severity, let title, _) = event, severity == "warning" { return title }
            return nil
        }
        XCTAssertEqual(
            notices,
            ["Claude Code v2.1.200 is too old for Claude Opus 5.5. Upgrade to v2.1.280 or newer to use it."]
        )
    }

    // MARK: - Helper messages

    func testASubagentStartsAndFinishesAsTheHelperMarksIt() async throws {
        let bundled = try requireBundled()
        let claude = try makeFakeClaude(bundled, script: "subagent")
        let connection = makeConnection(claude: claude.path, bundled: bundled)
        let recorder = ClaudeEventRecorder(connection.events)
        _ = try await connection.start(request())
        _ = try await connection.prompt([.text("explore")])

        let subagents = recorder.events.compactMap { event -> (VitruvianCodeActiveSubagent, Bool)? in
            if case .subagent(let subagent, let started) = event { return (subagent, started) }
            return nil
        }
        XCTAssertEqual(subagents.map(\.1), [true, false])
        XCTAssertEqual(subagents.first?.0.id, "toolu_01Sub")
        XCTAssertEqual(subagents.first?.0.role, "Explore repository")
        XCTAssertEqual(subagents.first?.0.prompt, "Find ACP transport definitions")
        XCTAssertEqual(subagents.last?.0.isRunning, false)
    }

    func testAUsageLimitNotificationBecomesAUsageLimitEvent() async throws {
        let bundled = try requireBundled()
        let claude = try makeFakeClaude(bundled, script: "usage-limit")
        let connection = makeConnection(claude: claude.path, bundled: bundled)
        let recorder = ClaudeEventRecorder(connection.events)
        _ = try await connection.start(request())
        _ = try await connection.prompt([.text("go on")])

        let limit = await recorder.wait("a usage limit") { event in
            if case .usageLimit = event { return true }
            return false
        }
        guard case .usageLimit(let resetsAt)? = limit else { return }
        XCTAssertEqual(resetsAt, Date(timeIntervalSince1970: 1_795_201_200))
    }

    func testForkAndMcpStatusSendTheHelpersMessages() async throws {
        let bundled = try requireBundled()
        let claude = try makeFakeClaude(bundled)
        let connection = makeConnection(claude: claude.path, bundled: bundled)
        let sessionID = try await connection.start(request())

        // The SDK's fork copies the session's transcript, which Claude writes under its config folder.
        let projects = configDirectory
            .appendingPathComponent("projects")
            .appendingPathComponent(work.path.replacingOccurrences(of: "[^a-zA-Z0-9]", with: "-", options: .regularExpression))
        try FileManager.default.createDirectory(at: projects, withIntermediateDirectories: true)
        let user = #"{"type":"user","uuid":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","parentUuid":null,"isSidechain":false,"sessionId":"\#(sessionID)","timestamp":"2026-11-20T10:00:00.000Z","cwd":"\#(work.path)","version":"2.1.400","message":{"role":"user","content":"hi"}}"#
        let assistant = #"{"type":"assistant","uuid":"bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb","parentUuid":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","isSidechain":false,"sessionId":"\#(sessionID)","timestamp":"2026-11-20T10:00:01.000Z","cwd":"\#(work.path)","version":"2.1.400","message":{"id":"msg_1","type":"message","role":"assistant","model":"claude-sonnet-5-5","content":[{"type":"text","text":"hello"}],"stop_reason":"end_turn","usage":{"input_tokens":1,"output_tokens":1}}}"#
        try (user + "\n" + assistant + "\n").write(
            to: projects.appendingPathComponent("\(sessionID).jsonl"),
            atomically: true,
            encoding: .utf8
        )

        let forked = try await connection.fork()
        XCTAssertFalse(forked.isEmpty)
        XCTAssertNotEqual(forked, sessionID)
        XCTAssertNotNil(UUID(uuidString: forked))

        let status = try await connection.mcpStatus()
        XCTAssertEqual(status.map(\.name), ["local-docs", "remote-mcp"])
        XCTAssertEqual(status.first?.status, "connected")
        XCTAssertEqual(status.first?.serverInfo, ClaudeMCPServerStatus.ServerInfo(name: "docs-mcp", version: "1.2.0"))
        XCTAssertEqual(status.first?.tools?.first?.name, "search_docs")
        XCTAssertEqual(status.last?.error, "Connection refused")
    }

    // MARK: - Failures before the helper starts

    func testWithNoBundledNodeTheConnectionFailsAtStartAndNeverFallsBack() async throws {
        let launched = ClaudeLockedBox(0)
        let connection = makeConnection(
            claude: "/usr/local/bin/claude",
            bundled: nil,
            processFactory: { _ in launched.update { $0 += 1 }; throw CocoaError(.featureUnsupported) }
        )
        let recorder = ClaudeEventRecorder(connection.events)

        do {
            _ = try await connection.start(request())
            XCTFail("with no bundled helper the connection must not start")
        } catch {
            XCTAssertEqual(
                (error as? LocalizedError)?.errorDescription,
                "This copy of Vitruvian Code doesn't include the Claude helper. Use the command line for this chat, or install a release build."
            )
        }
        await recorder.wait("a startup failure") { event in
            if case .connectionFailed(let failure) = event {
                return failure.kind == .startupFailed && failure.message == ClaudeSDKSupport.helperMissingMessage
            }
            return false
        }
        XCTAssertEqual(launched.value, 0, "nothing is started, and nothing falls back to the command line")
        await recorder.finish()
    }

    func testWithNoClaudeTheConnectionSaysSo() async throws {
        // Nothing on this machine counts as an executable, whatever is installed on it.
        environment.isExecutable = { _ in false }
        environment.fileExists = { _ in false }
        let bundled = BundledNode(nodeURL: URL(fileURLWithPath: "/usr/bin/true"), helperURL: URL(fileURLWithPath: "/usr/bin/true"))
        let connection = makeConnection(claude: nil, bundled: bundled)
        do {
            _ = try await connection.start(request())
            XCTFail("no claude, no start")
        } catch {
            XCTAssertEqual((error as? LocalizedError)?.errorDescription, ClaudeSDKSupport.claudeNotFoundMessage)
        }
    }

    // MARK: - Routing

    func testOnlyClaudeOnTheSDKGetsTheSDKConnection() {
        var live = VitruvianCodeEngine.Environment.live(stateDirectoryOverride: root.path)
        live.home = root.path
        let sdk = AgentConnectionSpec(provider: provider, workingDirectory: work.path)
        XCTAssertTrue(live.makeConnection(sdk) is ClaudeSDKConnection)

        var commandLine = provider!
        commandLine.connection = .commandLine
        XCTAssertTrue(live.makeConnection(AgentConnectionSpec(provider: commandLine, workingDirectory: work.path)) is CommandLineConnection)
        XCTAssertTrue(live.makeConnection(AgentConnectionSpec(provider: .claude, workingDirectory: work.path)) is CommandLineConnection,
                      "nothing changes for a chat that has not picked Claude SDK")

        var ollama = VitruvianCodeCLIProvider.ollama
        ollama.connection = .claudeSDK
        XCTAssertTrue(live.makeConnection(AgentConnectionSpec(provider: ollama, workingDirectory: work.path)) is CommandLineConnection,
                      "Ollama is a later step")
        var claudeACP = VitruvianCodeCLIProvider.claude
        claudeACP.connection = .claudeACP
        XCTAssertTrue(live.makeConnection(AgentConnectionSpec(provider: claudeACP, workingDirectory: work.path)) is CommandLineConnection,
                      "the ACP adapter is a later step")
    }
}
