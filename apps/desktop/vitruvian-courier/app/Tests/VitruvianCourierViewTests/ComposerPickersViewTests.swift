// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import AppKit
import SwiftUI
import VitruvianCourierCore
import XCTest

@testable import VitruvianCourier

/// The message box's live formatting, the emoji picker and the GIF strip, drawn light and dark (PNGs in the test's
/// outputs for a person to read) with assertions on what they do.
@MainActor
final class ComposerPickersViewTests: XCTestCase {
    private func makeComposer(text: String = "") -> (ComposerModel, ComposerPreferences) {
        let name = "courier.pickers.\(UUID().uuidString)"
        let defaults = ScratchDefaults.suite(named: name)!
        addTeardownBlock { defaults.removePersistentDomain(forName: name) }
        let preferences = ComposerPreferences(defaults: defaults)
        let composer = ComposerModel(sender: SnapshotMessageSender(), draftDelay: 0, sleep: { _ in }, preferences: preferences)
        composer.emojiUsage = EmojiUsageStore(defaults: defaults)
        composer.open(Fixture.room)
        composer.features = Fixture.features
        composer.network = "whatsapp"
        composer.text = text
        return (composer, preferences)
    }

    private func attributes(_ view: PlainTextView, at index: Int) -> [NSAttributedString.Key: Any] {
        view.textStorage?.attributes(at: index, effectiveRange: nil) ?? [:]
    }

    // MARK: Live formatting

    func testTypedMarkdownIsStyledAsYouTypeWithoutChangingTheText() throws {
        let view = PlainTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 100))
        let text = "a **bold** _it_ ~~no~~ `code` z"
        view.string = text
        view.apply([])
        XCTAssertEqual(view.string, text, "only attributes change: what is sent is what was typed")
        let ns = text as NSString

        let boldWord = ns.range(of: "bold")
        let boldFont = try XCTUnwrap(attributes(view, at: boldWord.location)[.font] as? NSFont)
        XCTAssertTrue(NSFontManager.shared.traits(of: boldFont).contains(.boldFontMask))

        let italicWord = ns.range(of: "it")
        let italicFont = try XCTUnwrap(attributes(view, at: italicWord.location)[.font] as? NSFont)
        XCTAssertTrue(NSFontManager.shared.traits(of: italicFont).contains(.italicFontMask))

        let struck = ns.range(of: "no")
        XCTAssertNotNil(attributes(view, at: struck.location)[.strikethroughStyle])

        let codeWord = ns.range(of: "code")
        let codeFont = try XCTUnwrap(attributes(view, at: codeWord.location)[.font] as? NSFont)
        XCTAssertTrue(codeFont.isFixedPitch, "code is monospaced")
        XCTAssertNotNil(attributes(view, at: codeWord.location)[.backgroundColor], "code sits on a shaded chip")

        // The markers are still there, drawn faint; plain words are not.
        let opening = ns.range(of: "**")
        let faint = try XCTUnwrap(attributes(view, at: opening.location)[.foregroundColor] as? NSColor)
        let plain = try XCTUnwrap(attributes(view, at: 0)[.foregroundColor] as? NSColor)
        XCTAssertLessThan(faint.alphaComponent, plain.alphaComponent * 0.5, "the marker is much fainter than the words")
        XCTAssertNil(attributes(view, at: 0)[.strikethroughStyle])
        let tick = ns.range(of: "`")
        XCTAssertNil(attributes(view, at: tick.location)[.backgroundColor], "the chip is behind the words, not the ticks")
    }

    func testTextThatOnlyLooksLikeMarkdownIsNotStyled() throws {
        let view = PlainTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 100))
        view.string = "2 * 3 * 4 and snake_case_name"
        view.apply([])
        let plain = try XCTUnwrap(attributes(view, at: 0)[.foregroundColor] as? NSColor)
        for index in 0 ..< (view.string as NSString).length {
            let color = try XCTUnwrap(attributes(view, at: index)[.foregroundColor] as? NSColor)
            XCTAssertEqual(color.alphaComponent, plain.alphaComponent, accuracy: 0.001, "character \(index) was dimmed")
        }
    }

    func testTypingKeepsTheCaretAndRestyles() throws {
        let (composer, preferences) = makeComposer()
        let host = NSHostingView(rootView: ComposerView(
            composer: composer, preferences: preferences, textHeight: .constant(ComposerTextView.minimumHeight)
        ))
        host.frame = NSRect(x: 0, y: 0, width: 620, height: 160)
        host.layoutSubtreeIfNeeded()
        let textView = try XCTUnwrap(host.first(PlainTextView.self))
        textView.insertText("hello **wor", replacementRange: textView.selectedRange())
        XCTAssertEqual(try XCTUnwrap(textView.textStorage).length, 11)
        let caretBefore = textView.selectedRange()
        textView.insertText("ld**", replacementRange: textView.selectedRange())
        for _ in 0 ..< 10 { RunLoop.main.run(mode: .default, before: Date(timeIntervalSinceNow: 0.004)) }
        XCTAssertEqual(textView.string, "hello **world**")
        XCTAssertEqual(textView.selectedRange(), NSRange(location: 15, length: 0), "the caret is where typing left it")
        XCTAssertEqual(caretBefore, NSRange(location: 11, length: 0))
        let font = try XCTUnwrap(attributes(textView, at: 9)[.font] as? NSFont)
        XCTAssertTrue(NSFontManager.shared.traits(of: font).contains(.boldFontMask), "styled once the closing marker is typed")
        // Text typed after the closing marker is plain.
        let typing = try XCTUnwrap(textView.typingAttributes[.font] as? NSFont)
        XCTAssertFalse(NSFontManager.shared.traits(of: typing).contains(.boldFontMask))
    }

    // MARK: Emoji picker

    func testEmojiPickerDrawsAndTheButtonTogglesIt() throws {
        let (composer, _) = makeComposer()
        composer.emojiUsage.record("🎉")
        let sizes = try Snapshot.render("emoji-picker-popover", width: 330, height: 380) {
            EmojiPickerPopover(composer: composer)
        }
        XCTAssertEqual(sizes.count, 2)
        // The emoji button opens the in-app picker (and, from its footer, the system palette).
        composer.toggleEmojiPicker()
        XCTAssertTrue(composer.isEmojiPickerPresented)
    }

    // MARK: GIF strip

    func testGIFStripIsAboveTheMessageBoxInsideTheChatAndAboutTwoHundredAndTwentyTall() throws {
        let (composer, preferences) = makeComposer()
        composer.gifProvider = StubGIFProvider()
        XCTAssertTrue(composer.openGIFPicker())
        let sizes = try Snapshot.render("gif-picker-strip", width: 620) {
            GIFPickerStrip(composer: composer)
                .padding(12)
        }
        XCTAssertEqual(sizes.first?.height, GIFPickerStrip.height + 24, "220 tall, plus the padding the test adds")

        // In the composer, the strip is part of the same view (so the chat's bottom bar grows), not a popover.
        let host = NSHostingView(rootView: ComposerView(
            composer: composer, preferences: preferences, textHeight: .constant(ComposerTextView.minimumHeight)
        ))
        host.frame = NSRect(x: 0, y: 0, width: 620, height: 600)
        host.layoutSubtreeIfNeeded()
        let withStrip = host.fittingSize.height
        composer.isGIFPickerPresented = false
        host.layoutSubtreeIfNeeded()
        let without = host.fittingSize.height
        XCTAssertGreaterThanOrEqual(withStrip - without, GIFPickerStrip.height, "the strip takes its room in the composer")
    }
}
