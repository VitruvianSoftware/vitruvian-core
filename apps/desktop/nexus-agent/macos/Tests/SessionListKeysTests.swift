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

/// The arrow keys and Return in the sessions drawer, as the standalone app's
/// own chat handled them (`moveSelection` and the prompt's `onSubmit` in its
/// `QuickPromptView`). The view only calls these rules, so they are tested
/// here without one.
final class SessionListKeysTests: XCTestCase {
    private typealias Keys = NexusAgentSessionListKeys

    func testDownStartsAtTheTopAndStopsAtTheBottom() {
        XCTAssertEqual(Keys.selection(after: .down, from: nil, count: 3), 0, "with nothing selected, down takes the first row")
        XCTAssertEqual(Keys.selection(after: .down, from: 0, count: 3), 1)
        XCTAssertEqual(Keys.selection(after: .down, from: 1, count: 3), 2)
        XCTAssertEqual(Keys.selection(after: .down, from: 2, count: 3), 2, "it stops at the last row; it does not wrap")
    }

    func testUpStartsAtTheBottomAndStopsAtTheTop() {
        XCTAssertEqual(Keys.selection(after: .up, from: nil, count: 3), 2, "with nothing selected, up takes the last row")
        XCTAssertEqual(Keys.selection(after: .up, from: 2, count: 3), 1)
        XCTAssertEqual(Keys.selection(after: .up, from: 1, count: 3), 0)
        XCTAssertEqual(Keys.selection(after: .up, from: 0, count: 3), 0, "it stops at the first row; it does not wrap")
    }

    func testAnEmptyListLeavesTheSelectionAlone() {
        for arrow in [Keys.Arrow.up, .down] {
            XCTAssertNil(Keys.selection(after: arrow, from: nil, count: 0))
            XCTAssertEqual(Keys.selection(after: arrow, from: 4, count: 0), 4, "nothing is changed, as in the standalone")
        }
    }

    func testOneRow() {
        XCTAssertEqual(Keys.selection(after: .down, from: nil, count: 1), 0)
        XCTAssertEqual(Keys.selection(after: .up, from: nil, count: 1), 0)
        XCTAssertEqual(Keys.selection(after: .down, from: 0, count: 1), 0)
        XCTAssertEqual(Keys.selection(after: .up, from: 0, count: 1), 0)
    }

    /// The filter can shorten the list under a selection. The standalone
    /// keeps the number it had: down comes back to the last row, up only
    /// steps one back, and Return ignores a row that is not there.
    func testASelectionPastTheEndOfAShorterList() {
        XCTAssertEqual(Keys.selection(after: .down, from: 8, count: 2), 1)
        XCTAssertEqual(Keys.selection(after: .up, from: 8, count: 2), 7)
        XCTAssertEqual(Keys.selection(after: .up, from: 2, count: 2), 1)
    }

    func testReturnResumesOnlyARowThatIsThere() {
        XCTAssertNil(Keys.rowToResume(selection: nil, count: 3), "nothing selected: Return is the prompt's")
        XCTAssertEqual(Keys.rowToResume(selection: 0, count: 3), 0)
        XCTAssertEqual(Keys.rowToResume(selection: 2, count: 3), 2)
        XCTAssertNil(Keys.rowToResume(selection: 3, count: 3), "a row the filter took away is not resumed")
        XCTAssertNil(Keys.rowToResume(selection: 0, count: 0))
        XCTAssertNil(Keys.rowToResume(selection: -1, count: 3))
    }
}
