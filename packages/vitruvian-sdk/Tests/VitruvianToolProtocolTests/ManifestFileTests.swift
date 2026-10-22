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

import VitruvianToolProtocol

/// The manifest's Swift type and its rules, held to `manifest.schema.json`
/// through the examples both read.
final class ManifestFileTests: XCTestCase {
    private var file: JSONValue { ProtocolFiles.json("protocol/examples/manifests.json") }

    /// The example manifest with some top-level fields replaced. A field
    /// replaced by null is left out.
    private func manifest(changing change: [String: JSONValue] = [:]) -> Data {
        var fields = file["base"]?.objectValue ?? [:]
        for (key, value) in change {
            fields[key] = value == .null ? nil : value
        }
        return (try? JSONEncoder().encode(JSONValue.object(fields))) ?? Data()
    }

    private func problem(_ change: [String: JSONValue]) -> ManifestProblem? {
        if case .failure(let problem) = ToolManifestFile.read(manifest(changing: change)) { return problem }
        return nil
    }

    /// The name of a problem's case, without what it carries.
    private func caseName(_ problem: ManifestProblem) -> String {
        Mirror(reflecting: problem).children.first?.label ?? String(describing: problem)
    }

    func testEveryExampleIsJudgedAsTheSchemaJudgesIt() {
        let examples = file["examples"]?.arrayValue ?? []
        XCTAssertFalse(examples.isEmpty)
        for example in examples {
            let about = example["about"]?.stringValue ?? "?"
            switch ToolManifestFile.read(manifest(changing: example["change"]?.objectValue ?? [:])) {
            case .success:
                XCTAssertEqual(example["valid"], .bool(true), "\(about): refused by the examples, read by Swift")
            case .failure(let problem):
                XCTAssertEqual(example["valid"], .bool(false), "\(about): \(problem)")
                XCTAssertEqual(caseName(problem), example["problem"]?.stringValue, about)
                for name in example["names"]?.arrayValue ?? [] {
                    XCTAssertTrue("\(problem)".contains(name.stringValue ?? "?"), "\(about): \(problem) names \(name)")
                }
            }
        }
    }

    func testTheTypeHasTheFieldsTheSchemaDeclares() throws {
        let schema = ProtocolFiles.json("protocol/manifest.schema.json")
        let read = try ToolManifestFile.read(manifest()).get()
        let command = try XCTUnwrap(read.contributes?.commands?.first)
        let preference = try XCTUnwrap(read.preferences?.first)
        XCTAssertEqual(ProtocolFiles.fields(of: read), ProtocolFiles.fields(declaredBy: schema))
        XCTAssertEqual(ProtocolFiles.fields(of: try XCTUnwrap(read.contributes)),
                       ProtocolFiles.fields(declaredBy: schema["$defs"]?["contributes"]))
        XCTAssertEqual(ProtocolFiles.fields(of: command), ProtocolFiles.fields(declaredBy: schema["$defs"]?["command"]))
        XCTAssertEqual(ProtocolFiles.fields(of: preference),
                       ProtocolFiles.fields(declaredBy: schema["$defs"]?["preference"]))
        XCTAssertEqual(ProtocolFiles.fields(of: read.runtime), ProtocolFiles.fields(declaredBy: schema["$defs"]?["runtime"]))
        let drawn = try ToolManifestFile.read(manifest(changing: [
            "protocol": .string("2"),
            "contributes": .object(["panels": .array([.object(["id": .string("deploys"),
                                                                "title": .object(["en": .string("Deploys")]),
                                                                "placement": .string("island")])])]),
        ])).get()
        let panel = try XCTUnwrap(drawn.contributes?.panels?.first)
        XCTAssertEqual(ProtocolFiles.fields(of: panel), ProtocolFiles.fields(declaredBy: schema["$defs"]?["panel"]))
        let chosen = try ToolManifestFile.read(manifest(changing: [
            "protocol": .string("2"),
            "contributes": .object(["status": .object(["placement": .string("island")]),
                                    "slot": .object(["placement": .string("agents")])]),
            "preferences": .array([.object(["id": .string("project"), "type": .string("string"),
                                            "default": .string("acme"),
                                            "options": .array([.object(["value": .string("acme"),
                                                                        "title": .object(["en": .string("Acme")])])])])]),
        ])).get()
        XCTAssertEqual(ProtocolFiles.fields(of: try XCTUnwrap(chosen.contributes?.status)),
                       ProtocolFiles.fields(declaredBy: schema["$defs"]?["statusContribution"]))
        XCTAssertEqual(ProtocolFiles.fields(of: try XCTUnwrap(chosen.contributes?.slot)),
                       ProtocolFiles.fields(declaredBy: schema["$defs"]?["slotContribution"]))
        XCTAssertEqual(chosen.contributes?.slot?.knownPlacement, .agents)
        XCTAssertEqual(ProtocolFiles.fields(of: try XCTUnwrap(chosen.preferences?.first?.options?.first)),
                       ProtocolFiles.fields(declaredBy: schema["$defs"]?["preferenceOption"]))
        XCTAssertEqual(Set((schema["$defs"]?.objectValue ?? [:]).keys),
                       ["localizedText", "contributes", "statusContribution", "slotContribution", "command", "panel",
                        "preference", "preferenceOption", "runtime"])
    }

    func testTheListsAreTheSchemasLists() {
        let schema = ProtocolFiles.json("protocol/manifest.schema.json")
        func listed(_ node: JSONValue?) -> [String] {
            (node?["items"]?["enum"]?.arrayValue ?? node?["enum"]?.arrayValue ?? []).compactMap(\.stringValue)
        }
        let command = schema["$defs"]?["command"]?["properties"]
        let preference = schema["$defs"]?["preference"]?["properties"]
        XCTAssertEqual(listed(schema["properties"]?["uses"]), AppService.allCases.map(\.rawValue))
        XCTAssertEqual(listed(schema["properties"]?["activation"]), ActivationName.allCases.map(\.rawValue))
        XCTAssertEqual(listed(command?["surfaces"]), SurfaceName.allCases.map(\.rawValue))
        XCTAssertEqual(listed(preference?["type"]), PreferenceKind.allCases.map(\.rawValue))
        XCTAssertEqual(listed(schema["properties"]?["protocol"]), ProtocolVersion.supported)
        XCTAssertEqual(ProtocolVersion.supported.last, ProtocolVersion.current)
        let panel = schema["$defs"]?["panel"]?["properties"]
        XCTAssertEqual(listed(panel?["placement"]), PanelPlacement.allCases.map(\.rawValue))
        XCTAssertEqual(listed(panel?["kind"]), PanelKind.allCases.map(\.rawValue))
        XCTAssertEqual(panel?["id"]?["maxLength"]?.numberValue, Double(ManifestLimits.maxNameLength))
        XCTAssertEqual(panel?["entry"]?["pattern"], schema["$defs"]?["runtime"]?["properties"]?["exec"]?["pattern"],
                       "a web panel's page stays inside the folder by the program's rule")
        XCTAssertEqual(schema["$defs"]?["contributes"]?["properties"]?["panels"]?["maxItems"]?.numberValue,
                       Double(ManifestLimits.maxPanels))
        XCTAssertEqual(schema["$defs"]?["runtime"]?["properties"]?["kind"]?["const"]?.stringValue,
                       ToolManifestFile.externalRuntime)
        XCTAssertEqual(schema["properties"]?["id"]?["maxLength"]?.numberValue, Double(ManifestLimits.maxNameLength))
        XCTAssertEqual(command?["id"]?["maxLength"]?.numberValue, Double(ManifestLimits.maxNameLength))
        XCTAssertEqual(preference?["id"]?["maxLength"]?.numberValue, Double(ManifestLimits.maxNameLength))
        XCTAssertEqual(preference?["title"]?["additionalProperties"]?["maxLength"]?.numberValue,
                       Double(ManifestLimits.maxPreferenceTitleLength))
        XCTAssertEqual(preference?["title"]?["$ref"]?.stringValue, "#/$defs/localizedText",
                       "a preference's title is text in several languages, as a command's is")
        XCTAssertEqual(schema["$defs"]?["contributes"]?["properties"]?["commands"]?["maxItems"]?.numberValue,
                       Double(ManifestLimits.maxCommands))
        XCTAssertEqual(schema["properties"]?["preferences"]?["maxItems"]?.numberValue,
                       Double(ManifestLimits.maxPreferences))
        XCTAssertEqual(listed(schema["$defs"]?["statusContribution"]?["properties"]?["placement"]),
                       StatusPlacement.allCases.map(\.rawValue))
        XCTAssertEqual(preference?["options"]?["maxItems"]?.numberValue, Double(ManifestLimits.maxOptions))
        XCTAssertEqual(preference?["options"]?["minItems"]?.numberValue, 1)
        let option = schema["$defs"]?["preferenceOption"]?["properties"]
        XCTAssertEqual(option?["value"]?["maxLength"]?.numberValue, Double(ManifestLimits.maxOptionValueLength))
        XCTAssertEqual(option?["value"]?["pattern"], preference?["title"]?["additionalProperties"]?["pattern"],
                       "an option's value has no control character, by the title's rule")
        XCTAssertEqual(option?["title"]?["additionalProperties"], preference?["title"]?["additionalProperties"],
                       "an option's title is held to what a preference's title is")
        XCTAssertEqual(option?["title"]?["$ref"]?.stringValue, "#/$defs/localizedText")
    }

    func testTheLimits() {
        XCTAssertEqual(ManifestLimits.maxBytes, 65_536)
        XCTAssertEqual(ManifestLimits.maxCommands, 32)
        XCTAssertEqual(ManifestLimits.maxPreferences, 16)
        XCTAssertEqual(ManifestLimits.maxNameLength, 128)
        XCTAssertEqual(ManifestLimits.maxPreferenceTitleLength, 60)
        XCTAssertEqual(ManifestLimits.maxPanels, 8)
        XCTAssertEqual(ManifestLimits.maxOptions, 64)
        XCTAssertEqual(ManifestLimits.maxOptionValueLength, 128)

        func commands(_ count: Int) -> JSONValue {
            .object(["commands": .array((0..<count).map { index in
                .object(["id": .string("c\(index)"), "title": .object(["en": .string("Command \(index)")])])
            })])
        }
        XCTAssertNil(problem(["contributes": commands(32)]))
        XCTAssertEqual(problem(["contributes": commands(33)]), .tooManyCommands(33))

        func preferences(_ count: Int) -> JSONValue {
            .array((0..<count).map { index in
                .object(["id": .string("p\(index)"), "type": .string("boolean"), "default": .bool(false)])
            })
        }
        XCTAssertNil(problem(["preferences": preferences(16)]))
        XCTAssertEqual(problem(["preferences": preferences(17)]), .tooManyPreferences(17))

        let longest = "com." + String(repeating: "a", count: 124)
        XCTAssertNil(problem(["id": .string(longest)]))
        XCTAssertEqual(problem(["id": .string(longest + "a")]), .idNotWellFormed(longest + "a"))

        let padding = String(repeating: "x", count: ManifestLimits.maxBytes)
        let large = manifest(changing: ["description": .object(["en": .string(padding)])])
        XCTAssertEqual(ToolManifestFile.read(large), .failure(.tooLarge(bytes: large.count)))
    }

    func testWhatIsNotAManifestAtAll() {
        XCTAssertEqual(ToolManifestFile.read(Data("not json".utf8)), .failure(.notJSON))
        XCTAssertEqual(ToolManifestFile.read(Data("[]".utf8)), .failure(.notJSON))
        XCTAssertEqual(ToolManifestFile.read(Data()), .failure(.notJSON))
        XCTAssertEqual(problem(["contributes": .object(["commands": .array([.object(["id": .string("a")])])])]),
                       .malformed(field: "contributes.commands[0].title"))
        XCTAssertEqual(problem(["runtime": .object(["kind": .string("external")])]), .malformed(field: "runtime.exec"))
    }

    func testEveryProblemIsListed() {
        let broken = ToolManifestFile.read(manifest(changing: [
            "id": .string("deploys"),
            "uses": .array([.string("camera")]),
            "runtime": .object(["kind": .string("bundled"), "exec": .string("../x")]),
        ]))
        XCTAssertEqual(broken, .failure(.idWithoutDot("deploys")), "the first problem is the one given")
        let all = (try? JSONDecoder().decode(ToolManifestFile.self, from: manifest(changing: [
            "id": .string("deploys"),
            "uses": .array([.string("camera")]),
            "runtime": .object(["kind": .string("bundled"), "exec": .string("../x")]),
        ])))?.problems()
        XCTAssertEqual(all, [.idWithoutDot("deploys"), .unknownService("camera"), .unsupportedRuntime("bundled"),
                             .programLeavesFolder("../x")])
    }

    /// Every case of `ManifestProblem`, by name. `init` has no `default`, so
    /// a case added to `ManifestProblem` does not compile until it is named
    /// here, and `testEveryProblemHasATest` then fails until a test gives it.
    private enum ProblemName: String, CaseIterable {
        case tooLarge, notJSON, malformed, idNotWellFormed, idWithoutDot, unsupportedProtocol, unsupportedRuntime
        case noEnglish, blankText, unknownService, duplicateService, unknownActivation, tooManyCommands
        case commandNotWellFormed, duplicateCommand, unknownSurface, tooManyPreferences, preferenceNotWellFormed
        case duplicatePreference, unknownPreferenceType, defaultOfWrongType, programLeavesFolder
        case preferenceTitleNotWellFormed
        case panelsNeedProtocol2, tooManyPanels, panelNotWellFormed, duplicatePanel, unknownPlacement
        case unknownPanelKind, placementTaken, webPanelWithoutEntry, panelEntryLeavesFolder
        case statusNeedsProtocol2, unknownStatusPlacement, optionsNeedString, optionCountOutOfRange
        case optionValueNotWellFormed, duplicateOption, optionTitleNotWellFormed, defaultNotAnOption
        case slotNeedsProtocol2, unknownSlotPlacement, pickerNeedsString, unknownPicker

        init(_ problem: ManifestProblem) {
            switch problem {
            case .tooLarge: self = .tooLarge
            case .notJSON: self = .notJSON
            case .malformed: self = .malformed
            case .idNotWellFormed: self = .idNotWellFormed
            case .idWithoutDot: self = .idWithoutDot
            case .unsupportedProtocol: self = .unsupportedProtocol
            case .unsupportedRuntime: self = .unsupportedRuntime
            case .noEnglish: self = .noEnglish
            case .blankText: self = .blankText
            case .unknownService: self = .unknownService
            case .duplicateService: self = .duplicateService
            case .unknownActivation: self = .unknownActivation
            case .tooManyCommands: self = .tooManyCommands
            case .commandNotWellFormed: self = .commandNotWellFormed
            case .duplicateCommand: self = .duplicateCommand
            case .unknownSurface: self = .unknownSurface
            case .tooManyPreferences: self = .tooManyPreferences
            case .preferenceNotWellFormed: self = .preferenceNotWellFormed
            case .duplicatePreference: self = .duplicatePreference
            case .unknownPreferenceType: self = .unknownPreferenceType
            case .defaultOfWrongType: self = .defaultOfWrongType
            case .programLeavesFolder: self = .programLeavesFolder
            case .preferenceTitleNotWellFormed: self = .preferenceTitleNotWellFormed
            case .panelsNeedProtocol2: self = .panelsNeedProtocol2
            case .tooManyPanels: self = .tooManyPanels
            case .panelNotWellFormed: self = .panelNotWellFormed
            case .duplicatePanel: self = .duplicatePanel
            case .unknownPlacement: self = .unknownPlacement
            case .unknownPanelKind: self = .unknownPanelKind
            case .placementTaken: self = .placementTaken
            case .webPanelWithoutEntry: self = .webPanelWithoutEntry
            case .panelEntryLeavesFolder: self = .panelEntryLeavesFolder
            case .statusNeedsProtocol2: self = .statusNeedsProtocol2
            case .unknownStatusPlacement: self = .unknownStatusPlacement
            case .optionsNeedString: self = .optionsNeedString
            case .optionCountOutOfRange: self = .optionCountOutOfRange
            case .optionValueNotWellFormed: self = .optionValueNotWellFormed
            case .duplicateOption: self = .duplicateOption
            case .optionTitleNotWellFormed: self = .optionTitleNotWellFormed
            case .defaultNotAnOption: self = .defaultNotAnOption
            case .slotNeedsProtocol2: self = .slotNeedsProtocol2
            case .unknownSlotPlacement: self = .unknownSlotPlacement
            case .pickerNeedsString: self = .pickerNeedsString
            case .unknownPicker: self = .unknownPicker
            }
        }
    }

    /// Every problem is given by the reader for some file here: by an
    /// example, or by one of the four files an example cannot hold (too
    /// large, not JSON, too many commands, too many preferences).
    func testEveryProblemHasATest() {
        var given: [ManifestProblem] = []
        for example in file["examples"]?.arrayValue ?? [] {
            let read = ToolManifestFile.read(manifest(changing: example["change"]?.objectValue ?? [:]))
            if case .failure(let problem) = read { given.append(problem) }
        }
        let item = JSONValue.object(["id": .string("a"), "title": .object(["en": .string("A")]),
                                     "type": .string("boolean"), "default": .bool(false)])
        func many(_ count: Int) -> JSONValue {
            .array((0..<count).map { index in
                var fields = item.objectValue ?? [:]
                fields["id"] = .string("a\(index)")
                return .object(fields)
            })
        }
        let padding = String(repeating: "x", count: ManifestLimits.maxBytes)
        let others: [Data] = [
            manifest(changing: ["description": .object(["en": .string(padding)])]),
            Data("not json".utf8),
            manifest(changing: ["contributes": .object(["commands": many(ManifestLimits.maxCommands + 1)])]),
            manifest(changing: ["preferences": many(ManifestLimits.maxPreferences + 1)]),
        ]
        for data in others {
            if case .failure(let problem) = ToolManifestFile.read(data) { given.append(problem) }
        }
        for problem in given {
            XCTAssertEqual(caseName(problem), ProblemName(problem).rawValue, "a problem is named as its case is")
        }
        let names = Set(given.map { ProblemName($0) })
        let missing = Set(ProblemName.allCases).subtracting(names).map(\.rawValue).sorted()
        XCTAssertEqual(missing, [], "no test gives these problems")
        XCTAssertEqual(names.count, ProblemName.allCases.count)
        XCTAssertEqual(ProblemName.allCases.count, 44)
    }

    func testNamesAndPaths() {
        for name in ["a", "copyLatest", "copy.latest", "a-b_c.9", String(repeating: "a", count: 128)] {
            XCTAssertTrue(ManifestRules.isWellFormedName(name), name)
        }
        for name in ["", ".a", "a.", "a..b", "a b", "a/b", "é", String(repeating: "a", count: 129)] {
            XCTAssertFalse(ManifestRules.isWellFormedName(name), name)
        }
        for path in ["deploys", "bin/deploys", "bin/v1.2/deploys", "...", "bin/..deploys"] {
            XCTAssertTrue(ManifestRules.staysInsideFolder(path), path)
        }
        for path in ["", "/bin/deploys", "../deploys", "bin/../deploys", "bin/./deploys", "bin//deploys", "bin/", ".", ".."] {
            XCTAssertFalse(ManifestRules.staysInsideFolder(path), path)
        }
    }

    func testTextIsFoundForALanguage() {
        let text = LocalizedText(["en": "Deploys", "fr": "Déploiements", "pt": "Implantações", "zh-Hans": "部署"])
        XCTAssertEqual(text.text(for: "fr"), "Déploiements")
        XCTAssertEqual(text.text(for: "pt-BR"), "Implantações", "a region falls back to its language")
        XCTAssertEqual(text.text(for: "zh-Hans"), "部署")
        XCTAssertEqual(text.text(for: "zh-TW"), "Deploys", "another script of the language is not a match")
        XCTAssertEqual(text.text(for: "en-US"), "Deploys")
        XCTAssertEqual(text.text(for: "ja"), "Deploys", "anything else is English")
        XCTAssertNil(LocalizedText(["fr": "Déploiements"]).text(for: "de"))
    }

    func testAPreferenceMayCarryATitle() throws {
        func preference(_ title: JSONValue?) -> [String: JSONValue] {
            var fields: [String: JSONValue] = ["id": .string("project"), "type": .string("string"), "default": .string("")]
            fields["title"] = title
            return ["preferences": .array([.object(fields)])]
        }
        func titled(_ text: String, in language: String = "en") -> [String: JSONValue] {
            preference(.object(language == "en" ? ["en": .string(text)] : ["en": .string("Project"), language: .string(text)]))
        }
        // The example manifest has no title, and is read as it always was.
        let plain = try ToolManifestFile.read(manifest()).get()
        XCTAssertEqual(plain.preferences?.map(\.id), ["project"])
        XCTAssertNil(plain.preferences?.first?.title, "a title is optional: a manifest with none is as valid as before")

        let read = try ToolManifestFile.read(manifest(changing: preference(.object(["en": .string("Project"),
                                                                                    "fr": .string("Projet")])))).get()
        XCTAssertEqual(read.preferences?.first?.title, LocalizedText(["en": "Project", "fr": "Projet"]))
        XCTAssertEqual(read.preferences?.first?.title?.text(for: "fr-CA"), "Projet")
        XCTAssertEqual(read.preferences?.first?.title?.text(for: "de"), "Project")

        let longest = String(repeating: "a", count: ManifestLimits.maxPreferenceTitleLength)
        XCTAssertNil(problem(titled(longest)))
        XCTAssertEqual(problem(titled(longest + "a")), .preferenceTitleNotWellFormed(preference: "project"))
        XCTAssertNil(problem(titled(longest, in: "de")))
        XCTAssertEqual(problem(titled(longest + "a", in: "de")), .preferenceTitleNotWellFormed(preference: "project"),
                       "every language is held to the length, not English alone")
        // Sixty characters as JSON Schema counts them, whatever each is made of.
        XCTAssertNil(problem(titled(String(repeating: "\u{1F680}", count: ManifestLimits.maxPreferenceTitleLength))))
        XCTAssertEqual(problem(titled(String(repeating: "e\u{301}", count: 31))),
                       .preferenceTitleNotWellFormed(preference: "project"), "an accent written apart counts")
        for control in ["\n", "\r", "\t", "\u{0}", "\u{1B}", "\u{7F}", "\u{85}", "\u{9F}"] {
            XCTAssertEqual(problem(titled("Pro" + control + "ject")), .preferenceTitleNotWellFormed(preference: "project"),
                           "\(control.unicodeScalars.map(\.value))")
            XCTAssertFalse(ManifestRules.isWellFormedTitle("Pro" + control + "ject"))
        }
        XCTAssertTrue(ManifestRules.isWellFormedTitle("Projet d\u{2019}équipe \u{00A0}: 部署"))
        XCTAssertEqual(problem(preference(.object(["fr": .string("Projet")]))),
                       .noEnglish(field: "preferences[project].title"))
        XCTAssertEqual(problem(preference(.object(["en": .string("Project"), "fr": .string(" ")]))),
                       .blankText(field: "preferences[project].title"))
        XCTAssertEqual(problem(preference(.string("Project"))), .malformed(field: "preferences[0].title"),
                       "a title is a map of languages, not bare text")
        XCTAssertEqual(problem(preference(.object([:]))), .noEnglish(field: "preferences[project].title"))
    }

    func testTheMostTextAPreferenceMayBeSetTo() {
        XCTAssertEqual(StorageLimits.maxTextLength, 4_096)
        let most = String(repeating: "\u{1F680}", count: StorageLimits.maxTextLength)
        XCTAssertTrue(StorageLimits.allows(.string(most)))
        XCTAssertFalse(StorageLimits.allows(.string(most + "a")))
        XCTAssertTrue(StorageLimits.allows(.string("")) && StorageLimits.allows(.bool(true))
            && StorageLimits.allows(.number(1e300)), "only text has a size")
        let said = ProtocolFiles.json("protocol/messages.schema.json")["$defs"]?["storageSetParams"]?["properties"]?["value"]?[
            "description"]?.stringValue ?? ""
        XCTAssertTrue(said.contains("4,096 characters"), "the schema says the number the code holds: \(said)")
    }

    func testAKindOfPreferenceTakesItsOwnValues() {
        XCTAssertTrue(PreferenceKind.string.accepts(.string("")))
        XCTAssertTrue(PreferenceKind.boolean.accepts(.bool(false)))
        XCTAssertTrue(PreferenceKind.integer.accepts(.number(20)))
        XCTAssertTrue(PreferenceKind.number.accepts(.number(0.5)) && PreferenceKind.number.accepts(.number(3)))
        XCTAssertFalse(PreferenceKind.integer.accepts(.number(1.5)))
        XCTAssertFalse(PreferenceKind.boolean.accepts(.number(1)))
        XCTAssertFalse(PreferenceKind.string.accepts(.null))
    }

    func testProtocolTwoAddsPanelsAndChangesNothingElse() throws {
        // The design's example manifest, read as protocol 2: every field of
        // protocol 1 is read as it was.
        let one = try ToolManifestFile.read(manifest()).get()
        let two = try ToolManifestFile.read(manifest(changing: ["protocol": .string("2")])).get()
        XCTAssertEqual(two.contributes?.commands, one.contributes?.commands)
        XCTAssertEqual(two.preferences, one.preferences)
        XCTAssertNil(two.contributes?.panels)

        let island = JSONValue.object(["id": .string("deploys"), "title": .object(["en": .string("Deploys")]),
                                       "placement": .string("island")])
        let panels = JSONValue.object(["panels": .array([island])])
        let read = try ToolManifestFile.read(manifest(changing: ["protocol": .string("2"), "contributes": panels])).get()
        XCTAssertEqual(read.contributes?.panels?.map(\.id), ["deploys"])
        XCTAssertNil(read.contributes?.panels?.first?.kind, "a panel's kind is blocks when left out")
        XCTAssertEqual(problem(["contributes": panels]), .panelsNeedProtocol2("1"),
                       "an app reading a protocol 1 manifest never finds panels in it")
        XCTAssertEqual(problem(["protocol": .string("3"), "contributes": panels]), .unsupportedProtocol("3"))
        XCTAssertEqual(ProtocolVersion.supported, ["1", "2"])
    }

    func testAToolMayDeclareAStatusInProtocolTwo() throws {
        func status(_ placement: JSONValue?) -> JSONValue {
            .object(["status": .object(placement.map { ["placement": $0] } ?? [:])])
        }
        let read = try ToolManifestFile.read(manifest(changing: ["protocol": .string("2"),
                                                                 "contributes": status(.string("island"))])).get()
        XCTAssertEqual(read.contributes?.status?.placement, "island")
        XCTAssertNil(read.contributes?.status?.activity, "a status that says nothing of words has none")
        let words = try ToolManifestFile.read(manifest(changing: [
            "protocol": .string("2"),
            "contributes": .object(["status": .object(["placement": .string("island"), "activity": .bool(true)])]),
        ])).get()
        XCTAssertEqual(words.contributes?.status?.activity, true)
        XCTAssertEqual(problem(["protocol": .string("2"),
                                "contributes": .object(["status": .object(["placement": .string("island"),
                                                                           "activity": .string("yes")])])]),
                       .malformed(field: "contributes.status.activity"))
        XCTAssertNil(try ToolManifestFile.read(manifest(changing: ["protocol": .string("2")])).get().contributes?.status,
                     "a manifest that declares none has none")
        XCTAssertEqual(problem(["contributes": status(.string("island"))]), .statusNeedsProtocol2("1"))
        XCTAssertEqual(problem(["protocol": .string("2"), "contributes": status(.string("menuBar"))]),
                       .unknownStatusPlacement("menuBar"))
        XCTAssertEqual(problem(["protocol": .string("2"), "contributes": status(nil)]),
                       .malformed(field: "contributes.status.placement"))
        XCTAssertEqual(StatusPlacement.allCases.map(\.rawValue), ["island"])
    }

    func testATextPreferenceMayOfferOptions() throws {
        func option(_ value: String, _ title: [String: String] = ["en": "Title"]) -> JSONValue {
            .object(["value": .string(value), "title": .object(title.mapValues(JSONValue.string))])
        }
        func preference(type: String = "string", default value: JSONValue = .string("a"),
                        _ options: [JSONValue]) -> [String: JSONValue] {
            ["preferences": .array([.object(["id": .string("project"), "type": .string(type), "default": value,
                                             "options": .array(options)])])]
        }
        let read = try ToolManifestFile.read(manifest(changing: preference([
            option("a", ["en": "Acme", "fr": "Acmé"]), option("", ["en": "None"]),
        ]))).get()
        XCTAssertEqual(read.preferences?.first?.options?.map(\.value), ["a", ""])
        XCTAssertEqual(read.preferences?.first?.options?.map(\.title),
                       [LocalizedText(["en": "Acme", "fr": "Acmé"]), LocalizedText(["en": "None"])])
        XCTAssertNil(try ToolManifestFile.read(manifest()).get().preferences?.first?.options,
                     "a preference with none is read as it always was")

        XCTAssertEqual(problem(preference(type: "boolean", default: .bool(true), [option("a")])),
                       .optionsNeedString(preference: "project"))
        XCTAssertEqual(problem(preference(type: "integer", default: .number(1), [option("1")])),
                       .optionsNeedString(preference: "project"))
        XCTAssertEqual(problem(preference([])), .optionCountOutOfRange(preference: "project", count: 0))
        let most = (0..<ManifestLimits.maxOptions).map { option("v\($0)") }
        XCTAssertNil(problem(preference(default: .string("v0"), most)))
        XCTAssertEqual(problem(preference(default: .string("v0"), most + [option("more")])),
                       .optionCountOutOfRange(preference: "project", count: 65))

        let longest = String(repeating: "\u{1F680}", count: ManifestLimits.maxOptionValueLength)
        XCTAssertNil(problem(preference([option("a"), option(longest)])))
        XCTAssertEqual(problem(preference([option("a"), option(longest + "a")])),
                       .optionValueNotWellFormed(preference: "project"))
        for control in ["\n", "\r", "\t", "\u{0}", "\u{7F}", "\u{85}"] {
            XCTAssertEqual(problem(preference([option("a"), option("b" + control + "c")])),
                           .optionValueNotWellFormed(preference: "project"), "\(control.unicodeScalars.map(\.value))")
            XCTAssertFalse(ManifestRules.isWellFormedOptionValue("b" + control + "c"))
        }
        XCTAssertTrue(ManifestRules.isWellFormedOptionValue(""), "an empty value is a value")
        XCTAssertTrue(ManifestRules.isWellFormedOptionValue("breathe blue 9"))

        XCTAssertEqual(problem(preference([option("a"), option("b"), option("a")])),
                       .duplicateOption(preference: "project", value: "a"))
        XCTAssertEqual(problem(preference(default: .string("z"), [option("a"), option("b")])),
                       .defaultNotAnOption(preference: "project"))

        let title = String(repeating: "a", count: ManifestLimits.maxPreferenceTitleLength)
        XCTAssertNil(problem(preference([option("a", ["en": title])])))
        XCTAssertEqual(problem(preference([option("a", ["en": title + "a"])])),
                       .optionTitleNotWellFormed(preference: "project"))
        XCTAssertEqual(problem(preference([option("a", ["en": "A", "de": title + "a"])])),
                       .optionTitleNotWellFormed(preference: "project"), "every language is held to the length")
        XCTAssertEqual(problem(preference([option("a", ["en": "A\nB"])])),
                       .optionTitleNotWellFormed(preference: "project"))
        XCTAssertEqual(problem(preference([option("a"), option("b", ["fr": "Bé"])])),
                       .noEnglish(field: "preferences[project].options[1].title"))
        XCTAssertEqual(problem(preference([option("a", ["en": "A", "fr": " "])])),
                       .blankText(field: "preferences[project].options[0].title"))
    }

    func testOptionsChangeNoVerdictOfAManifestWithout() {
        // Every problem a preference could have before is still the first
        // one given, with options or without.
        func preference(_ fields: [String: JSONValue]) -> [String: JSONValue] {
            var all: [String: JSONValue] = ["id": .string("project"), "type": .string("string"), "default": .string("a"),
                                            "options": .array([.object(["value": .string("a"),
                                                                        "title": .object(["en": .string("A")])])])]
            for (key, value) in fields { all[key] = value }
            return ["preferences": .array([.object(all)])]
        }
        XCTAssertNil(problem(preference([:])))
        XCTAssertEqual(problem(preference(["type": .string("choice")])),
                       .unknownPreferenceType(preference: "project", type: "choice"),
                       "a type nobody knows is still that problem: options add no type")
        XCTAssertEqual(problem(preference(["default": .number(1)])), .defaultOfWrongType(preference: "project"))
        XCTAssertEqual(problem(preference(["id": .string("my project")])), .preferenceNotWellFormed("my project"))
    }

    func testTheReferenceToolsManifestIsRead() throws {
        let data = ProtocolFiles.data("conformance/reference-tool/\(ToolManifestFile.fileName)")
        let manifest = try ToolManifestFile.read(data).get()
        XCTAssertEqual(manifest.id, "dev.vitruvian.reference")
        XCTAssertEqual(manifest.uses, [AppService.notify.rawValue])
        XCTAssertEqual(manifest.contributes?.commands?.map(\.id), ["hello"])
        XCTAssertEqual(manifest.runtime.exec, "bin/reference_tool.py")
    }

    func testTheSecondReferenceToolsManifestIsRead() throws {
        let data = ProtocolFiles.data("conformance/reference-tool-2/\(ToolManifestFile.fileName)")
        let manifest = try ToolManifestFile.read(data).get()
        XCTAssertEqual(manifest.id, "dev.vitruvian.reference2")
        XCTAssertEqual(manifest.`protocol`, "2")
        XCTAssertEqual(manifest.uses, [AppService.notify.rawValue])
        XCTAssertEqual(manifest.contributes?.commands?.map(\.id), ["hello"])
        XCTAssertEqual(manifest.contributes?.panels?.map(\.id), ["hello"])
        XCTAssertEqual(manifest.contributes?.panels?.map(\.placement), ["island"])
        XCTAssertEqual(manifest.runtime.exec, "bin/reference_tool_2.py")
    }
}
