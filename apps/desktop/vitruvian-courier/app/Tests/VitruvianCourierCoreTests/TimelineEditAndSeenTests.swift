// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import XCTest

@testable import VitruvianCourierCore

/// An edit that turns a message into a picture, and how the Seen line reads. All data here is made up.
final class TimelineEditAndSeenTests: XCTestCase {
    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.locale = Locale(identifier: "en_US")
        return calendar
    }

    private func json(_ text: String) -> JSONValue {
        try! JSONDecoder().decode(JSONValue.self, from: Data(text.utf8))
    }

    private func event(_ id: String, ts: Int64, content: String, media: String = "",
                       thumbnail: String? = nil) -> Event {
        Event(eventID: id, roomID: "!room", sender: "@florian:example.test", senderName: "Florian", mine: false,
              type: "m.room.message", content: json(content), ts: ts, seq: ts, status: .sent, mediaPath: media,
              thumbnailPath: thumbnail)
    }

    private func messages(_ events: [Event]) -> [TimelineMessage] {
        Timeline.build(events: events, me: Timeline.meUserID, calendar: utc)
            .compactMap { if case let .message(m) = $0 { m } else { nil } }
    }

    // MARK: - Edits that carry a file

    func testTextEditedToAPictureShowsThePictureWithItsCaption() {
        // Google Messages: a picture shared from WhatsApp comes as its caption, then an edit that adds the picture.
        let base = event("$1", ts: 1, content: #"{"msgtype":"m.text","body":"Look at this"}"#)
        let edit = event("$2", ts: 2, content: """
        {"msgtype":"m.image","body":"* Look at this",
         "m.new_content":{"msgtype":"m.image","body":"Look at this","filename":"17219.jpg",
                          "url":"mxc://example.test/abc","info":{"mimetype":"image/jpeg","w":640,"h":480,"size":1234}},
         "m.relates_to":{"rel_type":"m.replace","event_id":"$1"}}
        """, media: "/media/17219.jpg", thumbnail: "/media/17219-thumb.jpg")
        let shown = messages([base, edit])
        XCTAssertEqual(shown.count, 1)
        let message = shown[0]
        XCTAssertEqual(message.kind, .image)
        XCTAssertEqual(message.body, "Look at this")
        XCTAssertEqual(message.fileName, "17219.jpg")
        XCTAssertEqual(message.mimeType, "image/jpeg")
        XCTAssertEqual(message.width, 640)
        XCTAssertEqual(message.height, 480)
        XCTAssertEqual(message.mediaPath, "/media/17219.jpg")
        XCTAssertEqual(message.thumbnailPath, "/media/17219-thumb.jpg")
        XCTAssertTrue(message.isEdited)
    }

    func testAPictureWhoseCaptionIsTheFileNameHasNoCaption() {
        let base = event("$1", ts: 1, content: #"{"msgtype":"m.text","body":"17219.jpg"}"#)
        let edit = event("$2", ts: 2, content: """
        {"msgtype":"m.image","body":"* 17219.jpg",
         "m.new_content":{"msgtype":"m.image","body":"17219.jpg","filename":"17219.jpg","url":"mxc://example.test/abc",
                          "info":{"mimetype":"image/jpeg"}},
         "m.relates_to":{"rel_type":"m.replace","event_id":"$1"}}
        """, media: "/media/17219.jpg")
        let message = messages([base, edit])[0]
        XCTAssertEqual(message.kind, .image)
        XCTAssertEqual(message.body, "")
    }

    func testAPictureRecaptionedKeepsItsFile() {
        let base = event("$1", ts: 1, content: """
        {"msgtype":"m.image","body":"Old","filename":"a.jpg","url":"mxc://example.test/a",
         "info":{"mimetype":"image/jpeg","w":10,"h":20}}
        """, media: "/media/a.jpg")
        let edit = event("$2", ts: 2, content: """
        {"msgtype":"m.image","body":"* New","m.new_content":{"msgtype":"m.image","body":"New"},
         "m.relates_to":{"rel_type":"m.replace","event_id":"$1"}}
        """)
        let message = messages([base, edit])[0]
        XCTAssertEqual(message.kind, .image)
        XCTAssertEqual(message.body, "New")
        XCTAssertEqual(message.fileName, "a.jpg")
        XCTAssertEqual(message.width, 10)
        XCTAssertEqual(message.mediaPath, "/media/a.jpg")
    }

    func testAPictureSwappedForAnotherShowsTheNewOne() {
        let base = event("$1", ts: 1, content: """
        {"msgtype":"m.image","body":"a.jpg","url":"mxc://example.test/a","info":{"mimetype":"image/jpeg"}}
        """, media: "/media/a.jpg")
        let edit = event("$2", ts: 2, content: """
        {"msgtype":"m.video","body":"* b.mp4","m.new_content":{"msgtype":"m.video","body":"b.mp4",
         "url":"mxc://example.test/b","info":{"mimetype":"video/mp4"}},
         "m.relates_to":{"rel_type":"m.replace","event_id":"$1"}}
        """, media: "/media/b.mp4")
        let message = messages([base, edit])[0]
        XCTAssertEqual(message.kind, .video)
        XCTAssertEqual(message.fileName, "b.mp4")
        XCTAssertEqual(message.mediaPath, "/media/b.mp4")
    }

    func testATextEditStillOnlyChangesTheWords() {
        let base = event("$1", ts: 1, content: #"{"msgtype":"m.text","body":"Helo"}"#)
        let edit = event("$2", ts: 2, content: """
        {"msgtype":"m.text","body":"* Hello","m.new_content":{"msgtype":"m.text","body":"Hello"},
         "m.relates_to":{"rel_type":"m.replace","event_id":"$1"}}
        """)
        let message = messages([base, edit])[0]
        XCTAssertEqual(message.kind, .text)
        XCTAssertEqual(message.body, "Hello")
    }

    // MARK: - Seen

    private func date(_ day: Int, _ hour: Int, _ minute: Int) -> Date {
        utc.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }

    private func millis(_ date: Date) -> Int64 { Int64(date.timeIntervalSince1970 * 1000) }

    private var clock: (Date) -> String {
        { [utc] date in
            let parts = utc.dateComponents([.hour, .minute], from: date)
            let hour = parts.hour! % 12 == 0 ? 12 : parts.hour! % 12
            return String(format: "%d:%02d %@", hour, parts.minute!, parts.hour! < 12 ? "AM" : "PM")
        }
    }

    func testOneToOneSeenSaysWhen() {
        let now = date(14, 18, 0)
        func seen(_ at: Date?) -> String? {
            StatusLine.seenText(.seen(by: [], at: at.map(millis)), time: clock, now: now, calendar: utc)
        }
        XCTAssertEqual(seen(nil), "Seen")
        XCTAssertEqual(seen(date(14, 9, 25)), "Seen at 9:25 AM")
        XCTAssertEqual(seen(date(13, 21, 5)), "Seen yesterday at 9:05 PM")
        XCTAssertEqual(seen(date(2, 9, 25)), "Seen Oct 2 at 9:25 AM")
        XCTAssertEqual(
            StatusLine.seenText(.seen(by: [], at: millis(date(2, 9, 25))), time: clock, date: { _ in "2 Oct" },
                                now: now, calendar: utc),
            "Seen 2 Oct at 9:25 AM")
    }

    func testGroupSeenNamesTheReaders() {
        func seen(_ by: [String]) -> String? { StatusLine.seenText(.seen(by: by, at: nil), time: clock) }
        XCTAssertEqual(seen(["Kent"]), "Seen by Kent")
        XCTAssertEqual(seen(["Kent", "Eddie"]), "Seen by Kent & Eddie")
        XCTAssertEqual(seen(["Kent", "Eddie", "Ana"]), "Seen by Kent & 2 others")
        XCTAssertEqual(seen(["Kent", "Eddie", "Ana", "Bo"]), "Seen by Kent & 3 others")
        XCTAssertNil(StatusLine.seenText(.delivered, time: clock))
    }
}
