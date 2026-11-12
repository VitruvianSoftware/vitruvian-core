// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import XCTest

@testable import CourierCore

/// Recent searches and recent chats, kept in a UserDefaults suite of the test's own.
final class RecentSearchesTests: XCTestCase {
    private var store: TestDefaults!

    override func setUp() {
        store = TestDefaults()
    }

    override func tearDown() {
        store.remove()
    }

    func testKeepsTheNewestTenWithoutDuplicates() {
        let recents = RecentSearches(defaults: store.defaults)
        XCTAssertEqual(recents.searches, [])
        for index in 0 ..< 12 { recents.addSearch("search \(index)") }
        XCTAssertEqual(recents.searches, (2 ..< 12).reversed().map { "search \($0)" }, "the newest ten, newest first")

        recents.addSearch("search 5")
        XCTAssertEqual(recents.searches.first, "search 5")
        XCTAssertEqual(recents.searches.count, 10)
        XCTAssertEqual(recents.searches.filter { $0 == "search 5" }.count, 1, "searched again moves it up, once")

        // The same words in another case are the same search (the index folds case): the newest spelling stays.
        recents.addSearch("  SEARCH 7 ")
        XCTAssertEqual(recents.searches.first, "SEARCH 7", "kept without the spaces around it")
        XCTAssertFalse(recents.searches.contains("search 7"))
        recents.addSearch("   ")
        XCTAssertEqual(recents.searches.first, "SEARCH 7", "nothing to keep")

        XCTAssertEqual(store.defaults.stringArray(forKey: "courier.search.recentSearches"), recents.searches)
        XCTAssertEqual(RecentSearches(defaults: store.defaults).searches, recents.searches, "read back on launch")
    }

    func testClearSearches() {
        let recents = RecentSearches(defaults: store.defaults)
        recents.addSearch("picnic")
        recents.addChat("!a")
        recents.clearSearches()
        XCTAssertEqual(recents.searches, [])
        XCTAssertEqual(recents.chats, ["!a"], "Clear Recent Searches leaves the recent chats")
        XCTAssertEqual(RecentSearches(defaults: store.defaults).searches, [])
    }

    func testKeepsEightRecentChats() {
        let recents = RecentSearches(defaults: store.defaults)
        for index in 0 ..< 10 { recents.addChat("!r\(index)") }
        XCTAssertEqual(recents.chats, (2 ..< 10).reversed().map { "!r\($0)" })
        recents.addChat("!r4")
        XCTAssertEqual(recents.chats.first, "!r4")
        XCTAssertEqual(recents.chats.count, 8)
        XCTAssertEqual(Set(recents.chats).count, 8, "no chat twice")
        XCTAssertEqual(store.defaults.stringArray(forKey: "courier.search.recentChats"), recents.chats)
        XCTAssertEqual(RecentSearches(defaults: store.defaults).chats, recents.chats)
    }
}
