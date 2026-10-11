// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import Foundation
import VitruvianCore
import VitruvianServices
import VitruvianToolProtocol

/// One link to a tool, against a tool that is no program and a clock moved
/// by hand: nothing here starts a process or waits.
enum ToolLinkTests {
    static func run(_ suite: TestSuite) {
        greeting(suite)
        badGreetings(suite)
        commands(suite)
        deadlines(suite)
        whatAToolAsks(suite)
        notices(suite)
        goodbye(suite)
        endings(suite)
        limits(suite)
    }

    /// A link, its tool and its clock, and everything the link reported.
    final class Bench {
        let tool = FakeTool()
        let clock = ManualToolClock()
        var states: [ToolLink.State] = []
        var ends: [ToolLink.End] = []
        var runnable: [[String]] = []
        var logged: [ToolLog.Entry] = []
        var asked = 0
        /// What the tool asked of the app, and the way to answer each.
        var served: [(method: ToolMethod, params: JSONValue?, reply: ToolLink.Reply)] = []
        private(set) var link: ToolLink!

        init(limits: ToolLimits = .standard) {
            link = ToolLink(
                transport: tool, clock: clock, limits: limits,
                hello: InitializeParams(protocolVersions: ["1"], language: "fr", dataFolder: "/data"),
                serve: { [unowned self] method, params, reply in served.append((method, params, reply)) },
                events: .init(onChange: { [unowned self] in states.append(link.state) },
                              onRunnable: { [unowned self] in runnable.append($0) },
                              onLog: { [unowned self] in logged.append(.init(source: $1, text: $0)) },
                              onAsked: { [unowned self] in asked += 1 },
                              onEnd: { [unowned self] in ends.append($0) }))
        }

        /// A link that has started and been greeted.
        static func ready(limits: ToolLimits = .standard) -> Bench {
            let bench = Bench(limits: limits)
            bench.link.start()
            bench.tool.greets()
            return bench
        }

        /// Runs a command and gives back what the link said of it, when it
        /// has said anything.
        func run(_ command: String = "hello") -> () -> Result<Void, ToolLink.Failure>? {
            var outcome: Result<Void, ToolLink.Failure>?
            var times = 0
            link.run(command) {
                outcome = $0
                times += 1
            }
            return { times > 1 ? .failure(.notReady) : outcome }
        }
    }

    static func ok(_ outcome: Result<Void, ToolLink.Failure>?) -> Bool {
        if case .success? = outcome { return true }
        return false
    }

    static func failure(_ outcome: Result<Void, ToolLink.Failure>?) -> ToolLink.Failure? {
        if case .failure(let failure)? = outcome { return failure }
        return nil
    }

    static func error(_ code: Int, _ message: String) -> RPCErrorObject {
        RPCErrorObject(code: code, message: message)
    }

    static func greeting(_ suite: TestSuite) {
        let bench = Bench()
        suite.expect(bench.link.state == .idle && bench.tool.started == 0, "a link starts nothing until it is started")
        bench.link.start()
        bench.link.start()
        let hello = JSONValue.object(["protocolVersions": .array([.string("1")]), "language": .string("fr"),
                                      "dataFolder": .string("/data")])
        suite.expect(bench.tool.started == 1 && bench.link.state == .starting
                         && bench.tool.sent == [.request(id: .number(1), method: "initialize", params: hello)],
                     "starting a link starts the program once and greets it: versions, language, data folder")
        bench.tool.greets()
        suite.expect(bench.link.state == .ready && bench.link.toolVersion == "0.1.0"
                         && bench.states == [.starting, .ready] && bench.ends.isEmpty,
                     "a tool that picks an offered version is ready, and its own version is kept")
        bench.clock.advance(by: 60)
        suite.expect(bench.link.state == .ready && bench.tool.signals.isEmpty,
                     "a greeting that came in time is not timed out later")

        let unstartable = Bench()
        unstartable.tool.starts = false
        unstartable.link.start()
        suite.expect(unstartable.link.state == .ended && unstartable.ends == [.exited(nil)]
                         && unstartable.tool.sent.isEmpty,
                     "a program that cannot be started ends the link at once, with no status")
    }

    static func badGreetings(_ suite: TestSuite) {
        let cases: [(String, (Bench) -> Void, ToolLink.Fault)] = [
            ("a tool that picks a version the app did not offer is stopped",
             { $0.tool.greets(protocolVersion: "2") }, .badHandshake),
            ("a tool that refuses the greeting is stopped", { $0.tool.refuses(1, code: -32602) }, .badHandshake),
            ("a tool whose greeting is not a greeting is stopped", { $0.tool.answers(1, #"{"ok":true}"#) },
             .badHandshake),
            ("a tool that says something before its greeting is stopped",
             { $0.tool.says(#"{"jsonrpc":"2.0","method":"commands/state","params":{"runnable":[]}}"#) },
             .badHandshake),
            ("a tool that asks something before its greeting is stopped",
             { $0.tool.says(#"{"jsonrpc":"2.0","id":1,"method":"notify/beep"}"#) }, .badHandshake),
            ("a tool that does not greet within ten seconds is stopped", { $0.clock.advance(by: 10) }, .silent),
        ]
        for (message, misbehave, fault) in cases {
            let bench = Bench()
            bench.tool.exitsOnTerminate = 15
            bench.link.start()
            bench.clock.advance(by: 9.5)
            let before = bench.link.state
            misbehave(bench)
            suite.expect(before == .starting && bench.ends == [.misbehaved(fault)] && bench.link.state == .ended
                             && bench.tool.inputClosed && bench.tool.signals == ["terminate"]
                             && bench.served.isEmpty && bench.tool.sent.count == 1,
                         message)
        }
    }

    static func commands(_ suite: TestSuite) {
        let early = Bench()
        early.link.start()
        suite.expect(failure(early.run()()) == .notReady && early.tool.sent.count == 1,
                     "a command is not sent before the greeting is done")

        let bench = Bench.ready()
        let first = bench.run("copyLatest")
        suite.expect(bench.tool.sent.last == .request(id: .number(2), method: "command/run",
                                                      params: .object(["command": .string("copyLatest")]))
                         && first() == nil,
                     "a command is sent by its bare id, under the next request id")
        bench.tool.answers(2)
        suite.expect(ok(first()), "a command the tool answers is done")

        let second = bench.run()
        bench.tool.refuses(3)
        suite.expect(failure(second()) == .refused(error(-32010, "no")),
                     "a command the tool will not run fails with the tool's reason")

        let third = bench.run()
        let fourth = bench.run()
        bench.tool.answers(5)
        bench.tool.answers(4)
        suite.expect(ok(third()) && ok(fourth()) && bench.link.dropped == 0,
                     "answers are matched to requests by id, in whatever order they come")
        bench.tool.answers(4)
        suite.expect(bench.link.dropped == 1, "an answer to nothing the app asked is dropped and counted")

        bench.link.preferencesChanged(["project": .string("web")])
        bench.link.languageChanged("pt-BR")
        suite.expect(bench.tool.sent.suffix(2)
                         == [.notice(method: "preferences/changed",
                                     params: .object(["values": .object(["project": .string("web")])])),
                             .notice(method: "language/changed", params: .object(["language": .string("pt-BR")]))],
                     "new preference values and a new language are sent as notices")
        let quiet = Bench()
        quiet.link.start()
        quiet.link.languageChanged("fr")
        suite.expect(quiet.tool.sent.count == 1, "and not before the greeting is done")
    }

    static func deadlines(_ suite: TestSuite) {
        let bench = Bench.ready()
        let slow = bench.run()
        bench.clock.advance(by: 1.9)
        suite.expect(slow() == nil, "a command has two seconds to be answered")
        bench.clock.advance(by: 0.1)
        suite.expect(failure(slow()) == .noAnswer && bench.link.state == .ready,
                     "a command with no answer in time fails, and the link carries on")
        bench.tool.answers(2)
        suite.expect(failure(slow()) == .noAnswer && bench.link.dropped == 0,
                     "an answer that comes late changes nothing, and is not counted as nonsense")

        _ = bench.run()
        bench.clock.advance(by: 2)
        let answered = bench.run()
        bench.tool.answers(4)
        suite.expect(ok(answered()) && bench.link.state == .ready, "an answer in time clears the count of misses")
        for _ in 0..<2 {
            _ = bench.run()
            bench.clock.advance(by: 2)
        }
        suite.expect(bench.link.state == .ready && bench.ends.isEmpty, "two misses in a row are put up with")
        let last = bench.run()
        bench.tool.exitsOnTerminate = 15
        bench.clock.advance(by: 2)
        suite.expect(failure(last()) == .noAnswer && bench.ends == [.misbehaved(.silent)]
                         && bench.tool.signals == ["terminate"],
                     "three requests in a row with no answer: the tool has hung, and is stopped")
    }

    static func whatAToolAsks(_ suite: TestSuite) {
        let bench = Bench.ready()
        bench.tool.says(#"{"jsonrpc":"2.0","id":7,"method":"notify/hud","params":{"icon":"link","message":"Copied"}}"#)
        suite.expect(bench.served.count == 1 && bench.served[0].method == .notifyHUD
                         && bench.served[0].params == .object(["icon": .string("link"), "message": .string("Copied")])
                         && bench.asked == 1 && bench.tool.sent.count == 1,
                     "what a tool asks is handed on, with its params, and is not answered until the app has an answer")
        bench.served[0].reply(.success(.object([:])))
        bench.served[0].reply(.success(.object(["again": .bool(true)])))
        suite.expect(bench.tool.sent.dropFirst() == [.result(id: .number(7), value: .object([:]))],
                     "the answer goes back under the tool's id, once")

        bench.tool.says(#"{"jsonrpc":"2.0","id":"a","method":"clipboard/readText"}"#)
        bench.served[1].reply(.failure(RefusalCode.notInUses.error(service: .clipboardRead)))
        suite.expect(bench.tool.sent.last
                         == .failure(id: .string("a"),
                                     error: RPCErrorObject(code: -32001, message: "not listed in uses",
                                                           data: .object(["service": .string("clipboard.read")]))),
                     "a refusal goes back as a failure with its code and what it names; an id may be text")

        let before = bench.served.count
        for (line, why) in [
            (#"{"jsonrpc":"2.0","id":8,"method":"island/show"}"#, "a request the app does not know"),
            (#"{"jsonrpc":"2.0","id":8,"method":"command/run","params":{"command":"x"}}"#,
             "a request only the app makes"),
            (#"{"jsonrpc":"2.0","id":8,"method":"log","params":{"message":"x"}}"#, "a notice sent as a request"),
        ] {
            bench.tool.says(line)
            suite.expect(bench.tool.sent.last == .failure(id: .number(8), error: error(-32601, "unknown method"))
                             && bench.served.count == before,
                         "\(why) is answered with method not found, and nothing is done")
        }

        bench.tool.says(#"{"jsonrpc":"2.0","id":9,"method":"notify/beep"}"#)
        bench.tool.says(#"{"jsonrpc":"2.0","id":9,"method":"notify/beep"}"#)
        suite.expect(bench.served.count == before + 1
                         && bench.tool.sent.last
                         == .failure(id: .number(9), error: error(-32600, "this id is still being answered")),
                     "a second request under an id still being answered is refused, and the first stands")
        bench.served[before].reply(.success(.object([:])))
        suite.expect(bench.tool.sent.last == .result(id: .number(9), value: .object([:])), "which is then answered")

        bench.tool.says(#"{"jsonrpc":"2.0","id":10,"method":"clipboard/readText"}"#)
        let sent = bench.tool.sent.count
        bench.served[before + 1].reply(.success(.object(["text": .string(String(repeating: "x", count: 1_100_000))])))
        suite.expect(bench.tool.sent.count == sent + 1
                         && bench.tool.sent.last
                         == .failure(id: .number(10), error: error(-32603, "the answer is too long to send")),
                     "an answer over 1 MB is not sent; the tool is told it failed")

        bench.tool.says(#"{"jsonrpc":"2.0","id":11,"method":"notify/beep"}"#)
        bench.link.shutdown()
        let afterGoodbye = bench.tool.sent.count
        bench.served[before + 2].reply(.success(.object([:])))
        suite.expect(bench.tool.sent.count == afterGoodbye, "an answer that is ready after goodbye is not sent")
    }

    static func notices(_ suite: TestSuite) {
        let bench = Bench.ready()
        bench.tool.says(#"{"jsonrpc":"2.0","method":"commands/state","params":{"runnable":["hello","other"]}}"#)
        bench.tool.says(#"{"jsonrpc":"2.0","method":"commands/state","params":{"runnable":[]}}"#)
        suite.expect(bench.runnable == [["hello", "other"], []],
                     "a tool says which of its commands can run now, the whole list each time")
        bench.tool.says(#"{"jsonrpc":"2.0","method":"log","params":{"message":"started"}}"#)
        bench.tool.complains("warning: slow disk\n")
        suite.expect(bench.logged == [.init(source: .message, text: "started"),
                                      .init(source: .standardError, text: "warning: slow disk\n")],
                     "a log message and the tool's standard error both go to its log")
        bench.tool.says(#"{"jsonrpc":"2.0","method":"island/notice","params":{"text":"later"}}"#)
        suite.expect(bench.link.dropped == 0 && bench.link.state == .ready && bench.asked == 0,
                     "a notice the app does not know is ignored: a later protocol may add one")
        bench.tool.says(#"{"jsonrpc":"2.0","method":"commands/state","params":{"runnable":"all"}}"#)
        bench.tool.says(#"{"jsonrpc":"2.0","method":"log"}"#)
        suite.expect(bench.link.dropped == 2 && bench.runnable.count == 2 && bench.logged.count == 2,
                     "a notice the app knows, with params it cannot read, is dropped and counted")
    }

    static func goodbye(_ suite: TestSuite) {
        let bench = Bench.ready()
        let pending = bench.run()
        bench.tool.exitsOnClose = 0
        bench.link.shutdown()
        suite.expect(bench.tool.sent.last == .notice(method: "shutdown", params: nil) && bench.tool.inputClosed
                         && failure(pending()) == .notReady,
                     "stopping says goodbye and closes the tool's input, and a command still waiting fails")
        suite.expect(bench.ends == [.stopped] && bench.states == [.starting, .ready, .stopping, .ended]
                         && bench.tool.signals.isEmpty && bench.clock.waiting == 0,
                     "a tool that then exits was stopped, with no signal sent and no timer left")

        let stubborn = Bench.ready()
        stubborn.link.shutdown()
        stubborn.link.shutdown()
        stubborn.clock.advance(by: 1.9)
        suite.expect(stubborn.tool.signals.isEmpty && stubborn.link.state == .stopping,
                     "a tool has two seconds to leave after goodbye")
        stubborn.clock.advance(by: 0.1)
        suite.expect(stubborn.tool.signals == ["terminate"], "then it is asked to end")
        stubborn.clock.advance(by: 1)
        suite.expect(stubborn.tool.signals == ["terminate", "kill"] && stubborn.ends.isEmpty,
                     "and one second later it is killed")
        stubborn.clock.advance(by: 1)
        suite.expect(stubborn.ends == [.stopped] && stubborn.link.state == .ended && stubborn.clock.waiting == 0,
                     "a link whose program never reports its end is over all the same, a second after the kill")
        stubborn.tool.ends(9)
        suite.expect(stubborn.ends == [.stopped], "and ends once")

        let quitting = Bench.ready()
        quitting.link.shutdown()
        suite.expect(!quitting.link.hasEnded, "at quit a tool that is still running has not ended")
        quitting.link.escalate()
        suite.expect(quitting.tool.signals == ["terminate"], "the host can take the next step itself: ask it to end")
        quitting.tool.exitsOnKill = 9
        quitting.link.escalate()
        suite.expect(quitting.tool.signals == ["terminate", "kill"] && quitting.link.hasEnded
                         && quitting.ends == [.stopped],
                     "and the step after: kill it, after which it has ended")

        let unstarted = Bench()
        unstarted.link.shutdown()
        suite.expect(unstarted.ends == [.stopped] && unstarted.tool.started == 0 && unstarted.link.hasEnded,
                     "stopping a link that never started starts nothing")
    }

    static func endings(_ suite: TestSuite) {
        let bench = Bench.ready()
        let pending = bench.run()
        bench.tool.ends(3)
        suite.expect(bench.ends == [.exited(3)] && bench.link.state == .ended && failure(pending()) == .notReady
                         && bench.clock.waiting == 0,
                     "a tool that exits by itself ends the link with its status, and what was waiting fails")
        bench.tool.says(#"{"jsonrpc":"2.0","id":7,"method":"notify/beep"}"#)
        suite.expect(bench.served.isEmpty && failure(bench.run()()) == .notReady,
                     "a link that has ended hears nothing and sends nothing")

        let deaf = Bench.ready()
        deaf.tool.reads = false
        deaf.tool.exitsOnTerminate = 15
        let unsent = deaf.run()
        suite.expect(failure(unsent()) == .notReady && deaf.ends == [.misbehaved(.notReading)]
                         && deaf.tool.signals == ["terminate"],
                     "a tool that does not read what the app writes is stopped")

        let asked = Bench.ready()
        asked.tool.reads = false
        asked.link.shutdown()
        asked.tool.ends(0)
        suite.expect(asked.ends == [.stopped], "a tool the app asked to stop was stopped, whatever else it did")
    }

    static func limits(_ suite: TestSuite) {
        let long = Bench.ready()
        long.tool.exitsOnTerminate = 15
        long.tool.writes(Data(repeating: 0x78, count: WireLimits.maxLineBytes + 1))
        suite.expect(long.ends == [.misbehaved(.lineTooLong)] && long.tool.inputClosed
                         && long.tool.signals == ["terminate"],
                     "a line over 1 MB stops the tool, before its line break ever comes")

        let junk = Bench.ready()
        junk.tool.exitsOnTerminate = 15
        for _ in 0..<19 { junk.tool.says("not a message") }
        suite.expect(junk.link.state == .ready && junk.link.dropped == 19,
                     "a line that is not a message is dropped and counted, and the link carries on")
        junk.tool.says("not a message")
        suite.expect(junk.ends == [.misbehaved(.notMessages)], "twenty of them within a minute stop the tool")

        let slow = Bench.ready()
        for _ in 0..<19 { slow.tool.says("not a message") }
        slow.clock.advance(by: 60)
        for _ in 0..<19 { slow.tool.says(#"{"jsonrpc":"2.0","id":99,"result":{}}"#) }
        suite.expect(slow.link.state == .ready && slow.link.dropped == 38,
                     "nineteen a minute, lines or answers to nothing, is put up with for as long as it lasts")

        let note = #"{"jsonrpc":"2.0","method":"log","params":{"message":"x"}}"#
        let flood = Bench.ready()
        flood.tool.exitsOnTerminate = 15
        for _ in 0..<4 {
            for _ in 0..<201 { flood.tool.says(note) }
            flood.clock.advance(by: 1)
        }
        for _ in 0..<200 { flood.tool.says(note) }
        suite.expect(flood.link.state == .ready && flood.ends.isEmpty,
                     "four seconds of more than 200 messages, and a fifth of exactly 200, are put up with")
        flood.tool.says(note)
        suite.expect(flood.ends == [.misbehaved(.flood)] && flood.tool.signals == ["terminate"],
                     "more than 200 messages a second for five seconds in a row is a flood, and stops the tool")

        let bursty = Bench.ready()
        for _ in 0..<3 {
            for _ in 0..<4 {
                for _ in 0..<201 { bursty.tool.says(note) }
                bursty.clock.advance(by: 1)
            }
            bursty.clock.advance(by: 1)
        }
        suite.expect(bursty.link.state == .ready && bursty.ends.isEmpty,
                     "a quiet second breaks the run: bursts of four busy seconds are not a flood")

        var few = ToolLimits()
        few.messagesPerSecond = 10
        let greedy = Bench.ready(limits: few)
        greedy.clock.advance(by: 1)
        for id in 0..<15 { greedy.tool.says(#"{"jsonrpc":"2.0","id":\#(id),"method":"notify/beep"}"#) }
        suite.expect(greedy.served.count == 10
                         && greedy.tool.sent.suffix(5)
                         == (10..<15).map { .failure(id: .number($0), error: error(-32004, "not available right now")) },
                     "past the limit for a second, what a tool asks is refused as not available and nothing is done")
        greedy.clock.advance(by: 1)
        greedy.tool.says(#"{"jsonrpc":"2.0","id":15,"method":"notify/beep"}"#)
        suite.expect(greedy.served.count == 11, "the next second starts afresh")
    }
}
