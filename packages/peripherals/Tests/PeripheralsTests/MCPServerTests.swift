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

import CompXHID
import CompXProtocol
import GravaStarCLI
import StatusSignals

final class MCPServerTests: XCTestCase {
    private var printed: [String] = []
    private var transports: [MockTransport] = []

    /// A server over a scripted mouse. `printed` collects anything the runner
    /// itself would have written to stdout, which must stay empty.
    private func server(_ scripts: [[[UInt8]]] = [], baseline: String? = nil) -> MCPServer {
        var remaining = scripts
        let runner = CLIRunner(
            open: { _ in
                guard !remaining.isEmpty else { throw CompXError.deviceNotFound }
                let transport = MockTransport(replies: remaining.removeFirst())
                self.transports.append(transport)
                return GravaStarMouse(transport: transport, timing: .zero)
            },
            out: { self.printed.append($0) },
            err: { self.printed.append($0) },
            sleep: { _ in })
        return MCPServer(runner: runner, baselinePath: baseline)
    }

    private func request(_ server: MCPServer, _ method: String, _ params: [String: Any] = [:],
                         id: Any = 1) throws -> [String: Any] {
        let line = String(decoding: try JSONSerialization.data(
            withJSONObject: ["jsonrpc": "2.0", "id": id, "method": method, "params": params] as [String: Any]),
            as: UTF8.self)
        let reply = try XCTUnwrap(server.handle(line), "a request is answered")
        XCTAssertFalse(reply.contains("\n"), "a stdio message is one line")
        return try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(reply.utf8)) as? [String: Any])
    }

    private func call(_ server: MCPServer, _ tool: String, _ arguments: [String: Any] = [:])
        throws -> (text: String, isError: Bool) {
        let reply = try request(server, "tools/call", ["name": tool, "arguments": arguments])
        let result = try XCTUnwrap(reply["result"] as? [String: Any], "tool results are results: \(reply)")
        let content = try XCTUnwrap(result["content"] as? [[String: Any]])
        return (content.compactMap { $0["text"] as? String }.joined(), result["isError"] as? Bool ?? false)
    }

    func testInitializeAgreesOnAVersion() throws {
        let known = try request(server(), "initialize", ["protocolVersion": "2025-03-26"])
        let result = try XCTUnwrap(known["result"] as? [String: Any])
        XCTAssertEqual(result["protocolVersion"] as? String, "2025-03-26", "a version the server knows is echoed")
        XCTAssertNotNil((result["capabilities"] as? [String: Any])?["tools"])
        XCTAssertEqual((result["serverInfo"] as? [String: Any])?["version"] as? String, CLI.version)
        XCTAssertEqual(known["id"] as? Int, 1)

        let unknown = try request(server(), "initialize", ["protocolVersion": "1999-01-01"], id: "a")
        XCTAssertEqual((unknown["result"] as? [String: Any])?["protocolVersion"] as? String,
                       MCPServer.protocolVersions[0], "an unknown version gets the newest one")
        XCTAssertEqual(unknown["id"] as? String, "a", "a string id comes back as given")
    }

    func testProtocolEdges() throws {
        let server = self.server()
        XCTAssertNil(server.handle(#"{"jsonrpc":"2.0","method":"notifications/initialized"}"#),
                     "a notification is not answered")
        XCTAssertEqual((try request(server, "ping")["result"] as? [String: Any])?.count, 0, "ping answers {}")
        let missing = try request(server, "resources/list")
        XCTAssertEqual((missing["error"] as? [String: Any])?["code"] as? Int, -32601)
        let garbage = try XCTUnwrap(server.handle("{not json"))
        XCTAssertTrue(garbage.contains("-32700"), garbage)
        let unknownTool = try request(server, "tools/call", ["name": "mouse_explode"])
        XCTAssertEqual((unknownTool["error"] as? [String: Any])?["code"] as? Int, -32602)
    }

    func testToolsListEveryCommand() throws {
        let result = try XCTUnwrap(try request(server(), "tools/list")["result"] as? [String: Any])
        let tools = try XCTUnwrap(result["tools"] as? [[String: Any]])
        XCTAssertEqual(Set(tools.compactMap { $0["name"] as? String }),
                       ["mouse_status", "mouse_signal", "mouse_restore", "mouse_color",
                        "mouse_breathe", "mouse_rainbow", "mouse_off"])
        for tool in tools {
            XCTAssertEqual((tool["inputSchema"] as? [String: Any])?["type"] as? String, "object",
                           "\(tool["name"] ?? "?") has an object schema")
        }
        let signal = try XCTUnwrap(tools.first { $0["name"] as? String == "mouse_signal" })
        let properties = (signal["inputSchema"] as? [String: Any])?["properties"] as? [String: Any]
        XCTAssertEqual((properties?["signal"] as? [String: Any])?["enum"] as? [String],
                       StatusSignal.allCases.map(\.rawValue))
    }

    func testStatusReturnsTheLightingAndPrintsNothing() throws {
        let result = try call(server([[Fixtures.readCyanWithID]]), "mouse_status")
        XCTAssertFalse(result.isError)
        XCTAssertEqual(result.text, ##"{"brightness":7,"color":"#00ffff","mode":"fixed","speed":5}"##)
        XCTAssertTrue(printed.isEmpty, "stdout carries only the protocol: \(printed)")
    }

    func testColorWritesWhatTheCommandLineWould() throws {
        let slow = LightingConfig(mode: .fixed, color: .black, speed: Level(2)!, brightness: .seven)
        let result = try call(server([[Fixtures.readReply(slow), Fixtures.ack(includesReportID: true)]]),
                              "mouse_color", ["color": "red", "brightness": 4])
        XCTAssertFalse(result.isError, result.text)
        let expected = LightingConfig(mode: .fixed, color: RGB(r: 255, g: 0, b: 0), speed: Level(2)!, brightness: Level(4)!)
        XCTAssertEqual(transports[0].writes.last?.payload, Requests.writeLighting(expected).payload)
    }

    func testSignalSavesTheBaselineWhereTheServerWasToldTo() throws {
        let baseline = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: baseline) }
        let result = try call(server([[Fixtures.readCyanWithID, Fixtures.ack(includesReportID: true)]],
                                     baseline: baseline.path),
                              "mouse_signal", ["signal": "failure"])
        XCTAssertFalse(result.isError, result.text)
        XCTAssertTrue(FileManager.default.fileExists(atPath: baseline.path), "the cyan baseline is saved")
        XCTAssertEqual(transports[0].writes.last?.payload,
                       Requests.writeLighting(StatusPresets.lighting(for: .failure)).payload)
    }

    func testBadArgumentsAndAMissingMouseAreToolErrors() throws {
        let server = self.server()
        let bright = try call(server, "mouse_color", ["color": "red", "brightness": 12])
        XCTAssertTrue(bright.isError)
        XCTAssertTrue(bright.text.contains("--brightness must be 0-9"), bright.text)
        let missing = try call(server, "mouse_breathe")
        XCTAssertTrue(missing.isError)
        XCTAssertTrue(missing.text.contains("'color'"), missing.text)
        let panic = try call(server, "mouse_signal", ["signal": "panic"])
        XCTAssertTrue(panic.isError)
        let absent = try call(server, "mouse_off")
        XCTAssertTrue(absent.isError)
        XCTAssertEqual(absent.text, "gravastar-mouse: mouse not found")
        XCTAssertTrue(transports.isEmpty, "no bad call reached a mouse")
    }

    func testServeAnswersRequestsUntilInputEnds() {
        var lines = [
            #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18"}}"#,
            #"{"jsonrpc":"2.0","method":"notifications/initialized"}"#,
            "",
            #"{"jsonrpc":"2.0","id":2,"method":"tools/list"}"#,
        ]
        var written: [String] = []
        server().serve(readLine: { lines.isEmpty ? nil : lines.removeFirst() }, write: { written.append($0) })
        XCTAssertEqual(written.count, 2, "one answer per request, none for the notification or the blank line")
        XCTAssertTrue(written[0].contains(#""id":1"#) && written[1].contains(#""id":2"#), "\(written)")
    }

    func testCommandLineStartsTheServer() throws {
        XCTAssertEqual(try CLI.parse(["mcp"]).command, .mcp)
        XCTAssertEqual(try CLI.parse(["--baseline", "/tmp/b.json", "mcp"]),
                       Invocation(command: .mcp, baselinePath: "/tmp/b.json"))
        XCTAssertThrowsError(try CLI.parse(["mcp", "extra"]))
        XCTAssertEqual(try CLI.parse(["--version"]).command, .version)
        XCTAssertEqual(try CLI.parse(["version"]).command, .version)
    }
}
