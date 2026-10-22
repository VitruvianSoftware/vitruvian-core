// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import XCTest

@testable import CourierCore

/// RichTextHTML reads a message's Matrix HTML back into text and ranges. The shared cases are the ones the engine's
/// richtext tests render (protocol/richtext/cases.json), so what the engine sends reads back as what was typed.
final class RichTextTests: XCTestCase {
    private struct Cases: Decodable {
        let about: String
        let cases: [Case]
    }

    private struct Case: Decodable {
        let name: String
        let text: String
        let entities: [TextEntity]
        let keep: [TextEntity.Kind]
        let html: String
        let body: String
    }

    private func loadCases() throws -> [Case] {
        let dir = try XCTUnwrap(ProtocolConformanceTests.protocolDirectory(), "protocol.json not found")
        let data = try Data(contentsOf: dir.appendingPathComponent("richtext/cases.json"))
        let cases = try JSONDecoder().decode(Cases.self, from: data).cases
        // A loop over nothing would pass without checking anything.
        XCTAssertGreaterThan(cases.count, 20, "the cases are missing")
        return cases
    }

    private func entity(_ kind: TextEntity.Kind, _ offset: Int, _ length: Int, url: String? = nil,
                        userID: String? = nil) -> TextEntity {
        TextEntity(kind: kind, offset: offset, length: length, url: url, userID: userID)
    }

    private func parse(_ html: String, fallback: String = "fallback") -> RichText {
        RichTextHTML.parse(html: html, fallback: fallback)
    }

    // MARK: - The shared cases (Review Focus 4)

    func testHTMLRoundTripsTheSharedCases() throws {
        var exact = 0
        for item in try loadCases() {
            if item.html.isEmpty {
                // Nothing formatted was sent (a network that keeps none, or a range that needs no tag): the body is
                // the message, and it reads as itself.
                XCTAssertEqual(parse("", fallback: item.body), RichText(text: item.body, entities: []), item.name)
                continue
            }
            let parsed = parse(item.html, fallback: "unreadable")
            XCTAssertNotEqual(parsed.text, "unreadable", "\(item.name): the HTML was not read")
            // Every case, whatever the chat keeps: the parsed message, written plainly as the engine writes a body,
            // is that body. So a kind the chat didn't keep reads in its plain form, and nothing is lost or doubled.
            XCTAssertEqual(Self.plainBody(parsed), item.body, "\(item.name): plain form")
            XCTAssertTrue(parsed.entities.allSatisfy { item.keep.contains($0.kind) },
                          "\(item.name): only kinds the chat keeps come back")
            // When the chat keeps every kind it was sent, the text and ranges come back exactly as typed (less what the
            // engine drops: styles inside code).
            let kinds = Set(item.entities.map(\.kind))
            if kinds.isSubset(of: Set(item.keep)) {
                XCTAssertEqual(parsed.text, item.text, "\(item.name): text")
                XCTAssertEqual(parsed.entities, Self.expected(item.entities), "\(item.name): ranges")
                exact += 1
            }
        }
        XCTAssertGreaterThan(exact, 15, "most cases keep what they send")
    }

    /// The ranges the engine renders: a style inside code or a code block is dropped, and the rest come back in
    /// RichText's order.
    private static func expected(_ entities: [TextEntity]) -> [TextEntity] {
        let code = entities.filter { $0.kind == .code || $0.kind == .pre }
        let styles: Set<TextEntity.Kind> = [.bold, .italic, .strikethrough, .spoiler]
        return entities.filter { entity in
            !(styles.contains(entity.kind) && code.contains {
                $0.offset <= entity.offset && entity.offset + entity.length <= $0.offset + $0.length
            })
        }.sorted(by: TextEntity.precedes)
    }

    /// The engine's plain body for a message (richtext.body): list lines take "• " or "1. ", quoted lines "> ", and a
    /// link whose text isn't its address is followed by " (address)".
    static func plainBody(_ rich: RichText) -> String {
        let text = rich.text as NSString
        var lines: [NSRange] = []
        var start = 0
        while true {
            let next = text.range(of: "\n", range: NSRange(location: start, length: text.length - start))
            if next.location == NSNotFound {
                lines.append(NSRange(location: start, length: text.length - start))
                break
            }
            lines.append(NSRange(location: start, length: next.location - start))
            start = next.location + 1
        }
        let blocks = rich.entities.filter(\.kind.isBlock)
        var numbers: [Int: Int] = [:] // block index → the last number given
        var out = ""
        for (index, line) in lines.enumerated() {
            if index > 0 { out += "\n" }
            // A line is in the block that covers its start. A list's empty line takes no marker.
            if let block = blocks.firstIndex(where: { $0.offset <= line.location && line.location < $0.offset + $0.length }),
               line.length > 0 || blocks[block].kind == .blockquote {
                switch blocks[block].kind {
                case .blockquote: out += "> "
                case .bulletList: out += "• "
                case .orderedList:
                    let number = (numbers[block] ?? 0) + 1
                    numbers[block] = number
                    out += "\(number). "
                default: break
                }
            }
            var position = line.location
            let links = rich.entities.filter { $0.kind == .link }.sorted { $0.offset < $1.offset }
            for link in links where link.offset >= line.location && link.offset + link.length <= NSMaxRange(line) {
                let end = link.offset + link.length
                out += text.substring(with: NSRange(location: position, length: end - position))
                let shown = text.substring(with: NSRange(location: link.offset, length: link.length))
                if let url = link.url, !Self.sameAsAddress(shown, url) { out += " (\(url))" }
                position = end
            }
            out += text.substring(with: NSRange(location: position, length: NSMaxRange(line) - position))
        }
        return out
    }

    private static func sameAsAddress(_ text: String, _ address: String) -> Bool {
        let text = text.trimmingCharacters(in: .whitespaces)
        if text == address { return true }
        return ["mailto:", "http://", "https://"].contains { address.hasPrefix($0) && text == String(address.dropFirst($0.count)) }
    }

    // MARK: - On the wire

    func testTextEntityOnTheWire() throws {
        // The kind is "type"; a url or user_id that is empty is left out, never null or "".
        let bold = try JSONSerialization.jsonObject(with: JSONEncoder().encode(
            TextEntity(kind: .bold, offset: 1, length: 2, url: "", userID: nil))) as? NSDictionary
        XCTAssertEqual(bold, ["type": "bold", "offset": 1, "length": 2])
        let list = try JSONSerialization.jsonObject(with: JSONEncoder().encode(
            TextEntity(kind: .bulletList, offset: 0, length: 1))) as? NSDictionary
        XCTAssertEqual(list, ["type": "bullet_list", "offset": 0, "length": 1])
        let mention = try JSONDecoder().decode(TextEntity.self, from: Data(
            #"{"type":"mention","offset":0,"length":4,"user_id":"@a:x.test"}"#.utf8))
        XCTAssertEqual(mention, TextEntity(kind: .mention, offset: 0, length: 4, userID: "@a:x.test"))
        XCTAssertEqual(TextEntity.Kind.allCases.filter(\.isBlock), [.pre, .blockquote, .bulletList, .orderedList])

        // Draft's reply_to and thread_root are always there, null when there is none.
        let draft = try JSONSerialization.jsonObject(with: JSONEncoder().encode(
            Draft(text: "hi", entities: [], replyTo: nil, threadRoot: nil))) as? NSDictionary
        XCTAssertEqual(draft, ["text": "hi", "entities": [], "reply_to": NSNull(), "thread_root": NSNull()])
        XCTAssertEqual(Change(Changed(kind: .scheduled, roomID: "!r")), .scheduled(roomID: "!r"))
        XCTAssertEqual(Change(Changed(kind: .scheduled)), .resync, "a scheduled change needs its chat")
    }

    // MARK: - Reading Matrix HTML

    func testUnknownTagsKeepTheirText() {
        XCTAssertEqual(parse("<u>under</u> <font color=\"red\">red</font> <x-new a=b>new</x-new>"),
                       RichText(text: "under red new", entities: []))
        XCTAssertEqual(parse("<table><tr><td>cell</td></tr></table>"), RichText(text: "cell", entities: []))
        // Bold and italic by their other names, and a heading as a bold line.
        XCTAssertEqual(parse("<b>a</b> <i>b</i> <s>c</s>"),
                       RichText(text: "a b c", entities: [entity(.bold, 0, 1), entity(.italic, 2, 1),
                                                          entity(.strikethrough, 4, 1)]))
        XCTAssertEqual(parse("<h1>Title</h1>text"),
                       RichText(text: "Title\ntext", entities: [entity(.bold, 0, 5)]))
        // Paragraphs are a blank line apart.
        XCTAssertEqual(parse("<p>one</p><p>two</p>"), RichText(text: "one\n\ntwo", entities: []))
        // Script and style are never text.
        XCTAssertEqual(parse("a<script>alert(1)</script><style>p{}</style>b"), RichText(text: "ab", entities: []))
    }

    func testReplyFallbackIsDropped() {
        let html = "<mx-reply><blockquote><a href=\"https://matrix.to/#/!r:x.test/$e\">In reply to</a> "
            + "<a href=\"https://matrix.to/#/@ann:x.test\">@ann:x.test</a><br>the question</blockquote></mx-reply>"
            + "the <em>answer</em>"
        XCTAssertEqual(parse(html), RichText(text: "the answer", entities: [entity(.italic, 4, 6)]))
    }

    func testRangesCountUTF16() {
        // 🎉 is two UTF-16 units, 👍🏽 four, and é (as e and a combining accent) two: as NSString counts them.
        let parsed = parse("🎉 <strong>party</strong> 👍🏽 e\u{301}<em>x</em>")
        XCTAssertEqual(parsed.text, "🎉 party 👍🏽 e\u{301}x")
        XCTAssertEqual(parsed.entities, [entity(.bold, 3, 5), entity(.italic, 16, 1)])
        let text = parsed.text as NSString
        XCTAssertEqual(text.substring(with: NSRange(location: 3, length: 5)), "party")
        XCTAssertEqual(text.substring(with: NSRange(location: 16, length: 1)), "x")
    }

    func testEntitiesAndLinksAreRead() {
        XCTAssertEqual(parse("&lt;b&gt; &amp; &quot;q&quot; &#39;s&#39; &#x1F600; &nbsp;&bogus; &#0;"),
                       RichText(text: "<b> & \"q\" 's' 😀 \u{00A0}&bogus; \u{FFFD}", entities: []))
        // A mention, by its matrix.to link, its ID decoded.
        XCTAssertEqual(parse("hi <a href=\"https://matrix.to/#/%40ann%3Ax.test\">Ann</a>"),
                       RichText(text: "hi Ann", entities: [entity(.mention, 3, 3, userID: "@ann:x.test")]))
        // A link that isn't http, https or mailto keeps its text and nothing else.
        XCTAssertEqual(parse("<a href=\"javascript:alert(1)\">click</a> <a href='mailto:a@x.test'>mail</a>"),
                       RichText(text: "click mail", entities: [entity(.link, 6, 4, url: "mailto:a@x.test")]))
        // A numbered list that starts later than 1, on its own, is still a numbered list.
        XCTAssertEqual(parse("<ol start=\"3\"><li>c</li></ol>"),
                       RichText(text: "c", entities: [entity(.orderedList, 0, 1)]))
        // A code block keeps its lines, and nothing styles code.
        XCTAssertEqual(parse("<pre><code class=\"language-go\">a &lt; b\n<b>c</b></code></pre>"),
                       RichText(text: "a < b\nc", entities: [entity(.pre, 0, 7)]))
    }

    func testWhatCantBeReadGivesTheFallback() {
        XCTAssertEqual(parse("", fallback: "plain"), RichText(text: "plain", entities: []))
        XCTAssertEqual(parse("<mx-reply>only a quote</mx-reply>", fallback: "plain"), RichText(text: "plain", entities: []))
        XCTAssertEqual(parse("   ", fallback: "plain"), RichText(text: "plain", entities: []))
        // Broken HTML still reads as what it says.
        XCTAssertEqual(parse("<strong>open", fallback: "plain"), RichText(text: "open", entities: [entity(.bold, 0, 4)]))
        XCTAssertEqual(parse("a < b <", fallback: "plain"), RichText(text: "a < b <", entities: []))
        XCTAssertEqual(parse("</em>x<", fallback: "plain"), RichText(text: "x<", entities: []))
    }

    func testParseNeverFailsOnRandomInput() {
        let fragments = [
            "<", ">", "</", "/>", "<b>", "</b>", "<strong>", "</strong>", "<em>", "</em>", "<i>", "<del>", "</del>",
            "<code>", "</code>", "<pre>", "</pre>", "<blockquote>", "</blockquote>", "<ul>", "</ul>", "<ol>",
            "<ol start=\"7\">", "<ol start=x>", "</ol>", "<li>", "</li>", "<br>", "<br/>", "<p>", "</p>", "<h2>",
            "</h2>", "<a href=\"https://x.test\">", "<a href=\"https://matrix.to/#/@a:x.test\">", "<a href='",
            "</a>", "<span data-mx-spoiler>", "</span>", "<mx-reply>", "</mx-reply>", "<script>", "</script>",
            "&amp;", "&#", "&#x", "&#1114112;", "&#xD800;", "&", ";", "\"", "'", "=", "\n", " ", "a", "é", "🎉",
            "👍🏽", "\u{301}", "שלום", "\0", "<!--", "-->", "<!DOCTYPE html>", "<x", "<?", "</ x>",
        ]
        var random = SplitMix64(seed: 0xC0FFEE)
        for round in 0 ..< 2000 {
            let count = Int(random.next() % 40)
            var html = ""
            for _ in 0 ..< count { html += fragments[Int(random.next() % UInt64(fragments.count))] }
            let parsed = RichTextHTML.parse(html: html, fallback: "fallback")
            let length = (parsed.text as NSString).length
            for entity in parsed.entities {
                XCTAssertGreaterThanOrEqual(entity.offset, 0, "round \(round): \(html)")
                XCTAssertGreaterThan(entity.length, 0, "round \(round): \(html)")
                XCTAssertLessThanOrEqual(entity.offset + entity.length, length, "round \(round): \(html)")
            }
        }
    }
}

/// A small seeded generator, so the random inputs are the same every run.
struct SplitMix64 {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
