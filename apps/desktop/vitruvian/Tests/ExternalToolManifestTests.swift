// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import Foundation
import VitruvianCore
import VitruvianToolProtocol

/// A tool's manifest file, read into the platform's own manifest. Nothing
/// here starts a program: the folders are made in the temporary folder and
/// hold empty files.
enum ExternalToolManifestTests {
    static func run(_ suite: TestSuite) {
        theDesignsExample(suite)
        whatIsLeftOut(suite)
        refusals(suite)
        services(suite)
        listsAgree(suite)
        languages(suite)
        folders(suite)
        panels(suite)
        statusAndOptions(suite)
    }

    /// The manifest in the design, section 6, with a publisher.
    static let example = """
        {
          "id": "com.acme.deploys",
          "name": { "en": "Deploys", "fr": "Déploiements" },
          "description": { "en": "Copies the address of your latest deploy." },
          "version": "1.2.0",
          "protocol": "1",
          "publisher": "Acme",
          "license": "MIT",
          "icon": "shippingbox",
          "uses": ["clipboard.write", "notify", "storage"],
          "contributes": {
            "commands": [
              { "id": "copyLatest", "title": { "en": "Copy latest deploy" }, "icon": "link",
                "surfaces": ["commandBar", "radial", "shortcut"] }
            ]
          },
          "preferences": [ { "id": "project", "type": "string", "default": "" } ],
          "activation": ["onCommand"],
          "runtime": { "kind": "external", "exec": "bin/deploys" }
        }
        """

    /// The example with some of its top-level fields replaced, as the bytes
    /// of a file. `change` is a JSON object; a field it sets to null is left
    /// out.
    static func file(_ change: String = "{}") -> Data {
        var fields = object(example)
        for (key, value) in object(change) {
            if value is NSNull {
                fields.removeValue(forKey: key)
            } else {
                fields[key] = value
            }
        }
        return (try? JSONSerialization.data(withJSONObject: fields)) ?? Data()
    }

    static func object(_ text: String) -> [String: Any] {
        ((try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any]) ?? [:]
    }

    static func tool(_ change: String = "{}") -> ExternalToolManifest? {
        try? ExternalToolManifest.read(file(change)).get()
    }

    static func refusal(_ change: String) -> ManifestRefusal? {
        if case .failure(let refusal) = ExternalToolManifest.read(file(change)) { return refusal }
        return nil
    }

    /// `count` things written as JSON, in a list.
    static func list(_ count: Int, _ item: (Int) -> String) -> String {
        "[" + (0..<count).map(item).joined(separator: ",") + "]"
    }

    static func theDesignsExample(_ suite: TestSuite) {
        guard let tool = tool() else {
            suite.expect(false, "the manifest in the design is read")
            return
        }
        let id = ToolID("com.acme.deploys")!
        let command = CommandID(tool: id, name: "copyLatest")!
        let manifest = tool.manifest
        suite.expect(manifest.id == id && manifest.tool.name == "Deploys" && manifest.tool.symbol == "shippingbox"
                         && manifest.tool.feature == nil,
                     "an outside tool has its own id, its English name and its icon, and is no hub feature")
        suite.expect(manifest.tool.commands
                         == [CommandDescriptor(id: command, title: "Copy latest deploy", symbol: "link",
                                               surfaces: [.commandBar, .radial, .shortcut])!],
                     "a command is the tool's id, a slash and its own, with its English title and its surfaces")
        suite.expect(manifest.capabilities.map(\.capability) == [.clipboardWrite, .notify, .storage]
                         && manifest.capabilities.allSatisfy { $0.reason.isEmpty && !$0.startsWithoutGrant },
                     "uses becomes the capabilities the tool declares, in order, with no reasons")
        suite.expect(manifest.preferences
                         == [PreferenceDeclaration(key: "com.acme.deploys/project", default: .string(""))]
                         && ExternalToolManifest.storageKey(tool: id, preference: "project")
                         == "com.acme.deploys/project",
                     "a preference is saved under the tool's id, a slash and its own")
        suite.expect(manifest.activation == [.onCommand] && manifest.group == .tools && manifest.enabledBy == nil,
                     "it starts on its first command, is filed under Tools and has no switch of its own")
        suite.expect(tool.version == "1.2.0" && tool.publisher == "Acme" && tool.license == "MIT"
                         && tool.protocolVersion == "1" && tool.program == "bin/deploys",
                     "what only an outside tool carries is kept: version, publisher, licence, protocol, program")
        suite.expect(tool.name.byLanguage == ["en": "Deploys", "fr": "Déploiements"]
                         && tool.summary?.english == "Copies the address of your latest deploy."
                         && tool.commandTitles == [command: LocalizedText(["en": "Copy latest deploy"])],
                     "every language the author wrote is kept beside the English the descriptors hold")
    }

    static func whatIsLeftOut(_ suite: TestSuite) {
        let bare = tool(#"""
            {"description": null, "license": null, "icon": null, "uses": null, "contributes": null,
             "preferences": null, "activation": null}
            """#)
        suite.expect(bare?.manifest.capabilities.isEmpty == true && bare?.manifest.tool.commands.isEmpty == true
                         && bare?.manifest.preferences.isEmpty == true && bare?.manifest.activation == [.onCommand]
                         && bare?.manifest.tool.symbol == "puzzlepiece.extension" && bare?.summary == nil
                         && bare?.license == nil,
                     "only the required fields: no capability, command or preference, a plain puzzle piece, "
                         + "started on its first command")
        let borrowed = tool(#"{"contributes": {"commands": [{"id": "copyLatest", "title": {"en": "Copy"}}]}}"#)
        suite.expect(borrowed?.manifest.tool.commands.first?.symbol == "shippingbox"
                         && borrowed?.manifest.tool.commands.first?.surfaces.isEmpty == true,
                     "a command with no icon takes the tool's, and with no surfaces is listed nowhere")
        suite.expect(tool(#"{"icon": "  "}"#)?.manifest.tool.symbol == "puzzlepiece.extension",
                     "an icon that is only spaces is no icon")
        let later = tool(#"""
            {"future": {"anything": 1},
             "runtime": {"kind": "external", "exec": "bin/deploys", "arguments": ["--fast"]},
             "contributes": {"islandNotices": [], "commands": [
               {"id": "copyLatest", "title": {"en": "Copy latest deploy"}, "icon": "link",
                "surfaces": ["commandBar", "radial", "shortcut"], "argument": "later"}]}}
            """#)
        suite.expect(later != nil && later == tool(),
                     "fields a later protocol might add are ignored, wherever they are")
        suite.expect(tool(#"{"activation": ["onLaunch", "onCommand", "onLaunch"]}"#)?.manifest.activation
                         == [.onLaunch, .onCommand],
                     "each way of starting is kept once, in the order written")
    }

    static func refusals(_ suite: TestSuite) {
        let manyCommands = list(33) { #"{"id": "c\#($0)", "title": {"en": "Command"}}"# }
        let manyPreferences = list(17) { #"{"id": "p\#($0)", "type": "boolean", "default": false}"# }
        let cases: [(String, ManifestRefusal, String)] = [
            ("an id with no dot, which is a built-in feature's", .invalid(.idWithoutDot("pastePlain")),
             #"{"id": "pastePlain"}"#),
            ("an id with a character ids do not have", .invalid(.idNotWellFormed("com.acme/deploys")),
             #"{"id": "com.acme/deploys"}"#),
            ("a service the app does not have", .invalid(.unknownService("camera")),
             #"{"uses": ["notify", "camera"]}"#),
            ("a service built-in tools have and the protocol does not offer", .invalid(.unknownService("hotkey")),
             #"{"uses": ["hotkey"]}"#),
            ("a service listed twice", .invalid(.duplicateService("notify")), #"{"uses": ["notify", "notify"]}"#),
            ("a surface the app does not have", .invalid(.unknownSurface(command: "copyLatest", surface: "island")),
             #"{"contributes": {"commands": [{"id": "copyLatest", "title": {"en": "Copy"}, "surfaces": ["island"]}]}}"#),
            ("a kind of preference the app does not have",
             .invalid(.unknownPreferenceType(preference: "project", type: "color")),
             #"{"preferences": [{"id": "project", "type": "color", "default": "red"}]}"#),
            ("a default of another type", .invalid(.defaultOfWrongType(preference: "limit")),
             #"{"preferences": [{"id": "limit", "type": "integer", "default": "20"}]}"#),
            ("a way of starting only built-in tools have", .invalid(.unknownActivation("onShown")),
             #"{"activation": ["onShown"]}"#),
            ("a program above the folder", .invalid(.programLeavesFolder("../deploys")),
             #"{"runtime": {"kind": "external", "exec": "../deploys"}}"#),
            ("a program named from the root of the disk", .invalid(.programLeavesFolder("/usr/bin/true")),
             #"{"runtime": {"kind": "external", "exec": "/usr/bin/true"}}"#),
            ("a program that climbs out part way along", .invalid(.programLeavesFolder("bin/../../deploys")),
             #"{"runtime": {"kind": "external", "exec": "bin/../../deploys"}}"#),
            ("a kind of runtime a file may not name", .invalid(.unsupportedRuntime("bundled")),
             #"{"runtime": {"kind": "bundled", "exec": "bin/deploys"}}"#),
            ("a protocol the app does not speak", .invalid(.unsupportedProtocol("3")), #"{"protocol": "3"}"#),
            ("a name with no English", .invalid(.noEnglish(field: "name")), #"{"name": {"fr": "Déploiements"}}"#),
            ("a name that is only spaces", .invalid(.blankText(field: "name")), #"{"name": {"en": " "}}"#),
            ("no publisher", .invalid(.malformed(field: "publisher")), #"{"publisher": null}"#),
            ("no runtime", .invalid(.malformed(field: "runtime")), #"{"runtime": null}"#),
            ("two commands with one id", .invalid(.duplicateCommand("copyLatest")),
             #"""
             {"contributes": {"commands": [{"id": "copyLatest", "title": {"en": "Copy"}},
                                           {"id": "copyLatest", "title": {"en": "Copy again"}}]}}
             """#),
            ("two preferences with one id", .invalid(.duplicatePreference("project")),
             #"""
             {"preferences": [{"id": "project", "type": "string", "default": ""},
                              {"id": "project", "type": "boolean", "default": false}]}
             """#),
            ("options on a setting that is not text", .invalid(.optionsNeedString(preference: "loud")),
             #"""
             {"preferences": [{"id": "loud", "type": "boolean", "default": true,
                               "options": [{"value": "yes", "title": {"en": "Yes"}}]}]}
             """#),
            ("a default that is none of the options", .invalid(.defaultNotAnOption(preference: "project")),
             #"""
             {"preferences": [{"id": "project", "type": "string", "default": "initech",
                               "options": [{"value": "acme", "title": {"en": "Acme"}}]}]}
             """#),
            ("two options with one value", .invalid(.duplicateOption(preference: "project", value: "acme")),
             #"""
             {"preferences": [{"id": "project", "type": "string", "default": "acme",
                               "options": [{"value": "acme", "title": {"en": "Acme"}},
                                           {"value": "acme", "title": {"en": "Acme again"}}]}]}
             """#),
            ("an empty list of options", .invalid(.optionCountOutOfRange(preference: "project", count: 0)),
             #"{"preferences": [{"id": "project", "type": "string", "default": "", "options": []}]}"#),
            ("a status in a manifest of protocol 1", .invalid(.statusNeedsProtocol2("1")),
             #"{"contributes": {"status": {"placement": "island"}}}"#),
            ("a status in a place the app does not have", .invalid(.unknownStatusPlacement("menuBar")),
             #"{"protocol": "2", "contributes": {"status": {"placement": "menuBar"}}}"#),
            ("a kind of preference no app has, with options",
             .invalid(.unknownPreferenceType(preference: "project", type: "choice")),
             #"""
             {"preferences": [{"id": "project", "type": "choice", "default": "acme",
                               "options": [{"value": "acme", "title": {"en": "Acme"}}]}]}
             """#),
            ("more commands than a tool may have", .invalid(.tooManyCommands(33)),
             #"{"contributes": {"commands": \#(manyCommands)}}"#),
            ("more preferences than a tool may have", .invalid(.tooManyPreferences(17)),
             #"{"preferences": \#(manyPreferences)}"#),
        ]
        for (what, wanted, change) in cases {
            let got = refusal(change)
            suite.expect(got == wanted, "\(what) is refused, and the reason names it: \(String(describing: got))")
        }

        let longest = "com." + String(repeating: "a", count: ToolID.maxLength - 4)
        suite.expect(tool(#"{"id": "\#(longest)"}"#)?.manifest.id.rawValue == longest
                         && refusal(#"{"id": "\#(longest)a"}"#) == .invalid(.idNotWellFormed(longest + "a")),
                     "an id may be 128 characters and no longer")
        let padding = String(repeating: "x", count: ManifestLimits.maxBytes)
        let padded = file(#"{"description": {"en": "\#(padding)"}}"#)
        suite.expect(ExternalToolManifest.read(padded) == .failure(.invalid(.tooLarge(bytes: padded.count))),
                     "a manifest over 64 KB is refused before it is read as JSON")
        suite.expect(ExternalToolManifest.read(Data("not json".utf8)) == .failure(.invalid(.notJSON)),
                     "a file that is not JSON is refused, not crashed on")
    }

    static func services(_ suite: TestSuite) {
        let typing = tool(#"{"uses": ["keystrokes", "clipboard.read"]}"#)
        suite.expect(typing?.manifest.capabilities.first?.startsWithoutGrant == true
                         && typing?.manifest.grantsNeededToStart == []
                         && typing?.manifest.declares(.keystrokes) == true,
                     "an outside tool that uses keystrokes starts without Accessibility, and is refused call by call")
        suite.expect(typing?.manifest.capabilities.last?.startsWithoutGrant == false,
                     "a service that rides on no grant has nothing to start without")
        suite.expect(CapabilityRequest(.open, reason: " ") == nil,
                     "a built-in tool's request still needs its reason")
    }

    /// The protocol's lists and the app's. Every name a manifest may hold has
    /// a place in the app, so `notOfferedHere` is not reached today; it is
    /// what a future protocol name meets in an app that does not have it.
    static func listsAgree(_ suite: TestSuite) {
        suite.expect(AppService.allCases.allSatisfy { Capability(rawValue: $0.rawValue) != nil },
                     "every service the protocol offers is one of the app's capabilities")
        suite.expect(Set(Capability.allCases.map(\.rawValue)).subtracting(AppService.allCases.map(\.rawValue))
                         == ["clipboard.rewrite", "hotkey"],
                     "two capabilities are for built-in tools only: rewriting the clipboard, and a hotkey")
        suite.expect(Set(SurfaceName.allCases.map(\.rawValue)) == Set(ToolSurface.allCases.map(\.rawValue)),
                     "the protocol's surfaces are the app's")
        suite.expect(ActivationName.allCases.allSatisfy { Activation(rawValue: $0.rawValue) != nil },
                     "every way of starting the protocol has is one the app has")
        let samples: [(PreferenceKind, JSONValue, PreferenceDeclaration.Value)] = [
            (.string, .string("a"), .string("a")), (.boolean, .bool(true), .bool(true)),
            (.integer, .number(20), .int(20)), (.number, .number(0.5), .double(0.5)),
        ]
        suite.expect(samples.map(\.0) == PreferenceKind.allCases
                         && samples.allSatisfy { ExternalToolManifest.value($0.1, ofKind: $0.0.rawValue) == $0.2 },
                     "every kind of preference the protocol has is a value the app can hold")
        suite.expect(ExternalToolManifest.value(.string("#fff"), ofKind: "color") == nil
                         && ExternalToolManifest.value(.number(1.5), ofKind: "integer") == nil,
                     "a kind the app has no value for is nil, for the reader to refuse by name")
        let names = ["com.acme.deploys", "copyLatest", "a-b_c.9", "", ".a", "a.", "a..b", "a b", "a/b", "é",
                     String(repeating: "a", count: 128), String(repeating: "a", count: 129)]
        suite.expect(names.allSatisfy { ManifestRules.isWellFormedName($0) == (ToolID($0) != nil) }
                         && ManifestLimits.maxNameLength == ToolID.maxLength,
                     "the protocol and the app agree on what a well-formed id is")
        suite.expect(ProtocolVersion.supported == ["1", "2"] && WireLimits.maxLineBytes == 1_048_576,
                     "the app links protocol versions 1 and 2, with the 1 MB line")
        suite.expect(PanelPlacement.allCases.map(\.rawValue) == ToolPanelPlacement.allCases.map(\.rawValue),
                     "the protocol's placements are the app's")
    }

    static func languages(_ suite: TestSuite) {
        let named = tool(#"{"name": {"en": "Deploys", "fr": "Déploiements", "pt": "Implantações", "zh-Hans": "部署"}}"#)
        suite.expect(named?.manifest.tool.name == "Deploys", "the descriptor holds the English name")
        suite.expect(named?.name.text(for: AppLanguage.fr.rawValue) == "Déploiements"
                         && named?.name.text(for: AppLanguage.ptBR.rawValue) == "Implantações"
                         && named?.name.text(for: AppLanguage.zhHans.rawValue) == "部署"
                         && named?.name.text(for: AppLanguage.zhTW.rawValue) == "Deploys"
                         && named?.name.text(for: AppLanguage.enUS.rawValue) == "Deploys",
                     "a language is its own entry, else its language without the region, else English")
        suite.expect(AppLanguage.allCases.allSatisfy { named?.name.text(for: $0.rawValue)?.isEmpty == false },
                     "every language the app has gets a name")
    }

    static func folders(_ suite: TestSuite) {
        let files = FileManager.default
        let root = files.temporaryDirectory.appendingPathComponent("vitru-tool-manifest-\(UUID().uuidString)")
        defer { try? files.removeItem(at: root) }

        // A folder under `root` holding a manifest and a program, each
        // unless nil.
        func make(_ name: String, manifest: Data? = ExternalToolManifestTests.file(), program: String? = "bin/deploys",
                  mode: Int = 0o755) -> URL {
            let made = root.appendingPathComponent(name)
            try? files.createDirectory(at: made.appendingPathComponent("bin"), withIntermediateDirectories: true)
            if let manifest {
                files.createFile(atPath: made.appendingPathComponent("vitruvian-tool.json").path, contents: manifest)
            }
            if let program {
                files.createFile(atPath: made.appendingPathComponent(program).path, contents: Data(),
                                 attributes: [.posixPermissions: mode])
            }
            return made
        }
        func refused(_ folder: URL) -> ManifestRefusal? {
            if case .failure(let refusal) = ExternalToolManifest.read(folder: folder) { return refusal }
            return nil
        }

        suite.expect((try? ExternalToolManifest.read(folder: make("whole")).get()) == tool(),
                     "a folder with a manifest and its program is read as the manifest alone is")
        suite.expect(refused(make("empty", manifest: nil)) == .noManifest
                         && refused(root.appendingPathComponent("nowhere")) == .noManifest,
                     "a folder with no manifest, or no folder at all, is refused")
        suite.expect(refused(make("no-program", program: nil)) == .programMissing("bin/deploys"),
                     "a manifest whose program is not there is refused")
        suite.expect(refused(make("not-runnable", mode: 0o644)) == .programNotExecutable("bin/deploys"),
                     "a program macOS will not run is refused")
        let holdsFolder = make("holds-a-folder", program: nil)
        try? files.createDirectory(at: holdsFolder.appendingPathComponent("bin/deploys"),
                                   withIntermediateDirectories: true)
        suite.expect(refused(holdsFolder) == .programMissing("bin/deploys"),
                     "a folder where the program should be is no program")

        let outside = make("outside", manifest: nil, program: "bin/real")
        let linked = make("linked", program: nil)
        try? files.createSymbolicLink(at: linked.appendingPathComponent("bin/deploys"),
                                      withDestinationURL: outside.appendingPathComponent("bin/real"))
        suite.expect(refused(linked) == .programOutsideFolder("bin/deploys"),
                     "a program that is a link to a file outside the folder is refused")
        let within = make("within", program: "bin/real")
        try? files.createSymbolicLink(at: within.appendingPathComponent("bin/deploys"),
                                      withDestinationURL: within.appendingPathComponent("bin/real"))
        suite.expect(refused(within) == nil, "a link to a file inside the folder is the tool's own business")

        let padding = String(repeating: "x", count: ManifestLimits.maxBytes)
        let padded = file(#"{"description": {"en": "\#(padding)"}}"#)
        suite.expect(refused(make("large", manifest: padded)) == .invalid(.tooLarge(bytes: padded.count)),
                     "a manifest over 64 KB on disk is refused by its size")
        suite.expect(refused(make("breaks-a-rule", manifest: file(#"{"id": "deploys"}"#)))
                         == .invalid(.idWithoutDot("deploys")),
                     "a manifest that breaks a rule is refused for that rule, whatever the folder holds")
    }
}

extension ExternalToolManifestTests {
    /// Protocol 2's panels: read into descriptors the app's lists hold, and
    /// refused in a manifest of protocol 1.
    static func panels(_ suite: TestSuite) {
        let three = #"""
            {"protocol": "2", "contributes": {"commands": [{"id": "copyLatest", "title": {"en": "Copy"}}], "panels": [
              {"id": "deploys", "title": {"en": "Deploys", "fr": "Déploiements"}, "placement": "island", "icon": "list.bullet"},
              {"id": "settings", "title": {"en": "Deploys"}, "placement": "settings", "entry": "ignored.html"},
              {"id": "dashboard", "title": {"en": "Dashboard"}, "placement": "window", "kind": "web", "entry": "ui/dashboard.html"}
            ]}}
            """#
        let drawn = tool(three)
        suite.expect(drawn?.panels.map(\.id) == ["deploys", "settings", "dashboard"]
                         && drawn?.panels.map(\.placement) == [.island, .settings, .window],
                     "a tool of protocol 2 has its panels, in the manifest's order, each in its place")
        suite.expect(drawn?.panel("deploys")?.symbol == "list.bullet" && drawn?.panel("settings")?.symbol == "shippingbox",
                     "a panel's icon is its own, else the tool's")
        suite.expect(drawn?.panel("dashboard")?.entry == "ui/dashboard.html" && drawn?.panel("dashboard")?.isWeb == true
                         && drawn?.panel("settings")?.entry == nil && drawn?.panel("settings")?.isWeb == false,
                     "only a web panel has a page; a blocks panel ignores an entry")
        suite.expect(drawn?.panel(in: .island)?.id == "deploys" && drawn?.panel(in: .settings)?.id == "settings"
                         && drawn?.panel("nothing") == nil,
                     "a panel is found by its id, and the island's and Settings' by their place")
        suite.expect(drawn?.panel("deploys")?.title.text(for: AppLanguage.fr.rawValue) == "Déploiements",
                     "a panel's title is in every language its author wrote")
        suite.expect(drawn?.manifest.tool.commands.map(\.id.name) == ["copyLatest"] && drawn?.protocolVersion == "2",
                     "protocol 2 changes nothing else the manifest says")

        let plain = tool()
        suite.expect(plain?.panels.isEmpty == true && plain?.protocolVersion == "1",
                     "a tool of protocol 1 has no panels and is read as it always was")
        suite.expect(refusal(#"{"contributes": {"panels": [{"id": "deploys", "title": {"en": "Deploys"}, "placement": "island"}]}}"#)
                         == .invalid(.panelsNeedProtocol2("1")),
                     "a manifest of protocol 1 with panels is refused, and the reason names its protocol")
        suite.expect(refusal(#"{"protocol": "3"}"#) == .invalid(.unsupportedProtocol("3")),
                     "a protocol after 2 is refused")
        suite.expect(refusal(#"{"protocol": "2", "contributes": {"panels": [{"id": "d", "title": {"en": "D"}, "placement": "window", "kind": "web", "entry": "../page.html"}]}}"#)
                         == .invalid(.panelEntryLeavesFolder(panel: "d", entry: "../page.html")),
                     "a web panel's page that leaves the folder by its text is refused, as the program is")
    }
}

extension ExternalToolManifestTests {
    /// A status the manifest declares, and a preference's options, reach
    /// the app's own description of the tool; a manifest with neither is
    /// read as it always was.
    static func statusAndOptions(_ suite: TestSuite) {
        let declared = tool(#"""
            {"protocol": "2", "contributes": {"status": {"placement": "island"}},
             "preferences": [
               {"id": "light", "title": {"en": "Light"}, "type": "string", "default": "green",
                "options": [{"value": "green", "title": {"en": "Green", "fr": "Vert"}},
                            {"value": "", "title": {"en": "None"}}]},
               {"id": "project", "title": {"en": "Project"}, "type": "string", "default": ""},
               {"id": "hidden", "type": "string", "default": "a",
                "options": [{"value": "a", "title": {"en": "A"}}]}]}
            """#)
        let light = storageKey("light")
        suite.expect(declared?.showsStatus == true, "a manifest that declares a status is a tool that shows one")
        suite.expect(declared?.preferenceOptions[light]
                         == [PreferenceOption(value: "green", title: LocalizedText(["en": "Green", "fr": "Vert"])),
                             PreferenceOption(value: "", title: LocalizedText(["en": "None"]))]
                         && declared?.preferenceOptions[storageKey("project")] == nil
                         && declared?.preferenceOptions[storageKey("hidden")]?.map(\.value) == ["a"],
                     "a preference's options are kept in order, each title in every language written, under the "
                         + "key the preference is saved by; a preference with none has none")
        suite.expect(declared?.manifest.preferences
                         == [PreferenceDeclaration(key: light, default: .string("green")),
                             PreferenceDeclaration(key: storageKey("project"), default: .string("")),
                             PreferenceDeclaration(key: storageKey("hidden"), default: .string("a"))],
                     "what the tool reads and writes is text, with options or without: they are how the app draws")
        let plain = tool()
        suite.expect(plain?.showsStatus == false && plain?.preferenceOptions.isEmpty == true
                         && tool(#"{"protocol": "2"}"#)?.showsStatus == false,
                     "a manifest with neither is read as it always was: no status, and no options")
    }

    static func storageKey(_ preference: String) -> String {
        ExternalToolManifest.storageKey(tool: ToolID("com.acme.deploys")!, preference: preference)
    }
}
