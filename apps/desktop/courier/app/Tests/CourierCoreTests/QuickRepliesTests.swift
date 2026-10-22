// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import XCTest

@testable import CourierCore

/// Quick replies: kept on this Mac in a suite-named UserDefaults of the test's own (never the real one). All the
/// names and words here are made up.
final class QuickRepliesTests: XCTestCase {
    private var store: TestDefaults!

    override func setUp() {
        store = TestDefaults()
    }

    override func tearDown() {
        store.remove()
    }

    func testLimitsAndPersistence() throws {
        let replies = QuickReplies(defaults: store.defaults)
        XCTAssertEqual(replies.all, [])

        try replies.add(title: "omw", text: "On my way!")
        try replies.add(title: "  Thanks  ", text: "Thank you, {first_name}.")
        XCTAssertEqual(replies.all.map(\.title), ["omw", "Thanks"], "the title is kept without the spaces around it")

        // What is refused, and why.
        XCTAssertThrowsError(try replies.add(title: "", text: "x")) { XCTAssertEqual($0 as? QuickReplyError, .emptyTitle) }
        XCTAssertThrowsError(try replies.add(title: "x", text: " \n")) { XCTAssertEqual($0 as? QuickReplyError, .emptyText) }
        XCTAssertThrowsError(try replies.add(title: String(repeating: "t", count: QuickReplies.maxTitle + 1), text: "x")) {
            XCTAssertEqual($0 as? QuickReplyError, .titleTooLong)
        }
        XCTAssertThrowsError(try replies.add(title: "long", text: String(repeating: "x", count: QuickReplies.maxText + 1))) {
            XCTAssertEqual($0 as? QuickReplyError, .textTooLong)
        }
        XCTAssertThrowsError(try replies.add(title: "OMW", text: "again")) {
            XCTAssertEqual($0 as? QuickReplyError, .duplicateTitle, "titles are found by typing them, so each is one")
        }
        try replies.add(title: String(repeating: "t", count: QuickReplies.maxTitle),
                        text: String(repeating: "x", count: QuickReplies.maxText))

        // Kept, and read back by a new instance.
        let again = QuickReplies(defaults: store.defaults)
        XCTAssertEqual(again.all, replies.all)

        // Update and remove.
        var first = again.all[0]
        first.text = "Be there in 5"
        try again.update(first)
        XCTAssertEqual(QuickReplies(defaults: store.defaults).all[0].text, "Be there in 5")
        XCTAssertThrowsError(try again.update(QuickReply(id: UUID(), title: "new", text: "x"))) {
            XCTAssertEqual($0 as? QuickReplyError, .notFound)
        }
        again.remove(first.id)
        XCTAssertEqual(QuickReplies(defaults: store.defaults).all.map(\.title).first, "Thanks")

        // At most 100.
        let other = TestDefaults()
        defer { other.remove() }
        let full = QuickReplies(defaults: other.defaults)
        for index in 0 ..< QuickReplies.maxCount { try full.add(title: "r\(index)", text: "x") }
        XCTAssertThrowsError(try full.add(title: "one more", text: "x")) { XCTAssertEqual($0 as? QuickReplyError, .full) }

        // Found by title, folding case and accents, at most 8.
        try replies.add(title: "Café", text: "Coffee?")
        XCTAssertEqual(replies.matching("cafe").map(\.title), ["Café"])
        XCTAssertEqual(replies.matching("TH").map(\.title), ["Thanks"])
        XCTAssertEqual(full.matching("r").count, 8)
        XCTAssertEqual(full.matching("").count, 8)

        // Something unreadable in the store is an empty list, never a crash, and it is never written over: it is kept
        // aside before anything new is saved.
        store.defaults.set(Data("not json".utf8), forKey: QuickReplies.key)
        let unreadable = QuickReplies(defaults: store.defaults)
        XCTAssertEqual(unreadable.all, [])
        try unreadable.add(title: "new", text: "fresh")
        XCTAssertEqual(store.defaults.data(forKey: QuickReplies.unreadableKey), Data("not json".utf8))
        XCTAssertEqual(QuickReplies(defaults: store.defaults).all.map(\.title), ["new"])
    }

    func testFillUsesTheOtherPersonsName() {
        let text = "Hi {first_name}! ({full_name}, {last_name})"
        XCTAssertEqual(QuickReplies.fill(text, otherPerson: "Ada Lovelace"), "Hi Ada! (Ada Lovelace, Lovelace)")
        XCTAssertEqual(QuickReplies.fill(text, otherPerson: "Mary Ann Example"),
                       "Hi Mary! (Mary Ann Example, Example)", "the last name is the last word")
        XCTAssertEqual(QuickReplies.fill("Hi {first_name} {last_name}.", otherPerson: "Cher"), "Hi Cher .",
                       "one name: no last name")
        XCTAssertEqual(QuickReplies.fill(text, otherPerson: "  Ada   Lovelace "), "Hi Ada! (Ada Lovelace, Lovelace)")
    }

    func testUnknownVariablesStay() {
        XCTAssertEqual(QuickReplies.fill("See you {day}, {first_name}", otherPerson: "Ada Lovelace"),
                       "See you {day}, Ada", "a variable 4.3 doesn't fill stays as typed")
        XCTAssertEqual(QuickReplies.fill("Hi {first_name}", otherPerson: nil), "Hi {first_name}",
                       "a group chat has no one other person")
        XCTAssertEqual(QuickReplies.fill("Hi {first_name}", otherPerson: "  "), "Hi {first_name}")
        XCTAssertEqual(QuickReplies.fill("{FIRST_NAME} {first_name", otherPerson: "Ada"), "{FIRST_NAME} {first_name",
                       "only the exact names, closed")
    }
}
