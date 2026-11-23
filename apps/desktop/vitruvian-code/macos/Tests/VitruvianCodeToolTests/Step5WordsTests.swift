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

@MainActor
final class Step5WordsTests: XCTestCase {
    private let keys = ["automationNeedsYouTitle", "automationNeedsYouBodyFormat", "automationNeedsReEnable"]

    func testTheWordsOfScheduledRunsExistAndTranslateInAllFifteenLanguages() {
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

    func testTheNotificationNamesTheTaskInEveryLanguageAndHoldsNothingElse() {
        for language in Words.languages {
            let strings = ToolSettings.strings(for: language)
            let notice = strings.automationNeedsYou(taskName: "\u{201C}Nightly check\u{201D}")
            XCTAssertTrue(notice.body.contains("Nightly check"), "\(language): the body names the task")
            XCTAssertFalse(notice.body.contains("%@"), "\(language): the name is filled in")
            XCTAssertFalse(notice.title.isEmpty, language)
        }
    }
}
