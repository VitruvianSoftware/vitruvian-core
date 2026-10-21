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

import NexusAgentCore

/// How a saved OpenCode conversation is read back into the chat: one reply
/// per turn, and tool steps that say what they ran.
final class OpenCodeTranscriptTests: XCTestCase {
    /// A 2.x row: a whole message.
    private func row(_ type: String, _ data: [String: Any]) -> [String: Any] {
        ["type": type, "data": data]
    }

    private func tool(_ name: String, state: [String: Any]) -> [String: Any] {
        ["type": "tool", "tool": name, "state": state]
    }

    func testTheStepsOfOneTurnAreOneReply() throws {
        let rows = [
            row("user", ["text": "fix the build"]),
            row("assistant", ["content": [["type": "reasoning", "text": "Look first."],
                                          tool("bash", state: ["input": ["command": "bazel build //..."]])]]),
            row("assistant", ["content": [tool("read", state: ["input": ["filePath": "/a/BUILD"]])]]),
            row("assistant", ["content": [["type": "reasoning", "text": "Found it."],
                                          ["type": "text", "text": "Fixed."]]]),
            row("user", ["text": "thanks"]),
            row("assistant", ["content": [["type": "text", "text": "Any time."]]]),
        ]
        let messages = try XCTUnwrap(NexusAgentEngine.parseOpenCodeMessages(rows))
        XCTAssertEqual(messages.map(\.role), [.user, .agent, .user, .agent])
        let turn = messages[1]
        XCTAssertEqual(turn.toolSteps?.map(\.title), ["bazel build //...", "/a/BUILD"])
        XCTAssertEqual(turn.thinkingText, "Look first.\n\nFound it.")
        XCTAssertEqual(turn.text, "Fixed.")
        XCTAssertEqual(messages[3].text, "Any time.")
        XCTAssertNil(messages[3].toolSteps)
    }

    func testAToolStepSaysWhatItRan() throws {
        let steps: [([String: Any], String)] = [
            (["title": "List the repo", "input": [:] as [String: Any]], "List the repo"),
            (["input": ["code": "\n  print(1)\nprint(2)"]], "execute: print(1)"),
            (["input": ["path": "/src"]], "/src"),
            (["input": ["pattern": "*.swift"]], "*.swift"),
            (["input": ["url": "https://example.com"]], "https://example.com"),
            (["input": [:] as [String: Any]], "execute"),
        ]
        let rows = [row("assistant", ["content": steps.map { tool("execute", state: $0.0) }])]
        let messages = try XCTUnwrap(NexusAgentEngine.parseOpenCodeMessages(rows))
        XCTAssertEqual(messages.first?.toolSteps?.map(\.title), steps.map(\.1))
    }

    func testLongCodeIsCutToOneShortLine() throws {
        let code = String(repeating: "x", count: 200)
        let rows = [row("assistant", ["content": [tool("execute", state: ["input": ["code": code]])]])]
        let title = try XCTUnwrap(NexusAgentEngine.parseOpenCodeMessages(rows)?.first?.toolSteps?.first?.title)
        XCTAssertEqual(title.count, 80)
        XCTAssertTrue(title.hasPrefix("execute: x"))
    }

    func testARunningStepIsNotFinished() throws {
        let rows = [row("assistant", ["content": [tool("bash", state: ["status": "running",
                                                                     "input": ["command": "sleep 9"]])]])]
        let step = try XCTUnwrap(NexusAgentEngine.parseOpenCodeMessages(rows)?.first?.toolSteps?.first)
        XCTAssertFalse(step.isFinished)
    }
}
