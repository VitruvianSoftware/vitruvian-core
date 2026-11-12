// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import AppKit
import SwiftUI
import VitruvianCourierCore
import XCTest

@testable import VitruvianCourier

/// Every chat background can be drawn, light and dark, at any size a pane can be, with any saved settings.
///
/// Choosing Starfield crashed the app (0.3.17): the star positions were worked out with a 64-bit number squeezed into
/// a 32-bit one, which Swift stops the app on. The choice is saved, so the app crashed again on every launch. Drawing
/// each background here, the way a chat draws it, catches that kind of mistake before a person picks it.
@MainActor
final class WallpaperDrawingTests: XCTestCase {
    /// Sizes a chat pane can be: collapsed to nothing, a sliver, a phone-thin column, a wide strip, a tall 5K window.
    private static let sizes: [(CGFloat, CGFloat)] = [
        (0, 0), (1, 1), (120, 80), (40, 1400), (3000, 20), (900, 1200), (5120, 2880),
    ]

    func testEveryBackgroundDrawsAtEverySize() throws {
        for preset in CourierWallpaperPreset.allCases {
            for (width, height) in Self.sizes {
                let name = "wallpaper-\(preset.rawValue)-\(Int(width))x\(Int(height))"
                do {
                    let sizes = try Snapshot.render(name, width: width, height: height) {
                        ChatWallpaperCanvasView(preset: preset, opacity: 1)
                    }
                    XCTAssertFalse(sizes.isEmpty, name)
                } catch SnapshotError.noBitmap where width * height == 0 {
                    // The view was laid out and drawn; AppKit just has no picture of nothing to save.
                }
            }
        }
    }

    /// Saved settings outside the slider's range (an older version, or a hand-edited preference), blur, and
    /// Reduce Transparency.
    func testEveryBackgroundDrawsWithAnySettings() throws {
        for preset in CourierWallpaperPreset.allCases {
            for opacity in [-1.0, 0, 1, 7, .nan, .infinity] {
                for (blur, reduce) in [(false, false), (true, false), (true, true)] {
                    let name = "wallpaper-\(preset.rawValue)-settings"
                    let sizes = try Snapshot.render(name, width: 200, height: 150) {
                        ChatWallpaperCanvasView(preset: preset, opacity: opacity, blur: blur, reduceTransparency: reduce)
                    }
                    XCTAssertFalse(sizes.isEmpty, "\(name) opacity \(opacity) blur \(blur) reduce \(reduce)")
                }
            }
        }
    }

    /// A custom picture that has gone missing, is empty, or isn't a picture falls back to the chosen pattern.
    func testABrokenCustomPictureDoesNotCrash() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let empty = folder.appendingPathComponent("empty.png")
        let garbage = folder.appendingPathComponent("garbage.jpg")
        try Data().write(to: empty)
        try Data("not a picture".utf8).write(to: garbage)

        for path in ["", folder.appendingPathComponent("missing.png").path, empty.path, garbage.path, folder.path] {
            XCTAssertNil(WallpaperImageCache.shared.image(atPath: path), path)
            for preset in [CourierWallpaperPreset.none, .starfield] {
                let sizes = try Snapshot.render("wallpaper-broken-picture", width: 200, height: 150) {
                    ChatWallpaperCanvasView(preset: preset, customImagePath: path, opacity: 1, blur: true)
                }
                XCTAssertFalse(sizes.isEmpty, path)
            }
        }
    }
}
