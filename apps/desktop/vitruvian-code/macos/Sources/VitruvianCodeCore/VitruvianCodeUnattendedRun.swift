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
//
// Shared by the standalone Vitruvian Code app and the Code feature of the
// Vitruvian desktop app. Written for the shared library.

import Darwin
import Foundation

// MARK: - The launch argument

/// What `--run-automation <id>` on the command line asks for. A LaunchAgent
/// that `VitruvianCodeAutomationManager.plistXML` wrote starts the app with it,
/// so that a schedule runs with the app closed.
public enum VitruvianCodeAutomationLaunch: Equatable, Sendable {
    /// Run this task and exit, with no window.
    case run(UUID)
    /// The flag is there and means nothing. The text is fixed words and never
    /// the value, which could be anything.
    case invalid(String)

    public static let flag = "--run-automation"

    /// Nil when the flag is absent.
    public static func parse(arguments: [String]) -> VitruvianCodeAutomationLaunch? {
        let needsID = VitruvianCodeAutomationLaunch.invalid("\(flag) needs a task id")
        var index = 0
        while index < arguments.count {
            let argument = arguments[index]
            var value: String?
            if argument == flag {
                guard index + 1 < arguments.count else { return needsID }
                value = arguments[index + 1]
            } else if argument.hasPrefix(flag + "=") {
                value = String(argument.dropFirst(flag.count + 1))
            }
            if let value {
                guard let id = UUID(uuidString: value.trimmingCharacters(in: .whitespacesAndNewlines)) else {
                    return needsID
                }
                return .run(id)
            }
            index += 1
        }
        return nil
    }
}

// MARK: - The lock

/// A lock on one task, held for as long as a run of it lasts, so that two
/// firings of the same schedule never overlap. It is a `flock` on a file, so
/// it works across processes and the system drops it if the process dies:
/// a crash never leaves a task locked for good.
public final class VitruvianCodeRunLock: @unchecked Sendable {
    public let path: String
    private var descriptor: Int32 = -1

    public init(path: String) {
        self.path = path
    }

    deinit {
        release()
    }

    /// Where the lock for one task lives under the app's state folder.
    public static func path(stateDirectory: String, taskID: UUID) -> String {
        (stateDirectory as NSString).appendingPathComponent("automation-locks/\(taskID.uuidString.lowercased()).lock")
    }

    /// True when this lock now holds the task; false when another holds it,
    /// or the lock file cannot be made (an unknown state is not a free one).
    public func tryAcquire() -> Bool {
        guard descriptor < 0 else { return true }
        let directory = (path as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        // `O_EXLOCK | O_NONBLOCK` takes a `flock`-style lock as the file is
        // opened, and fails at once if another open file holds it.
        let fd = Darwin.open(path, O_CREAT | O_RDWR | O_EXLOCK | O_NONBLOCK, 0o600)
        guard fd >= 0 else { return false }
        descriptor = fd
        return true
    }

    public func release() {
        guard descriptor >= 0 else { return }
        Darwin.close(descriptor)
        descriptor = -1
    }
}

// MARK: - Saying so

/// How an unattended run reaches the user. The app posts a system
/// notification; tests record.
@MainActor
public protocol VitruvianCodeUnattendedNotifier: AnyObject {
    func notify(title: String, body: String) async
}

// MARK: - The runner

/// Runs one scheduled task with no window: in a worktree of its own when the
/// task's folder is a git repository, through the same `AgentConnection` a
/// chat uses, to the end of one prompt.
///
/// What it will not do, and the tests hold each one:
/// - run a task that is missing, off, or saved before live runs existed and
///   not switched on since (`liveRunsEnabled`), or one that is not due;
/// - run in the base repository when the worktree could not be made;
/// - run twice at once (`VitruvianCodeRunLock`);
/// - go on past its time limit: the connection, and with it the process
///   group, is stopped;
/// - approve anything. It uses the approval mode the app has saved, never a
///   higher one. An approval or a question that mode lets through is denied,
///   the user is told with a notification, and the run fails. A notification
///   cannot carry an answer back to a process that has no window, so the run
///   does not wait for one.
/// - put the task's prompt, the agent's words or any secret in a log line or
///   a notification. The only words of the task that appear are its name.
@MainActor
public final class VitruvianCodeAutomationRunner {
    public enum SkipReason: String, Equatable, Sendable {
        case taskNotFound
        case disabled
        /// Saved before live runs existed, and not switched on since.
        case needsReEnable
        case notDue
        case alreadyRunning
    }

    public enum FailureReason: String, Equatable, Sendable {
        case noFolder
        case providerMissing
        case programMissing
        case worktreeFailed
        case startFailed
        case agentError
        case endedEarly
        case needsApproval
        case needsAnswer
        case timeLimit
        case aborted
    }

    public enum Outcome: Equatable, Sendable {
        case skipped(SkipReason)
        case succeeded
        case failed(FailureReason)

        /// What the process exits with: a skip is a clean exit, a failure is not.
        public var exitCode: Int32 {
            if case .failed = self { return 1 }
            return 0
        }
    }

    /// How a prompt ended, or why the run ended it.
    private enum Turn: Equatable, Sendable {
        case finished(AgentStopReason)
        case startFailed
        case promptFailed
        case timedOut
        case needsApproval
        case needsAnswer
        case aborted
    }

    /// An interval task may be started a little early by the timer that fires
    /// it. A cron task may not: a minute that was early would come round again.
    public static let intervalGrace: TimeInterval = 30
    public static let defaultTimeLimit: TimeInterval = 30 * 60

    private let automations: VitruvianCodeAutomationManager
    private let worktreeManager: VitruvianCodeWorktreeManager
    private let providerByID: (UUID) -> VitruvianCodeCLIProvider?
    private let configuration: VitruvianCodeConfiguration
    private let planSwitch: Bool
    private let agentPath: (VitruvianCodeCLIProvider) -> String?
    private let makeConnection: (AgentConnectionSpec) -> any AgentConnection
    private let runGit: VitruvianCodeWorktreeManager.ProgramRunner
    private let isGitRepo: (String) -> Bool
    private let processEnvironment: [String: String]
    private let ollamaDefaultModel: String
    private let stateDirectory: String
    private let notifier: any VitruvianCodeUnattendedNotifier
    private let strings: VitruvianCodeHostStrings
    private let timeLimit: TimeInterval
    private let now: () -> Date
    private let logSink: (String) -> Void

    private var currentTurn: Latch<Turn>?
    private var aborted = false

    public init(
        automations: VitruvianCodeAutomationManager,
        worktreeManager: VitruvianCodeWorktreeManager = VitruvianCodeWorktreeManager(),
        providerByID: @escaping (UUID) -> VitruvianCodeCLIProvider?,
        configuration: VitruvianCodeConfiguration,
        planSwitch: Bool = false,
        agentPath: @escaping (VitruvianCodeCLIProvider) -> String?,
        makeConnection: @escaping (AgentConnectionSpec) -> any AgentConnection,
        runGit: @escaping VitruvianCodeWorktreeManager.ProgramRunner,
        isGitRepo: @escaping (String) -> Bool = { VitruvianCodeSupport.isGitRepo(at: URL(fileURLWithPath: $0)) },
        processEnvironment: [String: String] = [:],
        ollamaDefaultModel: String = VitruvianCodeSupport.ollamaFallbackModel,
        stateDirectory: String,
        notifier: any VitruvianCodeUnattendedNotifier,
        strings: VitruvianCodeHostStrings = VitruvianCodeHostStrings(),
        timeLimit: TimeInterval = VitruvianCodeAutomationRunner.defaultTimeLimit,
        now: @escaping () -> Date = Date.init,
        log: @escaping (String) -> Void = { _ in }
    ) {
        self.automations = automations
        self.worktreeManager = worktreeManager
        self.providerByID = providerByID
        self.configuration = configuration
        self.planSwitch = planSwitch
        self.agentPath = agentPath
        self.makeConnection = makeConnection
        self.runGit = runGit
        self.isGitRepo = isGitRepo
        self.processEnvironment = processEnvironment
        self.ollamaDefaultModel = ollamaDefaultModel
        self.stateDirectory = stateDirectory
        self.notifier = notifier
        self.strings = strings
        self.timeLimit = timeLimit
        self.now = now
        self.logSink = log
    }

    /// Ends the run in progress as failed and stops its connection. For a
    /// termination signal: the process group must not outlive the app.
    public func abort() {
        aborted = true
        currentTurn?.fulfil(.aborted)
    }

    /// Runs the task and says how it went. A task that was not run (missing,
    /// off, not switched on, not due, already running) is not recorded in the
    /// task's last-run fields; every run that was started is.
    public func run(taskID: UUID) async -> Outcome {
        guard let first = automations.tasks.first(where: { $0.id == taskID }) else {
            log("task \(taskID.uuidString.lowercased()) does not exist: nothing run")
            return .skipped(.taskNotFound)
        }
        let label = Self.label(for: first)
        if let skip = skipReason(for: first) {
            log("\(label): not run (\(skip.rawValue))\(skip == .needsReEnable ? ": turn it off and on again to let it run" : "")")
            return .skipped(skip)
        }

        let lock = VitruvianCodeRunLock(path: VitruvianCodeRunLock.path(stateDirectory: stateDirectory, taskID: taskID))
        guard lock.tryAcquire() else {
            log("\(label): not run (\(SkipReason.alreadyRunning.rawValue))")
            return .skipped(.alreadyRunning)
        }
        defer { lock.release() }

        // Another firing may have run it while this one waited: read what is
        // saved now, under the lock.
        automations.load()
        guard let task = automations.tasks.first(where: { $0.id == taskID }) else {
            log("\(label): not run (\(SkipReason.taskNotFound.rawValue))")
            return .skipped(.taskNotFound)
        }
        if let skip = skipReason(for: task) {
            log("\(label): not run (\(skip.rawValue))")
            return .skipped(skip)
        }

        let startedAt = now()
        log("\(label): started")
        let outcome = await execute(task, label: label)
        automations.load()
        automations.markExecuted(id: taskID, at: startedAt, succeeded: outcome == .succeeded)
        switch outcome {
        case .succeeded: log("\(label): succeeded")
        case .failed(let reason): log("\(label): failed (\(reason.rawValue))")
        case .skipped(let reason): log("\(label): not run (\(reason.rawValue))")
        }
        return outcome
    }

    // MARK: Whether to run

    private func skipReason(for task: VitruvianCodeScheduledTask) -> SkipReason? {
        guard task.isEnabled else { return .disabled }
        guard task.liveRunsEnabled else { return .needsReEnable }
        guard isDue(task) else { return .notDue }
        return nil
    }

    /// A LaunchAgent for an interval, or for a cron expression too wide to
    /// say in launchd's keys, fires every so often and leaves it to the app
    /// to see whether the task is due (`plistXML`).
    func isDue(_ task: VitruvianCodeScheduledTask) -> Bool {
        let current = now()
        guard let next = task.nextRunDate(now: current, calendar: automations.calendar) else { return false }
        if case .intervalMinutes = task.schedule {
            return next <= current.addingTimeInterval(Self.intervalGrace)
        }
        return next <= current
    }

    // MARK: The run

    private func execute(_ task: VitruvianCodeScheduledTask, label: String) async -> Outcome {
        guard let provider = providerByID(task.providerID) else { return .failed(.providerMissing) }
        let folder = task.workingDirectory.isEmpty ? configuration.workingDirectory : task.workingDirectory
        var isDirectory: ObjCBool = false
        guard !folder.isEmpty, FileManager.default.fileExists(atPath: folder, isDirectory: &isDirectory),
              isDirectory.boolValue else { return .failed(.noFolder) }
        guard let program = agentPath(provider) else { return .failed(.programMissing) }
        if aborted { return .failed(.aborted) }

        // In a git repository the run happens in a worktree of its own, and
        // only there. If the worktree cannot be made the run fails: the
        // agent is never started in the base repository instead.
        var runDirectory = folder
        var worktree: VitruvianCodeManagedWorktree?
        var baseHead: String?
        if isGitRepo(folder) {
            baseHead = await runGit("git", ["-C", folder, "rev-parse", "HEAD"])?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let made = await worktreeManager.createWorktree(
                taskName: Self.worktreeName(task.name, at: now()),
                baseRepositoryPath: folder,
                provider: provider,
                runGit: runGit
            )
            var isWorktreeDirectory: ObjCBool = false
            guard case .ready = made.setupStatus,
                  made.worktreePath != folder,
                  FileManager.default.fileExists(atPath: made.worktreePath, isDirectory: &isWorktreeDirectory),
                  isWorktreeDirectory.boolValue else {
                if FileManager.default.fileExists(atPath: made.worktreePath) {
                    _ = await worktreeManager.removeWorktree(id: made.id, force: true, deleteBranch: true,
                                                             runGit: runGit)
                }
                return .failed(.worktreeFailed)
            }
            worktree = made
            runDirectory = made.worktreePath
            log("\(label): working in a new worktree")
        } else {
            log("\(label): the folder is not a git repository: working in the folder")
        }

        let outcome = await converse(task, provider: provider, program: program,
                                     directory: runDirectory, label: label)

        if let worktree, let baseHead {
            await removeIfUntouched(worktree, baseHead: baseHead, label: label)
        }
        return outcome
    }

    /// Starts the connection, sends the prompt, and ends the run at the first
    /// of: the prompt finishing, the time limit, an approval or question, an
    /// abort. The connection is stopped on every path.
    private func converse(_ task: VitruvianCodeScheduledTask, provider: VitruvianCodeCLIProvider,
                          program: String, directory: String, label: String) async -> Outcome {
        // The saved mode, and no higher: a plan switch only lowers it.
        let savedMode = configuration.approvalMode
        var turnConfiguration = configuration
        if !task.model.isEmpty { turnConfiguration.model = task.model }
        if planSwitch { turnConfiguration.approvalMode = .plan }
        let plan = planSwitch
        // The same default a chat gets: agy and registry agents on ACP, Claude on the
        // Agent SDK, the rest on the command line, unless the provider saved a choice.
        // The connection factory reads the provider's own `connection`, so the provider
        // itself carries the default, as the engine does for a chat.
        let resolved = provider.withDefaultConnection
        let spec = AgentConnectionSpec(
            kind: resolved.resolvedConnection,
            provider: resolved,
            configuration: turnConfiguration,
            agentPath: program,
            workingDirectory: directory,
            ollamaDefaultModel: ollamaDefaultModel,
            turnModes: AgentTurnModes(plan: plan, worktree: false),
            environment: processEnvironment,
            liveModeProvider: { (savedMode, plan) }
        )
        let connection = makeConnection(spec)
        let latch = Latch<Turn>()
        currentTurn = latch
        if aborted { latch.fulfil(.aborted) }
        let tracker = Tracker()

        let events = connection.events
        let watcher = Task { @MainActor [weak self] in
            for await event in events {
                guard let self, !Task.isCancelled else { return }
                switch event {
                case .approval(let request):
                    // Only a request something is waiting on can be answered.
                    guard request.status == .pending, let requestID = request.requestID else { continue }
                    let denial = VitruvianCodeQuickPromptSession.approvalAnswer(for: request.options, decision: .denied)
                    try? await connection.answer(requestID, denial)
                    self.log("\(label): an approval was needed and denied")
                    await self.tellTheUser(taskName: task.name)
                    latch.fulfil(.needsApproval)
                case .question(let question):
                    try? await connection.answer(question.requestID, .cancelled)
                    self.log("\(label): an answer was needed and none was given")
                    await self.tellTheUser(taskName: task.name)
                    latch.fulfil(.needsAnswer)
                case .finished(_, _, let error, _, _):
                    if error != nil { tracker.reportedError = true }
                case .connectionFailed(let failure):
                    tracker.reportedError = true
                    self.log("\(label): the connection failed (\(failure.kind.rawValue))")
                default:
                    break
                }
            }
        }

        let request = AgentSessionRequest(workingDirectory: directory)
        let blocks: [PromptBlock] = [.text(task.prompt)]
        let work = Task { @MainActor in
            do {
                _ = try await connection.start(request)
            } catch {
                latch.fulfil(.startFailed)
                return
            }
            do {
                latch.fulfil(.finished(try await connection.prompt(blocks)))
            } catch {
                latch.fulfil(.promptFailed)
            }
        }
        let limit = timeLimit
        let timer = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(max(0, limit) * 1_000_000_000))
            if !Task.isCancelled { latch.fulfil(.timedOut) }
        }

        let turn = await latch.wait()
        timer.cancel()
        if case .finished = turn {
            // The turn is over: nothing to stop but the connection itself.
        } else {
            await connection.cancel()
        }
        // On every path, and the one place it is done: ends the process group.
        await connection.stop()
        work.cancel()
        // The events a connection sent just before its stream ended still
        // count (an error reported with the end of the turn).
        await Self.drain(watcher)
        watcher.cancel()
        currentTurn = nil
        let reportedError = tracker.reportedError

        switch turn {
        case .finished(let reason):
            if reportedError { return .failed(.agentError) }
            switch reason {
            case .endTurn: return .succeeded
            case .error: return .failed(.agentError)
            case .maxTokens, .maxTurnRequests, .refusal, .cancelled: return .failed(.endedEarly)
            }
        case .startFailed: return .failed(.startFailed)
        case .promptFailed: return .failed(.agentError)
        case .timedOut: return .failed(.timeLimit)
        case .needsApproval: return .failed(.needsApproval)
        case .needsAnswer: return .failed(.needsAnswer)
        case .aborted: return .failed(.aborted)
        }
    }

    /// Waits for the event loop to end, for no more than two seconds: it ends
    /// with the connection's stream, which `stop()` closes.
    private static func drain(_ watcher: Task<Void, Never>) async {
        let done = Latch<Bool>()
        let waiting = Task { @MainActor in
            await watcher.value
            done.fulfil(true)
        }
        let giveUp = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            done.fulfil(false)
        }
        _ = await done.wait()
        waiting.cancel()
        giveUp.cancel()
    }

    private func tellTheUser(taskName: String) async {
        let words = strings.automationNeedsYou(taskName: "\u{201C}\(Self.shortName(taskName))\u{201D}")
        await notifier.notify(title: words.title, body: words.body)
    }

    // MARK: Leftovers

    /// A worktree the agent changed nothing in is removed, with its branch,
    /// so that a schedule that finds nothing to do does not leave one more
    /// branch behind every time it fires. One with changes, or one that
    /// cannot be shown untouched, stays for the user to look at.
    private func removeIfUntouched(_ worktree: VitruvianCodeManagedWorktree, baseHead: String, label: String) async {
        guard !baseHead.isEmpty,
              let status = await runGit("git", ["-C", worktree.worktreePath, "status", "--porcelain"]),
              status.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let head = await runGit("git", ["-C", worktree.worktreePath, "rev-parse", "HEAD"]),
              head.trimmingCharacters(in: .whitespacesAndNewlines) == baseHead else {
            log("\(label): the worktree is kept")
            return
        }
        if await worktreeManager.removeWorktree(id: worktree.id, force: true, deleteBranch: true, runGit: runGit) {
            log("\(label): nothing changed, so the worktree was removed")
        }
    }

    // MARK: Words

    /// A name for the log and the notification: one line, cut short.
    static func shortName(_ name: String) -> String {
        let oneLine = name.components(separatedBy: .newlines)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
        return String(oneLine.prefix(80))
    }

    private static func label(for task: VitruvianCodeScheduledTask) -> String {
        "automation \(task.id.uuidString.lowercased()) \u{201C}\(shortName(task.name))\u{201D}"
    }

    /// Unique for each firing, so that a second run never meets the first
    /// one's branch.
    static func worktreeName(_ name: String, at date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return "auto-\(shortName(name))-\(formatter.string(from: date))"
    }

    private func log(_ message: String) {
        logSink(message)
    }
}

// MARK: - Small helpers

/// Holds a flag the event loop sets and the runner reads, both on the main actor.
@MainActor
private final class Tracker {
    var reportedError = false
}

/// A value that is set once, and that a task can wait for.
@MainActor
private final class Latch<Value: Sendable> {
    private var value: Value?
    private var waiter: CheckedContinuation<Value, Never>?

    func fulfil(_ newValue: Value) {
        guard value == nil else { return }
        value = newValue
        waiter?.resume(returning: newValue)
        waiter = nil
    }

    func wait() async -> Value {
        if let value { return value }
        return await withCheckedContinuation { waiter = $0 }
    }
}
