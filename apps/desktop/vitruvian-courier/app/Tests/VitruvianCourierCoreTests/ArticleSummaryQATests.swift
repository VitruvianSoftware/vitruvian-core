// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation
import XCTest

@testable import VitruvianCourierCore

// QA checks on the same-story gate: only a clear YES lets another site's page become "the summary".
final class ArticleSummaryQATests: XCTestCase {
    func testAnAnswerThatOnlyStartsWithTheLettersYesIsNotAYes() {
        XCTAssertNotEqual(AIPrompts.parseYesNo("Yesterday's report covers a different event"), true)
        XCTAssertNotEqual(AIPrompts.parseYesNo("YESNO"), true)
    }

    func testAClearYesStillPasses() {
        for answer in ["YES", "yes", "Yes.", "**YES**", "Yes, same event"] {
            XCTAssertEqual(AIPrompts.parseYesNo(answer), true, answer)
        }
    }

    func testAnythingThatIsNotAClearYesIsNeverTheSameStory() {
        for answer in ["No", "NO.", "Not sure", "Nope", "Maybe", "", "I cannot tell", "The stories differ"] {
            XCTAssertNotEqual(AIPrompts.parseYesNo(answer), true, answer)
        }
    }
}
