// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import XCTest

@testable import VitruvianCourierCore

/// The live formatting in the message box: which typed markdown is styled, and which is left alone.
final class MarkdownSpansTests: XCTestCase {
    /// Each span as `kind:content`, in order, so a case reads as what the person would see styled.
    private func styled(_ text: String) -> [String] {
        MarkdownSpans.parse(text).map { span in
            let kind: String
            switch span.kind {
            case .code: kind = "code"
            case .bold: kind = "bold"
            case .italic: kind = "italic"
            case .strikethrough: kind = "strike"
            }
            return "\(kind):\((text as NSString).substring(with: span.content))"
        }
    }

    func testEachKindOfSpan() {
        XCTAssertEqual(styled("use `git status` now"), ["code:git status"])
        XCTAssertEqual(styled("this is **bold** text"), ["bold:bold"])
        XCTAssertEqual(styled("this is _slanted_ text"), ["italic:slanted"])
        XCTAssertEqual(styled("this is *slanted* text"), ["italic:slanted"])
        XCTAssertEqual(styled("this is ~~gone~~ text"), ["strike:gone"])
    }

    func testMarkersAreFoundSoTheyCanBeDrawnFaint() throws {
        let text = "a **bo** b"
        let span = try XCTUnwrap(MarkdownSpans.parse(text).first)
        XCTAssertEqual(span.open, NSRange(location: 2, length: 2))
        XCTAssertEqual(span.content, NSRange(location: 4, length: 2))
        XCTAssertEqual(span.close, NSRange(location: 6, length: 2))
        XCTAssertEqual(span.whole, NSRange(location: 2, length: 6))
    }

    func testSeveralSpansAndNesting() {
        XCTAssertEqual(styled("**a** and _b_ and `c`"), ["bold:a", "italic:b", "code:c"])
        XCTAssertEqual(styled("**bold _and italic_**"), ["bold:bold _and italic_", "italic:and italic"])
        XCTAssertEqual(styled("*a **b** c*"), ["italic:a **b** c", "bold:b"])
        XCTAssertEqual(styled("***both***"), ["bold:*both*", "italic:both"])
    }

    func testCodeIsNotLookedInto() {
        XCTAssertEqual(styled("`**not bold**`"), ["code:**not bold**"])
        XCTAssertEqual(styled("`a_b_c` and _d_"), ["code:a_b_c", "italic:d"])
        // A marker inside code closes nothing outside it: here the backticks are code, and the stars never close.
        XCTAssertEqual(styled("**a `**` b"), ["code:**"])
        XCTAssertEqual(styled("``a ` b``"), ["code:a ` b"])
    }

    func testAFenceOfThreeMayCrossLines() {
        XCTAssertEqual(styled("```\nlet x = 1\n```"), ["code:\nlet x = 1\n"])
        XCTAssertEqual(styled("`one\ntwo`"), [], "a single backtick stops at the end of the line")
    }

    func testTextThatMerelyLooksLikeMarkersIsLeftAlone() {
        XCTAssertEqual(styled("2 * 3 * 4"), [])
        XCTAssertEqual(styled("** not bold **"), [])
        XCTAssertEqual(styled("snake_case_name and other_name"), [])
        XCTAssertEqual(styled("__init__"), [])
        XCTAssertEqual(styled("a lone * star"), [])
        XCTAssertEqual(styled("an open **bold"), [])
        XCTAssertEqual(styled("~ single tilde ~"), [])
        XCTAssertEqual(styled("empty **** here"), [])
        XCTAssertEqual(styled("* a bullet"), [])
        XCTAssertEqual(styled("https://example.com/a_b_c_d"), [])
    }

    func testASpanStaysOnItsLine() {
        XCTAssertEqual(styled("**one\ntwo**"), [])
        XCTAssertEqual(styled("**one**\n**two**"), ["bold:one", "bold:two"])
    }

    func testBackslashKeepsAMarkerAsItself() {
        XCTAssertEqual(styled("\\*not italic\\*"), [])
        // The escaped star is text; what follows is a lone `*x**` with no span.
        XCTAssertEqual(styled("\\**x**"), [])
    }

    func testUnderscoreAtTheEdgeOfAWordOnly() {
        XCTAssertEqual(styled("(_hi_)"), ["italic:hi"])
        XCTAssertEqual(styled("_hi_."), ["italic:hi"])
        XCTAssertEqual(styled("a_hi_b"), [])
    }

    func testRangesCountUTF16LikeTheTextView() throws {
        // The emoji is two UTF-16 units: the span's range must be in the text view's units, not characters.
        let text = "😀 **bold**"
        let span = try XCTUnwrap(MarkdownSpans.parse(text).first)
        XCTAssertEqual((text as NSString).substring(with: span.content), "bold")
        XCTAssertEqual(span.open.location, 3)
    }

    func testVeryLongDraftsAreNotStyled() {
        let long = String(repeating: "**a** ", count: MarkdownSpans.maximumLength)
        XCTAssertEqual(MarkdownSpans.parse(long), [])
        XCTAssertEqual(MarkdownSpans.parse(""), [])
        XCTAssertEqual(MarkdownSpans.parse("*"), [])
    }

    func testManyUnmatchedMarkersStillFinish() {
        let text = String(repeating: "*a ", count: 4_000)
        XCTAssertEqual(MarkdownSpans.parse(text), [])
    }
}
