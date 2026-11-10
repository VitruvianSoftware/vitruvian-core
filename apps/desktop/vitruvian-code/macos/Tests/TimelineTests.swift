// Copyright (c) 2026 VitruvianSoftware
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

import AppKit
import Foundation
import VitruvianCodeCore
import XCTest

@testable import VitruvianCodeUI

/// The conversation timeline's rules: how messages become turns, when the
/// rail shows, the card's text and dates, which dot is active, and where
/// the dots sit. Also the timestamps saved transcripts give the messages,
/// and the key the standalone app keeps the rail's edge under.
final class TimelineTests: XCTestCase {
    private func user(_ text: String, at date: Date? = nil) -> VitruvianCodeChatMessage {
        VitruvianCodeChatMessage(role: .user, text: text, createdAt: date)
    }

    private func agent(_ text: String, isError: Bool = false) -> VitruvianCodeChatMessage {
        VitruvianCodeChatMessage(role: .agent, text: text, isError: isError)
    }

    // MARK: - Edges

    /// macOS draws the scroll bar at the right edge, over the transcript.
    /// On that side the rail must stand wholly inside it, or the bar and
    /// the dots overlap and a drag on the bar lands on a dot.
    func testTheRightHandRailStandsClearOfTheScrollBar() {
        let bar = max(NSScroller.scrollerWidth(for: .regular, scrollerStyle: .legacy),
                      NSScroller.scrollerWidth(for: .regular, scrollerStyle: .overlay))
        XCTAssertGreaterThanOrEqual(VitruvianCodeTimelineScrubber.edge(onLeft: false), bar,
                                    "the rail's outer side is past the widest scroll bar")
        XCTAssertEqual(VitruvianCodeTimelineScrubber.edge(onLeft: true), VitruvianCodeTimelineScrubber.edgeInset,
                       "the left has no scroll bar, so the rail stays near its edge")
    }

    /// The transcript leaves the same clear space beside the rail on both
    /// sides: 6 points between the rail's inner side and the text.
    func testTheGutterLeavesTheSameRoomBesideTheRailOnEitherSide() {
        let padding: CGFloat = 14
        for onLeft in [true, false] {
            let railInner = VitruvianCodeTimelineScrubber.edge(onLeft: onLeft) + VitruvianCodeTimelineScrubber.railWidth
            let textStart = padding + VitruvianCodeTimelineScrubber.gutter(onLeft: onLeft)
            XCTAssertEqual(textStart - railInner, 6, onLeft ? "left" : "right")
        }
    }

    // MARK: - Turns

    func testEachPromptStartsATurnThatHoldsTheRepliesAfterIt() {
        let first = user("Fix the build")
        let reply = agent("Done, the **build** is green.")
        let more = agent("Also tidied the tests.")
        let second = user("Now ship it")
        let shipped = agent("Shipped.")
        let turns = VitruvianCodeTimeline.turns(from: [first, reply, more, second, shipped])
        XCTAssertEqual(turns.map(\.promptID), [first.id, second.id])
        XCTAssertEqual(turns[0].messageIDs, [first.id, reply.id, more.id])
        XCTAssertEqual(turns[0].replySnippet, "Done, the build is green.", "the first reply, as plain text")
        XCTAssertEqual(turns[1].messageIDs, [second.id, shipped.id])
    }

    func testAnAgentMessageBeforeAnyPromptBelongsToNoTurn() {
        let note = agent("Resumed session “Release”.")
        let prompt = user("Carry on")
        let turns = VitruvianCodeTimeline.turns(from: [note, prompt, agent("On it.")])
        XCTAssertEqual(turns.count, 1)
        XCTAssertEqual(turns[0].promptID, prompt.id)
        XCTAssertFalse(turns[0].messageIDs.contains(note.id))
        XCTAssertEqual(VitruvianCodeTimeline.turnIndexByMessage(turns)[note.id], nil)
        XCTAssertEqual(VitruvianCodeTimeline.turnIndexByMessage(turns)[prompt.id], 0)
    }

    func testATrailingPromptWithNoReplyIsATurnWaitingForOne() {
        let last = user("And the docs?")
        // The reply in flight: an agent message with nothing in it yet,
        // which the chat does not draw.
        let empty = agent("")
        let turns = VitruvianCodeTimeline.turns(from: [user("a"), agent("b"), last, empty])
        XCTAssertEqual(turns.count, 2)
        XCTAssertEqual(turns[1].promptID, last.id)
        XCTAssertNil(turns[1].replySnippet)
        XCTAssertEqual(turns[1].messageIDs, [last.id], "a message the chat does not draw is in no turn")
    }

    func testHiddenAndFailedRepliesAreNotTheSnippet() {
        let prompt = user("Run it")
        let steps = VitruvianCodeChatMessage(role: .agent, text: "",
                                          toolSteps: [VitruvianCodeToolStep(title: "swift build", kind: .bash)])
        let failed = agent("The agent stopped with an error.", isError: true)
        let answer = agent("It passed.")
        let turns = VitruvianCodeTimeline.turns(from: [prompt, steps, failed, answer])
        XCTAssertEqual(turns[0].messageIDs, [prompt.id, steps.id, failed.id, answer.id],
                       "a reply of tool steps alone is still drawn, so it is in the turn")
        XCTAssertEqual(turns[0].replySnippet, "It passed.", "the first reply with text that is not an error")
    }

    func testAPromptsLinesAreRunTogetherAndItKeepsItsTime() {
        let sent = Date(timeIntervalSince1970: 1_800_000_000)
        let turns = VitruvianCodeTimeline.turns(from: [user("one\n\n  two\tthree", at: sent)])
        XCTAssertEqual(turns[0].prompt, "one two three")
        XCTAssertEqual(turns[0].createdAt, sent)
    }

    func testTheRailShowsFromThreeTurns() {
        XCTAssertEqual(VitruvianCodeTimeline.minimumTurns, 3)
        XCTAssertFalse(VitruvianCodeTimeline.showsRail(turnCount: 0))
        XCTAssertFalse(VitruvianCodeTimeline.showsRail(turnCount: 2))
        XCTAssertTrue(VitruvianCodeTimeline.showsRail(turnCount: 3))
        XCTAssertTrue(VitruvianCodeTimeline.showsRail(turnCount: 40))
        let two = [user("a"), agent("b"), user("c"), agent("d")]
        XCTAssertFalse(VitruvianCodeTimeline.showsRail(turnCount: VitruvianCodeTimeline.turns(from: two).count))
        XCTAssertTrue(VitruvianCodeTimeline.showsRail(turnCount: VitruvianCodeTimeline.turns(from: two + [user("e")]).count))
    }

    // MARK: - The snippet

    func testCodeBlocksAreLeftOutOfTheSnippet() {
        let text = """
        Here is the fix:

        ```swift
        let a = 1
        ```

        Then rebuild.
        """
        XCTAssertEqual(VitruvianCodeTimeline.plainSnippet(text), "Here is the fix: Then rebuild.")
    }

    func testAReplyThatIsOnlyCodeKeepsTheCode() {
        XCTAssertEqual(VitruvianCodeTimeline.plainSnippet("```bash\nswift build\nswift test\n```"),
                       "swift build swift test")
    }

    func testHeadingsListsQuotesAndEmphasisAreStripped() {
        let text = """
        ## Result
        > **Note:** it _works_ now
        - first `item`
        2. second ~~old~~ *new*
        ---
        snake_case_name stays
        """
        XCTAssertEqual(VitruvianCodeTimeline.plainSnippet(text),
                       "Result Note: it works now first item second old new snake_case_name stays")
    }

    func testLinksReadAsTheirTextAndTablesAsTheirCells() {
        let text = """
        See [the guide](https://example.com/guide) and ![diagram](d.png).

        | File | Lines |
        | --- | ---: |
        | App.swift | 12 |
        """
        XCTAssertEqual(VitruvianCodeTimeline.plainSnippet(text),
                       "See the guide and diagram. File Lines App.swift 12")
    }

    func testNewLinesCollapseAndALongReplyIsCut() {
        XCTAssertEqual(VitruvianCodeTimeline.plainSnippet("one\n\n\ntwo   three\r\nfour"), "one two three four")
        let long = String(repeating: "word ", count: 200)
        let snippet = VitruvianCodeTimeline.plainSnippet(long, limit: 30)
        XCTAssertTrue(snippet.hasSuffix("…"))
        XCTAssertLessThanOrEqual(snippet.count, 31)
        XCTAssertEqual(VitruvianCodeTimeline.plainSnippet("   \n  "), "")
    }

    // MARK: - Words and dates

    func testTheDotsLabelAndTheCardsPositionUseTheWordsPieces() {
        let strings = VitruvianCodeChatStrings()
        XCTAssertEqual(VitruvianCodeTimeline.position(12, of: 40, strings: strings), "12 of 40")
        let long = String(repeating: "a", count: 80)
        XCTAssertEqual(VitruvianCodeTimeline.dotLabel(3, of: 6, prompt: long, strings: strings),
                       "Prompt 3 of 6: " + String(repeating: "a", count: 60) + "…")
        XCTAssertEqual(VitruvianCodeTimeline.dotLabel(1, of: 3, prompt: "Hi", strings: strings), "Prompt 1 of 3: Hi")
        var german = strings
        german.timelinePromptPrefix = "Prompt "
        german.timelineOf = " von "
        XCTAssertEqual(VitruvianCodeTimeline.position(2, of: 5, strings: german), "2 von 5")
    }

    func testTodayIsTheTimeAloneAndAnOlderDayIsTheDateToo() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))
        let locale = Locale(identifier: "en_US")
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 11, day: 5, hour: 18)))
        let earlierToday = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 11, day: 5,
                                                                            hour: 15, minute: 11)))
        let older = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 10, day: 26,
                                                                     hour: 15, minute: 11)))
        // ICU puts a narrow no-break space before "PM"; read it as a space.
        func plain(_ text: String) -> String { text.replacingOccurrences(of: "\u{202F}", with: " ") }
        let today = plain(VitruvianCodeTimeline.timeLabel(earlierToday, now: now, calendar: calendar, locale: locale))
        XCTAssertEqual(today, "3:11 PM")
        let past = plain(VitruvianCodeTimeline.timeLabel(older, now: now, calendar: calendar, locale: locale))
        XCTAssertTrue(past.contains("Oct 26, 2026"), past)
        XCTAssertTrue(past.contains("3:11 PM"), past)
        // Another locale writes it its own way.
        let french = plain(VitruvianCodeTimeline.timeLabel(earlierToday, now: now, calendar: calendar,
                                                        locale: Locale(identifier: "fr_FR")))
        XCTAssertEqual(french, "15:11")
    }

    // MARK: - The active dot

    func testTheActiveTurnIsTheLastOneStartedAtTheTop() {
        // Turn 4's prompt has scrolled off; its reply fills the top.
        XCTAssertEqual(VitruvianCodeTimeline.activeTurn(tops: [4: -300, 5: 220, 6: 640], current: 0), 4)
        XCTAssertEqual(VitruvianCodeTimeline.activeTurn(tops: [0: 14, 1: 300], current: 3), 0, "the first prompt at the top")
        XCTAssertEqual(VitruvianCodeTimeline.activeTurn(tops: [2: 40, 3: 41], current: 0), 2, "40 points down still counts")
    }

    func testWhenEveryTurnInViewStartsLowerTheOneBeforeIsActive() {
        XCTAssertEqual(VitruvianCodeTimeline.activeTurn(tops: [5: 120, 6: 500], current: 0), 4)
        XCTAssertEqual(VitruvianCodeTimeline.activeTurn(tops: [0: 90], current: 2), 0, "never before the first")
        XCTAssertEqual(VitruvianCodeTimeline.activeTurn(tops: [:], current: 7), 7, "nothing in view keeps the last answer")
    }

    // MARK: - Where the dots sit

    func testDotsAreSpreadEvenlyWhenThereIsRoom() {
        let layout = VitruvianCodeTimeline.RailLayout(count: 6, height: 100, active: 0)
        XCTAssertEqual(layout.spacing, 20)
        XCTAssertEqual(layout.offset, 0)
        XCTAssertTrue(layout.showsAll)
        XCTAssertEqual((0..<6).map(layout.y(of:)), [0, 20, 40, 60, 80, 100])
        XCTAssertEqual(layout.nearest(to: -50), 0)
        XCTAssertEqual(layout.nearest(to: 29), 1)
        XCTAssertEqual(layout.nearest(to: 31), 2)
        XCTAssertEqual(layout.nearest(to: 500), 5)
    }

    func testCrowdedDotsKeepTheirSpacingAndTheRailShowsTheStretchAroundTheActiveOne() {
        // 101 dots on 120 points would be 1.2 apart: they stay 6 apart.
        let middle = VitruvianCodeTimeline.RailLayout(count: 101, height: 120, active: 50)
        XCTAssertEqual(middle.spacing, 6)
        XCTAssertFalse(middle.showsAll)
        XCTAssertEqual(middle.y(of: 50), 60, "the active dot is in the middle of the rail")
        XCTAssertEqual(middle.nearest(to: 60), 50, "the pointer finds the dot it is over")
        XCTAssertEqual(middle.nearest(to: 66), 51)
        let start = VitruvianCodeTimeline.RailLayout(count: 101, height: 120, active: 2)
        XCTAssertEqual(start.offset, 0, "the stretch does not run past the first dot")
        XCTAssertEqual(start.y(of: 0), 0)
        let end = VitruvianCodeTimeline.RailLayout(count: 101, height: 120, active: 100)
        XCTAssertEqual(end.y(of: 100), 120, "nor past the last")
        XCTAssertEqual(end.nearest(to: 120), 100)
    }

    // MARK: - Transcript times

    func testAClaudeTranscriptGivesEachMessageItsRecordsTime() throws {
        let transcript = """
        {"type":"user","timestamp":"2026-10-22T01:20:49.851Z","message":{"role":"user","content":"Fix it"}}
        {"type":"assistant","timestamp":"2026-10-22T01:20:55Z","message":{"role":"assistant","content":[{"type":"text","text":"Fixed."}]}}
        {"type":"user","message":{"role":"user","content":"Thanks"}}
        {"type":"user","timestamp":"not a time","message":{"role":"user","content":"Again"}}
        """
        let messages = try XCTUnwrap(VitruvianCodeEngine.parseClaudeTranscript(transcript))
        XCTAssertEqual(messages.count, 4)
        XCTAssertEqual(try XCTUnwrap(messages[0].createdAt).timeIntervalSince1970, 1_792_632_049.851, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(messages[1].createdAt).timeIntervalSince1970, 1_792_632_055, accuracy: 0.001)
        XCTAssertNil(messages[2].createdAt, "a record with no time has none")
        XCTAssertNil(messages[3].createdAt, "nor one whose time does not read")
    }

    func testAnOpenCodeTranscriptGivesEachMessageItsCreatedTime() throws {
        let twoRows: [[String: Any]] = [
            ["type": "user", "data": #"{"text":"hi","time":{"created":1789418931039}}"#],
            ["type": "assistant", "data": #"{"content":[{"type":"text","text":"Hello"}],"time":{"created":1789418932000}}"#],
        ]
        let two = try XCTUnwrap(VitruvianCodeEngine.parseOpenCodeMessages(twoRows))
        XCTAssertEqual(try XCTUnwrap(two[0].createdAt).timeIntervalSince1970, 1_789_418_931.039, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(two[1].createdAt).timeIntervalSince1970, 1_789_418_932, accuracy: 0.001)

        XCTAssertTrue(VitruvianCodeEngine.opencodeTranscriptQueries(conversationID: "s")[1]
                        .contains("json_extract(m.data, '$.time.created') AS created"))
        let oneRows: [[String: Any]] = [
            ["message_id": "m1", "role": "user", "data": #"{"type":"text","text":"hi"}"#, "created": 1_768_437_980_642],
            ["message_id": "m2", "role": "assistant", "data": #"{"type":"text","text":"Hello"}"#],
        ]
        let one = try XCTUnwrap(VitruvianCodeEngine.parseOpenCodeMessages(oneRows))
        XCTAssertEqual(try XCTUnwrap(one[0].createdAt).timeIntervalSince1970, 1_768_437_980.642, accuracy: 0.001)
        XCTAssertNil(one[1].createdAt)
    }

    func testAMessageMadeWithoutATimeHasNoneAndEqualityStillHolds() {
        let message = VitruvianCodeChatMessage(role: .user, text: "a")
        XCTAssertNil(message.createdAt)
        var copy = message
        XCTAssertEqual(copy, message)
        copy.createdAt = Date()
        XCTAssertNotEqual(copy, message, "the time is part of the message")
    }

    // MARK: - The standalone app's key

    /// The standalone host keeps the edge in `UserDefaults` under
    /// `timelineOnLeft`, and Settings' toggle reaches it through the
    /// session, not a key of its own. The app cannot be linked into a test
    /// (it has `@main`), so its source is read.
    func testTheStandaloneHostKeepsTheEdgeUnderTimelineOnLeft() throws {
        let host = try XCTUnwrap(appSource("StandaloneHost.swift"), "could not find StandaloneHost.swift")
        let accessor = try XCTUnwrap(host.range(of: "var timelineOnLeft: Bool {"), "the host has the accessor")
        let body = String(host[accessor.upperBound...].prefix(240))
        XCTAssertTrue(body.contains(#"UserDefaults.standard.bool(forKey: "timelineOnLeft")"#), body)
        XCTAssertTrue(body.contains(#"UserDefaults.standard.set(newValue, forKey: "timelineOnLeft")"#), body)
        let settings = try XCTUnwrap(appSource("SettingsView.swift"), "could not find SettingsView.swift")
        XCTAssertTrue(settings.contains(#"Toggle("Show the conversation timeline on the left", isOn: $session.timelineOnLeft)"#))
        XCTAssertFalse(settings.contains(#"AppStorage("timelineOnLeft")"#), "one keeper of the key: the host")
    }

    private func appSource(_ name: String) -> String? {
        let relative = "apps/desktop/vitruvian-code/macos/Sources/VitruvianCode/\(name)"
        var candidates: [String] = []
        let environment = ProcessInfo.processInfo.environment
        if let runfiles = environment["TEST_SRCDIR"] {
            for workspace in [environment["TEST_WORKSPACE"], "_main"].compactMap({ $0 }) {
                candidates.append("\(runfiles)/\(workspace)/\(relative)")
            }
        }
        let here = (#filePath as NSString).deletingLastPathComponent
        candidates.append((here as NSString).deletingLastPathComponent + "/Sources/VitruvianCode/\(name)")
        guard let path = candidates.first(where: { FileManager.default.fileExists(atPath: $0) }) else { return nil }
        return try? String(contentsOfFile: path, encoding: .utf8)
    }
}
