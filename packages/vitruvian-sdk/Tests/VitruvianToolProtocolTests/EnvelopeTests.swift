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

final class EnvelopeTests: XCTestCase {
    private func read(_ text: String) throws -> RPCMessage {
        try LineFraming.message(from: Data(text.utf8))
    }

    func testTheFourKindsOfMessageAreToldApart() throws {
        XCTAssertEqual(
            try read(#"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"language":"en-US"}}"#),
            .request(id: .number(1), method: "initialize", params: .object(["language": .string("en-US")])))
        XCTAssertEqual(try read(#"{"jsonrpc":"2.0","method":"shutdown"}"#),
                       .notice(method: "shutdown", params: nil))
        XCTAssertEqual(try read(#"{"jsonrpc":"2.0","id":"a-7","result":{}}"#),
                       .result(id: .string("a-7"), value: .object([:])))
        XCTAssertEqual(
            try read(#"{"jsonrpc":"2.0","id":2,"error":{"code":-32601,"message":"method not found"}}"#),
            .failure(id: .number(2), error: RPCErrorObject(code: -32601, message: "method not found")))
        XCTAssertEqual(
            try read(#"{"jsonrpc":"2.0","id":null,"error":{"code":-32700,"message":"parse error"}}"#),
            .failure(id: nil, error: RPCErrorObject(code: RPCErrorCode.parseError, message: "parse error")))
    }

    func testWhatIsNotAMessageIsRefused() {
        let lines = [
            "not json",
            "[]",
            #"{"id":1,"method":"initialize"}"#,
            #"{"jsonrpc":"1.0","id":1,"method":"initialize"}"#,
            #"{"jsonrpc":"2.0","id":null,"method":"initialize"}"#,
            #"{"jsonrpc":"2.0","id":1.5,"method":"initialize"}"#,
            #"{"jsonrpc":"2.0","id":true,"method":"initialize"}"#,
            #"{"jsonrpc":"2.0","id":1,"method":7}"#,
            #"{"jsonrpc":"2.0","id":1,"method":"log","params":[1]}"#,
            #"{"jsonrpc":"2.0","id":1,"method":"log","params":"text"}"#,
            #"{"jsonrpc":"2.0","id":1,"method":"log","result":{}}"#,
            #"{"jsonrpc":"2.0","id":1}"#,
            #"{"jsonrpc":"2.0","result":{}}"#,
            #"{"jsonrpc":"2.0","id":1,"result":{},"error":{"code":1,"message":"both"}}"#,
            #"{"jsonrpc":"2.0","error":{"code":1,"message":"no id"}}"#,
            #"{"jsonrpc":"2.0","id":1,"error":{"message":"no code"}}"#,
        ]
        for line in lines {
            XCTAssertThrowsError(try read(line), line)
        }
    }

    func testAMessageWrittenIsTheMessageRead() throws {
        let messages: [RPCMessage] = [
            .request(id: .number(7), method: "command/run", params: .object(["command": .string("copyLatest")])),
            .request(id: .string("t-1"), method: "notify/beep", params: nil),
            .notice(method: "commands/state", params: .object(["runnable": .array([.string("a"), .string("b")])])),
            .result(id: .number(7), value: .object(["value": .number(20.5), "on": .bool(true), "none": .null])),
            .failure(id: .number(7), error: RPCErrorObject(code: -32001, message: "not listed in uses",
                                                           data: .object(["service": .string("clipboard.write")]))),
            .failure(id: nil, error: RPCErrorObject(code: RPCErrorCode.parseError, message: "parse error")),
        ]
        for message in messages {
            let line = try LineFraming.line(for: message)
            XCTAssertEqual(try LineFraming.message(from: line.dropLast()), message)
        }
    }

    private struct Greeting: Codable, Equatable {
        let language: String
        let versions: [String]
    }

    func testAValueIsReadAsATypeAndWrittenBack() throws {
        let greeting = Greeting(language: "fr", versions: ["1"])
        let value = try JSONValue(encoding: greeting)
        XCTAssertEqual(value["language"], .string("fr"))
        XCTAssertEqual(value["versions"]?.arrayValue, [.string("1")])
        XCTAssertEqual(try value.decode(Greeting.self), greeting)
        XCTAssertEqual(try JSONValue.object(["language": .string("fr"), "versions": .array([]), "later": .null])
                           .decode(Greeting.self),
                       Greeting(language: "fr", versions: []), "a field the type does not have is ignored")
        XCTAssertThrowsError(try JSONValue.object(["language": .number(1)]).decode(Greeting.self))
        XCTAssertEqual(try JSONValue(encoding: 3), .number(3))
        XCTAssertNil(JSONValue.string("x")["language"])
    }
}
