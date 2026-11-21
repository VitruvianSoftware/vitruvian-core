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
                       thumbnail: String? = nil, mine: Bool = false) -> Event {
        Event(eventID: id, roomID: "!room", sender: "@florian:example.test", senderName: "Florian", mine: mine,
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

    func testIdenticalBodyLinkPreviewEditUpdatesPreviewSilentlyWithoutEditedOrHistory() {
        let link = "https://example.test/post"
        let base = event("$1", ts: 1, content: #"{"msgtype":"m.text","body":"https://example.test/post"}"#)
        var previewEdit = event("$2", ts: 2, content: """
        {"msgtype":"m.text","body":"* https://example.test/post",
         "m.new_content":{"msgtype":"m.text","body":"https://example.test/post"},
         "m.relates_to":{"rel_type":"m.replace","event_id":"$1"}}
        """)
        previewEdit.linkPreviews = [
            LinkPreviewItem(matchedURL: link, url: link, title: "Added Preview Title", siteName: "Example"),
        ]
        let shown = messages([base, previewEdit])[0]
        XCTAssertFalse(shown.isEdited, "an identical-body edit adding a link preview must not label the message Edited")
        XCTAssertEqual(shown.changedEditCount, 0)
        XCTAssertEqual(shown.editCount, 1, "the network still counts it as an edit (for its edit limit)")
        XCTAssertEqual(shown.linkPreviews.first?.title, "Added Preview Title", "silent preview edit still updates linkPreviews")

        let whatsApp = ChatFeatures(reply: true, edit: true, unsend: true, source: .stored)
        let actions = MessageActions.available(for: shown, in: whatsApp, network: "whatsapp", now: Date(timeIntervalSince1970: 1))
        XCTAssertFalse(actions.actions.contains(.showHistory), "Edit History must not be offered for preview-only edits")

        // Also check m.new_content["com.beeper.linkpreviews"] JSON fallback.
        let jsonPreviewEdit = event("$3", ts: 3, content: """
        {"msgtype":"m.text","body":"* https://example.test/post",
         "m.new_content":{"msgtype":"m.text","body":"https://example.test/post",
          "com.beeper.linkpreviews":[{"matched_url":"https://example.test/post","og:title":"JSON Preview"}]},
         "m.relates_to":{"rel_type":"m.replace","event_id":"$1"}}
        """)
        let jsonShown = messages([base, jsonPreviewEdit])[0]
        XCTAssertFalse(jsonShown.isEdited)
        XCTAssertEqual(jsonShown.linkPreviews.first?.title, "JSON Preview")
    }

    // MARK: - An address that only became clickable is not an edit

    /// The edit a network sends when it makes a bare address clickable: the same words, plus a `formatted_body` whose
    /// only markup is a link whose text is its own address.
    private func linkifyEdit(_ id: String, of target: String, body: String, formatted: String, ts: Int64,
                             mine: Bool = false) -> Event {
        let bodyJSON = String(decoding: try! JSONEncoder().encode(body), as: UTF8.self)
        let starJSON = String(decoding: try! JSONEncoder().encode("* " + body), as: UTF8.self)
        let formattedJSON = String(decoding: try! JSONEncoder().encode(formatted), as: UTF8.self)
        return event(id, ts: ts, content: """
        {"msgtype":"m.text","body":\(starJSON),"format":"org.matrix.custom.html","formatted_body":\(formattedJSON),
         "m.new_content":{"msgtype":"m.text","body":\(bodyJSON),"format":"org.matrix.custom.html",
                          "formatted_body":\(formattedJSON)},
         "m.relates_to":{"rel_type":"m.replace","event_id":"\(target)"}}
        """, mine: mine)
    }

    private func isSilent(_ shown: TimelineMessage, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertFalse(shown.isEdited, "no Edited label", file: file, line: line)
        XCTAssertEqual(shown.changedEditCount, 0, "no Edit History entry", file: file, line: line)
        XCTAssertEqual(shown.editCount, 1, "still counts toward the network's edit limit", file: file, line: line)
    }

    func testAnEditThatOnlyMakesAYouTubeAddressClickableIsSilent() {
        // The real payloads from the Eddie & Kent chat.
        let url = "https://www.youtube.com/watch?v=HQlk9RGx2dk"
        let base = event("$1", ts: 1, content: #"{"msgtype":"m.text","body":"Haha https://www.youtube.com/watch?v=HQlk9RGx2dk"}"#,
                         mine: true)
        let edit = linkifyEdit("$2", of: "$1", body: "Haha \(url)",
                               formatted: #"Haha <a href="\#(url)">\#(url)</a>"#, ts: 2, mine: true)
        let shown = messages([base, edit])[0]
        isSilent(shown)
        XCTAssertEqual(shown.body, "Haha \(url)")
        XCTAssertEqual(shown.rich.entities.first?.kind, .link, "the address is clickable now")

        let features = ChatFeatures(reply: true, edit: true, editMaxCount: 1, unsend: true, source: .stored)
        let result = MessageActions.available(for: shown, in: features, network: "gchat",
                                              now: Date(timeIntervalSince1970: 1))
        XCTAssertFalse(result.actions.contains(.showHistory), "no Edit History for it")
        XCTAssertFalse(result.actions.contains(.edit), "the one edit it used is at the limit of 1")
        XCTAssertNotNil(result.unavailable.first { $0.action == .edit }, "and Edit says why")
    }

    func testAnEntityEncodedTextWithAClickableAddressIsSilent() {
        let url = "https://www.anthropic.com/news/claude-story"
        let base = event("$1", ts: 1, content: #"{"msgtype":"m.text","body":"Anthropic's own story https://www.anthropic.com/news/claude-story =)"}"#)
        let edit = linkifyEdit("$2", of: "$1", body: "Anthropic's own story \(url) =)",
                               formatted: #"Anthropic&#39;s own story <a href="\#(url)">\#(url)</a> =)"#, ts: 2)
        let shown = messages([base, edit])[0]
        isSilent(shown)
        XCTAssertEqual(shown.rich.text, "Anthropic's own story \(url) =)")
    }

    func testALinkShownWithoutItsSchemeIsStillAnAddress() {
        let base = event("$1", ts: 1, content: #"{"msgtype":"m.text","body":"see example.test/a"}"#)
        let edit = linkifyEdit("$2", of: "$1", body: "see example.test/a",
                               formatted: #"see <a href="https://example.test/a">example.test/a</a>"#, ts: 2)
        isSilent(messages([base, edit])[0])
    }

    func testRealEditsAroundAnAddressStillSayEdited() {
        let url = "https://www.youtube.com/watch?v=HQlk9RGx2dk"
        let base = event("$1", ts: 1, content: #"{"msgtype":"m.text","body":"Haha https://www.youtube.com/watch?v=HQlk9RGx2dk"}"#)
        func edited(_ edit: Event) -> TimelineMessage { messages([base, edit])[0] }

        // Bold added on top of the link.
        let bold = edited(linkifyEdit("$2", of: "$1", body: "Haha \(url)",
                                      formatted: #"<b>Haha</b> <a href="\#(url)">\#(url)</a>"#, ts: 2))
        XCTAssertTrue(bold.isEdited, "bold is a real change")
        XCTAssertEqual(bold.changedEditCount, 1)

        // Italics instead of a link.
        let italic = edited(linkifyEdit("$2", of: "$1", body: "Haha \(url)", formatted: "<i>Haha</i> \(url)", ts: 2))
        XCTAssertTrue(italic.isEdited)

        // The words changed (and the address is a link).
        let words = edited(linkifyEdit("$2", of: "$1", body: "Hehe \(url)",
                                       formatted: #"Hehe <a href="\#(url)">\#(url)</a>"#, ts: 2))
        XCTAssertTrue(words.isEdited, "different words are a real edit")

        // A link with words of its own is the writer's choice, not the network's.
        let named = edited(linkifyEdit("$2", of: "$1", body: "Haha \(url)",
                                       formatted: #"Haha <a href="\#(url)">this video</a>"#, ts: 2))
        XCTAssertTrue(named.isEdited, "a link that says something else is formatting")
    }

    func testASilentLinkEditAfterARealEditStaysOneChange() {
        let url = "https://www.youtube.com/watch?v=HQlk9RGx2dk"
        let base = event("$1", ts: 1, content: #"{"msgtype":"m.text","body":"Hah https://www.youtube.com/watch?v=HQlk9RGx2dk"}"#)
        let real = linkifyEdit("$2", of: "$1", body: "Haha \(url)", formatted: "", ts: 2)
        let silent = linkifyEdit("$3", of: "$1", body: "Haha \(url)",
                                 formatted: #"Haha <a href="\#(url)">\#(url)</a>"#, ts: 3)
        let shown = messages([base, real, silent])[0]
        XCTAssertTrue(shown.isEdited)
        XCTAssertEqual(shown.changedEditCount, 1)
        XCTAssertEqual(shown.editCount, 2)
    }

    func testEditHistoryHidesTheVersionThatOnlyMadeAnAddressClickable() {
        let url = "https://www.youtube.com/watch?v=HQlk9RGx2dk"
        let sent = Version(body: "Haha \(url)", ts: 1)
        let linked = Version(body: "Haha \(url)", formattedBody: #"Haha <a href="\#(url)">\#(url)</a>"#, ts: 2)
        let bold = Version(body: "Haha \(url)", formattedBody: #"<b>Haha</b> <a href="\#(url)">\#(url)</a>"#, ts: 3)
        XCTAssertEqual(EditHistory.visibleVersions([sent, linked]), [sent])
        XCTAssertEqual(EditHistory.visibleVersions([sent, linked, bold]), [sent, bold])
    }

    func testFormattingOnlyEditCountsAsEdited() {
        let base = event("$1", ts: 1, content: #"{"msgtype":"m.text","body":"hello"}"#)
        let formatEdit = event("$2", ts: 2, content: """
        {"msgtype":"m.text","body":"* hello",
         "m.new_content":{"msgtype":"m.text","body":"hello","format":"org.matrix.custom.html","formatted_body":"<b>hello</b>"},
         "m.relates_to":{"rel_type":"m.replace","event_id":"$1"}}
        """)
        let shown = messages([base, formatEdit])[0]
        XCTAssertTrue(shown.isEdited, "an edit that changes formatting must still be marked Edited")
        XCTAssertEqual(shown.editCount, 1)
        XCTAssertEqual(shown.changedEditCount, 1)
        let whatsApp = ChatFeatures(reply: true, edit: true, unsend: true, source: .stored)
        let actions = MessageActions.available(for: shown, in: whatsApp, network: "whatsapp", now: Date(timeIntervalSince1970: 1))
        XCTAssertTrue(actions.actions.contains(.showHistory))
    }

    func testRealEditFollowedBySilentLinkPreviewEditRemainsEdited() {
        let link = "https://example.test/updated"
        let base = event("$1", ts: 1, content: #"{"msgtype":"m.text","body":"https://example.test/old"}"#)
        let realEdit = event("$2", ts: 2, content: """
        {"msgtype":"m.text","body":"* https://example.test/updated",
         "m.new_content":{"msgtype":"m.text","body":"https://example.test/updated"},
         "m.relates_to":{"rel_type":"m.replace","event_id":"$1"}}
        """)
        var silentPreviewEdit = event("$3", ts: 3, content: """
        {"msgtype":"m.text","body":"* https://example.test/updated",
         "m.new_content":{"msgtype":"m.text","body":"https://example.test/updated"},
         "m.relates_to":{"rel_type":"m.replace","event_id":"$1"}}
        """)
        silentPreviewEdit.linkPreviews = [LinkPreviewItem(matchedURL: link, url: link, title: "Updated Title")]
        let shown = messages([base, realEdit, silentPreviewEdit])[0]
        XCTAssertTrue(shown.isEdited)
        XCTAssertEqual(shown.changedEditCount, 1)
        XCTAssertEqual(shown.editCount, 2, "both edits count toward the network's limit")
        XCTAssertEqual(shown.body, link)
        XCTAssertEqual(shown.linkPreviews.first?.title, "Updated Title")
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
