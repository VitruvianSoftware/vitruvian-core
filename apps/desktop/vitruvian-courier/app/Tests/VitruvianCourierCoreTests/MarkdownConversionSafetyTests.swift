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

    /// Every range of `back` lies inside a range of the same kind in `original`: nothing is invented or moved.
    private static func only(_ back: [TextEntity], from original: [TextEntity]) -> Bool {
        back.allSatisfy { entity in
            (entity.offset ..< entity.offset + entity.length).allSatisfy { position in
                original.contains { $0.kind == entity.kind && $0.offset <= position && position < $0.offset + $0.length }
            }
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

    /// A saved draft comes back the same, however often it is saved and opened again: the first opening is what the box
    /// holds, and from then on save then open changes nothing (a pathological `__https://a.example/_p_` once lost its
    /// underscores on the second round).
    func testSaveThenRestoreChangesNothingAndStaysThatWay() {
        var random = Generator(state: 0x5A7E)
        for _ in 0 ..< 4000 {
            let count = Int.random(in: 1 ... 14, using: &random)
            let draft = (0 ..< count).map { _ in pieces.randomElement(using: &random)! }.joined()
            let first = MarkdownConverter.restoredDraft(draft)
            var state = first
            for cycle in 0 ..< 3 {
                let saved = MarkdownConverter.markdown(text: state.text, entities: state.entities)
                let back = MarkdownConverter.restoredDraft(saved)
                let context = "cycle \(cycle): \(draft.debugDescription) saved as \(saved.debugDescription)"
                // The words never change.
                XCTAssertEqual(back.text, first.text, context)
                if cycle == 0 {
                    // Styles come back as they were, with the spaces at their edges (which sit outside the markers) off,
                    // or (where a marker cannot be written so it reads back, say one that would sit inside an address)
                    // are dropped together. Never one that was not there.
                    XCTAssertTrue(Self.only(back.entities, from: first.entities), context)
                } else {
                    XCTAssertEqual(back.entities, state.entities, "stable from the second save on: \(context)")
                }
                state = back
            }
        }
    }

    /// The same for what the box holds after text is pasted into it (converted, not opened from a draft).
    func testWhatPastingMakesSurvivesSaveAndRestore() {
        var random = Generator(state: 0xFA57)
        for _ in 0 ..< 4000 {
            let count = Int.random(in: 1 ... 14, using: &random)
            let pasted = (0 ..< count).map { _ in pieces.randomElement(using: &random)! }.joined()
            let held = MarkdownConverter.convertAll(text: pasted).map { ($0.text, $0.entities) } ?? (pasted, [])
            let back = MarkdownConverter.restoredDraft(MarkdownConverter.markdown(text: held.0, entities: held.1))
            XCTAssertEqual(back.text, held.0, pasted.debugDescription)
            // Where a style could not be written so it reads back, the words are kept and the styles are not: never
            // other styles, and never other words.
            XCTAssertTrue(Self.only(back.entities, from: held.1), pasted.debugDescription)
        }
    }

    func testThePathologicalDraftKeepsItsUnderscores() {
        let draft = "__https://a.example/_p_"
        var state = MarkdownConverter.restoredDraft(draft)
        XCTAssertEqual(state.text, draft)
        for _ in 0 ..< 3 {
            state = MarkdownConverter.restoredDraft(MarkdownConverter.markdown(text: state.text, entities: state.entities))
            XCTAssertEqual(state.text, draft)
            XCTAssertEqual(state.entities, [])
        }
        // Styles that would sit inside an address cannot be written so they read back: the words stay, intact.
        let styled = [TextEntity(kind: .bold, offset: 8, length: 9)]
        let text = "https://a.example/x"
        let saved = MarkdownConverter.markdown(text: text, entities: styled)
        let back = MarkdownConverter.restoredDraft(saved)
        XCTAssertEqual(back.text, text)
        XCTAssertEqual(MarkdownConverter.restoredDraft(MarkdownConverter.markdown(text: back.text, entities: back.entities)).text, text)
    }
}
