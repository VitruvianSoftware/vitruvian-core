// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation

/// The solid colour behind a Settings sidebar icon, as macOS System Settings does it. Named after the system colours so
/// the view maps each one to its adaptive `Color`, which looks right in light and dark mode.
public enum SettingsTileColor: String, CaseIterable, Sendable {
    case gray, indigo, red, blue, brown, green, teal, orange, purple, pink, mint, cyan
}

/// One row of the Settings sidebar: a pane, its white symbol, and the colour of the rounded square behind it.
public struct SettingsSidebarItem: Identifiable, Equatable, Sendable {
    public let pane: SettingsPaneID
    public let tile: SettingsTileColor

    public var id: String { pane.id }
    public var title: String { pane.title }
    public var symbolName: String { pane.symbolName }

    public init(pane: SettingsPaneID, tile: SettingsTileColor) {
        self.pane = pane
        self.tile = tile
    }
}

/// The Settings sidebar's rows, in order. Each pane has its own tile colour, so a row is found by its colour as well
/// as by its name.
public enum SettingsSidebar {
    public static let items: [SettingsSidebarItem] = SettingsPaneID.allCases.map {
        SettingsSidebarItem(pane: $0, tile: tileColor(for: $0))
    }

    public static func tileColor(for pane: SettingsPaneID) -> SettingsTileColor {
        switch pane {
        case .general: .gray
        case .appearance: .indigo
        case .notifications: .red
        case .accounts: .blue
        case .hotkeys: .brown
        case .quickReplies: .green
        case .bridges: .teal
        case .storage: .orange
        case .ai: .purple
        case .plan: .pink
        case .integrations: .mint
        case .about: .cyan
        }
    }
}

/// The card at the top of the Settings sidebar. Vitruvian Courier has no sign-in of its own, so there is no name or
/// picture of the person to show: the card says how many accounts are connected, and which plan this Mac is on.
/// Clicking it opens Settings ▸ Accounts.
public struct SettingsAccountCard: Equatable, Sendable {
    public let connectedCount: Int
    /// "10 accounts connected".
    public let title: String
    /// The plan's name: "Vitruvian Courier Plan".
    public let subtitle: String

    public init(connectedCount: Int, title: String, subtitle: String) {
        self.connectedCount = connectedCount
        self.title = title
        self.subtitle = subtitle
    }

    /// How many accounts are signed in and working. A network with several accounts counts each; one without a list of
    /// accounts counts itself.
    public static func connectedCount(of accounts: [Account]) -> Int {
        accounts.reduce(0) { total, account in
            if account.logins.isEmpty {
                return total + (account.state == .connected ? 1 : 0)
            }
            return total + account.logins.filter { $0.state == .connected }.count
        }
    }

    public static func countText(_ count: Int) -> String {
        switch count {
        case 0: String(localized: "No accounts connected")
        case 1: String(localized: "1 account connected")
        default: String(localized: "\(count) accounts connected")
        }
    }

    public static func make(accounts: [Account]) -> SettingsAccountCard {
        let count = connectedCount(of: accounts)
        return SettingsAccountCard(connectedCount: count, title: countText(count), subtitle: SettingsPaneID.plan.title)
    }
}

/// The colour of the controls in the Settings panes: the switches, pop-ups and sliders. It is the chat theme's accent,
/// as in the main window, so "on" is a clear colour and "off" stays grey. A theme whose accent is nearly grey (Slate)
/// would make "on" look like "off", so then the controls take the system blue.
public enum SettingsControlTint {
    /// The fallback for a grey accent: macOS's blue, as hex.
    public static let fallbackHex = "#0A84FF"

    /// The accent to tint the Settings controls with.
    public static func hex(forThemeAccent accent: String) -> String {
        guard let (red, green, blue) = rgb(accent) else { return fallbackHex }
        let high = max(red, green, blue)
        let low = min(red, green, blue)
        let saturation = high == 0 ? 0 : (high - low) / high
        return saturation >= 0.4 ? accent : fallbackHex
    }

    private static func rgb(_ hex: String) -> (Double, Double, Double)? {
        var digits = hex.trimmingCharacters(in: .whitespaces)
        if digits.hasPrefix("#") { digits.removeFirst() }
        guard digits.count == 6, let value = UInt32(digits, radix: 16) else { return nil }
        return (Double((value >> 16) & 0xFF) / 255, Double((value >> 8) & 0xFF) / 255, Double(value & 0xFF) / 255)
    }
}
