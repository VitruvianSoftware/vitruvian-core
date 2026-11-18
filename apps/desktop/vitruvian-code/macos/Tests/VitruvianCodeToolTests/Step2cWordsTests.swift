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

import VitruvianCodeToolCore
import XCTest

final class Step2cWordsTests: XCTestCase {
    func testApprovalAndQuestionCardWordsExistAndTranslateInAllFifteenLanguages() {
        let addedKeys = [
            "permissionRequest",
            "awaitingConfirmation",
            "approved",
            "denied",
            "allowedForSession",
            "allow",
            "deny",
            "allowForSession",
            "moreApprovalOptions",
            "questionTitle",
            "waitingForAnswer",
            "answered",
            "skipped",
            "noLongerWaiting",
            "skipQuestion",
            "openLink",
            "declineLink",
            "requiredField",
            "invalidNumber",
            "invalidInteger",
            "booleanYes",
            "booleanNo",
        ]

        for key in addedKeys {
            XCTAssertTrue(Words.keys.contains(key), "\(key) missing from Words.keys")
            for language in Words.languages {
                let word = Words.text(key, language)
                XCTAssertFalse(word.isEmpty || word == key, "\(language).\(key) missing translation")
            }
        }

        for language in Words.languages where language != "en" {
            XCTAssertNotEqual(Words.text("waitingForAnswer", language), Words.text("waitingForAnswer", "en"), language)
            XCTAssertNotEqual(Words.text("moreApprovalOptions", language), Words.text("moreApprovalOptions", "en"), language)
            XCTAssertNotEqual(Words.text("permissionRequest", language), Words.text("permissionRequest", "en"), language)
        }
    }
}
