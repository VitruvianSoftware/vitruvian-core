// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import AppKit
import VitruvianCourierCore
import SwiftUI
import XCTest

@testable import VitruvianCourier

@MainActor
final class SizeBox { var size = CGSize.zero }

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

    private func chip(_ message: TimelineMessage) -> some View {
        FileAttachmentChip(message: message).frame(maxWidth: .infinity, alignment: .leading).padding(10)
    }

    private func fileMessage(_ name: String, id: String) throws -> TimelineMessage {
        var event = Fixture.event(id, mine: false, ts: 25, content: [
            "msgtype": .string("m.file"), "body": .string(name), "filename": .string(name),
            "info": .object(["mimetype": .string("text/html"), "size": .int(48_000)]),
        ], name: "Alice Example")
        event.mediaPath = ""
        return try XCTUnwrap(Fixture.messages([event]).first)
    }

    /// Whether two renders draw the same pixels in the name's column (x in points from the left edge of each).
    private func nameColumnMatches(_ a: String, widthA: CGFloat, _ b: String, widthB: CGFloat) throws -> Bool {
        func rep(_ name: String) throws -> NSBitmapImageRep {
            try XCTUnwrap(NSBitmapImageRep(data: Data(contentsOf: Snapshot.directory.appendingPathComponent("\(name)-light.png"))))
        }
        let (ra, rb) = (try rep(a), try rep(b))
        let (sa, sb) = (Double(ra.pixelsWide) / widthA, Double(rb.pixelsWide) / widthB)
        XCTAssertEqual(sa, sb, accuracy: 0.01)
        let height = min(ra.pixelsHigh, rb.pixelsHigh)
        // The name starts after the picture's padding, the chip's padding, its badge and the gap: 66pt.
        for y in 0 ..< height {
            for x in Int(66 * sa) ..< Int(166 * sa) {
                guard let ca = ra.colorAt(x: x, y: y)?.usingColorSpace(.sRGB),
                      let cb = rb.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
                if abs(ca.redComponent - cb.redComponent) > 0.01 || abs(ca.greenComponent - cb.greenComponent) > 0.01
                    || abs(ca.blueComponent - cb.blueComponent) > 0.01 { return false }
            }
        }
        return true
    }

    func testANameThatFitsIsShownInFullAndALongOneLosesItsMiddle() throws {
        XCTAssertEqual(FileAttachmentChip.nameTruncation, .middle)
        let medium = try fileMessage("Report_final.html", id: "$file-medium")
        let long = try fileMessage("bucket_pipeline_monkey_report_with_a_very_long_name_indeed.html", id: "$file-long2")
        // The reference is a chip with more room than any name needs.
        try Snapshot.render("chip-medium-wide", width: 480) { chip(medium) }
        try Snapshot.render("chip-medium-fits", width: 380) { chip(medium) }
        try Snapshot.render("chip-medium-tight", width: 230) { chip(medium) }
        XCTAssertTrue(try nameColumnMatches("chip-medium-fits", widthA: 380, "chip-medium-wide", widthB: 480),
                      "a name that fits is drawn whole")
        XCTAssertFalse(try nameColumnMatches("chip-medium-tight", widthA: 230, "chip-medium-wide", widthB: 480),
                       "with no room the same name is cut (so the check above can tell)")
        try Snapshot.render("chip-long-wide", width: 480) { chip(long) }
        try Snapshot.render("chip-long-narrow", width: 300) { chip(long) }
        XCTAssertFalse(try nameColumnMatches("chip-long-narrow", widthA: 300, "chip-long-wide", widthB: 480),
                       "a long name is cut when the bubble is narrow")
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

    /// A colour as the view resolves it under an appearance (sRGB, with its opacity).
    private func resolved(_ color: NSColor, _ appearance: NSAppearance.Name) -> NSColor {
        var out = color
        NSAppearance(named: appearance)!.performAsCurrentDrawingAppearance {
            out = color.usingColorSpace(.sRGB) ?? color
        }
        return out
    }

    private func over(_ top: NSColor, _ bottom: NSColor) -> NSColor {
        let a = top.alphaComponent
        return NSColor(srgbRed: top.redComponent * a + bottom.redComponent * (1 - a),
                       green: top.greenComponent * a + bottom.greenComponent * (1 - a),
                       blue: top.blueComponent * a + bottom.blueComponent * (1 - a), alpha: 1)
    }

    private func pixelsNear(_ color: NSColor, _ name: String, _ suffix: String) throws -> Int {
        let rep = try XCTUnwrap(NSBitmapImageRep(data: Data(contentsOf: Snapshot.directory.appendingPathComponent("\(name)-\(suffix).png"))))
        var count = 0
        for y in 0 ..< rep.pixelsHigh {
            for x in 0 ..< rep.pixelsWide {
                guard let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
                if abs(c.redComponent - color.redComponent) < 0.08, abs(c.greenComponent - color.greenComponent) < 0.08,
                   abs(c.blueComponent - color.blueComponent) < 0.08 { count += 1 }
            }
        }
        return count
    }

    private func dominantColour(_ name: String, _ suffix: String) throws -> NSColor {
        let rep = try XCTUnwrap(NSBitmapImageRep(data: Data(contentsOf: Snapshot.directory.appendingPathComponent("\(name)-\(suffix).png"))))
        var counts: [String: (Int, NSColor)] = [:]
        for y in 0 ..< rep.pixelsHigh {
            for x in 0 ..< rep.pixelsWide {
                guard let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
                let key = String(format: "%.3f,%.3f,%.3f", c.redComponent, c.greenComponent, c.blueComponent)
                counts[key] = ((counts[key]?.0 ?? 0) + 1, c)
            }
        }
        return try XCTUnwrap(counts.values.max { $0.0 < $1.0 }?.1)
    }

    private func topColours(_ name: String, _ suffix: String) throws -> [String] {
        let rep = try XCTUnwrap(NSBitmapImageRep(data: Data(contentsOf: Snapshot.directory.appendingPathComponent("\(name)-\(suffix).png"))))
        var counts: [String: Int] = [:]
        for y in 0 ..< rep.pixelsHigh {
            for x in 0 ..< rep.pixelsWide {
                guard let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
                counts[String(format: "%.3f,%.3f,%.3f", c.redComponent, c.greenComponent, c.blueComponent), default: 0] += 1
            }
        }
        return counts.sorted { $0.value > $1.value }.prefix(3).map { "\($0.key)x\($0.value)" }
    }

    func testMentionsAreReadableOnTheirTintInLightAndDark() throws {
        // Plain, quoted, and the person's own (@me) mention take the same path; on my own accent bubble too.
        let accent = EnvironmentValues().themeAccentColor
        for (onBubble, quoted, userID) in [(false, false, "@ann:courier.local"), (false, true, "@ann:courier.local"),
                                           (false, false, Timeline.meUserID), (true, false, "@ann:courier.local"),
                                           (true, true, "@ann:courier.local")] {
            let name = "mention-\(onBubble ? "bubble" : "plain")-\(quoted ? "quoted" : "flat")-\(userID == Timeline.meUserID ? "me" : "other")"
            try Snapshot.render(name, width: 300) { mentionView(quoted: quoted, onBubble: onBubble, userID: userID) }
            let colors = RichTextView.mentionColors(onBubble: onBubble, accent: accent)
            for (suffix, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
                // The colours the view resolves: its tint laid over what is really behind it (the picture's plain
                // background, which is a device colour a little off the named one), and its text laid over that tint.
                let behind = try dominantColour(name, suffix)
                let tint = over(resolved(NSColor(colors.tint), appearance), behind)
                let text = over(resolved(NSColor(colors.text), appearance), tint)
                let (hi, lo) = (max(relativeLuminance(text), relativeLuminance(tint)),
                                min(relativeLuminance(text), relativeLuminance(tint)))
                let ratio = (hi + 0.05) / (lo + 0.05)
                XCTAssertGreaterThanOrEqual(ratio, 4.5, "\(name)-\(suffix): text against its tint is \(ratio):1")
                // And the picture really has that tint (so the colours measured are the ones drawn).
                let drawn = try pixelsNear(tint, name, suffix)
                let seen = try topColours(name, suffix)
                XCTAssertGreaterThan(drawn, 200, "\(name)-\(suffix): the tint is drawn (expected \(tint), pictured \(seen))")
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

    private func solid(_ color: NSColor) throws -> CGImage {
        let image = NSImage(size: NSSize(width: 160, height: 90), flipped: false) { rect in
            color.setFill(); rect.fill(); return true
        }
        return try XCTUnwrap(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
    }

    private func count(_ rep: NSBitmapImageRep, where match: (NSColor) -> Bool) -> Int {
        var n = 0
        for y in 0 ..< rep.pixelsHigh {
            for x in 0 ..< rep.pixelsWide {
                if let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB), match(c) { n += 1 }
            }
        }
        return n
    }

    /// The first video's picture arrives after the card has moved on to a second video: it must never be drawn.
    func testALateAnswerForAnEarlierVideoIsNotDrawn() async throws {
        _ = NSApplication.shared
        let first = try XCTUnwrap(ExternalEmbedDescriptor.match(urlString: "https://youtu.be/AAAAAAAAAAA"))
        let second = try XCTUnwrap(ExternalEmbedDescriptor.match(urlString: "https://youtu.be/BBBBBBBBBBB"))
        let red = try solid(NSColor(srgbRed: 1, green: 0, blue: 0, alpha: 1))
        let blue = try solid(NSColor(srgbRed: 0, green: 0, blue: 1, alpha: 1))
        let gate = PictureGate()
        // The first video's answer waits at the gate, and does not notice it was cancelled; the second answers at once.
        let fetch: @Sendable (String) async -> CGImage? = { id in
            if id == "AAAAAAAAAAA" { await gate.wait(); return red }
            return blue
        }
        let model = EmbedModel(first)
        let host = NSHostingView(rootView: StaleHost(model: model, fetch: fetch))
        host.appearance = NSAppearance(named: .aqua)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 360, height: 90), styleMask: [.borderless],
                              backing: .buffered, defer: false)
        window.contentView = host
        host.frame = NSRect(x: 0, y: 0, width: 360, height: 90)
        host.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        settle(host)
        let waiting = await gate.waiterCount
        XCTAssertEqual(waiting, 1, "the first video's fetch is under way")
        model.descriptor = second // the card moves on while the first answer is still out
        settle(host)
        await gate.release() // now the first answer comes in
        settle(host)
        host.layoutSubtreeIfNeeded()
        let rep = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: rep)
        let reds = count(rep) { $0.redComponent > 0.85 && $0.greenComponent < 0.4 && $0.blueComponent < 0.4 }
        let blues = count(rep) { $0.blueComponent > 0.85 && $0.redComponent < 0.4 && $0.greenComponent < 0.4 }
        XCTAssertGreaterThan(blues, 100, "the second video's picture is drawn")
        XCTAssertEqual(reds, 0, "the first video's late picture is dropped")
        window.contentView = nil
    }

    func testAPictureLoadedForAnotherSourceIsNeverDrawn() throws {
        let red = try solid(NSColor(srgbRed: 1, green: 0, blue: 0, alpha: 1))
        XCTAssertNil(EmbedConsentCard.visibleThumbnail(("youtube:AAAAAAAAAAA", red), currentSource: "youtube:BBBBBBBBBBB"))
        XCTAssertNil(EmbedConsentCard.visibleThumbnail(("", red), currentSource: ""))
        XCTAssertNil(EmbedConsentCard.visibleThumbnail(nil, currentSource: "youtube:AAAAAAAAAAA"))
        XCTAssertNotNil(EmbedConsentCard.visibleThumbnail(("youtube:AAAAAAAAAAA", red), currentSource: "youtube:AAAAAAAAAAA"))
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

/// Holds callers until released, and ignores cancellation (as a slow answer that is already on its way does).
actor PictureGate {
    private var isOpen = false
    private var waiting: [CheckedContinuation<Void, Never>] = []
    var waiterCount: Int { waiting.count }

    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { waiting.append($0) }
    }

    func release() {
        isOpen = true
        waiting.forEach { $0.resume() }
        waiting = []
    }
}

@MainActor
final class EmbedModel: ObservableObject {
    @Published var descriptor: ExternalEmbedDescriptor
    init(_ descriptor: ExternalEmbedDescriptor) { self.descriptor = descriptor }
}

struct StaleHost: View {
    @ObservedObject var model: EmbedModel
    let fetch: @Sendable (String) async -> CGImage?

    var body: some View {
        EmbedConsentCard(messageID: "$e", descriptor: model.descriptor, isLoaded: false, allowsRemoteThumbnail: true,
                         fetchPicture: fetch, onLoadEmbed: {})
            .padding(14)
    }
}
