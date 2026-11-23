// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import XCTest

@testable import VitruvianCourierCore

final class PinnedOrderTests: XCTestCase {
    private struct Item: Identifiable, Equatable {
        let id: String
    }

    func testMovingReordersTargetAndHandlesEdgeCases() {
        let order = ["a", "b", "c", "d"]

        XCTAssertEqual(PinnedOrder.moving("a", onto: "c", in: order), ["b", "c", "a", "d"])
        XCTAssertEqual(PinnedOrder.moving("d", onto: "b", in: order), ["a", "d", "b", "c"])
        XCTAssertEqual(PinnedOrder.moving("a", onto: "b", in: order), ["b", "a", "c", "d"])
        XCTAssertEqual(PinnedOrder.moving("b", onto: "a", in: order), ["b", "a", "c", "d"])
        XCTAssertEqual(PinnedOrder.moving("b", onto: "b", in: order), order)
        XCTAssertEqual(PinnedOrder.moving("missing", onto: "b", in: order), order)
        XCTAssertEqual(PinnedOrder.moving("b", onto: "missing", in: order), order)
        XCTAssertEqual(PinnedOrder.moving("a", onto: "b", in: []), [])
        XCTAssertEqual(PinnedOrder.moving("a", onto: "a", in: ["a"]), ["a"])
    }

    func testOrderedAppliesDraftDeduplicatesIgnoresUnknownAndKeepsUnmentioned() {
        let items = [Item(id: "a"), Item(id: "b"), Item(id: "c"), Item(id: "d")]

        XCTAssertEqual(PinnedOrder.ordered(items, by: nil), items)
        XCTAssertEqual(
            PinnedOrder.ordered(items, by: ["c", "unknown", "a", "c"]).map(\.id),
            ["c", "a", "b", "d"]
        )
        XCTAssertEqual(
            PinnedOrder.ordered(items, by: ["d", "c", "b", "a"]).map(\.id),
            ["d", "c", "b", "a"]
        )
    }
}
