// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import XCTest
@testable import VitruvianCourierCore

/// The chat list's reaction preview ("Kent reacted 😂 to “…”") and the group avatar drawn from the engine's members.
final class ReactionPreviewAndMembersTests: XCTestCase {
    private func row(name: String, direct: Bool, kind: PreviewKind = .text, preview: String = "hi",
                     mine: Bool = false, sender: String = "", members: [RowMember] = []) -> InboxRow {
        InboxRow(roomID: "!r", network: "gchat", name: name, avatarPath: "", isDirect: direct, lastTS: 0,
                 preview: preview, previewKind: kind, previewMine: mine, unread: 0, muted: false,
                 previewSenderName: sender, memberPreview: members)
    }

    func testReactionPreviewNamesWhoReacted() {
        let body = "😂 to “Maybe in his mind…”"
        XCTAssertEqual(row(name: "Eddie, Kent", direct: false, kind: .reaction, preview: body, sender: "Kent")
            .formattedPreviewText, "Kent reacted " + body)
        XCTAssertEqual(row(name: "Florian", direct: true, kind: .reaction, preview: body, sender: "Florian")
            .formattedPreviewText, "Reacted " + body)
        XCTAssertEqual(row(name: "Florian", direct: true, kind: .reaction, preview: body, mine: true)
            .formattedPreviewText, "You reacted " + body)
        XCTAssertNil(row(name: "Florian", direct: true).reactionPreviewLead)
    }

    func testEngineMembersBeatTheNameButNotAChannel() {
        let members = [RowMember(userID: "@k", name: "Kent Hua", avatarPath: "/tmp/k.jpg"),
                       RowMember(userID: "@e", name: "Eddie Stecker", avatarPath: nil)]
        guard case let .people(people) = row(name: "Weekend plans", direct: false, members: members).groupAvatarStyle
        else { return XCTFail("expected people") }
        XCTAssertEqual(people.map(\.name), ["Kent Hua", "Eddie Stecker"])
        XCTAssertEqual(people.first?.avatarPath, "/tmp/k.jpg")
        XCTAssertEqual(row(name: "#data-science", direct: false, members: members).groupAvatarStyle,
                       .channel("#data-science"))
        XCTAssertEqual(row(name: "Weekend plans", direct: false).groupAvatarStyle, .single)
    }
}
