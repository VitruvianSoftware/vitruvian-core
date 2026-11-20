// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import XCTest

@testable import VitruvianCourierCore

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
        XCTAssertTrue(preferences.enableEmojiAutocomplete)
        XCTAssertFalse(preferences.disableEmoticonReplacement)
        XCTAssertFalse(preferences.autoSendGIFs)
        XCTAssertEqual(preferences.timelineEngine, .table)
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
        preferences.enableEmojiAutocomplete = false
        preferences.disableEmoticonReplacement = true
        preferences.autoSendGIFs = true
        XCTAssertEqual(store.defaults.object(forKey: "courier.composer.incognito") as? Bool, true)
        XCTAssertEqual(store.defaults.object(forKey: "courier.composer.showTyping") as? Bool, false)
        XCTAssertEqual(store.defaults.object(forKey: "courier.composer.showIncognitoMark") as? Bool, false)
        XCTAssertEqual(store.defaults.object(forKey: "courier.composer.enableEmojiAutocomplete") as? Bool, false)
        XCTAssertEqual(store.defaults.object(forKey: "courier.composer.disableEmoticonReplacement") as? Bool, true)
        XCTAssertEqual(store.defaults.object(forKey: "courier.composer.autoSendGIFs") as? Bool, true)
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
        XCTAssertFalse(again.enableEmojiAutocomplete)
        XCTAssertTrue(again.disableEmoticonReplacement)
        XCTAssertTrue(again.autoSendGIFs)

        // A window the engine wouldn't take reads as off, never as something else.
        store.defaults.set(1234, forKey: "courier.composer.undoSendMillis")
        XCTAssertEqual(ComposerPreferences(defaults: store.defaults).undoSendMillis, 0)
        store.defaults.set("", forKey: "courier.composer.quickReaction")
        XCTAssertEqual(ComposerPreferences(defaults: store.defaults).quickReaction, "❤️")
    }

    func testPrimarySecondaryComposerButtonsAndTimeFormatPersistence() {
        let preferences = ComposerPreferences(defaults: store.defaults)
        XCTAssertEqual(preferences.primaryComposerButton, .emojiPicker)
        XCTAssertEqual(preferences.secondaryComposerButton, .none)
        XCTAssertEqual(preferences.timeFormat, .system)
        XCTAssertTrue(preferences.showMessageTimestamps)
        XCTAssertTrue(preferences.enableSpellcheck)

        preferences.primaryComposerButton = .sendLater
        preferences.secondaryComposerButton = .emojiPicker
        preferences.timeFormat = .twentyFourHour
        preferences.showMessageTimestamps = false
        preferences.enableSpellcheck = false

        XCTAssertEqual(store.defaults.string(forKey: "courier.composer.primaryComposerButton"), "sendLater")
        XCTAssertEqual(store.defaults.string(forKey: "courier.composer.secondaryComposerButton"), "emojiPicker")
        XCTAssertEqual(store.defaults.string(forKey: "courier.composer.timeFormat"), "twentyFourHour")

        let reloaded = ComposerPreferences(defaults: store.defaults)
        XCTAssertEqual(reloaded.primaryComposerButton, .sendLater)
        XCTAssertEqual(reloaded.secondaryComposerButton, .emojiPicker)
        XCTAssertEqual(reloaded.timeFormat, .twentyFourHour)
        XCTAssertFalse(reloaded.showMessageTimestamps)
        XCTAssertFalse(reloaded.enableSpellcheck)
    }

    func testDefaultVisibleControlsAndPlusMenuFallbacks() {
        let preferences = ComposerPreferences(defaults: store.defaults)
        XCTAssertEqual(preferences.primaryComposerButton, .emojiPicker)
        XCTAssertEqual(preferences.secondaryComposerButton, .none)
        XCTAssertEqual(preferences.visibleControlIDs(), ["plus", "emojiPicker", "send"])
        XCTAssertTrue(preferences.showsSendLaterInPlusMenu)

        preferences.primaryComposerButton = .none
        XCTAssertTrue(preferences.showsSendLaterInPlusMenu)

        preferences.secondaryComposerButton = .sendLater
        XCTAssertFalse(preferences.showsSendLaterInPlusMenu)
        XCTAssertEqual(preferences.visibleControlIDs(), ["plus", "sendLater", "send"])
        XCTAssertEqual(preferences.visibleControlIDs(isEditing: true), ["plus", "send"])
    }

    func testSavedButtonPreferencesAreNeverOverwrittenOnInit() {
        store.defaults.set("emojiPicker", forKey: "courier.composer.primaryComposerButton")
        store.defaults.set("sendLater", forKey: "courier.composer.secondaryComposerButton")

        let preferences = ComposerPreferences(defaults: store.defaults)
        XCTAssertEqual(preferences.primaryComposerButton, .emojiPicker)
        XCTAssertEqual(preferences.secondaryComposerButton, .sendLater)
        XCTAssertEqual(store.defaults.string(forKey: "courier.composer.primaryComposerButton"), "emojiPicker")
        XCTAssertEqual(store.defaults.string(forKey: "courier.composer.secondaryComposerButton"), "sendLater")
    }

    func testLegacyComposerButtonsMigrateToNoneOnLoad() {
        XCTAssertEqual(PrimaryComposerButton.allCases, [.emojiPicker, .sendLater, .none])
        XCTAssertEqual(SecondaryComposerButton.allCases, [.emojiPicker, .sendLater, .none])

        for legacyRawValue in ["gifPicker", "addAttachment", "recordAudio"] {
            let testStore = TestDefaults()
            defer { testStore.remove() }
            testStore.defaults.set(legacyRawValue, forKey: "courier.composer.primaryComposerButton")
            testStore.defaults.set(legacyRawValue, forKey: "courier.composer.secondaryComposerButton")

            let preferences = ComposerPreferences(defaults: testStore.defaults)
            XCTAssertEqual(preferences.primaryComposerButton, .none, "\(legacyRawValue) must migrate primary to .none")
            XCTAssertEqual(preferences.secondaryComposerButton, .none, "\(legacyRawValue) must migrate secondary to .none")
            XCTAssertEqual(testStore.defaults.string(forKey: "courier.composer.primaryComposerButton"), "none")
            XCTAssertEqual(testStore.defaults.string(forKey: "courier.composer.secondaryComposerButton"), "none")
        }
    }

    func testDuplicateSecondaryComposerButtonIsTreatedAsNoneAndOmittedFromPickers() {
        let preferences = ComposerPreferences(defaults: store.defaults)
        preferences.primaryComposerButton = .emojiPicker
        preferences.secondaryComposerButton = .emojiPicker

        XCTAssertEqual(preferences.effectiveSecondaryComposerButton, .none)
        XCTAssertEqual(preferences.visibleControlIDs(), ["plus", "emojiPicker", "send"])
        XCTAssertEqual(preferences.availableSecondaryComposerButtons, [.sendLater, .none])
        XCTAssertEqual(preferences.availablePrimaryComposerButtons, [.emojiPicker, .sendLater, .none])

        let duplicateStore = TestDefaults()
        defer { duplicateStore.remove() }
        duplicateStore.defaults.set("emojiPicker", forKey: "courier.composer.primaryComposerButton")
        duplicateStore.defaults.set("emojiPicker", forKey: "courier.composer.secondaryComposerButton")
        let reloaded = ComposerPreferences(defaults: duplicateStore.defaults)
        XCTAssertEqual(reloaded.effectiveSecondaryComposerButton, .none)
        XCTAssertEqual(reloaded.visibleControlIDs(), ["plus", "emojiPicker", "send"])
        XCTAssertEqual(reloaded.availableSecondaryComposerButtons, [.sendLater, .none])

        preferences.primaryComposerButton = .sendLater
        preferences.secondaryComposerButton = .sendLater
        XCTAssertEqual(preferences.effectiveSecondaryComposerButton, .none)
        XCTAssertEqual(preferences.visibleControlIDs(), ["plus", "sendLater", "send"])
        XCTAssertFalse(preferences.showsSendLaterInPlusMenu)

        preferences.primaryComposerButton = .emojiPicker
        preferences.secondaryComposerButton = .sendLater
        XCTAssertEqual(preferences.effectiveSecondaryComposerButton, .sendLater)
        XCTAssertEqual(preferences.availablePrimaryComposerButtons, [.emojiPicker, .none])
        XCTAssertEqual(preferences.availableSecondaryComposerButtons, [.sendLater, .none])

        preferences.primaryComposerButton = .none
        preferences.secondaryComposerButton = .none
        XCTAssertEqual(preferences.availablePrimaryComposerButtons, [.emojiPicker, .sendLater, .none])
        XCTAssertEqual(preferences.availableSecondaryComposerButtons, [.emojiPicker, .sendLater, .none])
    }

    func testTimelineEngineHiddenPreferencePersistsAndReadsLegacyKey() {
        let preferences = ComposerPreferences(defaults: store.defaults)
        XCTAssertEqual(preferences.timelineEngine, .table)

        preferences.timelineEngine = .swiftui
        XCTAssertEqual(store.defaults.string(forKey: "courier.composer.timelineEngine"), "swiftui")
        XCTAssertEqual(ComposerPreferences(defaults: store.defaults).timelineEngine, .swiftui)

        let unprefixed = TestDefaults()
        defer { unprefixed.remove() }
        unprefixed.defaults.set("swiftui", forKey: "timelineEngine")
        XCTAssertEqual(ComposerPreferences(defaults: unprefixed.defaults).timelineEngine, .swiftui)

        unprefixed.defaults.set("TABLE", forKey: "timelineEngine")
        XCTAssertEqual(ComposerPreferences(defaults: unprefixed.defaults).timelineEngine, .table)

        unprefixed.defaults.set("unknown", forKey: "timelineEngine")
        XCTAssertEqual(ComposerPreferences(defaults: unprefixed.defaults).timelineEngine, .table)
    }
}
