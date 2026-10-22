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

/// The code-block highlighter, and running a shell block.
final class SyntaxHighlightTests: XCTestCase {
    typealias Kind = NexusAgentSyntaxHighlighter.Token.Kind

    private func kinds(_ code: String, _ language: String?) -> [String: Kind] {
        var result: [String: Kind] = [:]
        for token in NexusAgentSyntaxHighlighter.tokens(code: code, language: language) {
            result[token.text] = token.kind
        }
        return result
    }

    func testSwift() {
        let found = kinds(#"let name: String = "hi" // greet"# + "\nreturn 42", "swift")
        XCTAssertEqual(found["let"], .keyword)
        XCTAssertEqual(found["String"], .type)
        XCTAssertEqual(found["\"hi\""], .string)
        XCTAssertEqual(found["// greet"], .comment)
        XCTAssertEqual(found["return"], .keyword)
        XCTAssertEqual(found["42"], .number)
        XCTAssertNil(found["name"])
    }

    func testACommentMarkerInsideAStringIsString() {
        let found = kinds(#"const u = "http://x"; // c"#, "ts")
        XCTAssertEqual(found["\"http://x\""], .string)
        XCTAssertEqual(found["// c"], .comment)
        XCTAssertEqual(found["const"], .keyword)
    }

    func testPython() {
        let found = kinds("def f(x):\n    \"\"\"doc\"\"\"\n    return None  # nothing", "python")
        XCTAssertEqual(found["def"], .keyword)
        XCTAssertEqual(found["\"\"\"doc\"\"\""], .string)
        XCTAssertEqual(found["None"], .keyword)
        XCTAssertEqual(found["# nothing"], .comment)
    }

    func testShell() {
        let found = kinds("export PATH=\"$HOME/bin\" # add\nif [ -n $X ]; then echo ok; fi\ncurl a#b", "bash")
        XCTAssertEqual(found["export"], .keyword)
        XCTAssertEqual(found["\"$HOME/bin\""], .string)
        XCTAssertEqual(found["# add"], .comment)
        XCTAssertEqual(found["$X"], .variable)
        XCTAssertEqual(found["fi"], .keyword)
        XCTAssertNil(found["#b"], "a # inside a word is not a comment")
    }

    func testGoRustKotlin() {
        XCTAssertEqual(kinds("func main() { defer x() }", "go")["defer"], .keyword)
        XCTAssertEqual(kinds("fn main() { let mut v = 1; }", "rust")["mut"], .keyword)
        XCTAssertEqual(kinds("fun f(): Int = 1", "kotlin")["fun"], .keyword)
    }

    func testJSONKeysAndValues() {
        let found = kinds(#"{"name": "x", "ok": true, "n": -1.5}"#, "json")
        XCTAssertEqual(found["\"name\""], .key)
        XCTAssertEqual(found["\"x\""], .string)
        XCTAssertEqual(found["true"], .keyword)
        XCTAssertEqual(found["-1.5"], .number)
    }

    func testYAML() {
        let found = kinds("name: app # the name\nreplicas: 3\nenabled: true", "yaml")
        XCTAssertEqual(found["name"], .key)
        XCTAssertEqual(found["# the name"], .comment)
        XCTAssertEqual(found["3"], .number)
        XCTAssertEqual(found["true"], .keyword)
    }

    func testDiffLines() {
        let found = kinds("@@ -1 +1 @@\n-old\n+new\n same", "diff")
        XCTAssertEqual(found["@@ -1 +1 @@"], .meta)
        XCTAssertEqual(found["-old"], .removed)
        XCTAssertEqual(found["+new"], .added)
        XCTAssertNil(found[" same"])
    }

    func testUnknownLanguageIsPlainAndHighlightKeepsTheText() {
        XCTAssertTrue(NexusAgentSyntaxHighlighter.tokens(code: "let x = 1", language: "brainfuck").isEmpty)
        for language in ["swift", "python", "bash", "json", "yaml", "diff", nil] {
            let code = "let x = \"é😀\" // ü\n# z\n+ 1"
            XCTAssertEqual(String(NexusAgentSyntaxHighlighter.highlight(code: code, language: language).characters), code)
        }
    }

    func testShellLanguages() {
        XCTAssertTrue(NexusAgentSyntaxHighlighter.isShell("bash"))
        XCTAssertTrue(NexusAgentSyntaxHighlighter.isShell("Console"))
        XCTAssertFalse(NexusAgentSyntaxHighlighter.isShell("swift"))
        XCTAssertFalse(NexusAgentSyntaxHighlighter.isShell(nil))
    }

    func testConsoleTranscriptRunsOnlyThePromptedLines() {
        XCTAssertEqual(NexusAgentShellSnippet.runnableScript(from: "$ ls -la\ntotal 0\n$ pwd\n/x"), "ls -la\npwd")
        XCTAssertEqual(NexusAgentShellSnippet.runnableScript(from: "brew update\nbrew upgrade"), "brew update\nbrew upgrade")
    }

    func testCommandFileDeletesItselfAndQuotesTheFolder() {
        let file = NexusAgentShellSnippet.commandFile(script: "make", directory: "/it's here")
        let lines = file.components(separatedBy: "\n")
        XCTAssertTrue(lines[0].hasPrefix("#!"))
        XCTAssertEqual(lines[1], "rm -f -- \"$0\"")
        XCTAssertEqual(lines[2], "cd -- '/it'\\''s here' || exit 1")
        XCTAssertTrue(file.hasSuffix("make\n"))
        XCTAssertFalse(NexusAgentShellSnippet.commandFile(script: "ls", directory: nil).contains("cd --"))
    }

    func testRunAsksFirst() {
        let start = Date(timeIntervalSince1970: 1000)
        XCTAssertFalse(NexusAgentRunSnippetGuard.clickRuns(firstClick: nil, now: start))
        XCTAssertTrue(NexusAgentRunSnippetGuard.clickRuns(firstClick: start, now: start.addingTimeInterval(2.9)))
        XCTAssertFalse(NexusAgentRunSnippetGuard.clickRuns(firstClick: start, now: start.addingTimeInterval(3)))
        XCTAssertFalse(NexusAgentRunSnippetGuard.clickRuns(firstClick: start, now: start.addingTimeInterval(-1)))
    }

    func testThinkingPill() {
        let strings = NexusAgentChatStrings()
        XCTAssertNil(NexusAgentThinkingPill.label(durationMs: nil, tokens: nil, isStreaming: true, strings: strings))
        XCTAssertEqual(NexusAgentThinkingPill.label(durationMs: 4200, tokens: 320, isStreaming: false, strings: strings),
                       "Thought for 4s · 320 tok")
        XCTAssertEqual(NexusAgentThinkingPill.label(durationMs: nil, tokens: 420, isStreaming: true, strings: strings),
                       "Thinking… · 420 tok")
        XCTAssertEqual(NexusAgentThinkingPill.label(durationMs: nil, tokens: 420, isStreaming: false, strings: strings),
                       "Thought · 420 tok")
        XCTAssertEqual(NexusAgentThinkingPill.duration(400), "<1s")
        XCTAssertEqual(NexusAgentThinkingPill.duration(65_000), "1m 5s")
        XCTAssertEqual(NexusAgentThinkingPill.duration(120_000), "2m")
    }
}
