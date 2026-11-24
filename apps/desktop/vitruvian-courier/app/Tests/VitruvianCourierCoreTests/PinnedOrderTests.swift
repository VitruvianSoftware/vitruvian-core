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

    func testAListMoveLandsBeforeTheDestinationRow() {
        let order = ["a", "b", "c", "d"]
        // Down: "a" dropped between "c" and "d".
        XCTAssertEqual(PinnedOrder.moving(fromOffsets: [0], toOffset: 3, in: order), ["b", "c", "a", "d"])
        // Up, to the top and to the very end.
        XCTAssertEqual(PinnedOrder.moving(fromOffsets: [3], toOffset: 0, in: order), ["d", "a", "b", "c"])
        XCTAssertEqual(PinnedOrder.moving(fromOffsets: [0], toOffset: 4, in: order), ["b", "c", "d", "a"])
        // Dropped where it already was, on either side of itself: nothing changes.
        XCTAssertEqual(PinnedOrder.moving(fromOffsets: [1], toOffset: 1, in: order), order)
        XCTAssertEqual(PinnedOrder.moving(fromOffsets: [1], toOffset: 2, in: order), order)
        // Several at once keep their order; bad input changes nothing it shouldn't.
        XCTAssertEqual(PinnedOrder.moving(fromOffsets: [0, 2], toOffset: 4, in: order), ["b", "d", "a", "c"])
        XCTAssertEqual(PinnedOrder.moving(fromOffsets: [9], toOffset: 1, in: order), order)
        XCTAssertEqual(PinnedOrder.moving(fromOffsets: [3], toOffset: 99, in: order), order)
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

    // MARK: The drag's steps

    func testADragThatMovesAndDropsSavesTheNewOrder() {
        var drag = PinnedDragState()
        let order = ["a", "b", "c", "d"]
        drag.begin("a", order: order)
        XCTAssertEqual(drag.fadedID, "a")
        XCTAssertTrue(drag.move(over: "c", order: order))
        XCTAssertEqual(drag.draft, ["b", "c", "a", "d"])
        XCTAssertFalse(drag.move(over: "a", order: order), "over itself nothing moves")
        XCTAssertFalse(drag.move(over: nil, order: order), "a gap moves nothing")
        XCTAssertEqual(drag.drop(order: order), ["b", "c", "a", "d"])
        XCTAssertNil(drag.fadedID)
        XCTAssertFalse(drag.canDrop)
        XCTAssertEqual(drag.draft, ["b", "c", "a", "d"], "the dropped order stays drawn until the saved one arrives")
        drag.committed()
        XCTAssertNil(drag.draft)
    }

    func testLeavingTheStripPutsTheTilesBackAndComingBackResumes() {
        var drag = PinnedDragState()
        let order = ["a", "b", "c"]
        drag.begin("a", order: order)
        drag.move(over: "c", order: order)
        drag.exit()
        XCTAssertNil(drag.draft, "out of the strip (or cancelled there) the tiles go back")
        XCTAssertNil(drag.fadedID)
        XCTAssertTrue(drag.canDrop, "the same drag may come back")
        XCTAssertTrue(drag.move(over: "b", order: order))
        XCTAssertEqual(drag.draft, ["b", "a", "c"])
        XCTAssertEqual(drag.fadedID, "a")
    }

    func testDroppingWithoutMovingSavesNothing() {
        var drag = PinnedDragState()
        drag.begin("a", order: ["a", "b"])
        XCTAssertNil(drag.drop(order: ["a", "b"]))
        XCTAssertNil(drag.draft)
        var none = PinnedDragState()
        XCTAssertNil(none.drop(order: ["a", "b"]), "a drop with no drag of ours saves nothing")
    }

    func testRowsChangingOrADisallowedDragEndsIt() {
        var drag = PinnedDragState()
        drag.begin("a", order: ["a", "b", "c"])
        drag.move(over: "b", order: ["a", "b", "c"])
        drag.rowsChanged(["a", "b", "c", "d"])
        XCTAssertNil(drag.draft, "the rows' own order takes over")
        XCTAssertTrue(drag.canDrop, "the dragged tile is still there")
        drag.rowsChanged(["b", "c"])
        XCTAssertFalse(drag.canDrop, "its tile was unpinned: the drag ends")
        XCTAssertNil(drag.fadedID)

        var locked = PinnedDragState()
        locked.begin("a", order: ["a", "b"])
        locked.cancel()
        XCTAssertEqual(locked, PinnedDragState())
    }

    func testASaveFinishingDuringTheNextDragLeavesThatDragAlone() {
        var drag = PinnedDragState()
        drag.begin("a", order: ["a", "b", "c"])
        drag.move(over: "c", order: ["a", "b", "c"])
        _ = drag.drop(order: ["a", "b", "c"])
        drag.begin("b", order: ["b", "c", "a"])
        drag.move(over: "a", order: ["b", "c", "a"])
        drag.committed()
        XCTAssertEqual(drag.draft, ["c", "a", "b"], "the earlier save doesn't wipe the drag under way")
    }
}
