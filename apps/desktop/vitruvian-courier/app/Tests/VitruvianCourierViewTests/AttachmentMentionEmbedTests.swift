// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import AppKit
import VitruvianCourierCore
import SwiftUI
import XCTest

@testable import VitruvianCourier

/// A long file name has room in its chip, mentions read in light and dark (also inside a quote), and a YouTube card
/// shows its video's picture. Look at attachment-long-name-*, mention-*, embed-thumbnail-*.
@MainActor
final class AttachmentMentionEmbedTests: XCTestCase {
    // MARK: - Pixels

    private func luminances(_ name: String, _ suffix: String) throws -> [Double] {
        let url = Snapshot.directory.appendingPathComponent("\(name)-\(suffix).png")
        let rep = try XCTUnwrap(NSBitmapImageRep(data: Data(contentsOf: url)))
        var values: [Double] = []
        for y in 0 ..< rep.pixelsHigh {
            for x in 0 ..< rep.pixelsWide {
                guard let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
                values.append(0.2126 * Double(c.redComponent) + 0.7152 * Double(c.greenComponent) + 0.0722 * Double(c.blueComponent))
            }
        }
        return values
    }

    private func redPixelCount(_ name: String, _ suffix: String) throws -> Int {
        let url = Snapshot.directory.appendingPathComponent("\(name)-\(suffix).png")
        let rep = try XCTUnwrap(NSBitmapImageRep(data: Data(contentsOf: url)))
        var count = 0
        for y in 0 ..< rep.pixelsHigh {
            for x in 0 ..< rep.pixelsWide {
                guard let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
                if c.redComponent > 0.85, c.greenComponent < 0.4, c.blueComponent < 0.4 { count += 1 }
            }
        }
        return count
    }

    // MARK: - 1. Attachment name

    func testALongFileNameGetsTheRoomBeforeItIsCut() throws {
        let name = "bucket_pipeline_monkey_report.html"
        var event = Fixture.event("$file-long", mine: false, ts: 25, content: [
            "msgtype": .string("m.file"), "body": .string(name), "filename": .string(name),
            "info": .object(["mimetype": .string("text/html"), "size": .int(48_000)]),
        ], name: "Alice Example")
        event.mediaPath = ""
        let message = try XCTUnwrap(Fixture.messages([event]).first)
        let chip = FileAttachmentChip(message: message)
        let host = NSHostingView(rootView: chip)
        // The old chip was cut at 340 points (and its name at 210), which cut this name at about 18 letters.
        XCTAssertGreaterThan(host.fittingSize.width, 340, "the chip grows to fit the whole name")
        XCTAssertLessThanOrEqual(host.fittingSize.width, FileAttachmentChip.maxChipWidth)
        try Snapshot.render("attachment-long-name", width: 460) { chip.padding(10) }
    }

    // MARK: - 3. Mentions

    private func mentionView(quoted: Bool) -> some View {
        let text = "Ann Example"
        var entities = [TextEntity(kind: .mention, offset: 0, length: text.utf16.count, userID: "@ann:courier.local")]
        if quoted { entities.insert(TextEntity(kind: .blockquote, offset: 0, length: text.utf16.count), at: 0) }
        return RichTextView(rich: RichText(text: text, entities: entities), onBubble: false, revealed: .constant(false))
            .font(.system(size: 22))
            .environment(\.courierMessagePointSize, 22)
            .padding(12)
    }

    func testMentionsUsePrimaryTextInLightAndDark() throws {
        for quoted in [false, true] {
            let name = quoted ? "mention-quoted" : "mention"
            try Snapshot.render(name, width: 300) { mentionView(quoted: quoted) }
            let light = try luminances(name, "light")
            XCTAssertLessThan(try XCTUnwrap(light.min()), 0.2, "\(name): dark text on the tint in light mode")
            let dark = try luminances(name, "dark")
            XCTAssertGreaterThan(try XCTUnwrap(dark.max()), 0.9, "\(name): light text on the tint in dark mode")
        }
    }

    // MARK: - 2. YouTube picture

    func testYouTubeDescriptorKnowsItsPictureAddress() throws {
        let youtube = try XCTUnwrap(ExternalEmbedDescriptor.match(urlString: "https://youtu.be/dQw4w9WgXcQ"))
        XCTAssertEqual(youtube.youTubeVideoID, "dQw4w9WgXcQ")
        XCTAssertEqual(youtube.remoteThumbnailURL?.absoluteString, "https://i.ytimg.com/vi/dQw4w9WgXcQ/mqdefault.jpg")
        let vimeo = try XCTUnwrap(ExternalEmbedDescriptor.match(urlString: "https://vimeo.com/123456"))
        XCTAssertNil(vimeo.remoteThumbnailURL)
        let spotify = try XCTUnwrap(ExternalEmbedDescriptor.match(urlString: "https://open.spotify.com/track/abc123"))
        XCTAssertNil(spotify.remoteThumbnailURL)
    }

    private func redPicture() throws -> String {
        let image = NSImage(size: NSSize(width: 160, height: 90), flipped: false) { rect in
            NSColor(srgbRed: 1, green: 0, blue: 0, alpha: 1).setFill()
            rect.fill()
            return true
        }
        let rep = try XCTUnwrap(NSBitmapImageRep(data: try XCTUnwrap(image.tiffRepresentation)))
        let png = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("embed-thumb-\(UUID().uuidString).png")
        try png.write(to: url)
        return url.path
    }

    private func settle(_ view: NSView) {
        for _ in 0 ..< 200 {
            RunLoop.main.run(mode: .default, before: Date(timeIntervalSinceNow: 0.01))
            view.layoutSubtreeIfNeeded()
        }
    }

    func testTheCardDrawsThePreviewPictureOverThePlayGlyph() throws {
        let descriptor = try XCTUnwrap(ExternalEmbedDescriptor.match(urlString: "https://www.youtube.com/watch?v=dQw4w9WgXcQ"))
        let path = try redPicture()
        try Snapshot.render("embed-thumbnail-none", width: 360, prepare: settle) {
            EmbedConsentCard(messageID: "$e", descriptor: descriptor, isLoaded: false, onLoadEmbed: {}).padding(14)
        }
        try Snapshot.render("embed-thumbnail", width: 360, prepare: settle) {
            EmbedConsentCard(messageID: "$e", descriptor: descriptor, isLoaded: false, previewImagePath: path,
                             onLoadEmbed: {}).padding(14)
        }
        for suffix in ["light", "dark"] {
            XCTAssertEqual(try redPixelCount("embed-thumbnail-none", suffix), 0, "no picture, the plain play tile")
            XCTAssertGreaterThan(try redPixelCount("embed-thumbnail", suffix), 500, "the saved preview picture is drawn")
        }
    }

    func testPreviewPathComesFromTheMessagesOwnPreview() throws {
        let path = try redPicture()
        func message(_ imagePath: String?) throws -> TimelineMessage {
            var event = Fixture.event("$m", mine: false, ts: 1, content: [
                "msgtype": .string("m.text"), "body": .string("https://youtu.be/dQw4w9WgXcQ"),
            ])
            event.linkPreviews = imagePath.map { [LinkPreviewItem(matchedURL: "https://youtu.be/dQw4w9WgXcQ", imagePath: $0)] }
            return try XCTUnwrap(Fixture.messages([event]).first)
        }
        XCTAssertNil(ExternalEmbedDescriptor.previewImagePath(in: try message(nil)))
        XCTAssertEqual(ExternalEmbedDescriptor.previewImagePath(in: try message(path)), path)
        XCTAssertNil(ExternalEmbedDescriptor.previewImagePath(in: try message("https://i.ytimg.com/x.jpg")),
                     "only pictures already on this Mac")
    }
}
