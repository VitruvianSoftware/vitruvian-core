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

final class FramingTests: XCTestCase {
    private func bytes(_ text: String) -> Data { Data(text.utf8) }

    /// How many bytes the splitter is holding back, read from its private
    /// buffer, so a test can say that it stays within the limit.
    private func held(_ splitter: LineSplitter) throws -> Int {
        let pending = Mirror(reflecting: splitter).children.first { $0.label == "pending" }?.value as? Data
        return try XCTUnwrap(pending, "LineSplitter keeps its unfinished line in `pending`").count
    }

    func testAMessageIsOneLine() throws {
        let message = RPCMessage.request(id: .number(1), method: "keystrokes/paste",
                                         params: .object(["text": .string("two\nlines\r\nand a / slash")]))
        let line = try LineFraming.line(for: message)
        XCTAssertEqual(line.last, 0x0A)
        XCTAssertEqual(line.filter { $0 == 0x0A }.count, 1, "the only line break is the one that ends the line")
        let text = String(decoding: line, as: UTF8.self)
        XCTAssertTrue(text.contains(#""method":"keystrokes/paste""#), "a slash is written as a slash: \(text)")
        XCTAssertEqual(try LineFraming.message(from: line.dropLast()), message)
    }

    func testAMessageOverTheLimitIsNotWritten() {
        let long = String(repeating: "x", count: WireLimits.maxLineBytes)
        let message = RPCMessage.notice(method: "log", params: .object(["message": .string(long)]))
        XCTAssertThrowsError(try LineFraming.line(for: message)) { error in
            XCTAssertTrue(error is LineFraming.LineTooLong)
        }
    }

    func testBytesBecomeLinesWhereverTheyAreCut() {
        var splitter = LineSplitter()
        XCTAssertEqual(splitter.append(bytes(#"{"a":"#)), [])
        XCTAssertEqual(splitter.append(bytes("1}\n{\"b\":2}\n{\"c\"")), [.line(bytes(#"{"a":1}"#)), .line(bytes(#"{"b":2}"#))])
        XCTAssertEqual(splitter.append(bytes(":3}")), [])
        XCTAssertEqual(splitter.append(bytes("\n")), [.line(bytes(#"{"c":3}"#))])

        // A character of several bytes cut in the middle arrives whole.
        let accented = bytes("{\"n\":\"Déploiements\"}\n")
        var cut = LineSplitter()
        var pieces: [LineSplitter.Piece] = []
        for byte in accented { pieces += cut.append(Data([byte])) }
        XCTAssertEqual(pieces, [.line(accented.dropLast())])
    }

    func testAMessageCutInsideACharacterIsTheMessageSent() throws {
        // Two reads, cut between the two bytes of "é" and again inside the
        // four bytes of an emoji: the message read is the message written.
        let message = RPCMessage.notice(method: "log", params: .object(["message": .string("Déploiements 🚀")]))
        let line = try LineFraming.line(for: message)
        for marker in [Data("é".utf8), Data("🚀".utf8)] {
            let cut = try XCTUnwrap(line.range(of: marker)).lowerBound + 1
            var splitter = LineSplitter()
            XCTAssertEqual(splitter.append(line[..<cut]), [])
            let pieces = splitter.append(line[cut...])
            guard case .line(let whole)? = pieces.first, pieces.count == 1 else {
                return XCTFail("one line expected, got \(pieces)")
            }
            XCTAssertEqual(try LineFraming.message(from: whole), message)
        }
    }

    func testEmptyLinesAreNotLines() {
        var splitter = LineSplitter()
        XCTAssertEqual(splitter.append(bytes("\n  \n\r\n{}\r\n\t\n")), [.line(bytes("{}\r"))])
    }

    func testALineEndedTheWindowsWayIsStillAMessage() throws {
        // The line keeps its carriage return; JSON reads it as white space.
        let message = RPCMessage.notice(method: "shutdown", params: nil)
        var windows = try LineFraming.line(for: message)
        windows.insert(0x0D, at: windows.count - 1)
        var splitter = LineSplitter()
        let pieces = splitter.append(windows + windows)
        XCTAssertEqual(pieces.count, 2)
        for piece in pieces {
            guard case .line(let line) = piece else { return XCTFail("a line expected, got \(piece)") }
            XCTAssertEqual(line.last, 0x0D)
            XCTAssertEqual(try LineFraming.message(from: line), message)
        }
    }

    func testALineOverTheLimitIsReportedOnceAndTheNextLineIsRead() {
        var splitter = LineSplitter(limit: 8)
        XCTAssertEqual(splitter.append(bytes("12345678\n")), [.line(bytes("12345678"))], "the limit itself is allowed")
        XCTAssertEqual(splitter.append(bytes("123456789")), [.oversized], "said as soon as it is known")
        XCTAssertEqual(splitter.append(bytes("more of the same line")), [])
        XCTAssertEqual(splitter.append(bytes(" and its end\nok\n")), [.line(bytes("ok"))])
        XCTAssertEqual(splitter.append(bytes("1234")), [])
        XCTAssertEqual(splitter.append(bytes("56789\nok\n")), [.oversized, .line(bytes("ok"))],
                       "a line that goes over when its end arrives")
        XCTAssertEqual(splitter.append(bytes("123456789\nok\n")), [.oversized, .line(bytes("ok"))])
    }

    func testALineOverTheLimitIsThrownAwayNotKept() throws {
        // 4 MB with no line break, in reads of 64 KB, against the real limit.
        // The splitter may hold up to the limit while the line could still be
        // a good one. The read that takes it over empties the buffer, and
        // every read after that is dropped until the line ends.
        let read = Data(repeating: UInt8(ascii: "x"), count: 65_536)
        var splitter = LineSplitter()
        var pieces: [LineSplitter.Piece] = []
        var most = 0
        for count in 1...64 {
            pieces += splitter.append(read)
            let holding = try held(splitter)
            most = max(most, holding)
            if count > 16 { XCTAssertEqual(holding, 0, "nothing of a line over the limit is kept (read \(count))") }
        }
        XCTAssertEqual(pieces, [.oversized], "said once, however long the line goes on")
        XCTAssertEqual(most, WireLimits.maxLineBytes, "never more than the limit: sixteen reads fill it exactly")
        XCTAssertEqual(splitter.append(bytes("the end of it\n{}\n")), [.line(bytes("{}"))])
        XCTAssertEqual(try held(splitter), 0)

        // The same line arriving in one read is never copied at all.
        var whole = Data(repeating: UInt8(ascii: "x"), count: WireLimits.maxLineBytes + 1)
        whole.append(bytes("\n{}\n"))
        var other = LineSplitter()
        XCTAssertEqual(other.append(whole), [.oversized, .line(bytes("{}"))])
        XCTAssertEqual(try held(other), 0)

        // One byte under: a line of exactly the limit is still a line.
        var allowed = LineSplitter()
        let longest = Data(repeating: UInt8(ascii: "x"), count: WireLimits.maxLineBytes)
        XCTAssertEqual(allowed.append(longest), [])
        XCTAssertEqual(allowed.append(bytes("\n")), [.line(longest)])
    }

    func testALastLineWithNoLineBreakIsNotALine() throws {
        // The other side stopped in the middle of a line. What arrived is
        // held, within the limit, and never given out as a message: a line
        // is a line once its line break has arrived.
        var splitter = LineSplitter()
        XCTAssertEqual(splitter.append(bytes("{\"jsonrpc\":\"2.0\",\"method\":\"shutdown\"}\n{\"jsonrpc\":\"2.0\",\"meth")),
                       [.line(bytes(#"{"jsonrpc":"2.0","method":"shutdown"}"#))])
        XCTAssertEqual(splitter.append(Data()), [], "an empty read, as at the end of input, gives nothing out")
        XCTAssertEqual(try held(splitter), 22)

        // A whole message with only its line break missing is not given out
        // either, until the line break comes.
        var whole = LineSplitter()
        XCTAssertEqual(whole.append(bytes(#"{"jsonrpc":"2.0","method":"shutdown"}"#)), [])
        XCTAssertEqual(whole.append(Data()), [])
        XCTAssertEqual(whole.append(bytes("\n")), [.line(bytes(#"{"jsonrpc":"2.0","method":"shutdown"}"#))])
    }

    func testTheLimitIsTheDesigns() {
        XCTAssertEqual(WireLimits.maxLineBytes, 1_048_576)
        XCTAssertEqual(LineSplitter().limit, WireLimits.maxLineBytes)
    }
}
