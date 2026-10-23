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

import Foundation
import XCTest

import NexusAgentCore

final class OrcaOrchestrationAndAutomationTests: XCTestCase {

    // MARK: - Hibernation: the eight safety checks

    /// A session that passes every check.
    private func sleepy() -> NexusAgentHibernationCandidate {
        NexusAgentHibernationCandidate(sessionID: "s-1", providerRoute: .claude, isTurnDone: true,
                                       isForeground: false, idleSeconds: 1800, hasPendingApproval: false,
                                       activeSubagentCount: 0, hasUnsettledOrchestrationDispatch: false,
                                       isDrivenByMobile: false, scrollOffsetY: 412.5)
    }

    func testASessionPassingAllEightChecksHibernates() {
        let evaluator = NexusAgentHibernationEvaluator()
        XCTAssertEqual(evaluator.idleThreshold, 1800)
        XCTAssertEqual(NexusAgentHibernationEvaluator.Check.allCases.count, 8)
        XCTAssertEqual(evaluator.failedChecks(sleepy()), [])
        XCTAssertTrue(evaluator.canHibernate(sleepy()))
    }

    func testFailingAnySingleCheckKeepsTheSessionAwake() {
        typealias Check = NexusAgentHibernationEvaluator.Check
        let breakers: [(Check, (inout NexusAgentHibernationCandidate) -> Void)] = [
            (.turnDone, { $0.isTurnDone = false }),
            (.notForeground, { $0.isForeground = true }),
            (.idleLongEnough, { $0.idleSeconds = 1799 }),
            (.providerResumes, { $0.providerRoute = .custom }),
            (.noPendingApproval, { $0.hasPendingApproval = true }),
            (.noActiveSubagents, { $0.activeSubagentCount = 1 }),
            (.noUnsettledDispatch, { $0.hasUnsettledOrchestrationDispatch = true }),
            (.notDrivenByMobile, { $0.isDrivenByMobile = true }),
        ]
        XCTAssertEqual(Set(breakers.map { $0.0 }), Set(Check.allCases), "every check is exercised")
        let evaluator = NexusAgentHibernationEvaluator()
        for (check, breakIt) in breakers {
            var candidate = sleepy()
            breakIt(&candidate)
            XCTAssertEqual(evaluator.failedChecks(candidate), [check], "\(check)")
            XCTAssertFalse(evaluator.canHibernate(candidate), "\(check)")
        }
    }

    func testEveryResumableProviderMayHibernate() {
        let evaluator = NexusAgentHibernationEvaluator()
        for route in [NexusAgentProviderRoute.claude, .ollama, .opencode, .antigravity] {
            var candidate = sleepy()
            candidate.providerRoute = route
            XCTAssertTrue(evaluator.canHibernate(candidate), "\(route)")
        }
    }

    func testTheIdleThresholdCanBeChanged() {
        var candidate = sleepy()
        candidate.idleSeconds = 300
        XCTAssertFalse(NexusAgentHibernationEvaluator().canHibernate(candidate))
        XCTAssertTrue(NexusAgentHibernationEvaluator(idleThreshold: 300).canHibernate(candidate))
    }

    @MainActor
    func testTheManagerKeepsTheScrollOffsetAndRestoresOnFocus() {
        let asleepAt = Date(timeIntervalSince1970: 1_800_000_000)
        let manager = NexusAgentHibernationManager(now: { asleepAt })
        let provider = UUID()

        var busy = sleepy()
        busy.hasPendingApproval = true
        XCTAssertNil(manager.hibernateIfEligible(busy, providerID: provider, workingDirectory: "/repo"))
        XCTAssertFalse(manager.isHibernated("s-1"))

        let record = manager.hibernateIfEligible(sleepy(), providerID: provider, workingDirectory: "/repo")
        XCTAssertEqual(record, NexusAgentHibernatedSessionRecord(sessionID: "s-1", providerID: provider,
                                                                 workingDirectory: "/repo", scrollOffsetY: 412.5,
                                                                 hibernatedAt: asleepAt))
        XCTAssertTrue(manager.isHibernated("s-1"))
        XCTAssertEqual(manager.hibernated.count, 1)

        let restored = manager.restore(sessionID: "s-1")
        XCTAssertEqual(restored?.scrollOffsetY, 412.5)
        XCTAssertFalse(manager.isHibernated("s-1"))
        XCTAssertNil(manager.restore(sessionID: "s-1"), "waking twice finds nothing")
    }

    // MARK: - Scheduled automations

    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func date(_ text: String) -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.date(from: text)!
    }

    func testPresetsFireWhenExpected() {
        // 2026-10-23 is a Friday.
        let friday = date("2026-10-23T10:15:30Z")
        XCTAssertEqual(NexusAgentAutomationSchedule.hourly.nextFireDate(after: friday, calendar: utc),
                       date("2026-10-23T11:00:00Z"))
        XCTAssertEqual(NexusAgentAutomationSchedule.daily.nextFireDate(after: friday, calendar: utc),
                       date("2026-10-24T00:00:00Z"))
        XCTAssertEqual(NexusAgentAutomationSchedule.weekdays9am.nextFireDate(after: friday, calendar: utc),
                       date("2026-10-26T09:00:00Z"), "Friday after nine skips the weekend to Monday")
        XCTAssertEqual(NexusAgentAutomationSchedule.weekdays9am.nextFireDate(after: date("2026-10-22T08:00:00Z"),
                                                                            calendar: utc),
                       date("2026-10-22T09:00:00Z"))
        XCTAssertEqual(NexusAgentAutomationSchedule.intervalMinutes(45).nextFireDate(after: friday, calendar: utc),
                       friday.addingTimeInterval(45 * 60))
        XCTAssertNil(NexusAgentAutomationSchedule.intervalMinutes(0).nextFireDate(after: friday, calendar: utc))
    }

    func testCronExpressionsFireWhenExpected() {
        let start = date("2026-10-23T10:15:00Z")
        XCTAssertEqual(NexusAgentAutomationSchedule.cron("*/20 * * * *").nextFireDate(after: start, calendar: utc),
                       date("2026-10-23T10:20:00Z"), "strictly after, never the same minute")
        XCTAssertEqual(NexusAgentAutomationSchedule.cron("30 8 1 * *").nextFireDate(after: start, calendar: utc),
                       date("2026-11-01T08:30:00Z"))
        XCTAssertEqual(NexusAgentAutomationSchedule.cron("0 12 * * 0").nextFireDate(after: start, calendar: utc),
                       date("2026-10-25T12:00:00Z"), "0 is Sunday")
        XCTAssertEqual(NexusAgentAutomationSchedule.cron("0 12 * * 7").nextFireDate(after: start, calendar: utc),
                       date("2026-10-25T12:00:00Z"), "and so is 7")
        XCTAssertEqual(NexusAgentAutomationSchedule.cron("0 0 1 1 *").nextFireDate(after: start, calendar: utc),
                       date("2027-01-01T00:00:00Z"))
        // Both day fields restricted: either matching runs (the 1st, or a Monday).
        XCTAssertEqual(NexusAgentAutomationSchedule.cron("0 6 1 * 1").nextFireDate(after: start, calendar: utc),
                       date("2026-10-26T06:00:00Z"))
        XCTAssertNil(NexusAgentAutomationSchedule.cron("0 0 30 2 *").nextFireDate(after: start, calendar: utc),
                     "February 30th never comes")
    }

    func testSchedulesParseAndRoundTripAsText() throws {
        XCTAssertEqual(NexusAgentAutomationSchedule(text: "@hourly"), .hourly)
        XCTAssertEqual(NexusAgentAutomationSchedule(text: "@daily"), .daily)
        XCTAssertEqual(NexusAgentAutomationSchedule(text: "@weekdays9am"), .weekdays9am)
        XCTAssertEqual(NexusAgentAutomationSchedule(text: "@every 15m"), .intervalMinutes(15))
        XCTAssertEqual(NexusAgentAutomationSchedule(text: "5 4 * * 1-5"), .cron("5 4 * * 1-5"))
        for bad in ["", "@sometimes", "@every 0m", "60 * * * *", "* * * *", "1-0 * * * *", "*/0 * * * *"] {
            XCTAssertNil(NexusAgentAutomationSchedule(text: bad), bad)
        }
        let all: [NexusAgentAutomationSchedule] = [.hourly, .daily, .weekdays9am, .intervalMinutes(30), .cron("0 9 * * 1")]
        let data = try JSONEncoder().encode(all)
        XCTAssertEqual(try JSONDecoder().decode([NexusAgentAutomationSchedule].self, from: data), all)
        XCTAssertEqual(String(data: try JSONEncoder().encode(NexusAgentAutomationSchedule.intervalMinutes(30)),
                              encoding: .utf8), "\"@every 30m\"")
    }

    private func temporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("orca-automation-\(UUID().uuidString)")
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    @MainActor
    func testDueTasksAndMarkExecuted() {
        let manager = NexusAgentAutomationManager(stateDirectory: temporaryDirectory(), calendar: utc)
        let provider = UUID()
        let hourly = NexusAgentScheduledTask(name: "Hourly triage", prompt: "triage", workingDirectory: "/repo",
                                             providerID: provider, schedule: .hourly)
        let interval = NexusAgentScheduledTask(name: "Every 30", prompt: "poll", workingDirectory: "/repo",
                                               providerID: provider, schedule: .intervalMinutes(30))
        let disabled = NexusAgentScheduledTask(name: "Off", prompt: "x", workingDirectory: "/repo",
                                               providerID: provider, schedule: .intervalMinutes(1), isEnabled: false)
        manager.upsert(hourly)
        manager.upsert(interval)
        manager.upsert(disabled)

        let topOfHour = date("2026-10-23T11:00:00Z")
        XCTAssertEqual(Set(manager.dueTasks(at: topOfHour).map(\.id)), [hourly.id, interval.id],
                       "a cron task never run is due in its minute; an interval task at once; a disabled one never")
        XCTAssertEqual(manager.dueTasks(at: date("2026-10-23T11:20:00Z")).map(\.id), [interval.id],
                       "not the top of the hour")

        manager.markExecuted(id: hourly.id, at: topOfHour, succeeded: true)
        manager.markExecuted(id: interval.id, at: topOfHour, succeeded: false)
        XCTAssertEqual(manager.tasks.first { $0.id == interval.id }?.lastRunSucceeded, false)
        XCTAssertEqual(manager.dueTasks(at: date("2026-10-23T11:29:00Z")), [])
        XCTAssertEqual(manager.dueTasks(at: date("2026-10-23T11:30:00Z")).map(\.id), [interval.id])
        XCTAssertEqual(Set(manager.dueTasks(at: date("2026-10-23T12:00:00Z")).map(\.id)), [hourly.id, interval.id])
    }

    @MainActor
    func testTasksPersistInTheStateDirectory() {
        let directory = temporaryDirectory()
        let manager = NexusAgentAutomationManager(stateDirectory: directory, calendar: utc)
        let task = NexusAgentScheduledTask(name: "Nightly", prompt: "summarise", workingDirectory: "/repo",
                                           providerID: UUID(), model: "opus", useWorktree: true,
                                           schedule: .cron("0 2 * * *"))
        manager.upsert(task)
        manager.markExecuted(id: task.id, at: date("2026-10-23T02:00:00Z"), succeeded: true)
        XCTAssertNil(manager.lastError)
        XCTAssertTrue(FileManager.default.fileExists(atPath: manager.fileURL.path))

        let reloaded = NexusAgentAutomationManager(stateDirectory: directory, calendar: utc)
        XCTAssertEqual(reloaded.tasks, manager.tasks)
        reloaded.setEnabled(false, id: task.id)
        reloaded.remove(id: task.id)
        XCTAssertEqual(NexusAgentAutomationManager(stateDirectory: directory).tasks, [])
    }

    @MainActor
    func testLaunchdPlistXML() throws {
        let manager = NexusAgentAutomationManager(stateDirectory: temporaryDirectory(), calendar: utc)
        let id = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
        let weekdays = NexusAgentScheduledTask(id: id, name: "Standup", prompt: "p", workingDirectory: "/Users/me/R&D",
                                               providerID: UUID(), schedule: .weekdays9am)
        let xml = manager.launchdPlistXML(for: weekdays, executablePath: "/Applications/Nexus Agent.app/Contents/MacOS/NexusAgent")
        XCTAssertTrue(xml.hasPrefix("<?xml version=\"1.0\" encoding=\"UTF-8\"?>"), xml)
        XCTAssertTrue(xml.contains("<string>nexus-agent.automation.11111111-2222-3333-4444-555555555555</string>"), xml)
        XCTAssertTrue(xml.contains("<string>--run-automation</string>"), xml)
        XCTAssertTrue(xml.contains("<string>/Users/me/R&amp;D</string>"), "escaped: \(xml)")

        // It is a real property list, with one calendar entry per weekday.
        let plist = try XCTUnwrap(PropertyListSerialization.propertyList(from: Data(xml.utf8), format: nil)
            as? [String: Any])
        XCTAssertEqual(plist["ProgramArguments"] as? [String],
                       ["/Applications/Nexus Agent.app/Contents/MacOS/NexusAgent", "--run-automation", id.uuidString])
        let entries = try XCTUnwrap(plist["StartCalendarInterval"] as? [[String: Int]])
        XCTAssertEqual(entries.count, 5)
        XCTAssertEqual(Set(entries.compactMap { $0["Weekday"] }), [1, 2, 3, 4, 5])
        XCTAssertTrue(entries.allSatisfy { $0["Hour"] == 9 && $0["Minute"] == 0 })

        var hourly = weekdays
        hourly.schedule = .hourly
        let hourlyPlist = try XCTUnwrap(PropertyListSerialization.propertyList(
            from: Data(manager.launchdPlistXML(for: hourly, executablePath: "/x").utf8), format: nil) as? [String: Any])
        XCTAssertEqual(hourlyPlist["StartCalendarInterval"] as? [String: Int], ["Minute": 0])

        var interval = weekdays
        interval.schedule = .intervalMinutes(15)
        let intervalPlist = try XCTUnwrap(PropertyListSerialization.propertyList(
            from: Data(manager.launchdPlistXML(for: interval, executablePath: "/x").utf8), format: nil) as? [String: Any])
        XCTAssertEqual(intervalPlist["StartInterval"] as? Int, 900)
        XCTAssertNil(intervalPlist["StartCalendarInterval"])
    }

    // MARK: - Orchestration runs and the control protocol

    /// write → (review, docs): review and docs both wait on write.
    private func diamond() -> [NexusAgentWorkerTask] {
        let write = NexusAgentWorkerTask(title: "Write", promptSpec: "implement", role: .writerWorktree)
        let review = NexusAgentWorkerTask(title: "Review", promptSpec: "review", role: .reviewerReadOnly,
                                          dependsOnTaskIDs: [write.id])
        let docs = NexusAgentWorkerTask(title: "Docs", promptSpec: "document", role: .writerWorktree,
                                        dependsOnTaskIDs: [write.id])
        return [write, review, docs]
    }

    func testReadyTasksAreThoseWhoseDependenciesCompleted() {
        var run = NexusAgentOrchestrationRun(name: "Diamond", tasks: diamond())
        XCTAssertEqual(run.readyTasks.map(\.title), ["Write"])
        XCTAssertFalse(run.isComplete)
        run.tasks[0].status = .completed
        XCTAssertEqual(run.readyTasks.map(\.title), ["Review", "Docs"])
        run.tasks[1].status = .completed
        run.tasks[2].status = .completed
        XCTAssertTrue(run.isComplete)
        XCTAssertTrue(run.succeeded)
        XCTAssertNil(run.validationError)
    }

    func testInvalidGraphsAreRefused() {
        var a = NexusAgentWorkerTask(title: "A", promptSpec: "a")
        var b = NexusAgentWorkerTask(title: "B", promptSpec: "b", dependsOnTaskIDs: [a.id])
        a.dependsOnTaskIDs = [b.id]
        XCTAssertEqual(NexusAgentOrchestrationRun(name: "loop", tasks: [a, b]).validationError,
                       "the task dependencies form a cycle")
        b.dependsOnTaskIDs = [UUID()]
        a.dependsOnTaskIDs = []
        XCTAssertNotNil(NexusAgentOrchestrationRun(name: "dangling", tasks: [a, b]).validationError)
    }

    @MainActor
    func testTheDAGMovesFromPendingThroughReadyDispatchedAndCompleted() throws {
        let coordinator = NexusAgentOrchestrationCoordinator(worktreeRoot: "/tmp/wt/")
        let tasks = diamond()
        let run = try coordinator.startRun(name: "Feature X", tasks: tasks).get()
        XCTAssertEqual(run.tasks.map(\.status), [.ready, .pending, .pending])

        let first = coordinator.dispatchReady(runID: run.id)
        XCTAssertEqual(first.map(\.title), ["Write"])
        XCTAssertEqual(first.first?.worktreePath,
                       "/tmp/wt/feature-x-" + tasks[0].id.uuidString.prefix(8).lowercased())
        XCTAssertEqual(coordinator.run(id: run.id)?.tasks.map(\.status), [.dispatched, .pending, .pending])
        XCTAssertEqual(coordinator.dispatchReady(runID: run.id), [], "nothing else is ready yet")

        XCTAssertNil(coordinator.workerDone(runID: run.id, taskID: tasks[0].id, succeeded: true, summary: "done"))
        XCTAssertEqual(coordinator.run(id: run.id)?.tasks.map(\.status), [.completed, .ready, .ready],
                       "finishing the writer unlocks both dependents")

        let second = coordinator.dispatchReady(runID: run.id)
        XCTAssertEqual(second.map(\.title), ["Review", "Docs"])
        XCTAssertNil(second[0].worktreePath, "a reviewer reads only, so it gets no worktree")
        XCTAssertNotNil(second[1].worktreePath)

        coordinator.workerDone(runID: run.id, taskID: tasks[1].id, succeeded: true, summary: "LGTM")
        coordinator.workerDone(runID: run.id, taskID: tasks[2].id, succeeded: true, summary: "docs")
        XCTAssertEqual(coordinator.run(id: run.id)?.isComplete, true)
        XCTAssertEqual(coordinator.inbox.map(\.summary), ["done", "LGTM", "docs"])
        XCTAssertNotNil(coordinator.workerDone(runID: run.id, taskID: tasks[1].id, succeeded: true, summary: ""),
                       "a second report for a finished task is refused")
    }

    @MainActor
    func testRepeatedFailureBreaksTheCircuitDownstream() throws {
        let coordinator = NexusAgentOrchestrationCoordinator(worktreeRoot: "/wt", maxFailures: 2)
        let tasks = diamond()
        let run = try coordinator.startRun(name: "Flaky", tasks: tasks).get()
        coordinator.dispatchReady(runID: run.id)
        coordinator.workerDone(runID: run.id, taskID: tasks[0].id, succeeded: false, summary: "oops")
        XCTAssertEqual(coordinator.run(id: run.id)?.tasks[0].status, .ready, "one failure is retried")
        coordinator.dispatchReady(runID: run.id)
        coordinator.workerDone(runID: run.id, taskID: tasks[0].id, succeeded: false, summary: "oops again")
        XCTAssertEqual(coordinator.run(id: run.id)?.tasks.map(\.status), [.circuitBroken, .circuitBroken, .circuitBroken])
        XCTAssertEqual(coordinator.run(id: run.id)?.isComplete, true)
        XCTAssertEqual(coordinator.run(id: run.id)?.succeeded, false)
    }

    @MainActor
    func testJSONControlCommands() throws {
        let coordinator = NexusAgentOrchestrationCoordinator(worktreeRoot: "/wt")
        coordinator.hibernatedSessionIDs = { ["asleep-1"] }

        // A CLI caller sends a bare task list: only title and promptSpec.
        let writerID = UUID()
        let dispatch = """
        {"id":"1","method":"orchestration.dispatch","params":{"runName":"cli run","tasks":[
          {"id":"\(writerID.uuidString)","title":"Write","promptSpec":"do it"},
          {"title":"Review","promptSpec":"check it","role":"reviewerReadOnly","dependsOnTaskIDs":["\(writerID.uuidString)"]}
        ]}}
        """
        let dispatched = try decode(coordinator.handle(json: Data(dispatch.utf8)))
        XCTAssertEqual(dispatched.id, "1")
        XCTAssertTrue(dispatched.ok, dispatched.error ?? "")
        XCTAssertEqual(dispatched.result?.dispatched?.map(\.id), [writerID])
        let runID = try XCTUnwrap(dispatched.result?.run?.id)

        let done = """
        {"id":"2","method":"orchestration.worker_done","params":{"runID":"\(runID.uuidString)","taskID":"\(writerID.uuidString)","succeeded":true,"summary":"wrote it"}}
        """
        let doneResponse = try decode(coordinator.handle(json: Data(done.utf8)))
        XCTAssertTrue(doneResponse.ok, doneResponse.error ?? "")
        XCTAssertEqual(doneResponse.result?.run?.tasks.map(\.status), [.completed, .ready])

        let status = try decode(coordinator.handle(json: Data(#"{"id":"3","method":"status"}"#.utf8)))
        XCTAssertTrue(status.ok)
        XCTAssertEqual(status.result?.runs?.map(\.id), [runID])
        XCTAssertEqual(status.result?.hibernatedSessionIDs, ["asleep-1"])

        let inbox = coordinator.handle(NexusAgentControlCommand(id: "4", method: .inboxList))
        XCTAssertEqual(inbox.result?.inbox?.map(\.summary), ["wrote it"])

        let worktree = coordinator.handle(NexusAgentControlCommand(
            method: .worktreeCreate, params: .init(branch: "feat/thing")))
        XCTAssertEqual(worktree.result?.worktreePath, "/wt/feat-thing")
        XCTAssertEqual(worktree.result?.gitArguments, ["worktree", "add", "-b", "feat/thing", "/wt/feat-thing"])

        // Mistakes come back as failures, never as a thrown error.
        let missing = coordinator.handle(NexusAgentControlCommand(method: .orchestrationWorkerDone))
        XCTAssertFalse(missing.ok)
        let garbage = try decode(coordinator.handle(json: Data("not json".utf8)))
        XCTAssertFalse(garbage.ok)
        XCTAssertNotNil(garbage.error)
        let unknown = try decode(coordinator.handle(json: Data(#"{"method":"reboot"}"#.utf8)))
        XCTAssertFalse(unknown.ok)
    }

    func testControlMethodsUseTheirWireNames() throws {
        XCTAssertEqual(NexusAgentControlCommand.Method.allCases.map(\.rawValue),
                       ["status", "worktree.create", "orchestration.dispatch", "orchestration.worker_done", "inbox.list"])
        let command = NexusAgentControlCommand(id: "9", method: .orchestrationWorkerDone,
                                               params: .init(runID: UUID(), taskID: UUID(), succeeded: true))
        let data = try JSONEncoder().encode(command)
        XCTAssertTrue(String(decoding: data, as: UTF8.self).contains("\"orchestration.worker_done\""))
        XCTAssertEqual(try JSONDecoder().decode(NexusAgentControlCommand.self, from: data), command)
    }

    private func decode(_ data: Data) throws -> NexusAgentControlResponse {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(NexusAgentControlResponse.self, from: data)
    }

    // MARK: - SSH remote worktrees and the mobile companion

    func testSSHArgumentsRunInTheRemoteWorkspaceWithAPortForward() {
        let host = NexusAgentRemoteHost(label: "Build box", sshHost: "build.lan", sshUser: "james",
                                        remoteWorkspacePath: "/home/james/it's here",
                                        portForwardLocalPort: 3000, portForwardRemotePort: 5173)
        XCTAssertEqual(NexusAgentRemoteAndMobileBridge.sshArguments(for: host, remoteCommand: "claude -p hi"),
                       ["-o", "BatchMode=yes", "-o", "ServerAliveInterval=30",
                        "-L", "3000:localhost:5173",
                        "james@build.lan",
                        "cd '/home/james/it'\\''s here' && claude -p hi"])
        XCTAssertEqual(NexusAgentRemoteAndMobileBridge.sshArguments(for: host, remoteCommand: " "),
                       ["-o", "BatchMode=yes", "-o", "ServerAliveInterval=30",
                        "-L", "3000:localhost:5173", "-N", "james@build.lan"],
                       "no command only holds the forward open")
    }

    func testSSHArgumentsWithoutAPortForwardOrUser() {
        let host = NexusAgentRemoteHost(label: "box", sshHost: "box", portForwardLocalPort: 3000)
        XCTAssertEqual(NexusAgentRemoteAndMobileBridge.sshArguments(for: host, remoteCommand: "ls"),
                       ["-o", "BatchMode=yes", "-o", "ServerAliveInterval=30", "box", "ls"])
        var badPort = host
        badPort.portForwardRemotePort = 70000
        XCTAssertEqual(NexusAgentRemoteAndMobileBridge.portForwardArguments(for: badPort), [])
    }

    func testMobileSnapshotsRoundTrip() throws {
        let snapshots = [
            NexusAgentMobileSessionSnapshot(sessionID: "a", title: "Fix the build", providerName: "Claude",
                                            status: "waiting", workingDirectory: "/repo", worktreeBranch: "fix/build",
                                            pendingApprovalSummary: "Run bazel test?",
                                            updatedAt: Date(timeIntervalSince1970: 1_800_000_000)),
            NexusAgentMobileSessionSnapshot(sessionID: "b", title: "Docs", providerName: "OpenCode",
                                            status: "idle", workingDirectory: "/docs",
                                            updatedAt: Date(timeIntervalSince1970: 1_800_000_060)),
        ]
        let data = try NexusAgentRemoteAndMobileBridge.exportSnapshots(snapshots)
        let text = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(text.contains("\"updatedAt\":\"2027-01-15T08:00:00Z\""), "dates go out as ISO 8601: \(text)")
        XCTAssertTrue(text.contains("\"pendingApprovalSummary\":\"Run bazel test?\""), text)
        XCTAssertEqual(try NexusAgentRemoteAndMobileBridge.importSnapshots(data), snapshots)
    }

    func testMobileQuickActions() throws {
        XCTAssertEqual(NexusAgentMobileQuickAction.allCases.map(\.rawValue),
                       ["approve", "deny", "stop", "send_prompt", "switch_account"])
        let prompt = try NexusAgentRemoteAndMobileBridge.decodeCommand(
            Data(#"{"action":"send_prompt","sessionID":"a","text":"keep going"}"#.utf8))
        XCTAssertEqual(prompt, NexusAgentMobileCommand(action: .sendPrompt, sessionID: "a", text: "keep going"))
        let approve = NexusAgentMobileCommand(action: .approve, sessionID: "a")
        XCTAssertEqual(try NexusAgentRemoteAndMobileBridge.decodeCommand(
            NexusAgentRemoteAndMobileBridge.encodeCommand(approve)), approve)

        XCTAssertThrowsError(try NexusAgentRemoteAndMobileBridge.decodeCommand(
            Data(#"{"action":"send_prompt","sessionID":"a"}"#.utf8))) { error in
            XCTAssertEqual(error as? NexusAgentRemoteAndMobileBridge.BridgeError, .missingText)
        }
        XCTAssertThrowsError(try NexusAgentRemoteAndMobileBridge.decodeCommand(
            Data(#"{"action":"switch_account","sessionID":"a"}"#.utf8))) { error in
            XCTAssertEqual(error as? NexusAgentRemoteAndMobileBridge.BridgeError, .missingAccount)
        }
        XCTAssertThrowsError(try NexusAgentRemoteAndMobileBridge.decodeCommand(
            Data(#"{"action":"stop","sessionID":" "}"#.utf8)))
        XCTAssertThrowsError(try NexusAgentRemoteAndMobileBridge.decodeCommand(
            Data(#"{"action":"reboot","sessionID":"a"}"#.utf8)))
    }
}
