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
/// `QuickPromptView`, removed in step 3c; see git history before
/// `b14d76b54`). The view only calls these rules, so they are tested here
/// without one.
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

    // MARK: The pill's prompt gives up its arrows only while it is empty

    func testAnArrowInAnEmptyPromptMovesTheSelection() {
        XCTAssertTrue(Keys.arrowMovesSelection(in: .prompt(""), hasModifiers: false, count: 3))
    }

    /// Up and down in a typed prompt are the caret's. A row selected there
    /// would make the next Return open a conversation instead of sending.
    func testAnArrowInATypedPromptIsLeftToTheTextField() {
        XCTAssertFalse(Keys.arrowMovesSelection(in: .prompt("fix the build"), hasModifiers: false, count: 3))
        XCTAssertFalse(Keys.arrowMovesSelection(in: .prompt(" "), hasModifiers: false, count: 3),
                       "a space is text too, as it is for the follow-up bar's history")
    }

    func testTheFilterAlwaysGivesTheListItsArrows() {
        XCTAssertTrue(Keys.arrowMovesSelection(in: .filter, hasModifiers: false, count: 3))
    }

    /// Shift, Option and Command with an arrow select text or move the
    /// caret by a word or to an end: never the list's, in either field.
    func testAnArrowWithAModifierIsNeverTheLists() {
        XCTAssertFalse(Keys.arrowMovesSelection(in: .prompt(""), hasModifiers: true, count: 3))
        XCTAssertFalse(Keys.arrowMovesSelection(in: .filter, hasModifiers: true, count: 3))
    }

    func testAnArrowWithNoRowsIsLeftToTheField() {
        XCTAssertFalse(Keys.arrowMovesSelection(in: .prompt(""), hasModifiers: false, count: 0))
        XCTAssertFalse(Keys.arrowMovesSelection(in: .filter, hasModifiers: false, count: 0))
    }

    func testReturnInAnEmptyPromptResumesTheSelectedRow() {
        XCTAssertEqual(Keys.rowToResume(from: .prompt(""), selection: 1, count: 3), 1)
        XCTAssertNil(Keys.rowToResume(from: .prompt(""), selection: nil, count: 3))
        XCTAssertNil(Keys.rowToResume(from: .prompt(""), selection: 3, count: 3), "a row that is not there")
    }

    /// A selection can outlive its moment: made from the filter, say, and
    /// then a prompt is typed. Return sends the prompt.
    func testReturnInATypedPromptSendsWhateverIsSelected() {
        XCTAssertNil(Keys.rowToResume(from: .prompt("fix the build"), selection: 1, count: 3))
        XCTAssertNil(Keys.rowToResume(from: .prompt(" "), selection: 0, count: 3))
    }

    func testReturnInTheFilterResumesTheSelectedRow() {
        XCTAssertEqual(Keys.rowToResume(from: .filter, selection: 2, count: 3), 2)
        XCTAssertNil(Keys.rowToResume(from: .filter, selection: nil, count: 3))
        XCTAssertNil(Keys.rowToResume(from: .filter, selection: 3, count: 3))
    }
}

/// The two clicks of Clear All, which deletes every conversation of a folder
/// and cannot be undone. The guard is a matter of time alone: a first click
/// that was not followed up stops counting after two seconds whether or not
/// anything ran in between to say so.
final class ClearAllGuardTests: XCTestCase {
    private typealias Guard = NexusAgentClearAllGuard
    private let first = Date(timeIntervalSinceReferenceDate: 1_000)

    func testOneClickNeverDeletes() {
        XCTAssertEqual(Guard.click(firstClick: nil, now: first), .arm(first))
        XCTAssertFalse(Guard.isArmed(firstClick: nil, now: first), "before any click the button is its name")
        XCTAssertTrue(Guard.isArmed(firstClick: first, now: first), "after one it asks")
    }

    func testASecondClickInTimeDeletes() {
        XCTAssertTrue(Guard.isArmed(firstClick: first, now: first.addingTimeInterval(1.9)))
        XCTAssertEqual(Guard.click(firstClick: first, now: first.addingTimeInterval(1.9)), .delete)
        XCTAssertEqual(Guard.click(firstClick: first, now: first), .delete, "a double click")
    }

    /// The case that used to delete: the question was never taken back
    /// because the task that would have done it was cancelled.
    func testASecondClickTooLateArmsAgainInsteadOfDeleting() {
        let late = first.addingTimeInterval(2.1)
        XCTAssertFalse(Guard.isArmed(firstClick: first, now: late), "the button is back to its name")
        XCTAssertEqual(Guard.click(firstClick: first, now: late), .arm(late))
        XCTAssertFalse(Guard.isArmed(firstClick: first, now: first.addingTimeInterval(2)), "two seconds is too late")

        let minutesLater = first.addingTimeInterval(600)
        XCTAssertFalse(Guard.isArmed(firstClick: first, now: minutesLater))
        XCTAssertEqual(Guard.click(firstClick: first, now: minutesLater), .arm(minutesLater),
                       "however long the first click was left lying, the next one only asks")
    }

    /// After a reset (the view forgets the first click when the button
    /// goes, the filter or provider changes, or the drawer closes) one
    /// click deletes nothing, even inside the two seconds.
    func testAfterAResetOneClickDeletesNothing() {
        let soon = first.addingTimeInterval(0.5)
        XCTAssertFalse(Guard.isArmed(firstClick: nil, now: soon))
        XCTAssertEqual(Guard.click(firstClick: nil, now: soon), .arm(soon))
    }

    /// After a delete the view forgets the first click, and after a late
    /// click it keeps the new time: either way two more are needed.
    func testEveryDeleteTakesTwoClicksOfItsOwn() {
        let rearmed = first.addingTimeInterval(5)
        XCTAssertEqual(Guard.click(firstClick: first, now: rearmed), .arm(rearmed))
        XCTAssertEqual(Guard.click(firstClick: rearmed, now: rearmed.addingTimeInterval(1)), .delete)
        XCTAssertEqual(Guard.click(firstClick: nil, now: rearmed.addingTimeInterval(1.5)),
                       .arm(rearmed.addingTimeInterval(1.5)))
    }

    func testAFirstClickLaterThanNowDoesNotCount() {
        let before = first.addingTimeInterval(-30)
        XCTAssertFalse(Guard.isArmed(firstClick: first, now: before), "the clock was set back")
        XCTAssertEqual(Guard.click(firstClick: first, now: before), .arm(before))
    }

    func testTheWindowIsTheStandalonesTwoSeconds() {
        XCTAssertEqual(Guard.window, 2)
    }
}
