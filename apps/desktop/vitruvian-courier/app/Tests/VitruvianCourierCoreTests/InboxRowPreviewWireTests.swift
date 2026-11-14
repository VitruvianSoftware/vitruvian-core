// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import XCTest

@testable import VitruvianCourierCore

/// InboxRow's optional preview fields (preview_sender_name, members_preview) and the reaction preview kind: an
/// engine that sends them, one before them that leaves them out, and a kind not known yet.
final class InboxRowPreviewWireTests: XCTestCase {
    private func row(_ extra: String) throws -> InboxRow {
        let json = """
        {"room_id":"!g","network":"gchat","name":"Group","avatar_path":"","is_direct":false,"last_ts":1,
         "preview":"😂 to “hi”","preview_kind":"\(extra.isEmpty ? "reaction" : "future_kind")","preview_mine":false,
         "preview_in_thread":false,"unread":0,"muted":false,"pinned":false,"archived":false,"low_priority":false,
         "hidden":false,"marked_unread":false,"request":false,"draft":"","labels":[],"muted_by":"","muted_by_name":"",
         "reminder":null,"typing":[],"unread_mentions":0,"preview_media_path":"","preview_call":null,
         "preview_status":"","login_name":""\(extra)}
        """
        return try JSONDecoder().decode(InboxRow.self, from: Data(json.utf8))
    }

    func testAnOlderEngineLeavesThemOut() throws {
        let r = try row("")
        XCTAssertEqual(r.previewKind, .reaction)
        XCTAssertEqual(r.previewSenderName, "")
        XCTAssertEqual(r.memberPreview, [])
    }

    func testTheyDecodeAndRoundTrip() throws {
        let r = try row("""
        ,"preview_sender_name":"Kent","members_preview":[
          {"user_id":"@a","name":"Alice","avatar_path":"/tmp/a"},{"user_id":"@b","name":"Bob","avatar_path":""}]
        """)
        XCTAssertEqual(r.previewKind.rawValue, "future_kind", "a kind not known yet still decodes")
        XCTAssertEqual(r.previewSenderName, "Kent")
        XCTAssertEqual(r.memberPreview, [RowMember(userID: "@a", name: "Alice", avatarPath: "/tmp/a"),
                                         RowMember(userID: "@b", name: "Bob")])
        XCTAssertNil(r.memberPreview[1].avatarPath, "\"\" is no picture")
        let again = try JSONDecoder().decode(InboxRow.self, from: JSONEncoder().encode(r))
        XCTAssertEqual(again, r)
    }
}
