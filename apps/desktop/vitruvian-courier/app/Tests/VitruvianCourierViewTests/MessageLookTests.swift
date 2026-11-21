// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import AppKit
import SwiftUI
import VitruvianCourierCore
import XCTest

@testable import VitruvianCourier

/// How messages look (batch 7, section A): bubbles that grow with a wide window, a photo with no frame, an article card
/// with the page's picture on top, and inline code on a rounded chip.
/// Look at look-wide-*, look-photo-*, look-caption-*, look-article-*, look-code-chip-*.
@MainActor
final class MessageLookTests: XCTestCase {
    private final class Box { var frame: CGRect = .zero }

    // MARK: Helpers

    private func bubbleFrame(_ event: Event, window: CGFloat, name: String, direct: Bool = false,
                             prepare: (NSView) -> Void = { _ in }) throws -> CGRect {
        let item = try XCTUnwrap(Fixture.items([event], isDirect: direct).first { if case .message = $0 { true } else { false } })
        let box = Box()
        let ui = MessageUI()
        let actions = VitruvianCourier.MessageActions(now: { Fixture.now })
        _ = try Snapshot.render("\(name)-\(Int(window))", width: window, prepare: prepare) {
            TimelineItemView(item: item, isSelected: false, showsSent: false, actions: actions, ui: ui)
                .overlayPreferenceValue(RowAnchorsKey.self) { anchors in
                    GeometryReader { geo in
                        Color.clear.onAppear { if let a = anchors.bubble { box.frame = geo[a] } }
                    }
                }
        }
        return box.frame
    }

    /// A solid-colour PNG in the temporary folder, `width` by `height`.
    private func picture(red: CGFloat, green: CGFloat, blue: CGFloat, width: Int, height: Int) throws -> String {
        let image = NSImage(size: NSSize(width: width, height: height), flipped: false) { rect in
            NSColor(srgbRed: red, green: green, blue: blue, alpha: 1).setFill()
            rect.fill()
            return true
        }
        let rep = try XCTUnwrap(NSBitmapImageRep(data: try XCTUnwrap(image.tiffRepresentation)))
        let png = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("look-\(UUID().uuidString).png")
        try png.write(to: url)
        return url.path
    }

    private func bitmap(_ name: String, _ suffix: String = "light") throws -> NSBitmapImageRep {
        let url = Snapshot.directory.appendingPathComponent("\(name)-\(suffix).png")
        return try XCTUnwrap(NSBitmapImageRep(data: Data(contentsOf: url)))
    }

    /// The box around every pixel `test` accepts, in points (the image's scale is its pixels over `width`).
    private func box(of rep: NSBitmapImageRep, width: CGFloat, where test: (NSColor) -> Bool) -> CGRect? {
        let scale = CGFloat(rep.pixelsWide) / width
        var minX = Int.max, minY = Int.max, maxX = -1, maxY = -1
        for y in 0 ..< rep.pixelsHigh {
            for x in 0 ..< rep.pixelsWide {
                guard let color = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB), test(color) else { continue }
                minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        guard maxX >= 0 else { return nil }
        return CGRect(x: CGFloat(minX) / scale, y: CGFloat(minY) / scale,
                      width: CGFloat(maxX - minX + 1) / scale, height: CGFloat(maxY - minY + 1) / scale)
    }

    private func isBlue(_ c: NSColor) -> Bool { c.blueComponent > 0.85 && c.redComponent < 0.3 && c.greenComponent < 0.3 }
    /// The colour-managed red of a pure red PNG draws a little orange (about 0.94, 0.25, 0.07).
    private func isRed(_ c: NSColor) -> Bool { c.redComponent > 0.8 && c.greenComponent < 0.4 && c.blueComponent < 0.3 }

    /// Pumps the run loop until the view has drawn some pixels `test` accepts (a picture arrived), or a few seconds pass.
    private func settle(until test: @escaping (NSColor) -> Bool) -> (NSView) -> Void {
        { view in
            for _ in 0 ..< 1500 {
                RunLoop.main.run(mode: .default, before: Date(timeIntervalSinceNow: 0.002))
                view.layoutSubtreeIfNeeded()
                guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { continue }
                view.cacheDisplay(in: view.bounds, to: rep)
                var hits = 0
                for y in stride(from: 0, to: rep.pixelsHigh, by: 2) {
                    for x in stride(from: 0, to: rep.pixelsWide, by: 2) {
                        if let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB), test(c) { hits += 1 }
                    }
                }
                if hits > 50 { return }
            }
        }
    }

    // MARK: A3. Wider bubbles

    func testATextBubbleGrowsWithAWideWindowAndKeepsTheOldWidthOnAMediumOne() throws {
        let long = String(repeating: "A long line of chat text that would stretch across a very wide window. ", count: 30)
        let event = Fixture.text("$wide", long, mine: false, ts: 2)
        let wide = try bubbleFrame(event, window: 1500, name: "look-wide").width
        XCTAssertEqual(wide, BubbleWidth.maxWidth(rowWidth: 1500), accuracy: 1, "60% of the window")
        XCTAssertGreaterThan(wide, 640, "wider than the old fixed cap")
        let medium = try bubbleFrame(event, window: 1000, name: "look-wide").width
        XCTAssertEqual(medium, 640, accuracy: 1, "a medium window keeps the width it always had")
        let narrow = try bubbleFrame(event, window: 400, name: "look-wide").width
        XCTAssertLessThanOrEqual(narrow, 400)
        XCTAssertGreaterThan(narrow, 250)
    }

    func testTheTimeStillTucksOntoTheLastLineOfAWideBubble() throws {
        // Text that ends a little short of the bubble's right edge: the time takes the room on its last line, so the
        // bubble is not taller than the same text with no time.
        let text = String(repeating: "word ", count: 14) + "end"
        func height(times: Bool) throws -> CGFloat {
            let item = try XCTUnwrap(Fixture.items([Fixture.text("$t", text, mine: false, ts: 2)])
                .first { if case .message = $0 { true } else { false } })
            var actions = VitruvianCourier.MessageActions(now: { Fixture.now })
            actions.showMessageTimestamps = times
            let host = NSHostingView(rootView: TimelineItemView(item: item, isSelected: false, showsSent: false,
                                                                actions: actions, ui: MessageUI())
                .frame(width: 1500).fixedSize(horizontal: false, vertical: true))
            return host.fittingSize.height
        }
        XCTAssertEqual(try height(times: true), try height(times: false), accuracy: 1,
                       "the time sits on the text's last line in a wide bubble")
    }

    // MARK: A2. Photos with no frame

    private func photoEvent(caption: String?, mine: Bool, path: String) -> Event {
        var content: [String: JSONValue] = [
            "msgtype": .string("m.image"), "body": .string(caption ?? "beach.jpg"),
            "info": .object(["w": .int(300), "h": .int(200), "mimetype": .string("image/png")]),
        ]
        if caption != nil { content["filename"] = .string("beach.jpg") }
        var event = Fixture.event("$photo", mine: mine, ts: 2, content: content)
        event.mediaPath = path
        return event
    }

    func testAPhotoOnItsOwnHasNoBubbleAndItsTimeRidesOnTheCorner() throws {
        let path = try picture(red: 0, green: 0, blue: 1, width: 300, height: 200)
        LocalFileFacts.warm(paths: [path])
        let plain = try bubbleFrame(photoEvent(caption: nil, mine: false, path: path), window: 520, name: "look-photo",
                                    prepare: settle(until: isBlue))
        XCTAssertEqual(plain.width, 300, accuracy: 0.5, "the bubble is the picture: no padding around it")
        XCTAssertEqual(plain.height, 200, accuracy: 0.5)

        let captioned = try bubbleFrame(photoEvent(caption: "Look at this", mine: false, path: path), window: 520,
                                        name: "look-caption", prepare: settle(until: isBlue))
        XCTAssertGreaterThan(captioned.width, plain.width + 4, "a caption keeps its bubble around the picture")
        XCTAssertGreaterThan(captioned.height, plain.height + 8)

        // The time is a dark patch over the picture's bottom-right corner, not a line under it.
        let rep = try bitmap("look-photo-520")
        let image = try XCTUnwrap(box(of: rep, width: 520, where: isBlue), "the picture is drawn")
        let darkBlue: (NSColor) -> Bool = { $0.blueComponent > 0.35 && $0.blueComponent < 0.65 && $0.redComponent < 0.15 }
        let capsule = try XCTUnwrap(box(of: rep, width: 520, where: darkBlue), "a translucent dark capsule over the picture")
        XCTAssertGreaterThan(capsule.midX, image.minX + image.width * 0.6, "on the right of the picture")
        XCTAssertGreaterThan(capsule.midY, image.minY + image.height * 0.6, "on the bottom of the picture")
        XCTAssertLessThanOrEqual(capsule.maxY, image.maxY + 1, "over the picture, not below it")
        XCTAssertLessThanOrEqual(capsule.maxX, image.maxX + 1)
    }

    // MARK: A1. Article card

    private func articleEvent(picturePath: String?, text: String) -> Event {
        var event = Fixture.event("$article", mine: false, ts: 2, content: [
            "msgtype": .string("m.text"), "body": .string(text),
        ])
        event.linkPreviews = [LinkPreviewItem(
            matchedURL: "https://example.com/story", url: "https://example.com/story",
            title: "A long story about a very long trail", siteName: "example.com",
            description: "What the page says about itself, in a sentence or three.",
            imagePath: picturePath, imageWidth: picturePath == nil ? nil : 1200, imageHeight: picturePath == nil ? nil : 630)]
        return event
    }

    func testAnArticleCardShowsThePictureFullWidthAboveTheLinkText() throws {
        let path = try picture(red: 1, green: 0, blue: 0, width: 1200, height: 630)
        LocalFileFacts.warm(paths: [path])
        _ = ImagePixelSizeReader.sizeNow(ofFirstReadable: [path])
        let event = articleEvent(picturePath: path, text: "https://example.com/story")
        let frame = try bubbleFrame(event, window: 1500, name: "look-article", direct: true, prepare: settle(until: isRed))
        XCTAssertEqual(frame.width, BubbleWidth.maxWidth(rowWidth: 1500), accuracy: 1, "the card is as wide as a bubble may be")

        let rep = try bitmap("look-article-1500")
        let red = try XCTUnwrap(box(of: rep, width: 1500, where: isRed), "the page's picture is drawn")
        XCTAssertEqual(red.height, LinkPreviewCardView<EmptyView>.maxPictureHeight, accuracy: 2, "cropped to 200 pt tall")
        // The bubble's own 11 pt padding either side, and the card's 1 pt border over the picture.
        XCTAssertEqual(red.width, frame.width - 22 - 2, accuracy: 4, "edge to edge across the card")
        XCTAssertLessThan(red.minY - frame.minY, 16, "the picture is on top of the bubble")
        XCTAssertGreaterThan(frame.height, red.maxY + 60, "the title, summary and the link's own text are below it")
    }

    func testACardWithNoPictureIsCompact() throws {
        let event = articleEvent(picturePath: nil, text: "https://example.com/story")
        let frame = try bubbleFrame(event, window: 1500, name: "look-article-none", direct: true)
        XCTAssertLessThanOrEqual(frame.width, LinkPreviewCardView<EmptyView>.maxTextOnlyWidth + 30,
                                 "a card with no picture is not stretched across the window")
    }

    func testTheCardHasAnEmptyFooterSlotUnderItsText() throws {
        let preview = LinkPreviewItem(matchedURL: "https://example.com/a", url: "https://example.com/a", title: "Title")
        let without = NSHostingView(rootView: LinkPreviewCardView(preview: preview).frame(width: 360))
        let with = NSHostingView(rootView: LinkPreviewCardView(preview: preview) { Color.green.frame(height: 30) }
            .frame(width: 360))
        XCTAssertEqual(with.fittingSize.height - without.fittingSize.height, 30, accuracy: 0.5,
                       "what goes in the footer sits inside the card, under its text")
    }

    private func noPictureCard(_ url: String = "https://www.example.com/news/story") -> LinkPreviewItem {
        LinkPreviewItem(matchedURL: url, url: url, title: "A story", siteName: "example.com")
    }

    func testACardWithNoPictureAsksForThePageOnceAndDrawsIt() throws {
        let path = try picture(red: 1, green: 0, blue: 0, width: 1200, height: 630)
        LocalFileFacts.warm(paths: [path])
        var asked: [URL] = []
        let images = LinkPreviewImages { url in
            asked.append(url)
            return LinkPreviewImage(path: path, width: 1200, height: 630)
        }
        // Drawn twice (light and dark are two cards of the same chat): one request.
        _ = try Snapshot.render("look-card-fetched", width: 520, prepare: settle(until: isRed)) {
            LinkPreviewCardView(preview: noPictureCard(), images: images, allowsRemoteImage: true).padding(14)
        }
        XCTAssertEqual(asked.count, 1, "asked once, however many cards are drawn")
        XCTAssertEqual(images.requestCount, 1)
        let rep = try bitmap("look-card-fetched")
        XCTAssertNotNil(box(of: rep, width: 520, where: isRed), "the fetched picture is drawn on the card")
    }

    func testACardAsksForNothingWhenShowLinkPreviewsIsOff() throws {
        let path = try picture(red: 1, green: 0, blue: 0, width: 1200, height: 630)
        var asked = 0
        let images = LinkPreviewImages { _ in
            asked += 1
            return LinkPreviewImage(path: path, width: 1200, height: 630)
        }
        _ = try Snapshot.render("look-card-policy-off", width: 520, prepare: { view in
            for _ in 0 ..< 100 {
                RunLoop.main.run(mode: .default, before: Date(timeIntervalSinceNow: 0.002))
                view.layoutSubtreeIfNeeded()
            }
        }) {
            LinkPreviewCardView(preview: noPictureCard(), images: images, allowsRemoteImage: false).padding(14)
        }
        XCTAssertEqual(asked, 0, "Show link previews off: the page is not asked about")
        XCTAssertNil(box(of: try bitmap("look-card-policy-off"), width: 520, where: isRed))
    }

    func testACardWhoseNetworkPreviewHasAPictureAsksForNothing() throws {
        let path = try picture(red: 0, green: 0, blue: 1, width: 1200, height: 630)
        LocalFileFacts.warm(paths: [path])
        var asked = 0
        let images = LinkPreviewImages { _ in asked += 1; return nil }
        var preview = noPictureCard()
        preview.imagePath = path
        _ = try Snapshot.render("look-card-has-picture", width: 520, prepare: settle(until: isBlue)) {
            LinkPreviewCardView(preview: preview, images: images, allowsRemoteImage: true).padding(14)
        }
        XCTAssertEqual(asked, 0)
        XCTAssertNotNil(box(of: try bitmap("look-card-has-picture"), width: 520, where: isBlue))
    }

    // MARK: A4. Inline code chip

    func testInlineCodeIsDrawnOnARoundedChip() throws {
        guard RichTextView.drawsCodeChips else { throw XCTSkip("rounded chips need macOS 15") }
        // Four em spaces of code: no ink, so every coloured pixel is the chip itself.
        let blank = "\u{2003}\u{2003}\u{2003}\u{2003}"
        let rich = RichText(text: blank, entities: [TextEntity(kind: .code, offset: 0, length: blank.utf16.count)])
        // Beside words, for the eye (look-code-chip-words-*).
        let words = RichText(text: "Run git status now, then git push.", entities: [
            TextEntity(kind: .code, offset: 4, length: 10), TextEntity(kind: .code, offset: 25, length: 8),
        ])
        for onBubble in [false, true] {
            _ = try Snapshot.render("look-code-chip-words-\(onBubble ? "mine" : "theirs")", width: 320) {
                RichTextView(rich: words, onBubble: onBubble, revealed: .constant(false)).padding(16)
                    .background(onBubble ? Color.blue : Color.clear)
            }
        }
        _ = try Snapshot.render("look-code-chip", width: 200) {
            RichTextView(rich: rich, onBubble: false, revealed: .constant(false)).padding(20)
        }
        let rep = try bitmap("look-code-chip")
        let scale = CGFloat(rep.pixelsWide) / 240
        // The window background is near white; the chip is a darker grey patch.
        func background() -> NSColor { rep.colorAt(x: 1, y: 1)!.usingColorSpace(.sRGB)! }
        let bg = background()
        let chip = try XCTUnwrap(box(of: rep, width: 240, where: { abs($0.redComponent - bg.redComponent) > 0.03 }),
                                 "a shaded chip behind the code")
        XCTAssertGreaterThan(chip.width, 20, "as wide as the code and its 2 pt either side")
        // Rounded: the chip's own corner pixel is background, a pixel a few points inside is chip.
        func pixel(_ x: CGFloat, _ y: CGFloat) -> NSColor {
            rep.colorAt(x: Int(x * scale), y: Int(y * scale))!.usingColorSpace(.sRGB)!
        }
        XCTAssertLessThan(abs(pixel(chip.minX + 0.25, chip.minY + 0.25).redComponent - bg.redComponent), 0.02,
                          "square corners would be filled here")
        XCTAssertGreaterThan(abs(pixel(chip.midX, chip.midY).redComponent - bg.redComponent), 0.03)
    }
}
