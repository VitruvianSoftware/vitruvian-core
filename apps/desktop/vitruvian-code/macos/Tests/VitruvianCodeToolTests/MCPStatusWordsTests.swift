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

import VitruvianCodeCore
@testable import VitruvianCodeToolCore
import XCTest

/// The words of the chat's MCP status panel.
@MainActor
final class MCPStatusWordsTests: XCTestCase {
    private let keys = ["mcpStatusButton", "mcpStatusExplanation", "mcpStatusNone", "mcpStatusNotConnected", "mcpStatusFailedPrefix", "mcpStatusLoading", "mcpStatusRefresh", "mcpStatusReveal", "mcpStateConnected", "mcpStateFailed", "mcpStateNeedsSignIn", "mcpStatePending", "mcpStateDisabled", "mcpStateUnknown", "mcpSourceClaudeUser", "mcpSourceClaudeLocal", "mcpSourceClaudeProject", "mcpSourceClaudeAI", "mcpSourceClaudeManaged", "mcpSourceClaudePlugin", "mcpSourceClaudeAgent", "mcpSourceClaudeOther", "mcpSourceAgy"]

    func testTheMCPStatusWordsExistAndTranslateInAllFifteenLanguages() {
        for key in keys {
            XCTAssertTrue(Words.keys.contains(key), "\(key) missing from Words.keys")
            for language in Words.languages {
                let word = Words.text(key, language)
                XCTAssertFalse(word.isEmpty || word == key, "\(language).\(key) missing translation")
                if language != "en" {
                    XCTAssertNotEqual(word, Words.text(key, "en"), "\(language).\(key) is still English")
                }
            }
        }
    }

    func testAutomationReEnableIsInEachLanguagesOwnScript() {
        // These were each one language off: Italian had Japanese, Japanese had Korean, and so on.
        XCTAssertEqual(Words.text("automationNeedsReEnable", "it"), "Disattiva, riattiva e poi esporta di nuovo")
        XCTAssertEqual(Words.text("automationNeedsReEnable", "ja"), "オフにしてオンに戻し、再度書き出してください")
        XCTAssertEqual(Words.text("automationNeedsReEnable", "ko"), "껐다 켠 뒤 다시 내보내세요")
        XCTAssertEqual(Words.text("automationNeedsReEnable", "uk"), "Вимкніть, увімкніть і експортуйте знову")
        XCTAssertEqual(Words.text("automationNeedsReEnable", "zh-Hans"), "请先关闭再开启，然后重新导出")
    }
}
