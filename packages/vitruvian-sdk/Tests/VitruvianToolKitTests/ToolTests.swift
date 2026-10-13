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

import VitruvianToolKit

/// A tool's link, made of two files: what the app will have sent, written
/// before the tool starts, and what the tool writes. A file never blocks,
/// and its end is the end of the link, so no test here can wait for long.
private final class Bench {
    let folder: URL
    private var sent = ""

    init() {
        folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("vitruvian-tool-kit-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: folder)
    }

    /// One line the app sends.
    @discardableResult
    func app(_ line: String) -> Bench {
        sent += line + "\n"
        return self
    }

    func hello(versions: String = #"["1"]"#) -> Bench {
        app(#"{"jsonrpc":"2.0","id":"hello","method":"initialize","params":{"protocolVersions":\#(versions),"language":"de-DE","dataFolder":"/tmp/kit-data"}}"#)
    }

    func run(_ command: String, id: Int) -> Bench {
        app(#"{"jsonrpc":"2.0","id":\#(id),"method":"command/run","params":{"command":"\#(command)"}}"#)
    }

    func goodbye() -> Bench {
        app(#"{"jsonrpc":"2.0","method":"shutdown"}"#)
    }

    /// Makes the tool over the two files. `build` adds its commands.
    func tool(_ build: (Tool) -> Void = { _ in }) throws -> Tool {
        let input = folder.appendingPathComponent("from-app")
        let output = folder.appendingPathComponent("to-app")
        try Data(sent.utf8).write(to: input)
        try Data().write(to: output)
        let tool = Tool(version: "9.9.9", input: try FileHandle(forReadingFrom: input),
                        output: try FileHandle(forWritingTo: output))
        build(tool)
        return tool
    }

    /// What the tool wrote, a message a line.
    func written() throws -> [RPCMessage] {
        let text = try String(contentsOf: folder.appendingPathComponent("to-app"), encoding: .utf8)
        return try text.split(separator: "\n").map { try LineFraming.message(from: Data($0.utf8)) }
    }
}

final class ToolTests: XCTestCase {
    private let done = JSONValue.object([:])

    func testEveryRequestAToolMaySendHasAType() {
        let wanted = ToolMethod.allCases.filter { $0.sender == .tool && $0.isAnswered }
        XCTAssertEqual(Set(AppRequests.methods), Set(wanted))
        XCTAssertEqual(AppRequests.methods.count, 11, "each request once")
    }

    func testHelloACommandAndGoodbye() throws {
        let bench = Bench().hello().run("hello", id: 2).goodbye()
        var ran = 0
        var seen: [String] = []
        let tool = try bench.tool { tool in
            tool.command("hello") { app in
                ran += 1
                seen = [app.language, app.dataFolder.path]
            }
        }
        XCTAssertEqual(tool.serve(), 0)
        XCTAssertEqual(ran, 1)
        XCTAssertEqual(seen, ["de-DE", "/tmp/kit-data"], "what the app said at hello is the handler's to read")
        XCTAssertEqual(try bench.written(), [
            .result(id: .string("hello"), value: .object(["protocolVersion": .string("1"),
                                                           "toolVersion": .string("9.9.9")])),
            .result(id: .number(2), value: done),
        ])
    }

    func testAHandlerCallsTheAppAndReadsTheAnswer() throws {
        let bench = Bench().hello().run("copy", id: 2)
            .app(#"{"jsonrpc":"2.0","id":1,"result":{"text":"from the clipboard"}}"#)
            .app(#"{"jsonrpc":"2.0","id":2,"result":{}}"#)
            .goodbye()
        var read: String?
        let tool = try bench.tool { tool in
            tool.command("copy") { app in
                read = try app.clipboardText()
                try app.showMessage("Read it", icon: "doc.on.clipboard")
            }
        }
        XCTAssertEqual(tool.serve(), 0)
        XCTAssertEqual(read, "from the clipboard")
        let written = try bench.written()
        XCTAssertEqual(written.count, 4)
        XCTAssertEqual(written[1], .request(id: .number(1), method: "clipboard/readText", params: done))
        XCTAssertEqual(written[2], .request(id: .number(2), method: "notify/hud",
                                            params: .object(["icon": .string("doc.on.clipboard"),
                                                             "message": .string("Read it")])))
        XCTAssertEqual(written[3], .result(id: .number(2), value: done), "the command is answered last")
    }

    func testAnAnswerToAnotherRequestIsNotTakenForThisOne() throws {
        // Two answers nobody waits for, as a call that gave up would leave
        // behind, come before the one the handler waits for.
        let bench = Bench().hello().run("copy", id: 2)
            .app(#"{"jsonrpc":"2.0","id":98,"error":{"code":-32004,"message":"not available right now"}}"#)
            .app(#"{"jsonrpc":"2.0","id":99,"result":{"text":"somebody else's"}}"#)
            .app(#"{"jsonrpc":"2.0","id":1,"result":{"text":"mine"}}"#)
            .goodbye()
        var read: String?
        let tool = try bench.tool { $0.command("copy") { read = try $0.clipboardText() } }
        XCTAssertEqual(tool.serve(), 0)
        XCTAssertEqual(read, "mine")
        XCTAssertEqual(try bench.written().last, .result(id: .number(2), value: done))
    }

    func testARefusalTheHandlerLetsThroughRefusesTheCommand() throws {
        let bench = Bench().hello().run("hello", id: 7)
            .app(#"{"jsonrpc":"2.0","id":1,"error":{"code":-32001,"message":"not listed in uses","data":{"service":"notify"}}}"#)
            .goodbye()
        let tool = try bench.tool { $0.command("hello") { try $0.showMessage("Hello") } }
        XCTAssertEqual(tool.serve(), 0)
        guard case .failure(let id, let error)? = try bench.written().last else { return XCTFail("no failure") }
        XCTAssertEqual(id, .number(7))
        XCTAssertEqual(error.code, -32010)
        XCTAssertEqual(error.data?["code"], .number(-32001), "the app's reason goes with it, for the log")
    }

    func testAHandlerMayCatchARefusalAndCarryOn() throws {
        let bench = Bench().hello().run("hello", id: 7)
            .app(#"{"jsonrpc":"2.0","id":1,"error":{"code":-32004,"message":"not available right now"}}"#)
            .goodbye()
        var why: RefusalCode?
        let tool = try bench.tool { tool in
            tool.command("hello") { app in
                do {
                    try app.beep()
                } catch let error as RPCErrorObject {
                    why = RefusalCode(error)
                }
            }
        }
        XCTAssertEqual(tool.serve(), 0)
        XCTAssertEqual(why, .unavailable)
        XCTAssertEqual(try bench.written().last, .result(id: .number(7), value: done))
    }

    func testACommandThatWillNotRunSaysWhy() throws {
        let bench = Bench().hello().run("hello", id: 3).run("missing", id: 4)
            .app(#"{"jsonrpc":"2.0","id":5,"method":"island/draw"}"#)
            .goodbye()
        let tool = try bench.tool { $0.command("hello") { _ in throw CommandRefused("nothing is selected") } }
        XCTAssertEqual(tool.serve(), 0)
        XCTAssertEqual(Array(try bench.written().dropFirst()), [
            .failure(id: .number(3), error: RPCErrorObject(code: -32010, message: "nothing is selected")),
            .failure(id: .number(4), error: RPCErrorObject(code: -32602, message: "no such command")),
            .failure(id: .number(5), error: RPCErrorObject(code: -32601, message: "method not found")),
        ])
    }

    func testWhatComesWhileAHandlerWaitsIsHandledAfterIt() throws {
        let bench = Bench().hello().run("first", id: 2)
            .app(#"{"jsonrpc":"2.0","method":"language/changed","params":{"language":"fr"}}"#)
            .run("second", id: 3)
            .app(#"{"jsonrpc":"2.0","id":1,"result":{}}"#)
            .app(#"{"jsonrpc":"2.0","id":2,"result":{}}"#)
            .goodbye()
        var order: [String] = []
        let tool = try bench.tool { tool in
            tool.command("first") { app in
                try app.beep()
                order.append("first in \(app.language)")
            }
            tool.command("second") { app in
                try app.beep()
                order.append("second in \(app.language)")
            }
        }
        XCTAssertEqual(tool.serve(), 0)
        XCTAssertEqual(order, ["first in de-DE", "second in fr"], "kept in the order it came")
        let answers = try bench.written().compactMap { message -> RPCID? in
            if case .result(let id, _) = message { return id }
            return nil
        }
        XCTAssertEqual(answers, [.string("hello"), .number(2), .number(3)])
    }

    func testGoodbyeWhileAHandlerWaitsEndsTheWait() throws {
        let bench = Bench().hello().run("hello", id: 2).goodbye()
        var thrown: AppUnreachable?
        let tool = try bench.tool { tool in
            tool.command("hello") { app in
                do {
                    try app.beep()
                } catch let error as AppUnreachable {
                    thrown = error
                    throw error
                }
            }
        }
        XCTAssertEqual(tool.serve(), 0)
        XCTAssertEqual(thrown, .linkClosed)
        guard case .failure(.number(2)?, let error)? = try bench.written().last else { return XCTFail("no failure") }
        XCTAssertEqual(error.code, -32010)
    }

    func testTheLinkEndingEndsTheWaitAndTheLoop() throws {
        let bench = Bench().hello().run("hello", id: 2)
        var thrown: AppUnreachable?
        let tool = try bench.tool { tool in
            tool.command("hello") { app in
                do {
                    try app.beep()
                } catch let error as AppUnreachable {
                    thrown = error
                }
            }
        }
        XCTAssertEqual(tool.serve(), 0, "the app going away is not the tool's failure")
        XCTAssertEqual(thrown, .linkClosed)
    }

    func testACallGivesUpWhenNoAnswerComes() throws {
        // A pipe, so that the link stays open with nothing on it.
        var ends: [Int32] = [0, 0]
        XCTAssertEqual(pipe(&ends), 0)
        let bench = Bench()
        let output = bench.folder.appendingPathComponent("to-app")
        try Data().write(to: output)
        let lines = #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersions":["1"],"language":"en","dataFolder":"/tmp"}}"#
            + "\n" + #"{"jsonrpc":"2.0","id":2,"method":"command/run","params":{"command":"hello"}}"# + "\n"
        XCTAssertEqual(write(ends[1], lines, lines.utf8.count), lines.utf8.count)
        let tool = Tool(version: "1", input: FileHandle(fileDescriptor: ends[0], closeOnDealloc: true),
                        output: try FileHandle(forWritingTo: output))
        tool.answerSeconds = 0.05
        var thrown: AppUnreachable?
        tool.command("hello") { app in
            do {
                try app.beep()
            } catch let error as AppUnreachable {
                thrown = error
            }
            // The app goes away, which ends the loop.
            close(ends[1])
        }
        let started = Date()
        XCTAssertEqual(tool.serve(), 0)
        XCTAssertEqual(thrown, .noAnswer(seconds: 0.05))
        XCTAssertLessThan(Date().timeIntervalSince(started), 5)
    }

    func testTheNewestVersionBothSpeakIsPicked() throws {
        for (offered, picked) in [(#"["1","2"]"#, "2"), (#"["1"]"#, "1"), (#"["2","1"]"#, "2"), (#"["2","3"]"#, "2")] {
            let bench = Bench().hello(versions: offered).goodbye()
            XCTAssertEqual(try bench.tool().serve(), 0)
            XCTAssertEqual(try bench.written().first?.answer?["protocolVersion"], .string(picked), offered)
        }
    }

    func testAVersionTheToolDoesNotSpeakIsRefused() throws {
        let bench = Bench().hello(versions: #"["3"]"#).run("hello", id: 2).goodbye()
        var ran = false
        let tool = try bench.tool { $0.command("hello") { _ in ran = true } }
        XCTAssertEqual(tool.serve(), 0)
        XCTAssertFalse(ran)
        XCTAssertEqual(try bench.written(), [
            .failure(id: .string("hello"), error: RPCErrorObject(code: -32602,
                                                                  message: "this tool speaks protocols 1 and 2 only")),
            .failure(id: .number(2), error: RPCErrorObject(code: -32600, message: "initialize comes first")),
        ])
    }

    func testNoticesReachTheirHandlersAndTheToolsOwnAreWritten() throws {
        let bench = Bench().hello()
            .app("this line is not a message")
            .app(#"{"jsonrpc":"2.0","method":"preferences/changed","params":{"values":{"project":"web"}}}"#)
            .app(#"{"jsonrpc":"2.0","method":"language/changed","params":{"language":"ja"}}"#)
            .goodbye()
        var changed: [String: JSONValue] = [:]
        var language = ""
        let tool = try bench.tool { tool in
            tool.onStart = { app in
                app.setRunnable(["hello"])
                app.log("started")
            }
            tool.onPreferencesChanged = { _, values in changed = values }
            tool.onLanguageChanged = { app in language = app.language }
        }
        XCTAssertEqual(tool.serve(), 0)
        XCTAssertEqual(changed, ["project": .string("web")])
        XCTAssertEqual(language, "ja")
        XCTAssertEqual(Array(try bench.written().dropFirst()), [
            .notice(method: "commands/state", params: .object(["runnable": .array([.string("hello")])])),
            .notice(method: "log", params: .object(["message": .string("started")])),
        ], "after the answer to initialize, never before it")
    }
}

extension RPCMessage {
    /// A result's value; nil for anything else.
    var answer: JSONValue? {
        if case .result(_, let value) = self { return value }
        return nil
    }
}

/// A tool that draws: its panels opened, acted in, rendered to and closed,
/// and a web panel's calls, against the same link of two files.
final class PanelTests: XCTestCase {
    private let done = JSONValue.object([:])

    private func open(_ panel: String, id: Int) -> String {
        #"{"jsonrpc":"2.0","id":\#(id),"method":"ui/open","params":{"panel":"\#(panel)"}}"#
    }

    private func tap(_ panel: String, _ block: String, id: Int) -> String {
        #"{"jsonrpc":"2.0","id":\#(id),"method":"ui/event","params":{"panel":"\#(panel)","block":"\#(block)","event":"tap"}}"#
    }

    private func tree(_ message: RPCMessage?) -> JSONValue? {
        if case .result(_, let value)? = message { return value["tree"] }
        return nil
    }

    func testAPanelIsOpenedActedInAndClosed() throws {
        let bench = Bench().hello(versions: #"["1","2"]"#)
            .app(open("counter", id: 2))
            .app(tap("counter", "add", id: 3))
            .app(tap("counter", "nothing", id: 4))
            .app(#"{"jsonrpc":"2.0","method":"ui/close","params":{"panel":"counter"}}"#)
            .goodbye()
        var count = 0
        var seen: [PanelEvent] = []
        var handle: Panel?
        let tool = try bench.tool { tool in
            handle = tool.panel("counter", onOpen: { _, _ in UITree { text("Pressed \(count) times") } },
                                   onEvent: { _, _, event in
                                       seen.append(event)
                                       guard event.block == "add" else { return .keep }
                                       count += 1
                                       return .page(UITree { text("Pressed \(count) times") })
                                   })
        }
        XCTAssertEqual(tool.serve(), 0)
        let written = try bench.written()
        XCTAssertEqual(written.first?.answer?["protocolVersion"], .string("2"), "a tool of the kit speaks protocol 2")
        XCTAssertEqual(tree(written[1]), .object(["blocks": .array([.object(["type": .string("text"),
                                                                            "text": .string("Pressed 0 times")])])]))
        XCTAssertEqual(tree(written[2]), .object(["blocks": .array([.object(["type": .string("text"),
                                                                            "text": .string("Pressed 1 times")])])]))
        XCTAssertEqual(written[3], .result(id: .number(4), value: .object(["keep": .bool(true)])))
        XCTAssertEqual(seen, [PanelEvent(block: "add", kind: .tap), PanelEvent(block: "nothing", kind: .tap)])
        XCTAssertEqual(handle?.isOpen, false, "ui/close closes it")
    }

    func testAPageIsSentUnpromptedOnlyWhileThePanelIsOpen() throws {
        let bench = Bench().hello(versions: #"["1","2"]"#)
            .run("refresh", id: 2)
            .app(open("counter", id: 3))
            .run("refresh", id: 4)
            .app(#"{"jsonrpc":"2.0","method":"ui/close","params":{"panel":"counter"}}"#)
            .run("refresh", id: 5)
            .goodbye()
        var sent: [Bool] = []
        let tool = try bench.tool { tool in
            let panel = tool.panel("counter", onOpen: { _, _ in UITree { heading("Counter") } })
            tool.command("refresh") { _ in sent.append(panel.render(UITree { text("Later") })) }
        }
        XCTAssertEqual(tool.serve(), 0)
        XCTAssertEqual(sent, [false, true, false], "render sends nothing for a panel that is not open")
        let renders = try bench.written().filter {
            if case .notice("ui/render", _) = $0 { return true }
            return false
        }
        XCTAssertEqual(renders, [.notice(method: "ui/render", params: .object([
            "panel": .string("counter"),
            "tree": .object(["blocks": .array([.object(["type": .string("text"), "text": .string("Later")])])]),
        ]))])
    }

    func testWhatIsNotAPanelOfTheToolsIsRefused() throws {
        let bench = Bench().hello(versions: #"["1","2"]"#)
            .app(open("nowhere", id: 2))
            .app(tap("counter", "add", id: 3))
            .goodbye()
        let tool = try bench.tool { $0.panel("counter", onOpen: { _, _ in nil }) }
        XCTAssertEqual(tool.serve(), 0)
        XCTAssertEqual(Array(try bench.written().dropFirst()), [
            .failure(id: .number(2), error: RPCErrorObject(code: -32602, message: "no such panel")),
            .failure(id: .number(3), error: RPCErrorObject(code: -32602, message: "the panel is not open")),
        ])
    }

    func testAnAnswerMayOpenAWindowOrReplyAndTheBadgeIsARequest() throws {
        let bench = Bench().hello(versions: #"["1","2"]"#)
            .app(open("deploys", id: 2))
            .app(tap("deploys", "log", id: 3))
            .app(#"{"jsonrpc":"2.0","id":1,"result":{}}"#)
            .goodbye()
        let tool = try bench.tool { tool in
            tool.panel("deploys", onOpen: { _, panel in
                try panel.badge(count: 2)
                return nil
            }, onEvent: { _, _, _ in .open("log") })
        }
        XCTAssertEqual(tool.serve(), 0)
        let written = try bench.written()
        XCTAssertEqual(written[1], .request(id: .number(1), method: "ui/badge", params: .object(["count": .number(2)])))
        XCTAssertEqual(written[2], .result(id: .number(2), value: done), "a page given as none is no tree")
        XCTAssertEqual(written[3], .result(id: .number(3), value: .object(["open": .string("log")])))
    }

    func testAWebPanelsCallsAreTheToolsOwnOrPassedToTheApp() throws {
        func bridge(_ id: Int, _ call: String) -> String {
            #"{"jsonrpc":"2.0","id":\#(id),"method":"ui/event","params":{"panel":"dashboard","event":"bridge","value":\#(call)}}"#
        }
        let bench = Bench().hello(versions: #"["1","2"]"#)
            .app(open("dashboard", id: 2))
            .app(bridge(3, #"{"method":"notify/hud","params":{"icon":"checkmark","message":"Saved"}}"#))
            .app(#"{"jsonrpc":"2.0","id":1,"result":{}}"#)
            .app(bridge(4, #"{"method":"tool/count","params":{"by":2}}"#))
            .app(bridge(5, #"{"method":"tool/other"}"#))
            .app(bridge(6, #"{"method":"initialize"}"#))
            .goodbye()
        let tool = try bench.tool { tool in
            let panel = tool.panel("dashboard", onOpen: { _, _ in nil })
            panel.onCall = { _, method, params in
                guard method == "tool/count" else { throw RPCErrorObject(code: -32601, message: "method not found") }
                return .object(["count": params?["by"] ?? .null])
            }
        }
        XCTAssertEqual(tool.serve(), 0)
        let written = Array(try bench.written().dropFirst(2))
        XCTAssertEqual(written, [
            .request(id: .number(1), method: "notify/hud",
                     params: .object(["icon": .string("checkmark"), "message": .string("Saved")])),
            .result(id: .number(3), value: .object(["reply": done])),
            .result(id: .number(4), value: .object(["reply": .object(["count": .number(2)])])),
            .failure(id: .number(5), error: RPCErrorObject(code: -32601, message: "method not found")),
            .failure(id: .number(6), error: RPCErrorObject(code: -32601, message: "method not found")),
        ], "a request of the app's is asked of the app as the tool's own; a method of the tool's goes to onCall")
    }

    func testAPageIsWrittenAsTheBlocksItHolds() {
        let count = 12
        let rows = ["web", "api"]
        let page = UITree {
            heading("Counter")
            text("Pressed \(count) times", style: .secondary)
            button("add", "Add one", style: .prominent)
            if count > 9 { text("That is a lot", style: .caption) }
            if count > 99 { divider() } else { spacer(4) }
            for name in rows { row(name, UIText.plain(name)) }
            list("deploys", [UIListRow(id: "web", title: "web 1.42.0")])
            toggle("notify", "Tell me", isOn: true)
            field("name", title: "Name", placeholder: "Type and press Return")
            progress(0.5)
            image("ui/logo.png", alt: "Logo")
            link("Dashboard", url: "https://example.com")
        }
        XCTAssertEqual(page.blocks.map { $0.type }, ["heading", "text", "button", "text", "spacer", "row", "row", "list",
                                                 "toggle", "field", "progress", "image", "link"])
        XCTAssertEqual(page.blocks[2].id, "add")
        XCTAssertEqual(page.blocks.compactMap { $0.id }, ["add", "web", "api", "deploys", "notify", "name"])
        XCTAssertEqual(UIBlock.kinds.count, 12)
    }
}

// MARK: - Timers

/// A link of two pipes, which stay open until the test closes them, so a
/// timer has time to run. The tool serves on a thread of its own; the test
/// is the app.
private final class LiveBench {
    private let fromApp = Pipe()
    private let toApp = Pipe()
    private var read = Data()
    private let lock = NSLock()
    private var status: Int32?

    let tool: Tool

    init(_ build: (Tool) -> Void) {
        tool = Tool(version: "9.9.9", input: fromApp.fileHandleForReading, output: toApp.fileHandleForWriting)
        build(tool)
        // What the tool writes is read as it comes, so a full pipe never
        // holds the tool.
        let handle = toApp.fileHandleForReading
        Thread.detachNewThread { [self] in
            while true {
                let piece = handle.availableData
                if piece.isEmpty { return }
                lock.withLock { read.append(piece) }
            }
        }
    }

    func serve() {
        Thread.detachNewThread { [self] in
            let ended = tool.serve()
            lock.withLock { status = ended }
        }
    }

    func app(_ line: String) {
        fromApp.fileHandleForWriting.write(Data((line + "\n").utf8))
    }

    func hello() {
        app(#"{"jsonrpc":"2.0","id":"hello","method":"initialize","params":{"protocolVersions":["1","2"],"language":"en-US","dataFolder":"/tmp/kit-data"}}"#)
    }

    /// Says goodbye, closes the link, and waits for the tool to stop.
    func goodbye() -> Int32? {
        app(#"{"jsonrpc":"2.0","method":"shutdown"}"#)
        try? fromApp.fileHandleForWriting.close()
        let until = Date().addingTimeInterval(5)
        while Date() < until {
            if let status = lock.withLock({ status }) {
                try? toApp.fileHandleForWriting.close()
                Thread.sleep(forTimeInterval: 0.05)
                return status
            }
            Thread.sleep(forTimeInterval: 0.01)
        }
        return nil
    }

    func written() throws -> [RPCMessage] {
        let text = String(decoding: lock.withLock { read }, as: UTF8.self)
        return try text.split(separator: "\n").map { try LineFraming.message(from: Data($0.utf8)) }
    }
}

extension ToolTests {
    private func logs(_ messages: [RPCMessage]) -> [String] {
        messages.compactMap { message in
            guard case .notice("log", let params) = message else { return nil }
            return params?["message"]?.stringValue
        }
    }

    func testATimerRunsBetweenMessagesAndCountsFromTheHello() throws {
        // Guarded by the tool's one thread: read after serve() has returned.
        nonisolated(unsafe) var ticks = 0
        let bench = LiveBench { tool in
            tool.every(seconds: 0.05) { app in
                ticks += 1
                app.log("tick \(ticks)")
            }
        }
        bench.serve()
        // Before the hello the timer is not running.
        Thread.sleep(forTimeInterval: 0.2)
        bench.hello()
        Thread.sleep(forTimeInterval: 0.3)
        XCTAssertEqual(bench.goodbye(), 0)
        let written = try bench.written()
        XCTAssertEqual(ticks, logs(written).count, "each run of the timer wrote its line")
        XCTAssertTrue((3...8).contains(ticks), "a timer of 50 ms ran about six times in 300 ms, not \(ticks)")
        guard case .result(id: .string("hello"), _)? = written.first else {
            return XCTFail("the hello is answered before any timer runs: \(written.first.map(String.init(describing:)) ?? "nothing")")
        }
    }

    func testATimerDoesNotRunWhileAHandlerWaitsForTheApp() throws {
        nonisolated(unsafe) var ticks = 0
        nonisolated(unsafe) var ticksWhenTheCommandRan = -1
        let bench = LiveBench { tool in
            tool.every(seconds: 0.05) { app in
                ticks += 1
                app.log("tick")
            }
            tool.command("copy") { app in
                _ = try app.clipboardText()
                ticksWhenTheCommandRan = ticks
            }
        }
        bench.serve()
        bench.hello()
        bench.app(#"{"jsonrpc":"2.0","id":2,"method":"command/run","params":{"command":"copy"}}"#)
        // The handler waits for the clipboard for 300 ms: six timer runs' worth.
        Thread.sleep(forTimeInterval: 0.3)
        bench.app(#"{"jsonrpc":"2.0","id":1,"result":{"text":"x"}}"#)
        Thread.sleep(forTimeInterval: 0.2)
        XCTAssertEqual(bench.goodbye(), 0)
        let written = try bench.written()
        XCTAssertEqual(ticksWhenTheCommandRan, 0, "no timer ran while the handler waited for its answer")
        XCTAssertGreaterThanOrEqual(ticks, 1, "the timer ran once the handler had returned")
        let answered = written.firstIndex { if case .result(id: .number(2), _) = $0 { return true } else { return false } }
        let firstLog = written.firstIndex { if case .notice("log", _) = $0 { return true } else { return false } }
        XCTAssertNotNil(answered)
        XCTAssertTrue(firstLog.map { $0 > (answered ?? .max) } ?? false, "every line of the timer came after the command's answer")
    }

    func testATimersErrorIsLoggedAndTheTimerGoesOn() throws {
        nonisolated(unsafe) var ticks = 0
        let bench = LiveBench { tool in
            tool.every(seconds: 0.05) { _ in
                ticks += 1
                throw CommandRefused("not now")
            }
        }
        bench.serve()
        bench.hello()
        Thread.sleep(forTimeInterval: 0.3)
        XCTAssertEqual(bench.goodbye(), 0)
        let lines = logs(try bench.written())
        XCTAssertEqual(lines.count, ticks)
        XCTAssertTrue(ticks >= 2 && lines.allSatisfy { $0.contains("not now") }, "\(lines)")
    }
}

// MARK: - Work handed from another thread

extension ToolTests {
    func testWorkHandedFromAnotherThreadRunsOnTheToolsThreadAfterTheHello() throws {
        // Written on the tool's one thread; read after serve() has returned.
        nonisolated(unsafe) var commandThread: Thread?
        nonisolated(unsafe) var handedThread: Thread?
        nonisolated(unsafe) var waker: ToolWaker?
        let bench = LiveBench { tool in
            waker = tool.waker
            tool.command("mark") { app in
                commandThread = Thread.current
                app.log("mark")
            }
        }
        bench.serve()
        // Handed before the hello: held until the app has said it.
        waker?.later { app in
            handedThread = Thread.current
            app.log("handed")
        }
        Thread.sleep(forTimeInterval: 0.2)
        XCTAssertEqual(logs(try bench.written()).count, 0, "nothing handed over runs before the hello")
        bench.hello()
        bench.app(#"{"jsonrpc":"2.0","id":2,"method":"command/run","params":{"command":"mark"}}"#)
        Thread.sleep(forTimeInterval: 0.2)
        waker?.later { app in app.log("handed again") }
        Thread.sleep(forTimeInterval: 0.2)
        XCTAssertEqual(bench.goodbye(), 0)
        XCTAssertEqual(logs(try bench.written()), ["handed", "mark", "handed again"])
        XCTAssertNotNil(handedThread)
        XCTAssertTrue(handedThread === commandThread, "handed work runs on the thread the handlers run on")
        XCTAssertFalse(handedThread === Thread.current, "and not on the thread that handed it")
    }

    func testWorkHandedWhileAHandlerWaitsRunsAfterTheHandler() throws {
        nonisolated(unsafe) var waker: ToolWaker?
        let bench = LiveBench { tool in
            waker = tool.waker
            tool.command("copy") { app in
                _ = try app.clipboardText()
                app.log("command done")
            }
        }
        bench.serve()
        bench.hello()
        bench.app(#"{"jsonrpc":"2.0","id":2,"method":"command/run","params":{"command":"copy"}}"#)
        Thread.sleep(forTimeInterval: 0.1)
        // The handler is waiting for the clipboard: this must not cut in.
        waker?.later { app in app.log("handed") }
        Thread.sleep(forTimeInterval: 0.2)
        bench.app(#"{"jsonrpc":"2.0","id":1,"result":{"text":"x"}}"#)
        Thread.sleep(forTimeInterval: 0.2)
        XCTAssertEqual(bench.goodbye(), 0)
        let written = try bench.written()
        XCTAssertEqual(logs(written), ["command done", "handed"], "the handler finishes first")
        let answered = written.firstIndex { if case .result(id: .number(2), _) = $0 { return true } else { return false } }
        let handed = written.firstIndex { if case .notice("log", let params) = $0 { return params?["message"]?.stringValue == "handed" } else { return false } }
        XCTAssertTrue((answered ?? .max) < (handed ?? .min), "the command's answer goes out before the handed work runs")
    }

    func testAnErrorInHandedWorkIsLoggedAndTheRestStillRuns() throws {
        nonisolated(unsafe) var waker: ToolWaker?
        let bench = LiveBench { tool in waker = tool.waker }
        bench.serve()
        bench.hello()
        Thread.sleep(forTimeInterval: 0.1)
        waker?.later { _ in throw CommandRefused("not now") }
        waker?.later { app in app.log("after") }
        Thread.sleep(forTimeInterval: 0.2)
        XCTAssertEqual(bench.goodbye(), 0)
        let lines = logs(try bench.written())
        XCTAssertEqual(lines.count, 2)
        XCTAssertTrue(lines.first?.contains("not now") == true && lines.last == "after", "\(lines)")
    }
}
