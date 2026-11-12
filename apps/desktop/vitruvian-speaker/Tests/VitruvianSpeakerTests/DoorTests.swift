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

import Foundation
import Testing
@testable import HomeSpeakerCore

// Which HomeSpeaker is in use, when both the app and the Vitruvian extension
// are on this Mac (design section 7). One file records the choice; each side
// works out from it, and from whether the other is installed, whether it
// runs, asks, waits or stays quiet.
//
// Every test keeps the choice file in its own temporary folder; none reads
// or writes the real one.

@Suite struct DoorTests {
    typealias Door = HomeSpeakerProfile.Door

    /// A choice file in a new temporary folder.
    private func scratchFile() -> DoorFile {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("homespeaker-door-\(UUID().uuidString)")
        return DoorFile(url: folder.appendingPathComponent(DoorFile.fileName))
    }

    private func object(at url: URL) throws -> [String: Any] {
        try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any] ?? [:]
    }

    // MARK: - Who runs (design table 7.3)

    @Test func eachRowOfTheTable() {
        // The other one is not installed: active, whatever the file says.
        #expect(DoorRole.decide(me: .app, otherInstalled: false, chosen: .extension) == .active)
        #expect(DoorRole.decide(me: .extension, otherInstalled: false, chosen: .app) == .active)
        // Installed, and this one is chosen: active.
        #expect(DoorRole.decide(me: .app, otherInstalled: true, chosen: .app) == .active)
        #expect(DoorRole.decide(me: .extension, otherInstalled: true, chosen: .extension) == .active)
        // Installed, and the other is chosen: quiet.
        #expect(DoorRole.decide(me: .app, otherInstalled: true, chosen: .extension) == .quiet(other: .extension))
        #expect(DoorRole.decide(me: .extension, otherInstalled: true, chosen: .app) == .quiet(other: .app))
        // Installed, and nobody has chosen: the app keeps running and asks;
        // the extension waits and asks.
        #expect(DoorRole.decide(me: .app, otherInstalled: true, chosen: nil) == .activeAsking)
        #expect(DoorRole.decide(me: .extension, otherInstalled: true, chosen: nil) == .waitingAsking)
    }

    @Test func aStaleChoiceIsIgnoredWhenTheOtherIsGone() {
        for me in [Door.app, .extension] {
            for chosen in [nil, Door.app, .extension] {
                #expect(DoorRole.decide(me: me, otherInstalled: false, chosen: chosen) == .active,
                        "\(me), chosen \(String(describing: chosen)): the other is gone, so this one runs")
            }
        }
    }

    @Test func onlyQuietStandsAside() throws {
        let file = scratchFile()
        let withApp = DoorCheck(file: file, appInstalled: { true }, fileExists: { _ in true })
        #expect(!withApp.standsAside(me: .extension), "no choice file: the extension waits, but does not stand aside")

        try file.update { $0.chosen = .app }
        #expect(withApp.standsAside(me: .extension))
        #expect(withApp.role(me: .extension) == .quiet(other: .app))
        #expect(!withApp.standsAside(me: .app))

        let noApp = DoorCheck(file: file, appInstalled: { false }, fileExists: { _ in true })
        #expect(!noApp.standsAside(me: .extension), "the app is gone: its old choice is ignored")
    }

    @Test func theAppStandsAsideOnlyForAnExtensionThatCanRunAlone() throws {
        let file = scratchFile()
        let program = "/Users/x/Library/Application Support/Vitruvian/Tools/dev.vitruvian.homespeaker/bin/tool"
        try file.update {
            $0.chosen = .extension
            $0.installedExtension = .init(program: program, dataFolder: "/d", version: "1.19.0", door: 1)
        }
        let present = DoorCheck(file: file, appInstalled: { true }, fileExists: { $0 == program })
        #expect(present.standsAside(me: .app))

        let removed = DoorCheck(file: file, appInstalled: { true }, fileExists: { _ in false })
        #expect(!removed.standsAside(me: .app), "the extension's program is gone: the app runs")
    }

    // MARK: - Is the other one installed (design 7.2)

    @Test func theAppInTheTrashIsNotInstalled() {
        for app in ["/Users/x/.Trash/HomeSpeaker.app", "/Users/x/.Trash/HomeSpeaker 2.app",
                    "/Volumes/Disk/.Trashes/501/HomeSpeaker.app"] {
            let program = URL(fileURLWithPath: app).appendingPathComponent("Contents/MacOS/HomeSpeaker")
            #expect(!OtherDoorPresence.appInstalled(locate: { program }), "\(app) is in the Trash")
        }
        let installed = URL(fileURLWithPath: "/Applications/HomeSpeaker.app/Contents/MacOS/HomeSpeaker")
        #expect(OtherDoorPresence.appInstalled(locate: { installed }))
        #expect(!OtherDoorPresence.appInstalled(locate: { nil }))
    }

    @Test func anOldExtensionIsNotASecondHomeSpeaker() {
        let program = "/Users/x/Library/Application Support/Vitruvian/Tools/dev.vitruvian.homespeaker/bin/tool"
        let exists: (String) -> Bool = { $0 == program }
        // A 1.17 or 1.18 extension never writes its block (design section 8).
        #expect(!OtherDoorPresence.extensionInstalled(record: nil, fileExists: exists))
        #expect(!OtherDoorPresence.extensionInstalled(record: DoorRecord(chosen: .extension), fileExists: exists))
        // A block without the mark of an extension that runs alone does not
        // count, whatever version it names.
        for version in ["1.17.0", "1.18.0"] {
            let old = DoorRecord(installedExtension: .init(program: program, dataFolder: "/d", version: version, door: nil))
            #expect(!OtherDoorPresence.extensionInstalled(record: old, fileExists: exists), "\(version)")
        }
        // The mark decides, not the version: the version is only shown.
        let marked = DoorRecord(installedExtension: .init(program: program, dataFolder: "/d", version: "1.18.9", door: 1))
        #expect(OtherDoorPresence.extensionInstalled(record: marked, fileExists: exists))
    }

    @Test func aMissingExtensionProgramIsNotInstalled() {
        let program = "/Users/x/Library/Application Support/Vitruvian/Tools/dev.vitruvian.homespeaker/bin/tool"
        let record = DoorRecord(installedExtension: .init(program: program, dataFolder: "/d", version: "1.19.0", door: 1))
        #expect(!OtherDoorPresence.extensionInstalled(record: record, fileExists: { _ in false }))
        #expect(OtherDoorPresence.extensionInstalled(record: record, fileExists: { $0 == program }))

        let trashed = DoorRecord(installedExtension: .init(
            program: "/Users/x/.Trash/dev.vitruvian.homespeaker/bin/tool", dataFolder: "/d", version: "1.19.0", door: 1))
        #expect(!OtherDoorPresence.extensionInstalled(record: trashed, fileExists: { _ in true }), "in the Trash")
    }

    // MARK: - The file

    @Test func noFileReadsAsNothing() {
        #expect(scratchFile().read() == nil)
    }

    @Test func theDesignsFileReads() throws {
        let file = scratchFile()
        try FileManager.default.createDirectory(at: file.url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("""
        {
          "version": 1,
          "chosen": "extension",
          "chosen_at": "2026-10-20T09:12:00Z",
          "chosen_by": "HomeSpeaker extension 1.19.0",
          "extension": {
            "program": "/Users/x/Tools/dev.vitruvian.homespeaker/bin/tool",
            "data_folder": "/Users/x/ToolData/dev.vitruvian.homespeaker",
            "version": "1.19.0",
            "door": 1
          }
        }
        """.utf8).write(to: file.url)

        let record = try #require(file.read())
        #expect(record.version == 1)
        #expect(record.chosen == .extension)
        #expect(record.chosenAt == ISO8601DateFormatter().date(from: "2026-10-20T09:12:00Z"))
        #expect(record.chosenBy == "HomeSpeaker extension 1.19.0")
        #expect(record.installedExtension == .init(
            program: "/Users/x/Tools/dev.vitruvian.homespeaker/bin/tool",
            dataFolder: "/Users/x/ToolData/dev.vitruvian.homespeaker", version: "1.19.0", door: 1))
    }

    @Test func anUnknownChoiceReadsAsNone() throws {
        let file = scratchFile()
        try FileManager.default.createDirectory(at: file.url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(#"{"version":1,"chosen":"both","chosen_by":7}"#.utf8).write(to: file.url)
        let record = try #require(file.read())
        #expect(record.chosen == nil)
        #expect(record.chosenBy == nil)
    }

    @Test func aWriteIsTheDesignsShape() throws {
        let file = scratchFile()
        let when = try #require(ISO8601DateFormatter().date(from: "2026-10-20T09:12:00Z"))
        try file.update {
            $0.chosen = .app
            $0.chosenAt = when
            $0.chosenBy = "HomeSpeaker 1.19.0"
        }
        let written = try object(at: file.url)
        #expect(written["version"] as? Int == 1)
        #expect(written["chosen"] as? String == "app")
        #expect(written["chosen_at"] as? String == "2026-10-20T09:12:00Z")
        #expect(written["chosen_by"] as? String == "HomeSpeaker 1.19.0")
        #expect(written["extension"] == nil)
        #expect(FileManager.default.fileExists(atPath: file.lockURL.path))
        #expect(file.lockURL.lastPathComponent == "speaker_door.json.lock")
    }

    @Test func unknownKeysSurvive() throws {
        let file = scratchFile()
        try FileManager.default.createDirectory(at: file.url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("""
        {"version":1,"chosen":"app","later":{"a":1},
         "extension":{"program":"/p","data_folder":"/d","version":"1.19.0","door":1,"pid":42}}
        """.utf8).write(to: file.url)

        try file.update { $0.chosen = .extension }
        var written = try object(at: file.url)
        #expect(written["chosen"] as? String == "extension")
        #expect((written["later"] as? [String: Any])?["a"] as? Int == 1, "a key this version does not know survives")
        #expect((written["extension"] as? [String: Any])?["pid"] as? Int == 42, "inside the block too")

        try file.update { $0.installedExtension?.version = "1.19.1" }
        written = try object(at: file.url)
        let block = try #require(written["extension"] as? [String: Any])
        #expect(block["version"] as? String == "1.19.1")
        #expect(block["pid"] as? Int == 42, "a changed block keeps its foreign keys")
        #expect(written["later"] != nil)

        try file.update { $0.chosen = nil }
        written = try object(at: file.url)
        #expect(written["chosen"] == nil, "a choice cleared is removed")
        #expect(written["later"] != nil)
    }

    @Test func aBlockKeyThisVersionCannotReadSurvivesAChangeToAnother() throws {
        // `door` is a string here, so this version reads it as absent. Changing
        // another key of the block must not throw the unreadable one away,
        // as the top level does not.
        let file = scratchFile()
        try FileManager.default.createDirectory(at: file.url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("""
        {"version":1,"extension":{"program":"/p","data_folder":"/d","version":"1.19.0","door":"1","pid":42}}
        """.utf8).write(to: file.url)
        #expect(file.read()?.installedExtension?.door == nil, "not an Int: read as absent")

        try file.update { $0.installedExtension?.version = "1.19.1" }

        let block = try #require(object(at: file.url)["extension"] as? [String: Any])
        #expect(block["version"] as? String == "1.19.1", "the changed key is written")
        #expect(block["door"] as? String == "1", "a key it could not read is kept")
        #expect(block["pid"] as? Int == 42)
        #expect(block["program"] as? String == "/p")
        #expect(block["data_folder"] as? String == "/d")

        // A key the change sets is written even over one it could not read,
        // and a key the change clears is removed.
        try file.update {
            $0.installedExtension?.door = 1
            $0.installedExtension?.dataFolder = nil
        }
        let after = try #require(object(at: file.url)["extension"] as? [String: Any])
        #expect(after["door"] as? Int == 1)
        #expect(after["data_folder"] == nil)
        #expect(after["pid"] as? Int == 42)
    }

    @Test func aFileThatDoesNotReadIsNotReplaced() throws {
        let file = scratchFile()
        try FileManager.default.createDirectory(at: file.url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let garbage = Data("not json".utf8)
        try garbage.write(to: file.url)
        #expect(throws: DoorFileError.self) { try file.update { $0.chosen = .app } }
        #expect(try Data(contentsOf: file.url) == garbage)
    }

    @Test func aCorruptFileFailsSafeTowardToday() throws {
        // A choice file that does not read changes nothing for today's
        // user: the app runs, and the extension waits and asks. Neither
        // stays quiet, so a hook pointed at either still speaks.
        let file = scratchFile()
        try FileManager.default.createDirectory(at: file.url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: file.url)
        #expect(file.read() == nil)

        let check = DoorCheck(file: file, appInstalled: { true }, fileExists: { _ in true })

        #expect(check.role(me: .app) == .active)
        #expect(check.role(me: .extension) == .waitingAsking)
        #expect(!check.standsAside(me: .app))
        #expect(!check.standsAside(me: .extension))
    }

    @Test func twoWritersBothLand() throws {
        // Many writers at once, each from its own DoorFile (so its own lock
        // descriptor) on its own thread, each adding its own mark to the
        // record. A read-modify-write without the lock loses marks.
        let url = scratchFile().url
        let writers = 48
        let start = DispatchSemaphore(value: 0)
        let group = DispatchGroup()
        let failures = Failures()
        for i in 0..<writers {
            group.enter()
            Thread {
                defer { group.leave() }
                start.wait()
                do {
                    try DoorFile(url: url).update { record in
                        let before = record.chosenBy ?? ""
                        // Widen the window between the read and the write.
                        usleep(2_000)
                        record.chosenBy = before + "<\(i)>"
                    }
                } catch {
                    failures.add("\(i): \(error)")
                }
            }.start()
        }
        for _ in 0..<writers { start.signal() }
        group.wait()

        #expect(failures.all.isEmpty)
        let marks = try #require(DoorFile(url: url).read()?.chosenBy)
        let landed = (0..<writers).filter { marks.contains("<\($0)>") }
        #expect(landed.count == writers, "every writer's mark landed; \(writers - landed.count) were lost")
    }

    @Test func theDefaultFileIsBesideTheAppsSettings() {
        let home = URL(fileURLWithPath: "/tmp/somebody")
        #expect(DoorFile.defaultURL(home: home).path == "/tmp/somebody/.gemini/speaker_door.json")
        #expect(DoorFile.defaultURL(home: home).deletingLastPathComponent()
            == HomeSpeakerProfile.app(home: home).settingsURL.deletingLastPathComponent())
    }
}

/// Failures collected from several threads.
private final class Failures: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [String] = []
    func add(_ item: String) { lock.lock(); items.append(item); lock.unlock() }
    var all: [String] { lock.lock(); defer { lock.unlock() }; return items }
}
