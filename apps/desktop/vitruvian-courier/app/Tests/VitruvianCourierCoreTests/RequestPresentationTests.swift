// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import XCTest

@testable import VitruvianCourierCore

final class RequestPresentationTests: XCTestCase {
    func testPlaceholderNames() {
        for name in ["Facebook user", "facebook user", "  Instagram user ", "", "   "] {
            XCTAssertTrue(RequestPresentation.isPlaceholderName(name), name)
        }
        for name in ["Ana Silva", "Facebook User Group Admin", "Instagram"] {
            XCTAssertFalse(RequestPresentation.isPlaceholderName(name), name)
        }
    }

    func testRealNameIsKept() {
        XCTAssertEqual(RequestPresentation.title(name: "Ana Silva", networkName: "Messenger"), "Ana Silva")
    }

    func testPlaceholderFallsBackToHandleThenUnknownContact() {
        XCTAssertEqual(RequestPresentation.title(name: "Facebook user", handle: "@ana.s", networkName: "Messenger"),
                       "@ana.s")
        XCTAssertEqual(RequestPresentation.title(name: "Facebook user", networkName: "Messenger"),
                       "Unknown Messenger contact")
        XCTAssertEqual(RequestPresentation.title(name: "", networkName: ""), "Unknown contact")
    }

    func testEmptyViewsLeadSomewhereUseful() {
        func guidance(_ space: String) -> EmptyStateGuidance {
            EmptyStateGuidance.of(InboxQuery(space: space, filters: []))
        }
        for space in ["send_later", "reminders", "archive", "low_priority"] {
            XCTAssertEqual(guidance(space).actions, [.goToInbox], space)
        }
        XCTAssertNotNil(guidance("send_later").howTo)
        XCTAssertNil(guidance("archive").howTo)
        XCTAssertEqual(guidance("inbox").actions, [])
        XCTAssertEqual(EmptyStateGuidance.of(InboxQuery(space: "inbox", filters: [.archived])).actions, [.goToInbox])
    }
}
