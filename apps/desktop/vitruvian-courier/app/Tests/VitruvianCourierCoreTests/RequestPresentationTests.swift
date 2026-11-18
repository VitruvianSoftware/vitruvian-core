// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import XCTest

@testable import VitruvianCourierCore

final class RequestPresentationTests: XCTestCase {
    func testPlaceholderNames() {
        for name in ["Facebook user", "facebook user", "  Instagram user ", "", "   "] {
            XCTAssertTrue(RequestPresentation.isPlaceholderName(name), name)
        }
        for name in ["Ana Silva", "Facebook User Group Admin", "Instagram"] {
            XCTAssertFalse(RequestPresentation.isPlaceholderName(name), name)
        }
    }

    func testRealNameIsKept() {
        XCTAssertEqual(RequestPresentation.title(name: "Ana Silva", networkName: "Messenger"), "Ana Silva")
    }

    func testPlaceholderFallsBackToHandleThenUnknownContact() {
        XCTAssertEqual(RequestPresentation.title(name: "Facebook user", handle: "@ana.s", networkName: "Messenger"),
                       "@ana.s")
        XCTAssertEqual(RequestPresentation.title(name: "Facebook user", handle: "   ", networkName: "Messenger"),
                       "Unknown Messenger contact")
        XCTAssertEqual(RequestPresentation.title(name: "Facebook user", networkName: "Messenger"),
                       "Unknown Messenger contact")
        XCTAssertEqual(RequestPresentation.title(name: "   ", networkName: "  Instagram  "),
                       "Unknown Instagram contact")
        XCTAssertEqual(RequestPresentation.title(name: "", networkName: ""), "Unknown contact")
    }

    func testAllKnownNetworkPlaceholdersAreRecognised() {
        let placeholders = [
            "WhatsApp user", "Telegram user", "Signal user", "Messenger user",
            "LinkedIn user", "Twitter user", "X user", "TikTok user",
            "LINE user", "Discord user", "Slack user", "Unknown user", "unknown",
        ]
        for placeholder in placeholders {
            XCTAssertTrue(RequestPresentation.isPlaceholderName(placeholder), placeholder)
        }
    }

    func testEmptyViewsLeadSomewhereUseful() {
        func guidance(_ space: String, filters: Set<InboxFilter> = []) -> EmptyStateGuidance {
            EmptyStateGuidance.of(InboxQuery(space: space, filters: filters))
        }
        for space in ["send_later", "reminders", "archive", "low_priority"] {
            XCTAssertEqual(guidance(space).actions, [.goToInbox], space)
        }
        for filter: InboxFilter in [.sendLater, .reminders, .archived, .lowPriority] {
            XCTAssertEqual(guidance("inbox", filters: [filter]).actions, [.goToInbox], filter.rawValue)
            XCTAssertEqual(guidance("inbox", filters: [.unread, filter]).actions, [.goToInbox], filter.rawValue)
        }
        XCTAssertEqual(guidance("send_later").howTo, "Right-click Send, or choose Send Later from the + menu.")
        XCTAssertEqual(guidance("inbox", filters: [.sendLater]).howTo,
                       "Right-click Send, or choose Send Later from the + menu.")
        for space in ["reminders", "archive", "low_priority", "inbox", "requests", "label:1", "account:whatsapp"] {
            XCTAssertNil(guidance(space).howTo, space)
        }
        for space in ["inbox", "requests", "label:1", "account:whatsapp"] {
            XCTAssertEqual(guidance(space).actions, [], space)
        }
        for filter: InboxFilter in [.unread, .drafts, .requests, .hidden, .muted] {
            XCTAssertEqual(guidance("inbox", filters: [filter]).actions, [], filter.rawValue)
        }
    }

    // MARK: Second line, handle, label

    private let london = TimeZone(identifier: "Europe/London")!
    private let us = Locale(identifier: "en_US")

    func testPreviewsOnAlwaysShowThePreview() {
        XCTAssertEqual(RequestPresentation.detail(showPreviews: true, handle: "@ana", lastTS: 5), .preview)
        XCTAssertEqual(RequestPresentation.detail(showPreviews: true, handle: "", lastTS: 0), .preview)
    }

    func testPreviewsOffShowHandleElseDateAndTime() {
        // 2026-11-14 15:12 UTC
        let ts: Int64 = 1_794_669_120_000
        XCTAssertEqual(RequestPresentation.detail(showPreviews: false, handle: " @ana.s ", lastTS: ts,
                                                  locale: us, timeZone: london), .text("@ana.s"))
        XCTAssertEqual(RequestPresentation.detail(showPreviews: false, handle: "", lastTS: ts,
                                                  locale: us, timeZone: london), .text("Nov 14, 3:12 PM"))
        XCTAssertEqual(RequestPresentation.detail(showPreviews: false, handle: "", lastTS: 0,
                                                  locale: us, timeZone: london), .text("Message request"))
    }

    func testTwoRequestsOnOneNetworkDifferWithPreviewsOff() {
        let a = RequestPresentation.detail(showPreviews: false, handle: "", lastTS: 1_794_669_120_000,
                                           locale: us, timeZone: london)
        let b = RequestPresentation.detail(showPreviews: false, handle: "", lastTS: 1_794_669_120_000 + 3_600_000 * 26,
                                           locale: us, timeZone: london)
        XCTAssertNotEqual(a, b)
        XCTAssertNotEqual(
            RequestPresentation.accessibilityLabel(title: "Unknown Messenger contact", networkName: "Messenger",
                                                   detail: "\(a)"),
            RequestPresentation.accessibilityLabel(title: "Unknown Messenger contact", networkName: "Messenger",
                                                   detail: "\(b)"))
    }

    func testAccessibilityLabelNamesWhoNetworkAndDetail() {
        XCTAssertEqual(
            RequestPresentation.accessibilityLabel(title: "@ana", networkName: "Messenger", detail: "Nov 14, 3:12 PM"),
            "@ana, Messenger, Message request, Nov 14, 3:12 PM")
    }

    func testHandleComesFromTheFirstHumanMemberWithOne() {
        func member(_ id: String, ids: [String], bot: Bool = false) -> Member {
            Member(userID: id, name: id, avatarPath: "", powerLevel: 0, isAdmin: false, identifiers: ids, tz: "", isBot: bot)
        }
        XCTAssertEqual(RequestPresentation.handle(from: [
            member("@bot", ids: ["bridge"], bot: true), member("@a", ids: []), member("@b", ids: ["", " @ana.s "]),
        ]), "@ana.s")
        XCTAssertEqual(RequestPresentation.handle(from: []), "")
    }
}

private final class Clock: @unchecked Sendable {
    var date = Date(timeIntervalSince1970: 1_000_000)
}

private actor Probe {
    var calls: [String] = []
    var active = 0
    var peak = 0
    var failing: Set<String> = []

    func fail(_ ids: Set<String>) { failing = ids }
    func enter(_ id: String) { calls.append(id); active += 1; peak = max(peak, active) }
    func leave() { active -= 1 }
    func shouldFail(_ id: String) -> Bool { failing.contains(id) }
}

@MainActor
final class RequestHandleLoaderTests: XCTestCase {
    private struct Down: Error {}

    private func row(_ id: String, name: String = "Facebook user", request: Bool = true) -> InboxRow {
        InboxRow(roomID: id, network: "facebook", name: name, avatarPath: "", isDirect: true, lastTS: 1,
                 preview: "hi", previewKind: .text, previewMine: false, unread: 1, muted: false, request: request)
    }

    private func fetch(_ probe: Probe, handle: String = "@ana", pause: Bool = false) -> RequestHandleLoader.Fetch {
        { id in
            await probe.enter(id)
            if pause { try? await Task.sleep(for: .milliseconds(20)) }
            await probe.leave()
            if await probe.shouldFail(id) { throw Down() }
            return handle.isEmpty ? [] : [Member(userID: "@u", name: "U", identifiers: [handle])]
        }
    }

    func testOnlyPlaceholderNamedRequestsAreLookedUp() {
        let rows = [row("!a"), row("!b", name: "Ana Silva"), row("!c", name: ""), row("!d", request: false)]
        XCTAssertEqual(RequestHandleLoader.candidates(in: rows), ["!a", "!c"])
    }

    func testFailureIsNotCachedAndIsRetriedAfterBackoff() async {
        let clock = Clock()
        let loader = RequestHandleLoader(now: { clock.date })
        let probe = Probe()
        await probe.fail(["!a"])
        let delay = await loader.run(candidates: { ["!a"] }, fetch: fetch(probe))
        XCTAssertEqual(delay, 30)
        XCTAssertNil(loader.handles["!a"], "an error must not cache an empty handle")
        var calls = await probe.calls
        XCTAssertEqual(calls, ["!a"])

        // Too soon: not asked again.
        clock.date.addTimeInterval(10)
        _ = await loader.run(candidates: { ["!a"] }, fetch: fetch(probe))
        calls = await probe.calls
        XCTAssertEqual(calls, ["!a"])

        // After the wait it fails again, and the wait doubles.
        clock.date.addTimeInterval(21)
        let second = await loader.run(candidates: { ["!a"] }, fetch: fetch(probe))
        XCTAssertEqual(second, 60)
        calls = await probe.calls
        XCTAssertEqual(calls, ["!a", "!a"])

        // The engine recovers: the handle is cached and never asked for again.
        await probe.fail([])
        clock.date.addTimeInterval(61)
        let done = await loader.run(candidates: { ["!a"] }, fetch: fetch(probe))
        XCTAssertNil(done)
        XCTAssertEqual(loader.handles["!a"], "@ana")
        _ = await loader.run(candidates: { ["!a"] }, fetch: fetch(probe))
        calls = await probe.calls
        XCTAssertEqual(calls.count, 3)
    }

    func testNoneFoundIsASuccessAndIsCached() async {
        let loader = RequestHandleLoader()
        let probe = Probe()
        let delay = await loader.run(candidates: { ["!a"] }, fetch: fetch(probe, handle: ""))
        XCTAssertNil(delay)
        XCTAssertEqual(loader.handles["!a"], "")
        _ = await loader.run(candidates: { ["!a"] }, fetch: fetch(probe, handle: ""))
        let calls = await probe.calls
        XCTAssertEqual(calls, ["!a"])
    }

    func testBackoffDoublesFrom30SecondsToTenMinutes() {
        XCTAssertEqual((1 ... 8).map { RequestHandleLoader.delay(afterFailures: $0) },
                       [30, 60, 120, 240, 480, 600, 600, 600])
    }

    func testEveryCandidateIsLookedUpWithAtMostFourAtOnce() async {
        let loader = RequestHandleLoader()
        let probe = Probe()
        let ids = (1 ... 30).map { "!r\($0)" }
        _ = await loader.run(candidates: { ids }, fetch: fetch(probe, pause: true))
        let calls = await probe.calls
        let peak = await probe.peak
        XCTAssertEqual(Set(calls), Set(ids), "no cap of 20 per refresh")
        XCTAssertEqual(calls.count, 30)
        XCTAssertLessThanOrEqual(peak, 4)
        XCTAssertEqual(loader.handles.count, 30)
    }
}
