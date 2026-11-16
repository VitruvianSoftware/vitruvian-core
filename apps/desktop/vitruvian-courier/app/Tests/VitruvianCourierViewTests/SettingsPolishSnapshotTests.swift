// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import AppKit
import VitruvianCourierCore
import SwiftUI
import XCTest

@testable import VitruvianCourier

/// The Settings window's look: the Labs tag, the sidebar's icon tiles, and the Notifications pane with each setting on its
/// own row. Look at settings-labs-badge-*, settings-sidebar-tiles-* and settings-notifications-pane-*.
@MainActor
final class SettingsPolishSnapshotTests: XCTestCase {
    /// How far apart the strongest and weakest of red, green and blue are, over every opaque pixel of `name`-`suffix`.png:
    /// 0 for greys, large for a coloured pixel.
    private func greatestChroma(of name: String, suffix: String) throws -> Int {
        let url = Snapshot.directory.appendingPathComponent("\(name)-\(suffix).png")
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: Data(contentsOf: url)))
        var greatest = 0
        for y in 0 ..< bitmap.pixelsHigh {
            for x in 0 ..< bitmap.pixelsWide {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB), color.alphaComponent > 0.5
                else { continue }
                let channels = [color.redComponent, color.greenComponent, color.blueComponent]
                greatest = max(greatest, Int(((channels.max() ?? 0) - (channels.min() ?? 0)) * 255))
            }
        }
        return greatest
    }

    /// "Labs" says "experimental", not "problem": secondary text on a faint fill, whatever the accent colour is.
    func testLabsTagIsNeutralInLightAndDark() throws {
        let sizes = try Snapshot.render("settings-labs-badge", width: 120, height: 32) {
            HStack { SettingBadgeView(badge: .labs) }.padding(6).tint(.red)
        }
        XCTAssertEqual(sizes.count, 2)
        for suffix in ["light", "dark"] {
            XCTAssertLessThan(try greatestChroma(of: "settings-labs-badge", suffix: suffix), 24,
                              "the Labs tag takes a colour in \(suffix) mode")
        }
    }

    /// Each sidebar row has a solid coloured tile, 20 points across, with a white symbol.
    func testSidebarTilesAreTwentyPointsAndEachRowHasItsColour() throws {
        let sizes = try Snapshot.render("settings-sidebar-tiles", width: 240) {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(SettingsSidebar.items) { item in
                    HStack(spacing: 9) {
                        SettingsIconTile(symbolName: item.symbolName, color: item.tile.color)
                        Text(item.title)
                        Spacer()
                    }
                }
            }
            .padding(12)
        }
        XCTAssertEqual(sizes.count, 2)
        let tile = NSHostingView(rootView: SettingsIconTile(symbolName: "gearshape", color: .gray))
        XCTAssertEqual(tile.fittingSize.width, 20, accuracy: 0.5)
        XCTAssertEqual(tile.fittingSize.height, 20, accuracy: 0.5)
    }

    /// Notifications: the sound pickers are rows of their own under their toggle, and the delay has its footnote.
    func testNotificationsPaneSnapshotWithAlertOffAndFootnote() throws {
        let suite = "courier.snapshots.settings-polish.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(ScratchDefaults.suite(named: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = NotificationPreferences(defaults: defaults)
        preferences.messageNotificationsEnabled = false
        let lifecycle = SystemLifecycleModel(
            loginItemService: SnapshotLoginItemService(),
            biometricService: SnapshotBiometricService(),
            defaults: try XCTUnwrap(ScratchDefaults.suite(named: "\(suite).lifecycle"))
        )
        let sizes = try Snapshot.render("settings-notifications-pane", width: 720, height: 900) {
            NotificationsSettingsPane(preferences: preferences, accounts: [], lifecycle: lifecycle)
        }
        XCTAssertEqual(sizes.count, 2)
    }
}
