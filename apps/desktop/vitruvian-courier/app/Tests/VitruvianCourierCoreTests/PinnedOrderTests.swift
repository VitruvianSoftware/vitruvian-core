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

    /// The strip has one drop target and finds the tile under the pointer from the tiles' frames.
    func testTileAtFindsTheTileUnderThePointerAndNoneInTheGaps() {
        let frames: [String: CGRect] = [
            "a": CGRect(x: 10, y: 8, width: 84, height: 70),
            "b": CGRect(x: 100, y: 8, width: 84, height: 70),
        ]
        XCTAssertEqual(PinnedOrder.tile(at: CGPoint(x: 50, y: 40), in: frames), "a")
        XCTAssertEqual(PinnedOrder.tile(at: CGPoint(x: 140, y: 40), in: frames), "b")
        XCTAssertNil(PinnedOrder.tile(at: CGPoint(x: 97, y: 40), in: frames), "the gap between tiles is no tile")
        XCTAssertNil(PinnedOrder.tile(at: CGPoint(x: 50, y: 90), in: frames), "below the tiles")
        XCTAssertNil(PinnedOrder.tile(at: .zero, in: [:]))
    }
}
