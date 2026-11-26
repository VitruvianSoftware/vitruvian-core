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

/// The Claude ACP adapter (design step 5f), following T3 Code's `claudeAcp.ts`. The subagent
/// updates replayed here were recorded from claude-acp 0.112.0 on 2026-11-26.
@MainActor
final class ClaudeACPAdapterTests: XCTestCase {
    private var scratch: String!
    private var state: String { (scratch as NSString).appendingPathComponent("state") }

    override func setUpWithError() throws {
        scratch = (NSTemporaryDirectory() as NSString).appendingPathComponent("claude-acp-\(UUID().uuidString)")
        try FileManager.default.createDirectory(atPath: scratch, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(atPath: scratch)
    }

    private func notifications(_ file: String) throws -> [ACPSessionNotification] {
        let relative = "apps/desktop/vitruvian-code/testdata/acp/\(file)"
        var candidates: [String] = []
        let environment = ProcessInfo.processInfo.environment
        if let runfiles = environment["TEST_SRCDIR"] {
            for workspace in [environment["TEST_WORKSPACE"], "_main"].compactMap({ $0 }) {
                candidates.append("\(runfiles)/\(workspace)/\(relative)")
            }
        }
        let here = (#filePath as NSString).deletingLastPathComponent
        candidates.append(((here as NSString).deletingLastPathComponent as NSString).deletingLastPathComponent + "/testdata/acp/\(file)")
        let path = try XCTUnwrap(candidates.first { FileManager.default.fileExists(atPath: $0) }, "missing \(file)")
        let text = try String(contentsOfFile: path, encoding: .utf8)
        return try text.split(separator: "\n").map { line in
            let object = try JSONDecoder().decode([String: ACPJSONValue].self, from: Data(line.utf8))
            let params = try XCTUnwrap(object["params"])
            return try JSONDecoder().decode(ACPSessionNotification.self, from: JSONEncoder().encode(params))
        }
    }

    private func subagents(_ events: [AgentEvent]) -> [(VitruvianCodeActiveSubagent, Bool)] {
        events.compactMap { if case .subagent(let s, let started) = $0 { return (s, started) } else { return nil } }
    }

    private func update(_ json: String, session: String = "sess-parent") throws -> ACPSessionNotification {
        try JSONDecoder().decode(ACPSessionNotification.self,
                                 from: Data(#"{"sessionId":"\#(session)","update":\#(json)}"#.utf8))
    }

    // MARK: Subagents

    /// The recorded Agent call: nothing while its input has no prompt (T3 Code's provisional
    /// tool), then one running subagent named by its description, then the same one finished.
    func testTheRecordedAgentCallBecomesOneSubagentThatFinishes() throws {
        let tracker = ClaudeSubagentTracker()
        let events = try notifications("claude-acp-subagent.ndjson").compactMap(tracker.event(for:))
        let shown = subagents(events)
        XCTAssertEqual(shown.count, 2, "\(shown)")
        XCTAssertEqual(shown.first?.0.role, "say ok")
        XCTAssertEqual(shown.first?.0.prompt, "Reply with exactly: sub ok")
        XCTAssertEqual(shown.first?.0.isRunning, true)
        XCTAssertEqual(shown.first?.1, true)
        XCTAssertEqual(shown.last?.0.id, shown.first?.0.id)
        XCTAssertEqual(shown.last?.0.isRunning, false, "a foreground subagent ends with its call")
    }

    func testABackgroundSubagentStaysRunningWhenItsCallCompletes() throws {
        let tracker = ClaudeSubagentTracker()
        _ = tracker.event(for: try update(#"{"sessionUpdate":"tool_call","toolCallId":"t1","title":"Task","status":"pending","rawInput":{},"_meta":{"claudeCode":{"toolName":"Agent"}}}"#))
        let started = tracker.event(for: try update(#"{"sessionUpdate":"tool_call_update","toolCallId":"t1","rawInput":{"description":"watch","prompt":"Watch the logs","run_in_background":true}}"#))
        let completed = tracker.event(for: try update(#"{"sessionUpdate":"tool_call_update","toolCallId":"t1","status":"completed"}"#))
        XCTAssertEqual(subagents([started].compactMap { $0 }).first?.0.isRunning, true)
        XCTAssertNil(completed, "still running, so nothing new to show")

        // Claude reports it async too, without the flag.
        let async = ClaudeSubagentTracker()
        _ = async.event(for: try update(#"{"sessionUpdate":"tool_call","toolCallId":"t2","title":"Task","status":"pending","rawInput":{"prompt":"p"},"_meta":{"claudeCode":{"toolName":"Agent"}}}"#))
        let done = async.event(for: try update(#"{"sessionUpdate":"tool_call_update","toolCallId":"t2","status":"completed","_meta":{"claudeCode":{"toolResponse":{"isAsync":true}}}}"#))
        XCTAssertNil(done)
    }

    func testOtherToolsAreNotSubagents() throws {
        let tracker = ClaudeSubagentTracker()
        XCTAssertNil(tracker.event(for: try update(#"{"sessionUpdate":"tool_call","toolCallId":"b1","title":"Bash","status":"pending","rawInput":{"command":"ls","prompt":"x"},"_meta":{"claudeCode":{"toolName":"Bash"}}}"#)))
    }

    /// A child session's state (`subagent_update`) finishes the subagent its delegation
    /// (`session_message`, whose id is the Agent call's tool-use id) belongs to.
    func testAChildSessionsStateFinishesItsSubagent() throws {
        let tracker = ClaudeSubagentTracker()
        _ = tracker.event(for: try update(#"{"sessionUpdate":"tool_call","toolCallId":"t3","title":"Task","status":"in_progress","rawInput":{"description":"bg","prompt":"Do it","run_in_background":true},"_meta":{"claudeCode":{"toolName":"Agent"}}}"#))
        XCTAssertNil(tracker.event(for: try update(#"{"sessionUpdate":"session_message","messageId":"t3","senderSessionId":"sess-parent","content":[{"type":"text","text":"Do it"}]}"#, session: "child-1")))
        let running = tracker.event(for: try update(#"{"sessionUpdate":"subagent_update","sessionId":"child-1","state":{"state":"running"}}"#))
        XCTAssertNil(running, "no change")
        let done = tracker.event(for: try update(#"{"sessionUpdate":"subagent_update","sessionId":"child-1","state":{"state":"idle","stopReason":"end_turn"}}"#))
        let shown = subagents([done].compactMap { $0 })
        XCTAssertEqual(shown.first?.0.id, "t3")
        XCTAssertEqual(shown.first?.0.isRunning, false)
    }

    // MARK: Launch

    func testTheAdapterStartsWithT3CodesSwitchAndTheClaudeConfigFolder() {
        let environment = ClaudeACPAdapter.environment(base: ["PATH": "/usr/bin"], configDirectory: "/Users/x/.claude-work")
        XCTAssertEqual(environment["CLAUDE_AGENT_ACP_EXPERIMENTAL_V2"], "1")
        XCTAssertEqual(environment["CLAUDE_CONFIG_DIR"], "/Users/x/.claude-work")
        let kept = ClaudeACPAdapter.environment(base: ["CLAUDE_AGENT_ACP_EXPERIMENTAL_V2": "0"], configDirectory: nil)
        XCTAssertEqual(kept["CLAUDE_AGENT_ACP_EXPERIMENTAL_V2"], "0", "the user's own setting wins, as in T3 Code")
        XCTAssertNil(kept["CLAUDE_CONFIG_DIR"])
    }

    private func installAdapter(version: String) async throws {
        let host = ACPRegistryHost(
            fetch: { _, _, _ in throw URLError(.notConnectedToInternet) },
            download: { _, destination, _, _ in
                try "#!/bin/sh\n".write(toFile: destination, atomically: true, encoding: .utf8)
                chmod(destination, 0o755)
                return "unchecked"
            },
            run: { _, _, _, _, _ in .init(status: 127, stdout: "") },
            findProgram: { _, _ in nil })
        let installer = ACPRegistryInstaller(stateDirectory: state, host: host, environment: [:], platformTarget: "darwin-aarch64")
        let agent = ACPRegistry.Agent(
            id: "claude-acp", name: "Claude Agent", version: version, description: "", authors: [], license: nil,
            website: nil, repository: nil, icon: nil,
            distribution: .init(binary: ["darwin-aarch64": .init(archive: "https://example.test/claude-agent-acp",
                                                                 cmd: "./claude-agent-acp", sha256: nil, args: [], env: [:])],
                                npx: nil, uvx: nil))
        _ = try await installer.install(agent)
    }

    private func claudeProvider(recorded: String? = nil) -> VitruvianCodeCLIProvider {
        var provider = VitruvianCodeCLIProvider.claude
        provider.connection = .claudeACP
        provider.registryAgent = recorded.map { .init(agentID: "claude-acp", version: $0) }
        return provider
    }

    /// The chat uses the version recorded on the Claude provider, else the newest installed,
    /// compared as numbers (0.112.0 is newer than 0.99.0). Nothing installed: nothing to run.
    func testTheChatRunsTheRecordedOrNewestInstalledAdapter() async throws {
        XCTAssertNil(ACPRegistryConnection.claudeAdapterInstall(stateDirectory: state, recorded: nil))
        try await installAdapter(version: "0.99.0")
        try await installAdapter(version: "0.112.0")
        XCTAssertEqual(ACPRegistryConnection.claudeAdapterInstall(stateDirectory: state, recorded: nil)?.version, "0.112.0")
        XCTAssertEqual(ACPRegistryConnection.claudeAdapterInstall(stateDirectory: state,
                                                                  recorded: .init(agentID: "claude-acp", version: "0.99.0"))?.version, "0.99.0")
        XCTAssertEqual(ACPRegistryConnection.claudeAdapterInstall(stateDirectory: state,
                                                                  recorded: .init(agentID: "claude-acp", version: "9.9.9"))?.version, "0.112.0",
                       "a recorded version that is gone falls back to the newest")

        let provider = claudeProvider()
        let spec = AgentConnectionSpec(
            provider: provider,
            configuration: VitruvianCodeConfiguration(approvalMode: .yolo, model: "", effort: .high, activeProvider: provider),
            agentPath: nil, workingDirectory: "/w", ollamaDefaultModel: "",
            turnModes: AgentTurnModes(plan: false, worktree: false, attachments: [], fork: false),
            environment: ["PATH": "/usr/bin"])
        let launch = try XCTUnwrap(ACPRegistryConnection.claudeLaunchSpec(spec: spec, stateDirectory: state, home: scratch))
        XCTAssertTrue(launch.executable.hasSuffix("/agents/claude-acp/0.112.0/darwin-aarch64/claude-agent-acp"), launch.executable)
        XCTAssertEqual(launch.environment["CLAUDE_AGENT_ACP_EXPERIMENTAL_V2"], "1")
    }

    /// "Claude ACP" was offered in Settings but ran the command line: the engine had no
    /// connection for it.
    func testClaudeACPGetsItsOwnConnectionAndSaysWhenTheAdapterIsMissing() {
        let environment = VitruvianCodeEngine.Environment.live(stateDirectoryOverride: state)
        let provider = claudeProvider()
        let spec = AgentConnectionSpec(
            provider: provider,
            configuration: VitruvianCodeConfiguration(approvalMode: .yolo, model: "", effort: .high, activeProvider: provider),
            agentPath: nil, workingDirectory: scratch, ollamaDefaultModel: "",
            turnModes: AgentTurnModes(plan: false, worktree: false, attachments: [], fork: false),
            environment: [:])
        XCTAssertTrue(environment.makeConnection(spec) is ACPConnection)
        XCTAssertFalse(environment.makeConnection(spec) is CommandLineConnection)
        XCTAssertEqual(VitruvianCodeHostStrings().missingProgram(of: provider),
                       VitruvianCodeHostStrings().claudeAdapterNotInstalled)
        var commandLine = provider
        commandLine.connection = .commandLine
        XCTAssertEqual(VitruvianCodeHostStrings().missingProgram(of: commandLine),
                       VitruvianCodeHostStrings().commandNotFound("claude"))
    }

    /// One real turn on the real adapter through the app's own connection: Claude starts a
    /// subagent and the chat sees it start and finish. Skipped unless asked for, as it uses the
    /// user's Claude sign-in:
    ///
    ///     bazel test --config=macos-app //apps/desktop/vitruvian-code/macos:VitruvianCodeTests \
    ///       --test_filter=ClaudeACPAdapterTests/testLive --strategy=TestRunner=local \
    ///       --test_env=CLAUDE_ACP_LIVE_ADAPTER=/path/to/claude-agent-acp --test_env=HOME=$HOME --test_env=USER=$USER
    func testLiveSubagentThroughTheAppsConnection() async throws {
        let environmentVariables = ProcessInfo.processInfo.environment
        guard let adapter = environmentVariables["CLAUDE_ACP_LIVE_ADAPTER"], !adapter.isEmpty else {
            throw XCTSkip("Set CLAUDE_ACP_LIVE_ADAPTER to a claude-agent-acp binary to run one real turn.")
        }
        let work = (scratch as NSString).appendingPathComponent("work")
        try FileManager.default.createDirectory(atPath: work, withIntermediateDirectories: true)
        let home = environmentVariables["HOME"] ?? NSHomeDirectory()
        let launch = AgentProcessLaunchSpec(
            executable: adapter, arguments: [],
            environment: ClaudeACPAdapter.environment(
                base: ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "HOME": home, "TMPDIR": NSTemporaryDirectory(),
                       "USER": environmentVariables["USER"] ?? NSUserName(), "LOGNAME": environmentVariables["USER"] ?? NSUserName()],
                configDirectory: nil),
            workingDirectory: work)
        let tracker = ClaudeSubagentTracker()
        let connection = ACPConnection(
            launchSpec: launch, policy: .none, modeProvider: { (.yolo, false) },
            hooks: ACPConnection.Hooks(
                transformSessionUpdate: { update in (notification: update, extraEvents: tracker.event(for: update).map { [$0] } ?? []) },
                modeSync: .agentPlanMode),
            sessionSetupTimeout: 120)
        var shown: [VitruvianCodeActiveSubagent] = []
        var reply = ""
        let reader = Task { @MainActor in
            for await event in connection.events {
                switch event {
                case .subagent(let subagent, _): shown.append(subagent)
                case .text(let chunk): reply += chunk
                case .finished(let status, _, let error, _, _): reply += " [finished \(status) \(error ?? "")]"
                case .connectionFailed(let failure): reply += " [failed \(failure.message) \(failure.detail ?? "")]"
                default: break
                }
            }
        }
        _ = try await connection.start(AgentSessionRequest(workingDirectory: work))
        try await connection.syncMode(approvalMode: .yolo, planSwitch: false)
        let stop = try await connection.prompt([.text(
            "Use your Agent tool once to start a subagent with the description 'say ok' and the prompt "
            + "'Reply with exactly: sub ok'. Wait for it, then reply with exactly: done")])
        for _ in 0..<200 { await Task.yield() }
        reader.cancel()
        await connection.stop()
        print("ClaudeACPLive: stop=\(stop.rawValue) reply=\(reply.prefix(600)) subagents=\(shown.map { "\($0.role):\($0.isRunning)" })")
        XCTAssertEqual(stop, .endTurn)
        XCTAssertEqual(shown.first?.isRunning, true, "the chat saw the subagent start")
        XCTAssertEqual(shown.last?.isRunning, false, "and finish")
    }

    /// The installed adapter's version is kept on the built-in Claude provider across saves.
    func testTheBuiltInClaudeProviderKeepsItsAdapter() {
        var saved = VitruvianCodeCLIProvider.claude
        saved.connection = .claudeACP
        saved.registryAgent = .init(agentID: "claude-acp", version: "0.112.0")
        let claude = VitruvianCodeCLIProvider.available(saved: [saved]).first { $0.id == VitruvianCodeCLIProvider.claude.id }
        XCTAssertEqual(claude?.registryAgent, .init(agentID: "claude-acp", version: "0.112.0"))
        XCTAssertEqual(claude?.route, .claude, "still Claude, not a registry agent")
    }
}
