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

// Scheduled runs with no window: the flag a LaunchAgent starts the app with,
// the runner it leads to, and the rules that runner keeps. Everything here is
// a double: connections are fakes, "git" is a recorder that makes folders,
// notifications go to a list. No process is started, except one test that
// starts `/bin/sh` and `sleep` to prove that a time limit ends a whole
// process group, and no notification is posted.

import Darwin
import Foundation
@testable import VitruvianCodeCore
import XCTest

// MARK: - Doubles

/// A connection that does what the test scripts and records everything the
/// runner asked of it.
@MainActor
private final class RunFakeConnection: AgentConnection {
    let capabilities = AgentCapabilities()
    let events: AsyncStream<AgentEvent>
    private let continuation: AsyncStream<AgentEvent>.Continuation
    let spec: AgentConnectionSpec
    var startError: Error?
    var onPrompt: (RunFakeConnection) async throws -> AgentStopReason
    var onStop: (() async -> Void)?
    private(set) var started: [AgentSessionRequest] = []
    private(set) var prompts: [[PromptBlock]] = []
    private(set) var answers: [(requestID: String, answer: AgentAnswer)] = []
    private(set) var cancels = 0
    private(set) var stops = 0
    private(set) var stopped = false
    /// What a hanging prompt waits on.
    private var hold: CheckedContinuation<Void, Never>?
    /// The order things happened in, by name.
    private(set) var timeline: [String] = []

    init(spec: AgentConnectionSpec, onPrompt: @escaping (RunFakeConnection) async throws -> AgentStopReason) {
        self.spec = spec
        self.onPrompt = onPrompt
        var made: AsyncStream<AgentEvent>.Continuation!
        events = AsyncStream { made = $0 }
        continuation = made
    }

    func emit(_ event: AgentEvent) { continuation.yield(event) }

    /// Does not return until `stop()` is called, as a prompt on a stuck agent does.
    func hang() async throws -> AgentStopReason {
        if !stopped { await withCheckedContinuation { hold = $0 } }
        throw CancellationError()
    }

    func start(_ request: AgentSessionRequest) async throws -> String {
        started.append(request)
        timeline.append("start")
        if let startError { throw startError }
        return "session-1"
    }

    func prompt(_ blocks: [PromptBlock]) async throws -> AgentStopReason {
        prompts.append(blocks)
        timeline.append("prompt")
        return try await onPrompt(self)
    }

    func cancel() async {
        cancels += 1
        timeline.append("cancel")
    }

    func answer(_ requestID: String, _ choice: AgentAnswer) async throws {
        answers.append((requestID, choice))
        timeline.append("answer")
    }

    func setConfigOption(_ id: String, _ value: AgentConfigValue) async throws -> [AgentConfigOption] { [] }

    func stop() async {
        stops += 1
        stopped = true
        timeline.append("stop")
        hold?.resume()
        hold = nil
        continuation.finish()
        await onStop?()
    }
}

/// "git", as the worktree code runs it: it makes and removes the folders a
/// real `git worktree` would, and says what the test told it to.
private final class FakeGit: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [[String]] = []
    var failWorktreeAdd = false
    var worktreeHasChanges = false
    var calls: [[String]] { lock.withLock { recorded } }

    func run(_ name: String, _ arguments: [String]) -> String? {
        lock.withLock { recorded.append([name] + arguments) }
        guard name == "git" else { return "" }
        var args = arguments
        var directory = ""
        if args.first == "-C", args.count > 2 {
            directory = args[1]
            args.removeFirst(2)
        }
        let inWorktree = directory.contains("-worktrees/")
        switch args.first {
        case "rev-parse":
            return "abc123\n"
        case "status":
            return inWorktree && worktreeHasChanges ? " M changed.txt\n" : ""
        case "worktree" where args.count > 1 && args[1] == "add":
            if failWorktreeAdd { return nil }
            try? FileManager.default.createDirectory(atPath: args[4], withIntermediateDirectories: true)
            return ""
        case "worktree" where args.count > 1 && args[1] == "remove":
            try? FileManager.default.removeItem(atPath: args.last ?? "")
            return ""
        default:
            return ""
        }
    }

    func ran(_ words: [String]) -> Bool {
        calls.contains { call in
            var rest = Array(call.dropFirst())
            if rest.first == "-C", rest.count > 2 { rest.removeFirst(2) }
            return Array(rest.prefix(words.count)) == words
        }
    }
}

@MainActor
private final class RecordingNotifier: VitruvianCodeUnattendedNotifier {
    private(set) var posted: [(title: String, body: String)] = []
    func notify(title: String, body: String) async { posted.append((title, body)) }
}

/// Everything one test needs: a repository in a temporary folder, a state
/// folder, and the doubles.
@MainActor
private final class World {
    let root: URL
    let stateDirectory: String
    let repository: String
    let plainFolder: String
    let manager: VitruvianCodeAutomationManager
    let git = FakeGit()
    let notifier = RecordingNotifier()
    private(set) var logs: [String] = []
    private(set) var connections: [RunFakeConnection] = []
    var provider = VitruvianCodeCLIProvider.antigravity
    var providerKnown = true
    var startFails = false
    var script: (RunFakeConnection) async throws -> AgentStopReason = { _ in .endTurn }
    var onStop: (() async -> Void)?
    var clock = Date(timeIntervalSince1970: 1_800_000_000)
    static let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    init() {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("unattended-\(UUID().uuidString)")
        stateDirectory = root.appendingPathComponent("state").path
        repository = root.appendingPathComponent("repo").path
        plainFolder = root.appendingPathComponent("plain").path
        let fileManager = FileManager.default
        try? fileManager.createDirectory(atPath: repository + "/.git", withIntermediateDirectories: true)
        try? "base\n".write(toFile: repository + "/README.md", atomically: true, encoding: .utf8)
        try? fileManager.createDirectory(atPath: plainFolder, withIntermediateDirectories: true)
        manager = VitruvianCodeAutomationManager(stateDirectory: URL(fileURLWithPath: stateDirectory),
                                              calendar: Self.utc)
    }

    func cleanUp() { try? FileManager.default.removeItem(at: root) }

    @discardableResult
    func addTask(name: String = "Nightly check", prompt: String = "check things", folder: String? = nil,
                 enabled: Bool = true, liveRunsEnabled: Bool = true,
                 schedule: VitruvianCodeAutomationSchedule = .intervalMinutes(60),
                 lastRunAt: Date? = nil) -> VitruvianCodeScheduledTask {
        let task = VitruvianCodeScheduledTask(
            name: name, prompt: prompt, workingDirectory: folder ?? repository, providerID: provider.id,
            schedule: schedule, isEnabled: enabled, lastRunAt: lastRunAt, liveRunsEnabled: liveRunsEnabled)
        manager.upsert(task)
        return task
    }

    func runner(mode: VitruvianCodeApprovalMode = .standard, planSwitch: Bool = false,
                timeLimit: TimeInterval = 5, program: String? = "/usr/local/bin/agy") -> VitruvianCodeAutomationRunner {
        var configuration = VitruvianCodeConfiguration(approvalMode: mode)
        configuration.workingDirectory = repository
        return VitruvianCodeAutomationRunner(
            automations: manager,
            providerByID: { [unowned self] _ in providerKnown ? provider : nil },
            configuration: configuration,
            planSwitch: planSwitch,
            agentPath: { _ in program },
            makeConnection: { [unowned self] spec in
                let connection = RunFakeConnection(spec: spec, onPrompt: script)
                connection.onStop = onStop
                if startFails { connection.startError = CocoaError(.fileReadUnknown) }
                connections.append(connection)
                return connection
            },
            runGit: { [git] name, arguments in git.run(name, arguments) },
            stateDirectory: stateDirectory,
            notifier: notifier,
            timeLimit: timeLimit,
            now: { [unowned self] in clock },
            log: { [unowned self] in logs.append($0) })
    }

    /// The task as the saved file now holds it.
    func saved(_ id: UUID) -> VitruvianCodeScheduledTask? {
        manager.load()
        return manager.tasks.first { $0.id == id }
    }

    func repositoryFiles() -> [String] {
        ((try? FileManager.default.subpathsOfDirectory(atPath: repository)) ?? []).sorted()
    }

    /// Waits for `condition`, for as long as `seconds`.
    func wait(_ seconds: TimeInterval = 3, until condition: () -> Bool) async {
        let deadline = Date().addingTimeInterval(seconds)
        while !condition(), Date() < deadline { try? await Task.sleep(nanoseconds: 5_000_000) }
    }
}

// MARK: - Tests

@MainActor
final class UnattendedRunTests: XCTestCase {
    private var world: World!

    override func setUp() async throws {
        world = World()
    }

    override func tearDown() async throws {
        world.cleanUp()
        world = nil
    }

    // MARK: The flag

    func testTheFlagIsReadInBothSpellings() {
        let id = UUID()
        XCTAssertNil(VitruvianCodeAutomationLaunch.parse(arguments: ["/app/VitruvianCode"]))
        XCTAssertNil(VitruvianCodeAutomationLaunch.parse(arguments: []))
        XCTAssertEqual(VitruvianCodeAutomationLaunch.parse(arguments: ["/app", "--run-automation", id.uuidString]), .run(id))
        XCTAssertEqual(VitruvianCodeAutomationLaunch.parse(arguments: ["/app", "--run-automation=\(id.uuidString)"]), .run(id))
        XCTAssertEqual(VitruvianCodeAutomationLaunch.parse(arguments: ["/app", "--state-dir", "/x", "--run-automation", id.uuidString]), .run(id))
    }

    func testAFlagWithNoUsableIDIsInvalidAndNeverEchoesTheValue() {
        for arguments in [["/app", "--run-automation"], ["/app", "--run-automation", "not-an-id-SECRETVALUE"],
                          ["/app", "--run-automation="]] {
            guard case .invalid(let reason)? = VitruvianCodeAutomationLaunch.parse(arguments: arguments) else {
                return XCTFail("expected invalid for \(arguments)")
            }
            XCTAssertFalse(reason.contains("SECRETVALUE"))
        }
    }

    func testTheLaunchAgentRunsTheFlagTheAppHandles() {
        let task = VitruvianCodeScheduledTask(name: "n", prompt: "p", workingDirectory: "/tmp", providerID: UUID(),
                                           schedule: .hourly)
        let plist = VitruvianCodeAutomationManager.plistXML(for: task, executablePath: "/Apps/V.app/Contents/MacOS/VitruvianCode")
        XCTAssertTrue(plist.contains(VitruvianCodeAutomationLaunch.flag))
        XCTAssertEqual(VitruvianCodeAutomationLaunch.parse(arguments: ["/x", VitruvianCodeAutomationLaunch.flag, task.id.uuidString]), .run(task.id))
    }

    // MARK: Old data, and who may run

    func testOldSavedDataDecodesWithLiveRunsOff() throws {
        let task = VitruvianCodeScheduledTask(name: "n", prompt: "p", workingDirectory: "/tmp", providerID: UUID(),
                                           schedule: .hourly)
        XCTAssertTrue(task.liveRunsEnabled, "a task made now may run")
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(task)) as? [String: Any])
        XCTAssertNotNil(object.removeValue(forKey: "liveRunsEnabled"), "the key is written")
        let old = try JSONDecoder().decode(VitruvianCodeScheduledTask.self,
                                           from: JSONSerialization.data(withJSONObject: object))
        XCTAssertFalse(old.liveRunsEnabled)
        XCTAssertTrue(old.isEnabled)
        XCTAssertEqual(old.id, task.id)
        let again = try JSONDecoder().decode(VitruvianCodeScheduledTask.self, from: JSONEncoder().encode(task))
        XCTAssertEqual(again, task)
    }

    func testSwitchingATaskOnAllowsItToRunAndSwitchingItOffDoesNot() throws {
        let task = world.addTask(liveRunsEnabled: false)
        world.manager.setEnabled(false, id: task.id)
        XCTAssertFalse(world.saved(task.id)?.liveRunsEnabled ?? true, "off does not turn it on")
        world.manager.setEnabled(true, id: task.id)
        XCTAssertEqual(world.saved(task.id)?.liveRunsEnabled, true)
    }

    func testAMissingTaskDoesNothing() async {
        let outcome = await world.runner().run(taskID: UUID())
        XCTAssertEqual(outcome, .skipped(.taskNotFound))
        XCTAssertEqual(outcome.exitCode, 0, "a skip is a clean exit")
        XCTAssertTrue(world.connections.isEmpty)
        XCTAssertFalse(world.logs.isEmpty, "it says why")
    }

    func testADisabledTaskDoesNothing() async {
        let task = world.addTask(enabled: false)
        let outcome = await world.runner().run(taskID: task.id)
        XCTAssertEqual(outcome, .skipped(.disabled))
        XCTAssertTrue(world.connections.isEmpty)
        XCTAssertNil(world.saved(task.id)?.lastRunAt)
    }

    func testAnOldTaskThatWasNeverSwitchedOnDoesNothing() async {
        let task = world.addTask(liveRunsEnabled: false)
        let outcome = await world.runner().run(taskID: task.id)
        XCTAssertEqual(outcome, .skipped(.needsReEnable))
        XCTAssertTrue(world.connections.isEmpty, "no agent is started for a dormant schedule")
        XCTAssertTrue(world.git.calls.isEmpty, "and no worktree is made")
        XCTAssertNil(world.saved(task.id)?.lastRunAt, "and nothing is recorded")
        XCTAssertTrue(world.logs.contains { $0.contains("needsReEnable") }, "the log says it needs re-enabling")
    }

    func testAnEnabledTaskRuns() async {
        let task = world.addTask()
        let outcome = await world.runner().run(taskID: task.id)
        XCTAssertEqual(outcome, .succeeded)
        XCTAssertEqual(world.connections.count, 1)
    }

    func testATaskThatIsNotDueDoesNotRun() async {
        let task = world.addTask(schedule: .intervalMinutes(60), lastRunAt: world.clock.addingTimeInterval(-600))
        let outcome = await world.runner().run(taskID: task.id)
        XCTAssertEqual(outcome, .skipped(.notDue))
        XCTAssertTrue(world.connections.isEmpty)
    }

    func testDueIsExactForCronAndForgivesAnIntervalTimerThirtySeconds() {
        let runner = world.runner()
        let early = world.addTask(schedule: .intervalMinutes(60), lastRunAt: world.clock.addingTimeInterval(-3600 + 20))
        XCTAssertTrue(runner.isDue(early), "an interval timer may fire a little early")
        let tooEarly = world.addTask(schedule: .intervalMinutes(60), lastRunAt: world.clock.addingTimeInterval(-3600 + 120))
        XCTAssertFalse(runner.isDue(tooEarly))
        let utc = World.utc
        let noon = utc.date(from: DateComponents(year: 2027, month: 1, day: 15, hour: 12))!
        world.clock = noon
        let ran = world.addTask(schedule: .daily, lastRunAt: utc.date(from: DateComponents(year: 2027, month: 1, day: 15, hour: 0, second: 5)))
        XCTAssertFalse(runner.isDue(ran), "today's midnight run happened")
        let missed = world.addTask(schedule: .daily, lastRunAt: utc.date(from: DateComponents(year: 2027, month: 1, day: 14, hour: 0, second: 5)))
        XCTAssertTrue(runner.isDue(missed))
    }

    // MARK: The worktree

    func testARunHappensInANewWorktreeAndTheBaseRepositoryIsUntouched() async throws {
        let before = world.repositoryFiles()
        world.script = { connection in
            // The agent writes where it was started.
            let directory = connection.spec.workingDirectory
            try "from the agent\n".write(toFile: directory + "/agent.txt", atomically: true, encoding: .utf8)
            return .endTurn
        }
        world.git.worktreeHasChanges = true
        let task = world.addTask()
        let outcome = await world.runner().run(taskID: task.id)
        XCTAssertEqual(outcome, .succeeded)
        let connection = try XCTUnwrap(world.connections.first)
        let directory = connection.spec.workingDirectory
        XCTAssertNotEqual(directory, world.repository)
        XCTAssertTrue(directory.hasPrefix(world.repository + "-worktrees/"), directory)
        XCTAssertEqual(connection.started.first?.workingDirectory, directory)
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory + "/agent.txt"))
        XCTAssertEqual(world.repositoryFiles(), before, "the base repository has nothing new in it")
        XCTAssertEqual(try String(contentsOfFile: world.repository + "/README.md", encoding: .utf8), "base\n")
        XCTAssertTrue(world.git.ran(["worktree", "add"]))
        XCTAssertFalse(world.git.ran(["worktree", "remove"]), "a worktree with changes is kept")
        XCTAssertEqual(connection.spec.turnModes.worktree, false, "the app made the worktree: no -w on top")
    }

    func testAWorktreeNothingChangedInIsRemovedAgain() async {
        let task = world.addTask()
        let outcome = await world.runner().run(taskID: task.id)
        XCTAssertEqual(outcome, .succeeded)
        XCTAssertTrue(world.git.ran(["worktree", "remove"]))
        XCTAssertTrue(world.git.ran(["branch", "-D"]))
    }

    func testAFailedWorktreeFailsTheRunAndNeverRunsInTheBaseRepository() async {
        world.git.failWorktreeAdd = true
        let task = world.addTask()
        let outcome = await world.runner().run(taskID: task.id)
        XCTAssertEqual(outcome, .failed(.worktreeFailed))
        XCTAssertEqual(outcome.exitCode, 1)
        XCTAssertTrue(world.connections.isEmpty, "no connection was made, so nothing ran in the base repository")
        XCTAssertEqual(world.saved(task.id)?.lastRunSucceeded, false)
    }

    func testAFolderThatIsNotARepositoryIsRunInDirectly() async throws {
        let task = world.addTask(folder: world.plainFolder)
        let outcome = await world.runner().run(taskID: task.id)
        XCTAssertEqual(outcome, .succeeded)
        XCTAssertEqual(try XCTUnwrap(world.connections.first).spec.workingDirectory, world.plainFolder)
        XCTAssertFalse(world.git.ran(["worktree", "add"]))
    }

    // MARK: Recording

    func testEveryRunThatStartedIsRecordedWithItsResult() async throws {
        // Success.
        let ok = world.addTask(name: "ok")
        _ = await world.runner().run(taskID: ok.id)
        XCTAssertEqual(world.saved(ok.id)?.lastRunSucceeded, true)
        XCTAssertEqual(world.saved(ok.id)?.lastRunAt, world.clock)

        // Each way to fail.
        let failures: [(String, VitruvianCodeAutomationRunner.FailureReason, (World) -> Void)] = [
            ("worktree", .worktreeFailed, { $0.git.failWorktreeAdd = true }),
            ("start", .startFailed, { $0.startFails = true }),
            ("error", .agentError, { $0.script = { _ in .error } }),
            ("early", .endedEarly, { $0.script = { _ in .maxTokens } }),
            ("threw", .agentError, { $0.script = { _ in throw CocoaError(.fileReadUnknown) } }),
            ("provider", .providerMissing, { $0.providerKnown = false }),
        ]
        for (name, reason, arrange) in failures {
            let fresh = World()
            defer { fresh.cleanUp() }
            arrange(fresh)
            let task = fresh.addTask(name: name)
            let outcome = await fresh.runner().run(taskID: task.id)
            XCTAssertEqual(outcome, .failed(reason), name)
            XCTAssertEqual(fresh.saved(task.id)?.lastRunSucceeded, false, "\(name) is recorded as failed")
            XCTAssertEqual(fresh.saved(task.id)?.lastRunAt, fresh.clock, "\(name) is recorded with its time")
        }
    }

    // MARK: Overlap

    func testALockHeldElsewherePreventsARun() async {
        let task = world.addTask()
        let other = VitruvianCodeRunLock(path: VitruvianCodeRunLock.path(stateDirectory: world.stateDirectory, taskID: task.id))
        XCTAssertTrue(other.tryAcquire())
        let outcome = await world.runner().run(taskID: task.id)
        XCTAssertEqual(outcome, .skipped(.alreadyRunning))
        XCTAssertTrue(world.connections.isEmpty)
        XCTAssertNil(world.saved(task.id)?.lastRunAt, "the run that holds the lock records, not this one")
        other.release()
        let after = await world.runner().run(taskID: task.id)
        XCTAssertEqual(after, .succeeded, "the lock is let go")
    }

    func testTwoFiringsDoNotOverlap() async {
        let task = world.addTask(folder: world.plainFolder)
        let gate = Gate()
        world.script = { _ in
            await gate.wait()
            return .endTurn
        }
        let first = Task { @MainActor in await self.world.runner().run(taskID: task.id) }
        await world.wait { self.world.connections.count == 1 }
        XCTAssertEqual(world.connections.count, 1)
        let second = await world.runner().run(taskID: task.id)
        XCTAssertEqual(second, .skipped(.alreadyRunning))
        XCTAssertEqual(world.connections.count, 1, "the second firing started no agent")
        gate.open()
        let firstOutcome = await first.value
        XCTAssertEqual(firstOutcome, .succeeded)
    }

    func testALockIsReleasedWhenTheProcessThatHeldItEnds() {
        let path = VitruvianCodeRunLock.path(stateDirectory: world.stateDirectory, taskID: UUID())
        var lock: VitruvianCodeRunLock? = VitruvianCodeRunLock(path: path)
        XCTAssertTrue(lock?.tryAcquire() ?? false)
        XCTAssertFalse(VitruvianCodeRunLock(path: path).tryAcquire())
        lock = nil
        XCTAssertTrue(VitruvianCodeRunLock(path: path).tryAcquire(), "a dropped lock is free")
    }

    // MARK: The time limit

    func testTheTimeLimitStopsTheProcessGroup() async throws {
        let process = try AgentProcess(AgentProcessLaunchSpec(executable: "/bin/sh",
                                                              arguments: ["-c", "sleep 60 & echo $!; wait"]))
        let group = process.processGroupID
        defer { _ = Darwin.kill(-group, SIGKILL) }
        world.onStop = { await process.terminate(grace: 0.1) }
        world.script = { connection in
            XCTAssertTrue(AgentProcess.processGroupExists(group), "the agent's group is running while the prompt hangs")
            return try await connection.hang()
        }
        let task = world.addTask()
        let outcome = await world.runner(timeLimit: 0.3).run(taskID: task.id)
        XCTAssertEqual(outcome, .failed(.timeLimit))
        let connection = try XCTUnwrap(world.connections.first)
        XCTAssertEqual(connection.stops, 1)
        XCTAssertFalse(AgentProcess.processGroupExists(group), "the whole group is gone")
        XCTAssertEqual(world.saved(task.id)?.lastRunSucceeded, false)
    }

    func testAnAbortStopsTheConnectionAndFailsTheRun() async throws {
        world.script = { connection in try await connection.hang() }
        let task = world.addTask()
        let runner = world.runner(timeLimit: 30)
        let run = Task { @MainActor in await runner.run(taskID: task.id) }
        await world.wait { self.world.connections.first?.timeline.contains("prompt") == true }
        runner.abort()
        let outcome = await run.value
        XCTAssertEqual(outcome, .failed(.aborted))
        XCTAssertEqual(try XCTUnwrap(world.connections.first).stops, 1)
    }

    // MARK: Approvals

    private func pendingApproval(requestID: String? = "req-1") -> VitruvianCodeApprovalRequest {
        VitruvianCodeApprovalRequest(
            toolName: "Bash", commandOrPath: "deploy --token sk-LEAK-COMMAND", requestID: requestID,
            options: [AgentPermissionOption(id: "allow", name: "Allow", kind: .allowOnce),
                      AgentPermissionOption(id: "reject", name: "Reject", kind: .rejectOnce)])
    }

    func testAnApprovalIsDeniedTheUserIsToldAndTheRunFails() async throws {
        world.script = { [self] connection in
            connection.emit(.approval(pendingApproval()))
            return try await connection.hang()
        }
        let task = world.addTask(name: "Nightly check")
        let outcome = await world.runner(timeLimit: 30).run(taskID: task.id)
        XCTAssertEqual(outcome, .failed(.needsApproval))
        let connection = try XCTUnwrap(world.connections.first)
        XCTAssertEqual(connection.answers.count, 1)
        XCTAssertEqual(connection.answers.first?.requestID, "req-1")
        XCTAssertEqual(connection.answers.first?.answer, .option("reject"), "denied, never allowed")
        XCTAssertEqual(world.notifier.posted.count, 1, "the user is told")
        let notice = try XCTUnwrap(world.notifier.posted.first)
        XCTAssertTrue(notice.body.contains("Nightly check"))
        XCTAssertEqual(notice.title, VitruvianCodeHostStrings().automationNeedsYouTitle)
        let timeline = connection.timeline
        XCTAssertLessThan(try XCTUnwrap(timeline.firstIndex(of: "answer")), try XCTUnwrap(timeline.firstIndex(of: "stop")),
                          "the denial is sent before the connection is stopped")
        XCTAssertEqual(connection.cancels, 1)
        XCTAssertEqual(world.saved(task.id)?.lastRunSucceeded, false)
    }

    func testAnApprovalWithNoRequestToAnswerIsNotWaitedOn() async {
        world.script = { [self] connection in
            connection.emit(.approval(pendingApproval(requestID: nil)))
            return .endTurn
        }
        let task = world.addTask()
        let outcome = await world.runner().run(taskID: task.id)
        XCTAssertEqual(outcome, .succeeded)
        XCTAssertTrue(world.notifier.posted.isEmpty)
    }

    func testAQuestionIsCancelledTheUserIsToldAndTheRunFails() async throws {
        world.script = { connection in
            connection.emit(.question(AgentQuestion(requestID: "q-1", message: "Which file? sk-LEAK-QUESTION", fields: [])))
            return try await connection.hang()
        }
        let task = world.addTask()
        let outcome = await world.runner(timeLimit: 30).run(taskID: task.id)
        XCTAssertEqual(outcome, .failed(.needsAnswer))
        let connection = try XCTUnwrap(world.connections.first)
        XCTAssertEqual(connection.answers.first?.answer, .cancelled)
        XCTAssertEqual(world.notifier.posted.count, 1)
        XCTAssertFalse(world.notifier.posted.first?.body.contains("sk-LEAK-QUESTION") ?? true)
    }

    // MARK: The saved mode

    func testTheSavedModeIsPassedAndNeverRaised() async throws {
        for mode in VitruvianCodeApprovalMode.globalChoices {
            let fresh = World()
            defer { fresh.cleanUp() }
            let task = fresh.addTask()
            _ = await fresh.runner(mode: mode).run(taskID: task.id)
            let connection = try XCTUnwrap(fresh.connections.first, "\(mode)")
            XCTAssertEqual(connection.spec.configuration.approvalMode, mode, "\(mode)")
            let live = connection.spec.liveModeProvider?()
            XCTAssertEqual(live?.mode, mode, "\(mode): the live mode answers with the saved one")
            XCTAssertEqual(live?.planSwitch, false)
            XCTAssertEqual(connection.spec.turnModes.plan, false)
        }
    }

    /// A scheduled run gets the connection a chat gets: with no choice saved, agy and
    /// registry agents run over ACP and Claude on the Agent SDK; the others, and any
    /// provider with a saved choice, keep theirs.
    func testARunUsesTheSameDefaultConnectionAsAChat() async throws {
        let registryAgent = VitruvianCodeCLIProvider(
            id: UUID(), name: "OpenCode (ACP)", commandTemplate: "", isBuiltIn: false, connection: nil,
            registryAgent: .init(agentID: "opencode", version: "2.4.2"))
        var chosen = VitruvianCodeCLIProvider.antigravity
        chosen.connection = .commandLine
        let cases: [(VitruvianCodeCLIProvider, AgentConnectionKind, String, String)] = [
            (.antigravity, .acp, "AntigravityACPConnection", "agy"),
            (.claude, .claudeSDK, "ClaudeSDKConnection", "Claude Code"),
            (.ollama, .commandLine, "CommandLineConnection", "Ollama (claude)"),
            (.opencode, .commandLine, "CommandLineConnection", "OpenCode"),
            (registryAgent, .acp, "", "a registry agent"),
            (chosen, .commandLine, "CommandLineConnection", "agy with the command line chosen"),
        ]
        // The app's own factory, which only builds the object; nothing is started.
        let realFactory = VitruvianCodeEngine.Environment.live(stateDirectoryOverride: nil).makeConnection
        for (provider, expected, realType, name) in cases {
            let fresh = World()
            defer { fresh.cleanUp() }
            fresh.provider = provider
            let task = fresh.addTask()
            _ = await fresh.runner(mode: .yolo).run(taskID: task.id)
            let connection = try XCTUnwrap(fresh.connections.first, name)
            XCTAssertEqual(connection.spec.kind, expected, name)
            XCTAssertEqual(connection.spec.provider.connection, expected,
                           "\(name): the app's connection factory reads the provider's own connection")
            let built = String(describing: type(of: realFactory(connection.spec)))
            if realType.isEmpty {
                XCTAssertNotEqual(built, "CommandLineConnection", name)
            } else {
                XCTAssertEqual(built, realType, name)
            }
        }
    }

    func testAPlanSwitchOnlyLowersTheModeAndTheTaskModelDoesNotChangeIt() async throws {
        let task = world.addTask()
        var changed = task
        changed.model = "some-model"
        world.manager.upsert(changed)
        _ = await world.runner(mode: .yolo, planSwitch: true).run(taskID: task.id)
        let connection = try XCTUnwrap(world.connections.first)
        XCTAssertEqual(connection.spec.configuration.approvalMode, .plan)
        XCTAssertEqual(connection.spec.liveModeProvider?().planSwitch, true)
        XCTAssertEqual(connection.spec.configuration.model, "some-model")
    }

    func testWithNothingSavedTheModeIsApprovalRequired() {
        let rig = ComposerRig()
        var environment = rig.environment
        environment.readFile = { _ in nil }
        let engine = VitruvianCodeEngine(environment: environment, host: ComposerQuietHost())
        XCTAssertEqual(engine.savedConfigurationForUnattendedRun().approvalMode, .standard)

        environment.readFile = { path in path.hasSuffix(".env") ? "AGY_APPROVAL_MODE=accept-edits\n" : nil }
        let saved = VitruvianCodeEngine(environment: environment, host: ComposerQuietHost())
        XCTAssertEqual(saved.savedConfigurationForUnattendedRun().approvalMode, .acceptEdits)

        environment.readFile = { path in path.hasSuffix(".env") ? "AGY_APPROVAL_MODE=yolo\n" : nil }
        let full = VitruvianCodeEngine(environment: environment, host: ComposerQuietHost())
        XCTAssertEqual(full.savedConfigurationForUnattendedRun().approvalMode, .yolo, "what the user saved is what runs")
    }

    // MARK: Secrets

    func testNeitherTheLogNorANotificationHoldsThePromptOrAnySecret() async {
        let secretPrompt = "SECRET-PROMPT sk-PROMPT-KEY"
        let scenarios: [(String, (RunFakeConnection) async throws -> AgentStopReason)] = [
            ("success", { connection in
                connection.emit(.text("sk-LEAK-OUTPUT"))
                connection.emit(.finished(status: "ok", response: "sk-LEAK-OUTPUT", error: nil, conversationID: nil))
                return .endTurn
            }),
            ("agent error", { connection in
                connection.emit(.finished(status: "error", response: nil, error: "bad key sk-LEAK-ERROR", conversationID: nil))
                return .error
            }),
            ("connection failed", { connection in
                connection.emit(.connectionFailed(AgentFailure(kind: .exited, message: "sk-LEAK-FAILURE", detail: "sk-LEAK-DETAIL")))
                return .error
            }),
            ("approval", { [self] connection in
                connection.emit(.approval(pendingApproval()))
                return try await connection.hang()
            }),
        ]
        for (name, script) in scenarios {
            let fresh = World()
            defer { fresh.cleanUp() }
            fresh.script = script
            let task = fresh.addTask(name: "Nightly check", prompt: secretPrompt)
            _ = await fresh.runner(timeLimit: 30).run(taskID: task.id)
            let everything = (fresh.logs + fresh.notifier.posted.flatMap { [$0.title, $0.body] }).joined(separator: "\n")
            XCTAssertFalse(everything.isEmpty, name)
            for secret in ["SECRET-PROMPT", "sk-PROMPT-KEY", "sk-LEAK", "deploy", "--token"] {
                XCTAssertFalse(everything.contains(secret), "\(name): \(secret) leaked: \(everything)")
            }
        }
    }

    func testALongOrMultilineNameIsCutToOneShortLine() {
        let name = "line one\nline two " + String(repeating: "x", count: 200)
        let short = VitruvianCodeAutomationRunner.shortName(name)
        XCTAssertFalse(short.contains("\n"))
        XCTAssertLessThanOrEqual(short.count, 80)
    }

    func testThePromptIsSentOnceAsTheOnlyBlock() async throws {
        let task = world.addTask(prompt: "check things")
        _ = await world.runner().run(taskID: task.id)
        let connection = try XCTUnwrap(world.connections.first)
        XCTAssertEqual(connection.prompts, [[.text("check things")]])
        XCTAssertNil(connection.started.first?.resumeSessionID, "a fresh session each firing")
        XCTAssertEqual(connection.stops, 1, "the connection is stopped when the run ends")
    }
}

/// A door a test holds shut until it opens it.
@MainActor
private final class Gate {
    private var isOpen = false
    private var waiter: CheckedContinuation<Void, Never>?

    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { waiter = $0 }
    }

    func open() {
        isOpen = true
        waiter?.resume()
        waiter = nil
    }
}
