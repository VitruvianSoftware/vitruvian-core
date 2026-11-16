// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import AppKit
import VitruvianCourierCore
import SwiftUI
import XCTest

@testable import VitruvianCourier

/// The Beeper-like bubble look: saturated outgoing vs neutral incoming, the time inside each bubble, the sender's name
/// inside the first incoming bubble of a group cluster, links in the bubble's text colour with a small arrow, and
/// large pictures (sized from the file when the message has no width/height). Look at bubble-beeper-*, image-large-*.
@MainActor
final class BubbleBeeperLookSnapshotTests: XCTestCase {
    private func appearance() -> AppearancePreferences {
        let name = "test.courier.bubble.look.\(UUID().uuidString)"
        let prefs = AppearancePreferences(defaults: ScratchDefaults.suite(named: name)!)
        prefs.themePreset = .slate
        return prefs
    }

    private func timeline(_ events: [Event], direct: Bool, showTimes: Bool = true) -> some View {
        let ui = MessageUI()
        var actions = VitruvianCourier.MessageActions(now: { Fixture.now })
        actions.appearance = appearance()
        actions.showMessageTimestamps = showTimes
        return VStack(spacing: 0) {
            ForEach(Fixture.items(events, isDirect: direct)) { item in
                TimelineItemView(item: item, isSelected: false, showsSent: false, actions: actions, ui: ui)
            }
        }
        .padding(14)
    }

    private var events: [Event] {
        [
            Fixture.text("$b1", "Are we still on for the hike on Saturday? I can drive if you want, the trailhead is about forty minutes out of town.", mine: false, ts: 9),
            Fixture.text("$b2", "Hi!", mine: false, ts: 8),
            Fixture.text("$b3", "Yes, see you at eight. Route: https://example.com/trails/ridge-loop", mine: true, ts: 4),
            Fixture.text("$b4", "Great", mine: true, ts: 3),
            Fixture.text("$b5", "Bring water!", mine: false, ts: 2, sender: "@bo:courier.local", name: "Bo Example"),
        ]
    }

    func testGroupLook() throws {
        let sizes = try Snapshot.render("bubble-beeper-group", width: 620) { timeline(events, direct: false) }
        XCTAssertEqual(sizes.count, 2)
    }

    /// A long sender name in a narrow window truncates inside its bubble; it doesn't push the bubble wider.
    func testLongSenderNameInANarrowBubbleTruncates() throws {
        let long = "Alexandrina Wolfeschlegelsteinhausenbergerdorff-Montgomery the Third"
        let events = [
            Fixture.text("$n1", "On my way.", mine: false, ts: 5, sender: "@alex:courier.local", name: long),
            Fixture.text("$n2", "See you there", mine: true, ts: 4),
            Fixture.text("$n3", "A reply that is long enough to wrap onto a second line in this narrow window.",
                         mine: false, ts: 2, sender: "@alex:courier.local", name: long),
        ]
        let sizes = try Snapshot.render("bubble-long-sender-name-narrow", width: 260) { timeline(events, direct: false) }
        XCTAssertEqual(sizes.count, 2)
        for size in sizes { XCTAssertEqual(size.width, 260) }
        // The row, measured: the bubble stays inside the window (14 pt padding each side).
        let host = NSHostingView(rootView: timeline(events, direct: false).frame(width: 260).fixedSize(horizontal: false, vertical: true))
        XCTAssertLessThanOrEqual(host.fittingSize.width, 260, "the name doesn't widen the row past the window")
    }

    /// A link with an embed card (YouTube) is drawn as that one card, carrying the preview's title, not also as a
    /// link card for the same address; other links in the message keep theirs.
    func testAnEmbeddedLinkGetsOneCardNotTwo() throws {
        let youtube = "https://www.youtube.com/watch?v=dQw4w9WgXcQ"
        let article = "https://example.org/article"
        var event = Fixture.text("$yt", "\(youtube) and \(article)", mine: true, ts: 3)
        event.linkPreviews = [
            LinkPreviewItem(matchedURL: youtube, url: youtube, title: "Never Gonna Give You Up", siteName: "YouTube"),
            LinkPreviewItem(matchedURL: article, url: article, title: "An article", siteName: "example.org"),
        ]
        let items = Fixture.items([event], isDirect: false)
        var message: TimelineMessage?
        for case let .message(m) in items { message = m }
        let shown = try XCTUnwrap(message)
        XCTAssertNotNil(ExternalEmbedDescriptor.first(in: shown))
        XCTAssertEqual(ExternalEmbedDescriptor.cardPreviews(in: shown).map(\.title), ["An article"],
                       "the YouTube preview is not drawn as a second card")
        XCTAssertEqual(ExternalEmbedDescriptor.embedTitle(in: shown), "Never Gonna Give You Up")

        var plain = Fixture.text("$pl", article, mine: false, ts: 2)
        plain.linkPreviews = [LinkPreviewItem(matchedURL: article, url: article, title: "An article")]
        for case let .message(m) in Fixture.items([plain], isDirect: false) {
            XCTAssertEqual(ExternalEmbedDescriptor.cardPreviews(in: m).count, 1, "no embed: every preview is a card")
            XCTAssertNil(ExternalEmbedDescriptor.embedTitle(in: m))
        }
        _ = try Snapshot.render("bubble-embed-single-card", width: 420) { timeline([event], direct: false) }
    }

    func testDirectLookNoTimestamps() throws {
        let sizes = try Snapshot.render("bubble-beeper-direct-notimes", width: 620) {
            timeline(events, direct: true, showTimes: false)
        }
        XCTAssertEqual(sizes.count, 2)
    }

    /// A bridged picture with no width/height in its event is sized from the file, up to 400 pt, not a 240x180 box.
    func testImageWithoutDimensionsUsesFileSize() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("courier-img-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("wide.png")
        let image = NSImage(size: NSSize(width: 1200, height: 600), flipped: false) { rect in
            NSGradient(colors: [.systemTeal, .systemIndigo])?.draw(in: rect, angle: 30)
            return true
        }
        let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
        try rep.representation(using: .png, properties: [:])!.write(to: url)

        let size = ImagePixelSizeReader.read(url.path)
        XCTAssertEqual(size?.width, 1200)
        XCTAssertEqual(size?.height, 600)

        var event = Fixture.mediaEvent("$img1", msgtype: "m.image", body: "wide.png", ts: 3)
        event.mediaPath = url.path
        let sized = EnhancedImageView.proportionalSize(width: 1200, height: 600)
        XCTAssertEqual(sized.width, 400)
        XCTAssertEqual(sized.height, 200)
        XCTAssertEqual(EnhancedImageView.longestSide, 400)

        let sizes = try Snapshot.render("image-large", width: 620) { timeline([event], direct: false) }
        XCTAssertEqual(sizes.count, 2)
    }
}
