// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import XCTest

@testable import CourierCore

/// EntityEditing: how the composer's formatting ranges follow the text as it is typed, and what the formatting keys
/// do. Offsets are UTF-16 code units, as NSString counts them.
final class EntityEditingTests: XCTestCase {
    private func entity(_ kind: TextEntity.Kind, _ offset: Int, _ length: Int, user: String? = nil) -> TextEntity {
        TextEntity(kind: kind, offset: offset, length: length, userID: user)
    }

    private func edit(_ entities: [TextEntity], at location: Int, removing removed: Int = 0, inserting inserted: Int)
        -> [TextEntity] {
        EntityEditing.replacing(entities, range: NSRange(location: location, length: removed), with: inserted)
    }

    func testTypingInsideABoldRangeGrowsIt() {
        // "hello world": "hello" bold, "world" italic.
        let start = [entity(.bold, 0, 5), entity(.italic, 6, 5)]

        XCTAssertEqual(edit(start, at: 2, inserting: 1), [entity(.bold, 0, 6), entity(.italic, 7, 5)],
                       "typed inside: it grows, and what comes after moves along")
        XCTAssertEqual(edit(start, at: 0, inserting: 2), [entity(.bold, 2, 5), entity(.italic, 8, 5)],
                       "typed before it: it moves, and doesn't take the new text")
        XCTAssertEqual(edit(start, at: 5, inserting: 1), [entity(.bold, 0, 5), entity(.italic, 7, 5)],
                       "typed just after it: plain (a formatting key makes what is typed next bold)")
        XCTAssertEqual(edit(start, at: 11, inserting: 3), start, "typed after everything: nothing moves")
    }

    func testDeletingAcrossARangeShrinksIt() {
        // "abcdefghij" with "cdefgh" bold.
        let bold = [entity(.bold, 2, 6)]
        XCTAssertEqual(edit(bold, at: 0, removing: 4, inserting: 0), [entity(.bold, 0, 4)],
                       "deleting its start with what came before: what is left of it moves up")
        XCTAssertEqual(edit(bold, at: 6, removing: 4, inserting: 0), [entity(.bold, 2, 4)],
                       "deleting its end with what came after")
        XCTAssertEqual(edit(bold, at: 3, removing: 2, inserting: 5), [entity(.bold, 2, 9)],
                       "replacing inside it: it takes the new text")
        XCTAssertEqual(edit(bold, at: 1, removing: 8, inserting: 0), [], "deleted with it: it goes")
        XCTAssertEqual(edit(bold, at: 2, removing: 6, inserting: 3), [], "wholly replaced: it goes")
        XCTAssertEqual(edit(bold, at: 0, removing: 1, inserting: 0), [entity(.bold, 1, 6)])
    }

    func testEditingAMentionRemovesIt() {
        // "hi @Ann ok": "@Ann" a mention.
        let mention = [entity(.mention, 3, 4, user: "@ann:example.test")]
        XCTAssertEqual(edit(mention, at: 5, inserting: 1), [], "typing inside a name breaks it: it is one unit")
        XCTAssertEqual(edit(mention, at: 6, removing: 2, inserting: 0), [], "deleting into it")
        XCTAssertEqual(edit(mention, at: 4, removing: 1, inserting: 1), [], "replacing a letter of it")
        XCTAssertEqual(edit(mention, at: 7, inserting: 1), mention, "a space typed after it leaves it whole")
        XCTAssertEqual(edit(mention, at: 3, inserting: 2), [entity(.mention, 5, 4, user: "@ann:example.test")],
                       "typed before it: it moves")
        XCTAssertEqual(edit(mention, at: 0, removing: 3, inserting: 0), [entity(.mention, 0, 4, user: "@ann:example.test")])
    }

    func testToggleOnAndOff() {
        let text = "one two three" as NSString
        var entities: [TextEntity] = []

        entities = EntityEditing.toggle(.bold, in: NSRange(location: 0, length: 3), of: text, entities: entities)
        XCTAssertEqual(entities, [entity(.bold, 0, 3)])
        entities = EntityEditing.toggle(.bold, in: NSRange(location: 4, length: 3), of: text, entities: entities)
        XCTAssertEqual(entities, [entity(.bold, 0, 3), entity(.bold, 4, 3)], "a space apart: two ranges")
        entities = EntityEditing.toggle(.bold, in: NSRange(location: 3, length: 1), of: text, entities: entities)
        XCTAssertEqual(entities, [entity(.bold, 0, 7)], "bridging the gap makes them one")

        entities = EntityEditing.toggle(.bold, in: NSRange(location: 2, length: 3), of: text, entities: entities)
        XCTAssertEqual(entities, [entity(.bold, 0, 2), entity(.bold, 5, 2)],
                       "a selection already bold comes off, and only there")

        entities = EntityEditing.toggle(.bold, in: NSRange(location: 0, length: 7), of: text, entities: entities)
        XCTAssertEqual(entities, [entity(.bold, 0, 7)], "partly bold: the key makes all of it bold")

        entities = EntityEditing.toggle(.italic, in: NSRange(location: 4, length: 9), of: text, entities: entities)
        XCTAssertEqual(entities, [entity(.bold, 0, 7), entity(.italic, 4, 9)], "kinds don't touch each other")

        XCTAssertEqual(EntityEditing.toggle(.bold, in: NSRange(location: 3, length: 0), of: text, entities: entities),
                       entities, "with no selection, nothing changes here: the composer keeps it for what is typed next")
    }

    func testBlockKindsCoverWholeLines() {
        let text = "first\nsecond\nthird" as NSString

        // A caret in a line is that line.
        var entities = EntityEditing.toggle(.blockquote, in: NSRange(location: 8, length: 0), of: text, entities: [])
        XCTAssertEqual(entities, [entity(.blockquote, 6, 6)], "the line \"second\", without its line break")

        // A selection across lines takes every line it touches, and replaces another block on them.
        entities = EntityEditing.toggle(.bulletList, in: NSRange(location: 2, length: 7), of: text, entities: entities)
        XCTAssertEqual(entities, [entity(.bulletList, 0, 12)], "a list over \"first\" and \"second\"; the quote goes")

        // Again on the same lines: it comes off.
        XCTAssertEqual(EntityEditing.toggle(.bulletList, in: NSRange(location: 0, length: 3), of: text,
                                            entities: entities),
                       [entity(.bulletList, 6, 6)], "off the first line only, and the second stays a list")
        XCTAssertEqual(EntityEditing.toggle(.bulletList, in: NSRange(location: 1, length: 9), of: text,
                                            entities: entities), [])

        // A selection that ends just after a line break doesn't take the line after it.
        XCTAssertEqual(EntityEditing.toggle(.pre, in: NSRange(location: 0, length: 6), of: text, entities: []),
                       [entity(.pre, 0, 5)])

        // The line next to a quote joins it.
        let quoted = [entity(.blockquote, 0, 5)]
        XCTAssertEqual(EntityEditing.toggle(.blockquote, in: NSRange(location: 7, length: 0), of: text, entities: quoted),
                       [entity(.blockquote, 0, 12)])

        // A block takes whole lines, so what the engine refuses (a block on part of a line) is never made.
        for location in 0 ..< text.length {
            for kind in [TextEntity.Kind.pre, .blockquote, .bulletList, .orderedList] {
                let made = EntityEditing.toggle(kind, in: NSRange(location: location, length: 0), of: text, entities: [])
                XCTAssertEqual(RichTextHTML.sendable(made, in: text as String), made, "\(kind) at \(location)")
            }
        }
    }

    func testJoiningLinesKeepsTheFirstLinesBlock() {
        // Backspace at the start of a quoted line joins it to a plain one: the joined line is plain, as the first was.
        let quoted = [entity(.blockquote, 6, 5)] // "plain\nquote"
        var joined = EntityEditing.replacing(quoted, range: NSRange(location: 5, length: 1), with: 0)
        XCTAssertEqual(EntityEditing.fitted(joined, to: "plainquote"), [])

        // Joined the other way, the quote takes the line that joined it.
        let first = [entity(.blockquote, 0, 5)] // "quote\nplain"
        joined = EntityEditing.replacing(first, range: NSRange(location: 5, length: 1), with: 0)
        XCTAssertEqual(EntityEditing.fitted(joined, to: "quoteplain"), [entity(.blockquote, 0, 10)])

        // Deleting across a line break into a list leaves it its whole lines.
        let list = [entity(.bulletList, 6, 7)] // "intro\none\ntwo"
        let cut = EntityEditing.replacing(list, range: NSRange(location: 3, length: 5), with: 0) // "int" + "e\ntwo"
        XCTAssertEqual(EntityEditing.fitted(cut, to: "inte\ntwo"), [entity(.bulletList, 5, 3)])

        // Styles of a kind that come to touch are one, as the engine has them.
        let styles = [entity(.bold, 0, 1), entity(.bold, 2, 1)] // "aXb"
        let touching = EntityEditing.replacing(styles, range: NSRange(location: 1, length: 1), with: 0)
        XCTAssertEqual(EntityEditing.fitted(touching, to: "ab"), [entity(.bold, 0, 2)])
    }

    func testEditsKeepEveryRangeSendable() {
        // Every block kind, a style, a link and a mention, across lines; then every insertion and deletion there is.
        let text = "plain bold\nquoted line\none\ntwo\n1st\n2nd\ncode\nsee site @Ann" as NSString
        func at(_ word: String) -> Int { text.range(of: word).location }
        let start: [TextEntity] = [
            entity(.bold, at("bold"), 4),
            entity(.blockquote, at("quoted"), 11),
            entity(.bulletList, at("one"), 7),
            entity(.orderedList, at("1st"), 7),
            entity(.pre, at("code"), 4),
            TextEntity(kind: .link, offset: at("site"), length: 4, url: "https://example.test/a"),
            entity(.mention, at("@Ann"), 4, user: "@ann:example.test"),
        ].sorted(by: TextEntity.precedes)
        XCTAssertEqual(RichTextHTML.sendable(start, in: text as String), start, "the fixture itself is sendable")

        var edits: [(NSRange, String)] = []
        for location in 0 ... text.length {
            edits.append((NSRange(location: location, length: 0), "x"))
            edits.append((NSRange(location: location, length: 0), "\n"))
            for length in 1 ... 3 where location + length <= text.length {
                edits.append((NSRange(location: location, length: length), ""))
                edits.append((NSRange(location: location, length: length), "\n"))
            }
        }
        for (range, inserted) in edits {
            let edited = text.replacingCharacters(in: range, with: inserted)
            let ranges = EntityEditing.fitted(
                EntityEditing.replacing(start, range: range, with: (inserted as NSString).length), to: edited as NSString)
            XCTAssertEqual(RichTextHTML.sendable(ranges, in: edited), ranges,
                           "\(range) → \(inserted.debugDescription): nothing the engine would drop")
        }
    }

    func testEmojiOffsets() {
        // "😀 hi": the emoji is two UTF-16 code units, so "hi" is at 3.
        let text = "😀 hi" as NSString
        XCTAssertEqual(text.length, 5)
        let bold = EntityEditing.toggle(.bold, in: text.range(of: "hi"), of: text, entities: [])
        XCTAssertEqual(bold, [entity(.bold, 3, 2)])

        // Typing an emoji (two units) before it moves it by two; one inside grows it by two.
        XCTAssertEqual(EntityEditing.replacing(bold, range: NSRange(location: 0, length: 0), with: 2), [entity(.bold, 5, 2)])
        XCTAssertEqual(EntityEditing.replacing(bold, range: NSRange(location: 4, length: 0), with: 2), [entity(.bold, 3, 4)])

        // Deleting the emoji (both units) moves it back.
        XCTAssertEqual(EntityEditing.replacing(bold, range: NSRange(location: 0, length: 2), with: 0), [entity(.bold, 1, 2)])

        // A family emoji is many units; the whole line still makes one block.
        let family = "👨‍👩‍👧 home" as NSString
        XCTAssertEqual(EntityEditing.toggle(.blockquote, in: NSRange(location: 3, length: 0), of: family, entities: []),
                       [entity(.blockquote, 0, family.length)])
    }
}
