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
import StatusSignals

final class StatusSignalsTests: XCTestCase {
    private var directory: URL!
    private var store: BaselineStore!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        store = BaselineStore(url: directory.appendingPathComponent("nested/baseline.json"))
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func indicator(_ replies: [[UInt8]]) -> (MouseStatusIndicator, MockTransport) {
        let transport = MockTransport(replies: replies)
        let mouse = GravaStarMouse(transport: transport, timing: .zero)
        return (MouseStatusIndicator(mouse: mouse, store: store), transport)
    }

    func testPresetTableIsTotalAndDistinct() {
        let configs = StatusSignal.allCases.map(StatusPresets.lighting(for:))
        XCTAssertEqual(Set(configs).count, StatusSignal.allCases.count, "every signal has its own look")
        for signal in StatusSignal.allCases {
            XCTAssertEqual(StatusPresets.signal(showing: StatusPresets.lighting(for: signal)), signal)
        }
    }

    func testPresetTableMatchesTheSpec() {
        func config(_ mode: LightingMode, _ hex: String, _ speed: Int, _ brightness: Int) -> LightingConfig {
            LightingConfig(mode: mode, color: RGB(hex: hex)!, speed: Level(speed)!, brightness: Level(brightness)!)
        }
        XCTAssertEqual(StatusPresets.lighting(for: .working), config(.breathe, "#0000FF", 5, 7))
        XCTAssertEqual(StatusPresets.lighting(for: .success), config(.fixed, "#00FF00", 5, 7))
        XCTAssertEqual(StatusPresets.lighting(for: .failure), config(.breathe, "#FF0000", 7, 9))
        XCTAssertEqual(StatusPresets.lighting(for: .warning), config(.fixed, "#FF8000", 5, 7))
        XCTAssertEqual(StatusPresets.lighting(for: .attention), config(.breathe, "#FF00FF", 5, 7))
        XCTAssertEqual(StatusPresets.lighting(for: .off), config(.off, "#000000", 0, 0))
    }

    func testSignalSavesTheUsersOwnLookAsBaseline() throws {
        let (indicator, transport) = indicator([Fixtures.readCyanWithID, Fixtures.ack(includesReportID: true)])
        try indicator.signal(.failure)
        XCTAssertEqual(try store.load(), Fixtures.cyan)
        XCTAssertEqual(transport.commands, [8, 7])
        XCTAssertEqual(transport.writes[1].payload, Requests.writeLighting(StatusPresets.lighting(for: .failure)).payload)
    }

    func testSignalOverAPresetKeepsTheOriginalBaseline() throws {
        try store.save(Fixtures.cyan)
        let showingFailure = Fixtures.readReply(StatusPresets.lighting(for: .failure))
        let (indicator, _) = indicator([showingFailure, Fixtures.ack(includesReportID: true)])
        try indicator.signal(.success)
        XCTAssertEqual(try store.load(), Fixtures.cyan, "a preset on the device is never mistaken for the user's look")
    }

    func testRestoreWritesTheBaselineBackAndKeepsTheFile() throws {
        try store.save(Fixtures.cyan)
        let (indicator, transport) = indicator([Fixtures.ack(includesReportID: true)])
        XCTAssertEqual(try indicator.restore(), .restored(Fixtures.cyan))
        XCTAssertEqual(transport.writes.map(\.payload), [Requests.writeLighting(Fixtures.cyan).payload])
        XCTAssertEqual(try store.load(), Fixtures.cyan)
    }

    func testRestoreWithoutBaselineIsANoOp() throws {
        let (indicator, transport) = indicator([])
        XCTAssertEqual(try indicator.restore(), .noBaseline)
        XCTAssertTrue(transport.writes.isEmpty)
    }

    func testRestoreIfShowingSkipsWhenSomethingElseChangedTheLight() throws {
        try store.save(Fixtures.cyan)
        let showingSuccess = Fixtures.readReply(StatusPresets.lighting(for: .success))
        let (indicator, transport) = indicator([showingSuccess])
        XCTAssertEqual(try indicator.restore(ifShowing: .failure),
                       .skipped(current: StatusPresets.lighting(for: .success)))
        XCTAssertEqual(transport.commands, [8], "read only, no write")
    }

    func testRestoreIfShowingRestoresWhenStillShowing() throws {
        try store.save(Fixtures.cyan)
        let showingFailure = Fixtures.readReply(StatusPresets.lighting(for: .failure))
        let (indicator, _) = indicator([showingFailure, Fixtures.ack(includesReportID: true)])
        XCTAssertEqual(try indicator.restore(ifShowing: .failure), .restored(Fixtures.cyan))
    }

    func testBaselineFileIsReadableJSON() throws {
        try store.save(Fixtures.cyan)
        let object = try JSONSerialization.jsonObject(with: Data(contentsOf: store.url)) as? [String: Any]
        XCTAssertEqual(object?["mode"] as? String, "fixed")
        XCTAssertEqual(object?["color"] as? String, "#00ffff")
        XCTAssertEqual(object?["speed"] as? Int, 5)
        XCTAssertEqual(object?["brightness"] as? Int, 7)
    }

    func testDefaultBaselineLocation() {
        XCTAssertTrue(BaselineStore.defaultURL.path.hasSuffix(
            "Library/Application Support/Vitruvian/peripherals/gravastar-baseline.json"))
    }
}
