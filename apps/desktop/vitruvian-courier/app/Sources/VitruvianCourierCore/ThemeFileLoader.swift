// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation

public struct CustomThemeStylesheet: Equatable, Sendable {
    public let path: String
    public let css: String
    public let loadedAt: Date

    public init(path: String, css: String, loadedAt: Date = Date()) {
        self.path = path
        self.css = css
        self.loadedAt = loadedAt
    }
}

public enum ThemeFileLoaderDisposition: Equatable, Sendable {
    case unavailable(reason: String)
    case loaded(CustomThemeStylesheet)
}

/// Spec §3 seam for loading custom CSS / theme files in Settings ▸ Appearance.
public protocol ThemeFileLoader: Sendable {
    var isAvailable: Bool { get }
    var unavailableReason: String { get }
    func loadThemeFile(at url: URL) -> ThemeFileLoaderDisposition
    func reload() -> ThemeFileLoaderDisposition
    func reset()
}

public struct UnavailableThemeFileLoader: ThemeFileLoader {
    public init() {}
    public var isAvailable: Bool { false }
    public var unavailableReason: String {
        String(localized: "Custom CSS and external theme files aren’t available yet in Courier. Use the built-in themes, colours, and wallpapers above.")
    }
    public func loadThemeFile(at _: URL) -> ThemeFileLoaderDisposition {
        .unavailable(reason: unavailableReason)
    }
    public func reload() -> ThemeFileLoaderDisposition {
        .unavailable(reason: unavailableReason)
    }
    public func reset() {}
}
