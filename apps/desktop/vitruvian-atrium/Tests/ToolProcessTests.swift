// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import Darwin
import Foundation
import os
import VitruvianCore
import VitruvianServices
import VitruvianToolProtocol

/// A link to a tool that is a real child process: the fixture tool
/// (`Tools/ToolFixture.swift`), which Bazel builds and hands to the tests.
///
/// Nothing here can hang the run. Every deadline of the runtime is on a
/// clock the test moves by hand, so none runs out because a runner is slow.
/// Every wait for the child is `ToolRuntimeSupport.wait`, which gives up
/// after twenty seconds. Every child is killed and seen gone before its
/// test returns, and the fixture ends itself after two minutes whatever
/// happens.
enum ToolProcessTests {
    static func run(_ suite: TestSuite) {
        guard let fixture else {
            suite.expect(false, "the fixture tool is built and handed to the tests in VITRUVIAN_TOOL_FIXTURE")
            return
        }
        runsAndStops(suite, fixture)
        diesMidCommand(suite, fixture)
        hangs(suite, fixture)
        staysHungWhenItsInputEnds(suite, fixture)
        ignoresBeingAskedToEnd(suite, fixture)
        doesNotRead(suite, fixture)
        floods(suite, fixture)
        cannotStart(suite)
        whichGroup(suite)
        helpersEndWithTheirTool(suite, fixture)
        helpersAreAskedThenKilled(suite, fixture)
        helpersOutOfReach(suite, fixture)
    }

    /// The fixture tool, below the runfiles Bazel gives the test.
    static var fixture: URL? {
        let environment = ProcessInfo.processInfo.environment
        guard let path = environment["VITRUVIAN_TOOL_FIXTURE"], let runfiles = environment["TEST_SRCDIR"],
              let workspace = environment["TEST_WORKSPACE"] else { return nil }
        let url = URL(fileURLWithPath: "\(runfiles)/\(workspace)/\(path)")
        return FileManager.default.isExecutableFile(atPath: url.path) ? url : nil
    }

    /// A link over a real process, and everything the link reported.
    final class Bench {
        let clock = ManualToolClock()
        let folder: URL
        let transport: ProcessTransport
        var ends: [ToolLink.End] = []
        var runnable: [[String]] = []
        var logged: [ToolLog.Entry] = []
        var served: [(method: ToolMethod, params: JSONValue?)] = []
        private(set) var link: ToolLink!

        /// The helpers the fixture started in this bench. `close` ends
        /// each that is still there.
        var helpers: [Helper] = []

        /// Every process group the app signalled for this tool, and with
        /// what: "kill <group>" for a signal, "sweep <group>" for the end
        /// of what a tool left behind.
        let signalled = OSAllocatedUnfairLock(initialState: [String]())

        /// `groupOf` stands in for asking macOS which process group a
        /// process is in. Without `sweeps`, what a tool leaves behind when
        /// it is gone is noted and not ended.
        init(program: URL, groupOf: (@Sendable (pid_t) -> pid_t)? = nil, sweeps: Bool = true) {
            let folder = FileManager.default.temporaryDirectory
                .appendingPathComponent("vitruvian-tool-process-\(UUID().uuidString)", isDirectory: true)
            self.folder = folder
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let live = ToolProcessGroup.Access.live
            let signalled = self.signalled
            transport = ProcessTransport(program: program, directory: folder, groups: .init(
                of: groupOf ?? live.of,
                signal: { group, number in
                    signalled.withLock { $0.append("\(number == SIGKILL ? "kill" : "signal \(number)") \(group)") }
                    live.signal(group, number)
                },
                sweep: { group in
                    signalled.withLock { $0.append("sweep \(group)") }
                    if sweeps { live.sweep(group) }
                }))
            link = ToolLink(
                transport: transport, clock: clock,
                hello: InitializeParams(protocolVersions: ProtocolVersion.supported, language: "fr",
                                        dataFolder: folder.path),
                serve: { [unowned self] method, params, reply in
                    served.append((method, params))
                    reply(.success(.object([:])))
                },
                events: .init(onRunnable: { [unowned self] in runnable.append($0) },
                              onLog: { [unowned self] in logged.append(.init(source: $1, text: $0)) },
                              onEnd: { [unowned self] in ends.append($0) }))
        }

        /// Starts the tool and waits for its greeting.
        func start() -> Bool {
            link.start()
            let ready = ToolRuntimeSupport.wait { self.link.state == .ready || self.link.state == .ended }
                && link.state == .ready
            if !ready { problem = "the tool was not greeted: link \(link.state), ended \(ends)" }
            return ready
        }

        func run(_ command: String) -> () -> Result<Void, ToolLink.Failure>? {
            var outcome: Result<Void, ToolLink.Failure>?
            link.run(command) { outcome = $0 }
            return { outcome }
        }

        /// True when the process is gone: ended, and collected by the app.
        var isGone: Bool {
            guard let pid = transport.processIdentifier else { return true }
            return !transport.isRunning && Darwin.kill(pid, 0) == -1 && errno == ESRCH
        }

        /// Ends the process whatever state the test left it in, and every
        /// helper it started that is still there, and says whether all of
        /// them are gone.
        func close() -> Bool {
            transport.kill()
            let gone = ToolRuntimeSupport.wait { self.isGone }
            let helpersGone = helpers.map { $0.end() }.allSatisfy { $0 }
            try? FileManager.default.removeItem(at: folder)
            return gone && helpersGone
        }

        /// Has the fixture start a helper, and gives it back once it has
        /// written its file for the first time.
        func startHelper(_ command: String = "helper") -> Helper? {
            let answer = run(command)
            guard ToolRuntimeSupport.wait(until: { answer() != nil }), ToolLinkTests.ok(answer()) else {
                problem = "the command `\(command)` was not answered: \(String(describing: answer())), link \(link.state)"
                return nil
            }
            guard let helper = Helper(logged: logged.map(\.text), program: transport.program) else {
                problem = "the fixture did not log its helper: \(logged.map(\.text))"
                return nil
            }
            // Whatever comes next, the test knows of it and ends it.
            helpers.append(helper)
            guard ToolRuntimeSupport.wait(until: { helper.count > 0 }) else {
                problem = "the helper \(helper.pid) never wrote its file"
                return nil
            }
            return helper
        }

        /// Why the last step of setting a test up did not work.
        var problem = ""

        /// Has the fixture ignore being asked to end, and stop reading.
        func makeStubborn() -> Bool {
            _ = run("stubborn")
            return ToolRuntimeSupport.wait { self.logged.contains(.init(source: .message, text: "stubborn")) }
        }
    }

    /// A program the fixture started for itself, as a test sees it: by its
    /// process id, and by the file it writes a count into for as long as it
    /// lives. It is no child of the test, so nothing waits for it: once it
    /// has ended, launchd collects it and its id names no process.
    struct Helper {
        let pid: pid_t
        let file: URL
        /// The fixture's own file, to tell this helper from a process that
        /// took its id after it ended.
        let program: URL

        /// Reads the newest "helper pid=<id> file=<path>" the fixture logged.
        init?(logged: [String], program: URL) {
            guard let line = logged.last(where: { $0.hasPrefix("helper pid=") }),
                  let split = line.range(of: " file="),
                  let pid = pid_t(line[line.index(line.startIndex, offsetBy: "helper pid=".count)..<split.lowerBound]),
                  pid > 1 else { return nil }
            self.pid = pid
            file = URL(fileURLWithPath: String(line[split.upperBound...]))
            self.program = program
        }

        /// The count it last wrote; 0 when its file is not there. The
        /// helper writes each count as a whole new file, so a count that
        /// was read is never followed by a smaller one.
        var count: Int {
            (try? String(contentsOf: file, encoding: .utf8)).flatMap { Int($0) } ?? 0
        }

        /// True when it goes on writing: its count rises while this looks.
        func stillWrites(upTo seconds: TimeInterval = 20) -> Bool {
            let from = count
            return ToolRuntimeSupport.wait(upTo: seconds) { self.count > from }
        }

        /// True once no process has its id.
        var isGone: Bool {
            ToolRuntimeSupport.wait { Darwin.kill(self.pid, 0) == -1 && errno == ESRCH }
        }

        /// True once it has ended. While its tool lives and does not
        /// collect it, a helper that ended still has its id, as a zombie.
        var hasEnded: Bool {
            ToolRuntimeSupport.wait {
                if Darwin.kill(self.pid, 0) == -1, errno == ESRCH { return true }
                var name = [CTL_KERN, KERN_PROC, KERN_PROC_PID, self.pid]
                var info = kinfo_proc()
                var size = MemoryLayout<kinfo_proc>.stride
                guard sysctl(&name, 4, &info, &size, nil, 0) == 0, size > 0 else { return true }
                // SZOMB: ended, and waiting to be collected.
                return info.kp_proc.p_stat == 5
            }
        }

        /// The process group it is in now, or -1 when it is gone.
        var group: pid_t { getpgid(pid) }

        /// True while the process with its id runs the fixture's program.
        private var isStillTheHelper: Bool {
            var buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
            guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { return false }
            let running = URL(fileURLWithPath: String(cString: buffer)).lastPathComponent
            return running == program.lastPathComponent || running == program.resolvingSymlinksInPath().lastPathComponent
        }

        /// Ends it when it is still there, and says whether it is gone. It
        /// kills only this helper: never a process that took its id since.
        @discardableResult
        func end() -> Bool {
            if isStillTheHelper { Darwin.kill(pid, SIGKILL) }
            return isGone
        }
    }

    static func runsAndStops(_ suite: TestSuite, _ fixture: URL) {
        let bench = Bench(program: fixture)
        suite.expect(bench.start() && bench.link.toolVersion == "fixture" && bench.transport.isRunning,
                     "a real tool is started as a child process and greeted")
        suite.expect(ToolRuntimeSupport.wait { !bench.runnable.isEmpty }
                         && bench.runnable.first?.contains("hello") == true,
                     "and says which of its commands can run")

        let hello = bench.run("hello")
        suite.expect(ToolRuntimeSupport.wait { hello() != nil } && ToolLinkTests.ok(hello())
                         && bench.served.count == 1 && bench.served.first?.method == .notifyHUD
                         && bench.served.first?.params
                         == .object(["icon": .string("hand.wave"), "message": .string("Hello from the fixture")]),
                     "its command runs: it asks the app for a message, is answered, and answers the command")

        let place = bench.run("where")
        _ = ToolRuntimeSupport.wait { place() != nil }
        // "cwd=<folder> data=<folder> language=<tag>", the first as macOS
        // names the folder once links are followed.
        let told = bench.logged.last?.text.split(separator: " ").map(String.init) ?? []
        suite.expect(told.count == 3 && told[0].hasPrefix("cwd=")
                         && URL(fileURLWithPath: String(told[0].dropFirst(4))).resolvingSymlinksInPath()
                         == bench.folder.resolvingSymlinksInPath()
                         && told[1] == "data=\(bench.folder.path)" && told[2] == "language=fr",
                     "it runs in its data folder, and was told that folder and the language")

        let mutter = bench.run("mutter")
        suite.expect(ToolRuntimeSupport.wait {
                         mutter() != nil && bench.logged.contains(.init(source: .standardError,
                                                                        text: "fixture: on standard error\n"))
                     }, "what it writes to standard error goes to its log")

        bench.link.shutdown()
        // Not one turn of the run loop: this is what the app can see at quit.
        let deadline = Date(timeIntervalSinceNow: 20)
        while !bench.link.hasEnded, Date() < deadline { usleep(5_000) }
        suite.expect(bench.link.hasEnded, "after goodbye it exits, and the app sees that without its main thread turning")
        suite.expect(ToolRuntimeSupport.wait { !bench.ends.isEmpty } && bench.ends == [.stopped]
                         && bench.transport.exitStatus == 0 && bench.clock.waiting == 0,
                     "it was stopped: it left by itself with status 0, and no signal was needed")
        suite.expect(bench.close(), "and no process is left")
    }

    static func diesMidCommand(_ suite: TestSuite, _ fixture: URL) {
        let bench = Bench(program: fixture)
        guard bench.start(), let pid = bench.transport.processIdentifier else {
            suite.expect(false, "the tool starts, to be killed (\(bench.problem))")
            _ = bench.close()
            return
        }
        let hung = bench.run("hang")
        Darwin.kill(pid, SIGKILL)
        suite.expect(ToolRuntimeSupport.wait { !bench.ends.isEmpty } && bench.ends == [.exited(128 + SIGKILL)]
                         && ToolLinkTests.failure(hung()) == .notReady && bench.link.state == .ended,
                     "a tool killed while it runs a command ends its link, and the command fails")
        suite.expect(bench.close(), "and no process is left")

        let crashing = Bench(program: fixture)
        guard crashing.start() else {
            suite.expect(false, "the tool starts, to crash (\(crashing.problem))")
            _ = crashing.close()
            return
        }
        let crash = crashing.run("crash")
        suite.expect(ToolRuntimeSupport.wait { !crashing.ends.isEmpty } && crashing.ends == [.exited(3)]
                         && ToolLinkTests.failure(crash()) == .notReady,
                     "a tool that exits by itself ends its link with its status")
        suite.expect(crashing.close(), "and no process is left")
    }

    static func hangs(_ suite: TestSuite, _ fixture: URL) {
        let bench = Bench(program: fixture)
        guard bench.start() else {
            suite.expect(false, "the tool starts, to hang (\(bench.problem))")
            _ = bench.close()
            return
        }
        var outcomes: [() -> Result<Void, ToolLink.Failure>?] = []
        for _ in 0..<3 {
            outcomes.append(bench.run("hang"))
            bench.clock.advance(by: 2)
        }
        suite.expect(outcomes.allSatisfy { ToolLinkTests.failure($0()) == .noAnswer }
                         && bench.link.state == .stopping,
                     "a tool that answers nothing three times in a row is being stopped")
        suite.expect(ToolRuntimeSupport.wait { !bench.ends.isEmpty } && bench.ends == [.misbehaved(.silent)]
                         && bench.transport.exitStatus == 128 + SIGTERM,
                     "it is asked to end at once, with no goodbye, and ends")
        suite.expect(bench.close(), "and no process is left")
    }

    /// The fixture's `hang` must outlive its input: `hangs` closes it and
    /// signals the tool at once, and reads the signal from the status.
    static func staysHungWhenItsInputEnds(_ suite: TestSuite, _ fixture: URL) {
        let bench = Bench(program: fixture)
        guard bench.start() else {
            suite.expect(false, "the tool starts, to hang (\(bench.problem))")
            _ = bench.close()
            return
        }
        _ = bench.run("hang")
        bench.transport.closeInput()
        let ended = ToolRuntimeSupport.wait(upTo: 1) { bench.transport.exitStatus != nil }
        suite.expect(!ended && bench.transport.isRunning,
                     "a hung tool whose input ends is still there: only a signal ends it")
        suite.expect(bench.close(), "and no process is left")
    }

    static func ignoresBeingAskedToEnd(_ suite: TestSuite, _ fixture: URL) {
        let bench = Bench(program: fixture)
        guard bench.start() else {
            suite.expect(false, "the tool starts, to be stubborn (\(bench.problem))")
            _ = bench.close()
            return
        }
        _ = bench.run("stubborn")
        guard ToolRuntimeSupport.wait(until: { bench.logged.contains(.init(source: .message, text: "stubborn")) }) else {
            suite.expect(false, "the tool says it has stopped listening")
            _ = bench.close()
            return
        }
        bench.link.shutdown()
        bench.clock.advance(by: 2)
        bench.clock.advance(by: 1)
        suite.expect(ToolRuntimeSupport.wait { !bench.ends.isEmpty } && bench.ends == [.stopped]
                         && bench.transport.exitStatus == 128 + SIGKILL,
                     "a tool that ignores goodbye and being asked to end is killed")
        suite.expect(bench.close(), "and no process is left")
    }

    static func doesNotRead(_ suite: TestSuite, _ fixture: URL) {
        let bench = Bench(program: fixture)
        guard bench.start() else {
            suite.expect(false, "the tool starts, to stop reading (\(bench.problem))")
            _ = bench.close()
            return
        }
        _ = bench.run("stubborn")
        guard ToolRuntimeSupport.wait(until: { bench.logged.contains(.init(source: .message, text: "stubborn")) }) else {
            suite.expect(false, "the tool says it has stopped listening")
            _ = bench.close()
            return
        }
        // Six notices of 900 KB each, to a tool that takes none of them.
        let large = String(repeating: "x", count: 900_000)
        let started = ProcessInfo.processInfo.systemUptime
        for _ in 0..<6 { bench.link.preferencesChanged(["blob": .string(large)]) }
        suite.expect(bench.link.fault == .notReading && bench.link.state == .stopping
                         && ProcessInfo.processInfo.systemUptime - started < 5,
                     "a tool that takes nothing of what the app writes is stopped once 4 MB waits for it, "
                         + "and the main thread did not wait on its pipe")
        bench.clock.advance(by: 1)
        suite.expect(ToolRuntimeSupport.wait { !bench.ends.isEmpty } && bench.ends == [.misbehaved(.notReading)],
                     "and it is ended like any tool that misbehaves")
        suite.expect(bench.close(), "and no process is left")
    }

    static func floods(_ suite: TestSuite, _ fixture: URL) {
        let bench = Bench(program: fixture)
        guard bench.start() else {
            suite.expect(false, "the tool starts, to flood (\(bench.problem))")
            _ = bench.close()
            return
        }
        _ = bench.run("flood")
        // Five seconds on the link's clock, each with more than 200 lines
        // that arrived within it.
        var seen = true
        for _ in 1...5 where seen {
            let before = bench.logged.count
            seen = ToolRuntimeSupport.wait { bench.logged.count > before + 200 || !bench.ends.isEmpty }
            bench.clock.advance(by: 1)
        }
        suite.expect(seen && ToolRuntimeSupport.wait { !bench.ends.isEmpty } && bench.ends == [.misbehaved(.flood)],
                     "a tool that writes without end is stopped as a flood, and the app read it all the while")
        suite.expect(bench.close(), "and no process is left")
    }

    static func cannotStart(_ suite: TestSuite) {
        let missing = Bench(program: URL(fileURLWithPath: "/nonexistent/vitruvian-tool"))
        missing.link.start()
        suite.expect(missing.ends == [.exited(nil)] && !missing.transport.isRunning
                         && missing.transport.processIdentifier == nil,
                     "a program that is not there cannot be started, and its link ends at once")
        suite.expect(missing.close(), "with no process to leave behind")
    }

    /// Which process group the app may signal for a child: only one the
    /// child leads, and never the app's own, the first process's or none.
    static func whichGroup(_ suite: TestSuite) {
        suite.expect(ProcessTransport.group(ledBy: 4_242, in: 4_242, mine: 77) == 4_242,
                     "a child that leads a process group of its own has that group")
        suite.expect(ProcessTransport.group(ledBy: 4_242, in: 77, mine: 77) == nil
                         && ProcessTransport.group(ledBy: 4_242, in: 900, mine: 77) == nil
                         && ProcessTransport.group(ledBy: 4_242, in: -1, mine: 77) == nil,
                     "a child in the app's own group, in another's, or already gone, has no group the app may signal")
        suite.expect(ProcessTransport.group(ledBy: 0, in: 0, mine: 77) == nil
                         && ProcessTransport.group(ledBy: 1, in: 1, mine: 77) == nil
                         && ProcessTransport.group(ledBy: -1, in: -1, mine: 77) == nil
                         && ProcessTransport.group(ledBy: 77, in: 77, mine: 77) == nil,
                     "group 0, group 1, a group that is no group and the app's own are never signalled, whatever is asked")
    }

    /// A program the tool started is ended with it, however the tool ends,
    /// as long as it is still in the tool's process group.
    static func helpersEndWithTheirTool(_ suite: TestSuite, _ fixture: URL) {
        // Told goodbye.
        let polite = Bench(program: fixture)
        guard polite.start(), let left = polite.startHelper() else {
            suite.expect(false, "the tool starts, and starts a helper (\(polite.problem))")
            _ = polite.close()
            return
        }
        let tool = polite.transport.processIdentifier
        suite.expect(tool != nil && polite.transport.processGroup == tool && left.group == tool && tool != getpgrp(),
                     "a tool is started in a process group of its own, not the app's, and a program it starts is in it")
        suite.expect(left.stillWrites(), "the helper runs beside its tool, and writes")
        polite.link.shutdown()
        suite.expect(ToolRuntimeSupport.wait { polite.isGone } && polite.transport.exitStatus == 0 && left.isGone
                         && !left.stillWrites(upTo: 0.2),
                     "a tool that leaves when it is told goodbye takes the helper it left running with it: "
                         + "the helper is gone, and its file stops changing")
        suite.expect(polite.close(), "and no process is left")

        // Crashed.
        let crashing = Bench(program: fixture)
        guard crashing.start(), let orphan = crashing.startHelper() else {
            suite.expect(false, "the tool starts, and starts a helper, to crash (\(crashing.problem))")
            _ = crashing.close()
            return
        }
        _ = crashing.run("crash")
        suite.expect(ToolRuntimeSupport.wait { !crashing.ends.isEmpty } && crashing.ends == [.exited(3)] && orphan.isGone,
                     "a tool that crashes does not leave its helper behind")
        suite.expect(crashing.close(), "and no process is left")

        // Its input closes with no goodbye, as when the app itself is gone.
        let cut = Bench(program: fixture)
        guard cut.start(), let child = cut.startHelper() else {
            suite.expect(false, "the tool starts, and starts a helper, to lose its input (\(cut.problem))")
            _ = cut.close()
            return
        }
        cut.transport.closeInput()
        suite.expect(ToolRuntimeSupport.wait { cut.isGone } && cut.transport.exitStatus == 0 && child.isGone,
                     "a tool whose input closes ends by itself, with no signal from a terminal or the app, "
                         + "and its helper with it")
        suite.expect(cut.close(), "and no process is left")
    }

    /// The steps the app takes to end a tool that will not leave reach the
    /// programs the tool started: asked to end, then killed.
    static func helpersAreAskedThenKilled(_ suite: TestSuite, _ fixture: URL) {
        let bench = Bench(program: fixture)
        guard bench.start(), let helper = bench.startHelper(), bench.makeStubborn() else {
            suite.expect(false, "the tool starts, starts a helper, and stops listening (\(bench.problem))")
            _ = bench.close()
            return
        }
        bench.transport.terminate()
        suite.expect(helper.hasEnded && !helper.stillWrites(upTo: 0.2) && bench.transport.isRunning,
                     "asking a tool to end asks the programs it started too: a helper that heeds it has ended "
                         + "while the tool that ignores it still runs")
        bench.transport.kill()
        suite.expect(ToolRuntimeSupport.wait { bench.isGone } && bench.transport.exitStatus == 128 + SIGKILL
                         && helper.isGone,
                     "and the kill ends the tool")
        suite.expect(bench.close(), "and no process is left")

        let deaf = Bench(program: fixture)
        guard deaf.start(), let stays = deaf.startHelper("helper-deaf"), deaf.makeStubborn() else {
            suite.expect(false, "the tool starts, starts a helper that ignores being asked, and stops listening (\(deaf.problem))")
            _ = deaf.close()
            return
        }
        deaf.transport.terminate()
        suite.expect(stays.stillWrites() && deaf.transport.isRunning,
                     "a helper that ignores being asked to end runs on, as its tool does")
        let tool = deaf.transport.processIdentifier ?? 0
        deaf.transport.kill()
        suite.expect(ToolRuntimeSupport.wait { deaf.isGone } && stays.isGone && !stays.stillWrites(upTo: 0.2),
                     "the kill ends the tool and the helper together")
        suite.expect(tool > 1 && deaf.signalled.withLock { $0 } == ["kill \(tool)", "sweep \(tool)"],
                     "the app signalled one process group and no other: the one its tool led, killed with the "
                         + "tool and looked over once when the tool was gone")
        suite.expect(deaf.close(), "and no process is left")

        // The kill by itself, with nothing looked over afterwards: as at
        // quit, when the app is gone before it sees the tool go.
        let quitting = Bench(program: fixture, sweeps: false)
        guard quitting.start(), let last = quitting.startHelper("helper-deaf"), quitting.makeStubborn() else {
            suite.expect(false, "the tool starts, starts a helper that ignores being asked, and stops listening, to be killed (\(quitting.problem))")
            _ = quitting.close()
            return
        }
        quitting.transport.kill()
        suite.expect(ToolRuntimeSupport.wait { quitting.isGone } && last.isGone,
                     "killing a tool kills the programs it started in the same stroke: nothing has to be "
                         + "looked over afterwards for them to be gone")
        suite.expect(quitting.close(), "and no process is left")
    }

    /// What the app does not reach, and must not: a helper that left the
    /// tool's process group, and any group the app did not see the tool
    /// lead.
    static func helpersOutOfReach(_ suite: TestSuite, _ fixture: URL) {
        let bench = Bench(program: fixture)
        guard bench.start(), let away = bench.startHelper("helper-away") else {
            suite.expect(false, "the tool starts, and starts a helper that leaves its group (\(bench.problem))")
            _ = bench.close()
            return
        }
        suite.expect(ToolRuntimeSupport.wait { away.group == away.pid } && away.group != bench.transport.processGroup,
                     "a helper can leave its tool's process group for one of its own")
        bench.link.shutdown()
        suite.expect(ToolRuntimeSupport.wait { bench.isGone } && away.stillWrites()
                         && bench.signalled.withLock { $0 } == ["sweep \(bench.transport.processIdentifier ?? 0)"],
                     "a helper that left the tool's process group is out of the app's reach: it runs on after its "
                         + "tool, and the app signals its tool's group and never the helper's")
        suite.expect(away.end() && bench.close(), "the test ends it, and no process is left")

        // Looking a group over is for a tool that is gone. A process that
        // has the id now is not what the tool left behind.
        let alive = Bench(program: fixture)
        guard alive.start(), let leader = alive.transport.processIdentifier else {
            suite.expect(false, "the tool starts, to be looked over while it runs (\(alive.problem))")
            _ = alive.close()
            return
        }
        ToolProcessGroup.Access.live.sweep(leader)
        let quick = alive.run("quick")
        suite.expect(ToolRuntimeSupport.wait { quick() != nil } && ToolLinkTests.ok(quick()) && alive.transport.isRunning,
                     "what is left of a process group is ended only when no process has its leader's id: "
                         + "while one has, nothing is signalled")
        suite.expect(alive.close(), "and no process is left")

        // As if macOS had not put the tool in a group of its own: the app
        // is told it is in the app's own group, and kills the tool alone.
        let mine = getpgrp()
        let shared = Bench(program: fixture, groupOf: { _ in mine })
        guard shared.start(), let helper = shared.startHelper("helper-deaf"), shared.makeStubborn() else {
            suite.expect(false, "the tool starts, starts a helper, and stops listening, in no group the app saw (\(shared.problem))")
            _ = shared.close()
            return
        }
        suite.expect(shared.transport.processGroup == nil,
                     "a tool the app did not see lead a process group has none the app may signal")
        shared.transport.terminate()
        shared.transport.kill()
        suite.expect(ToolRuntimeSupport.wait { shared.isGone } && shared.transport.exitStatus == 128 + SIGKILL
                         && helper.stillWrites() && shared.signalled.withLock { $0 }.isEmpty,
                     "such a tool is killed alone, as before, and nothing is looked over when it is gone: "
                         + "a group the app did not see the tool lead is never signalled")
        suite.expect(helper.end() && shared.close(), "the test ends the helper, and no process is left")
    }
}
