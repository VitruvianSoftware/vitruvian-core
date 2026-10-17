// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import XCTest

@testable import CourierCore

/// "Looking at the chat" is the window being key AND the screen unlocked AND the display awake AND someone having
/// touched the Mac in the last three minutes.
@MainActor
final class AttentionTests: XCTestCase {
    private func make() -> (Attention, StaticPresence, () -> Int) {
        let presence = StaticPresence()
        let attention = Attention(source: presence, pollInterval: nil)
        var returns = 0
        attention.onReturn { returns += 1 }
        return (attention, presence, { returns })
    }

    func testLookingNeedsEveryCondition() {
        let (attention, presence, _) = make()
        XCTAssertFalse(attention.isLooking, "no window is key yet")
        attention.setWindowKey(true)
        XCTAssertTrue(attention.isLooking)

        presence.isScreenLocked = true
        XCTAssertFalse(attention.isLooking, "a locked screen")
        presence.isScreenLocked = false
        presence.isDisplayAsleep = true
        XCTAssertFalse(attention.isLooking, "a sleeping display")
        presence.isDisplayAsleep = false
        presence.secondsSinceLastInput = Attention.idleLimit
        XCTAssertFalse(attention.isLooking, "three minutes without input")
        presence.secondsSinceLastInput = Attention.idleLimit - 1
        XCTAssertTrue(attention.isLooking)

        attention.setWindowKey(false)
        XCTAssertFalse(attention.isLooking, "the window went away, or is behind another app")
    }

    func testReturningRunsTheHooksOncePerReturn() {
        let (attention, presence, returns) = make()
        attention.setWindowKey(true)
        XCTAssertEqual(returns(), 1, "the window coming forward is a return")
        attention.reevaluate()
        XCTAssertEqual(returns(), 1, "still looking: nothing new")

        // Locking and unlocking come from the system as changes.
        presence.isScreenLocked = true
        presence.onChange?()
        presence.isScreenLocked = false
        presence.onChange?()
        XCTAssertEqual(returns(), 2)

        // Idle is found by looking again (the app polls while the window is key).
        presence.secondsSinceLastInput = 600
        attention.reevaluate()
        presence.secondsSinceLastInput = 1
        attention.reevaluate()
        XCTAssertEqual(returns(), 3, "coming back to the keyboard")

        attention.setWindowKey(false)
        attention.setWindowKey(true)
        XCTAssertEqual(returns(), 4)
    }

    func testPollingNoticesTheReturnFromIdle() async throws {
        let presence = StaticPresence()
        presence.secondsSinceLastInput = 600
        let attention = Attention(source: presence, pollInterval: 0.02)
        var returned = false
        attention.onReturn { returned = true }
        attention.setWindowKey(true)
        XCTAssertFalse(returned)
        presence.secondsSinceLastInput = 0
        try await waitUntil { returned }
        attention.setWindowKey(false)
    }
}
