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

/// `file:line` references in a reply become links that open the file.
final class PathLinkTests: XCTestCase {
    private func link(_ text: String, cwd: String? = "/repo") -> String {
        NexusAgentPathLinks.linkify(text, workingDirectory: cwd)
    }

    func testRelativePathResolvesAgainstTheWorkingFolder() {
        XCTAssertEqual(link("See src/app.ts:42 for it."), "See [src/app.ts:42](file:///repo/src/app.ts#L42) for it.")
        XCTAssertEqual(link("in ./a/b.go:7"), "in [./a/b.go:7](file:///repo/a/b.go#L7)")
        XCTAssertEqual(link("../x.py:1", cwd: "/repo/sub"), "[../x.py:1](file:///repo/x.py#L1)")
    }

    func testLineAndColumn() {
        XCTAssertEqual(link("main.swift:12:5"), "[main.swift:12:5](file:///repo/main.swift#L12C5)")
    }

    func testAbsoluteAndHomePathsLinkWithoutAWorkingFolder() {
        XCTAssertEqual(link("/tmp/a.c:3", cwd: nil), "[/tmp/a.c:3](file:///tmp/a.c#L3)")
        let home = NSHomeDirectory()
        XCTAssertEqual(link("~/n.md:9.", cwd: nil), "[~/n.md:9](file://\(home)/n.md#L9).")
    }

    func testRelativePathsStayTextWithoutAWorkingFolder() {
        XCTAssertEqual(link("src/app.ts:42", cwd: nil), "src/app.ts:42")
    }

    func testCodeSpansLinksAndURLsAreLeftAlone() {
        XCTAssertEqual(link("`src/app.ts:42`"), "`src/app.ts:42`")
        XCTAssertEqual(link("``a.swift:1``"), "``a.swift:1``")
        XCTAssertEqual(link("[a.swift:1](https://x.dev)"), "[a.swift:1](https://x.dev)")
        XCTAssertEqual(link("<https://x.dev/a.swift:1>"), "<https://x.dev/a.swift:1>")
        XCTAssertEqual(link("open https://x:8080/a.js:3 now"), "open https://x:8080/a.js:3 now")
        XCTAssertEqual(link("http://localhost:8080"), "http://localhost:8080")
    }

    func testTimesHostsAndVersionsAreNotPaths() {
        XCTAssertEqual(link("at 10:30 today"), "at 10:30 today")
        XCTAssertEqual(link("example.com:8080"), "example.com:8080")
        XCTAssertEqual(link("ratio 1.5:2"), "ratio 1.5:2")
        XCTAssertEqual(link("a std::vector:3"), "a std::vector:3")
    }

    func testCodeSpanThenAPathOutsideIt() {
        XCTAssertEqual(link("`x.go:1` and y.go:2"), "`x.go:1` and [y.go:2](file:///repo/y.go#L2)")
    }

    func testTheRewrittenTextParsesAsALink() throws {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        let parsed = try AttributedString(markdown: link("see b/c.swift:3 now"), options: options)
        let links = parsed.runs.compactMap(\.link)
        XCTAssertEqual(links.count, 1)
        XCTAssertEqual(links.first?.isFileURL, true)
        XCTAssertEqual(links.first?.path, "/repo/b/c.swift")
        XCTAssertEqual(links.first?.fragment, "L3")
        XCTAssertEqual(String(parsed.characters), "see b/c.swift:3 now")
    }
}
