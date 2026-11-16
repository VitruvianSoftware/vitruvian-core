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

    /// The switch keeps its colour in a window that is not in front (these windows are never shown, so none is key):
    /// the system's own switch is grey and white there, which is what made "on" and "off" look alike. Look at
    /// settings-switch-on-* and settings-switch-off-*.
    func testSwitchKeepsItsColourWhenOnEvenInAWindowNotInFront() throws {
        for (name, isOn) in [("settings-switch-on", true), ("settings-switch-off", false)] {
            let sizes = try Snapshot.render(name, width: 160, height: 40) {
                Toggle("Switch", isOn: .constant(isOn))
                    .toggleStyle(SettingsSwitchToggleStyle())
                    .tint(.blue)
                    .padding(8)
            }
            XCTAssertEqual(sizes.count, 2)
            for suffix in ["light", "dark"] {
                let chroma = try greatestChroma(of: name, suffix: suffix)
                if isOn {
                    XCTAssertGreaterThan(chroma, 120, "an 'on' switch is grey in \(suffix) mode")
                } else {
                    XCTAssertLessThan(chroma, 24, "an 'off' switch takes a colour in \(suffix) mode")
                }
            }
        }
    }

    /// The card at the top of the sidebar, with the longest text it shows, fits the sidebar's width without cutting
    /// the count short. Look at settings-account-card-*.
    func testAccountCardShowsItsFullTextAtSidebarWidth() throws {
        let accounts = (0 ..< 10).map { Account(network: "net\($0)", displayName: "N", flows: [], state: .connected) }
        let card = SettingsAccountCard.make(accounts: accounts)
        XCTAssertEqual(card.title, "10 accounts connected")
        var pressed = 0
        let sizes = try Snapshot.render("settings-account-card", width: 244) {
            SettingsAccountCardView(card: card) { pressed += 1 }.padding(12)
        }
        XCTAssertEqual(sizes.count, 2)
        let font = NSFont.systemFont(ofSize: NSFont.preferredFont(forTextStyle: .subheadline).pointSize, weight: .semibold)
        let titleWidth = (card.title as NSString).size(withAttributes: [.font: font]).width
        // The card is 244 wide, less 12 either side, 10 either side inside, the 34 picture, 10 and 6 of gaps, the chevron.
        XCTAssertLessThan(titleWidth, 244 - 24 - 20 - 34 - 10 - 6 - 10, "the card's title no longer fits")
        XCTAssertEqual(pressed, 0)
    }
}
