// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import Foundation
import VitruvianCore
import VitruvianServices
import VitruvianToolProtocol
import VitruvianUI

/// A tool's own settings: the preferences its manifest gives a title, as
/// the store lists them, as the tool's detail shows them, and what happens
/// when the person changes one. No view is drawn, and no program is
/// started: each tool here is one that is no program.
enum ExternalToolSettingsTests {
    static func run(_ suite: TestSuite) {
        theReader(suite)
        listed(suite)
        changing(suite)
        told(suite)
        inTheDetail(suite)
    }

    static let id = ExternalToolTests.id
    static let copy = ExternalToolTests.copy
    static let english = FeatureStrings.externalTools(.enUS)

    /// The design's example with five preferences: one of each kind with a
    /// title, and one its author gave none.
    static let preferences = #"""
        {"preferences": [
          {"id": "project", "title": {"en": "Project", "fr": "Projet"}, "type": "string", "default": "web"},
          {"id": "notify", "title": {"en": "Tell me when a deploy ends"}, "type": "boolean", "default": true},
          {"id": "secret", "type": "string", "default": "s3cret"},
          {"id": "limit", "title": {"en": "Deploys to list"}, "type": "integer", "default": 5},
          {"id": "ratio", "title": {"en": "Ratio"}, "type": "number", "default": 0.5}]}
        """#

    static func key(_ preference: String, of tool: ToolID = id) -> String {
        "\(tool.rawValue)/\(preference)"
    }

    /// A bench with the tool of `manifest` added.
    static func bench(_ manifest: String = preferences) -> ExternalToolStoreTests.Bench {
        let bench = ExternalToolStoreTests.Bench()
        bench.add(bench.folder(manifest: ExternalToolManifestTests.file(manifest)))
        return bench
    }

    /// Every `preferences/changed` the app has sent a run of a tool, as the
    /// values each carried.
    static func notices(_ tool: FakeTool) -> [[String: JSONValue]] {
        tool.sent.compactMap { message in
            guard case .notice(let method, let params) = message, method == "preferences/changed" else { return nil }
            return params?["values"]?.objectValue
        }
    }

    /// The protocol's own example of `preferences/changed`, from the file
    /// the schema is tested against.
    static var example: JSONValue? { example(of: "preferences/changed") }

    /// The protocol's own valid example of one message, by its method.
    static func example(of method: String) -> JSONValue? {
        let environment = ProcessInfo.processInfo.environment
        guard let path = environment["VITRUVIAN_MESSAGE_EXAMPLES"], let runfiles = environment["TEST_SRCDIR"],
              let workspace = environment["TEST_WORKSPACE"],
              let data = FileManager.default.contents(atPath: "\(runfiles)/\(workspace)/\(path)"),
              let file = try? JSONDecoder().decode(JSONValue.self, from: data) else { return nil }
        return file["examples"]?.arrayValue?.first {
            $0["valid"] == .bool(true) && $0["message"]?["method"]?.stringValue == method
        }?["message"]
    }

    /// The manifest's titles reach the app's own description of the tool.
    static func theReader(_ suite: TestSuite) {
        let tool = ExternalToolManifestTests.tool(preferences)
        suite.expect(tool?.preferenceTitles == [key("project"): LocalizedText(["en": "Project", "fr": "Projet"]),
                                                key("notify"): LocalizedText(["en": "Tell me when a deploy ends"]),
                                                key("limit"): LocalizedText(["en": "Deploys to list"]),
                                                key("ratio"): LocalizedText(["en": "Ratio"])],
                     "a preference's title is kept in every language its author wrote, under the key the preference "
                         + "is saved by; one with no title has none")
        suite.expect(tool?.manifest.preferences
                         == [PreferenceDeclaration(key: key("project"), default: .string("web")),
                             PreferenceDeclaration(key: key("notify"), default: .bool(true)),
                             PreferenceDeclaration(key: key("secret"), default: .string("s3cret")),
                             PreferenceDeclaration(key: key("limit"), default: .int(5)),
                             PreferenceDeclaration(key: key("ratio"), default: .double(0.5))],
                     "what the tool itself may read and write is all five, titled or not, as before")
        suite.expect(ExternalToolManifestTests.tool()?.preferenceTitles.isEmpty == true
                         && ExternalToolManifestTests.tool()?.manifest.preferences.count == 1,
                     "a manifest with no title is read as it always was")
        suite.expect(ExternalToolManifestTests.refusal(#"""
                         {"preferences": [{"id": "project", "title": {"en": "Pro\nject"}, "type": "string", "default": ""}]}
                         """#) == .invalid(.preferenceTitleNotWellFormed(preference: "project"))
                         && ExternalToolManifestTests.refusal(#"""
                             {"preferences": [{"id": "project", "title": "Project", "type": "string", "default": ""}]}
                             """#) == .invalid(.malformed(field: "preferences[0].title")),
                     "a title that breaks the manifest's rules refuses the tool, by a reason that names the preference")
    }

    /// What the store says a tool's settings are.
    static func listed(_ suite: TestSuite) {
        let bench = bench()
        defer { bench.close() }
        let fresh = bench.store.settings(of: id)
        suite.expect(fresh.map(\.id) == ["project", "notify", "limit", "ratio"]
                         && fresh.map(\.value) == [.string("web"), .bool(true), .int(5), .double(0.5)]
                         && fresh.first?.title == LocalizedText(["en": "Project", "fr": "Projet"]),
                     "a tool's settings are the preferences its author gave a title, in the manifest's order, each "
                         + "with its default while nothing is saved; the one with no title is not among them")
        bench.box.values[key("project")] = "api"
        bench.box.values[key("notify")] = false
        bench.box.values[key("limit")] = 7
        bench.box.values[key("ratio")] = 1.25
        bench.box.values[key("secret")] = "other"
        suite.expect(bench.store.settings(of: id).map(\.value) == [.string("api"), .bool(false), .int(7), .double(1.25)],
                     "and with what is saved once something is")
        bench.box.values[key("limit")] = "seven"
        suite.expect(bench.store.settings(of: id).map(\.value).dropFirst(2).first == .int(5),
                     "a saved value of another kind is shown as the default, as the tool itself would read it")

        bench.store.setOn(id, false)
        suite.expect(bench.store.settings(of: id).map(\.id) == ["project", "notify", "limit", "ratio"],
                     "a tool that is switched off still has its settings")
        suite.expect(bench.store.settings(of: ToolID("com.acme.other")!).isEmpty,
                     "a tool nobody added has none")
        try? Data("{}".utf8).write(to: bench.files.appendingPathComponent("vitruvian-tool.json"))
        let next = bench.relaunched()
        next.store.restore()
        suite.expect(next.store.listed.map(\.isHeld) == [true] && next.store.settings(of: id).isEmpty
                         && next.store.setSetting(.string("x"), for: "project", of: id) != nil
                         && next.box.values[key("project")] == nil,
                     "a tool that is held back shows no setting and takes no change: its manifest is not the one agreed to")

        let plain = self.bench("{}")
        defer { plain.close() }
        suite.expect(plain.store.settings(of: id).isEmpty && plain.store.installed[id]?.tool.manifest.preferences.count == 1,
                     "a tool whose preferences have no titles has no settings to show, and works as before")
    }

    /// The person changes a setting: where it is saved, and what is refused.
    static func changing(_ suite: TestSuite) {
        let bench = bench()
        defer { bench.close() }
        suite.expect(bench.store.setSetting(.string("api"), for: "project", of: id) == nil
                         && bench.box.values[key("project")] as? String == "api" && bench.box.values.count == 1
                         && bench.box.values["project"] == nil,
                     "a changed setting is saved under the tool's id, a slash and the preference's own, "
                         + "the key the tool reads it by, and under no other")
        suite.expect(bench.store.setSetting(.bool(false), for: "notify", of: id) == nil
                         && bench.box.values[key("notify")] as? Bool == false
                         && bench.store.setSetting(.int(9), for: "limit", of: id) == nil
                         && bench.box.values[key("limit")] as? Int == 9
                         && bench.store.setSetting(.double(2), for: "ratio", of: id) == nil
                         && bench.box.values[key("ratio")] as? Double == 2
                         && bench.store.settings(of: id).map(\.value) == [.string("api"), .bool(false), .int(9), .double(2)],
                     "a yes or no, a whole number and a number are each saved as what the preference is")

        let saved = bench.box.values.count
        let wrong: [(PreferenceDeclaration.Value, String)] = [
            (.bool(true), "project"), (.int(3), "project"), (.string("yes"), "notify"), (.double(1.5), "limit"),
            (.string("9"), "limit"), (.int(2), "ratio"), (.double(.infinity), "ratio"), (.double(.nan), "ratio"),
        ]
        suite.expect(wrong.allSatisfy { bench.store.setSetting($0.0, for: $0.1, of: id) == .wrongKind(key($0.1)) }
                         && bench.box.values.count == saved && bench.box.values[key("project")] as? String == "api"
                         && bench.box.values[key("limit")] as? Int == 9 && bench.box.values[key("ratio")] as? Double == 2,
                     "a value of another kind than the preference's, and a number that is no number, is refused "
                         + "and nothing is saved")

        let most = String(repeating: "é", count: StorageLimits.maxTextLength)
        suite.expect(StorageLimits.maxTextLength == 4_096
                         && bench.store.setSetting(.string(most), for: "project", of: id) == nil
                         && bench.box.values[key("project")] as? String == most
                         && bench.store.setSetting(.string(most + "é"), for: "project", of: id) == .tooLong(key("project"))
                         && bench.box.values[key("project")] as? String == most,
                     "text of 4,096 characters is saved, and one character more is refused with nothing saved")

        suite.expect(bench.store.setSetting(.string("mine"), for: "secret", of: id) == .undeclared("secret")
                         && bench.box.values[key("secret")] == nil,
                     "a preference with no title cannot be changed from the screen: the person was never shown it")

        // Another tool, with a preference of the same name.
        let other = ToolID("com.acme.other")!
        bench.add(bench.folder("other", manifest: ExternalToolManifestTests.file(#"""
            {"id": "com.acme.other", "name": {"en": "Other"},
             "preferences": [{"id": "project", "title": {"en": "Project"}, "type": "string", "default": ""}]}
            """#)))
        bench.box.values["appLanguage"] = "fr"
        let before = bench.box.values.count
        var reached = false
        for name in ["../com.acme.deploys/project", "com.acme.deploys/project", key("project"), "/project",
                     "appLanguage", "", "nothing"] where bench.store.setSetting(.string("theirs"), for: name, of: other) == nil {
            reached = true
        }
        suite.expect(!reached && bench.box.values.count == before && bench.box.values[key("project")] as? String == most
                         && bench.box.values["appLanguage"] as? String == "fr"
                         && bench.store.setSetting(.string("theirs"), for: "project", of: other) == nil
                         && bench.box.values[key("project", of: other)] as? String == "theirs"
                         && bench.box.values[key("project")] as? String == most
                         && bench.box.values.count == before + 1,
                     "no name reaches another tool's settings or the app's own: a change is looked up among the "
                         + "tool's own titled preferences, and saved under that tool's id alone")
        suite.expect(bench.store.setSetting(.string("x"), for: "project", of: ToolID("com.acme.nobody")!) == .undeclared("project")
                         && bench.box.values.count == before + 1,
                     "a change for a tool nobody added saves nothing")
    }

    /// A running tool is told what changed: once, with the protocol's own
    /// params, and only when it can hear.
    static func told(_ suite: TestSuite) {
        let bench = bench()
        defer { bench.close() }
        suite.expect(bench.store.setSetting(.string("early"), for: "project", of: id) == nil && bench.runs.isEmpty
                         && bench.started.isEmpty && bench.store.listed.first?.standing == .resting,
                     "changing a setting of a tool that is not running saves it and starts nothing: "
                         + "the tool reads it when it next starts")

        bench.registry.run(copy)
        let run = bench.current
        suite.expect(bench.store.listed.first?.standing == .starting
                         && bench.store.setSetting(.string("sooner"), for: "project", of: id) == nil
                         && bench.box.values[key("project")] as? String == "sooner"
                         && run.sent.count == 1 && notices(run).isEmpty,
                     "a tool that has not answered initialize yet is told nothing: until then neither side says "
                         + "anything else")
        run.greets()
        suite.expect(notices(run).isEmpty, "and nothing is sent late for what changed before it was ready")

        let changes: [(PreferenceDeclaration.Value, String)] = [(.string("acme"), "project"), (.bool(false), "notify"),
                                                               (.int(20), "limit")]
        var counts: [Int] = []
        for change in changes {
            bench.store.setSetting(change.0, for: change.1, of: id)
            counts.append(notices(run).count)
        }
        suite.expect(counts == [1, 2, 3]
                         && notices(run) == [["project": .string("acme")], ["notify": .bool(false)], ["limit": .number(20)]],
                     "a running tool is sent preferences/changed once for each change, with the preference's own id "
                         + "and its new value")
        let wanted = example?["params"]?["values"]?.objectValue
        let sent = notices(run).reduce(into: [String: JSONValue]()) { all, one in all.merge(one) { _, new in new } }
        let whole = run.sent.last.flatMap { try? JSONValue(encoding: $0) }
        suite.expect(wanted != nil && sent == wanted
                         && whole == .object(["jsonrpc": .string("2.0"), "method": .string("preferences/changed"),
                                              "params": .object(["values": .object(["limit": .number(20)])])]),
                     "what it is sent is the protocol's own example of the message: a notice with no id, whose "
                         + "params hold the values and nothing else")

        let before = run.sent.count
        suite.expect(bench.store.setSetting(.int(20), for: "limit", of: id) == nil && run.sent.count == before,
                     "saving the value a setting already has changes nothing, and says nothing")
        suite.expect(bench.store.setSetting(.string("9"), for: "limit", of: id) != nil
                         && bench.store.setSetting(.string("mine"), for: "secret", of: id) != nil
                         && run.sent.count == before,
                     "a change that was refused is not announced")
        suite.expect(bench.store.setSetting(.double(0.75), for: "ratio", of: id) == nil && run.sent.count == before + 1
                         && notices(run).last == ["ratio": .number(0.75)] && !run.inputClosed
                         && bench.store.listed.first?.standing == .running,
                     "a number is sent as a number, and the tool runs on: it is not restarted to hear it")

        // Crashed and held back for its wait: there is nobody to tell.
        run.ends(1)
        suite.expect(bench.store.listed.first?.standing == .waiting
                         && bench.store.setSetting(.int(21), for: "limit", of: id) == nil
                         && bench.box.values[key("limit")] as? Int == 21 && run.sent.count == before + 1
                         && bench.runs.count == 1,
                     "a tool that stopped is told nothing, and the change is saved all the same")

        bench.store.setOn(id, false)
        suite.expect(bench.store.setSetting(.int(22), for: "limit", of: id) == nil
                         && bench.box.values[key("limit")] as? Int == 22 && bench.runs.count == 1
                         && bench.store.listed.first?.standing == nil,
                     "a tool that is switched off is told nothing either: its setting is saved for when it is on again")
    }

    /// The tool's settings as its detail shows them.
    static func inTheDetail(_ suite: TestSuite) {
        let bench = bench()
        defer { bench.close() }
        bench.box.values[key("limit")] = 7
        func detail(_ bench: ExternalToolStoreTests.Bench, _ language: AppLanguage = .enUS) -> ExternalToolDetail? {
            bench.store.listed.first.map {
                ExternalToolDetail($0, files: nil, language: language, strings: FeatureStrings.externalTools(language),
                                   settings: bench.store.settings(of: $0.id), settingsTitle: "Settings")
            }
        }
        let shown = detail(bench)
        suite.expect(shown?.settingsTitle == "Settings"
                         && shown?.settings.map(\.title) == ["Project", "Tell me when a deploy ends", "Deploys to list", "Ratio"]
                         && shown?.settings.map(\.control) == [.text("web"), .toggle(true), .whole(7), .number(0.5)]
                         && shown?.settings.map(\.id) == ["project", "notify", "limit", "ratio"],
                     "a tool's detail lists its settings under the app's word for them: a text field for text, a "
                         + "switch for yes or no, a number field for a number, each showing the saved value or the default")
        let words = (shown?.settings.map(\.title) ?? []) + (shown?.commands ?? []) + (shown?.uses ?? [])
        suite.expect(shown?.settings.count == 4 && !words.contains("secret")
                         && !words.contains { $0.contains("secret") || $0.contains("s3cret") },
                     "a preference with no title is not shown: not by its id, and not by its value")
        suite.expect(detail(bench, .fr)?.settings.map(\.title)
                         == ["Projet", "Tell me when a deploy ends", "Deploys to list", "Ratio"],
                     "a title is shown in the person's language where its author wrote one, and in English where not")
        suite.expect(shown?.listRows == 8 && shown?.listsScroll == true
                         && shown?.settings.map(\.control.value) == [.string("web"), .bool(true), .int(7), .double(0.5)],
                     "the settings count among the detail's rows, so a long list of them scrolls with the rest; "
                         + "and what a control holds is saved as the kind of value the preference is")

        // The most a tool may declare, every one with a title.
        let titled = ExternalToolManifestTests.list(16) {
            #"{"id": "p\#($0)", "title": {"en": "Setting \#($0)"}, "type": "boolean", "default": false}"#
        }
        let full = self.bench(#"{"uses": null, "contributes": null, "preferences": \#(titled)}"#)
        defer { full.close() }
        let many = detail(full)
        suite.expect(many?.settings.count == 16 && many?.settings.first?.title == "Setting 0"
                         && many?.settings.last?.title == "Setting 15" && many?.commands.isEmpty == true
                         && many?.uses.isEmpty == true && many?.listRows == 16 && many?.listsScroll == true,
                     "sixteen settings, the most a tool may have, are all listed, and scroll in the region the "
                         + "lists share, so the detail is no taller for them")

        // A title is one short line of plain text, whatever it holds.
        func setting(_ title: String) -> ExternalToolSetting {
            ExternalToolSetting(ExternalToolStore.Setting(id: "project", title: LocalizedText(["en": title]),
                                                          value: .string("")), language: .enUS)
        }
        let long = setting("Pro\nject\u{202E}" + String(repeating: "x", count: 50_000))
        suite.expect(long.title.hasPrefix("Pro jectxxx") && long.title.hasSuffix("…") && long.title.count == 60
                         && !long.title.contains("\n") && !long.title.unicodeScalars.contains("\u{202E}")
                         && setting("**Bold** [free](https://example.invalid)").title == "**Bold** [free](https://example.invalid)",
                     "a setting's title is drawn as one line of plain text of at most 60 characters, with markdown "
                         + "and a link in it left as written")
        let blank = ExternalToolStore.Setting(id: "project", title: LocalizedText(["en": " \n "]), value: .string(""))
        if let listed = bench.store.listed.first {
            let odd = ExternalToolDetail(listed, files: nil, language: .enUS, strings: english,
                                         settings: [blank] + bench.store.settings(of: id), settingsTitle: "Settings")
            suite.expect(odd.settings.map(\.id) == ["project", "notify", "limit", "ratio"]
                             && odd.settings.first?.title == "Project",
                         "a setting whose title would draw as nothing is left out, never drawn by its id")
        }
        if let listed = bench.store.listed.first {
            let none = ExternalToolDetail(listed, files: nil, language: .enUS, strings: english)
            suite.expect(none.settings.isEmpty && none.listRows == 4,
                         "with no settings handed to it the detail is as it was: four rows for the design's example")
        }
    }
}
