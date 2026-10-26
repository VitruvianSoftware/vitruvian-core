// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import XCTest

@testable import CourierCore

final class EmojiCatalogTests: XCTestCase {
    func testSearchOrdersPrefixMatchesAheadOfSubstringAndKeywordsAndMergesCustomEmoji() {
        let custom = [
            EmojiCandidate(
                id: "mxc://local.courier/custom_smile",
                shortcode: "smilodon",
                glyph: nil,
                mediaURL: "mxc://local.courier/custom_smile",
                isCustom: true,
                keywords: ["dino", "prehistoric"]
            ),
            EmojiCandidate(
                id: "mxc://local.courier/cosmic",
                shortcode: "cosmic_cat",
                glyph: nil,
                mediaURL: "mxc://local.courier/cosmic",
                isCustom: true,
                keywords: ["space"]
            ),
        ]

        let results = EmojiCatalog.shared.search("smi", custom: custom, limit: 12)
        let shortcodes = results.map(\.shortcode)

        XCTAssertTrue(shortcodes.contains("smile"))
        XCTAssertTrue(shortcodes.contains("smiley"))
        XCTAssertTrue(shortcodes.contains("smirk"))
        XCTAssertTrue(shortcodes.contains("smilodon"), "prefix custom emoji is merged")
        XCTAssertTrue(shortcodes.contains("cosmic_cat"), "substring custom emoji is merged")

        // Prefix matches ("smile", "smiley", "smirk", "smilodon") come before substring/keyword matches ("cosmic_cat", "grin").
        let lastPrefixIndex = shortcodes.enumerated()
            .filter { $0.element.hasPrefix("smi") }
            .map(\.offset)
            .max()!
        let firstNonPrefixIndex = shortcodes.enumerated()
            .filter { !$0.element.hasPrefix("smi") }
            .map(\.offset)
            .min()
        if let firstNonPrefixIndex {
            XCTAssertLessThan(lastPrefixIndex, firstNonPrefixIndex)
        }
    }

    func testReplaceTrailingEmoticon() {
        XCTAssertEqual(EmojiCatalog.replaceTrailingEmoticon(in: ":) "), "🙂 ")
        XCTAssertEqual(EmojiCatalog.replaceTrailingEmoticon(in: "hello :-) "), "hello 🙂 ")
        XCTAssertEqual(EmojiCatalog.replaceTrailingEmoticon(in: ":-D\n"), "😃\n")
        XCTAssertEqual(EmojiCatalog.replaceTrailingEmoticon(in: "love <3 "), "love ❤️ ")
        XCTAssertEqual(EmojiCatalog.replaceTrailingEmoticon(in: "heartbroken </3 "), "heartbroken 💔 ")

        // URLs and inline code spans are untouched.
        XCTAssertNil(EmojiCatalog.replaceTrailingEmoticon(in: "https://example.com/:) "))
        XCTAssertNil(EmojiCatalog.replaceTrailingEmoticon(in: "http://example.com/:D "))
        XCTAssertNil(EmojiCatalog.replaceTrailingEmoticon(in: "`:) "))
        XCTAssertNil(EmojiCatalog.replaceTrailingEmoticon(in: "check `code :) "))
        XCTAssertNil(EmojiCatalog.replaceTrailingEmoticon(in: "word:) "))
    }
}
