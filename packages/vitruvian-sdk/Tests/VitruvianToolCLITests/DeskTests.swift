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

import VitruvianToolCLI
import VitruvianToolProtocol

/// What `run` answers a tool's requests with.
final class DeskTests: XCTestCase {
    private func desk(uses: [String] = AppService.allCases.map(\.rawValue), status: Bool = true) throws -> Desk {
        let manifest = """
            {"id":"com.example.desk","name":{"en":"Desk"},"version":"1","protocol":"2","publisher":"Example",
             "uses":\(String(decoding: try JSONEncoder().encode(uses), as: UTF8.self)),
             "contributes":{\(status ? #""status":{"placement":"island"}"# : "")},
             "preferences":[{"id":"project","type":"string","default":"web"},{"id":"count","type":"integer","default":0}],
             "runtime":{"kind":"external","exec":"bin/tool"}}
            """
        return Desk(manifest: try ToolManifestFile.read(Data(manifest.utf8)).get())
    }

    private func params(_ json: String) throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: Data(json.utf8))
    }

    private func code(_ answer: Desk.Answer) -> Int? {
        if case .failure(let error) = answer { return error.code }
        return nil
    }

    func testEveryRequestATooMaySendIsAnswered() throws {
        var desk = try desk()
        let asked: [(ToolMethod, String, String)] = [
            (.notifyHUD, #"{"icon":"bell","message":"Hi"}"#, "{}"),
            (.notifyBeep, "{}", "{}"),
            (.openURL, #"{"url":"https://example.com/a"}"#, #"{"opened":true}"#),
            (.clipboardReadText, "{}", #"{"text":"text from vitruvian-tool run"}"#),
            (.clipboardWriteText, #"{"text":"mine"}"#, #"{"written":true}"#),
            (.clipboardReadText, "{}", #"{"text":"mine"}"#),
            (.keystrokesPaste, #"{"text":"typed"}"#, "{}"),
            (.keystrokesPressMenuItem, #"{"equivalents":[{"character":"c","modifiers":["shift"]}]}"#, #"{"pressed":true}"#),
            (.processesTerminate, #"{"pid":1,"name":"launchd","force":true}"#, "{}"),
            (.storageGet, #"{"key":"project"}"#, #"{"value":"web"}"#),
            (.storageSet, #"{"key":"count","value":4}"#, "{}"),
            (.storageGet, #"{"key":"count"}"#, #"{"value":4}"#),
            (.uiBadge, #"{"count":2}"#, "{}"),
            (.uiStatus, #"{"state":"busy","icon":"arrow.triangle.branch"}"#, "{}"),
        ]
        for (method, sent, wanted) in asked {
            let (answer, said) = desk.serve(method.rawValue, try params(sent))
            XCTAssertEqual(try answer.get(), try params(wanted), method.rawValue)
            XCTAssertFalse(said.isEmpty)
        }
        let answered = Set(asked.map(\.0))
        XCTAssertEqual(answered, Set(ToolMethod.allCases.filter { $0.sender == .tool && $0.isAnswered }))
    }

    func testAStatusIsSaidAndAnUndeclaredOneRefused() throws {
        var desk = try desk(uses: [])
        XCTAssertEqual(desk.serve("ui/status", try params(#"{"state":"busy"}"#)).said,
                       "the app would show busy on the closed island", "it needs nothing in `uses`")
        XCTAssertEqual(desk.serve("ui/status", try params(#"{"state":"failure","text":"main is red"}"#)).said,
                       "the app would show failure on the closed island, saying \"main is red\"")
        XCTAssertEqual(desk.serve("ui/status", try params(#"{"state":"ok","text":{"en":"Fine","fr":"Bien"}}"#)).said,
                       "the app would show ok on the closed island, saying \"Fine\"")
        let gone = desk.serve("ui/status", try params(#"{"state":"none"}"#))
        XCTAssertEqual(try gone.answer.get(), .object([:]))
        XCTAssertEqual(gone.said, "the app would show no status on the closed island")
        XCTAssertEqual(code(desk.serve("ui/status", try params(#"{"state":"broken"}"#)).answer), -32602)
        XCTAssertEqual(code(desk.serve("ui/status", nil).answer), -32602)

        var undeclared = try self.desk(status: false)
        let refused = undeclared.serve("ui/status", try params(#"{"state":"busy"}"#))
        XCTAssertEqual(code(refused.answer), -32602, "as the app refuses it")
        XCTAssertEqual(refused.said, "refused: the manifest declares no status. Add `contributes.status`")
        // Params that are not the message's are that first, declared or not.
        XCTAssertEqual(undeclared.serve("ui/status", try params(#"{"state":"broken"}"#)).said,
                       "params that are not this message's")
    }

    func testItRefusesWhatTheAppRefuses() throws {
        var desk = try desk(uses: ["storage"])
        let (unlisted, said) = desk.serve("notify/hud", try params(#"{"icon":"bell","message":"Hi"}"#))
        guard case .failure(let error) = unlisted else { return XCTFail("answered") }
        XCTAssertEqual(error, RefusalCode.notInUses.error(service: .notify))
        XCTAssertEqual(said, "refused: `notify` is not in the manifest's `uses`")

        XCTAssertEqual(code(desk.serve("storage/get", try params(#"{"key":"nope"}"#)).answer), -32602)
        XCTAssertEqual(code(desk.serve("storage/set", try params(#"{"key":"nope","value":1}"#)).answer), -32602)
        XCTAssertEqual(code(desk.serve("storage/set", try params(#"{"key":"count","value":1.5}"#)).answer), -32602)
        XCTAssertEqual(code(desk.serve("storage/set", try params(#"{"key":"count"}"#)).answer), -32602)
        XCTAssertEqual(desk.values["count"], .number(0), "a refused value is not kept")

        let most = String(repeating: "é", count: StorageLimits.maxTextLength)
        XCTAssertEqual(StorageLimits.maxTextLength, 4_096)
        XCTAssertNotNil(try? desk.serve("storage/set", .object(["key": .string("project"), "value": .string(most)]))
            .answer.get(), "the longest text the app saves is saved here too")
        let over = desk.serve("storage/set", .object(["key": .string("project"), "value": .string(most + "é")]))
        XCTAssertEqual(code(over.answer), -32602)
        XCTAssertEqual(over.said, "refused: `project` would be over 4096 characters, the most the app saves")
        XCTAssertEqual(desk.values["project"], .string(most), "and a longer one is refused, as the app refuses it")

        for unknown in ["island/draw", "initialize", "command/run", "log", "commands/state"] {
            XCTAssertEqual(code(desk.serve(unknown, nil).answer), -32601, unknown)
        }

        var all = try self.desk()
        XCTAssertEqual(code(all.serve("notify/hud", try params(#"{"icon":"bell"}"#)).answer), -32602)
        XCTAssertEqual(code(all.serve("open/url", try params(#"{"url":"no scheme"}"#)).answer), -32602)
        all.refuseAll = true
        XCTAssertEqual(code(all.serve("notify/beep", nil).answer), -32004)
        XCTAssertEqual(code(all.serve("island/draw", nil).answer), -32601, "an unknown request is unknown first")
    }
}
