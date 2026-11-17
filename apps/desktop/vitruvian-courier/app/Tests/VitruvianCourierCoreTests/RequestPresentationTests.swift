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
        XCTAssertEqual(RequestPresentation.title(name: "Facebook user", handle: "   ", networkName: "Messenger"),
                       "Unknown Messenger contact")
        XCTAssertEqual(RequestPresentation.title(name: "Facebook user", networkName: "Messenger"),
                       "Unknown Messenger contact")
        XCTAssertEqual(RequestPresentation.title(name: "   ", networkName: "  Instagram  "),
                       "Unknown Instagram contact")
        XCTAssertEqual(RequestPresentation.title(name: "", networkName: ""), "Unknown contact")
    }

    func testAllKnownNetworkPlaceholdersAreRecognised() {
        let placeholders = [
            "WhatsApp user", "Telegram user", "Signal user", "Messenger user",
            "LinkedIn user", "Twitter user", "X user", "TikTok user",
            "LINE user", "Discord user", "Slack user", "Unknown user", "unknown",
        ]
        for placeholder in placeholders {
            XCTAssertTrue(RequestPresentation.isPlaceholderName(placeholder), placeholder)
        }
    }

    func testEmptyViewsLeadSomewhereUseful() {
        func guidance(_ space: String, filters: Set<InboxFilter> = []) -> EmptyStateGuidance {
            EmptyStateGuidance.of(InboxQuery(space: space, filters: filters))
        }
        for space in ["send_later", "reminders", "archive", "low_priority"] {
            XCTAssertEqual(guidance(space).actions, [.goToInbox], space)
        }
        for filter: InboxFilter in [.sendLater, .reminders, .archived, .lowPriority] {
            XCTAssertEqual(guidance("inbox", filters: [filter]).actions, [.goToInbox], filter.rawValue)
            XCTAssertEqual(guidance("inbox", filters: [.unread, filter]).actions, [.goToInbox], filter.rawValue)
        }
        XCTAssertEqual(guidance("send_later").howTo, "Right-click Send, or choose Send Later from the + menu.")
        XCTAssertEqual(guidance("inbox", filters: [.sendLater]).howTo,
                       "Right-click Send, or choose Send Later from the + menu.")
        for space in ["reminders", "archive", "low_priority", "inbox", "requests", "label:1", "account:whatsapp"] {
            XCTAssertNil(guidance(space).howTo, space)
        }
        for space in ["inbox", "requests", "label:1", "account:whatsapp"] {
            XCTAssertEqual(guidance(space).actions, [], space)
        }
        for filter: InboxFilter in [.unread, .drafts, .requests, .hidden, .muted] {
            XCTAssertEqual(guidance("inbox", filters: [filter]).actions, [], filter.rawValue)
        }
    }
}
