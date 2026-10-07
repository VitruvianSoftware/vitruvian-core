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

final class CLIParseTests: XCTestCase {
    private func command(_ args: String...) throws -> CLICommand {
        try CLI.parse(args).command
    }

    private func assertUsageError(_ args: String..., file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try CLI.parse(args), file: file, line: line) {
            XCTAssertTrue($0 is UsageError, "expected a usage error, got \($0)", file: file, line: line)
        }
    }

    func testDefaultsToStatus() throws {
        XCTAssertEqual(try CLI.parse([]), Invocation(command: .status(json: false)))
        XCTAssertEqual(try command("status", "--json"), .status(json: true))
        XCTAssertEqual(try command("--json"), .status(json: true))
    }

    func testColourCommands() throws {
        XCTAssertEqual(try command("color", "cyan"), .color(RGB(r: 0, g: 255, b: 255), brightness: .seven))
        XCTAssertEqual(try command("color", "#00ffcc", "--brightness", "3"), .color(RGB(r: 0, g: 255, b: 204), brightness: Level(3)!))
        XCTAssertEqual(try command("breathe", "magenta", "--speed=2"),
                       .breathe(RGB(r: 255, g: 0, b: 255), speed: Level(2)!, brightness: .seven))
        XCTAssertEqual(try command("rainbow", "--brightness", "9"), .rainbow(speed: .five, brightness: .nine))
        XCTAssertEqual(try command("off"), .off)
    }

    func testSetCommand() throws {
        XCTAssertEqual(try command("set", "--mode", "static", "--color", "blue", "--speed", "1", "--brightness", "2"),
                       .set(LightingConfig(mode: .fixed, color: RGB(r: 0, g: 0, b: 255), speed: Level(1)!, brightness: Level(2)!)))
        XCTAssertEqual(try command("set", "--mode", "neon"),
                       .set(LightingConfig(mode: .neon, color: RGB(r: 255, g: 0, b: 0), speed: .five, brightness: .seven)))
        assertUsageError("set")
        assertUsageError("set", "--mode", "disco")
    }

    func testSignalAndRestore() throws {
        XCTAssertEqual(try command("signal", "failure"), .signal(.failure, restoreAfter: nil))
        XCTAssertEqual(try command("signal", "working", "--restore-after", "1.5"), .signal(.working, restoreAfter: .milliseconds(1500)))
        XCTAssertEqual(try command("restore"), .restore)
        for signal in StatusSignal.allCases {
            XCTAssertEqual(try command("signal", signal.rawValue), .signal(signal, restoreAfter: nil))
        }
        assertUsageError("signal")
        assertUsageError("signal", "panic")
        assertUsageError("signal", "success", "--restore-after", "0")
        assertUsageError("signal", "success", "--restore-after", "soon")
    }

    func testGlobalFlags() throws {
        let invocation = try CLI.parse(["--trace", "--baseline", "/tmp/b.json", "signal", "success"])
        XCTAssertEqual(invocation, Invocation(command: .signal(.success, restoreAfter: nil), trace: true, baselinePath: "/tmp/b.json"))
        XCTAssertEqual(try command("--help"), .help)
        XCTAssertEqual(try command("-h"), .help)
    }

    func testUsageErrors() {
        assertUsageError("color")
        assertUsageError("color", "#xyz")
        assertUsageError("color", "red", "--brightness", "10")
        assertUsageError("breathe", "red", "--speed", "-1")
        assertUsageError("status", "--speed", "3")
        assertUsageError("off", "--json")
        assertUsageError("dance")
        assertUsageError("--bogus")
        assertUsageError("color", "red", "--brightness")
    }
}

final class CLIRunnerTests: XCTestCase {
    private var output: [String] = []
    private var errors: [String] = []
    private var transports: [MockTransport] = []

    private func runner(_ scripts: [[[UInt8]]]) -> CLIRunner {
        var remaining = scripts
        return CLIRunner(
            open: { _ in
                let transport = MockTransport(replies: remaining.removeFirst())
                self.transports.append(transport)
                return GravaStarMouse(transport: transport, timing: .zero)
            },
            out: { self.output.append($0) },
            err: { self.errors.append($0) },
            sleep: { _ in })
    }

    func testStatusJSON() {
        XCTAssertEqual(runner([[Fixtures.readCyanWithID]]).main(["status", "--json"]), 0)
        XCTAssertEqual(output, [##"{"brightness":7,"color":"#00ffff","mode":"fixed","speed":5}"##])
    }

    func testUsageErrorExitsTwo() {
        XCTAssertEqual(runner([]).main(["signal", "panic"]), 2)
        XCTAssertTrue(output.isEmpty)
        XCTAssertFalse(errors.isEmpty)
    }

    func testMouseNotFoundExitsOneQuietly() {
        let runner = CLIRunner(open: { _ in throw CompXError.deviceNotFound },
                               out: { self.output.append($0) }, err: { self.errors.append($0) }, sleep: { _ in })
        XCTAssertEqual(runner.main(["signal", "success"]), 1)
        XCTAssertEqual(errors, ["gravastar-mouse: mouse not found"])
    }

    func testSignalWithRestoreAfterReopensAndRestores() throws {
        let baseline = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: baseline) }
        let showingFailure = Fixtures.readReply(StatusPresets.lighting(for: .failure))
        let code = runner([
            [Fixtures.readCyanWithID, Fixtures.ack(includesReportID: true)],
            [showingFailure, Fixtures.ack(includesReportID: true)],
        ]).main(["--baseline", baseline.path, "signal", "failure", "--restore-after", "2"])
        XCTAssertEqual(code, 0, "errors: \(errors)")
        XCTAssertEqual(transports.count, 2, "the device is reopened after the wait")
        XCTAssertEqual(transports[1].writes.last?.payload, Requests.writeLighting(Fixtures.cyan).payload)
        XCTAssertEqual(output.last, "Restored fixed #00ffff speed 5 brightness 7.")
    }

    func testColorKeepsTheDeviceSpeed() {
        let slow = LightingConfig(mode: .fixed, color: .black, speed: Level(2)!, brightness: .seven)
        XCTAssertEqual(runner([[Fixtures.readReply(slow), Fixtures.ack(includesReportID: true)]]).main(["color", "red"]), 0)
        let expected = LightingConfig(mode: .fixed, color: RGB(r: 255, g: 0, b: 0), speed: Level(2)!, brightness: .seven)
        XCTAssertEqual(transports[0].writes.last?.payload, Requests.writeLighting(expected).payload)
    }
}
