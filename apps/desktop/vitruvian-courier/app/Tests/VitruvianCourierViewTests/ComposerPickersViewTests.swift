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

    // MARK: Typed markdown becomes formatting

    private func hostedComposer() throws -> (ComposerModel, NSHostingView<ComposerView>, PlainTextView) {
        let (composer, preferences) = makeComposer()
        let host = NSHostingView(rootView: ComposerView(
            composer: composer, preferences: preferences, textHeight: .constant(ComposerTextView.minimumHeight)
        ))
        // In a window, as the box is in the app: the window gives the text view its undo manager.
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 620, height: 160), styleMask: [.borderless],
                              backing: .buffered, defer: false)
        window.contentView = host
        host.frame = NSRect(x: 0, y: 0, width: 620, height: 160)
        host.layoutSubtreeIfNeeded()
        addTeardownBlock { window.contentView = nil }
        let textView = try XCTUnwrap(host.first(PlainTextView.self))
        return (composer, host, textView)
    }

    private func pump() {
        for _ in 0 ..< 10 { RunLoop.main.run(mode: .default, before: Date(timeIntervalSinceNow: 0.004)) }
    }

    private func isBold(_ view: PlainTextView, at index: Int) -> Bool {
        guard let font = attributes(view, at: index)[.font] as? NSFont else { return false }
        return NSFontManager.shared.traits(of: font).contains(.boldFontMask)
    }

    func testTypingTheClosingMarkerStylesTheWordsAndTakesTheMarkersOut() throws {
        let (composer, _, textView) = try hostedComposer()
        for character in "say **bold**" {
            textView.insertText(String(character), replacementRange: textView.selectedRange())
        }
        pump()
        XCTAssertEqual(textView.string, "say bold", "the markers are gone from the box")
        XCTAssertEqual(composer.text, "say bold", "and from what will be sent")
        XCTAssertEqual(composer.entities, [TextEntity(kind: .bold, offset: 4, length: 4)])
        XCTAssertTrue(isBold(textView, at: 4))
        XCTAssertFalse(isBold(textView, at: 0))
        XCTAssertEqual(textView.selectedRange(), NSRange(location: 8, length: 0), "the caret is after the words")
        // Typing goes on in the plain style.
        textView.insertText(" more", replacementRange: textView.selectedRange())
        pump()
        XCTAssertEqual(textView.string, "say bold more")
        XCTAssertFalse(isBold(textView, at: 9))
        XCTAssertEqual(composer.entities, [TextEntity(kind: .bold, offset: 4, length: 4)])
    }

    func testUndoRightAfterTheConversionBringsTheMarkersBack() throws {
        let (composer, _, textView) = try hostedComposer()
        for character in "say **bold**" {
            textView.insertText(String(character), replacementRange: textView.selectedRange())
        }
        pump()
        XCTAssertEqual(textView.string, "say bold")
        let undo = try XCTUnwrap(textView.undoManager)
        XCTAssertTrue(undo.canUndo)
        undo.undo()
        pump()
        XCTAssertEqual(textView.string, "say **bold**")
        XCTAssertEqual(composer.text, "say **bold**")
        XCTAssertEqual(composer.entities, [])
        XCTAssertFalse(isBold(textView, at: 4))
        XCTAssertEqual(textView.selectedRange(), NSRange(location: 12, length: 0))
    }

    func testPastedMarkdownConvertsToo() throws {
        let (composer, _, textView) = try hostedComposer()
        textView.insertText("a **b** _c_ `d`", replacementRange: textView.selectedRange())
        pump()
        XCTAssertEqual(textView.string, "a b c d")
        XCTAssertEqual(composer.entities.map(\.kind), [.bold, .italic, .code])
        let code = try XCTUnwrap(attributes(textView, at: 6)[.font] as? NSFont)
        XCTAssertTrue(code.isFixedPitch)
    }

    func testTextThatOnlyLooksLikeMarkdownIsLeftAsTyped() throws {
        let (composer, _, textView) = try hostedComposer()
        textView.insertText("2*3*4 and snake_case_name", replacementRange: textView.selectedRange())
        pump()
        XCTAssertEqual(textView.string, "2*3*4 and snake_case_name")
        XCTAssertEqual(composer.entities, [])
    }

    func testCommandBIAndEAndShiftXAreTheStyleKeysAndCommandEIsArchiveWithNoSelection() throws {
        func key(_ chars: String, _ flags: NSEvent.ModifierFlags, code: UInt16) -> NSEvent {
            NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: 0, context: nil,
                             characters: chars, charactersIgnoringModifiers: chars, isARepeat: false, keyCode: code)!
        }
        XCTAssertEqual(PlainTextView.formatKind(for: key("b", [.command], code: 0x0B)), .bold)
        XCTAssertEqual(PlainTextView.formatKind(for: key("i", [.command], code: 0x22)), .italic)
        XCTAssertEqual(PlainTextView.formatKind(for: key("e", [.command], code: 0x0E)), .code)
        XCTAssertEqual(PlainTextView.formatKind(for: key("x", [.command, .shift], code: 0x07)), .strikethrough)

        let (composer, _, textView) = try hostedComposer()
        textView.insertText("make code here", replacementRange: textView.selectedRange())
        pump()
        // With nothing selected, ⌘E is not Code (it stays Archive elsewhere in the app).
        textView.setSelectedRange(NSRange(location: 5, length: 0))
        _ = textView.performKeyEquivalent(with: key("e", [.command], code: 0x0E))
        XCTAssertEqual(composer.entities, [])
        // Over a selection it is Code.
        textView.setSelectedRange(NSRange(location: 5, length: 4))
        composer.selectionChanged(to: NSRange(location: 5, length: 4))
        XCTAssertTrue(textView.onFormat(.code, false))
        XCTAssertEqual(composer.entities.map(\.kind), [.code])
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

    func testAKeystrokeInAFiveThousandCharDraftIsQuickInTheTextView() throws {
        for chunk in ["*a ", "**a *b _c "] {
            let (composer, _, textView) = try hostedComposer()
            let base = String(repeating: chunk, count: 5_000 / chunk.count)
            textView.insertText(base, replacementRange: textView.selectedRange())
            pump()
            XCTAssertEqual(composer.text, base)
            var worst: TimeInterval = 0
            for character in "typing on and on, forty keys!" {
                let started = Date()
                textView.insertText(String(character), replacementRange: textView.selectedRange())
                worst = max(worst, Date().timeIntervalSince(started))
            }
            print("QA-TIMING view keystroke at \((base as NSString).length) chars of \(chunk.debugDescription): worst \(Int(worst * 1000)) ms")
            XCTAssertLessThan(worst, 0.1, "a keystroke in \(chunk.debugDescription)")
        }
    }
}
