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
final class SizeBox { var size = CGSize.zero }

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

    func testTheChipFitsInANarrowBubble() throws {
        let name = "bucket_pipeline_monkey_report_with_a_very_long_name_indeed.html"
        var event = Fixture.event("$file-narrow", mine: false, ts: 25, content: [
            "msgtype": .string("m.file"), "body": .string(name), "filename": .string(name),
            "info": .object(["mimetype": .string("text/html"), "size": .int(48_000)]),
        ], name: "Alice Example")
        event.mediaPath = ""
        let message = try XCTUnwrap(Fixture.messages([event]).first)
        let measured = SizeBox()
        let host = NSHostingView(rootView: FileAttachmentChip(message: message)
            .onGeometryChange(for: CGSize.self, of: { $0.size }) { measured.size = $0 }
            .frame(width: 260, alignment: .leading))
        host.frame = NSRect(x: 0, y: 0, width: 260, height: 80)
        host.layoutSubtreeIfNeeded()
        settle(host)
        XCTAssertGreaterThan(measured.size.width, 0)
        XCTAssertLessThanOrEqual(measured.size.width, 260, "the chip does not spill out of a 260pt bubble")
        try Snapshot.render("attachment-narrow", width: 260) {
            FileAttachmentChip(message: message)
        }
    }

    // MARK: - 3. Mentions

    private func mentionView(quoted: Bool, onBubble: Bool, userID: String = "@ann:courier.local") -> some View {
        let text = "Ann Example"
        var entities = [TextEntity(kind: .mention, offset: 0, length: text.utf16.count, userID: userID)]
        if quoted { entities.insert(TextEntity(kind: .blockquote, offset: 0, length: text.utf16.count), at: 0) }
        return RichTextView(rich: RichText(text: text, entities: entities), onBubble: onBubble, revealed: .constant(false))
            .environment(\.courierMessagePointSize, 22)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(onBubble ? Color(red: 0.0, green: 0.40, blue: 0.80) : Color.clear)
    }

    private func linear(_ v: Double) -> Double { v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }

    private func relativeLuminance(_ c: NSColor) -> Double {
        0.2126 * linear(Double(c.redComponent)) + 0.7152 * linear(Double(c.greenComponent)) + 0.0722 * linear(Double(c.blueComponent))
    }

    /// The contrast between the mention's text (the pixel furthest from its background) and its tint: the second most
    /// common colour in the picture, after the plain background around it.
    private func mentionContrast(_ name: String, _ suffix: String) throws -> Double {
        let url = Snapshot.directory.appendingPathComponent("\(name)-\(suffix).png")
        let rep = try XCTUnwrap(NSBitmapImageRep(data: Data(contentsOf: url)))
        var counts: [String: (Int, NSColor)] = [:]
        var all: [NSColor] = []
        for y in 0 ..< rep.pixelsHigh {
            for x in 0 ..< rep.pixelsWide {
                guard let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
                let key = String(format: "%.3f/%.3f/%.3f", c.redComponent, c.greenComponent, c.blueComponent)
                counts[key] = ((counts[key]?.0 ?? 0) + 1, c)
                all.append(c)
            }
        }
        let ranked = counts.values.sorted { $0.0 > $1.0 }
        XCTAssertGreaterThanOrEqual(ranked.count, 2)
        let tint = relativeLuminance(ranked[1].1)
        let text = all.map(relativeLuminance).max { abs($0 - tint) < abs($1 - tint) } ?? tint
        let (hi, lo) = (max(text, tint), min(text, tint))
        return (hi + 0.05) / (lo + 0.05)
    }

    func testMentionsAreReadableOnTheirTintInLightAndDark() throws {
        // Plain, quoted, and the person's own (@me) mention take the same path; on my own accent bubble too.
        for (onBubble, quoted, userID) in [(false, false, "@ann:courier.local"), (false, true, "@ann:courier.local"),
                                           (false, false, Timeline.meUserID), (true, false, "@ann:courier.local"),
                                           (true, true, "@ann:courier.local")] {
            let name = "mention-\(onBubble ? "bubble" : "plain")-\(quoted ? "quoted" : "flat")-\(userID == Timeline.meUserID ? "me" : "other")"
            try Snapshot.render(name, width: 300) { mentionView(quoted: quoted, onBubble: onBubble, userID: userID) }
            for suffix in ["light", "dark"] {
                let ratio = try mentionContrast(name, suffix)
                XCTAssertGreaterThanOrEqual(ratio, 4.5, "\(name)-\(suffix): text against its tint is \(ratio):1")
            }
        }
    }

    func testLinksInsideAQuoteStaySofterThanLinksOutsideIt() throws {
        let text = "docs"
        let link = TextEntity(kind: .link, offset: 0, length: text.utf16.count, url: "https://example.org")
        func render(_ name: String, quoted: Bool) throws -> Double {
            let entities = quoted ? [TextEntity(kind: .blockquote, offset: 0, length: 4), link] : [link]
            try Snapshot.render(name, width: 200) {
                RichTextView(rich: RichText(text: text, entities: entities), onBubble: false, revealed: .constant(false))
                    .environment(\.courierMessagePointSize, 22).padding(12)
            }
            return try luminances(name, "light").min() ?? 1
        }
        XCTAssertGreaterThan(try render("link-quoted", quoted: true), try render("link-flat", quoted: false),
                             "a link in a quote is dimmed as it always was")
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

    func testTheVideoPictureIsFetchedOnlyWhenExternalContentIsAllowed() throws {
        let descriptor = try XCTUnwrap(ExternalEmbedDescriptor.match(urlString: "https://youtu.be/Zx9Qk3LmN-_"))
        EmbedThumbnail.clearCache()
        let rep = try XCTUnwrap(NSBitmapImageRep(data: try XCTUnwrap(NSImage(size: NSSize(width: 16, height: 9), flipped: false) { rect in
            NSColor(srgbRed: 1, green: 0, blue: 0, alpha: 1).setFill(); rect.fill(); return true
        }.tiffRepresentation)))
        EmbedCountingURLProtocol.reset(body: try XCTUnwrap(rep.representation(using: .png, properties: [:])))
        let session = EmbedCountingURLProtocol.session()

        try Snapshot.render("embed-remote-off", width: 360, prepare: settle) {
            EmbedConsentCard(messageID: "$e", descriptor: descriptor, isLoaded: false, allowsRemoteThumbnail: false,
                             session: session, onLoadEmbed: {}).padding(14)
        }
        XCTAssertEqual(EmbedCountingURLProtocol.requests, [], "external content off: nothing is requested")
        for suffix in ["light", "dark"] { XCTAssertEqual(try redPixelCount("embed-remote-off", suffix), 0) }

        try Snapshot.render("embed-remote-on", width: 360, prepare: settle) {
            EmbedConsentCard(messageID: "$e", descriptor: descriptor, isLoaded: false, allowsRemoteThumbnail: true,
                             session: session, onLoadEmbed: {}).padding(14)
        }
        // Light and dark each draw the card; the second comes from memory, so the site is asked once.
        XCTAssertEqual(EmbedCountingURLProtocol.requests, ["https://i.ytimg.com/vi/Zx9Qk3LmN-_/mqdefault.jpg"])
        XCTAssertGreaterThan(try redPixelCount("embed-remote-on", "light"), 100, "the fetched picture is drawn")
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

/// Answers every request with a small picture and remembers what was asked for.
final class EmbedCountingURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var requests: [String] = []
    nonisolated(unsafe) static var body = Data()
    private static let lock = NSLock()

    static func reset(body: Data) {
        lock.lock(); defer { lock.unlock() }
        requests = []
        self.body = body
    }

    static func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [EmbedCountingURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lock.lock()
        Self.requests.append(request.url?.absoluteString ?? "")
        let body = Self.body
        Self.lock.unlock()
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
