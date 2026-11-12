// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import Foundation
import VitruvianCore
import VitruvianServices
import VitruvianToolProtocol

/// One outside tool as the host holds it, across runs of its program:
/// started when needed, stopped when idle, held back after a crash, and
/// given up on. Each run is a tool that is no program, on a clock moved by
/// hand.
enum ExternalToolTests {
    static func run(_ suite: TestSuite) {
        firstCommand(suite)
        whatCanRun(suite)
        commandsThatFail(suite)
        idle(suite)
        crashes(suite)
        waits(suite)
        startsWithTheApp(suite)
        heldCommands(suite)
        stopping(suite)
        quitting(suite)
        panels(suite)
    }

    static let id = ToolID("com.acme.deploys")!
    static let copy = CommandID(tool: id, name: "copyLatest")!

    /// The tool of the design's example manifest, and each run of its
    /// program, the newest last.
    final class Bench {
        let clock = ManualToolClock()
        var runs: [FakeTool] = []
        /// Sets a run up before it starts.
        var prepare: (FakeTool) -> Void = { _ in }
        var changes = 0
        var stoppedWorking = 0
        var failed = 0
        var rendered: [String] = []
        var runsEnded = 0
        private(set) var tool: ExternalTool!

        init(activation: String = "onCommand", limits: ToolLimits = .standard) {
            let manifest = ExternalToolManifestTests.tool(#"{"activation": ["\#(activation)"]}"#)!.manifest
            tool = ExternalTool(
                manifest: manifest, clock: clock, limits: limits,
                makeLink: { [unowned self] events in
                    let run = FakeTool()
                    prepare(run)
                    runs.append(run)
                    return ToolLink(transport: run, clock: clock, limits: limits,
                                    hello: InitializeParams(protocolVersions: ["1"], language: "en",
                                                            dataFolder: "/data"),
                                    serve: { _, _, reply in reply(.success(.object([:]))) }, events: events)
                },
                events: .init(onChange: { [unowned self] in changes += 1 },
                              onStoppedWorking: { [unowned self] in stoppedWorking += 1 },
                              onCommandFailed: { [unowned self] in failed += 1 },
                              onRender: { [unowned self] panel, _ in rendered.append(panel) },
                              onRunEnded: { [unowned self] in runsEnded += 1 }))
        }

        var current: FakeTool { runs[runs.count - 1] }

        /// Stops the tool and lets go of it, as removing a tool does.
        func forget() {
            tool.stop()
            tool = nil
        }

        /// A tool the host started, whose program runs and has been greeted.
        static func running(activation: String = "onCommand", limits: ToolLimits = .standard) -> Bench {
            let bench = Bench(activation: activation, limits: limits)
            bench.tool.start()
            if activation == "onCommand" { bench.tool.run(copy) }
            bench.current.greets()
            return bench
        }

        /// The commands the current run was sent, by name.
        var commandsSent: [String] {
            current.sent.compactMap { message in
                if case .request(_, "command/run", let params) = message { return params?["command"]?.stringValue }
                return nil
            }
        }

        /// Starts a run by a command, greets it, and has it end by itself.
        func crashOnce() {
            tool.run(copy)
            current.greets()
            current.ends(1)
        }
    }

    static func firstCommand(_ suite: TestSuite) {
        let bench = Bench()
        suite.expect(bench.tool.standing == .off && !bench.tool.canRun(copy) && bench.tool.hasEnded,
                     "a tool the host has not started is off, and none of its commands can run")
        bench.tool.run(copy)
        suite.expect(bench.runs.isEmpty && bench.failed == 1, "running a command of a tool that is off fails")

        bench.tool.start()
        bench.tool.start()
        suite.expect(bench.tool.standing == .resting && bench.runs.isEmpty && bench.tool.canRun(copy),
                     "a tool that starts on a command starts no program when the host starts it, and can run")
        bench.tool.run(copy)
        suite.expect(bench.runs.count == 1 && bench.tool.standing == .starting && bench.commandsSent.isEmpty,
                     "its first command starts its program, and waits for the greeting")
        bench.current.greets()
        suite.expect(bench.tool.standing == .running && bench.commandsSent == ["copyLatest"],
                     "once greeted, the command is sent")
        bench.current.answers(2)
        bench.tool.run(copy)
        suite.expect(bench.runs.count == 1 && bench.commandsSent == ["copyLatest", "copyLatest"] && bench.failed == 1,
                     "the next command goes to the program that is already running")
    }

    static func whatCanRun(_ suite: TestSuite) {
        let bench = Bench.running()
        let other = CommandID(tool: id, name: "other")!
        let stranger = CommandID(tool: ToolID("com.acme.other")!, name: "copyLatest")!
        suite.expect(bench.tool.canRun(copy) && !bench.tool.canRun(other) && !bench.tool.canRun(stranger),
                     "until a tool says otherwise every command of its manifest can run, and nothing else")
        let before = bench.changes
        bench.current.says(#"{"jsonrpc":"2.0","method":"commands/state","params":{"runnable":["other"]}}"#)
        suite.expect(!bench.tool.canRun(copy) && !bench.tool.canRun(other) && bench.changes == before + 1,
                     "a command the tool leaves out cannot run, one its manifest lacks never can, "
                         + "and whoever lists them is told to look again")
        let sent = bench.current.sent.count
        bench.tool.run(copy)
        suite.expect(bench.current.sent.count == sent && bench.failed == 1,
                     "asking is answered from the last list: nothing is sent to find out, or to run what cannot")
        bench.current.says(#"{"jsonrpc":"2.0","method":"commands/state","params":{"runnable":["copyLatest"]}}"#)
        suite.expect(bench.tool.canRun(copy), "the tool says when it can run again")
    }

    static func commandsThatFail(_ suite: TestSuite) {
        let bench = Bench.running()
        bench.current.refuses(2)
        suite.expect(bench.failed == 1, "a command the tool will not run is reported as failed")
        bench.tool.run(copy)
        bench.clock.advance(by: 2)
        suite.expect(bench.failed == 2 && bench.tool.standing == .running,
                     "and so is one the tool does not answer in time")
        bench.tool.preferencesChanged(["project": .string("web")])
        bench.tool.languageChanged("fr")
        suite.expect(bench.current.sent.suffix(2).map { message -> String in
                         if case .notice(let method, _) = message { return method }
                         return ""
                     } == ["preferences/changed", "language/changed"],
                     "new preference values and a new language reach a tool that runs")
        bench.current.complains("deploys: slow network\n")
        suite.expect(bench.tool.log.entries.map(\.text) == ["starting", "deploys: slow network\n"],
                     "the tool's log holds what the runtime noted and what the tool wrote")
    }

    static func idle(_ suite: TestSuite) {
        let bench = Bench.running()
        bench.current.answers(2)
        bench.prepare = { $0.exitsOnClose = 0 }
        bench.clock.advance(by: 119)
        suite.expect(bench.tool.standing == .running, "a tool is kept for two minutes after its last command")
        bench.tool.run(copy)
        bench.current.answers(3)
        bench.clock.advance(by: 100)
        bench.current.says(#"{"jsonrpc":"2.0","id":1,"method":"notify/beep"}"#)
        bench.clock.advance(by: 119)
        suite.expect(bench.tool.standing == .running && bench.current.signals.isEmpty,
                     "a command, and anything the tool asks of the app, each start the two minutes again")
        bench.current.exitsOnClose = 0
        bench.clock.advance(by: 1)
        suite.expect(bench.current.sent.last == .notice(method: "shutdown", params: nil) && bench.current.inputClosed
                         && bench.tool.standing == .resting && bench.stoppedWorking == 0,
                     "after two idle minutes it is told goodbye and stopped, which is no crash")
        suite.expect(bench.tool.canRun(copy), "a tool stopped for being idle can still run its commands")
        bench.tool.run(copy)
        suite.expect(bench.runs.count == 2 && bench.tool.standing == .starting,
                     "and the next command starts its program again")
    }

    static func crashes(_ suite: TestSuite) {
        let bench = Bench.running()
        let before = bench.changes
        bench.current.ends(1)
        suite.expect(bench.tool.standing == .waiting && !bench.tool.canRun(copy) && bench.stoppedWorking == 1
                         && bench.failed == 1 && bench.changes > before,
                     "a tool whose program ends by itself is held back: its commands cannot run, the one "
                         + "that was waiting failed, and it is said once that the tool stopped working")
        bench.tool.run(copy)
        suite.expect(bench.runs.count == 1 && bench.failed == 2, "nothing starts it during the wait")
        bench.clock.advance(by: 0.9)
        suite.expect(bench.tool.standing == .waiting, "the first wait is one second")
        bench.clock.advance(by: 0.1)
        suite.expect(bench.tool.standing == .resting && bench.tool.canRun(copy) && bench.runs.count == 1,
                     "after it the commands can run again, and the next need starts the program")

        bench.crashOnce()
        bench.clock.advance(by: 1.9)
        suite.expect(bench.runs.count == 2 && bench.tool.standing == .waiting, "the second wait is two seconds")
        bench.clock.advance(by: 0.1)
        suite.expect(bench.tool.standing == .resting, "and then it may start again")

        bench.crashOnce()
        suite.expect(bench.tool.standing == .gaveUp && !bench.tool.canRun(copy) && bench.clock.waiting == 0,
                     "three crashes within a minute and the tool stays stopped")
        bench.clock.advance(by: 3_600)
        bench.tool.run(copy)
        suite.expect(bench.tool.standing == .gaveUp && bench.runs.count == 3 && bench.stoppedWorking == 1,
                     "for as long as the app runs, and the person was told once, not three times")
        suite.expect(bench.tool.log.entries.last?.text == "crashed 3 times within 60 seconds: not started again",
                     "its log says why")
        bench.tool.revive()
        suite.expect(bench.tool.standing == .resting && bench.tool.canRun(copy),
                     "until it is started again by hand, which forgets the crashes")
        bench.crashOnce()
        suite.expect(bench.tool.standing == .waiting, "so that its next crash is a first one")

        let rude = Bench.running()
        rude.prepare = { $0.exitsOnTerminate = 15 }
        rude.current.exitsOnTerminate = 15
        for _ in 0..<19 { rude.current.says("not a message") }
        suite.expect(rude.tool.canRun(copy), "a tool that misbehaves a little carries on")
        rude.current.exitsOnTerminate = nil
        rude.current.says("not a message")
        suite.expect(rude.tool.standing == .stopping && !rude.tool.canRun(copy),
                     "a tool the app is stopping for what it did cannot run a command from that moment")
        rude.current.ends(15)
        suite.expect(rude.tool.standing == .waiting && rude.stoppedWorking == 1
                         && rude.tool.log.entries.last?.text == "stopped by the app: notMessages",
                     "and being stopped by the app counts as a crash")
    }

    static func waits(_ suite: TestSuite) {
        var patient = ToolLimits()
        patient.crashesBeforeGivingUp = 100
        let bench = Bench(limits: patient)
        bench.tool.start()
        var measured: [TimeInterval] = []
        for _ in 0..<11 {
            bench.crashOnce()
            let crashedAt = bench.clock.now
            while bench.tool.standing == .waiting, bench.clock.now - crashedAt < 1_000 { bench.clock.advance(by: 1) }
            measured.append(bench.clock.now - crashedAt)
        }
        suite.expect(measured == [1, 2, 4, 8, 16, 32, 64, 128, 256, 300, 300],
                     "the wait after a crash doubles from one second and stops growing at five minutes")

        bench.tool.run(copy)
        bench.current.greets()
        bench.current.answers(2)
        bench.clock.advance(by: 60)
        bench.current.ends(1)
        bench.clock.advance(by: 1)
        suite.expect(bench.tool.standing == .resting, "a run that stayed up for a minute earns the short wait back")
    }

    static func startsWithTheApp(_ suite: TestSuite) {
        let bench = Bench(activation: "onLaunch")
        bench.tool.start()
        suite.expect(bench.runs.count == 1 && bench.tool.standing == .starting,
                     "a tool that starts with the app starts its program as soon as the host starts it")
        bench.current.greets()
        bench.clock.advance(by: 3_600)
        suite.expect(bench.tool.standing == .running && !bench.current.inputClosed,
                     "and is kept running however long nothing is asked of it")
        bench.current.ends(1)
        bench.clock.advance(by: 0.9)
        suite.expect(bench.runs.count == 1 && bench.tool.standing == .waiting, "after a crash it waits like any other")
        bench.clock.advance(by: 0.1)
        suite.expect(bench.runs.count == 2 && bench.tool.standing == .starting,
                     "and is then started again without being asked")
    }

    static func heldCommands(_ suite: TestSuite) {
        var limits = ToolLimits()
        limits.commandsHeld = 2
        let bench = Bench(limits: limits)
        bench.tool.start()
        bench.tool.run(copy)
        bench.tool.run(copy)
        suite.expect(bench.runs.count == 1 && bench.failed == 0, "commands asked for while the program starts wait")
        bench.tool.run(copy)
        suite.expect(bench.failed == 1, "up to a number; one more fails at once")
        bench.current.greets()
        suite.expect(bench.commandsSent == ["copyLatest", "copyLatest"], "and are sent once it is greeted")

        let broken = Bench()
        broken.prepare = { $0.starts = false }
        broken.tool.start()
        broken.tool.run(copy)
        suite.expect(broken.runs.count == 1 && broken.failed == 1 && broken.tool.standing == .waiting
                         && broken.stoppedWorking == 1
                         && broken.tool.log.entries.map(\.text) == ["starting", "ended by itself: it could not be started"],
                     "a program that cannot be started fails the command that wanted it, and counts as a crash")
    }

    static func stopping(_ suite: TestSuite) {
        let bench = Bench.running(activation: "onLaunch")
        bench.tool.stop()
        bench.tool.stop()
        suite.expect(bench.current.sent.last == .notice(method: "shutdown", params: nil)
                         && bench.tool.standing == .off && !bench.tool.canRun(copy),
                     "the host stopping a tool says goodbye to its program, and its commands cannot run")
        bench.tool.start()
        suite.expect(bench.runs.count == 1, "started again at once, it does not start a second program beside the first")
        bench.current.ends(0)
        suite.expect(bench.runs.count == 2 && bench.tool.standing == .starting && bench.stoppedWorking == 0,
                     "the new one starts when the old one has gone, and a stop is no crash")

        let removed = Bench.running()
        removed.forget()
        removed.clock.advance(by: 2)
        removed.clock.advance(by: 1)
        suite.expect(removed.current.signals == ["terminate", "kill"],
                     "a tool nobody holds any more still has its program ended, however long it will not leave")

        let crashed = Bench.running()
        crashed.current.ends(1)
        crashed.tool.stop()
        crashed.clock.advance(by: 10)
        crashed.tool.start()
        suite.expect(crashed.tool.standing == .resting && crashed.runs.count == 1 && crashed.clock.waiting == 0,
                     "stopping a tool that was waiting after a crash ends the wait")
    }

    static func quitting(_ suite: TestSuite) {
        let bench = Bench.running()
        suite.expect(!bench.tool.hasEnded, "a tool whose program runs has not ended")
        bench.tool.stop()
        suite.expect(!bench.tool.hasEnded && bench.current.signals.isEmpty, "nor one that was only told goodbye")
        bench.tool.escalate()
        bench.current.exitsOnKill = 9
        bench.tool.escalate()
        suite.expect(bench.current.signals == ["terminate", "kill"] && bench.tool.hasEnded,
                     "at quit the host ends it a step harder each time, until it has")
    }
}

extension ExternalToolTests {
    /// A panel of an outside tool: opening one starts the program as a
    /// command does; while one is open the tool is not stopped for being
    /// idle; and every panel ends with the program.
    static func panels(_ suite: TestSuite) {
        let bench = Bench()
        bench.tool.start()
        var first: Result<JSONValue, ToolLink.Failure>?
        bench.tool.open(panel: "deploys") { first = $0 }
        suite.expect(bench.runs.count == 1 && bench.tool.standing == .starting && bench.tool.isOpen(panel: "deploys"),
                     "opening a panel of a tool that rests starts its program")
        bench.current.greets()
        suite.expect(bench.current.sent.last == .request(id: .number(2), method: "ui/open",
                                                         params: .object(["panel": .string("deploys")])),
                     "once it has answered initialize it is asked for the panel")
        bench.current.answers(2, #"{"tree":{"blocks":[]}}"#)
        suite.expect(first == .success(.object(["tree": .object(["blocks": .array([])])])),
                     "the first page is handed back")

        bench.current.says(#"{"jsonrpc":"2.0","method":"ui/render","params":{"panel":"deploys","tree":{"blocks":[]}}}"#)
        suite.expect(bench.rendered == ["deploys"], "a page the tool sends is handed on with its panel")

        bench.clock.advance(by: ToolLimits.standard.idleStop * 3)
        suite.expect(bench.tool.standing == .running && bench.current.signals.isEmpty,
                     "while a panel is open the tool is not stopped for being idle")

        var answer: Result<JSONValue, ToolLink.Failure>?
        bench.tool.event(UIEventParams(panel: "settings", event: .tap)) { answer = $0 }
        suite.expect(answer == .failure(.notReady) && bench.current.sent.count == 2,
                     "an event for a panel that is not open is not sent")
        bench.tool.event(UIEventParams(panel: "deploys", block: "again", event: .tap)) { answer = $0 }
        bench.current.answers(3, #"{"keep":true}"#)
        suite.expect(answer == .success(.object(["keep": .bool(true)])), "an event for an open panel is sent and answered")

        bench.tool.close(panel: "deploys")
        suite.expect(!bench.tool.isOpen(panel: "deploys")
                         && bench.current.sent.last == .notice(method: "ui/close", params: .object(["panel": .string("deploys")])),
                     "closing it tells the tool")
        bench.current.exitsOnClose = 0
        bench.clock.advance(by: ToolLimits.standard.idleStop)
        suite.expect(bench.tool.standing == .resting && bench.runsEnded == 1,
                     "once no panel is open the idle stop applies again, and the run's end is said")

        let crash = Bench()
        crash.tool.start()
        crash.tool.open(panel: "deploys") { _ in }
        crash.current.greets()
        crash.current.ends(1)
        suite.expect(!crash.tool.isOpen(panel: "deploys") && crash.runsEnded == 1,
                     "a panel ends with its tool's program")

        let stopped = Bench()
        stopped.tool.start()
        var held: Result<JSONValue, ToolLink.Failure>?
        stopped.tool.open(panel: "deploys") { held = $0 }
        stopped.tool.stop()
        suite.expect(held == .failure(.notReady) && !stopped.tool.isOpen(panel: "deploys"),
                     "a panel that waited for a program that was then stopped is told so")
        var off: Result<JSONValue, ToolLink.Failure>?
        stopped.tool.open(panel: "deploys") { off = $0 }
        suite.expect(off == .failure(.notReady) && stopped.runs.count == 1,
                     "a tool the host has stopped opens no panel and starts nothing")
    }
}
