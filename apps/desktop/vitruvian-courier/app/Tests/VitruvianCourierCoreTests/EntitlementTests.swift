// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import XCTest

@testable import CourierCore

/// The plan seam (spec §3): the only provider says yes, and a feature that is denied calls nothing.
@MainActor
final class EntitlementTests: XCTestCase {
    private var harnesses: [InboxHarness] = []

    override func tearDown() async throws {
        for harness in harnesses {
            await harness.app.stop()
            harness.cleanUp()
        }
        harnesses = []
    }

    /// A plan without these features.
    private struct Denies: EntitlementProvider {
        let denied: Set<Feature>
        func isEntitled(_ feature: Feature) -> Bool { !denied.contains(feature) }
    }

    func testAlwaysEntitledAllowsEveryFeature() {
        let provider = AlwaysEntitled()
        for feature in Feature.allCases { XCTAssertTrue(provider.isEntitled(feature), feature.rawValue) }
        XCTAssertEqual(Feature.allCases.map(\.rawValue),
                       ["reminders", "send_later", "undo_send", "incognito", "low_priority", "auto_archive"])
    }

    func testDeniedReminderShowsAPlanToastAndCallsNothing() async throws {
        let h = try await startInbox(rooms: [room("!a", ts: 200), room("!b", ts: 100)], autoRelease: true,
                                     entitlement: Denies(denied: [.reminders, .lowPriority]))
        harnesses.append(h)
        h.inbox.select("!a")

        await h.inbox.remind(at: Date().addingTimeInterval(3600), condition: .ifNoReply)
        XCTAssertEqual(h.inbox.toast?.message, "Available with a plan")
        XCTAssertEqual(h.inbox.toast?.canUndo, false)
        XCTAssertEqual(h.count("reminder.set"), 0)
        XCTAssertNil(h.preferences.lastUsedReminder, "a reminder that was not set is not remembered")

        await h.inbox.setLowPriority(true)
        XCTAssertEqual(h.inbox.toast?.message, "Available with a plan")
        XCTAssertEqual(h.count("room.setLowPriority"), 0)

        // Moving chats back out of Low priority is never part of a plan.
        await h.inbox.setLowPriority(false)
        XCTAssertEqual(dicts(h.server.receivedParams("room.setLowPriority")),
                       dicts([["room_ids": ["!a"], "on": false]]))
    }

    /// An engine whose plan says no (-32022) says the same as the app's own check.
    func testTheEnginesNoSaysTheSame() async throws {
        let h = try await startInbox(rooms: [room("!a", ts: 200)], autoRelease: true)
        harnesses.append(h)
        h.script.fail("reminder.set", code: -32022)
        h.inbox.select("!a")
        await h.inbox.remind(at: Date().addingTimeInterval(3600), condition: .always)
        XCTAssertEqual(h.count("reminder.set"), 1)
        XCTAssertEqual(h.inbox.toast?.message, "Available with a plan")
    }

    func testPlanSummaryAndFreebieNudgeForAlwaysEntitledAndNoPlan() {
        let entitled = AlwaysEntitled()
        let entitledSummary = entitled.planSummary
        XCTAssertEqual(entitledSummary.badgeTitle, "Included")
        XCTAssertEqual(entitledSummary.bannerState, .activeIncluded)
        XCTAssertEqual(entitledSummary.featureRows.count, 6)
        XCTAssertTrue(entitledSummary.featureRows.allSatisfy(\.isAllowedNow))
        for feature in Feature.allCases {
            XCTAssertNil(entitled.freebieNudgeText(for: feature))
        }

        let noPlan = NoPlan()
        let noPlanSummary = noPlan.planSummary
        XCTAssertEqual(noPlanSummary.badgeTitle, "Free")
        XCTAssertEqual(noPlanSummary.headline, "Available with a plan")
        XCTAssertEqual(noPlanSummary.featureRows.count, 6)
        XCTAssertTrue(noPlanSummary.featureRows.allSatisfy { !$0.isAllowedNow })
        XCTAssertEqual(noPlan.freebieNudgeText(for: .incognito), "Available with a plan")
        for feature in Feature.allCases {
            XCTAssertEqual(noPlan.freebieNudgeText(for: feature), "Available with a plan")
        }
    }
}
