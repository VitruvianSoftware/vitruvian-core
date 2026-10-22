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

import NexusAgentToolCore

final class WordsTests: XCTestCase {
    func testEveryKeyIsInAllFifteenLanguagesAndEnglishIsFirst() {
        XCTAssertEqual(Words.languages.count, 15)
        XCTAssertEqual(Words.languages.first, "en")
        XCTAssertEqual(Set(Words.languages), Set(Words.table.keys))
        for language in Words.languages {
            let missing = Words.keys.filter { Words.table[language]?[$0]?.isEmpty ?? true }
            XCTAssertEqual(missing, [], "\(language) lacks \(missing)")
        }
        XCTAssertEqual(Set(Words.keys).count, Words.keys.count, "no key twice")
    }

    func testTheWordsAreTypesetAsTheAppsAre() {
        for (language, words) in Words.table {
            for (key, word) in words {
                XCTAssertFalse(word.contains("..."), "\(language).\(key) uses three dots, not an ellipsis")
                XCTAssertFalse(word.contains(" - ") || word.contains("—"), "\(language).\(key) has a dash")
                XCTAssertFalse(word.contains("\n"), "\(language).\(key) breaks a line")
            }
        }
    }

    func testARegionTagAndAnUnknownTagReadAsEnglish() {
        XCTAssertEqual(Words.text("start", "en-US"), Words.text("start", "en"))
        XCTAssertEqual(Words.text("start", "xx"), Words.text("start", "en"))
        XCTAssertEqual(Words.text("nothing", "fr"), "nothing", "an unknown key is itself")
        XCTAssertEqual(Words.text("start", "de"), "Starten")
    }

    func testTheChatAndDockWordsAreThereInEveryLanguage() {
        let added = ["pinWindow", "unpinWindow", "scrollToBottom", "newMessages", "emptyHint", "newChatShortcut",
                     "dockToNotch", "dockToNotchHelp"]
        for key in added {
            XCTAssertTrue(Words.keys.contains(key), "\(key) is listed")
            for language in Words.languages {
                let word = Words.text(key, language)
                XCTAssertFalse(word.isEmpty || word == key, "\(language).\(key)")
            }
        }
        XCTAssertEqual(Words.text("pinWindow", "en"), "Pin window")
        XCTAssertEqual(Words.text("emptyHint", "en"), "Type a prompt above to start an agent session.")
        XCTAssertEqual(Words.text("newChatShortcut", "ko"), " (⌘N)", "the shortcut is written the same everywhere")
        for language in Words.languages where language != "en" {
            XCTAssertNotEqual(Words.text("dockToNotchHelp", language), Words.text("dockToNotchHelp", "en"), language)
            XCTAssertNotEqual(Words.text("scrollToBottom", language), Words.text("scrollToBottom", "en"), language)
        }
    }
}
