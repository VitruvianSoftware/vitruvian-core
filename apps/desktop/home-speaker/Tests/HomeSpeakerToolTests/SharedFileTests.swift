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
import VitruvianToolKit
import VitruvianToolProtocol

/// The tool writes the same shared file the app, the phone's Mac agent and
/// the CLI do: these hold it to the app's rules, against a disk in memory.
final class SharedFileTests: XCTestCase {
    final class MemoryFiles: ConfigFileSystem, @unchecked Sendable {
        private let lock = NSLock()
        private var files: [String: Data] = [:]
        private(set) var writes = 0
        subscript(url: URL) -> Data? {
            get { lock.withLock { files[url.path] } }
            set { lock.withLock { files[url.path] = newValue } }
        }
        func read(_ url: URL) throws -> Data? { self[url] }
        func write(_ data: Data, to url: URL) throws {
            lock.withLock { writes += 1 }
            self[url] = data
        }
    }

    final class Link: ToolLink {
        var messages: [String] = []
        var logged: [String] = []
        func render(panel: String, _ tree: UITree) {}
        func showMessage(_ message: String, icon: String) { messages.append(message) }
        func log(_ message: String) { logged.append(message) }
        func clipboardText() -> String? { nil }
    }

    final class Driver: SpeakerDriver {
        var program: URL?
        var isInstalled: Bool { program != nil }
        init(program: URL?) { self.program = program }
        func run(_ job: Job, then: @escaping @Sendable (JobResult) -> Void) {}
    }

    private let url = URL(fileURLWithPath: "/fake/.gemini/speaker_broadcast.json")
    private let appProgram = URL(fileURLWithPath: "/Applications/HomeSpeaker.app/Contents/MacOS/HomeSpeaker")

    private func object(_ files: MemoryFiles) -> [String: Any] {
        (files[url].flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }) ?? [:]
    }

    private func tool(_ files: MemoryFiles, program: URL? = nil) -> HomeSpeakerTool {
        HomeSpeakerTool(parts: .init(link: Link(), store: FileConfigStore(url: url, fileSystem: files),
                                     driver: Driver(program: program ?? appProgram), later: { $0() }))
    }

    func testTheToolKeepsKeysItDoesNotKnow() throws {
        let files = MemoryFiles()
        files[url] = Data("""
        {"enabled":true,"default_target":"kitchen","structure_id":"s1",
         "targets":{"kitchen":{"id":"d1","type":"SPEAKER","name":"Kitchen","phone_icon":"speaker"}},
         "chat_monitor":{"slack_enabled":true,"phone_only":1},"macagent_version":"2.1"}
        """.utf8)
        try tool(files).run(command: HomeSpeakerTool.Command.toggleQuietHours)
        let disk = object(files)
        XCTAssertEqual(disk["quiet_hours_enabled"] as? Bool, true, "the tool's change landed")
        XCTAssertEqual(disk["macagent_version"] as? String, "2.1", "a top-level key the tool does not know survives")
        XCTAssertEqual((disk["chat_monitor"] as? [String: Any])?["phone_only"] as? Int, 1)
        XCTAssertEqual(((disk["targets"] as? [String: Any])?["kitchen"] as? [String: Any])?["phone_icon"] as? String, "speaker")
    }

    func testTheToolNeverSavesItsDefaultsOverAFileThatDoesNotRead() {
        let files = MemoryFiles()
        files[url] = Data("{ broken".utf8)
        let tool = tool(files)
        XCTAssertThrowsError(try tool.run(command: HomeSpeakerTool.Command.toggleBroadcasting))
        _ = tool.settingsPage()
        _ = tool.settingsEvent(PanelEvent(block: Pages.Block.speakLocal, kind: .toggle, value: .bool(true)))
        XCTAssertEqual(files.writes, 0, "nothing written")
        XCTAssertEqual(files[url], Data("{ broken".utf8), "the file is exactly as it was")
    }

    func testHooksFromTheToolPointAtTheAppNotAtBinTool() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("homespeaker-tool-home-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: home) }
        let agents = try XCTUnwrap(tool(MemoryFiles()).agentIntegration(home: home))
        XCTAssertEqual(agents.hookCommand(for: .claudeCode), "\"\(appProgram.path)\" --claude-stop-hook")
        XCTAssertFalse(agents.hookCommand(for: .claudeCode).contains(CommandLine.arguments[0]), "never the running program")
        let missing = HomeSpeakerTool(parts: .init(link: Link(), store: FileConfigStore(url: url, fileSystem: MemoryFiles()),
                                                   driver: Driver(program: nil), later: { $0() }))
        XCTAssertNil(missing.agentIntegration(home: home), "no HomeSpeaker, nothing to point a hook at")
    }

    func testTheDriverReportsTheProgramItRuns() {
        XCTAssertEqual(ProcessDriver(binary: appProgram).program, appProgram)
        XCTAssertNil(ProcessDriver(binary: nil).program)
    }
}
