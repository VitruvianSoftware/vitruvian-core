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


import Foundation
@testable import VitruvianCodeCore
import XCTest

/// The handoff text, checked against T3 Code's `handoffBudget.ts` at d6e5f2e0.
final class AgentContextHandoffTests: XCTestCase {
    private func message(_ index: Int, _ role: AgentContextHandoff.HistoricalMessage.Role, _ text: String)
        -> AgentContextHandoff.HistoricalMessage {
        .init(role: role, text: text, threadID: "t", runOrdinal: index, itemID: "i\(index)",
              providerThreadID: "p", status: "completed", kind: role == .user ? "user_message" : "assistant_message")
    }

    func testRendersEachRowAsT3CodeDoes() {
        let rendered = AgentContextHandoff.renderHistory([message(1, .user, "hi")], context: "ctx")
        XCTAssertEqual(rendered,
                       "ctx\n\n[Historical user; user_message; thread=t; run=1; item=i1; provider-thread=p; status=completed]\nhi")
        XCTAssertEqual(AgentContextHandoff.withInlineContext("", userText: "go"), "go")
        XCTAssertEqual(AgentContextHandoff.withInlineContext("ctx", userText: "go"), "ctx\n\nUser message:\ngo")
    }

    func testMeasuresLikeJSONStringify() throws {
        for text in ["plain", "quote \" and \\ slash / tab\t", "line\nfeed\r\u{01}", "émoji 🚀 漢字"] {
            let quoted = AgentContextHandoff.jsonQuoted(text)
            XCTAssertEqual(try JSONSerialization.jsonObject(with: Data(quoted.utf8), options: .fragmentsAllowed) as? String, text)
            XCTAssertFalse(quoted.contains("\\/"), "JSON.stringify leaves / alone")
        }
        XCTAssertEqual(AgentContextHandoff.jsonQuoted("a\u{01}"), "\"a\\u0001\"")
    }

    /// Over the cap, T3 Code keeps the first user message and the newest rows, each whole, and
    /// says how many it left out.
    func testKeepsTheFirstAndNewestRowsUnderTheCap() {
        let filler = String(repeating: "x", count: 3_000)
        var items: [AgentContextHandoff.HistoricalMessage] = []
        for index in 1...20 {
            items.append(message(index, index.isMultiple(of: 2) ? .assistant : .user, "row \(index) \(filler)"))
        }
        let prompt = try! XCTUnwrap(AgentContextHandoff.prompt(
            strategy: .fullThreadSummary, threadID: "t", runs: 1...20, items: items, userText: "next",
            attachments: [], nativeContextEstimate: 0))
        XCTAssertLessThanOrEqual(AgentContextHandoff.jsonQuoted(prompt).utf8.count,
                                 AgentContextHandoff.defaultTokenCap + 64, "the history stays within the cap")
        XCTAssertTrue(prompt.contains("]\nrow 1 "), "the first user message is kept")
        XCTAssertTrue(prompt.contains("]\nrow 20 ") && prompt.contains("]\nrow 19 "), "the newest rows are kept")
        XCTAssertFalse(prompt.contains("]\nrow 10 "), "the middle is dropped")
        let selection = AgentContextHandoff.selectHistory(items, coverage: "c", budget: AgentContextHandoff.defaultTokenCap)
        XCTAssertTrue(prompt.contains("Selected \(selection.messages.count) intact items; omitted \(20 - selection.messages.count) items."), prompt)
        XCTAssertEqual(selection.messages.map(\.itemID).first, "i1")
    }

    /// `handoffBudget`: a prompt that fills the window leaves no room, and the history is not sent.
    func testAPromptThatFillsTheWindowSendsNoHistory() {
        let huge = String(repeating: "y", count: 100_000)
        XCTAssertEqual(AgentContextHandoff.budget(userText: huge, attachments: [], nativeContextEstimate: 0), 0)
        XCTAssertEqual(AgentContextHandoff.budget(userText: "hi", attachments: [], nativeContextEstimate: 0),
                       AgentContextHandoff.defaultTokenCap)
        XCTAssertNil(AgentContextHandoff.prompt(strategy: .fullThreadSummary, threadID: "t", runs: 1...1,
                                                items: [message(1, .user, "a")], userText: huge,
                                                attachments: [], nativeContextEstimate: 0))
    }

    /// Commands and file changes from an agent's reply go ahead of its text, as T3 Code's items do.
    func testToolStepsBecomeTheirOwnRows() {
        let reply = VitruvianCodeChatMessage(role: .agent, text: "done", toolSteps: [
            VitruvianCodeToolStep(id: "s1", title: "Bash", detail: "ls -la", kind: .bash, output: "a.txt"),
            VitruvianCodeToolStep(id: "s2", title: "Edit", detail: nil, kind: .edit, filePath: "/r/a.txt"),
            VitruvianCodeToolStep(id: "s3", title: "Read", detail: nil, kind: .read),
        ])
        let rows = AgentContextHandoff.historicalMessages([.init(message: reply, runOrdinal: 1, agentSessionID: "s")], threadID: "t")
        XCTAssertEqual(rows.map(\.kind), ["command_execution", "file_change", "assistant_message"])
        XCTAssertEqual(rows[0].text, "Command: ls -la\nExit code: unknown\na.txt")
        XCTAssertEqual(rows[1].text, "File change: /r/a.txt")
    }
}
