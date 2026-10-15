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

// The helpers the Vitruvian tool's Settings shares with the app: the
// arguments for each app-identity command, and removing a speaker.

@Suite struct AppCommandArgumentsTests {
    /// Every case, with each of its options.
    static let every: [AppCommand] = [
        .signOut(chatOnly: false), .signOut(chatOnly: true),
        .discover(save: false, home: nil), .discover(save: true, home: nil),
        .discover(save: false, home: "h1"), .discover(save: true, home: "structures/abc-123"),
        .testMediaPause,
    ] + LoginItemAction.allCases.map { .loginItem($0) }

    @Test(arguments: every) func parseReadsBackWhatArgumentsWrites(_ command: AppCommand) {
        #expect(AppCommandParser.parse(AppCommandParser.arguments(for: command)) == .success(command))
    }

    @Test func theArgumentsAreTheDocumentedFlags() {
        #expect(AppCommandParser.arguments(for: .signOut(chatOnly: false)) == ["--sign-out"])
        #expect(AppCommandParser.arguments(for: .signOut(chatOnly: true)) == ["--sign-out", "--chat"])
        #expect(AppCommandParser.arguments(for: .discover(save: true, home: "h1")) == ["--discover", "--save", "--home", "h1"])
        #expect(AppCommandParser.arguments(for: .loginItem(.status)) == ["--login-item", "status"])
        #expect(AppCommandParser.arguments(for: .testMediaPause) == ["--test-media-pause"])
    }

    @Test func everyCaseIsCovered() {
        // A new AppCommand case must join `every`; this switch stops compiling without it.
        for command in Self.every {
            switch command {
            case .signOut, .discover, .loginItem, .testMediaPause: continue
            }
        }
        #expect(Set(Self.every.compactMap { if case .loginItem(let a) = $0 { return a } else { return nil } }) == Set(LoginItemAction.allCases))
    }
}

@Suite struct RemoveTargetTests {
    /// Two aliases for the kitchen speaker, one for the office.
    private var config: SpeakerConfig {
        SpeakerConfig(defaultTarget: "kitchen", structureId: "s1", targets: [
            "kitchen": SpeakerDevice(id: "d1", type: "SpeakerDevice", name: "Kitchen"),
            "kitchen_display": SpeakerDevice(id: "d1", type: "SpeakerDevice", name: "Kitchen"),
            "office": SpeakerDevice(id: "d2", type: "SpeakerDevice", name: "Office"),
        ])
    }

    @Test func removingTheDefaultPicksTheFirstRemainingSpeakerByName() {
        var c = config
        c.removeTarget("kitchen")
        #expect(c.targets["kitchen"] == nil)
        #expect(c.defaultTarget == "kitchen_display", "Kitchen sorts before Office, and its other alias is all that is left of it")
        c.removeTarget("kitchen_display")
        #expect(c.defaultTarget == "office")
    }

    @Test func removingASecondAliasLeavesTheDefaultAlone() {
        var c = config
        c.removeTarget("kitchen_display")
        #expect(c.defaultTarget == "kitchen")
        #expect(c.targets.keys.sorted() == ["kitchen", "office"])
        c.removeTarget("nowhere")
        #expect(c.targets.count == 2 && c.defaultTarget == "kitchen", "an unknown alias changes nothing")
    }

    @Test func removingTheLastSpeakerLeavesNoDefault() {
        var c = SpeakerConfig(defaultTarget: "office", structureId: "s1",
                              targets: ["office": SpeakerDevice(id: "d2", type: "SpeakerDevice", name: "Office")])
        c.removeTarget("office")
        #expect(c.targets.isEmpty)
        #expect(c.defaultTarget == "")
        #expect(c.defaultDevice == nil)
    }

    @Test @MainActor func theConfigManagerRemovesThroughTheConfigAndSaves() {
        let files = MemoryFiles()
        let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("homespeaker-remove-\(UUID().uuidString)")
        let url = scratch.appendingPathComponent("speaker_broadcast.json")
        let manager = ConfigManager(configPath: url, historyPath: scratch.appendingPathComponent("history.json"),
                                    secrets: SecretStore(fileURL: scratch.appendingPathComponent("secrets.json")),
                                    fileSystem: files)
        manager.config = config
        manager.removeTarget("kitchen")
        var expected = config
        expected.removeTarget("kitchen")
        #expect(manager.config == expected)
        guard case .loaded(let saved) = SpeakerConfigFile(url: url, fileSystem: files).read() else {
            Issue.record("nothing saved")
            return
        }
        #expect(saved == expected)
    }
}
