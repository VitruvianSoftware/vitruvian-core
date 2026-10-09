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

import XCTest

import NexusAgentCore

/// Which permission arguments a chat turn is started with, for every way a
/// provider is run, every approval mode and plan mode on and off. The one
/// rule that must never break: a turn skips the agent's permission prompts
/// only when the approval mode is yolo and plan mode is off.
///
/// Each cell sends a real turn through the session and reads the arguments
/// the program would have been started with, so the session's own part
/// (plan mode overriding the approval mode) is in the test too.
@MainActor
final class PermissionArgumentsTests: XCTestCase {

    private final class QuietHost: NexusAgentHost {
        var configuredBotDirectory = ""
        var startsBotAtLaunch = false
        var planMode = false
        var hiddenClaudeSessionIDs: [String] = []
        var chosenProviderID: UUID?
        var savedProviders: [NexusAgentCLIProvider] = []
        var promptHistory: [String] = []
        var worktreeMode = false
        var strings = NexusAgentHostStrings()
        func turnNeedsApproval(_ notice: NexusAgentTurnNotice) {}
        func turnFinished(_ notice: NexusAgentTurnNotice, isChatVisible: Bool) {}
    }

    /// Records what would have been started, and starts nothing.
    @MainActor
    private final class World {
        var agentRuns: [[String]] = []
        var commandRuns: [(path: String, arguments: [String])] = []
        var agentExit: (@MainActor @Sendable (Int32) -> Void)?
        var commandExit: (@MainActor @Sendable (Int32) -> Void)?

        var environment: NexusAgentEngine.Environment {
            NexusAgentEngine.Environment(
                defaults: UserDefaults(suiteName: "com.vitruviansoftware.nexus-agent.tests.unused")!,
                home: "/Users/rig",
                processEnvironment: ["PATH": "/usr/bin"],
                stateDirectory: "/Users/rig/state",
                // The one program a command of the user's own is found as.
                isExecutable: { $0 == "/opt/homebrew/bin/llm" },
                fileExists: { _ in false },
                readFile: { _ in nil },
                readTail: { _, _ in nil },
                writePrivateFile: { _, _ in false },
                removeFile: { _ in },
                isBotProcess: { _ in false },
                signal: { _, _ in },
                launchBot: { _, _, _, _, _ in throw CocoaError(.fileWriteUnknown) },
                schedule: { _, _ in },
                openFile: { _ in },
                launchAgent: { [unowned self] _, arguments, _, _, _, onExit in
                    agentRuns.append(arguments)
                    agentExit = onExit
                    return NexusAgentRunningAgent(terminate: {})
                },
                launchCommand: { [unowned self] path, arguments, _, _, _, _, onExit in
                    commandRuns.append((path, arguments))
                    commandExit = onExit
                    return NexusAgentRunningAgent(terminate: {})
                })
        }
    }

    private static let prompt = "tidy the readme"
    private static let model = "m1"

    private static func own(_ template: String) -> NexusAgentCLIProvider {
        NexusAgentCLIProvider(id: UUID(uuidString: "AAAAAAAA-0000-0000-0000-00000000000A")!,
                              name: "My LLM", commandTemplate: template, isBuiltIn: false)
    }

    /// The arguments one turn is started with. A model is always set, so
    /// Ollama has no list to ask for first.
    private func arguments(provider: NexusAgentCLIProvider, approval: NexusAgentApprovalMode,
                           planMode: Bool, worktree: Bool = false, resuming: String? = nil) -> [String]? {
        let world = World()
        let host = QuietHost()
        host.planMode = planMode
        host.worktreeMode = worktree
        let session = NexusAgentQuickPromptSession(environment: world.environment, host: host)
        if let resuming {
            session.resume(NexusAgentSessionSummary(id: resuming, title: "Earlier", steps: 1, modified: nil),
                           configuration: NexusAgentConfiguration(activeProvider: provider))
        }
        session.send(Self.prompt,
                     configuration: NexusAgentConfiguration(approvalMode: approval, model: Self.model,
                                                            activeProvider: provider),
                     agentPath: "/fake/program")
        defer {
            world.agentExit?(0)
            world.commandExit?(0)
            session.stopTranscriptFollower()
        }
        XCTAssertEqual(world.agentRuns.count + world.commandRuns.count, 1, "exactly one program per turn")
        return world.agentRuns.first ?? world.commandRuns.first?.arguments
    }

    /// The arguments that decide what the agent may do without asking: each
    /// flag, with its value where it takes one, in the order given.
    static func permissionArguments(in arguments: [String]) -> [String] {
        var found: [String] = []
        var index = 0
        while index < arguments.count {
            let argument = arguments[index]
            if argument == "--permission-mode" || argument == "--mode" {
                found.append(argument)
                if index + 1 < arguments.count { found.append(arguments[index + 1]) }
                index += 2
            } else {
                if argument.hasPrefix("--") && isAboutPermissions(argument) { found.append(argument) }
                index += 1
            }
        }
        return found
    }

    private static func isAboutPermissions(_ argument: String) -> Bool {
        let lowered = argument.lowercased()
        return ["permission", "bypass", "yolo", "approval", "trust", "auto-approve", "force"]
            .contains { lowered.contains($0) }
    }

    /// Whether these arguments let the agent act without asking: agy's and
    /// Claude's flag, Claude's bypass mode, or any other spelling of either.
    static func skipsPermissionPrompts(_ arguments: [String]) -> Bool {
        let permission = permissionArguments(in: arguments).map { $0.lowercased() }
        return permission.contains { $0.contains("skip-permissions") || $0.contains("bypass") || $0.contains("yolo") }
    }

    private static let plan = ["--permission-mode", "plan"]

    /// Every cell, written out. Plan mode on is the same for all four
    /// approval modes, which is the point of it.
    private static let expected: [(route: String, provider: NexusAgentCLIProvider,
                                   planOff: [NexusAgentApprovalMode: [String]], planOn: [String])] = [
        ("agy", .antigravity,
         [.yolo: ["--dangerously-skip-permissions"],
          .acceptEdits: ["--mode", "accept-edits"],
          .plan: ["--mode", "plan"],
          .standard: []],
         ["--mode", "plan"]),
        ("Claude", .claude,
         [.yolo: ["--permission-mode", "bypassPermissions", "--dangerously-skip-permissions"],
          .acceptEdits: ["--permission-mode", "acceptEdits"],
          .plan: plan,
          .standard: ["--permission-mode", "default"]],
         plan),
        ("Ollama", .ollama,
         [.yolo: ["--permission-mode", "bypassPermissions", "--dangerously-skip-permissions"],
          .acceptEdits: ["--permission-mode", "acceptEdits"],
          .plan: plan,
          .standard: ["--permission-mode", "default"]],
         plan),
        // A command of the user's own is run as its template is written:
        // the approval mode adds nothing to it and takes nothing away.
        ("own command", own("llm -m {model} \"{prompt}\""),
         [.yolo: [], .acceptEdits: [], .plan: [], .standard: []],
         []),
    ]

    func testEveryCellOfTheTable() {
        XCTAssertEqual(Self.expected.map(\.provider.route), [.antigravity, .claude, .ollama, .custom],
                       "one row for each way a provider is run")
        var cells = 0
        for row in Self.expected {
            XCTAssertEqual(Set(row.planOff.keys), Set(NexusAgentApprovalMode.allCases), "\(row.route): every mode")
            for mode in NexusAgentApprovalMode.allCases {
                for planMode in [false, true] {
                    let cell = "\(row.route), \(mode.rawValue), plan mode \(planMode ? "on" : "off")"
                    guard let started = arguments(provider: row.provider, approval: mode, planMode: planMode) else {
                        XCTFail("\(cell): nothing was started")
                        continue
                    }
                    let want = planMode ? row.planOn : (row.planOff[mode] ?? ["missing"])
                    XCTAssertEqual(Self.permissionArguments(in: started), want, cell)
                    // The rule itself, apart from the table: only yolo with
                    // plan mode off may skip, and no own command does unless
                    // its template says so.
                    let maySkip = mode == .yolo && !planMode && row.provider.route != .custom
                    XCTAssertEqual(Self.skipsPermissionPrompts(started), maySkip, cell)
                    cells += 1
                }
            }
        }
        XCTAssertEqual(cells, 32, "four ways to run, four modes, plan mode on and off")
    }

    /// The two things a turn can carry besides its approval mode. Each adds
    /// its own flag and nothing else, so neither can let a turn skip the
    /// agent's prompts outside yolo. agy has no worktree flag at all.
    private static let extras: [(route: String, provider: NexusAgentCLIProvider,
                                 worktree: [String], resume: String)] = [
        ("agy", .antigravity, [], "--conversation"),
        ("Claude", .claude, ["-w"], "--resume"),
        ("Ollama", .ollama, ["-w"], "--resume"),
    ]

    /// `arguments` with one run of `flags` taken out, or nil if it is not there.
    private static func removing(_ flags: [String], from arguments: [String]) -> [String]? {
        guard !flags.isEmpty else { return arguments }
        guard arguments.count >= flags.count else { return nil }
        for start in 0...(arguments.count - flags.count)
        where Array(arguments[start..<(start + flags.count)]) == flags {
            return Array(arguments[..<start]) + Array(arguments[(start + flags.count)...])
        }
        return nil
    }

    func testWorktreeModeAddsOnlyItsOwnFlag() throws {
        for row in Self.extras {
            for mode in NexusAgentApprovalMode.allCases {
                let cell = "\(row.route), \(mode.rawValue)"
                let plain = try XCTUnwrap(arguments(provider: row.provider, approval: mode, planMode: false))
                let inWorktree = try XCTUnwrap(arguments(provider: row.provider, approval: mode, planMode: false,
                                                         worktree: true))
                XCTAssertEqual(Self.removing(row.worktree, from: inWorktree), plain, cell)
                XCTAssertEqual(Self.permissionArguments(in: inWorktree), Self.permissionArguments(in: plain), cell)
                XCTAssertEqual(Self.skipsPermissionPrompts(inWorktree), mode == .yolo, cell)
            }
        }
    }

    func testAResumedConversationAddsOnlyItsOwnFlag() throws {
        let id = "11111111-2222-3333-4444-555555555555"
        for row in Self.extras {
            for mode in NexusAgentApprovalMode.allCases {
                let cell = "\(row.route), \(mode.rawValue)"
                let plain = try XCTUnwrap(arguments(provider: row.provider, approval: mode, planMode: false))
                let resumed = try XCTUnwrap(arguments(provider: row.provider, approval: mode, planMode: false,
                                                      resuming: id))
                XCTAssertEqual(Self.removing([row.resume, id], from: resumed), plain, cell)
                XCTAssertEqual(Self.permissionArguments(in: resumed), Self.permissionArguments(in: plain), cell)
                XCTAssertEqual(Self.skipsPermissionPrompts(resumed), mode == .yolo, cell)
            }
        }
    }

    /// Where the flags sit, for the two shapes that differ: Ollama's go
    /// after the `--`, to the Claude it launches, not to Ollama itself.
    func testOllamasPermissionArgumentsGoToTheClaudeItLaunches() throws {
        let started = try XCTUnwrap(arguments(provider: .ollama, approval: .acceptEdits, planMode: false))
        let split = try XCTUnwrap(started.firstIndex(of: "--"))
        XCTAssertEqual(Array(started[..<split]), ["launch", "claude", "--model", "m1"])
        XCTAssertEqual(Self.permissionArguments(in: Array(started[..<split])), [])
        XCTAssertEqual(Self.permissionArguments(in: Array(started[split...])), ["--permission-mode", "acceptEdits"])
    }

    /// A built-in provider's template is not what is run, so the skip flag
    /// in Antigravity's shipped template never reaches agy by that road.
    func testTheSkipFlagInAntigravitysTemplateIsNotPassedOutsideYolo() throws {
        XCTAssertTrue(NexusAgentCLIProvider.antigravity.commandTemplate.contains("--dangerously-skip-permissions"),
                      "the shipped template names the flag, which is why this is worth checking")
        for mode in [NexusAgentApprovalMode.acceptEdits, .plan, .standard] {
            let started = try XCTUnwrap(arguments(provider: .antigravity, approval: mode, planMode: false))
            XCTAssertFalse(started.contains("--dangerously-skip-permissions"), mode.rawValue)
        }
    }

    /// An own command that starts with `claude` or `ollama` is run as that
    /// provider, so its template's flags are dropped and the approval mode
    /// decides, as for the built-in one.
    func testAnOwnCommandRunAsClaudeFollowsTheApprovalMode() throws {
        let own = Self.own("claude --dangerously-skip-permissions -p {prompt}")
        XCTAssertEqual(own.route, .claude)
        let asked = try XCTUnwrap(arguments(provider: own, approval: .standard, planMode: false))
        XCTAssertEqual(Self.permissionArguments(in: asked), ["--permission-mode", "default"])
        XCTAssertFalse(Self.skipsPermissionPrompts(asked))
        let yolo = try XCTUnwrap(arguments(provider: own, approval: .yolo, planMode: false))
        XCTAssertTrue(Self.skipsPermissionPrompts(yolo))
    }

    /// What an own command's template says is passed as written, in every
    /// mode: the approval mode in Settings does not reach it. Written down
    /// here so a change to that is a decision, not an accident. Plan mode
    /// reaches it only as words in front of the prompt.
    func testAnOwnCommandsOwnFlagsArePassedAsWrittenInEveryMode() throws {
        let own = Self.own("llm --dangerously-skip-permissions \"{prompt}\"")
        XCTAssertEqual(own.route, .custom)
        for mode in NexusAgentApprovalMode.allCases {
            let started = try XCTUnwrap(arguments(provider: own, approval: mode, planMode: false))
            XCTAssertEqual(started, ["--dangerously-skip-permissions", Self.prompt], mode.rawValue)
            let planned = try XCTUnwrap(arguments(provider: own, approval: mode, planMode: true))
            XCTAssertEqual(planned, ["--dangerously-skip-permissions", NexusAgentSupport.planModePrompt(Self.prompt)],
                           mode.rawValue)
        }
    }

    /// The collector is only worth something if it sees what it should.
    func testTheCollectorSeesEverySpelling() {
        XCTAssertEqual(Self.permissionArguments(in: ["-p", "--mode", "plan", "--model", "m", "--yolo", "--trust-all"]),
                       ["--mode", "plan", "--yolo", "--trust-all"])
        XCTAssertTrue(Self.skipsPermissionPrompts(["--yolo"]))
        XCTAssertTrue(Self.skipsPermissionPrompts(["--permission-mode", "bypassPermissions"]))
        XCTAssertTrue(Self.skipsPermissionPrompts(["--dangerously-skip-permissions"]))
        XCTAssertFalse(Self.skipsPermissionPrompts(["--permission-mode", "acceptEdits", "-p", "please bypass it"]))
    }
}
