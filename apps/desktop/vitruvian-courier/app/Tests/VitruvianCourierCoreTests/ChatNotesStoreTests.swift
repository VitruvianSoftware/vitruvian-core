// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import XCTest

@testable import VitruvianCourierCore

final class ChatNotesStoreTests: XCTestCase {
    private func defaults() throws -> (UserDefaults, () -> Void) {
        let name = "courier.test.chatnotes.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(ScratchDefaults.suite(named: name))
        return (defaults, { defaults.removePersistentDomain(forName: name) })
    }

    func testANoteIsKeptPerChatAndSurvivesARestart() throws {
        let (defaults, cleanup) = try defaults()
        defer { cleanup() }
        let store = ChatNotesStore(defaults: defaults)
        XCTAssertEqual(store.note(for: "!a"), "")

        store.setNote("Birthday is 4 May\nAllergic to nuts", for: "!a")
        store.setNote("Landlord", for: "!b")
        XCTAssertEqual(store.note(for: "!a"), "Birthday is 4 May\nAllergic to nuts")
        XCTAssertEqual(store.note(for: "!b"), "Landlord")
        XCTAssertTrue(store.hasNote(for: "!a"))

        let afterRestart = ChatNotesStore(defaults: defaults)
        XCTAssertEqual(afterRestart.note(for: "!a"), "Birthday is 4 May\nAllergic to nuts")
    }

    func testClearingANoteRemovesIt() throws {
        let (defaults, cleanup) = try defaults()
        defer { cleanup() }
        let store = ChatNotesStore(defaults: defaults)
        store.setNote("keep", for: "!a")
        store.setNote("  \n ", for: "!a")
        XCTAssertEqual(store.note(for: "!a"), "")
        XCTAssertFalse(store.hasNote(for: "!a"))
        XCTAssertNil((defaults.dictionary(forKey: ChatNotesStore.defaultsKey) as? [String: String])?["!a"])
        store.setNote("no chat", for: "")
        XCTAssertEqual(store.note(for: ""), "")
    }
}
