// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import AppKit
import VitruvianCourierCore
import SwiftUI
import XCTest

@testable import VitruvianCourier

/// The viewer's filmstrip tile for media with no thumbnail yet: a `photo` or `video` symbol, centred, at about 40% of
/// the tile, in `.secondary` on the dark tile. Look at filmstrip-tile-*: a photo, a video and a sticker, light and dark.
@MainActor
final class FilmstripPlaceholderTests: XCTestCase {
    private func item(_ kind: MessageKind) -> CarouselItem {
        CarouselItem(eventID: "$e-\(kind)", roomID: "!r:courier.local", kind: kind, mediaPath: "", thumbnailPath: "")
    }

    func testPlaceholderSymbolFollowsTheKindOfMedia() {
        XCTAssertEqual(CarouselFilmstripTile.placeholderSymbol(for: .image), "photo")
        XCTAssertEqual(CarouselFilmstripTile.placeholderSymbol(for: .sticker), "photo")
        XCTAssertEqual(CarouselFilmstripTile.placeholderSymbol(for: .video), "video")
        XCTAssertEqual(CarouselFilmstripTile.placeholderSymbolFraction, 0.4, accuracy: 0.001)
    }

    /// Draws the tile in a 48 pt square and returns its pixels (dark appearance) as 8-bit grey, row by row.
    private func render(_ kind: MessageKind) throws -> (grey: [UInt8], side: Int) {
        let name = "filmstrip-tile-\(kind)"
        try Snapshot.render(name, width: CarouselFilmstripTile.tileSize, height: CarouselFilmstripTile.tileSize) {
            CarouselFilmstripTile(item: item(kind), isSelected: false, action: {})
        }
        let url = Snapshot.directory.appendingPathComponent("\(name)-dark.png")
        let rep = try XCTUnwrap(NSBitmapImageRep(data: try Data(contentsOf: url)))
        var grey: [UInt8] = []
        for y in 0 ..< rep.pixelsHigh {
            for x in 0 ..< rep.pixelsWide {
                let color = try XCTUnwrap(rep.colorAt(x: x, y: y)?.usingColorSpace(.deviceGray))
                grey.append(UInt8((color.whiteComponent * 255).rounded()))
            }
        }
        return (grey, rep.pixelsWide)
    }

    func testTheTileShowsASymbolInTheMiddleOnADarkTile() throws {
        for kind in [MessageKind.image, .video, .sticker] {
            let (grey, side) = try render(kind)
            // Away from the symbol (an inner corner, clear of the rounded corner) it is the plain dark tile. Read it back
            // from the picture rather than assume a value: the grey conversion shifts it.
            let tile = grey[side / 6 * side + side / 6]
            XCTAssertLessThan(Int(tile), 90, "\(kind): the tile is dark")
            // The middle 40% holds the symbol, lighter than the tile (`.secondary` on dark).
            let lo = Int(Double(side) * 0.3), hi = Int(Double(side) * 0.7)
            var brightest: UInt8 = 0
            var lit = 0
            for y in lo ..< hi {
                for x in lo ..< hi {
                    brightest = max(brightest, grey[y * side + x])
                    if Int(grey[y * side + x]) > Int(tile) + 40 { lit += 1 }
                }
            }
            XCTAssertGreaterThan(Int(brightest), Int(tile) + 40, "\(kind): a symbol is drawn in the middle")
            XCTAssertGreaterThan(lit, 10, "\(kind): the symbol covers more than a speck")
            // The symbol stays inside about 40% of the tile: the outer ring is untouched.
            let margin = Int(Double(side) * 0.2)
            for y in 0 ..< side {
                for x in 0 ..< side where x < margin || x >= side - margin || y < margin || y >= side - margin {
                    if (6 ..< side - 6).contains(x), (6 ..< side - 6).contains(y) {
                        XCTAssertLessThan(Int(grey[y * side + x]), Int(tile) + 40, "\(kind): symbol too big at \(x),\(y)")
                    }
                }
            }
        }
    }

    func testVideoAndPhotoPlaceholdersDiffer() throws {
        XCTAssertNotEqual(try render(.image).grey, try render(.video).grey)
    }
}

/// The routine link style's cues for a pointer and for the keyboard.
final class RoutineLinkStyleTests: XCTestCase {
    func testALinkIsUnderlinedUnderThePointerOrWithKeyboardFocus() {
        XCTAssertFalse(RoutineLinkButtonStyle.isUnderlined(hovered: false, focused: false))
        XCTAssertTrue(RoutineLinkButtonStyle.isUnderlined(hovered: true, focused: false))
        XCTAssertTrue(RoutineLinkButtonStyle.isUnderlined(hovered: false, focused: true))
    }
}
