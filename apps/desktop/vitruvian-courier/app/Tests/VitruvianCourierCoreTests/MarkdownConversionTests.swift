// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import XCTest

@testable import VitruvianCourierCore

/// Typed markdown becomes real formatting: the markers go, the words keep the style as a range, and the ranges are
/// what is sent. All data here is made up.
@MainActor
final class MarkdownConversionTests: XCTestCase {
    private struct Made {
        let composer: ComposerModel
        let sender: FakeSender
    }

    private func make(draft: String = "") -> Made {
        let store = TestDefaults()
        addTeardownBlock { store.remove() }
        let preferences = ComposerPreferences(defaults: store.defaults)
        preferences.undoSendMillis = 0
        let sender = FakeSender()
        let composer = ComposerModel(sender: sender, draftDelay: 0, sleep: { _ in }, preferences: preferences)
        composer.emojiUsage = EmojiUsageStore(defaults: store.defaults)
        composer.savedDraft = { room in room == "!draft" ? draft : "" }
        composer.open("!a")
        return Made(composer: composer, sender: sender)
    }

    /// Types `text` one character at a time, as the text view reports it.
    private func type(_ text: String, into composer: ComposerModel) {
        for character in text {
            insert(String(character), into: composer, at: (composer.text as NSString).length)
        }
    }

    private func insert(_ text: String, into composer: ComposerModel, at location: Int) {
        let current = composer.text as NSString
        composer.textChanged(to: current.replacingCharacters(in: NSRange(location: location, length: 0), with: text),
                             replacing: NSRange(location: location, length: 0), with: (text as NSString).length)
    }

    private func entity(_ kind: TextEntity.Kind, _ offset: Int, _ length: Int) -> TextEntity {
        TextEntity(kind: kind, offset: offset, length: length)
    }

    // MARK: Typing the closing marker

    func testClosingTheMarkerTurnsTheWordsIntoFormattingAndTakesTheMarkersOut() {
        let composer = make().composer
        type("say **bold**", into: composer)
        XCTAssertEqual(composer.text, "say bold")
        XCTAssertEqual(composer.entities, [entity(.bold, 4, 4)])
        XCTAssertEqual(composer.selection, NSRange(location: 8, length: 0), "the caret is after the words")
        XCTAssertEqual(composer.caretRequest?.location, 8, "and the text view is told")
        XCTAssertNotNil(composer.lastMarkdownConversion)
    }

    func testEachKindOfMarker() {
        for (typed, text, kind) in [
            ("a _it_", "a it", TextEntity.Kind.italic), ("a *it*", "a it", .italic), ("a ~~gone~~", "a gone", .strikethrough),
            ("a `code`", "a code", .code), ("a **b**", "a b", .bold),
        ] {
            let composer = make().composer
            type(typed, into: composer)
            XCTAssertEqual(composer.text, text, typed)
            XCTAssertEqual(composer.entities.map(\.kind), [kind], typed)
            XCTAssertEqual(composer.entities.first?.offset, 2, typed)
        }
    }

    func testTypingGoesOnPlainAfterIt() {
        let composer = make().composer
        type("say **bold**", into: composer)
        type(" more", into: composer)
        XCTAssertEqual(composer.text, "say bold more")
        XCTAssertEqual(composer.entities, [entity(.bold, 4, 4)], "what follows is not bold")
        type(" and _it_", into: composer)
        XCTAssertEqual(composer.text, "say bold more and it")
        XCTAssertEqual(composer.entities, [entity(.bold, 4, 4), entity(.italic, 18, 2)])
    }

    func testNothingChangesUntilTheMarkerIsClosed() {
        let composer = make().composer
        type("say **bold*", into: composer)
        XCTAssertEqual(composer.text, "say **bold*")
        XCTAssertEqual(composer.entities, [])
        XCTAssertNil(composer.lastMarkdownConversion)
    }

    func testMarkersInsideWordsAndSpacedOnesAreLeftAlone() {
        for typed in ["snake_case_name", "2*3*4", "2 * 3 * 4", "** not **", "a lone * star", "file_name_ok"] {
            let composer = make().composer
            type(typed, into: composer)
            XCTAssertEqual(composer.text, typed)
            XCTAssertEqual(composer.entities, [], typed)
        }
    }

    func testNestedStylesConvertInTurn() {
        let composer = make().composer
        type("**bold _and italic_**", into: composer)
        XCTAssertEqual(composer.text, "bold and italic")
        XCTAssertEqual(composer.entities, [entity(.bold, 0, 15), entity(.italic, 5, 10)])
    }

    // MARK: Undo

    func testUndoRightAfterTheConversionPutsTheMarkersBack() throws {
        let composer = make().composer
        type("say **bold**", into: composer)
        let record = try XCTUnwrap(composer.lastMarkdownConversion)
        XCTAssertTrue(composer.undoMarkdownConversion(record))
        XCTAssertEqual(composer.text, "say **bold**")
        XCTAssertEqual(composer.entities, [])
        XCTAssertEqual(composer.selection, NSRange(location: 12, length: 0))
        XCTAssertEqual(composer.caretRequest?.location, 12)
        XCTAssertNil(composer.lastMarkdownConversion)
        // Typing on afterwards does not convert it again.
        type(" x", into: composer)
        XCTAssertEqual(composer.text, "say **bold** x")
        XCTAssertEqual(composer.entities, [])
    }

    func testUndoDoesNothingOnceTheBoxHasMovedOn() throws {
        let composer = make().composer
        type("say **bold**", into: composer)
        let record = try XCTUnwrap(composer.lastMarkdownConversion)
        type("!", into: composer)
        XCTAssertFalse(composer.undoMarkdownConversion(record))
        XCTAssertEqual(composer.text, "say bold!")
    }

    // MARK: Paste

    func testPastedTextWithMarkersConverts() {
        let composer = make().composer
        insert("a **b** c _d_ ~~e~~ `f`", into: composer, at: 0)
        XCTAssertEqual(composer.text, "a b c d e f")
        XCTAssertEqual(composer.entities, [
            entity(.bold, 2, 1), entity(.italic, 6, 1), entity(.strikethrough, 8, 1), entity(.code, 10, 1),
        ])
    }

    func testPastingIntoTheMiddleKeepsTheRangesAfterItInPlace() {
        let composer = make().composer
        type("hello world", into: composer)
        composer.toggle(.italic, in: NSRange(location: 6, length: 5))
        insert("**big** ", into: composer, at: 6)
        XCTAssertEqual(composer.text, "hello big world")
        XCTAssertEqual(composer.entities, [entity(.bold, 6, 3), entity(.italic, 10, 5)])
    }

    func testTextInsideCodeNeverConverts() {
        let composer = make().composer
        // Backticks make code, and what is inside stays as typed (here pasted: typed one key at a time, the stars
        // close before the backtick does).
        insert("`**x**`", into: composer, at: 0)
        XCTAssertEqual(composer.text, "**x**")
        XCTAssertEqual(composer.entities, [entity(.code, 0, 5)])

        // Pasted into a range that is already code (⌘E over it), nothing converts either.
        let other = make().composer
        type("ab", into: other)
        other.toggle(.code, in: NSRange(location: 0, length: 2))
        insert("**x**", into: other, at: 1)
        XCTAssertEqual(other.text, "a**x**b")
        XCTAssertEqual(other.entities.map(\.kind), [.code])
    }

    func testAFenceAroundSeveralLinesIsACodeBlock() {
        let composer = make().composer
        insert("```\nlet x = 1\nlet y = 2\n```", into: composer, at: 0)
        XCTAssertEqual(composer.text, "let x = 1\nlet y = 2")
        XCTAssertEqual(composer.entities, [entity(.pre, 0, 19)])
    }

    // MARK: Addresses, mentions, kept-literal markers

    /// An address or an @mention is one word: markers inside it are part of it, not formatting.
    func testAddressesAndMentionNamesAreNeverConverted() {
        for typed in ["see https://x.com/a_b_c now", "see https://x.com/_a_ now", "go https://x.com/?q=*a* ok",
                      "@john_doe_ hi", "@_john_ hi"] {
            let composer = make().composer
            type(typed, into: composer)
            XCTAssertEqual(composer.text, typed, "typed: \(typed)")
            XCTAssertEqual(composer.entities, [], "typed: \(typed)")
        }
    }

    func testMoreAddressShapesAndAMentionAlreadyMade() {
        for typed in ["see www.example.com/_a_ ok", "mail me_a_b@example.com now", "**https://x.com/a**"] {
            let composer = make().composer
            type(typed, into: composer)
            XCTAssertEqual(composer.text, typed, "typed: \(typed)")
            XCTAssertEqual(composer.entities, [], "typed: \(typed)")
        }
        // A mention that is already a range keeps what is inside it.
        XCTAssertNil(MarkdownConverter.convertAll(text: "hi _Ann_", entities: [
            TextEntity(kind: .mention, offset: 3, length: 5, userID: "@ann:x"),
        ]))
        // Words beside an address still convert.
        let composer = make().composer
        type("see https://x.com and **this**", into: composer)
        XCTAssertEqual(composer.text, "see https://x.com and this")
        XCTAssertEqual(composer.entities, [entity(.bold, 22, 4)])
    }

    func testMarkersLeftAsTypedAfterUndoStayLiteralInTheSavedDraft() async throws {
        let made = make()
        type("**x**", into: made.composer)
        XCTAssertEqual(made.composer.text, "x")
        XCTAssertTrue(made.composer.undoMarkdownConversion(try XCTUnwrap(made.composer.lastMarkdownConversion)))
        XCTAssertEqual(made.composer.text, "**x**")
        made.composer.open("!b")
        for _ in 0 ..< 50 { await Task.yield() }
        let saved = try XCTUnwrap(made.sender.savedDrafts.last)
        XCTAssertEqual(saved, "\\*\\*x\\*\\*", "each kept-literal marker is escaped")

        // Reopened from the engine's draft: still literal, not bold.
        let again = make(draft: saved).composer
        again.open("!draft")
        XCTAssertEqual(again.text, "**x**")
        XCTAssertEqual(again.entities, [])
    }

    func testBackslashesSurviveTheDraftRoundTrip() {
        for (text, entities) in [
            ("C:\\dir\\*not*", [TextEntity]()), ("a \\*b* c", [TextEntity]()), ("one \\ two", [TextEntity]()),
            ("bold \\x", [TextEntity(kind: .bold, offset: 0, length: 4)]),
        ] {
            let written = MarkdownConverter.markdown(text: text, entities: entities)
            let converted = MarkdownConverter.convertAll(text: written)
            let back = MarkdownConverter.unescaped(text: converted?.text ?? written, entities: converted?.entities ?? [])
            XCTAssertEqual(back.text, text, written)
            XCTAssertEqual(back.entities, entities, written)
        }
    }

    /// The inbox's "Draft:" line shows the draft as the box shows it: no escapes, no style markers.
    func testTheInboxDraftLineShowsTheDraftAsTheBoxDoes() async throws {
        XCTAssertEqual(MarkdownConverter.visibleDraft("say **bold** and _it_"), "say bold and it")
        XCTAssertEqual(MarkdownConverter.visibleDraft("\\*\\*x\\*\\* kept"), "**x** kept")
        XCTAssertEqual(MarkdownConverter.visibleDraft("C:\\\\dir \\\\\\* ok"), "C:\\dir \\* ok")
        XCTAssertEqual(MarkdownConverter.visibleDraft("plain text"), "plain text")

        // What the box saved for text left as typed reads back, in that line, exactly as the box showed it.
        let made = make()
        type("**x**", into: made.composer)
        XCTAssertEqual(made.composer.text, "x")
        XCTAssertTrue(made.composer.undoMarkdownConversion(try XCTUnwrap(made.composer.lastMarkdownConversion)))
        type(" and \\path", into: made.composer)
        XCTAssertEqual(made.composer.text, "**x** and \\path")
        let shown = made.composer.text
        made.composer.open("!b")
        for _ in 0 ..< 50 { await Task.yield() }
        let saved = try XCTUnwrap(made.sender.savedDrafts.last)
        XCTAssertNotEqual(saved, shown, "the kept draft carries escapes")
        XCTAssertEqual(MarkdownConverter.visibleDraft(saved), shown)
    }

    // MARK: What is sent

    func testTheRangesAreWhatIsSentAndTheMarkersAreNot() async {
        let made = make()
        type("hello **world** and _you_", into: made.composer)
        await made.composer.submit()?.value
        XCTAssertEqual(made.sender.sends.last?.rich, RichText(text: "hello world and you", entities: [
            entity(.bold, 6, 5), entity(.italic, 16, 3),
        ]))
    }

    func testANetworkWithNoFormattingGetsThePlainWordsWithNoMarkers() async {
        let made = make()
        made.composer.features = .noFeatures
        XCTAssertFalse(made.composer.features.keeps(.bold))
        type("hello **world** and `code`", into: made.composer)
        await made.composer.submit()?.value
        let sent = made.sender.sends.last?.rich
        XCTAssertEqual(sent?.text, "hello world and code")
        XCTAssertFalse(sent?.text.contains("*") ?? true)
        XCTAssertFalse(sent?.text.contains("`") ?? true)
        // The engine, which knows what the chat keeps, writes a chat that keeps none the plain words
        // (richtext's TestPlainNetworksGetReadableText).
    }

    // MARK: Editing a sent message

    func testEditingAFormattedMessageLoadsItsRangesBackAsStyledText() throws {
        let made = make()
        let sentAt = Date(timeIntervalSince1970: 1_700_000_000)
        let content = try JSONDecoder().decode(JSONValue.self, from: Data(#"""
        {"msgtype":"m.text","body":"bold and it","format":"org.matrix.custom.html",
         "formatted_body":"<strong>bold</strong> and <em>it</em>"}
        """#.utf8))
        let event = Event(eventID: "$m", roomID: "!a", sender: "@me:x", senderName: "me", mine: true,
                          type: "m.room.message", content: content, ts: Int64(sentAt.timeIntervalSince1970 * 1000),
                          seq: 1, status: .sent, statusReason: "")
        let timeline = Timeline.build(events: [event], me: "@me:x", now: sentAt.addingTimeInterval(60))
        var message: TimelineMessage?
        for case let .message(found) in timeline where found.id == "$m" { message = found }
        let found = try XCTUnwrap(message)
        made.composer.startEditing(found)
        XCTAssertEqual(made.composer.text, "bold and it")
        XCTAssertEqual(made.composer.entities, [entity(.bold, 0, 4), entity(.italic, 9, 2)])
    }

    // MARK: Drafts

    func testTheStylesStayWithTheDraftWhileTheAppRuns() {
        let made = make()
        type("say **bold**", into: made.composer)
        made.composer.open("!b")
        XCTAssertEqual(made.composer.text, "")
        made.composer.open("!a")
        XCTAssertEqual(made.composer.text, "say bold")
        XCTAssertEqual(made.composer.entities, [entity(.bold, 4, 4)])
    }

    func testTheEngineKeepsTheDraftAsMarkdownTextAndItOpensStyledAgain() async {
        let made = make(draft: "kept **bold** and _it_")
        type("say **bold**", into: made.composer)
        made.composer.open("!b")
        for _ in 0 ..< 50 { await Task.yield() }
        XCTAssertTrue(made.sender.savedDrafts.contains("say **bold**"), "saved: \(made.sender.savedDrafts)")
        made.composer.open("!draft")
        XCTAssertEqual(made.composer.text, "kept bold and it")
        XCTAssertEqual(made.composer.entities, [entity(.bold, 5, 4), entity(.italic, 14, 2)])
    }

    // MARK: Writing styles as markdown, and back

    func testMarkdownOfRanges() {
        XCTAssertEqual(MarkdownConverter.markdown(text: "say bold", entities: [entity(.bold, 4, 4)]), "say **bold**")
        XCTAssertEqual(MarkdownConverter.markdown(text: "a b c", entities: [
            entity(.italic, 0, 1), entity(.strikethrough, 2, 1), entity(.code, 4, 1),
        ]), "_a_ ~~b~~ `c`")
        XCTAssertEqual(MarkdownConverter.markdown(text: "bold and it", entities: [
            entity(.bold, 0, 11), entity(.italic, 5, 3),
        ]), "**bold _and_ it**")
        // Spaces at the edge of a range stay outside the markers, or they would not read back.
        XCTAssertEqual(MarkdownConverter.markdown(text: "a  b c", entities: [entity(.bold, 1, 3)]), "a  **b** c")
        XCTAssertEqual(MarkdownConverter.markdown(text: "x`y", entities: [entity(.code, 0, 3)]), "``x`y``")
        // Ranges with no marker are plain, as before.
        XCTAssertEqual(MarkdownConverter.markdown(text: "see", entities: [entity(.spoiler, 0, 3)]), "see")
        // Next to each other, one closes before the next opens.
        XCTAssertEqual(MarkdownConverter.markdown(text: "ab", entities: [entity(.bold, 0, 1), entity(.italic, 1, 1)]), "**a**_b_")
    }

    func testWhatIsWrittenAsMarkdownReadsBackAsTheSameStyles() {
        let samples: [(String, [TextEntity])] = [
            ("say bold", [entity(.bold, 4, 4)]),
            ("a b c", [entity(.italic, 0, 1), entity(.strikethrough, 2, 1), entity(.code, 4, 1)]),
            ("bold and it", [entity(.bold, 0, 11), entity(.italic, 5, 3)]),
            ("x`y and z", [entity(.code, 0, 3)]),
        ]
        for (text, entities) in samples {
            let written = MarkdownConverter.markdown(text: text, entities: entities)
            let back = MarkdownConverter.convertAll(text: written)
            XCTAssertEqual(back?.text, text, written)
            XCTAssertEqual(back?.entities, entities, written)
        }
    }

    func testTheConverterLeavesPlainTextAlone() {
        XCTAssertNil(MarkdownConverter.convertAll(text: "nothing here: 2 * 3, snake_case"))
        XCTAssertNil(MarkdownConverter.convert(text: "**a** b", entities: [], inserted: NSRange(location: 6, length: 1)),
                     "a span whose closing marker was not just typed stays as it is")
    }

    // MARK: Where markers are not formatting

    func testTheFormattingKeysGiveTheSameRangesAsTypedMarkers() async {
        let cases: [(String, TextEntity.Kind)] = [("**", .bold), ("_", .italic), ("~~", .strikethrough), ("`", .code)]
        for (marker, kind) in cases {
            let typed = make()
            type("say \(marker)word\(marker)", into: typed.composer)
            let keyed = make()
            type("say word", into: keyed.composer)
            keyed.composer.toggle(kind, in: NSRange(location: 4, length: 4))
            XCTAssertEqual(keyed.composer.text, typed.composer.text, marker)
            XCTAssertEqual(keyed.composer.entities, typed.composer.entities, marker)
            await typed.composer.submit()?.value
            await keyed.composer.submit()?.value
            XCTAssertNotNil(typed.sender.sends.last?.rich, marker)
            XCTAssertEqual(keyed.sender.sends.last?.rich, typed.sender.sends.last?.rich, "what is sent for \(marker)")
        }
    }

    func testTypingIntoAFiveThousandCharDraftStaysQuick() {
        // A draft that is slow to scan: openers that never close, on one line.
        for chunk in ["*a ", "_a ", "~~a ", "`a `` ", "**a *b _c "] {
            let composer = make().composer
            let base = String(repeating: chunk, count: 5_000 / chunk.count)
            composer.textChanged(to: base, replacing: NSRange(location: 0, length: 0), with: (base as NSString).length)
            var worst: TimeInterval = 0
            for character in "typing on and on" {
                let started = Date()
                insert(String(character), into: composer, at: (composer.text as NSString).length)
                worst = max(worst, Date().timeIntervalSince(started))
            }
            print("QA-TIMING model keystroke at \((base as NSString).length) chars of \(chunk.debugDescription): worst \(Int(worst * 1000)) ms")
            XCTAssertLessThan(worst, 0.1, "a keystroke in \(chunk.debugDescription)")
        }
    }
}
