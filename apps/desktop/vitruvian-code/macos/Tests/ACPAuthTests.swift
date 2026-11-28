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

/// Signing in from the failure card (`ACPAuth`, design step 5). Every sign-in program here is a
/// fake: either an in-memory process or `/bin/sh` standing in for one. No real sign-in runs.
@MainActor
final class ACPAuthTests: XCTestCase {
    private var scratchSuites: [(UserDefaults, String)] = []

    override func tearDown() {
        for (defaults, domain) in scratchSuites { defaults.removePersistentDomain(forName: domain) }
        scratchSuites.removeAll()
        super.tearDown()
    }

    private static let agentLaunch = AgentProcessLaunchSpec(
        executable: "/opt/agents/demo-agent",
        arguments: ["acp"],
        environment: [
            "HOME": "/Users/someone",
            "PATH": "/usr/bin:/bin",
            "ANTHROPIC_API_KEY": "sk-ant-secret-value",
            "GH_TOKEN": "ghp_secret_value",
        ],
        workingDirectory: "/workspace"
    )

    private static let terminalMethod = AgentSignInMethod(
        id: "demo-login",
        name: "Demo",
        kind: .terminal(ACPAuth.terminalCommand(
            launchSpec: agentLaunch,
            methodArguments: ["--login"],
            methodEnvironment: ["DEMO_LOGIN_MODE": "browser"]
        ))
    )

    // MARK: - Methods from authMethods

    func testMethodsAreListedFromTheAgentsAuthMethods() {
        let advertised = [
            ACPAuthMethod(id: "oauth-personal", name: "Google", description: "Sign in with Google"),
            ACPAuthMethod(id: "agent-typed", name: "Typed agent", type: "agent"),
            ACPAuthMethod(id: "cli-login", name: "Terminal login", type: "terminal", args: ["--login"], env: ["MODE": "x"]),
            ACPAuthMethod(id: "api-key", name: "API key", type: "env_var"),
            ACPAuthMethod(id: "oauth-personal", name: "Duplicate"),
            ACPAuthMethod(id: String(repeating: "x", count: 129), name: "Too long"),
            ACPAuthMethod(id: "  ", name: "Blank"),
        ]
        let offered = ACPAuth.signInMethods(advertised: advertised, launchSpec: Self.agentLaunch, terminalAdvertised: true)
        XCTAssertEqual(offered.map(\.id), ["oauth-personal", "agent-typed", "cli-login"])
        XCTAssertEqual(offered[0].kind, .agent)
        XCTAssertEqual(offered[0].name, "Google")
        XCTAssertEqual(offered[1].kind, .agent)
        XCTAssertEqual(offered[2].command?.arguments, ["acp", "--login"])

        let withoutTerminal = ACPAuth.signInMethods(advertised: advertised, launchSpec: Self.agentLaunch, terminalAdvertised: false)
        XCTAssertEqual(withoutTerminal.map(\.id), ["oauth-personal", "agent-typed"],
                       "a terminal method is offered only when the app said it can run one")

        let many = (0..<40).map { ACPAuthMethod(id: "m\($0)", name: "M\($0)") }
        XCTAssertEqual(ACPAuth.signInMethods(advertised: many, launchSpec: Self.agentLaunch, terminalAdvertised: true).count,
                       ACPAuth.maxMethods)
    }

    func testTheAuthMethodFieldsDecodeAndAMalformedOneDropsOnlyItsField() throws {
        let json = #"""
        {"protocolVersion":1,"authMethods":[
          {"id":"t","name":"T","type":"terminal","args":["--login"],"env":{"A":"b"}},
          {"id":"bad","name":"Bad","type":"terminal","args":"not-a-list","env":7}
        ]}
        """#
        let result = try JSONDecoder().decode(ACPInitializeResult.self, from: Data(json.utf8))
        XCTAssertEqual(result.authMethods?[0], ACPAuthMethod(id: "t", name: "T", type: "terminal", args: ["--login"], env: ["A": "b"]))
        XCTAssertEqual(result.authMethods?[1], ACPAuthMethod(id: "bad", name: "Bad", type: "terminal"))
    }

    func testTheTerminalCapabilityIsAdvertisedOnlyWhenThePolicySaysSo() throws {
        let encoder = JSONEncoder()
        let off = try XCTUnwrap(String(data: encoder.encode(ACPClientPolicy.none.clientCapabilities), encoding: .utf8))
        XCTAssertFalse(off.contains("auth"), off)
        let on = try XCTUnwrap(String(data: encoder.encode(ACPClientPolicy(authTerminal: true).clientCapabilities), encoding: .utf8))
        XCTAssertTrue(on.contains(#""auth":{"terminal":true}"#), on)
        XCTAssertFalse(String(data: try encoder.encode(ACPClientPolicy.claudeSDK.clientCapabilities), encoding: .utf8)!.contains("auth"),
                       "the Claude helper's initialize is unchanged")
    }

    // MARK: - Agent methods call authenticate

    func testAnAgentMethodSendsAuthenticateBeforeTheSessionOpens() async throws {
        let agent = ScriptedACPAgent()
        let connection = ACPConnection(
            launchSpec: Self.agentLaunch,
            hooks: ACPConnection.Hooks(authenticateMethodID: "oauth-personal"),
            processFactory: agent.makeProcessFactory()
        )
        let driver = Task {
            try await agent.playSteps([
                .expectClientRequest(method: "initialize"),
                .agentSend(Self.result(["protocolVersion": .int(1), "authMethods": .array([
                    .object(["id": .string("oauth-personal"), "name": .string("Google")]),
                ])])),
                .expectClientRequest(method: "authenticate"),
                .agentSend(Self.result([:])),
                .expectClientRequest(method: "session/new"),
                .agentSend(Self.result(["sessionId": .string("sess-1")])),
            ])
        }
        let sessionID = try await withACPTestTimeout(seconds: 3) {
            try await connection.start(AgentSessionRequest(workingDirectory: "/workspace"))
        }
        try await withACPTestTimeout(seconds: 3) { try await driver.value }
        XCTAssertEqual(sessionID, "sess-1")
        let auth = try await agent.clientMessage(at: 1)
        XCTAssertEqual(auth.objectValue?["method"]?.stringValue, "authenticate")
        XCTAssertEqual(auth.objectValue?["params"]?.objectValue?["methodId"]?.stringValue, "oauth-personal")
        await connection.stop()
    }

    func testATerminalMethodIsNeverSentAsAuthenticate() async throws {
        let agent = ScriptedACPAgent()
        let connection = ACPConnection(
            launchSpec: Self.agentLaunch,
            policy: ACPClientPolicy(authTerminal: true),
            hooks: ACPConnection.Hooks(authenticateMethodID: "cli-login"),
            processFactory: agent.makeProcessFactory()
        )
        let reader = ACPEventStreamReader(connection.events)
        let driver = Task {
            try await agent.playSteps([
                .expectClientRequest(method: "initialize"),
                .agentSend(Self.result(["protocolVersion": .int(1), "authMethods": .array([
                    .object(["id": .string("cli-login"), "name": .string("Login"), "type": .string("terminal")]),
                ])])),
            ])
        }
        do {
            _ = try await withACPTestTimeout(seconds: 3) {
                try await connection.start(AgentSessionRequest(workingDirectory: "/workspace"))
            }
            XCTFail("a terminal method's ID is not sent")
        } catch {}
        try await withACPTestTimeout(seconds: 3) { try await driver.value }
        let methods = await agent.allClientMessages().compactMap { $0.objectValue?["method"]?.stringValue }
        XCTAssertFalse(methods.contains("authenticate"), "\(methods)")
        let failure = try await Self.firstFailure(reader)
        XCTAssertEqual(failure.kind, .auth)
        XCTAssertEqual(failure.message, ACPConnection.signInMethodGoneMessage)
    }

    func testASignInFailureCarriesTheAgentsMethods() async throws {
        let agent = ScriptedACPAgent()
        let connection = ACPConnection(
            launchSpec: Self.agentLaunch,
            policy: ACPClientPolicy(authTerminal: true),
            processFactory: agent.makeProcessFactory()
        )
        let reader = ACPEventStreamReader(connection.events)
        let driver = Task {
            try await agent.playSteps([
                .expectClientRequest(method: "initialize"),
                .agentSend(Self.result(["protocolVersion": .int(1), "authMethods": .array([
                    .object(["id": .string("oauth"), "name": .string("Browser")]),
                    .object(["id": .string("cli-login"), "name": .string("Terminal"), "type": .string("terminal"),
                             "args": .array([.string("--login")])]),
                ])])),
                .expectClientRequest(method: "session/new"),
                .agentSend(.object(["jsonrpc": .string("2.0"), "id": .string("$id"),
                                    "error": .object(["code": .int(-32000), "message": .string("Authentication required")])])),
            ])
        }
        do {
            _ = try await withACPTestTimeout(seconds: 3) {
                try await connection.start(AgentSessionRequest(workingDirectory: "/workspace"))
            }
            XCTFail("start needs sign-in")
        } catch {}
        try await withACPTestTimeout(seconds: 3) { try await driver.value }
        let failure = try await Self.firstFailure(reader)
        XCTAssertEqual(failure.kind, .auth)
        XCTAssertEqual(failure.signInMethods.map(\.id), ["oauth", "cli-login"])
        guard failure.signInMethods.count == 2 else { return }
        XCTAssertEqual(failure.signInMethods[1].command?.executable, "/opt/agents/demo-agent")
        XCTAssertEqual(failure.signInMethods[1].command?.arguments, ["acp", "--login"])
    }

    // MARK: - Terminal methods: argv, output, exit status, cancel

    func testATerminalMethodRunsTheAgentsOwnProgramWithArgvNotAShell() async throws {
        let tricky = ACPAuth.terminalCommand(
            launchSpec: Self.agentLaunch,
            methodArguments: ["--login", "a b; rm -rf ~", "$(whoami)"],
            methodEnvironment: [:]
        )
        XCTAssertEqual(tricky.executable, "/opt/agents/demo-agent")
        XCTAssertEqual(tricky.arguments, ["acp", "--login", "a b; rm -rf ~", "$(whoami)"],
                       "each argument stays one string; nothing is joined or split")

        let launches = LockedBox<[AgentProcessLaunchSpec]>([])
        let fake = FakeSignInProcess()
        let method = AgentSignInMethod(id: "t", name: "T", kind: .terminal(tricky))
        let run = try XCTUnwrap(ACPSignInRun(method: method, launcher: { spec in
            launches.withValue { $0.append(spec) }
            return fake
        }))
        run.start()
        let spec = try XCTUnwrap(launches.value.first)
        XCTAssertEqual(spec.executable, "/opt/agents/demo-agent", "the program itself, not /bin/sh -c")
        XCTAssertEqual(spec.arguments, tricky.arguments)
        XCTAssertEqual(spec.workingDirectory, "/workspace")
        fake.finish(exitCode: 0)
        _ = await run.waitUntilFinished()
    }

    func testTheRealLauncherStartsTheProgramWithNoShell() async throws {
        // `/bin/echo` prints its arguments as given; a shell would have expanded these.
        let command = AgentSignInCommand(executable: "/bin/echo", arguments: ["$HOME", "a;b", "*"], environment: [:])
        let run = try XCTUnwrap(ACPSignInRun(method: AgentSignInMethod(id: "e", name: "E", kind: .terminal(command))))
        run.start()
        let state = try await withACPTestTimeout(seconds: 5) { await run.waitUntilFinished() }
        XCTAssertEqual(state, .succeeded)
        XCTAssertEqual(run.output.trimmingCharacters(in: .whitespacesAndNewlines), "$HOME a;b *")
    }

    /// A stand-in for a sign-in tool that needs a terminal: it refuses to run unless its input and
    /// output are terminals and `/dev/tty` opens, prints a prompt with no newline, and reads a reply.
    private static let needsATerminal = AgentSignInCommand(
        executable: "/bin/sh",
        arguments: ["-c", #"test -t 0 && test -t 1 && (: </dev/tty) || { echo "not a terminal"; exit 9; }; printf "Paste code: "; read code; echo "got [$code] TERM=$TERM""#],
        environment: ACPAuth.signInEnvironment(base: ["PATH": "/usr/bin:/bin"], method: [:]).environment
    )

    func testATerminalSignInRunsInAPseudoTerminal() async throws {
        let run = try XCTUnwrap(ACPSignInRun(method: AgentSignInMethod(id: "tty", name: "TTY", kind: .terminal(Self.needsATerminal))))
        run.start()
        try await waitUntil("the prompt with no newline") { run.output.contains("Paste code: ") }
        XCTAssertEqual(run.state, .running)
        run.send("ABCD-1234")
        let state = try await withACPTestTimeout(seconds: 5) { await run.waitUntilFinished() }
        XCTAssertEqual(state, .succeeded, run.output)
        XCTAssertTrue(run.output.contains("got [ABCD-1234] TERM=xterm-256color"), run.output)
        XCTAssertFalse(run.output.contains("not a terminal"), run.output)
        XCTAssertFalse(run.output.contains("\r"), "the terminal's carriage returns are taken out")
    }

    func testTheSameProgramFailsUnderPipes() async throws {
        // The check above means something only if the stand-in really needs a terminal.
        let process = try AgentProcess(AgentProcessLaunchSpec(
            executable: Self.needsATerminal.executable,
            arguments: Self.needsATerminal.arguments,
            environment: Self.needsATerminal.environment
        ))
        process.closeInput()
        let exit = try await process.waitForExit(timeout: 5)
        XCTAssertEqual(exit.exitCode, 9)
    }

    func testOutputStreamsIntoTheRunAsItIsPrinted() async throws {
        let fake = FakeSignInProcess()
        let run = try XCTUnwrap(ACPSignInRun(method: Self.terminalMethod, launcher: { _ in fake }))
        run.start()
        XCTAssertEqual(run.state, .running)
        fake.emit("Opening your browser…\n")
        try await waitUntil("first line") { run.output.contains("Opening your browser") }
        XCTAssertEqual(run.state, .running, "output arrives while the program still runs")
        fake.emit("\u{1B}[32mVisit https://example.test/device\u{1B}[0m\r\n")
        try await waitUntil("second line") { run.output.contains("Visit https://example.test/device") }
        XCTAssertFalse(run.output.contains("\u{1B}"), "terminal codes are taken out")
        run.send("ABCD-1234")
        XCTAssertEqual(fake.input, ["ABCD-1234\n"], "only what the user typed goes to the program")
        fake.finish(exitCode: 0)
        _ = await run.waitUntilFinished()
    }

    func testExitZeroReconnectsAndRetriesTheTurn() async throws {
        let (session, connections) = makeSession()
        let config = VitruvianCodeConfiguration(approvalMode: .standard, activeProvider: Self.liveProvider)
        try await failFirstTurnWithSignIn(session, connections, config: config, methods: [Self.terminalMethod])

        let fake = FakeSignInProcess()
        session.signInLauncher = { _ in fake }
        let card = AgentErrorCardView(failure: try XCTUnwrap(session.lastLiveFailure), strings: VitruvianCodeChatStrings(),
                                      onRetry: {}, onUseCommandLine: {}, onDismiss: {}, onSignIn: { _ in })
        XCTAssertEqual(card.signInMethodsShown, [Self.terminalMethod])

        session.signIn(with: Self.terminalMethod, configuration: config, agentPath: "/fake/agent")
        let run = try XCTUnwrap(session.signInRun)
        XCTAssertEqual(run.state, .ready, "the sheet shows the command before anything runs")
        XCTAssertEqual(connections.value.count, 1)
        run.start()
        fake.finish(exitCode: 0)

        try await waitUntil("retried on a new connection") {
            connections.value.count == 2 && connections.value[1].promptCalls.count == 1
        }
        XCTAssertTrue(connections.value[0].isStopped, "the old connection is closed, so the agent reads the new login")
        XCTAssertEqual(connections.value[1].promptCalls.first, [.text("Hello")])
        XCTAssertNil(session.signInRun)
        XCTAssertNil(session.lastLiveFailure)
        connections.value[1].finishPrompt(with: .endTurn)
        await session.stopAll()
    }

    func testANonZeroExitShowsTheErrorAndRetriesNothing() async throws {
        let (session, connections) = makeSession()
        let config = VitruvianCodeConfiguration(approvalMode: .standard, activeProvider: Self.liveProvider)
        try await failFirstTurnWithSignIn(session, connections, config: config, methods: [Self.terminalMethod])

        let fake = FakeSignInProcess()
        session.signInLauncher = { _ in fake }
        session.signIn(with: Self.terminalMethod, configuration: config, agentPath: "/fake/agent")
        let run = try XCTUnwrap(session.signInRun)
        run.start()
        fake.emit("Login failed: access denied\n")
        fake.finish(exitCode: 3)
        let state = await run.waitUntilFinished()
        XCTAssertEqual(state, .failed(exitStatus: 3))
        let strings = VitruvianCodeChatStrings()
        XCTAssertEqual(AgentSignInSheetLogic.statusText(state, strings: strings),
                       "Sign-in did not finish (status 3). Nothing was retried.")
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(connections.value.count, 1, "no reconnect")
        XCTAssertEqual(connections.value[0].promptCalls.count, 1, "no retry")
        XCTAssertTrue(session.signInRun === run, "the sheet stays open with the error")
        XCTAssertNotNil(session.lastLiveFailure, "the card stays")
        XCTAssertEqual(session.lastFailedPrompt, "Hello")
        await session.closeSignIn()
        XCTAssertNil(session.signInRun)
        await session.stopAll()
    }

    func testCancelEndsTheWholeProcessGroupAndRetriesNothing() async throws {
        // A stand-in sign-in program that leaves a second process in its group.
        let command = AgentSignInCommand(executable: "/bin/sh", arguments: ["-c", "sleep 30 & sleep 30"], environment: [:])
        let method = AgentSignInMethod(id: "slow", name: "Slow", kind: .terminal(command))
        let launched = LockedBox<ACPPtySignInProcess?>(nil)

        let (session, connections) = makeSession()
        let config = VitruvianCodeConfiguration(approvalMode: .standard, activeProvider: Self.liveProvider)
        try await failFirstTurnWithSignIn(session, connections, config: config, methods: [method])
        session.signInLauncher = { spec in
            let process = try ACPPtySignInProcess(spec)
            launched.withValue { $0 = process }
            return process
        }
        session.signIn(with: method, configuration: config, agentPath: "/fake/agent")
        let run = try XCTUnwrap(session.signInRun)
        run.start()
        let process = try XCTUnwrap(launched.value)
        let group = process.processGroupID
        try await waitUntil("both sleeps run") { Self.processCount(inGroup: group) >= 2 }

        await run.cancel()
        XCTAssertEqual(run.state, .cancelled)
        try await waitUntil("the group is gone", timeout: 5) { !AgentProcess.processGroupExists(group) }
        XCTAssertEqual(connections.value.count, 1, "no reconnect after a cancel")
        XCTAssertEqual(connections.value[0].promptCalls.count, 1, "no retry after a cancel")
        XCTAssertEqual(AgentSignInSheetLogic.statusText(.cancelled, strings: VitruvianCodeChatStrings()),
                       "Sign-in cancelled. Nothing was retried.")
        await session.closeSignIn()
        await session.stopAll()
    }

    func testTheToolsShutdownKillsARunningSignInAndItsGroup() async throws {
        let registry = ChildProcesses()
        let process = try ACPPtySignInProcess(
            AgentProcessLaunchSpec(executable: "/bin/sh", arguments: ["-c", "sleep 30 & sleep 30"], environment: [:]),
            registry: registry
        )
        let group = process.processGroupID
        XCTAssertEqual(registry.pids, [process.pid], "a running sign-in is listed for the shutdown deadline")
        try await waitUntil("both sleeps run") { Self.processCount(inGroup: group) >= 2 }
        XCTAssertEqual(registry.killAll(), 1)
        try await waitUntil("the group is gone", timeout: 5) { !AgentProcess.processGroupExists(group) }
        _ = await process.waitForExit()
        XCTAssertEqual(registry.pids, [], "a reaped sign-in is taken off the list")
    }

    func testAnAgentMethodFromTheCardReconnectsWithAuthenticate() async throws {
        let (session, connections) = makeSession()
        let config = VitruvianCodeConfiguration(approvalMode: .standard, activeProvider: Self.liveProvider)
        let method = AgentSignInMethod(id: "oauth-personal", name: "Google", kind: .agent)
        try await failFirstTurnWithSignIn(session, connections, config: config, methods: [method])
        XCTAssertNil(connections.value[0].spec.signInMethodID)

        session.signIn(with: method, configuration: config, agentPath: "/fake/agent")
        XCTAssertNil(session.signInRun, "an agent method needs no sheet")
        try await waitUntil("retried") { connections.value.count == 2 && connections.value[1].promptCalls.count == 1 }
        XCTAssertEqual(connections.value[1].spec.signInMethodID, "oauth-personal",
                       "the new connection is told to send authenticate with the picked method")
        connections.value[1].emit(.finished(status: "completed", response: "OK", error: nil, conversationID: "mock-signin-1"))
        connections.value[1].finishPrompt(with: .endTurn)
        try await waitUntil("turn done") { !session.isRunning }

        session.send("Again", configuration: config, agentPath: "/fake/agent")
        try await waitUntil("next turn") { connections.value.flatMap(\.promptCalls).count == 3 }
        XCTAssertTrue(connections.value.allSatisfy { $0 === connections.value[1] || $0.spec.signInMethodID == nil },
                      "authenticate is asked for once, not on every later connection")
        connections.value.last?.finishPrompt(with: .endTurn)
        await session.stopAll()
    }

    // MARK: - Secrets

    func testNoSecretReachesTheArgvTheEnvironmentOrTheLog() async throws {
        let command = ACPAuth.terminalCommand(
            launchSpec: Self.agentLaunch,
            methodArguments: ["--login"],
            methodEnvironment: [
                "DEMO_LOGIN_MODE": "browser-mode-value",
                "PATH": "/tmp/evil",
                "DYLD_INSERT_LIBRARIES": "/tmp/evil.dylib",
                "NODE_OPTIONS": "--require /tmp/evil.js",
            ]
        )
        let secrets = ["sk-ant-secret-value", "ghp_secret_value"]
        for secret in secrets {
            XCTAssertFalse(command.arguments.contains { $0.contains(secret) }, "argv holds no secret")
            XCTAssertFalse(command.environment.values.contains { $0.contains(secret) }, "the environment holds no secret")
        }
        XCTAssertEqual(Set(command.environment.keys), ["HOME", "PATH", "TERM", "DEMO_LOGIN_MODE"],
                       "only the app's short list and the method's own variable")
        XCTAssertEqual(command.environment["PATH"], "/usr/bin:/bin", "the method cannot change PATH")
        XCTAssertEqual(command.refusedVariableNames, ["DYLD_INSERT_LIBRARIES", "NODE_OPTIONS", "PATH"])
        XCTAssertEqual(command.methodVariableNames, ["DEMO_LOGIN_MODE"])

        let logged = LockedBox<[String]>([])
        let fake = FakeSignInProcess()
        let run = try XCTUnwrap(ACPSignInRun(
            method: AgentSignInMethod(id: "t", name: "T", kind: .terminal(command)),
            launcher: { _ in fake },
            log: { line in logged.withValue { $0.append(line) } }
        ))
        run.start()
        fake.emit("Your token: tok-printed-by-agent\n")
        try await waitUntil("output") { run.output.contains("tok-printed-by-agent") }
        run.send("typed-by-user-code")
        fake.finish(exitCode: 0)
        _ = await run.waitUntilFinished()
        let log = logged.value.joined(separator: "\n")
        XCTAssertFalse(log.isEmpty, "the run does log, so this check means something")
        for value in ["tok-printed-by-agent", "typed-by-user-code", "browser-mode-value", "--login", "/usr/bin:/bin", "/Users/someone"] {
            XCTAssertFalse(log.contains(value), "the log holds \(value): \(log)")
        }
    }

    func testNetworkSettingsAndTERMPassButNoSecretDoes() {
        var base: [String: String] = [
            "HOME": "/Users/someone", "TMPDIR": "/var/folders/x/T/",
            "ANTHROPIC_API_KEY": "sk-ant-api", "ANTHROPIC_AUTH_TOKEN": "sk-ant-token",
            "OPENAI_API_KEY": "sk-openai", "GH_TOKEN": "ghp_x", "AWS_SECRET_ACCESS_KEY": "aws-secret",
            "TERM": "dumb",
        ]
        let network = ["HTTP_PROXY", "HTTPS_PROXY", "NO_PROXY", "ALL_PROXY", "http_proxy", "https_proxy",
                       "no_proxy", "all_proxy", "SSL_CERT_FILE", "SSL_CERT_DIR", "NODE_EXTRA_CA_CERTS"]
        for name in network { base[name] = "value-of-\(name)" }
        let environment = ACPAuth.signInEnvironment(base: base, method: [:]).environment
        for name in network {
            XCTAssertEqual(environment[name], "value-of-\(name)", name)
        }
        XCTAssertEqual(environment["TMPDIR"], "/var/folders/x/T/")
        XCTAssertEqual(environment["TERM"], "xterm-256color", "the pseudo-terminal's type, not the app's")
        for secret in ["ANTHROPIC_API_KEY", "ANTHROPIC_AUTH_TOKEN", "OPENAI_API_KEY", "GH_TOKEN", "AWS_SECRET_ACCESS_KEY"] {
            XCTAssertNil(environment[secret], secret)
        }
        let claude = ACPAuth.claudeSignInMethods(claudePath: "/bin/claude", helperEnvironment: base, workingDirectory: nil)
        XCTAssertNil(claude.first?.command?.environment["ANTHROPIC_AUTH_TOKEN"])
        XCTAssertEqual(claude.first?.command?.environment["HTTPS_PROXY"], "value-of-HTTPS_PROXY")
    }

    // MARK: - Claude on the Agent SDK

    func testClaudeOffersClaudeAuthLoginInItsConfigFolderAndNothingElse() {
        let methods = ACPAuth.claudeSignInMethods(
            claudePath: "/Users/someone/.local/bin/claude",
            helperEnvironment: [
                "HOME": "/Users/someone",
                "PATH": "/opt/node/bin:/usr/bin",
                "CLAUDE_CONFIG_DIR": "/Users/someone/.claude_work",
                "ANTHROPIC_API_KEY": "sk-ant-secret-value",
                "CLAUDE_CODE_ENABLE_TODO_TOOLS": "1",
            ],
            workingDirectory: "/workspace"
        )
        XCTAssertEqual(methods.count, 1)
        let command = try? XCTUnwrap(methods.first?.command)
        XCTAssertEqual(methods.first?.id, ACPAuth.claudeLoginMethodID)
        XCTAssertEqual(command?.executable, "/Users/someone/.local/bin/claude")
        XCTAssertEqual(command?.arguments, ["auth", "login"])
        XCTAssertEqual(command?.environment["CLAUDE_CONFIG_DIR"], "/Users/someone/.claude_work",
                       "the login lands in the folder the helper's claude reads")
        XCTAssertEqual(command?.environment["PATH"], "/opt/node/bin:/usr/bin")
        XCTAssertNil(command?.environment["ANTHROPIC_API_KEY"])
        XCTAssertNil(command?.environment["CLAUDE_CODE_ENABLE_TODO_TOOLS"])
        XCTAssertEqual(command?.displayLine, "/Users/someone/.local/bin/claude auth login")
        XCTAssertEqual(ACPAuth.claudeSignInMethods(claudePath: nil, helperEnvironment: [:], workingDirectory: nil), [])
    }

    func testALoggedOutClaudeMidChatShowsTheClaudeSignInAction() async throws {
        let agent = ScriptedACPAgent()
        let connection = ClaudeSDKConnection(
            launchSpec: AgentProcessLaunchSpec(
                executable: "/fake/node",
                arguments: ["/fake/helper.mjs", "--claude-path", "/fake/bin/claude"],
                environment: ["HOME": "/Users/someone", "PATH": "/usr/bin", "ANTHROPIC_API_KEY": "sk-ant-secret-value"],
                workingDirectory: "/workspace"
            ),
            bundled: BundledNode(nodeURL: URL(fileURLWithPath: "/fake/node"), helperURL: URL(fileURLWithPath: "/fake/helper.mjs")),
            claudePath: "/fake/bin/claude",
            providerID: UUID(),
            secrets: nil,
            modeProvider: { (.yolo, false) },
            versionProbe: { nil },
            processFactory: agent.makeProcessFactory()
        )
        let reader = ACPEventStreamReader(connection.events)
        let driver = Task {
            try await agent.playSteps([
                .expectClientRequest(method: "initialize"),
                .agentSend(Self.result(["protocolVersion": .int(1), "authMethods": .array([])])),
                .expectClientRequest(method: "session/new"),
                .agentSend(Self.result(["sessionId": .string("claude-1")])),
                .expectClientRequest(method: "session/set_mode"),
                .agentSend(Self.result([:])),
                .expectClientRequest(method: "session/prompt"),
                .agentSend(.object(["jsonrpc": .string("2.0"), "id": .string("$id"), "error": .object([
                    "code": .int(-32000),
                    "message": .string("Run `claude auth login` in your terminal and try again."),
                    "data": .object(["reason": .string("auth_required")]),
                ])])),
            ])
        }
        _ = try await withACPTestTimeout(seconds: 3) {
            try await connection.start(AgentSessionRequest(workingDirectory: "/workspace"))
        }
        let stop = try await withACPTestTimeout(seconds: 3) { try await connection.prompt([.text("hi")]) }
        try await withACPTestTimeout(seconds: 3) { try await driver.value }
        XCTAssertEqual(stop, .error)
        let failure = try await Self.firstFailure(reader)
        XCTAssertEqual(failure.kind, .auth)
        XCTAssertEqual(failure.signInMethods.map(\.id), [ACPAuth.claudeLoginMethodID])
        XCTAssertEqual(failure.signInMethods.first?.command?.executable, "/fake/bin/claude")
        XCTAssertEqual(failure.signInMethods.first?.command?.arguments, ["auth", "login"])
        XCTAssertNil(failure.signInMethods.first?.command?.environment["ANTHROPIC_API_KEY"])

        let card = AgentErrorCardView(
            failure: AgentLiveFailure(message: failure.message, signInMethods: failure.signInMethods, needsSignIn: true),
            strings: VitruvianCodeChatStrings(),
            onRetry: {}, onUseCommandLine: {}, onDismiss: {}, onSignIn: { _ in }
        )
        XCTAssertEqual(card.signInMethodsShown.map(\.name), ["Claude Code"])
        XCTAssertEqual(AgentBannerLogic.format(VitruvianCodeChatStrings().signInWithFormat, "Claude Code"), "Sign in with Claude Code")
        await connection.stop()
    }

    // MARK: - Helpers

    private static let liveProvider = VitruvianCodeCLIProvider(
        id: VitruvianCodeCLIProvider.claude.id,
        name: "Claude Code",
        commandTemplate: VitruvianCodeCLIProvider.claude.commandTemplate,
        connection: .claudeSDK
    )

    private static func result(_ fields: [String: ACPJSONValue]) -> ACPJSONValue {
        .object(["jsonrpc": .string("2.0"), "id": .string("$id"), "result": .object(fields)])
    }

    private static func firstFailure(_ reader: ACPEventStreamReader) async throws -> AgentFailure {
        while let event = try await reader.next(timeout: 3) {
            if case .connectionFailed(let failure) = event { return failure }
        }
        throw ACPTestTimeoutError.timedOut(description: "no connectionFailed", seconds: 3)
    }

    private static func processCount(inGroup group: pid_t) -> Int {
        var count = 0
        for pid in 1..<pid_t(99_999) where getpgid(pid) == group { count += 1; if count >= 2 { break } }
        return count
    }

    private func failFirstTurnWithSignIn(
        _ session: VitruvianCodeQuickPromptSession,
        _ connections: LockedBox<[SignInMockConnection]>,
        config: VitruvianCodeConfiguration,
        methods: [AgentSignInMethod]
    ) async throws {
        session.send("Hello", configuration: config, agentPath: "/fake/agent")
        try await waitUntil("prompt") { connections.value.first?.promptCalls.count == 1 }
        let first = try XCTUnwrap(connections.value.first)
        first.emit(.connectionFailed(AgentFailure(kind: .auth, message: "Sign in first.", signInMethods: methods)))
        first.failPrompt(with: ACPConnectionError.notStarted)
        try await waitUntil("failed") { !session.isRunning }
        XCTAssertEqual(session.lastLiveFailure?.signInMethods, methods)
        XCTAssertEqual(session.lastLiveFailure?.needsSignIn, true)
        XCTAssertEqual(session.lastFailedPrompt, "Hello")
    }

    private func makeSession() -> (VitruvianCodeQuickPromptSession, LockedBox<[SignInMockConnection]>) {
        let connections = LockedBox<[SignInMockConnection]>([])
        let domain = "com.vitruviansoftware.vitruvian-code.tests.signin.\(UUID().uuidString)"
        let defaults = ScratchDefaults.suite(named: domain)!
        defaults.removePersistentDomain(forName: domain)
        scratchSuites.append((defaults, domain))
        let environment = VitruvianCodeEngine.Environment(
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
            makeConnection: { spec in
                let connection = SignInMockConnection(spec: spec)
                connections.withValue { $0.append(connection) }
                return connection
            },
            runProgram: { _, _ in nil }
        )
        let session = VitruvianCodeQuickPromptSession(environment: environment, host: SignInMockHost())
        session.takeCheckpoint = { _ in nil }
        return (session, connections)
    }

    private func waitUntil(
        _ description: String,
        timeout: TimeInterval = 4.0,
        condition: @escaping @MainActor () -> Bool
    ) async throws {
        try await withACPTestTimeout(seconds: timeout, description: description) { @MainActor in
            while !condition() {
                try? await Task.sleep(nanoseconds: 5_000_000)
            }
        }
    }
}

private final class LockedBox<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var rawValue: Value
    init(_ initial: Value) { rawValue = initial }
    var value: Value { lock.withLock { rawValue } }
    func withValue(_ body: (inout Value) -> Void) { lock.withLock { body(&rawValue) } }
}

/// An in-memory sign-in program: the test says what it prints and when it ends.
private final class FakeSignInProcess: ACPSignInProcess, @unchecked Sendable {
    let output: AsyncStream<Data>
    private let continuation: AsyncStream<Data>.Continuation
    private let lock = NSLock()
    private var exit: AgentProcessExit?
    private var exitWaiters: [CheckedContinuation<AgentProcessExit, Never>] = []
    private var typed: [String] = []
    private(set) var terminated = false

    init() {
        var captured: AsyncStream<Data>.Continuation!
        output = AsyncStream { captured = $0 }
        continuation = captured
    }

    var input: [String] { lock.withLock { typed } }

    func emit(_ text: String) { continuation.yield(Data(text.utf8)) }

    func finish(exitCode: Int32? = nil, signal: Int32? = nil) {
        let waiters: [CheckedContinuation<AgentProcessExit, Never>] = lock.withLock {
            guard exit == nil else { return [] }
            exit = AgentProcessExit(exitCode: exitCode, signal: signal)
            defer { exitWaiters.removeAll() }
            return exitWaiters
        }
        continuation.finish()
        let ended = lock.withLock { exit! }
        for waiter in waiters { waiter.resume(returning: ended) }
    }

    func sendInput(_ data: Data) {
        lock.withLock { typed.append(String(decoding: data, as: UTF8.self)) }
    }

    func waitForExit() async -> AgentProcessExit {
        await withCheckedContinuation { waiter in
            let ended: AgentProcessExit? = lock.withLock {
                if let exit { return exit }
                exitWaiters.append(waiter)
                return nil
            }
            if let ended { waiter.resume(returning: ended) }
        }
    }

    func terminate() async {
        lock.withLock { terminated = true }
        finish(signal: SIGTERM)
    }
}

@MainActor
private final class SignInMockConnection: PersistentAgentConnection {
    let spec: AgentConnectionSpec
    var capabilities = AgentCapabilities(resumeSession: true, closeSession: true)
    let events: AsyncStream<AgentEvent>
    private let continuation: AsyncStream<AgentEvent>.Continuation
    private(set) var promptCalls: [[PromptBlock]] = []
    var isStopped = false
    var isConnected: Bool { !isStopped }
    private var promptContinuation: CheckedContinuation<AgentStopReason, any Error>?

    init(spec: AgentConnectionSpec) {
        self.spec = spec
        var captured: AsyncStream<AgentEvent>.Continuation!
        self.events = AsyncStream { captured = $0 }
        self.continuation = captured
    }

    func start(_ request: AgentSessionRequest) async throws -> String { request.resumeSessionID ?? "mock-signin-1" }
    func syncPlanMode(_ planSwitch: Bool) async throws {}
    func syncMode(approvalMode: VitruvianCodeApprovalMode, planSwitch: Bool) async throws {}
    func prompt(_ blocks: [PromptBlock]) async throws -> AgentStopReason {
        promptCalls.append(blocks)
        return try await withCheckedThrowingContinuation { promptContinuation = $0 }
    }
    func cancel() async {}
    func answer(_ requestID: String, _ choice: AgentAnswer) async throws {}
    func setConfigOption(_ id: String, _ value: AgentConfigValue) async throws -> [AgentConfigOption] { [] }
    func stop() async {
        isStopped = true
        continuation.finish()
        let pending = promptContinuation
        promptContinuation = nil
        pending?.resume(throwing: ACPConnectionError.alreadyStopped)
    }
    func emit(_ event: AgentEvent) { continuation.yield(event) }
    func finishPrompt(with reason: AgentStopReason) {
        let pending = promptContinuation
        promptContinuation = nil
        pending?.resume(returning: reason)
    }
    func failPrompt(with error: any Error) {
        let pending = promptContinuation
        promptContinuation = nil
        pending?.resume(throwing: error)
    }
}

@MainActor
private final class SignInMockHost: VitruvianCodeHost {
    var configuredBotDirectory = ""
    var startsBotAtLaunch = false
    var planMode = false
    var hiddenClaudeSessionIDs: [String] = []
    var chosenProviderID: UUID? = VitruvianCodeCLIProvider.claude.id
    var chosenModels: [UUID: String] = [:]
    var savedProviders: [VitruvianCodeCLIProvider] = []
    var promptHistory: [String] = []
    var worktreeMode = false
    var timelineOnLeft = true
    var sessionPreferences = VitruvianCodeSessionPreferences()
    var chatModes: [String: String] = [:]
    var chatConnections: [String: String] = [:]
    var strings = VitruvianCodeHostStrings()

    func turnNeedsApproval(_ notice: VitruvianCodeTurnNotice) {}
    func turnFinished(_ notice: VitruvianCodeTurnNotice, isChatVisible: Bool) {}
}
