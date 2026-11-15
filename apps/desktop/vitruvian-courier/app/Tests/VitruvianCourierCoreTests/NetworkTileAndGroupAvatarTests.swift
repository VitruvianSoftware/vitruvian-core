// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import XCTest

@testable import VitruvianCourierCore

final class NetworkTileAndGroupAvatarTests: XCTestCase {
    private func row(_ name: String, direct: Bool = false, mine: Bool = false, inThread: Bool = false) -> InboxRow {
        InboxRow(roomID: "!r", network: "slack", name: name, avatarPath: "", isDirect: direct, lastTS: 1,
                 preview: "hi", previewKind: .text, previewMine: mine, unread: 0, muted: false,
                 previewInThread: inThread)
    }

    // MARK: Network tiles

    func testEveryNetworkHasItsOwnTile() {
        var seen = Set<String>()
        for network in NetworkTile.knownNetworks {
            let tile = NetworkTile.of(network)
            XCTAssertNotEqual(tile, NetworkTile.fallback, "\(network) has a tile of its own")
            XCTAssertFalse(tile.glyph.isEmpty, network)
            seen.insert("\(tile.glyph)/\(tile.top)/\(tile.bottom)")
            // The badge and the tile agree on which networks are known.
            XCTAssertNotEqual(NetworkAppearance.of(network), NetworkAppearance.fallback, network)
        }
        XCTAssertEqual(seen.count, NetworkTile.knownNetworks.count, "no two networks share a tile")
        XCTAssertEqual(NetworkTile.of("a-network-added-later"), NetworkTile.fallback)
    }

    func testNoTwoNetworksShareABrandColourAndGlyphPair() {
        // Two networks may share a glyph (a bubble) or a hue, never both.
        let pairs = NetworkTile.knownNetworks.map { NetworkTile.of($0) }
        for (i, a) in pairs.enumerated() {
            for b in pairs[(i + 1)...] {
                XCTAssertFalse(a.glyph == b.glyph && a.top == b.top)
            }
        }
    }

    func testBrandColoursAreTheDocumentedOnes() {
        XCTAssertEqual(NetworkTile.of("whatsapp").top, NetworkTile.RGB(hex: 0x25D366))
        XCTAssertEqual(NetworkTile.of("telegram").glyph, "paperplane.fill")
        XCTAssertNotEqual(NetworkTile.of("facebook").top, NetworkTile.of("facebook").bottom, "Messenger is a gradient")
        XCTAssertEqual(NetworkTile.of("slack").top, NetworkTile.RGB(hex: 0x4A154B))
    }

    // MARK: Group avatars

    func testAGroupNamedForItsPeopleShowsThem() {
        let style = row("Eddie Stecker, Kent Hua, GitHub").groupAvatarStyle
        XCTAssertEqual(style, .people([AvatarMember(name: "Eddie Stecker"), AvatarMember(name: "Kent Hua"),
                                       AvatarMember(name: "GitHub")]))
        XCTAssertEqual(row("Ann & Bo").groupAvatarStyle, .people([AvatarMember(name: "Ann"), AvatarMember(name: "Bo")]))
        if case let .people(people) = row("A, B, C, D, E").groupAvatarStyle {
            XCTAssertEqual(people.map(\.name), ["A", "B", "C"], "three at most")
        } else {
            XCTFail("a list of five names is people")
        }
    }

    func testAChannelIsATileNotPeople() {
        XCTAssertEqual(row("#data-science").groupAvatarStyle, .channel("#data-science"))
        XCTAssertNotEqual(row("#data-science").groupAvatarStyle, row("#general").groupAvatarStyle,
                          "each channel is told apart")
    }

    func testAnyOtherGroupNameIsASingleMark() {
        XCTAssertEqual(row("Weekend Hikers").groupAvatarStyle, .single)
        XCTAssertEqual(row("Dinner on Friday, if everyone can make it that late").groupAvatarStyle, .single,
                       "a sentence with a comma is not a list of people")
        XCTAssertEqual(row("#").groupAvatarStyle, .single)
    }

    // MARK: Thread preview

    func testThreadSenderFollowsTheCompactGlyph() {
        XCTAssertEqual(row("Ann", direct: true, inThread: true).previewThreadSender, "Ann: ")
        XCTAssertEqual(row("Ann", direct: true, mine: true, inThread: true).previewThreadSender, "You: ")
        XCTAssertNil(row("Hikers", inThread: true).previewThreadSender, "a group's sender isn't known")
        XCTAssertNil(row("Ann", direct: true).previewThreadSender, "not a thread reply")
    }
}
