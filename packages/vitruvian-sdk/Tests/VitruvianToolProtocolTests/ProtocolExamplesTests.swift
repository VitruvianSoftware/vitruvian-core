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

/// The Swift types, held to the schemas. `protocol/protocol_examples_test.py`
/// checks the same example files against the schemas themselves, so an
/// example both sides agree on is a message they read alike.
final class ProtocolExamplesTests: XCTestCase {
    /// Reads `value` as `type` and writes it back.
    private static func again<Shape: Codable>(_ value: JSONValue, as type: Shape.Type) throws -> JSONValue {
        try JSONValue(encoding: value.decode(type))
    }

    /// A message's params, read as the type that message carries.
    private static func params(_ method: ToolMethod, _ value: JSONValue) throws -> JSONValue {
        switch method {
        case .initialize: return try again(value, as: InitializeParams.self)
        case .commandRun: return try again(value, as: CommandRunParams.self)
        case .preferencesChanged: return try again(value, as: PreferencesChangedParams.self)
        case .languageChanged: return try again(value, as: LanguageChangedParams.self)
        case .commandsState: return try again(value, as: CommandsStateParams.self)
        case .notifyHUD: return try again(value, as: NotifyHUDParams.self)
        case .openURL: return try again(value, as: OpenURLParams.self)
        case .clipboardWriteText: return try again(value, as: ClipboardWriteTextParams.self)
        case .keystrokesPaste: return try again(value, as: KeystrokesPasteParams.self)
        case .keystrokesPressMenuItem: return try again(value, as: KeystrokesPressMenuItemParams.self)
        case .processesTerminate: return try again(value, as: ProcessesTerminateParams.self)
        case .storageGet: return try again(value, as: StorageGetParams.self)
        case .storageSet: return try again(value, as: StorageSetParams.self)
        case .log: return try again(value, as: LogParams.self)
        case .uiOpen: return try again(value, as: UIOpenParams.self)
        case .uiEvent: return try again(value, as: UIEventParams.self)
        case .uiClose: return try again(value, as: UICloseParams.self)
        case .uiRender: return try again(value, as: UIRenderParams.self)
        case .uiBadge: return try again(value, as: UIBadgeParams.self)
        case .shutdown, .notifyBeep, .clipboardReadText: return try again(value, as: EmptyObject.self)
        }
    }

    /// A request's result, read as the type that request is answered with.
    /// Nil for a notice, which has no answer.
    private static func result(_ method: ToolMethod, _ value: JSONValue) throws -> JSONValue? {
        switch method {
        case .initialize: return try again(value, as: InitializeResult.self)
        case .openURL: return try again(value, as: OpenURLResult.self)
        case .clipboardReadText: return try again(value, as: ClipboardReadTextResult.self)
        case .clipboardWriteText: return try again(value, as: ClipboardWriteTextResult.self)
        case .keystrokesPressMenuItem: return try again(value, as: KeystrokesPressMenuItemResult.self)
        case .storageGet: return try again(value, as: StorageGetResult.self)
        case .uiOpen: return try again(value, as: UIOpenResult.self)
        case .uiEvent: return try again(value, as: UIEventResult.self)
        case .commandRun, .notifyHUD, .notifyBeep, .keystrokesPaste, .processesTerminate, .storageSet, .uiBadge:
            return try again(value, as: EmptyObject.self)
        case .preferencesChanged, .languageChanged, .shutdown, .commandsState, .log, .uiClose, .uiRender:
            return nil
        }
    }

    /// One value of each type a message carries, under the name of its
    /// definition in `messages.schema.json`.
    private static let shapes: [(String, Any)] = [
        ("error", RPCErrorObject(code: 0, message: "")),
        ("refusalData", RefusalData()),
        ("empty", EmptyObject()),
        ("initializeParams", InitializeParams(protocolVersions: [], language: "", dataFolder: "")),
        ("initializeResult", InitializeResult(protocolVersion: "", toolVersion: "")),
        ("commandRunParams", CommandRunParams(command: "")),
        ("preferencesChangedParams", PreferencesChangedParams(values: [:])),
        ("languageChangedParams", LanguageChangedParams(language: "")),
        ("commandsStateParams", CommandsStateParams(runnable: [])),
        ("notifyHUDParams", NotifyHUDParams(icon: "", message: "")),
        ("openURLParams", OpenURLParams(url: "")),
        ("openURLResult", OpenURLResult(opened: false)),
        ("clipboardReadTextResult", ClipboardReadTextResult(text: nil)),
        ("clipboardWriteTextParams", ClipboardWriteTextParams(text: "")),
        ("clipboardWriteTextResult", ClipboardWriteTextResult(written: false)),
        ("keystrokesPasteParams", KeystrokesPasteParams(text: "")),
        ("keystrokesPressMenuItemParams", KeystrokesPressMenuItemParams(equivalents: [])),
        ("keyEquivalent", KeyEquivalent(character: "", modifiers: [])),
        ("keystrokesPressMenuItemResult", KeystrokesPressMenuItemResult(pressed: false)),
        ("processesTerminateParams", ProcessesTerminateParams(pid: 0, name: "", force: false)),
        ("storageGetParams", StorageGetParams(key: "")),
        ("storageGetResult", StorageGetResult(value: .null)),
        ("storageSetParams", StorageSetParams(key: "", value: .null)),
        ("logParams", LogParams(message: "")),
        ("uiOpenParams", UIOpenParams(panel: "")),
        ("uiOpenResult", UIOpenResult()),
        ("uiEventParams", UIEventParams(panel: "", event: .tap)),
        ("uiEventResult", UIEventResult()),
        ("uiCloseParams", UICloseParams(panel: "")),
        ("uiRenderParams", UIRenderParams(panel: "", tree: UITree(blocks: []))),
        ("uiBadgeParams", UIBadgeParams()),
        ("uiTree", UITree(blocks: [])),
        ("uiListRow", UIListRow(id: "", title: "")),
        ("textBlock", TextBlock(text: "")),
        ("headingBlock", HeadingBlock(text: "")),
        ("rowBlock", RowBlock(title: "")),
        ("buttonBlock", ButtonBlock(title: "")),
        ("toggleBlock", ToggleBlock(title: "", value: false)),
        ("fieldBlock", FieldBlock()),
        ("listBlock", ListBlock(rows: [])),
        ("progressBlock", ProgressBlock()),
        ("imageBlock", ImageBlock(source: "")),
        ("dividerBlock", DividerBlock()),
        ("linkBlock", LinkBlock(title: "", url: "")),
        ("spacerBlock", SpacerBlock()),
    ]

    /// The definitions that are the message itself, read by `RPCMessage`.
    private static let envelopes: Set<String> = ["id", "request", "notice", "result", "failure"]

    /// The definitions that are no object with fields of its own: text, one
    /// way or another, and a block, whose fields are its kind's and whose
    /// own three are held by `testABlockIsItsKindAndItsThreeFields`.
    private static let notStructs: Set<String> = ["uiText", "localizedText", "uiBlock"]

    func testTheMethodTableIsTheSchemasTable() {
        let rows = ProtocolFiles.json("protocol/methods.json")["methods"]?.arrayValue ?? []
        XCTAssertEqual(rows.compactMap { $0["method"]?.stringValue }, ToolMethod.allCases.map(\.rawValue),
                       "the same messages, in the same order")
        for row in rows {
            guard let name = row["method"]?.stringValue, let method = ToolMethod(rawValue: name) else { continue }
            XCTAssertEqual(row["sender"]?.stringValue, method.sender.rawValue, name)
            XCTAssertEqual(row["kind"]?.stringValue, method.isAnswered ? "request" : "notice", name)
            XCTAssertEqual(row["uses"]?.stringValue, method.service?.rawValue, name)
        }
        XCTAssertEqual(ProtocolFiles.json("protocol/methods.json")["protocol"]?.stringValue, ProtocolVersion.current)
    }

    func testEachTypeHasTheFieldsItsDefinitionDeclares() {
        let definitions = ProtocolFiles.json("protocol/messages.schema.json")["$defs"]
        for (name, value) in Self.shapes {
            XCTAssertEqual(ProtocolFiles.fields(of: value), ProtocolFiles.fields(declaredBy: definitions?[name]), name)
        }
        XCTAssertEqual(Set(Self.shapes.map(\.0)).union(Self.envelopes).union(Self.notStructs),
                       Set((definitions?.objectValue ?? [:]).keys),
                       "every definition has a Swift type, and every type a definition")
        let modifiers = definitions?["keyEquivalent"]?["properties"]?["modifiers"]?["items"]?["enum"]?.arrayValue
        XCTAssertEqual(modifiers?.compactMap(\.stringValue), KeyEquivalent.Modifier.allCases.map(\.rawValue))
    }

    func testEveryExampleIsReadAsTheSchemaReadsIt() throws {
        let examples = ProtocolFiles.json("protocol/examples/messages.json")["examples"]?.arrayValue ?? []
        XCTAssertFalse(examples.isEmpty)
        for example in examples {
            let about = example["about"]?.stringValue ?? "?"
            let valid = example["valid"]?.boolValue ?? false
            do {
                try Self.read(example)
                XCTAssertTrue(valid, "\(about): the schema refuses it and the Swift types read it")
            } catch let changed as Changed {
                // Reading a value as something else is not refusing it. For
                // an example the schema refuses, it means a type took what
                // the schema does not allow and made something of it.
                XCTFail("\(about): the Swift types read it and wrote back something else: \(changed)")
            } catch {
                XCTAssertFalse(valid, "\(about): the schema accepts it and the Swift types do not: \(error)")
            }
        }
    }

    /// What a type wrote back, when it is not what the type was given.
    private struct Changed: Error {
        let from: JSONValue
        let to: JSONValue
    }

    /// Reads one example as the app or a tool would, and throws where it
    /// cannot be read. Whatever is read must also come back as it went in;
    /// if it does not, the error is `Changed`.
    private static func read(_ example: JSONValue) throws {
        // What a type reads and writes back is what it was given, unless
        // the example carries a field version 1 does not have.
        func same(_ written: JSONValue, _ given: JSONValue) throws {
            if example["unknownFields"]?.boolValue != true, written != given {
                throw Changed(from: given, to: written)
            }
        }
        let original = example["message"] ?? .null
        let message = try LineFraming.message(from: JSONEncoder().encode(original))
        let written = try JSONValue(encoding: message)
        if written != original { throw Changed(from: original, to: written) }
        switch message {
        case .request(_, let name, let params), .notice(let name, let params):
            // A method version 1 does not have is still a message.
            guard let method = ToolMethod(rawValue: name) else { return }
            let carried = params ?? .object([:])
            try same(Self.params(method, carried), carried)
        case .result(_, let value):
            guard let method = (example["answers"]?.stringValue).flatMap(ToolMethod.init(rawValue:)),
                  let answered = try Self.result(method, value) else { return }
            try same(answered, value)
        case .failure(_, let error):
            guard let refusal = RefusalCode(error), refusal == .notInUses || refusal == .permissionMissing,
                  let data = error.data else { return }
            // The message was read, so its data was taken. Data that is
            // not what a refusal carries is a message the envelope should
            // have refused: the test's own reading of it is no refusal.
            guard let read = try? Self.again(data, as: RefusalData.self) else {
                throw Changed(from: data, to: .null)
            }
            try same(read, data)
        }
    }

    func testARefusalIsAFailureWithItsCode() {
        XCTAssertEqual(RefusalCode.allCases.map(\.rawValue), [-32001, -32002, -32003, -32004, -32010])
        let missing = RefusalCode.permissionMissing.error(permission: "accessibility")
        XCTAssertEqual(missing.code, -32003)
        XCTAssertEqual(missing.data, .object(["permission": .string("accessibility")]))
        XCTAssertEqual(RefusalCode(missing), .permissionMissing)
        XCTAssertEqual(RefusalCode.notInUses.error(service: .clipboardWrite).data,
                       .object(["service": .string("clipboard.write")]))
        XCTAssertNil(RefusalCode.unavailable.error().data)
        XCTAssertNil(RefusalCode(RPCErrorObject(code: RPCErrorCode.methodNotFound, message: "method not found")))
        XCTAssertEqual(Set(RefusalCode.allCases.map(\.message)).count, RefusalCode.allCases.count)
    }

    func testEveryServiceAMessageNeedsIsOneAManifestMayList() {
        XCTAssertEqual(Set(ToolMethod.allCases.compactMap(\.service)), Set(AppService.allCases))
        XCTAssertEqual(ToolMethod.allCases.filter { $0.sender == .app }.map(\.rawValue),
                       ["initialize", "command/run", "preferences/changed", "language/changed", "shutdown",
                        "ui/open", "ui/event", "ui/close"])
    }

    func testABlockIsItsKindAndItsThreeFields() {
        let definitions = ProtocolFiles.json("protocol/messages.schema.json")["$defs"]
        let block = definitions?["uiBlock"]
        XCTAssertEqual(ProtocolFiles.fields(declaredBy: block), ["type", "id", "fallback"])
        // Each kind picks the definition of its own fields, and the twelve
        // are the kinds the Swift type reads.
        let picked = (block?["allOf"]?.arrayValue ?? []).compactMap { branch -> (String, String)? in
            guard let kind = branch["if"]?["properties"]?["type"]?["const"]?.stringValue,
                  let target = branch["then"]?["$ref"]?.stringValue else { return nil }
            return (kind, target)
        }
        XCTAssertEqual(picked.map(\.0), UIBlock.kinds)
        XCTAssertEqual(picked.map(\.1), UIBlock.kinds.map { "#/$defs/\($0)Block" })
        let needingID = (block?["allOf"]?.arrayValue ?? []).compactMap {
            $0["if"]?["properties"]?["type"]?["enum"]?.arrayValue?.compactMap(\.stringValue)
        }
        XCTAssertEqual(needingID.map(Set.init), [UIBlock.kindsWithID])
        let tree = definitions?["uiTree"]?["properties"]?["blocks"]?["maxItems"]?.numberValue
        XCTAssertEqual(tree, Double(UILimits.maxBlocks))
        XCTAssertEqual(definitions?["listBlock"]?["properties"]?["rows"]?["maxItems"]?.numberValue,
                       Double(UILimits.maxListRows))
        XCTAssertEqual(definitions?["textBlock"]?["properties"]?["lines"]?["maximum"]?.numberValue,
                       Double(UILimits.maxTextLines))
        XCTAssertEqual(definitions?["spacerBlock"]?["properties"]?["size"]?["maximum"]?.numberValue, UILimits.maxSpacer)
        XCTAssertEqual(definitions?["imageBlock"]?["properties"]?["height"]?["maximum"]?.numberValue,
                       UILimits.maxImageHeight)
        let events = definitions?["uiEventParams"]?["properties"]?["event"]?["enum"]?.arrayValue
        XCTAssertEqual(events?.compactMap(\.stringValue), UIEventKind.allCases.map(\.rawValue))
        func listed(_ name: String, _ field: String) -> [String] {
            (definitions?[name]?["properties"]?[field]?["enum"]?.arrayValue ?? []).compactMap(\.stringValue)
        }
        XCTAssertEqual(listed("textBlock", "style"), TextBlock.Style.allCases.map(\.rawValue))
        XCTAssertEqual(listed("buttonBlock", "style"), ButtonBlock.Style.allCases.map(\.rawValue))
        XCTAssertEqual(listed("fieldBlock", "kind"), FieldBlock.Kind.allCases.map(\.rawValue))
        let said = definitions?["uiTree"]?["description"]?.stringValue ?? ""
        XCTAssertTrue(said.contains("262,144 bytes"), "the schema says the number the code holds: \(said)")
    }
}
