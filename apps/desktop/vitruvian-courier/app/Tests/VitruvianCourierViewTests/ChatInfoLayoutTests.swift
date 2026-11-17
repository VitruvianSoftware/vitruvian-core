// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import AppKit
import SwiftUI
import XCTest

@testable import VitruvianCourier
import VitruvianCourierCore

/// What Chat Info shows and how it is laid out: its grouped boxes, the five quick actions at every width, and what
/// each box says. The PNGs the renders write (`chat-info-grouped-*`) are for a person to look at.
@MainActor
final class ChatInfoLayoutTests: XCTestCase {
    private final class Probes {
        var rows: [String] = []
        var rects: [String: NSRect] = [:]
    }

    private func render(_ name: String, info: RoomInfoResult, bookmarks: [MessageHit] = [], width: CGFloat,
                        readAloud: ChatReadAloud? = .default, probes: Probes) throws {
        try Snapshot.render(name, width: width) {
            ChatInfoPane(
                info: info, bookmarks: bookmarks, now: { Fixture.now }, readAloud: readAloud,
                onMergeChat: {}, onSummarizeChat: {}
            )
            .environment(\.chatInfoRowProbe) { probes.rows.append($0) }
            .environment(\.chatInfoQuickActionProbe) { title, rect in
                if let rect, !rect.isEmpty { probes.rects[title] = rect }
            }
        }
    }

    private func mapsLinkChat() -> RoomInfoResult {
        var info = Fixture.directChatInfo()
        info.sharedLinks = [
            RoomLink(eventID: "$l1", sender: "@wa_alice:courier.local", ts: Fixture.millis(15),
                     url: "https://example.com/trail-guide", host: "example.com"),
            RoomLink(eventID: "$l2", sender: "@wa_alice:courier.local", ts: Fixture.millis(5),
                     url: "https://maps.app.goo.gl/kX9abc123", host: "maps.app.goo.gl"),
        ]
        return info
    }

    /// The Shared box shows photos, videos and links together, a Maps link among them; Bookmarks lists this chat's
    /// bookmarked messages; Contact has the phone number; Privacy says WhatsApp is encrypted on WhatsApp's side.
    func testGroupedSectionsShowWhatEachOneIsFor() throws {
        let probes = Probes()
        try render("chat-info-grouped", info: mapsLinkChat(), bookmarks: Fixture.chatInfoBookmarks(), width: 300, probes: probes)
        XCTAssertTrue(probes.rows.contains("link:https://maps.app.goo.gl/kX9abc123"), "the Maps link: \(probes.rows)")
        // Four tiles at most, newest first: the Maps link and the three photos and videos; the older link waits in Show All.
        XCTAssertFalse(probes.rows.contains("link:https://example.com/trail-guide"), "only the newest four: \(probes.rows)")
        XCTAssertTrue(probes.rows.contains { $0.hasPrefix("bookmark:Alice Example:Don’t forget the trail pass") }, "\(probes.rows)")
        XCTAssertTrue(probes.rows.contains("contact:Phone=+1 555-010-0101"), "\(probes.rows)")
        XCTAssertTrue(probes.rows.contains("encryption:End-to-end encrypted on WhatsApp"), "\(probes.rows)")
        XCTAssertFalse(probes.rows.contains { $0.hasPrefix("encryption:Not end-to-end") }, "\(probes.rows)")
    }

    func testAnEncryptedOnlyOnTheBridgeWhatsAppChatIsNotCalledUnencrypted() throws {
        var info = Fixture.directChatInfo()
        info.encrypted = false
        let probes = Probes()
        try render("chat-info-grouped-whatsapp-room-unflagged", info: info, width: 300, probes: probes)
        XCTAssertTrue(probes.rows.contains("encryption:End-to-end encrypted on WhatsApp"), "\(probes.rows)")

        info.network = "slack"
        info.encrypted = false
        let slack = Probes()
        try render("chat-info-grouped-slack", info: info, width: 300, probes: slack)
        XCTAssertTrue(slack.rows.contains("encryption:Not end-to-end encrypted on Slack"), "\(slack.rows)")
    }

    func testAChatWithNothingSharedOrBookmarkedSaysWhereTheyWillAppear() throws {
        var info = Fixture.directChatInfo()
        info.sharedMedia = []
        info.sharedLinks = []
        let probes = Probes()
        try render("chat-info-grouped-empty", info: info, bookmarks: [], width: 300, probes: probes)
        XCTAssertFalse(probes.rows.contains { $0.hasPrefix("bookmark:") || $0.hasPrefix("link:") })
        XCTAssertTrue(probes.rows.contains("empty:Bookmarked messages appear here."), "\(probes.rows)")
        XCTAssertTrue(probes.rows.contains("empty:Photos, videos and links shared in this chat appear here."), "\(probes.rows)")
    }

    /// All five quick-action labels fit their buttons, at the pane's narrowest (280 pt) and at the width it opens at
    /// (340 pt): "Remind…" was cut off while "Mute", "Pin", "Archive" and "Search" fit.
    func testQuickActionLabelsAreAllWholeAtTheMinimumAndDefaultWidths() throws {
        let font = NSFont.preferredFont(forTextStyle: .caption1)
        for width: CGFloat in [280, 340] {
            let probes = Probes()
            try render("chat-info-quick-actions-\(Int(width))", info: Fixture.directChatInfo(), width: width, probes: probes)
            let titles = ["Mute", "Pin", "Archive", "Remind…", "Search"]
            for title in titles {
                let rect = try XCTUnwrap(probes.rects[title], "no button \(title) at \(width) pt: \(probes.rects.keys)")
                let label = ChatInfoQuickActionMetrics.visibleLabel(for: title)
                let natural = (label as NSString).size(withAttributes: [.font: font]).width
                // With 4 pt to spare on each side: a label that only just fits is cut off by the first font tweak.
                XCTAssertLessThanOrEqual(
                    natural, rect.width - 8, "“\(label)” needs \(natural) pt in a \(rect.width) pt button at \(width) pt wide")
            }
            let widths = titles.compactMap { probes.rects[$0]?.width }
            XCTAssertLessThanOrEqual((widths.max() ?? 0) - (widths.min() ?? 0), 1, "five equal buttons: \(widths)")
        }
    }

    /// The label under the icon of the one action that asks for more input drops its ellipsis; the name its help
    /// and VoiceOver give it keeps it.
    func testRemindLabelIsShortWhileItsNameKeepsTheEllipsis() {
        XCTAssertEqual(ChatInfoQuickActionMetrics.visibleLabel(for: "Remind…"), "Remind")
        XCTAssertEqual(ChatInfoQuickActionMetrics.visibleLabel(for: "Archive"), "Archive")
    }
}
