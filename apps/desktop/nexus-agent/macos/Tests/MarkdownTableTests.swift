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

import NexusAgentCore
import XCTest

/// GitHub-style pipe tables in a reply's prose.
final class MarkdownTableTests: XCTestCase {
    func testParsesHeaderDelimiterAndRows() {
        let blocks = NexusAgentMarkdownBlock.parse("""
        Intro line
        | Name | Size |
        | --- | :---: |
        | a.swift | 12 |
        | b.swift | 7 |
        After
        """)
        XCTAssertEqual(blocks, [
            .paragraph(text: "Intro line"),
            .table(headers: ["Name", "Size"], rows: [["a.swift", "12"], ["b.swift", "7"]]),
            .paragraph(text: "After"),
        ])
    }

    func testOuterPipesAreOptional() {
        let blocks = NexusAgentMarkdownBlock.parse("a | b\n--|:-:\n1 | 2")
        XCTAssertEqual(blocks, [.table(headers: ["a", "b"], rows: [["1", "2"]])])
    }

    func testEscapedPipeStaysInTheCell() {
        let blocks = NexusAgentMarkdownBlock.parse("| op | means |\n|---|---|\n| `a \\| b` | or |")
        XCTAssertEqual(blocks, [.table(headers: ["op", "means"], rows: [["`a | b`", "or"]])])
    }

    func testShortRowsArePaddedAndLongRowsCut() {
        let blocks = NexusAgentMarkdownBlock.parse("| a | b | c |\n|---|---|---|\n| 1 |\n| 1 | 2 | 3 | 4 |")
        XCTAssertEqual(blocks, [.table(headers: ["a", "b", "c"], rows: [["1", "", ""], ["1", "2", "3"]])])
    }

    func testHeaderOnlyTable() {
        XCTAssertEqual(NexusAgentMarkdownBlock.parse("| a | b |\n| - | - |"), [.table(headers: ["a", "b"], rows: [])])
    }

    func testBlankLineEndsTheTable() {
        let blocks = NexusAgentMarkdownBlock.parse("| a |\n| --- |\n| 1 |\n\n| not a row |")
        XCTAssertEqual(blocks, [.table(headers: ["a"], rows: [["1"]]), .paragraph(text: "| not a row |")])
    }

    func testNotATableWithoutAMatchingDelimiterRow() {
        // A pipe in prose, a delimiter of the wrong width, a plain divider.
        XCTAssertEqual(NexusAgentMarkdownBlock.parse("use a | b here\nnext"), [.paragraph(text: "use a | b here\nnext")])
        XCTAssertEqual(NexusAgentMarkdownBlock.parse("| a | b |\n| --- |"), [.paragraph(text: "| a | b |\n| --- |")])
        XCTAssertEqual(NexusAgentMarkdownBlock.parse("text\n---"), [.paragraph(text: "text"), .divider])
    }
}
