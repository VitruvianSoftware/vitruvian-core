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
        XCTAssertEqual(AppRequests.methods.count, 10, "each request once")
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

    func testAVersionTheToolDoesNotSpeakIsRefused() throws {
        let bench = Bench().hello(versions: #"["2"]"#).run("hello", id: 2).goodbye()
        var ran = false
        let tool = try bench.tool { $0.command("hello") { _ in ran = true } }
        XCTAssertEqual(tool.serve(), 0)
        XCTAssertFalse(ran)
        XCTAssertEqual(try bench.written(), [
            .failure(id: .string("hello"), error: RPCErrorObject(code: -32602, message: "this tool speaks protocol 1 only")),
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
