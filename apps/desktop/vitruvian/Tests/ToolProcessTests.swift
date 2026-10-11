// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import Darwin
import Foundation
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
        ignoresBeingAskedToEnd(suite, fixture)
        doesNotRead(suite, fixture)
        floods(suite, fixture)
        cannotStart(suite)
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

        init(program: URL) {
            folder = FileManager.default.temporaryDirectory
                .appendingPathComponent("vitruvian-tool-process-\(UUID().uuidString)", isDirectory: true)
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            transport = ProcessTransport(program: program, directory: folder)
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
            return ToolRuntimeSupport.wait { self.link.state == .ready || self.link.state == .ended }
                && link.state == .ready
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

        /// Ends the process whatever state the test left it in, and says
        /// whether it is gone.
        func close() -> Bool {
            transport.kill()
            let gone = ToolRuntimeSupport.wait { self.isGone }
            try? FileManager.default.removeItem(at: folder)
            return gone
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
            suite.expect(false, "the tool starts, to be killed")
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
            suite.expect(false, "the tool starts, to crash")
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
            suite.expect(false, "the tool starts, to hang")
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

    static func ignoresBeingAskedToEnd(_ suite: TestSuite, _ fixture: URL) {
        let bench = Bench(program: fixture)
        guard bench.start() else {
            suite.expect(false, "the tool starts, to be stubborn")
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
            suite.expect(false, "the tool starts, to stop reading")
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
            suite.expect(false, "the tool starts, to flood")
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
}
