// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import XCTest

@testable import VitruvianCourierCore

/// The emoji picker's content, skin tones and "Frequently used" memory.
final class EmojiPickerTests: XCTestCase {
    private func store(_ now: @escaping @Sendable () -> Date = Date.init) -> (EmojiUsageStore, TestDefaults) {
        let defaults = TestDefaults()
        addTeardownBlock { defaults.remove() }
        return (EmojiUsageStore(defaults: defaults.defaults, now: now), defaults)
    }

    // MARK: Skin tones

    func testSkinToneGoesAfterTheFirstEmojiOfAHandOrPerson() {
        XCTAssertEqual(EmojiSkinTone.apply(.medium, to: "👍"), "👍🏽")
        XCTAssertEqual(EmojiSkinTone.apply(.dark, to: "🙏"), "🙏🏿")
        XCTAssertEqual(EmojiSkinTone.apply(.light, to: "👋"), "👋🏻")
        // The emoji presentation selector (FE0F) of ✌️ gives way to the tone.
        XCTAssertEqual(EmojiSkinTone.apply(.mediumLight, to: "✌️"), "✌🏼")
        // A sequence keeps what follows the base.
        XCTAssertEqual(EmojiSkinTone.apply(.dark, to: "🤷\u{200D}\u{2640}\u{FE0F}"), "🤷🏿\u{200D}\u{2640}\u{FE0F}")
    }

    func testSkinToneLeavesWhatCannotTakeOneAlone() {
        for glyph in ["😀", "❤️", "🔥", "🎉"] {
            XCTAssertFalse(EmojiSkinTone.supports(glyph), glyph)
            XCTAssertEqual(EmojiSkinTone.apply(.dark, to: glyph), glyph)
        }
        XCTAssertEqual(EmojiSkinTone.apply(.none, to: "👍"), "👍")
        XCTAssertEqual(EmojiSkinTone.apply(.dark, to: "👍🏻"), "👍🏻", "one that has a tone already keeps it")
        XCTAssertNil(EmojiSkinTone.none.modifier)
        XCTAssertEqual(EmojiSkinTone.dark.modifier?.value, 0x1F3FF)
        XCTAssertEqual(EmojiSkinTone.allCases.count, 6)
    }

    // MARK: Frequently used

    func testFrequentlyUsedIsMostUsedFirstThenMostRecent() {
        nonisolated(unsafe) var clock = Date(timeIntervalSince1970: 1_000)
        let (usage, _) = store { clock }
        XCTAssertEqual(usage.frequent(), [])
        usage.record("😂")
        clock += 10
        usage.record("👍")
        clock += 10
        usage.record("👍")
        clock += 10
        usage.record("🎉")
        // 👍 twice; then 🎉 and 😂 once each, the later use first.
        XCTAssertEqual(usage.frequent(), ["👍", "🎉", "😂"])
        XCTAssertEqual(usage.frequent(limit: 2), ["👍", "🎉"])
    }

    func testUsageIsKeptOnThisMacBetweenLaunches() {
        let (usage, defaults) = store()
        usage.record("🔥")
        usage.record("🔥")
        usage.skinTone = .mediumDark
        let relaunched = EmojiUsageStore(defaults: defaults.defaults)
        XCTAssertEqual(relaunched.frequent(), ["🔥"])
        XCTAssertEqual(relaunched.skinTone, .mediumDark)
        relaunched.clear()
        XCTAssertEqual(EmojiUsageStore(defaults: defaults.defaults).frequent(), [])
        XCTAssertEqual(EmojiUsageStore(defaults: defaults.defaults).skinTone, .mediumDark, "clearing counts keeps the tone")
    }

    func testOnlyTheMostUsedAreRemembered() {
        let (usage, _) = store()
        for index in 0..<(EmojiUsageStore.maximumRemembered + 30) {
            usage.record("e\(index)")
        }
        usage.record("keeper")
        usage.record("keeper")
        XCTAssertLessThanOrEqual(usage.frequent(limit: 500).count, EmojiUsageStore.maximumRemembered)
        XCTAssertEqual(usage.frequent(limit: 1), ["keeper"])
        usage.record("")
        XCTAssertFalse(usage.frequent(limit: 500).contains(""))
    }

    // MARK: What the picker shows

    func testWithNoSearchItShowsFrequentlyUsedThenEveryCategory() {
        let sections = EmojiPickerContent.sections(query: "", tone: .none, frequent: ["🎉", "👍"])
        XCTAssertEqual(sections.map(\.id), [EmojiPickerContent.frequentSectionID] + EmojiCategory.allCases.map(\.id))
        XCTAssertEqual(sections.first?.items.map(\.glyph), ["🎉", "👍"])
        XCTAssertNil(sections.first?.category)
        for section in sections.dropFirst() {
            XCTAssertFalse(section.items.isEmpty, section.title)
            XCTAssertNotNil(section.category)
        }
    }

    func testFrequentlyUsedIsLeftOutUntilSomethingWasChosen() {
        let sections = EmojiPickerContent.sections(query: "  ", tone: .none, frequent: [])
        XCTAssertEqual(sections.map(\.id), EmojiCategory.allCases.map(\.id))
    }

    func testTheSameEmojiIsNeverShownTwiceInASection() {
        let sections = EmojiPickerContent.sections(query: "", tone: .none, frequent: [])
        for section in sections {
            let glyphs = section.items.map(\.glyph)
            XCTAssertEqual(glyphs.count, Set(glyphs).count, "\(section.title) repeats an emoji (thumbsup and +1 are both 👍)")
        }
    }

    func testEverySectionTakesTheChosenSkinTone() {
        let sections = EmojiPickerContent.sections(query: "", tone: .dark, frequent: [])
        let hands = sections.first { $0.category == .hands }
        XCTAssertTrue(hands?.items.contains { $0.glyph == "👍🏿" } == true)
        XCTAssertFalse(hands?.items.contains { $0.glyph == "👍" } == true)
        let smileys = sections.first { $0.category == .smileys }
        XCTAssertTrue(smileys?.items.contains { $0.glyph == "😀" } == true, "a face has no tone")
    }

    func testSearchFindsByNameAndByKeywordInOneResultsSection() {
        let byName = EmojiPickerContent.sections(query: "thumbsup", tone: .none, frequent: ["🎉"])
        XCTAssertEqual(byName.map(\.id), [EmojiPickerContent.resultsSectionID], "no Frequently used while searching")
        XCTAssertEqual(byName.first?.items.first?.glyph, "👍")
        XCTAssertEqual(byName.first?.items.map(\.glyph).filter { $0 == "👍" }.count, 1)

        let byKeyword = EmojiPickerContent.sections(query: "celebrate", tone: .none, frequent: [])
        XCTAssertTrue(byKeyword.first?.items.contains { $0.glyph == "🎉" } == true)

        XCTAssertEqual(EmojiPickerContent.sections(query: "zzzzzqqq", tone: .none, frequent: []), [])
    }

    func testSearchResultsTakeTheSkinToneToo() {
        let results = EmojiPickerContent.sections(query: "clap", tone: .medium, frequent: [])
        XCTAssertEqual(results.first?.items.first?.glyph, "👏🏽")
    }

    func testCategoriesPartitionTheBuiltInCatalog() {
        let catalog = EmojiCatalog.shared
        let all = EmojiCategory.allCases.flatMap { catalog.entries(in: $0) }
        XCTAssertEqual(all.map(\.shortcode), catalog.entries.map(\.shortcode), "every emoji is in exactly one category, in order")
        XCTAssertEqual(EmojiCatalog.defaultEntries.count, catalog.entries.count)
    }
}
