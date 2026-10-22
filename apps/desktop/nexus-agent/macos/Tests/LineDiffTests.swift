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

import NexusAgentUI
import XCTest

/// The diff a tool-step card draws for an edit or a write.
final class LineDiffTests: XCTestCase {
    typealias Line = NexusAgentLineDiff.Line

    func testWriteIsEveryLineAdded() {
        XCTAssertEqual(NexusAgentLineDiff.lines(old: nil, new: "a\nb\n"), [Line(.added, "a"), Line(.added, "b")])
    }

    func testCommonPrefixAndSuffixAreContext() {
        let lines = NexusAgentLineDiff.lines(old: "one\ntwo\nthree", new: "one\nTWO\nthree")
        XCTAssertEqual(lines, [Line(.context, "one"), Line(.removed, "two"), Line(.added, "TWO"), Line(.context, "three")])
        XCTAssertEqual(lines.map(\.unified), ["  one", "- two", "+ TWO", "  three"])
    }

    func testSeparateChangesKeepTheLinesBetweenThem() {
        let lines = NexusAgentLineDiff.lines(old: "a\nb\nc\nd\ne", new: "a\nB\nc\nd\nE")
        XCTAssertEqual(lines, [
            Line(.context, "a"), Line(.removed, "b"), Line(.added, "B"),
            Line(.context, "c"), Line(.context, "d"),
            Line(.removed, "e"), Line(.added, "E"),
        ])
    }

    func testDeletionOnly() {
        XCTAssertEqual(NexusAgentLineDiff.lines(old: "a\nb\nc", new: "a\nc"),
                       [Line(.context, "a"), Line(.removed, "b"), Line(.context, "c")])
    }

    func testIdenticalTextIsAllContext() {
        XCTAssertEqual(NexusAgentLineDiff.lines(old: "x\ny", new: "x\ny"), [Line(.context, "x"), Line(.context, "y")])
    }

    func testEmptyNewIsEveryLineRemoved() {
        XCTAssertEqual(NexusAgentLineDiff.lines(old: "x\ny", new: ""), [Line(.removed, "x"), Line(.removed, "y")])
    }
}
