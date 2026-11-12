// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import AppKit
import SwiftUI
import VitruvianCourierCore
import XCTest

@testable import VitruvianCourier

/// Every chat background can be drawn, light and dark, at a small and a large size.
///
/// Choosing Starfield crashed the app (0.3.17): the star positions were worked out with a 64-bit number squeezed into
/// a 32-bit one, which Swift stops the app on. The choice is saved, so the app crashed again on every launch. Drawing
/// each background here, the way a chat draws it, catches that kind of mistake before a person picks it.
@MainActor
final class WallpaperDrawingTests: XCTestCase {
    func testEveryBackgroundDraws() throws {
        for preset in CourierWallpaperPreset.allCases {
            for (width, height) in [(CGFloat(120), CGFloat(80)), (900, 1200)] {
                let sizes = try Snapshot.render("wallpaper-\(preset.rawValue)-\(Int(width))", width: width, height: height) {
                    ChatWallpaperCanvasView(preset: preset, opacity: 1)
                }
                XCTAssertFalse(sizes.isEmpty, "\(preset.rawValue) at \(width)×\(height)")
            }
        }
    }
}
