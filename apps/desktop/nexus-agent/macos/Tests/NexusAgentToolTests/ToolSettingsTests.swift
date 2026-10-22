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

import NexusAgentCore
import NexusAgentToolCore
import VitruvianToolProtocol

@MainActor
final class ToolSettingsTests: XCTestCase {
    private var folder: URL!

    // `async`, so the override runs on the main actor the class is held to.
    // Swift 6.1.2, the CI Mac's (Xcode 16.4), refuses a plain `setUp()` that
    // touches the class's own properties; Swift 6.4 lets it by.
    override func setUp() async throws {
        folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("nexus-agent-tool-settings-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: folder)
    }

    /// What the app's feature hands over, as its hand-off writes it.
    private let handed: [String: JSONValue] = [
        "botDirectory": .string("~/bots/nexus"),
        "autoStart": .bool(true),
        "planMode": .bool(true),
        "worktreeMode": .bool(false),
        "chosenProvider": .string("00000000-0000-0000-0000-000000000003"),
        "savedProviders": .string(#"[{"id":"11111111-1111-1111-1111-111111111111","name":"Mine","commandTemplate":"mine -p \"{prompt}\"","isBuiltIn":false}]"#),
        "promptHistory": .string(#"["first","second"]"#),
        "hiddenClaudeSessions": .string(#"["abc"]"#),
        "chosenModels": .string(#"{"00000000-0000-0000-0000-000000000002":"opus","not a uuid":"x"}"#),
        "sessionPreferences": .string(#"{"pinnedSessionIDs":["s1"],"renamedSessionTitles":{"s2":"Renamed"}}"#),
    ]

    func testTheFirstRunTakesEverythingHandedAndWritesTheFile() throws {
        let settings = ToolSettings(folder: folder)
        XCTAssertTrue(settings.isFirstRun)
        let taken = settings.apply(handed: handed)
        XCTAssertEqual(taken, ["chosenModels", "chosenProvider", "hiddenClaudeSessions", "promptHistory", "savedProviders",
                               "sessionPreferences"])
        XCTAssertFalse(settings.isFirstRun)
        XCTAssertEqual(settings.configuredBotDirectory, "~/bots/nexus")
        XCTAssertTrue(settings.startsBotAtLaunch && settings.planMode && !settings.worktreeMode)
        XCTAssertEqual(settings.chosenProviderID, UUID(uuidString: "00000000-0000-0000-0000-000000000003"))
        XCTAssertEqual(settings.savedProviders.map(\.name), ["Mine"])
        XCTAssertEqual(settings.promptHistory, ["first", "second"])
        XCTAssertEqual(settings.hiddenClaudeSessionIDs, ["abc"])
        XCTAssertEqual(settings.chosenModels, [UUID(uuidString: "00000000-0000-0000-0000-000000000002")!: "opus"])
        XCTAssertEqual(settings.sessionPreferences.pinnedSessionIDs, ["s1"])
        XCTAssertEqual(settings.sessionPreferences.renamedSessionTitles, ["s2": "Renamed"])
        let data = try Data(contentsOf: folder.appendingPathComponent(ToolSettings.fileName))
        let again = ToolSettings(folder: folder)
        XCTAssertFalse(again.isFirstRun)
        XCTAssertEqual(again.values, settings.values, "the file holds all of it: \(String(decoding: data, as: UTF8.self))")
    }

    func testALaterRunTakesTheTitledPreferencesOnlyAndTheFileIsTheTruthForTheRest() {
        let first = ToolSettings(folder: folder)
        _ = first.apply(handed: handed)
        first.promptHistory = ["first", "second", "third"]
        let later = ToolSettings(folder: folder)
        var changed = handed
        changed["botDirectory"] = .string("")
        changed["planMode"] = .bool(false)
        changed["promptHistory"] = .string(#"["stale"]"#)
        XCTAssertEqual(later.apply(handed: changed), [], "nothing untitled is taken twice")
        XCTAssertEqual(later.configuredBotDirectory, "")
        XCTAssertFalse(later.planMode)
        XCTAssertEqual(later.promptHistory, ["first", "second", "third"], "the file's history, not the stale handed copy")
    }

    func testAValueOfTheWrongKindIsLeftOutAndLogged() {
        var logged: [String] = []
        let settings = ToolSettings(folder: folder, log: { logged.append($0) })
        let taken = settings.apply(handed: ["autoStart": .string("yes"), "promptHistory": .string("not json"),
                                            "hiddenClaudeSessions": .string(#"["x"]"#)])
        XCTAssertEqual(taken, ["hiddenClaudeSessions"])
        XCTAssertFalse(settings.startsBotAtLaunch)
        XCTAssertEqual(settings.promptHistory, [])
        XCTAssertEqual(logged.count, 2, "\(logged)")
    }

    func testAChangeTheToolMakesToATitledPreferenceIsToldToTheApp() {
        let settings = ToolSettings(folder: folder)
        _ = settings.apply(handed: [:])
        var told: [(String, JSONValue)] = []
        settings.preferenceChanged = { told.append(($0, $1)) }
        settings.planMode = true
        settings.planMode = true
        settings.worktreeMode = true
        settings.promptHistory = ["a"]
        XCTAssertEqual(told.map(\.0), ["planMode", "worktreeMode"], "each titled change once; an untitled one never")
        XCTAssertEqual(told.map(\.1), [.bool(true), .bool(true)])
        // The person changed one in the app: taken, and not told back.
        settings.changed(["planMode": .bool(false), "promptHistory": .string("[]")])
        XCTAssertFalse(settings.planMode)
        XCTAssertEqual(settings.promptHistory, ["a"], "an untitled key in a change is ignored")
        XCTAssertEqual(told.count, 2)
    }

    func testTheHostsStringsFollowTheLanguage() {
        let settings = ToolSettings(folder: folder)
        settings.language = "de"
        XCTAssertEqual(settings.strings.untitledSession, Words.text("untitledSession", "de"))
        XCTAssertEqual(settings.strings.missingAgent, Words.text("missingAgent", "de"))
        XCTAssertEqual(settings.strings.doneTitleSuffix, NexusAgentHostStrings().doneTitleSuffix, "the rest is the shared English")
        var approvals = 0
        settings.onApproval = { _ in approvals += 1 }
        settings.turnNeedsApproval(NexusAgentTurnNotice(providerName: "agy", text: "rm", failed: false, endedCleanly: false))
        XCTAssertEqual(approvals, 1)
    }

    func testModelChoicesAndSessionPreferencesAreKeptInTheFile() throws {
        let settings = ToolSettings(folder: folder)
        _ = settings.apply(handed: [:])
        var told: [String] = []
        settings.preferenceChanged = { key, _ in told.append(key) }
        let claude = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000002"))
        settings.chosenModels = [claude: "sonnet"]
        var preferences = settings.sessionPreferences
        preferences.togglePin("s9")
        preferences.rename(id: "s9", to: "Release notes")
        settings.sessionPreferences = preferences
        XCTAssertEqual(told, [], "neither is the app's to keep")
        let again = ToolSettings(folder: folder)
        XCTAssertEqual(again.chosenModels, [claude: "sonnet"])
        XCTAssertEqual(again.values.chosenModels, [claude.uuidString: "sonnet"], "kept by the id as text")
        XCTAssertTrue(again.sessionPreferences.isPinned("s9"))
        XCTAssertEqual(again.sessionPreferences.renamedSessionTitles["s9"], "Release notes")
    }

    func testArchivingASessionTellsTheAppOnlyWhenTheListChanged() {
        let settings = ToolSettings(folder: folder)
        _ = settings.apply(handed: [:])
        var told: [(String, JSONValue)] = []
        settings.preferenceChanged = { told.append(($0, $1)) }
        settings.hiddenClaudeSessionIDs = ["a", "b"]
        settings.hiddenClaudeSessionIDs = ["a", "b"]
        settings.hiddenClaudeSessionIDs = []
        XCTAssertEqual(told.map(\.0), ["hiddenClaudeSessions", "hiddenClaudeSessions"])
        XCTAssertEqual(told.map(\.1), [.string(#"["a","b"]"#), .string("[]")], "as the JSON text the app keeps")
    }

    func testAFileFromAnEarlierVersionIsStillRead() throws {
        let earlier = #"{"autoStart":true,"botDirectory":"/b","chosenProvider":"","hiddenClaudeSessions":["h"],"#
            + #""planMode":false,"promptHistory":["p"],"savedProviders":[],"worktreeMode":true}"#
        try Data(earlier.utf8).write(to: folder.appendingPathComponent(ToolSettings.fileName))
        let settings = ToolSettings(folder: folder)
        XCTAssertFalse(settings.isFirstRun, "a file without the newer keys is no first run")
        XCTAssertEqual(settings.configuredBotDirectory, "/b")
        XCTAssertEqual(settings.promptHistory, ["p"])
        XCTAssertEqual(settings.hiddenClaudeSessionIDs, ["h"])
        XCTAssertTrue(settings.worktreeMode)
        XCTAssertEqual(settings.chosenModels, [:])
        XCTAssertEqual(settings.sessionPreferences, NexusAgentSessionPreferences())
    }
}
