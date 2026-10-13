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

import HomeSpeakerCore
import HomeSpeakerToolCore

final class ConfigTests: XCTestCase {
    private var folder: URL!

    override func setUp() {
        folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("homespeaker-tool-config-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: folder)
    }

    func testTheFileIsReadAndWrittenAsTheAppWritesIt() throws {
        let store = FileConfigStore(url: folder.appendingPathComponent(".gemini/speaker_broadcast.json"))
        XCTAssertNil(store.load(), "no file yet")
        var config = SpeakerConfig(enabled: true, defaultTarget: "kitchen", structureId: "s1", structureName: "Home",
                                   targets: ["kitchen": SpeakerDevice(id: "d1", type: "SpeakerDevice", name: "Kitchen", room: "Kitchen")],
                                   speechLength: .headline, quietHoursEnabled: true, quietHoursStart: "22:00", quietHoursEnd: "07:00")
        config.effectiveSpeakLocal = true
        try store.save(config)
        let text = try String(contentsOf: store.url, encoding: .utf8)
        XCTAssertTrue(text.contains("\"default_target\" : \"kitchen\"") && text.contains("\"speech_length\" : \"headline\"")
                          && text.contains("\"speak_local\" : true"), "the app's keys, pretty and sorted:\n\(text)")
        XCTAssertEqual(store.load(), config)
    }

    func testAnUnreadableFileReadsAsNothing() throws {
        let url = folder.appendingPathComponent("speaker_broadcast.json")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: url)
        XCTAssertNil(FileConfigStore(url: url).load())
    }

    func testAQuietHourIsHHmm() {
        XCTAssertEqual(SpeakerConfig.quietHour(" 22:30 "), "22:30")
        XCTAssertEqual(SpeakerConfig.quietHour("7:05"), "7:05")
        XCTAssertNil(SpeakerConfig.quietHour("25:00"))
        XCTAssertNil(SpeakerConfig.quietHour("ten"))
    }
}
