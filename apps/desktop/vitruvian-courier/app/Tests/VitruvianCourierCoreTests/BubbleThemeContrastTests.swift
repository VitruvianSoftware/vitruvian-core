// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import XCTest
@testable import VitruvianCourierCore

/// Outgoing bubbles must be vivid with white text readable on them; incoming bubbles neutral; and the two clearly
/// apart, in every preset, light and dark.
final class BubbleThemeContrastTests: XCTestCase {
    private func pairs(_ preset: CourierThemePreset) -> [(mode: String, out: String, inc: String)] {
        [("light", preset.defaultOutgoingBubbleHexLight, preset.defaultIncomingBubbleHexLight),
         ("dark", preset.defaultOutgoingBubbleHexDark, preset.defaultIncomingBubbleHexDark)]
    }

    func testOutgoingIsVividAndIncomingIsNeutralInEveryPreset() {
        for preset in CourierThemePreset.allCases {
            for p in pairs(preset) {
                XCTAssertGreaterThanOrEqual(HexColorMetrics.saturation(p.out), 0.6, "\(preset) \(p.mode) outgoing not vivid")
                XCTAssertLessThanOrEqual(HexColorMetrics.saturation(p.inc), 0.2, "\(preset) \(p.mode) incoming not neutral")
            }
        }
    }

    func testOutgoingAndIncomingAreClearlySeparated() {
        for preset in CourierThemePreset.allCases {
            for p in pairs(preset) {
                let satGap = HexColorMetrics.saturation(p.out) - HexColorMetrics.saturation(p.inc)
                XCTAssertGreaterThanOrEqual(satGap, 0.45, "\(preset) \(p.mode) saturation gap")
                XCTAssertGreaterThanOrEqual(HexColorMetrics.contrast(p.out, p.inc), 2.0, "\(preset) \(p.mode) luminance gap")
            }
        }
    }

    func testWhiteTextIsReadableOnOutgoing() {
        for preset in CourierThemePreset.allCases {
            for p in pairs(preset) {
                XCTAssertGreaterThanOrEqual(HexColorMetrics.contrast("#FFFFFF", p.out), 4.5, "\(preset) \(p.mode) white-on-outgoing")
            }
        }
    }

    func testSenderNameColoursAreLegibleOnIncomingBubbles() {
        for preset in CourierThemePreset.allCases {
            for p in pairs(preset) {
                let isDark = p.mode == "dark"
                for index in 0 ..< 200 {
                    let hex = AppearancePreferences.senderNameColorHex(for: "@user\(index):hs", isDark: isDark)
                    XCTAssertGreaterThanOrEqual(HexColorMetrics.contrast(hex, p.inc), 4.5, "\(hex) on \(p.inc) (\(preset) \(p.mode))")
                }
            }
        }
    }

    func testSenderNameColourIsDeterministicAndVaried() {
        XCTAssertEqual(AppearancePreferences.senderNameColorHex(for: "@a:b", isDark: true),
                       AppearancePreferences.senderNameColorHex(for: "@a:b", isDark: true))
        let distinct = Set((0 ..< 50).map { AppearancePreferences.senderNameColorHex(for: "u\($0)", isDark: true) })
        XCTAssertGreaterThanOrEqual(distinct.count, 6)
    }
}
