// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import XCTest

@testable import VitruvianCourierCore

/// Whatever is typed or pasted, what the converter hands on to be sent holds together: every range is inside the text
/// (in UTF-16 units, emoji included), nothing the engine would drop is left in, and a saved draft comes back without
/// crashing. The inputs are made up, from a fixed seed, so a failure repeats.
final class MarkdownConversionSafetyTests: XCTestCase {
    private struct Generator: RandomNumberGenerator {
        var state: UInt64
        mutating func next() -> UInt64 {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return state ^ (state >> 29)
        }
    }

    private let pieces = [
        "*", "**", "_", "~~", "`", "```", "\\", "a", "bc", " ", "\n", "😀", "👍🏽", "é", "@", "@x", "https://a.example/_p_",
        "www.a.example", "1", "__",
    ]

    func testConvertedRangesStayInsideTheTextAndAreAlreadyFitted() throws {
        var random = Generator(state: 0x5EED)
        for _ in 0 ..< 4000 {
            let count = Int.random(in: 1 ... 14, using: &random)
            let text = (0 ..< count).map { _ in pieces.randomElement(using: &random)! }.joined()
            let length = (text as NSString).length
            guard let result = MarkdownConverter.convertAll(text: text) else { continue }
            let out = result.text as NSString
            XCTAssertLessThan(out.length, length, "a conversion takes markers out: \(text.debugDescription)")
            for entity in result.entities {
                XCTAssertGreaterThanOrEqual(entity.offset, 0, text.debugDescription)
                XCTAssertGreaterThan(entity.length, 0, text.debugDescription)
                XCTAssertLessThanOrEqual(entity.offset + entity.length, out.length, text.debugDescription)
                // Never a range that starts or ends inside an emoji.
                for edge in [entity.offset, entity.offset + entity.length] where edge > 0 && edge < out.length {
                    let high = out.character(at: edge - 1)
                    XCTAssertFalse((0xD800 ..< 0xDC00).contains(high) && (0xDC00 ..< 0xE000).contains(out.character(at: edge)),
                                   "range splits a surrogate pair: \(text.debugDescription)")
                }
            }
            XCTAssertEqual(EntityEditing.fitted(result.entities, to: out), result.entities,
                           "the engine would change these ranges: \(text.debugDescription)")
        }
    }

    func testSavedDraftsComeBackWithoutBadRanges() {
        var random = Generator(state: 0xD2AF7)
        for _ in 0 ..< 2000 {
            let count = Int.random(in: 1 ... 14, using: &random)
            let text = (0 ..< count).map { _ in pieces.randomElement(using: &random)! }.joined()
            let restored = MarkdownConverter.restoredDraft(text)
            let length = (restored.text as NSString).length
            for entity in restored.entities {
                XCTAssertTrue(entity.offset >= 0 && entity.length > 0 && entity.offset + entity.length <= length,
                              text.debugDescription)
            }
            // And writing them out again must not crash or send a range out of the text.
            let again = MarkdownConverter.restoredDraft(MarkdownConverter.markdown(text: restored.text, entities: restored.entities))
            let againLength = (again.text as NSString).length
            for entity in again.entities {
                XCTAssertTrue(entity.offset >= 0 && entity.length > 0 && entity.offset + entity.length <= againLength,
                              text.debugDescription)
            }
        }
    }
}
