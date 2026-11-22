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
        for typed in ["see www.example.com/_a_ ok", "mail me_a_b@example.com now"] {
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

    func testASpanThatEndsInAnAddressOrMentionConverts() {
        for (typed, expected, kind) in [
            ("**see https://x.com**", "see https://x.com", TextEntity.Kind.bold), ("_hi @bob_", "hi @bob", .italic),
            ("**@bob**", "@bob", .bold), ("**https://x.com/a**", "https://x.com/a", .bold),
            ("~~see www.x.com/a.~~", "see www.x.com/a.", .strikethrough),
        ] {
            let composer = make().composer
            type(typed, into: composer)
            XCTAssertEqual(composer.text, expected, typed)
            XCTAssertEqual(composer.entities.map(\.kind), [kind], typed)
        }
        // The address inside the words is still one word: a marker inside it stays.
        let composer = make().composer
        type("**a** https://x.com/_b_", into: composer)
        XCTAssertEqual(composer.text, "a https://x.com/_b_")
        XCTAssertEqual(composer.entities.map(\.kind), [.bold])
    }

    /// A draft kept before this feature (or by another app) has backslashes of its own: only the doubled backslash
    /// and a backslash before a marker character are escapes.
    func testOldDraftsKeepTheirBackslashes() {
        for old in ["C:\\Users\\(x)", "a\\b", "path\\to\\file_name", "what\\?"] {
            let restored = MarkdownConverter.restoredDraft(old)
            XCTAssertEqual(restored.text, old)
            XCTAssertEqual(restored.entities, [])
        }
        // What this feature writes still reads back exactly, backslashes before other marks included.
        for text in ["C:\\Users\\(x)", "a\\b", "x \\*y\\* z", "two \\\\ slashes", "tail\\"] {
            let written = MarkdownConverter.markdown(text: text, entities: [])
            XCTAssertEqual(MarkdownConverter.restoredDraft(written).text, text, written)
        }
    }

    func testQAProbeStyledSentencesEndingInAnAddressOrMention() {
        for (typed, expected) in [("**see https://x.com**", "see https://x.com"), ("_hi @bob_", "hi @bob"),
                                  ("**@bob**", "@bob"), ("**a** https://x.com/_b_", "a https://x.com/_b_")] {
            let composer = make().composer
            type(typed, into: composer)
            XCTAssertEqual(composer.text, expected, typed)
        }
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

    /// The typical time of a keystroke at the end of a draft made of `chunk` repeated to about `size` characters: the
    /// median of 16 keystrokes, the best of 3 tries, so one slow moment on a busy machine does not decide it.
    private func keystrokeTime(_ chunk: String, size: Int) -> TimeInterval {
        var best = TimeInterval.infinity
        for _ in 0 ..< 3 {
            let composer = make().composer
            let base = String(repeating: chunk, count: size / chunk.count)
            composer.textChanged(to: base, replacing: NSRange(location: 0, length: 0), with: (base as NSString).length)
            var times: [TimeInterval] = []
            for character in "typing on and on" {
                let started = Date()
                insert(String(character), into: composer, at: (composer.text as NSString).length)
                times.append(Date().timeIntervalSince(started))
            }
            best = min(best, times.sorted()[times.count / 2])
        }
        return best
    }

    func testTypingIntoALongDraftGrowsNoFasterThanTheDraft() {
        // Drafts that are slow to scan: openers that never close, on one line, or hundreds of code spans. A keystroke
        // must cost about as much more as the draft is longer, not that squared: eight times the draft, about eight
        // times the time (a save that grows with the square would take about sixty-four). A ratio, not a fixed number
        // of milliseconds, because the CI machines run this about ten times slower than a Mac on a desk.
        for chunk in ["*a ", "_a ", "~~a ", "`a `` ", "**a *b _c "] {
            let small = keystrokeTime(chunk, size: 1_000)
            let large = keystrokeTime(chunk, size: 8_000)
            let ratio = large / max(small, 0.000_05)
            print("QA-TIMING model keystroke in \(chunk.debugDescription): 1000 chars \(String(format: "%.2f", small * 1000)) ms, 8000 chars \(String(format: "%.2f", large * 1000)) ms, ratio \(String(format: "%.1f", ratio))")
            XCTAssertLessThan(ratio, 14, "a keystroke in \(chunk.debugDescription) grows faster than the draft")
            XCTAssertLessThan(large, 0.5, "a keystroke in an 8000-char draft of \(chunk.debugDescription)")
        }
    }

    /// The one-pass removal and merge give exactly what removing and adding one at a time gave, on made-up drafts.
    func testOnePassRemovalAndMergeMatchOneAtATime() {
        var rng = SystemRandomNumberGenerator()
        let kinds: [TextEntity.Kind] = [.bold, .italic, .code, .mention, .link, .strikethrough]
        for _ in 0 ..< 2_000 {
            let length = Int.random(in: 0 ... 40, using: &rng)
            let string = String(repeating: "x", count: length) as NSString
            var entities: [TextEntity] = []
            for _ in 0 ..< Int.random(in: 0 ... 6, using: &rng) where length > 0 {
                let offset = Int.random(in: 0 ..< length, using: &rng)
                let size = Int.random(in: 1 ... length - offset, using: &rng)
                entities.append(TextEntity(kind: kinds.randomElement(using: &rng)!, offset: offset, length: size))
            }
            entities.sort(by: TextEntity.precedes)
            var removed: [NSRange] = []
            var at = 0
            while length > 0, at < length, removed.count < 8 {
                at += Int.random(in: 0 ... 5, using: &rng)
                guard at < length else { break }
                let size = Int.random(in: 1 ... min(3, length - at), using: &rng)
                removed.append(NSRange(location: at, length: size))
                at += size
            }
            var expectedText = string
            var expected = entities
            for marker in removed.reversed() {
                expectedText = expectedText.replacingCharacters(in: marker, with: "") as NSString
                expected = EntityEditing.replacing(expected, range: marker, with: 0)
            }
            let got = MarkdownConverter.removingAll(removed, from: string, entities: entities)
            XCTAssertEqual(got.text, expectedText as String, "removing \(removed) from \(length)")
            XCTAssertEqual(got.entities, expected, "removing \(removed) from \(entities)")

            let made = (0 ..< Int.random(in: 0 ... 5, using: &rng)).compactMap { _ -> TextEntity? in
                guard length > 0 else { return nil }
                let offset = Int.random(in: 0 ..< length, using: &rng)
                let kind: TextEntity.Kind = [.bold, .italic, .code].randomElement(using: &rng)!
                return TextEntity(kind: kind, offset: offset, length: Int.random(in: 1 ... length - offset, using: &rng))
            }
            // As the converter uses it: onto ranges already fitted, and fitted again after. A box never holds two code
            // ranges that overlap or touch (code is only ever added merged), and the converter never adds code that runs
            // into code already there, so the made-up drafts don't either.
            func touchesCode(_ entity: TextEntity, in list: [TextEntity]) -> Bool {
                list.contains { $0.kind == .code && $0.offset <= entity.offset + entity.length && entity.offset <= $0.offset + $0.length }
            }
            var fitted: [TextEntity] = []
            for entity in EntityEditing.fitted(entities, to: string) {
                if entity.kind == .code, touchesCode(entity, in: fitted) { continue }
                fitted.append(entity)
            }
            let added = made.filter { $0.kind != .code || !touchesCode($0, in: fitted) }
            var oneAtATime = fitted
            for entity in added {
                oneAtATime = EntityEditing.adding(entity.kind, in: entity.range, of: string, entities: oneAtATime)
            }
            XCTAssertEqual(EntityEditing.fitted(MarkdownConverter.merging(added, into: fitted), to: string),
                           EntityEditing.fitted(oneAtATime, to: string), "adding \(added) to \(fitted)")
        }
    }
}
