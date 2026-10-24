// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import XCTest

@testable import CourierCore

/// The composer's settings, in a suite-named UserDefaults of the test's own (never the real one).
final class ComposerPreferencesTests: XCTestCase {
    private var store: TestDefaults!

    override func setUp() {
        store = TestDefaults()
    }

    override func tearDown() {
        store.remove()
    }

    func testDefaultsMatchTheInventory() {
        let preferences = ComposerPreferences(defaults: store.defaults)
        XCTAssertEqual(preferences.undoSendMillis, 0, "undo send is off until it is chosen")
        XCTAssertFalse(preferences.clickPendingToUndo)
        XCTAssertEqual(preferences.upArrow, .focusMessages)
        XCTAssertTrue(preferences.showFormattingMenu)
        XCTAssertEqual(preferences.sendLaterDefault, .ifNoReply)
        XCTAssertEqual(preferences.doubleClickMessage, .reply)
        XCTAssertEqual(preferences.quickReaction, "❤️")
        XCTAssertFalse(preferences.copyWithTimestamps)
        XCTAssertFalse(preferences.hideDeletedMessages)
        // 02 §1.2 and §1.3: Incognito mode off, Show recipients I'm typing on, Show incognito mode indicator on.
        XCTAssertFalse(preferences.incognito)
        XCTAssertTrue(preferences.showTyping)
        XCTAssertTrue(preferences.showIncognitoMark)
        XCTAssertTrue(store.defaults.dictionaryRepresentation().keys.filter { $0.hasPrefix("courier.") }.isEmpty,
                      "reading the defaults writes nothing")

        XCTAssertEqual(ComposerPreferences.undoSendValues, [0, 750, 1000, 2000, 3000, 5000, 10000])
        XCTAssertEqual(ComposerPreferences.undoSendValues, SendParams.holdValues, "the windows the engine takes")
        XCTAssertEqual(MessageDoubleClickAction.allCases,
                       [.reply, .nothing, .reactionPicker, .forward, .menu, .reactWith])
        XCTAssertEqual(SendLaterCondition.ifNoReply.rawValue, "if_no_reply")
        XCTAssertEqual(SendLaterCondition.allCases.map(\.wire), ScheduleCondition.known)
    }

    func testValuesPersistUnderTheirKeys() {
        let preferences = ComposerPreferences(defaults: store.defaults)
        preferences.undoSendMillis = 5000
        preferences.clickPendingToUndo = true
        preferences.upArrow = .editLast
        preferences.showFormattingMenu = false
        preferences.sendLaterDefault = .always
        preferences.doubleClickMessage = .reactWith
        preferences.quickReaction = "👍"
        preferences.copyWithTimestamps = true
        preferences.hideDeletedMessages = true
        preferences.incognito = true
        preferences.showTyping = false
        preferences.showIncognitoMark = false
        XCTAssertEqual(store.defaults.object(forKey: "courier.composer.incognito") as? Bool, true)
        XCTAssertEqual(store.defaults.object(forKey: "courier.composer.showTyping") as? Bool, false)
        XCTAssertEqual(store.defaults.object(forKey: "courier.composer.showIncognitoMark") as? Bool, false)
        XCTAssertEqual(store.defaults.integer(forKey: "courier.composer.undoSendMillis"), 5000)
        XCTAssertEqual(store.defaults.string(forKey: "courier.composer.upArrow"), "editLast")

        let again = ComposerPreferences(defaults: store.defaults)
        XCTAssertEqual(again.undoSendMillis, 5000)
        XCTAssertTrue(again.clickPendingToUndo)
        XCTAssertEqual(again.upArrow, .editLast)
        XCTAssertFalse(again.showFormattingMenu)
        XCTAssertEqual(again.sendLaterDefault, .always)
        XCTAssertEqual(again.doubleClickMessage, .reactWith)
        XCTAssertEqual(again.quickReaction, "👍")
        XCTAssertTrue(again.copyWithTimestamps)
        XCTAssertTrue(again.hideDeletedMessages)
        XCTAssertTrue(again.incognito)
        XCTAssertFalse(again.showTyping)
        XCTAssertFalse(again.showIncognitoMark)

        // A window the engine wouldn't take reads as off, never as something else.
        store.defaults.set(1234, forKey: "courier.composer.undoSendMillis")
        XCTAssertEqual(ComposerPreferences(defaults: store.defaults).undoSendMillis, 0)
        store.defaults.set("", forKey: "courier.composer.quickReaction")
        XCTAssertEqual(ComposerPreferences(defaults: store.defaults).quickReaction, "❤️")
    }
}
